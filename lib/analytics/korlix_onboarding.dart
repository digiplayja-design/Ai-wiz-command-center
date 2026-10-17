import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class KorlixOnboardingContext {
  final Map<String, String> headers;
  final bool newSetup;
  const KorlixOnboardingContext(this.headers, {required this.newSetup});
}

/// First-party observations only. Never pass user text or credentials here.
/// Disabled until main() initializes it; widget tests do not send real traffic.
class KorlixOnboarding {
  static final instance = KorlixOnboarding();
  static const queueKey = 'korlix_onboarding_queue_v1';
  static const _names = {
    'app_open',
    'registration_screen_viewed',
    'registration_submit',
    'registration_validation_error',
    'registration_transport_error',
    'confirmation_screen_viewed',
    'login_screen_viewed',
  };
  static const _errors = {
    'required_fields',
    'password_length',
    'eligibility',
    'network',
    'response',
  };
  final http.Client _client;
  KorlixOnboarding({http.Client? client}) : _client = client ?? http.Client();
  Future<void>? _ready;
  Future<void> _changes = Future<void>.value();
  SharedPreferences? _prefs;
  Uri? _endpoint;
  Map<String, String> _headers = {};
  final List<Map<String, dynamic>> _queue = [];
  Timer? _retry;
  bool _sending = false;
  bool _disposed = false;

  Future<void> start({
    required String baseUrl,
    required Future<KorlixOnboardingContext> Function() context,
  }) {
    return _ready ??= _start(baseUrl, context);
  }

  Future<void> _start(
    String baseUrl,
    Future<KorlixOnboardingContext> Function() context,
  ) async {
    try {
      final info = await context();
      _endpoint = Uri.parse('$baseUrl/api/onboarding/events');
      _headers = {'Content-Type': 'application/json', ...info.headers};
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs!.getString(queueKey);
      if (saved != null) {
        try {
          final data = jsonDecode(saved);
          if (data is List) {
            final cutoff = DateTime.now()
                .subtract(const Duration(days: 7))
                .millisecondsSinceEpoch;
            for (final row in data.take(48)) {
              if (row is Map &&
                  row['queued_at'] is int &&
                  row['queued_at'] >= cutoff &&
                  _names.contains(row['name']) &&
                  row['id'] is String &&
                  RegExp(
                    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                  ).hasMatch(row['id']) &&
                  (!row.containsKey('new_setup') ||
                      (row['name'] == 'app_open' &&
                          row['new_setup'] is bool)) &&
                  (!row.containsKey('error_code') ||
                      _errors.contains(row['error_code']))) {
                _queue.add({
                  'id': row['id'],
                  'name': row['name'],
                  'queued_at': row['queued_at'],
                  if (row.containsKey('new_setup'))
                    'new_setup': row['new_setup'],
                  if (row.containsKey('error_code'))
                    'error_code': row['error_code'],
                });
              }
            }
          }
        } catch (_) {
          /* A corrupt measurement cache must never block login. */
        }
      }
      await _append('app_open', newSetup: info.newSetup);
    } catch (_) {
      /* Optional diagnostics must never block app startup. */
    }
  }

  void track(String name, {String? errorCode}) {
    if (_ready == null ||
        _disposed ||
        !_names.contains(name) ||
        name == 'app_open' ||
        (errorCode != null && !_errors.contains(errorCode))) {
      return;
    }
    unawaited(
      _ready!
          .then((_) => _append(name, errorCode: errorCode))
          .catchError((Object _) {}),
    );
  }

  String _id() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  Future<void> _change(Future<void> Function() action) {
    _changes = _changes.then((_) => action()).catchError((Object _) {});
    return _changes;
  }

  Future<void> _persist() async {
    await _prefs?.setString(queueKey, jsonEncode(_queue));
  }

  Future<void> _append(String name, {bool? newSetup, String? errorCode}) async {
    await _change(() async {
      if (_disposed || _prefs == null) return;
      // Preserve the earliest unsent first-open event when the queue is full.
      if (_queue.length >= 48) _queue.removeAt(_queue.length > 1 ? 1 : 0);
      _queue.add({
        'id': _id(),
        'name': name,
        'queued_at': DateTime.now().millisecondsSinceEpoch,
        'new_setup': ?newSetup,
        'error_code': ?errorCode,
      });
      await _persist();
    });
    unawaited(flush());
  }

  Future<void> flush() async {
    if (_sending || _disposed || _endpoint == null || _queue.isEmpty) return;
    _sending = true;
    _retry?.cancel();
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final batch = _queue
            .take(12)
            .map(
              (row) => <String, dynamic>{
                'id': row['id'],
                'name': row['name'],
                if (row.containsKey('new_setup')) 'new_setup': row['new_setup'],
                if (row.containsKey('error_code'))
                  'error_code': row['error_code'],
              },
            )
            .toList();
        final response = await _client
            .post(
              _endpoint!,
              headers: _headers,
              body: jsonEncode({'events': batch}),
            )
            .timeout(const Duration(seconds: 4));
        if (response.statusCode >= 500 ||
            response.statusCode == 429 ||
            response.statusCode == 404) {
          break;
        }
        if (response.statusCode != 202 && response.statusCode != 400) break;
        final sentIds = batch.map((row) => row['id']).toSet();
        await _change(() async {
          _queue.removeWhere((row) => sentIds.contains(row['id']));
          await _persist();
        });
      }
    } catch (_) {
      /* Keep bounded pending events for a later attempt. */
    } finally {
      _sending = false;
      if (!_disposed && _queue.isNotEmpty) {
        _retry = Timer(const Duration(minutes: 1), () => unawaited(flush()));
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _client.close();
  }
}

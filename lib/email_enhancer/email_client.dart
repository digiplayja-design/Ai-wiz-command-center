import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../chat/chat_memory_client.dart' show chatAccountStorageKey;
import '../live_convo/agent_studio_client.dart' show agentStudioKey;
import 'email_model.dart';

abstract class EmailDraftStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class EmailPreferences implements EmailDraftStore {
  @override
  Future<String?> read(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw const EmailEnhancerException(
        'This device could not save the draft. Export a copy before leaving.',
      );
    }
  }
}

class EmailEnhancerClient extends ChangeNotifier {
  EmailEnhancerClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
    EmailDraftStore? store,
  }) : _http = client ?? http.Client(),
       _owns = client == null,
       _store = store ?? EmailPreferences() {
    _scope = _identity();
    _key = 'korlix_email_drafts_v1_${chatAccountStorageKey(headersBuilder())}';
    sessionChanges?.addListener(_check);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _owns;
  final EmailDraftStore _store;
  late final String _scope, _key;
  bool _closed = false,
      _denied = false,
      busy = false,
      saving = false,
      loaded = false;
  String? _lastSaved, _lastInput, _requestKey;
  List<EmailDraft> drafts = [];
  bool get available => !_closed && !_denied;
  String _identity() {
    try {
      final token = headersBuilder().entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value
          .split(' ')
          .last;
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      final values = [j['iss'], j['sub'], j['session_id']];
      if (values.any((x) => x is! String || x.isEmpty)) return '';
      return jsonEncode(values);
    } catch (_) {
      return '';
    }
  }

  void _check() {
    if (!available) return;
    if (_scope.isEmpty || _scope != _identity()) {
      _denied = true;
      drafts = [];
      _lastInput = _requestKey = _lastSaved = null;
      notifyListeners();
    }
  }

  void guard() {
    _check();
    if (!available) {
      throw const EmailEnhancerException(
        'Your session changed. Sign in and reopen Email Enhancer.',
      );
    }
  }

  Future<void> load() async {
    guard();
    final raw = await _store.read(_key);
    guard();
    try {
      final data = raw == null ? [] : jsonDecode(raw);
      if (data is! List || data.length > 20) throw const FormatException();
      final next = data
          .map((j) => EmailDraft.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      drafts = next;
      _lastSaved = raw;
      loaded = true;
    } catch (_) {
      throw const EmailEnhancerException(
        'Saved drafts could not be read. They have not been overwritten.',
      );
    }
  }

  Future<void> save(EmailDraft draft) async {
    if (draft.brief.source.trim().isEmpty) {
      throw const EmailEnhancerException(
        'Add an email or notes before saving.',
      );
    }
    await _persist([draft, ...drafts.where((d) => d.id != draft.id)]);
  }

  Future<void> remove(String id) =>
      _persist(drafts.where((d) => d.id != id).toList());
  Future<void> _persist(List<EmailDraft> next) async {
    guard();
    if (!loaded || saving) {
      throw const EmailEnhancerException(
        'Wait for saved drafts to load before saving.',
      );
    }
    if (next.length > 20) {
      throw const EmailEnhancerException(
        'You can keep 20 drafts on this device. Remove an older draft first.',
      );
    }
    final payload = jsonEncode(next.map((d) => d.json).toList());
    if (payload.length > 1600000) {
      throw const EmailEnhancerException(
        'Draft storage is full. Export and remove an older draft first.',
      );
    }
    saving = true;
    try {
      final current = await _store.read(_key);
      guard();
      if (current != _lastSaved) {
        throw const EmailEnhancerException(
          'Another window changed your drafts. Export this email, then reopen Email Enhancer.',
        );
      }
      await _store.write(_key, payload);
      guard();
      drafts = next;
      _lastSaved = payload;
    } finally {
      saving = false;
    }
  }

  Future<EnhancedEmail> enhance(EmailBrief brief) async {
    guard();
    if (busy) {
      throw const EmailEnhancerException(
        'Wait for your current enhancement to finish.',
      );
    }
    EmailBrief.fromJson(brief.json);
    if (brief.error != null) throw EmailEnhancerException(brief.error!);
    final fingerprint = jsonEncode(brief.json);
    if (_lastInput != fingerprint) {
      _lastInput = fingerprint;
      _requestKey = agentStudioKey();
    }
    busy = true;
    try {
      final r = await _http
          .post(
            Uri.parse(
              '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/email-enhancer',
            ),
            headers: {...headersBuilder(), 'Content-Type': 'application/json'},
            body: jsonEncode({
              ...brief.json,
              'consent': true,
              'requestKey': _requestKey,
            }),
          )
          .timeout(const Duration(seconds: 200));
      guard();
      if (r.statusCode == 401) {
        _denied = true;
        drafts = [];
        notifyListeners();
        throw const EmailEnhancerException('Sign in again to continue.');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw EmailEnhancerException(
          '${j['error'] ?? 'Rici could not finish this email.'}',
        );
      }
      final result = EnhancedEmail.fromJson(
        Map<String, dynamic>.from(j['result']),
      );
      _lastInput = _requestKey = null;
      return result;
    } on TimeoutException {
      guard();
      throw const EmailEnhancerException(
        'Rici is taking longer than expected. Your original is unchanged. Retry when ready.',
      );
    } on http.ClientException {
      guard();
      throw const EmailEnhancerException(
        'Check your connection. Your original is unchanged.',
      );
    } on FormatException {
      throw const EmailEnhancerException(
        'The email response could not be read. Your original is unchanged.',
      );
    } finally {
      busy = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    sessionChanges?.removeListener(_check);
    drafts = [];
    _lastInput = _requestKey = _lastSaved = null;
    if (_owns) _http.close();
    super.dispose();
  }
}

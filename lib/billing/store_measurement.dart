import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/korlix_http.dart' as http;

/// Advertising measurement is optional and independent of the store transaction.
class StoreMeasurement extends ChangeNotifier {
  StoreMeasurement(this._client);
  final http.Client _client;
  static const _native = MethodChannel('korlix/store_measurement');
  static final _instanceId = RegExp(r'^[a-f0-9]{32}$');
  static final _checkoutId = RegExp(r'^[a-f0-9-]{36}$');
  String? _owner;
  String _store = '', _base = '';
  Map<String, String> Function()? _headers;
  bool enabled = false, working = false;
  String? feedback;
  int _version = 0;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final op = _tail.then((_) => action());
    _tail = op.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return op;
  }

  String get _prefix => 'korlix.store.measurement.$_store.$_owner.';
  bool _current(int version) => !_disposed && version == _version;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<String?> _nativeId(String method, String? owner) async {
    try {
      final value = await _native.invokeMethod<String>(method, {
        'owner': owner,
      });
      return value != null && _instanceId.hasMatch(value) ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _post(String path, Map<String, Object> fields) {
    final headers = Map<String, String>.from(_headers?.call() ?? {})
      ..['Content-Type'] = 'application/json';
    return _client
        .post(
          Uri.parse('$_base/api/billing/measurement/$path'),
          headers: headers,
          body: jsonEncode({'store': _store, ...fields}),
        )
        .timeout(const Duration(seconds: 3));
  }

  Future<void> _withdraw(SharedPreferences prefs, int version) async {
    if (!_current(version) || prefs.getBool('${_prefix}withdraw') != true)
      return;
    final prefix = _prefix;
    try {
      final response = await _post('withdraw', {});
      if (response.statusCode == 200) {
        await prefs.remove('${prefix}withdraw');
        if (_current(version)) feedback = null;
        return;
      }
    } catch (_) {}
    if (_current(version)) feedback = 'Measurement is off on this device. Reconnect to finish withdrawing pending reports.';
  }

  Future<void> selectAccount(
    String? owner,
    String store,
    String base,
    Map<String, String> Function()? headers,
  ) {
    _headers = headers;
    _base = base;
    if (_owner == owner && _store == store) return _tail;
    _owner = owner;
    _store = store;
    final version = ++_version;
    enabled = false;
    working = false;
    feedback = null;
    _notify();
    return _serialize(() async {
      if (!_current(version)) return;
      if (owner == null) {
        await _nativeId('disable', null);
        return;
      }
      await _refresh(version);
    });
  }

  Future<void> refresh() {
    final version = _version;
    return _serialize(() => _refresh(version));
  }

  Future<void> _refresh(int version) async {
    if (!_current(version) || _owner == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_current(version)) return;
      if (prefs.getBool('${_prefix}enabled') == true) {
        final id = await _nativeId('resume', _owner);
        if (!_current(version)) return;
        if (id == null) {
          await _off(prefs, version);
        } else {
          enabled = true;
        }
      } else {
        await _nativeId('disable', null);
        if (_current(version)) await _withdraw(prefs, version);
      }
    } catch (_) {}
    if (_current(version)) _notify();
  }

  Future<void> _off(SharedPreferences prefs, int version) async {
    if (!_current(version)) return;
    final prefix = _prefix;
    enabled = false;
    await _nativeId('disable', null);
    await prefs.setBool('${prefix}withdraw', true);
    await prefs.remove('${prefix}enabled');
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith('${prefix}checkout.'))
            .toList()) {
      await prefs.remove(key);
    }
    await _withdraw(prefs, version);
  }

  Future<void> choose(bool value) {
    if (working || _owner == null) return Future<void>.value();
    final version = _version;
    working = true;
    if (!value) enabled = false;
    feedback = null;
    _notify();
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!_current(version)) return;
        if (!value) {
          await _off(prefs, version);
          return;
        }
        await _withdraw(prefs, version);
        if (!_current(version) || prefs.getBool('${_prefix}withdraw') == true)
          return;
        final id = await _nativeId('enable', _owner);
        if (!_current(version)) return;
        if (id == null) {
          await _nativeId('disable', null);
          feedback = 'Measurement is unavailable or permission is off. You can still subscribe.';
          return;
        }
        await prefs.setBool('${_prefix}enabled', true);
        if (_current(version)) enabled = true;
      } catch (_) {
        if (_current(version)) {
          await _nativeId('disable', null);
          if (_current(version))
            feedback =
                'Your choice could not be saved. You can still subscribe.';
        }
      } finally {
        if (_current(version)) {
          working = false;
          _notify();
        }
      }
    });
  }

  Future<void> begin(String sku) async {
    if (!enabled || working || _owner == null) return;
    final version = _version, prefix = _prefix;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${prefix}checkout.$sku');
      if (!_current(version) || !enabled) return;
      final instance = await _nativeId(
        'resume',
        _owner,
      ).timeout(const Duration(seconds: 2));
      if (!_current(version) || !enabled) return;
      if (instance == null) {
        await choose(false);
        return;
      }
      final response = await _post('checkout', {
        'sku': sku,
        'consent': true,
        'instanceId': instance,
      });
      if (!_current(version) || !enabled || response.statusCode != 200) return;
      final id = jsonDecode(response.body)['checkoutId'];
      if (id is String && _checkoutId.hasMatch(id))
        await prefs.setString('${prefix}checkout.$sku', id);
    } catch (_) {
      /* Measurement availability must never gate the store sheet. */
    }
  }

  Future<String?> checkoutFor(String sku) async {
    if (!enabled || working || _owner == null) return null;
    final version = _version, prefix = _prefix;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _current(version) && enabled
          ? prefs.getString('${prefix}checkout.$sku')
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> bound(String sku, String checkout) async {
    final key = '${_prefix}checkout.$sku';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(key) == checkout) await prefs.remove(key);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    super.dispose();
  }
}

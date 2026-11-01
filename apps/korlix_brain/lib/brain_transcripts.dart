import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BrainTranscriptException implements Exception {
  const BrainTranscriptException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Local account partitioning only. Server authorization still verifies the JWT.
/// Never key a saved transcript by email, session ID, or a bearer token.
String brainTranscriptOwner(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException();
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final issuer = claims['iss'], subject = claims['sub'];
    if (issuer is! String ||
        subject is! String ||
        issuer.isEmpty ||
        subject.isEmpty ||
        issuer.length > 500 ||
        subject.length > 200) {
      throw const FormatException();
    }
    return base64Url.encode(utf8.encode(jsonEncode([issuer, subject])));
  } catch (_) {
    throw const BrainTranscriptException(
      'Sign in again to access saved messages.',
    );
  }
}

abstract interface class BrainTranscriptStorage {
  Future<String?> read(String owner);
  Future<void> write(String owner, String value);
  Future<void> delete(String owner);
}

class NativeBrainTranscriptStorage implements BrainTranscriptStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  String _key(String owner) => 'korlix_brain_saved_messages_v1_$owner';
  @override
  Future<String?> read(String owner) => _storage.read(key: _key(owner));
  @override
  Future<void> write(String owner, String value) =>
      _storage.write(key: _key(owner), value: value);
  @override
  Future<void> delete(String owner) => _storage.delete(key: _key(owner));
}

class BrainTranscript {
  const BrainTranscript({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });
  final String id, role, text, createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    'createdAt': createdAt,
  };
  factory BrainTranscript.fromJson(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id'] as String) ||
        !['you', 'rici'].contains(value['role']) ||
        value['text'] is! String ||
        (value['text'] as String).isEmpty ||
        (value['text'] as String).length > 20000 ||
        value['createdAt'] is! String ||
        DateTime.tryParse(value['createdAt'] as String) == null) {
      throw const FormatException('Invalid saved transcript');
    }
    return BrainTranscript(
      id: value['id'] as String,
      role: value['role'] as String,
      text: value['text'] as String,
      createdAt: value['createdAt'] as String,
    );
  }
  String get shareText =>
      'KORLIX Brain+Voice\n${role == 'you' ? 'You' : 'Rici'} · $createdAt\n\n$text';
}

/// Only explicit Save persists content. A single account-scoped secure entry
/// commits the archive atomically; failed writes leave the visible state intact.
class BrainTranscripts {
  BrainTranscripts({
    required this.owner,
    required this.isCurrent,
    BrainTranscriptStorage? storage,
  }) : _storage = storage ?? NativeBrainTranscriptStorage();
  final String owner;
  final bool Function() isCurrent;
  final BrainTranscriptStorage _storage;
  final _live = <String, BrainTranscript>{};
  Map<String, BrainTranscript>? _saved;
  Future<void> _pending = Future<void>.value();
  static const maxSaved = 100;
  static const maxBytes = 512 * 1024;

  void _check() {
    if (!isCurrent()) {
      throw const BrainTranscriptException(
        'Your account changed. Sign in again to continue.',
      );
    }
  }

  BrainTranscript? receive(String role, String text) {
    _check();
    if (!['you', 'rici'].contains(role) || text.isEmpty || text.length > 20000) {
      return null;
    }
    final random = Random.secure();
    final item = BrainTranscript(
      id: List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      role: role,
      text: text,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    _live[item.id] = item;
    while (_live.length > 60) {
      _live.remove(_live.keys.first);
    }
    return item;
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) async {
      _check();
      try {
        final value = await action();
        _check();
        return value;
      } on BrainTranscriptException {
        rethrow;
      } catch (_) {
        throw const BrainTranscriptException(
          'Could not access saved messages securely. Unlock this device and try again.',
        );
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, BrainTranscript>> _load() async {
    if (_saved != null) return _saved!;
    final raw = await _storage.read(owner);
    _check();
    if (raw == null) return _saved = {};
    if (utf8.encode(raw).length > maxBytes) throw const FormatException();
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['messages'] is! List ||
        (data['messages'] as List).length > maxSaved) {
      throw const FormatException();
    }
    final items = (data['messages'] as List)
        .map(BrainTranscript.fromJson)
        .toList();
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException();
    }
    return _saved = {for (final item in items) item.id: item};
  }

  Future<List<Map<String, dynamic>>> listSaved() => _serial(
    () async => (await _load()).values
        .toList()
        .reversed
        .map((item) => item.toJson())
        .toList(),
  );
  Future<BrainTranscript> get(String id) =>
      _serial(() async => _find(id, await _load()));
  BrainTranscript _find(String id, Map<String, BrainTranscript> saved) =>
      _live[id] ??
      saved[id] ??
      (throw const BrainTranscriptException(
        'This transcript message is no longer available.',
      ));

  Future<void> _commit(Map<String, BrainTranscript> items) async {
    final encoded = jsonEncode({
      'version': 1,
      'messages': items.values.map((item) => item.toJson()).toList(),
    });
    if (items.length > maxSaved || utf8.encode(encoded).length > maxBytes) {
      throw const BrainTranscriptException(
        'Saved messages are full. Share or delete older messages, then save again.',
      );
    }
    _check();
    await _storage.write(owner, encoded);
    _check();
    _saved = items;
  }

  Future<Map<String, dynamic>> save(String id) => _serial(() async {
    final saved = await _load();
    final item = _find(id, saved);
    if (!saved.containsKey(id)) await _commit({...saved, id: item});
    return item.toJson();
  });

  Future<void> delete(String id) => _serial(() async {
    final saved = await _load();
    if (saved.containsKey(id)) await _commit({...saved}..remove(id));
    _live.remove(id);
  });

  Future<void> clear() => _serial(() async {
    await _storage.delete(owner);
    _check();
    _saved = {};
    _live.clear();
  });
}

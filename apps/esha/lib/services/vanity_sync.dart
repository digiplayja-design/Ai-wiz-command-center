import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'korlix_api.dart';

enum SyncState { local, loading, saved, saving, conflict, uncertain, offline }

/// Owns one account collection at a time. Account changes invalidate all old
/// async work. A missed mutation response is reconciled by reading before retry.
class VanitySync extends ChangeNotifier {
  VanitySync({required this.gateway, required this.storage});
  final VanityGateway gateway;
  final StringStore storage;
  Vanity value = Vanity();
  SyncState status = SyncState.loading;
  String? message;
  String? _userId;
  int _epoch = 0, _version = 0, _revision = 0;
  bool _dirty = false, _disposed = false;
  Vanity? _attempted;
  Future<void>? _saving;
  Future<void> _localWrites = Future.value();
  String? get userId => _userId;
  int get confirmedVersion => _version;
  bool get canEdit => status != SyncState.loading;
  bool get dirty => _dirty;
  String _key(String? userId) => userId == null
      ? 'esha.vanity.guest.v2'
      : 'esha.vanity.account.$userId.v2';
  bool _current(int epoch, String? userId) =>
      !_disposed && _epoch == epoch && _userId == userId;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> attach(String? userId) async {
    final epoch = ++_epoch;
    _userId = userId;
    value = Vanity();
    _version = 0;
    _revision = 0;
    _dirty = false;
    _attempted = null;
    _saving = null;
    status = SyncState.loading;
    message = null;
    _notify();
    Json draft = {};
    try {
      final stored = await storage.read(_key(userId));
      if (stored != null) draft = object(jsonDecode(stored));
    } catch (_) {
      /* A damaged local draft never replaces a cloud collection. */
    }
    if (!_current(epoch, userId)) return;
    if (userId == null) {
      try {
        if (draft.isNotEmpty) {
          value = Vanity.fromJson(object(draft['state'] ?? draft));
        }
      } catch (_) {
        message = 'The previous guest collection could not be read.';
      }
      status = SyncState.local;
      _notify();
      return;
    }
    try {
      final record = await gateway.loadVanity();
      if (!_current(epoch, userId)) return;
      _version = record.version;
      value = record.state ?? Vanity();
      if (draft['dirty'] == true && draft['state'] is Map) {
        final local = Vanity.fromJson(object(draft['state']));
        if (record.state?.sameAs(local) == true) {
          value = local;
        } else if (draft['version'] == record.version) {
          value = local;
          _dirty = true;
        } else {
          value = local;
          _dirty = true;
          status = SyncState.conflict;
          message = 'A newer account collection is available. Your local draft is retained. Review and load the account version to continue syncing.';
          _notify();
          return;
        }
      }
      status = SyncState.saved;
      await _persist();
      if (!_current(epoch, userId)) return;
      _notify();
      if (_dirty) unawaited(_drain());
    } catch (error) {
      if (!_current(epoch, userId)) return;
      // Only this same account's local draft is ever available while offline.
      try {
        if (draft['state'] is Map) {
          value = Vanity.fromJson(object(draft['state']));
        }
      } catch (_) {}
      _version = draft['version'] is int ? draft['version'] as int : 0;
      _dirty = draft['dirty'] == true;
      status = SyncState.offline;
      message = 'Your account collection could not be loaded. Local changes stay on this device until a safe retry.';
      _notify();
    }
  }

  void update(Vanity next) {
    if (!canEdit) return;
    Vanity.fromJson(
      next.toJson(),
    ); // Enforce schema and byte limits at the boundary.
    value = next;
    _revision++;
    _dirty = true;
    unawaited(
      _persist().catchError((Object _) {
        message = 'Local storage could not save this change. Keep the app open and retry sync.';
        _notify();
      }),
    );
    if (_userId == null) {
      status = SyncState.local;
      _dirty = false;
    }
    _notify();
    if (_userId != null &&
        ![
          SyncState.conflict,
          SyncState.uncertain,
          SyncState.offline,
        ].contains(status)) {
      unawaited(_drain());
    }
  }

  Future<void> _persist() {
    final key = _key(_userId);
    final payload = jsonEncode({
      'state': value.toJson(),
      'version': _version,
      'dirty': _dirty,
    });
    final operation = _localWrites
        .catchError((Object _) {})
        .then((_) => storage.write(key, payload));
    _localWrites = operation;
    return operation;
  }

  Future<void> _drain() async {
    if (_saving != null) return _saving;
    final epoch = _epoch, user = _userId;
    if (user == null) return;
    final operation = () async {
      while (_current(epoch, user) &&
          _dirty &&
          ![
            SyncState.conflict,
            SyncState.uncertain,
            SyncState.offline,
          ].contains(status)) {
        final snapshot = value,
            revision = _revision,
            expectedVersion = _version;
        _attempted = snapshot;
        status = SyncState.saving;
        message = null;
        _notify();
        try {
          final confirmed = await gateway.saveVanity(snapshot, expectedVersion);
          if (!_current(epoch, user)) return;
          _version = confirmed.version;
          _attempted = null;
          if (_revision == revision) _dirty = false;
          status = SyncState.saved;
          await _persist();
          if (!_current(epoch, user)) return;
        } catch (error) {
          if (!_current(epoch, user)) return;
          final e = error is EshaException
              ? error
              : const EshaException(
                  'SYNC_UNCERTAIN',
                  'The save could not be confirmed. Your local draft is retained.',
                );
          status = e.code == 'CONFLICT'
              ? SyncState.conflict
              : e.code == 'SYNC_UNCERTAIN' || e.code == 'NETWORK_ERROR'
              ? SyncState.uncertain
              : SyncState.offline;
          message = e.message;
          try {
            await _persist();
          } catch (_) {}
          _notify();
          return;
        }
        _notify();
      }
    }();
    _saving = operation;
    try {
      await operation;
    } finally {
      if (identical(_saving, operation)) _saving = null;
    }
  }

  Future<void> retry() async {
    if (_userId == null) {
      await _persist();
      return;
    }
    final epoch = _epoch, user = _userId;
    if (_saving != null) await _saving;
    if (!_current(epoch, user)) return;
    try {
      final record = await gateway.loadVanity();
      if (!_current(epoch, user)) return;
      if (record.state?.sameAs(value) == true) {
        _version = record.version;
        _dirty = false;
        _attempted = null;
      } else if (_attempted != null &&
          record.state?.sameAs(_attempted!) == true) {
        _version = record.version;
        _attempted = null;
      } else if (record.version != _version && _dirty) {
        status = SyncState.conflict;
        message = 'Your account collection changed. Your local draft is retained; load the account version to resolve this conflict.';
        _notify();
        return;
      } else if (!_dirty) {
        value = record.state ?? Vanity();
        _version = record.version;
      }
      status = SyncState.saved;
      message = null;
      await _persist();
      if (!_current(epoch, user)) return;
      _notify();
      await _drain();
    } catch (error) {
      if (!_current(epoch, user)) return;
      status = SyncState.offline;
      message = 'Sync could not be confirmed. Your local draft is retained.';
      _notify();
    }
  }

  /// Call only after the user explicitly chooses the remote account version.
  Future<void> loadAccountVersion() async {
    if (_userId == null) return;
    final epoch = _epoch, user = _userId;
    if (_saving != null) await _saving;
    if (!_current(epoch, user)) return;
    status = SyncState.loading;
    _notify();
    try {
      final record = await gateway.loadVanity();
      if (!_current(epoch, user)) return;
      value = record.state ?? Vanity();
      _version = record.version;
      _revision++;
      _dirty = false;
      _attempted = null;
      status = SyncState.saved;
      message = null;
      await _persist();
    } catch (_) {
      if (!_current(epoch, user)) return;
      status = SyncState.offline;
      message = 'The account version could not be loaded. Your local draft is retained.';
    }
    if (_current(epoch, user)) _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}

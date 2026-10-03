import 'dart:async';

import 'package:flutter/foundation.dart';

import '../live_convo/agent_studio_client.dart' show agentAccountScope;
import 'social_client.dart';

class SocialUnreadConversation {
  const SocialUnreadConversation({
    required this.card,
    required this.group,
    required this.unread,
  });
  final SocialMap card;
  final bool group;
  final int unread;
  String get key => '${group ? 'group' : 'peer'}:${card['id']}';
  String get name => '${card['name'] ?? (group ? 'Group chat' : 'Message')}';
}

/// Reads the existing server counts. Opening this inbox never marks chat read.
/// All state is in memory and is discarded on sign-out or session replacement.
class SocialNotifications extends ChangeNotifier {
  SocialNotifications({
    required this.baseUrl,
    required this.headersBuilder,
    required this.sessionChanges,
    required this.shouldPoll,
    this.clientBuilder,
    this.enableCalls = false,
    Duration interval = const Duration(seconds: 5),
  }) {
    sessionChanges.addListener(_sessionChanged);
    _syncAccount();
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    if (enableCalls) {
      _callTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refreshCalls()),
      );
    }
  }

  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable sessionChanges;
  final bool Function() shouldPoll;
  final SocialClient Function()? clientBuilder;
  final bool enableCalls;
  SocialClient? _client;
  SocialClient? get client => available ? _client : null;
  Timer? _timer, _callTimer, _callExpiry;
  Future<void>? _pending, _pendingCalls;
  String _scope = '';
  int _generation = 0;
  int _callGeneration = 0;
  bool _closed = false, _foreground = true;
  bool _hasMessageBaseline = false, _callOpen = false;
  bool get callOpen => _callOpen;
  SocialUnreadConversation? _messageAlert;
  SocialUnreadConversation? get messageAlert => _messageAlert;
  String? _activeConversationKey;
  String? get activeConversationKey => _activeConversationKey;
  int _messageRevision = 0;
  int get messageRevision => _messageRevision;
  SocialMap? _incomingCall;
  SocialMap? get incomingCall => _incomingCall;
  String? _lastCallId;
  String? _callExpiryId;
  int _callRevision = 0;
  int get callRevision => _callRevision;
  List<SocialUnreadConversation> _conversations = const [];
  List<SocialUnreadConversation> get conversations => _conversations;
  int get totalUnread =>
      _conversations.fold(0, (total, item) => total + item.unread);
  bool _partial = false;
  String get countLabel => '$totalUnread${_partial ? '+' : ''}';
  bool get available => !_closed && (_client?.available ?? false);

  void _sessionChanged() {
    _syncAccount(replaceDenied: true);
    unawaited(refresh());
    unawaited(refreshCalls());
  }

  void _syncAccount({bool replaceDenied = false}) {
    if (_closed) return;
    final scope = agentAccountScope(headersBuilder());
    if (scope == _scope && !(replaceDenied && _client?.available == false)) {
      return;
    }
    _invalidateLoads();
    _client?.removeListener(_accessChanged);
    // Shared call controllers must stop capture before disposal removes their
    // access-change listeners.
    _client?.invalidateSession();
    _client?.dispose();
    _scope = scope;
    _client = scope.isEmpty
        ? null
        : (clientBuilder?.call() ??
              SocialClient(
                baseUrl: baseUrl,
                headersBuilder: headersBuilder,
                sessionChanges: sessionChanges,
              ));
    _client?.addListener(_accessChanged);
    _clear();
  }

  void _accessChanged() {
    if (!available) {
      _invalidateLoads();
      _clear();
    }
  }

  void _clear() {
    _conversations = const [];
    _partial = false;
    _hasMessageBaseline = false;
    _messageAlert = null;
    _activeConversationKey = null;
    _incomingCall = null;
    _lastCallId = null;
    _callOpen = false;
    _callExpiry?.cancel();
    _callExpiryId = null;
    if (!_closed) notifyListeners();
  }

  void _invalidateLoads() {
    _generation++;
    _callGeneration++;
    _pending = null;
    _pendingCalls = null;
  }

  void _hideAlerts() {
    _invalidateLoads();
    final changed = _messageAlert != null || _incomingCall != null;
    _messageAlert = null;
    _incomingCall = null;
    _callExpiry?.cancel();
    _callExpiryId = null;
    if (changed && !_closed) notifyListeners();
  }

  void dismissMessage() {
    if (_closed || _messageAlert == null) return;
    _messageAlert = null;
    notifyListeners();
  }

  void setActiveConversation(String? key) {
    if (_closed || key == _activeConversationKey) return;
    _activeConversationKey = key;
    if (key != null && _messageAlert?.key == key) _messageAlert = null;
    notifyListeners();
  }

  /// Reserves the one app-wide call route. Opening a route never answers a call
  /// or asks for microphone/camera access; those remain explicit screen actions.
  bool beginCall() {
    if (_closed) return false;
    _syncAccount();
    if (!available || _callOpen) return false;
    _callOpen = true;
    _callGeneration++;
    _pendingCalls = null;
    _incomingCall = null;
    _callExpiry?.cancel();
    _callExpiryId = null;
    notifyListeners();
    return true;
  }

  void endCall() {
    if (_closed || !_callOpen) return;
    _callOpen = false;
    notifyListeners();
    unawaited(refreshCalls());
  }

  void setForeground(bool active) {
    if (_closed) return;
    _foreground = active;
    if (!active) {
      // Keep confirmed badge counts and the baseline. Messages received while
      // away can alert on resume; a previously dismissed count will not repeat.
      _hideAlerts();
    } else {
      unawaited(refresh());
      unawaited(refreshCalls());
    }
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    _syncAccount();
    if (!_foreground || !shouldPoll()) {
      _hideAlerts();
      return Future.value();
    }
    if (!available) return Future.value();
    return _pending ??= _load(_client!, _generation);
  }

  bool _current(SocialClient client, int generation) =>
      !_closed &&
      _foreground &&
      shouldPoll() &&
      generation == _generation &&
      identical(client, _client) &&
      client.available;

  Future<void> _load(SocialClient client, int generation) async {
    try {
      final found = <String, SocialUnreadConversation>{};
      var partial = false;
      // The API returns 40 rows plus a look-ahead row; never count that row
      // twice. Traverse both lists, including users beyond the first page.
      for (final group in [false, true]) {
        for (var offset = 0; offset <= 50000; offset += 40) {
          final response = await client.get(group ? 'groups' : 'connections', {
            'offset': offset,
            if (!group) 'state': 'accepted',
          });
          if (!_current(client, generation)) return;
          final rows = socialItems(response['items']);
          for (final card in rows.take(40)) {
            final accepted = card[group ? 'state' : 'connection'] == 'accepted';
            final unread = int.tryParse('${card['unread']}') ?? 0;
            if (!accepted || unread <= 0 || card['id'] == null) continue;
            final item = SocialUnreadConversation(
              card: Map.unmodifiable(card),
              group: group,
              unread: unread,
            );
            found[item.key] = item;
          }
          if (rows.length <= 40) break;
          // The existing API clamps offsets to 50,000. At that limit label
          // the count as a lower bound instead of looping over the last page.
          if (offset == 50000) partial = true;
        }
      }
      if (!_current(client, generation)) return;
      final previous = {
        for (final item in _conversations) item.key: item.unread,
      };
      SocialUnreadConversation? newest;
      if (_hasMessageBaseline) {
        for (final item in found.values) {
          if (item.key != _activeConversationKey &&
              item.unread > (previous[item.key] ?? 0)) {
            newest = item;
          }
        }
      }
      _hasMessageBaseline = true;
      if (newest != null) {
        _messageAlert = newest;
        _messageRevision++;
      } else if (_messageAlert != null) {
        // Keep an existing popup current, and remove it once its chat is read
        // or is no longer an accepted conversation.
        _messageAlert = found[_messageAlert!.key];
      }
      _conversations = List.unmodifiable(found.values);
      _partial = partial;
      notifyListeners();
    } on SocialException catch (error) {
      if (_current(client, generation) &&
          [401, 403, 404].contains(error.status)) {
        _invalidateLoads();
        _clear();
      }
      // Keep the last confirmed counts during temporary network failures.
    } catch (_) {
      // A notification outage must not interrupt the main KORLIX screen.
    } finally {
      if (!_closed && generation == _generation) _pending = null;
    }
  }

  Future<void> refreshCalls() {
    if (_closed || !enableCalls) return Future.value();
    _syncAccount();
    if (!_foreground || !shouldPoll()) {
      _hideAlerts();
      return Future.value();
    }
    if (!available || _callOpen) return Future.value();
    return _pendingCalls ??= _loadCalls(_client!, _generation, _callGeneration);
  }

  bool _currentCall(SocialClient client, int generation, int callGeneration) =>
      _current(client, generation) &&
      !_callOpen &&
      callGeneration == _callGeneration;

  Future<void> _loadCalls(
    SocialClient client,
    int generation,
    int callGeneration,
  ) async {
    try {
      final response = await client.get('call_inbox', {
        'device': client.callDevice,
      });
      if (!_currentCall(client, generation, callGeneration)) return;
      final call = socialMap(response['call']);
      final id = call['id']?.toString();
      final created = DateTime.tryParse('${call['created_at']}');
      final valid =
          id != null &&
          id.isNotEmpty &&
          call['state'] == 'ringing' &&
          created != null;
      if (!valid) {
        _callExpiry?.cancel();
        _callExpiryId = null;
        if (_incomingCall != null) {
          _incomingCall = null;
          notifyListeners();
        }
        return;
      }
      final firstSeen = _callExpiryId != id;
      // Once a local deadline elapses, repeated responses must not revive or
      // extend that invitation. A background/resume cycle can check it anew.
      if (!firstSeen && _callExpiry?.isActive != true) return;
      _incomingCall = Map.unmodifiable(call);
      if (_lastCallId != id) {
        _lastCallId = id;
        _callRevision++;
      }
      if (firstSeen) {
        _callExpiry?.cancel();
        _callExpiryId = id;
        // The server inbox authoritatively filters expired calls. A skewed
        // device clock must not reject a valid invitation. Bound its lifetime
        // from first sight without resetting this timer on successful polls.
        _callExpiry = Timer(const Duration(seconds: 45), () {
          if (_currentCall(client, generation, callGeneration) &&
              _incomingCall?['id'] == id) {
            _incomingCall = null;
            notifyListeners();
          }
        });
      }
      notifyListeners();
    } on SocialException catch (error) {
      if (_currentCall(client, generation, callGeneration) &&
          [401, 403, 404].contains(error.status)) {
        _invalidateLoads();
        _clear();
      }
      // A temporary outage keeps the current alert only until its local expiry.
    } catch (_) {
      // Calls never interrupt another tool when their inbox is unavailable.
    } finally {
      if (!_closed &&
          generation == _generation &&
          callGeneration == _callGeneration) {
        _pendingCalls = null;
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    _callTimer?.cancel();
    _callExpiry?.cancel();
    sessionChanges.removeListener(_sessionChanged);
    _client?.removeListener(_accessChanged);
    _client?.invalidateSession();
    _client?.dispose();
    _conversations = const [];
    _messageAlert = null;
    _incomingCall = null;
    super.dispose();
  }
}

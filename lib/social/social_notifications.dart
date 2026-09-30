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
    Duration interval = const Duration(seconds: 5),
  }) {
    sessionChanges.addListener(_sessionChanged);
    _syncAccount();
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable sessionChanges;
  final bool Function() shouldPoll;
  final SocialClient Function()? clientBuilder;
  SocialClient? _client;
  Timer? _timer;
  Future<void>? _pending;
  String _scope = '';
  int _generation = 0;
  bool _closed = false, _foreground = true;
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
  }

  void _syncAccount({bool replaceDenied = false}) {
    if (_closed) return;
    final scope = agentAccountScope(headersBuilder());
    if (scope == _scope && !(replaceDenied && _client?.available == false)) {
      return;
    }
    _generation++;
    _pending = null;
    _client?.removeListener(_accessChanged);
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
    if (!available) _clear();
  }

  void _clear() {
    _conversations = const [];
    _partial = false;
    if (!_closed) notifyListeners();
  }

  void setForeground(bool active) {
    _foreground = active;
    if (active) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    _syncAccount();
    if (!_foreground || !shouldPoll() || !available) return Future.value();
    return _pending ??= _load(_client!, _generation);
  }

  bool _current(SocialClient client, int generation) =>
      !_closed && generation == _generation && client.available;

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
      _conversations = List.unmodifiable(found.values);
      _partial = partial;
      notifyListeners();
    } on SocialException catch (error) {
      if (_current(client, generation) &&
          [401, 403, 404].contains(error.status)) {
        _clear();
      }
      // Keep the last confirmed counts during temporary network failures.
    } catch (_) {
      // A notification outage must not interrupt the main KORLIX screen.
    } finally {
      if (!_closed && generation == _generation) _pending = null;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    sessionChanges.removeListener(_sessionChanged);
    _client?.removeListener(_accessChanged);
    _client?.dispose();
    _conversations = const [];
    super.dispose();
  }
}

import 'social_appearance.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

String socialCallHistoryLabel(SocialMap call) {
  final incoming = call['incoming'] == true || call['direction'] == 'incoming';
  final state = call['state'];
  return state == 'missed'
      ? incoming
            ? socialCallCount(call['missed_count']) > 1
                  ? '${socialCallCount(call['missed_count'])} missed calls'
                  : 'Missed call'
            : 'No answer'
      : state == 'declined'
      ? 'Declined'
      : state == 'accepted'
      ? 'In progress'
      : state == 'ringing'
      ? 'Ringing'
      : incoming
      ? 'Incoming call'
      : 'Outgoing call';
}

/// Keep one card per missed caller, ordered by their most recent attempt.
/// Server totals cover all 30 days, including attempts on later history pages.
List<SocialMap> socialCallHistoryGroups(List<SocialMap> items) {
  final result = <SocialMap>[], groups = <String, SocialMap>{};
  final loaded = <String, int>{}, seen = <String>{};
  for (final item in items) {
    final id = item['id']?.toString();
    if (id != null && !seen.add(id)) continue;
    final peerId = socialMap(item['peer'])['id']?.toString();
    if (item['state'] != 'missed' ||
        item['incoming'] != true ||
        peerId == null) {
      result.add(item);
      continue;
    }
    loaded[peerId] = (loaded[peerId] ?? 0) + 1;
    final group = groups.putIfAbsent(peerId, () {
      final copy = Map<String, dynamic>.from(item);
      result.add(copy);
      return copy;
    });
    final serverCount = socialCallCount(item['peer_missed_count']);
    final previous = socialCallCount(group['missed_count']);
    group['missed_count'] = [
      serverCount,
      previous,
      loaded[peerId]!,
    ].reduce((a, b) => a > b ? a : b);
  }
  return result;
}

class SocialCallHistory extends StatefulWidget {
  const SocialCallHistory({
    super.key,
    required this.client,
    required this.onCall,
  });
  final SocialClient client;
  final Future<void> Function(SocialMap peer, bool video) onCall;
  @override
  State<SocialCallHistory> createState() => _SocialCallHistoryState();
}

class _SocialCallHistoryState extends State<SocialCallHistory> {
  final List<SocialMap> _items = [];
  bool _loading = false, _more = false;
  int _missedTotal = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!widget.client.available && mounted) {
      setState(() {
        _items.clear();
        _more = false;
        _missedTotal = 0;
        _error = 'Sign in again to view call history.';
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || !widget.client.available) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get('call_history', {
        'device': widget.client.callDevice,
        'offset': more ? _items.length : 0,
      });
      if (!mounted || !widget.client.available) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(socialItems(response['items']));
        _more = response['has_more'] == true;
        _missedTotal = socialCallCount(response['missed_total']);
      });
      final through = response['missed_as_of'];
      if (!more && through is String) {
        // Acknowledge only the snapshot the recipient actually opened. Calls
        // ending after this snapshot remain new, even while this POST is pending.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            !widget.client.available ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        await widget.client.post('call_history_read', {
          'device': widget.client.callDevice,
          'through': through,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return SocialScaffold(
      appBar: AppBar(
        title: const Text('Call history'),
        actions: [
          IconButton(
            tooltip: 'Refresh call history',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Your recent calls',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Last 30 days. Missed calls are grouped by caller.',
                  style: TextStyle(color: skin.mutedText),
                ),
                const SizedBox(height: 20),
                if (_missedTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '$_missedTotal missed ${_missedTotal == 1 ? 'call' : 'calls'} in the last 30 days',
                      style: TextStyle(
                        color: skin.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: TextStyle(color: skin.danger)),
                  ),
                if (!_loading && _items.isEmpty && _error == null)
                  const SocialPanel(
                    child: Text('No calls yet. Your calls will appear here.'),
                  ),
                for (final item in socialCallHistoryGroups(_items))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Builder(
                      builder: (context) {
                        final peer = socialMap(item['peer']);
                        final time = DateTime.tryParse(
                          '${item['created_at'] ?? ''}',
                        )?.toLocal();
                        return SocialPanel(
                          accent: item['state'] == 'missed'
                              ? skin.danger
                              : skin.primary,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SocialAvatar(member: peer, size: 42),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${peer['name'] ?? 'Unavailable member'}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${socialCallHistoryLabel(item)} · ${socialCallCount(item['missed_count']) > 1 ? 'Latest: ' : ''}${item['mode'] == 'video' ? 'Video' : 'Audio'}',
                                style: TextStyle(
                                  color: item['state'] == 'missed'
                                      ? skin.danger
                                      : skin.mutedText,
                                ),
                              ),
                              if (time != null)
                                Text(
                                  '${MaterialLocalizations.of(context).formatMediumDate(time)} · ${TimeOfDay.fromDateTime(time).format(context)}',
                                  style: TextStyle(color: skin.mutedText),
                                ),
                              if (peer['id'] != null &&
                                  item['can_call'] == true)
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          widget.onCall(peer, false),
                                      icon: const Icon(Icons.call_rounded),
                                      label: const Text('Audio call'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          widget.onCall(peer, true),
                                      icon: const Icon(Icons.videocam_rounded),
                                      label: const Text('Video call'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (_more)
                  TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: const Text('Load earlier calls'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

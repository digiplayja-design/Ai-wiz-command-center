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
            ? 'Missed call'
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
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Scaffold(
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
                  'Missed, incoming and outgoing calls. Tap a call button to start a new call.',
                  style: TextStyle(color: skin.mutedText),
                ),
                const SizedBox(height: 20),
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
                for (final item in _items)
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
                                '${socialCallHistoryLabel(item)} · ${item['mode'] == 'video' ? 'Video' : 'Audio'}',
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

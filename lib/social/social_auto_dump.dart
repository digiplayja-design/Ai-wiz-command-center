import 'dart:async';

import 'package:flutter/material.dart';

import 'social_client.dart';

const socialAutoDumpDelays = <int, String>{
  15: '15 seconds',
  45: '45 seconds',
  60: '1 minute',
  900: '15 minutes',
  3600: '1 hour',
  86400: '1 day',
};

/// Deadlines are anchored to the server and elapsed time, not device time.
class SocialAutoDump extends ChangeNotifier {
  SocialAutoDump({DateTime Function()? now}) : _testNow = now;
  final DateTime Function()? _testNow;
  final _elapsed = Stopwatch();
  DateTime? _serverAnchor, _testAnchor;
  DateTime? _lastServerTime;
  final deadlines = <String, DateTime>{};
  final dumped = <String>{};
  final _confirmedDumped = <String>{};
  Timer? _ticker;
  bool _closed = false;
  DateTime get now {
    final anchor = _serverAnchor;
    if (anchor == null) return (_testNow ?? DateTime.now)().toUtc();
    return anchor.add(
      _testNow == null ? _elapsed.elapsed : _testNow().difference(_testAnchor!),
    );
  }

  bool _anchor(dynamic value) {
    final server = DateTime.tryParse('$value');
    if (server == null) return true;
    if (_lastServerTime != null && server.isBefore(_lastServerTime!)) {
      return false;
    }
    _lastServerTime = server;
    _serverAnchor = server.toUtc();
    _testAnchor = _testNow?.call();
    _elapsed
      ..reset()
      ..start();
    return true;
  }

  void observe(SocialMap response, Iterable<SocialMap> messages) {
    if (_closed) return;
    if (!_anchor(response['server_time'])) return;
    final hidden = response['dumped_ids'];
    if (hidden is List) _confirmedDumped.addAll(hidden.whereType<String>());
    final snapshot = response['dump_schedules'];
    if (snapshot is Map) {
      deadlines.clear();
      for (final entry in snapshot.entries) {
        final deadline = DateTime.tryParse('${entry.value}');
        if (entry.key is String && deadline != null) {
          deadlines[entry.key as String] = deadline.toUtc();
        }
      }
      // A second device may have cancelled while this device was offline.
      // Only server-confirmed removals are permanent; refresh restores any
      // locally expired message that the authoritative server still permits.
      dumped
        ..clear()
        ..addAll(_confirmedDumped);
    } else {
      dumped.addAll(_confirmedDumped);
    }
    for (final message in messages) {
      if (snapshot is! Map) _observeMessage(message);
      final reply = socialMap(message['reply']);
      if (snapshot is! Map && reply.isNotEmpty) _observeMessage(reply);
    }
    _tick();
    _startTicker();
  }

  void _observeMessage(SocialMap message) {
    final id = message['id'];
    if (id is! String) return;
    // Older APIs do not provide this field. Absence is not a cancellation.
    if (!message.containsKey('dump_at')) return;
    final due = DateTime.tryParse('${message['dump_at']}');
    if (due == null) {
      deadlines.remove(id);
    } else {
      deadlines[id] = due.toUtc();
    }
  }

  void confirm(String id, SocialMap response) {
    if (_closed) return;
    if (!_anchor(response['server_time'])) return;
    if (response['dumped'] == true) {
      _confirmedDumped.add(id);
      dumped.add(id);
    } else if (!_confirmedDumped.contains(id)) {
      dumped.remove(id);
    }
    _observeMessage({...response, 'id': id});
    _tick();
    _startTicker();
  }

  void _startTicker() {
    if (deadlines.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_closed) return;
    for (final entry in deadlines.entries) {
      if (!entry.value.isAfter(now)) dumped.add(entry.key);
    }
    notifyListeners();
  }

  bool hidden(String id) => dumped.contains(id);
  Duration? remaining(String id) => deadlines[id]?.difference(now);
  String countdown(String id) {
    final seconds = ((remaining(id)?.inMilliseconds ?? 0) / 1000).ceil();
    if (seconds <= 0) return 'Dumped from your history';
    if (seconds < 60) return 'Auto Dump in ${seconds}s';
    if (seconds < 3600) return 'Auto Dump in ${(seconds / 60).ceil()}m';
    if (seconds < 86400) return 'Auto Dump in ${(seconds / 3600).ceil()}h';
    return 'Auto Dump in 1 day';
  }

  void clear() {
    _ticker?.cancel();
    _ticker = null;
    deadlines.clear();
    dumped.clear();
    _confirmedDumped.clear();
    _elapsed.stop();
    _serverAnchor = _testAnchor = null;
    _lastServerTime = null;
  }

  @override
  void dispose() {
    _closed = true;
    clear();
    super.dispose();
  }
}

class SocialAutoDumpSheet extends StatefulWidget {
  const SocialAutoDumpSheet({
    super.key,
    required this.client,
    required this.dumps,
    required this.message,
    required this.onSave,
  });
  final SocialClient client;
  final SocialAutoDump dumps;
  final SocialMap message;
  final Future<void> Function(int? seconds, String requestId) onSave;
  @override
  State<SocialAutoDumpSheet> createState() => _SocialAutoDumpSheetState();
}

class _SocialAutoDumpSheetState extends State<SocialAutoDumpSheet> {
  int _seconds = 15;
  String _requestId = socialId();
  String? _error;
  bool _saving = false;
  int? _operation;

  Future<void> _save(int? seconds) async {
    if (_saving || !widget.client.available) return;
    if (_operation != seconds) _requestId = socialId();
    _operation = seconds;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(seconds, _requestId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.client, widget.dumps]),
    builder: (context, _) {
      final id = '${widget.message['id']}';
      final hidden = widget.dumps.hidden(id);
      final available = widget.client.available;
      final scheduled = widget.dumps.deadlines.containsKey(id);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Auto Dump',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close Auto Dump',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!available)
                  const Text(
                    'Your session changed. Close Social and sign in again.',
                  )
                else if (hidden)
                  const Text('This message has been dumped from your history.')
                else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: .5),
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${widget.message['body'] ?? ''}'.trim().isEmpty
                          ? 'Selected attachment'
                          : '${widget.message['body']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Remove from your history on all your devices. Other participants keep their copies.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The timer starts when saved and continues while the app is closed. You can cancel before it expires.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (scheduled) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.dumps.countdown(id),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final delay in socialAutoDumpDelays.entries)
                        ChoiceChip(
                          key: ValueKey('dump-delay-${delay.key}'),
                          label: Text(delay.value),
                          selected: _seconds == delay.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _seconds = delay.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('dump-confirm'),
                    onPressed: _saving ? null : () => _save(_seconds),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.local_shipping_rounded),
                    label: Text(
                      scheduled ? 'Reschedule Auto Dump' : 'Schedule Auto Dump',
                    ),
                  ),
                  if (scheduled)
                    TextButton.icon(
                      key: const ValueKey('dump-cancel'),
                      onPressed: _saving ? null : () => _save(null),
                      icon: const Icon(Icons.timer_off_outlined),
                      label: const Text('Cancel this timer'),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

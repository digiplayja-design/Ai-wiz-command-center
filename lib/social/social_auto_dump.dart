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
  final selfDeadlines = <String, DateTime>{};
  final everyoneDeadlines = <String, DateTime>{};
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
    _readSnapshot(response['dump_self_schedules'], selfDeadlines);
    _readSnapshot(response['dump_everyone_schedules'], everyoneDeadlines);
    if (snapshot is Map && response['dump_self_schedules'] is! Map) {
      // Backward-compatible APIs only supported personal timers.
      _readSnapshot(snapshot, selfDeadlines);
      everyoneDeadlines.clear();
    }
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

  void _readSnapshot(dynamic value, Map<String, DateTime> target) {
    if (value is! Map) return;
    target.clear();
    for (final entry in value.entries) {
      final date = DateTime.tryParse('${entry.value}');
      if (entry.key is String && date != null) {
        target[entry.key as String] = date.toUtc();
      }
    }
  }

  DateTime? scopeDeadline(String id, String scope) =>
      (scope == 'everyone' ? everyoneDeadlines : selfDeadlines)[id];

  void _observeMessage(SocialMap message) {
    final id = message['id'];
    if (id is! String) return;
    for (final scope in ['self', 'everyone']) {
      final key = '${scope}_dump_at';
      final target = scope == 'self' ? selfDeadlines : everyoneDeadlines;
      if (message.containsKey(key)) {
        final date = DateTime.tryParse('${message[key]}');
        if (date == null) {
          target.remove(id);
        } else {
          target[id] = date.toUtc();
        }
      }
    }
    if (!message.containsKey('self_dump_at') &&
        !message.containsKey('everyone_dump_at') &&
        message.containsKey('dump_at')) {
      final date = DateTime.tryParse('${message['dump_at']}');
      if (date == null) {
        selfDeadlines.remove(id);
      } else {
        selfDeadlines[id] = date.toUtc();
      }
    }
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
  String countdown(String id, {String? scope}) {
    final remaining = scope == null
        ? this.remaining(id)
        : scopeDeadline(id, scope)?.difference(now);
    final seconds = ((remaining?.inMilliseconds ?? 0) / 1000).ceil();
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
    selfDeadlines.clear();
    everyoneDeadlines.clear();
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
    this.canDumpEveryone = false,
  });
  final SocialClient client;
  final SocialAutoDump dumps;
  final SocialMap message;
  final bool canDumpEveryone;
  final Future<void> Function(int? seconds, String scope, String requestId)
  onSave;
  @override
  State<SocialAutoDumpSheet> createState() => _SocialAutoDumpSheetState();
}

class _SocialAutoDumpSheetState extends State<SocialAutoDumpSheet> {
  int _seconds = 15;
  String _requestId = socialId();
  String? _error;
  bool _saving = false;
  String? _operation;
  String _scope = 'self';

  @override
  void initState() {
    super.initState();
    final id = '${widget.message['id']}';
    if (widget.canDumpEveryone &&
        widget.dumps.scopeDeadline(id, 'self') == null &&
        widget.dumps.scopeDeadline(id, 'everyone') != null) {
      _scope = 'everyone';
    }
  }

  Future<void> _save(int? seconds) async {
    if (_saving || !widget.client.available) return;
    final operation = '$_scope:$seconds';
    if (_operation != operation) _requestId = socialId();
    _operation = operation;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(seconds, _scope, _requestId);
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
      final scheduled = widget.dumps.scopeDeadline(id, _scope) != null;
      final everyoneScheduled =
          widget.dumps.scopeDeadline(id, 'everyone') != null;
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('dump-scope-self'),
                        label: const Text('Only for me'),
                        selected: _scope == 'self',
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _scope = 'self'),
                      ),
                      if (widget.canDumpEveryone)
                        ChoiceChip(
                          key: const ValueKey('dump-scope-everyone'),
                          label: const Text('For everyone'),
                          selected: _scope == 'everyone',
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _scope = 'everyone'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _scope == 'everyone'
                        ? "Remove your sent message from everyone's conversation history. Screenshots, downloads and other saved copies cannot be recalled."
                        : 'Remove from your history on all your devices. Other participants keep their copies.',
                  ),
                  if (!widget.canDumpEveryone) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Only the sender can dump a message for everyone.',
                    ),
                    if (everyoneScheduled)
                      Text(
                        'Sender timer for everyone: ${widget.dumps.countdown(id, scope: 'everyone')}',
                      ),
                  ],
                  if (widget.dumps.scopeDeadline(id, 'self') != null &&
                      everyoneScheduled) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'A personal timer and an everyone timer are active. Whichever expires first removes your copy; cancelling one leaves the other active.',
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'The timer starts when saved and continues while the app is closed. You can cancel before it expires.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (scheduled) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${_scope == 'everyone' ? 'For everyone' : 'Only for me'}: ${widget.dumps.countdown(id, scope: _scope)}',
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
                      label: Text(
                        _scope == 'everyone'
                            ? 'Cancel everyone timer'
                            : 'Cancel my timer',
                      ),
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

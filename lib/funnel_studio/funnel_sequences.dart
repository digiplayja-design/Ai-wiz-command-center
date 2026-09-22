import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

String sequenceDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return 'Not scheduled';
  return '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.timeZoneName}';
}

Future<Map<String, dynamic>?> showSequenceComposer(
  BuildContext context, {
  required Map<String, dynamic> task,
  Map<String, dynamic>? existing,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SequenceComposer(task: task, existing: existing),
);

class _SequenceStep {
  _SequenceStep(String subject, String body, this.time, {this.task})
    : subject = TextEditingController(text: subject),
      body = TextEditingController(text: body);
  final TextEditingController subject, body;
  final Map<String, dynamic>? task;
  DateTime time;
  void dispose() {
    subject.dispose();
    body.dispose();
  }
}

class _SequenceComposer extends StatefulWidget {
  const _SequenceComposer({required this.task, this.existing});
  final Map<String, dynamic> task;
  final Map<String, dynamic>? existing;
  @override
  State<_SequenceComposer> createState() => _SequenceComposerState();
}

class _SequenceComposerState extends State<_SequenceComposer> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final List<_SequenceStep> _steps = [];
  final List<_SequenceStep> _removedSteps = [];
  bool _review = false, _approved = false;
  String? _error;
  bool get _resume => widget.existing != null;
  String get _recipient =>
      '${widget.existing?['to_email'] ?? widget.task['to_email']}';
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: '${widget.existing?['sequence']['name'] ?? 'Inquiry follow-up'}',
    );
    var start = DateTime.now().add(const Duration(hours: 1, minutes: 1));
    final due = DateTime.tryParse('${widget.task['due_at']}')?.toLocal();
    if (!_resume && due != null && due.isAfter(start)) {
      start = due.add(const Duration(minutes: 1));
    }
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    );
    if (_resume) {
      final remaining = (widget.existing!['steps'] as List)
          .cast<Map>()
          .where((t) => t['state'] != 'sent')
          .toList();
      for (var i = 0; i < remaining.length; i++) {
        final t = Map<String, dynamic>.from(remaining[i]);
        _steps.add(
          _SequenceStep(
            '${t['subject']}',
            '${t['body']}',
            start.add(Duration(days: i)),
            task: t,
          ),
        );
      }
    } else {
      _steps.add(
        _SequenceStep(
          '${widget.task['subject']}',
          '${widget.task['body']}',
          start,
        ),
      );
      _steps.add(
        _SequenceStep(
          'Following up on your inquiry',
          'Hi ${widget.task['lead_name']},\n\nI am following up on your recent inquiry. Is there anything else you would like us to clarify?',
          start.add(const Duration(days: 1)),
        ),
      );
      _steps.add(
        _SequenceStep(
          'Would you like to continue?',
          'Hi ${widget.task['lead_name']},\n\nWould you like to continue the conversation about your inquiry? Let us know how we can help.',
          start.add(const Duration(days: 3)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final s in [..._steps, ..._removedSteps]) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(_SequenceStep step) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: step.time.isBefore(now)
          ? now
          : step.time.isAfter(now.add(const Duration(days: 30)))
          ? now.add(const Duration(days: 30))
          : step.time,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(step.time),
    );
    if (time == null || !mounted) return;
    setState(() {
      step.time = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _approved = false;
    });
  }

  bool _validate() {
    final now = DateTime.now();
    DateTime? previous;
    for (final step in _steps) {
      if (step.subject.text.trim().isEmpty ||
          step.body.text.trim().isEmpty ||
          step.time.isBefore(now.add(const Duration(minutes: 2))) ||
          step.time.isAfter(now.add(const Duration(days: 30))) ||
          previous != null && step.time.difference(previous).inSeconds < 3600) {
        setState(
          () => _error =
              'Add a subject and message to each step. Choose times within 30 days, at least two minutes ahead and one hour apart.',
        );
        return false;
      }
      previous = step.time;
    }
    return true;
  }

  void _submit() {
    if (!_approved || !_validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'confirmed': true,
      'steps': _steps
          .map(
            (s) => <String, dynamic>{
              if (_resume) ...{
                'task_id': s.task!['id'],
                'version': s.task!['version'],
              } else ...{
                'subject': s.subject.text.trim(),
                'body': s.body.text.trim(),
              },
              'scheduled_for': s.time.toUtc().toIso8601String(),
            },
          )
          .toList(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _review
          ? 'Review every sequence step'
          : _resume
          ? 'Review & resume sequence'
          : 'Build a NOVA sequence',
    ),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .66,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WfBadge('${_steps.length} EMAILS · ONE INQUIRY'),
              const SizedBox(height: 12),
              SelectableText(
                'To: $_recipient',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Messages send in order, at least one hour apart, after the previous send is accepted. Sending limits and quiet hours apply. Monitor replies in Email Center and use Mark replied to stop the sequence.',
                style: TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              if (!_review)
                TextFormField(
                  controller: _name,
                  readOnly: _resume,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Sequence name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Name this sequence.'
                      : null,
                ),
              for (var i = 0; i < _steps.length; i++)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: WfStyle.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: WfStyle.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          WfBadge(
                            'STEP ${_resume ? (_steps[i].task!['sequence_step'] as num).toInt() + 1 : i + 1}',
                          ),
                          if (!_review &&
                              !_resume &&
                              i > 0 &&
                              _steps.length > 2)
                            TextButton(
                              onPressed: () => setState(() {
                                _removedSteps.add(_steps.removeAt(i));
                              }),
                              child: const Text('Remove step'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!_review)
                        OutlinedButton.icon(
                          onPressed: () => _pick(_steps[i]),
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            sequenceDate(_steps[i].time.toIso8601String()),
                          ),
                        )
                      else
                        Text(
                          sequenceDate(_steps[i].time.toIso8601String()),
                          style: const TextStyle(color: WfStyle.cyan),
                        ),
                      const SizedBox(height: 12),
                      if (_review || _resume) ...[
                        SelectableText(
                          _steps[i].subject.text.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(_steps[i].body.text.trim()),
                      ] else ...[
                        TextFormField(
                          controller: _steps[i].subject,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a subject.'
                              : null,
                        ),
                        TextFormField(
                          controller: _steps[i].body,
                          maxLength: 6000,
                          minLines: 3,
                          maxLines: 7,
                          decoration: const InputDecoration(
                            labelText: 'Message',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a message.'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              if (!_review && !_resume && _steps.length < 5)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _steps.add(
                        _SequenceStep(
                          '',
                          '',
                          _steps.last.time.add(const Duration(days: 1)),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add step'),
                  ),
                ),
              if (_review)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _approved,
                    onChanged: (v) => setState(() => _approved = v == true),
                    title: Text(
                      'I approve all ${_steps.length} messages and send times for $_recipient.',
                    ),
                    subtitle: const Text(
                      'These are responses to this inquiry. No promotional campaign is authorized. You can pause remaining steps anytime.',
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WfStyle.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_review)
        TextButton(
          onPressed: () => setState(() {
            _review = false;
            _approved = false;
          }),
          child: const Text('Back'),
        ),
      FilledButton(
        onPressed: _review
            ? (_approved ? _submit : null)
            : () {
                if (_form.currentState!.validate() && _validate()) {
                  setState(() {
                    _review = true;
                    _error = null;
                  });
                }
              },
        child: Text(
          _review
              ? _resume
                    ? 'Approve & resume'
                    : 'Approve sequence'
              : 'Review sequence',
        ),
      ),
    ],
  );
}

class FunnelSequenceTimeline extends StatefulWidget {
  const FunnelSequenceTimeline({
    super.key,
    required this.client,
    required this.funnelId,
    required this.sequenceId,
  });
  final FunnelClient client;
  final String funnelId, sequenceId;
  @override
  State<FunnelSequenceTimeline> createState() => _FunnelSequenceTimelineState();
}

class _FunnelSequenceTimelineState extends State<FunnelSequenceTimeline> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = true;
  String get _path => '/${widget.funnelId}/followups';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.request(
        'GET',
        '$_path/sequences/${widget.sequenceId}',
      );
      if (mounted) {
        setState(() => _data = d);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _act(String action) async {
    final q = Map<String, dynamic>.from(_data!['sequence'] as Map);
    final steps = (_data!['steps'] as List).cast<Map>();
    Map<String, dynamic>? payload;
    if (action == 'resumeSequence') {
      payload = await showSequenceComposer(
        context,
        task: Map<String, dynamic>.from(steps.first),
        existing: _data,
      );
    } else {
      final verb = action == 'pauseSequence'
          ? 'Pause sequence'
          : action == 'replySequence'
          ? 'Mark replied'
          : 'Cancel sequence';
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$verb?'),
          content: Text(
            action == 'pauseSequence'
                ? 'Pending steps will stop and require fresh approval to resume. A send already underway may finish.'
                : 'Remaining steps will stop. This does not send a reply or recall any email already sent. A send underway may finish.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(verb),
            ),
          ],
        ),
      );
      if (yes == true) {
        payload = {'confirmed': true};
      }
    }
    if (payload == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        '$_path/$action',
        body: {...payload, 'sequence_id': q['id'], 'version': q['version']},
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _data?['sequence'] as Map?;
    final steps = (_data?['steps'] as List? ?? []).cast<Map>();
    final canManage = q?['state'] == 'active' || q?['state'] == 'paused';
    final remaining = steps.where((t) => t['state'] != 'sent').toList();
    final canResume =
        q?['state'] == 'paused' &&
        remaining.isNotEmpty &&
        remaining.every(
          (t) => t['state'] == 'review' && t['message_id'] == null,
        );
    return AlertDialog(
      title: const Text('Sequence timeline'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .65,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (q != null) ...[
                Text(
                  '${q['name']}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WfBadge('${q['state']}'.toUpperCase()),
                    WfBadge(
                      '${steps.where((s) => s['state'] == 'sent').length}/${steps.length} ACCEPTED',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SelectableText(
                  '${_data!['lead_name']} · ${_data!['to_email']}',
                ),
                const SizedBox(height: 12),
                Text(
                  '${q['note']}',
                  style: const TextStyle(color: WfStyle.muted, height: 1.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mark replied is manual. Check incoming replies in NOVA Email Center; this sequence does not automatically detect replies.',
                  style: TextStyle(color: WfStyle.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (q['state'] == 'active')
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _act('pauseSequence'),
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause sequence'),
                      ),
                    if (canResume)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _act('resumeSequence'),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Review & resume'),
                      ),
                    if (canManage) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _act('replySequence'),
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text('Mark replied'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _act('cancelSequence'),
                        child: const Text('Cancel sequence'),
                      ),
                    ],
                  ],
                ),
                if (q['state'] == 'paused' && !canResume)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Check the existing delivery in NOVA Email Center before restarting any remaining messages.',
                      style: TextStyle(color: WfStyle.gold),
                    ),
                  ),
                for (final t in steps)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: WfStyle.line),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STEP ${(t['sequence_step'] as num).toInt() + 1} · ${'${t['state']}'.toUpperCase()}',
                          style: const TextStyle(
                            color: WfStyle.cyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${t['scheduled_for'] == null ? 'Planned' : 'Approved'}: ${sequenceDate(t['scheduled_for'] ?? t['due_at'])}',
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          '${t['subject']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        SelectableText('${t['body']}'),
                        if ('${t['note'] ?? ''}'.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              '${t['note']}',
                              style: const TextStyle(color: WfStyle.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WfStyle.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  _load();
                },
          child: const Text('Refresh timeline'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

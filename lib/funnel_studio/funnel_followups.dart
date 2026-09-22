import 'dart:async';
import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

class FunnelFollowups extends StatefulWidget {
  const FunnelFollowups({
    super.key,
    required this.client,
    required this.funnelId,
    this.onOpenContacts,
  });
  final FunnelClient client;
  final String funnelId;
  final Future<void> Function()? onOpenContacts;
  @override
  State<FunnelFollowups> createState() => _FunnelFollowupsState();
}

class _FunnelFollowupsState extends State<FunnelFollowups> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int _offset = 0;
  String _filter = 'open';
  String get _path => '/${widget.funnelId}/followups';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() => _run(_fetch);
  Future<void> _fetch() async {
    final data = await widget.client.request(
      'GET',
      _path,
      query: {'offset': '$_offset', 'filter': _filter},
    );
    if (mounted) setState(() => _data = data);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post(String action, Map<String, dynamic> body) =>
      _run(() async {
        try {
          await widget.client.request('POST', '$_path/$action', body: body);
        } finally {
          await _fetch();
        }
      });
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: WfStyle.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: WfStyle.line),
    ),
    child: child,
  );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final callback = _busy ? null : action;
    return primary
        ? FilledButton.icon(
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }

  String _date(dynamic raw) {
    final date = DateTime.tryParse('$raw')?.toLocal();
    if (date == null) return 'Unknown';
    return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirm(
    String title,
    String description,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: Text(description)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _settings() async {
    final s = Map<String, dynamic>.from(_data!['settings'] as Map);
    final subject = TextEditingController(text: '${s['subject']}');
    final body = TextEditingController(text: '${s['body']}');
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Design your follow-up'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'When a new inquiry arrives, create tasks for your team. Every email requires your review and Send confirmation.',
                      style: TextStyle(color: WfStyle.muted, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Email response'),
                      subtitle: const Text(
                        'Editable message, sent through NOVA after approval.',
                      ),
                      value: s['email_enabled'] == true,
                      onChanged: (v) =>
                          set(() => s['email_enabled'] = v == true),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Call review task'),
                      subtitle: const Text(
                        'Prepare a contact brief. No automatic calls are placed.',
                      ),
                      value: s['call_enabled'] == true,
                      onChanged: (v) =>
                          set(() => s['call_enabled'] = v == true),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: s['delay_minutes'] as int,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Task becomes due',
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Immediately')),
                        DropdownMenuItem(
                          value: 60,
                          child: Text('After 1 hour'),
                        ),
                        DropdownMenuItem(
                          value: 240,
                          child: Text('After 4 hours'),
                        ),
                        DropdownMenuItem(
                          value: 1440,
                          child: Text('After 1 day'),
                        ),
                      ],
                      onChanged: (v) => s['delay_minutes'] = v,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: subject,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Email subject',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Add a subject.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: body,
                      minLines: 5,
                      maxLines: 12,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: 'Email template',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Add a message.'
                          : null,
                    ),
                    const Text(
                      'Personalize with {{name}}, {{brand}}, {{funnel}}, and {{booking_url}}. Use this message to respond to the inquiry; the form does not collect marketing consent.',
                      style: TextStyle(color: WfStyle.muted, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Template and timing changes apply to new tasks. Existing tasks keep their reviewed content.',
                      style: TextStyle(color: WfStyle.gold, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => {
                if (form.currentState!.validate() &&
                    (s['email_enabled'] == true || s['call_enabled'] == true))
                  Navigator.pop(c, {
                    ...s,
                    'subject': subject.text,
                    'body': body.text,
                  }),
              },
              child: const Text('Review settings'),
            ),
          ],
        ),
      ),
    );
    // Keep controllers alive until the dialog's closing transition completes.
    Future<void>.delayed(const Duration(seconds: 1), () {
      subject.dispose();
      body.dispose();
    });
    if (result == null || !mounted) return;
    if (!await _confirm(
          'Save this workflow?',
          'New inquiries will create ${result['email_enabled'] == true ? 'email response tasks' : ''}${result['email_enabled'] == true && result['call_enabled'] == true ? ' and ' : ''}${result['call_enabled'] == true ? 'call review tasks' : ''}.\n\nTask delay: ${result['delay_minutes']} minutes.\n${result['enabled'] == true ? 'The workflow will remain enabled.' : 'The workflow stays paused until you enable it.'}\n\nSaving will not send an email or place a call.',
          'Save workflow',
        ) ||
        !mounted) {
      return;
    }
    await _post('settings', {...result, 'confirmed': true});
  }

  Future<void> _toggle() async {
    final s = Map<String, dynamic>.from(_data!['settings'] as Map);
    final enable = s['enabled'] != true;
    if (!await _confirm(
          enable ? 'Enable this workflow?' : 'Pause this workflow?',
          enable
              ? 'New inquiries will create follow-up tasks automatically. Emails are sent only when you review a task and press Send. Calls remain review tasks. Existing inquiries are added individually from the Leads tab.'
              : 'Stop creating new tasks and prevent email sends from this workflow. Existing tasks remain available for review. An email already accepted by the provider cannot be recalled.',
          enable ? 'Enable workflow' : 'Pause workflow',
        ) ||
        !mounted) {
      return;
    }
    await _post('settings', {...s, 'enabled': enable, 'confirmed': true});
  }

  Future<void> _edit(Map<String, dynamic> task) async {
    final subject = TextEditingController(text: '${task['subject']}');
    final body = TextEditingController(text: '${task['body']}');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit response'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('To: ${task['to_email']}'),
                const SizedBox(height: 18),
                TextField(
                  controller: subject,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                TextField(
                  controller: body,
                  minLines: 7,
                  maxLines: 15,
                  maxLength: 6000,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, {
              'task_id': task['id'],
              'version': task['version'],
              'subject': subject.text,
              'body': body.text,
            }),
            child: const Text('Save response'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      subject.dispose();
      body.dispose();
    });
    if (result != null && mounted) await _post('edit', result);
  }

  Future<void> _send(Map<String, dynamic> task) async {
    bool acknowledged = false;
    final result =
        await showDialog<bool>(
          context: context,
          builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
              title: const Text('Review & send with NOVA'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'To: ${task['to_email']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${task['subject']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        '${task['body']}',
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 20),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: acknowledged,
                        onChanged: (v) => set(() => acknowledged = v == true),
                        title: const Text(
                          'I reviewed this recipient and message and approve this response to their inquiry.',
                        ),
                        subtitle: const Text(
                          'This links an eligible contact to NOVA Email if needed and sends one email. Submitted contact details are unverified.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: acknowledged ? () => Navigator.pop(c, true) : null,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send email now'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (result && mounted) {
      await _post('send', {
        'task_id': task['id'],
        'version': task['version'],
        'confirmed': true,
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> t, String outcome) async {
    final done = outcome == 'done';
    if (!await _confirm(
          done ? 'Complete call review?' : 'Dismiss this task?',
          done
              ? 'Mark the brief as reviewed. This records a review; it does not place a call or confirm that a call occurred.'
              : 'Remove this task from the open queue. No message will be sent.',
          done ? 'Mark reviewed' : 'Dismiss task',
        ) ||
        !mounted) {
      return;
    }
    await _post('resolve', {
      'task_id': t['id'],
      'version': t['version'],
      'state': outcome,
      'note': done
          ? 'Call brief reviewed by owner. No automatic call was placed.'
          : 'Dismissed by owner.',
    });
  }

  Widget _task(Map<String, dynamic> t) {
    final email = t['channel'] == 'email';
    final review = t['state'] == 'review';
    final due =
        DateTime.tryParse('${t['due_at']}')?.isAfter(DateTime.now()) != true;
    final allowed = t[email ? 'email_allowed' : 'call_allowed'] == true;
    final active =
        _data?['settings']['enabled'] == true &&
        _data?['settings']['email_enabled'] == true &&
        _data?['page_state'] == 'published';
    final status =
        {
          'review': due ? 'Ready for review' : 'Scheduled',
          'processing': 'Sending',
          'needs_review': 'Check delivery',
          'sent': 'Provider accepted',
          'done': 'Reviewed',
          'dismissed': 'Dismissed',
        }[t['state']] ??
        'Review';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  email ? Icons.mail_outline : Icons.phone_in_talk_outlined,
                  color: email ? WfStyle.cyan : WfStyle.violet,
                ),
                Text(
                  '${t['lead_name']}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                WfBadge(
                  status.toUpperCase(),
                  color: t['state'] == 'needs_review'
                      ? WfStyle.gold
                      : WfStyle.cyan,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              email
                  ? '${t['to_email']}'
                  : '${t['phone'] ?? 'No phone number recorded'}',
              style: const TextStyle(color: WfStyle.muted),
            ),
            const SizedBox(height: 8),
            Text(
              'Due ${_date(t['due_at'])} · local time',
              style: const TextStyle(color: WfStyle.muted, fontSize: 12),
            ),
            if ('${t['inquiry'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'Inquiry: ${t['inquiry']}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            const SizedBox(height: 14),
            if (email) ...[
              Text(
                '${t['subject']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${t['body']}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
            ] else
              Text(
                '${t['call_brief'] ?? ''}'.isNotEmpty
                    ? '${t['call_brief']}'
                    : 'Review the inquiry and contact record before arranging a call.',
                style: const TextStyle(height: 1.5),
              ),
            if (!allowed && review)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  email
                      ? 'Email is held: review the contact’s address, consent, and suppression status in Contacts CRM.'
                      : 'Calling permission is not recorded, or the phone number needs review in Contacts CRM.',
                  style: const TextStyle(color: WfStyle.gold, height: 1.5),
                ),
              ),
            if (email && review && !active)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Enable email follow-ups and publish the page before sending.',
                  style: TextStyle(color: WfStyle.gold),
                ),
              ),
            if ('${t['note'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${t['note']}',
                  style: const TextStyle(color: WfStyle.muted, height: 1.5),
                ),
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (review && email) ...[
                  _button(
                    'Review & send',
                    Icons.send_outlined,
                    allowed && active && due && _data?['email_ready'] == true
                        ? () => _send(t)
                        : null,
                    primary: true,
                  ),
                  if (t['message_id'] == null)
                    _button(
                      'Edit response',
                      Icons.edit_outlined,
                      () => _edit(t),
                    ),
                ],
                if (review && !email)
                  _button(
                    'Mark reviewed',
                    Icons.task_alt,
                    () => _resolve(t, 'done'),
                  ),
                if (t['state'] == 'needs_review')
                  _button(
                    'Check delivery',
                    Icons.sync,
                    () => _post('reconcile', {'task_id': t['id']}),
                  ),
                if (review)
                  _button(
                    'Dismiss',
                    Icons.close,
                    () => _resolve(t, 'dismissed'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _data?['settings'];
    final counts = _data?['counts'] as Map? ?? {};
    final total = (_data?['total'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn interest into a conversation.',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'NOVA organizes each next step. You decide when a message leaves your business.',
                style: TextStyle(color: WfStyle.muted, height: 1.6),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  WfBadge(
                    s?['enabled'] == true ? 'WORKFLOW ON' : 'WORKFLOW PAUSED',
                    color: s?['enabled'] == true ? WfStyle.cyan : WfStyle.gold,
                  ),
                  WfBadge('${counts['open'] ?? 0} OPEN'),
                  WfBadge('${counts['sent'] ?? 0} EMAILS ACCEPTED'),
                  WfBadge('${counts['completed'] ?? 0} REVIEWED / DISMISSED'),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _button(
                    'Workflow settings',
                    Icons.tune,
                    _data == null ? null : _settings,
                  ),
                  _button(
                    s?['enabled'] == true
                        ? 'Pause workflow'
                        : 'Enable workflow',
                    s?['enabled'] == true ? Icons.pause : Icons.play_arrow,
                    _data == null ? null : _toggle,
                    primary: true,
                  ),
                  _button('Refresh queue', Icons.refresh, _load),
                  if (widget.onOpenContacts != null)
                    _button(
                      'Contacts CRM',
                      Icons.people_outline,
                      () => widget.onOpenContacts!(),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _data?['email_ready'] == true
                    ? 'NOVA Email connected · existing sending limits and quiet hours apply.'
                    : '${_data?['email_reason'] ?? 'Checking NOVA Email…'}',
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'Outbound calling: review tasks only. No calls are placed by this workflow.',
                style: TextStyle(color: WfStyle.muted, height: 1.5),
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _error!,
              style: const TextStyle(color: WfStyle.danger, height: 1.5),
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in {
              'open': 'Open tasks',
              'completed': 'Completed',
              'all': 'All activity',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() {
                          _filter = entry.key;
                          _offset = 0;
                        });
                        unawaited(_load());
                      },
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (_data != null && (_data!['tasks'] as List).isEmpty)
          _card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_motion_outlined,
                  color: WfStyle.cyan,
                  size: 32,
                ),
                SizedBox(height: 14),
                Text(
                  'Your next steps will appear here.',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 10),
                Text(
                  'Enable a workflow for new inquiries, or queue an existing inquiry from Leads. No test contacts or sample messages are added to your CRM.',
                  style: TextStyle(color: WfStyle.muted, height: 1.6),
                ),
              ],
            ),
          ),
        for (final task in _data?['tasks'] as List? ?? [])
          _task(Map<String, dynamic>.from(task as Map)),
        if (total > 0)
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_offset + 1}–${(_offset + 25).clamp(0, total)} of $total tasks',
              ),
              _button(
                'Previous',
                Icons.chevron_left,
                _offset > 0
                    ? () {
                        setState(
                          () => _offset = (_offset - 25).clamp(0, 100000),
                        );
                        unawaited(_load());
                      }
                    : null,
              ),
              _button(
                'Next',
                Icons.chevron_right,
                _offset + 25 < total
                    ? () {
                        setState(() => _offset += 25);
                        unawaited(_load());
                      }
                    : null,
              ),
            ],
          ),
      ],
    );
  }
}

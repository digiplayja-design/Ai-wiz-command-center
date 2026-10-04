import 'dart:async';

import 'package:flutter/material.dart';

import 'workforce_client.dart';
import 'workforce_style.dart';
import 'workforce_email_recipient.dart';

const _kinds = <String, (String, IconData, String)>{
  'missed_update': (
    'Work update reminders',
    Icons.edit_note,
    'A gentle nudge when a required work update is overdue.',
  ),
  'missed_shift': (
    'Shift check-ins',
    Icons.schedule_outlined,
    'Follow up when a scheduled shift has no recorded clock-in.',
  ),
  'daily_summary': (
    'Morning team summary',
    Icons.mark_email_read_outlined,
    'The previous day’s recorded work, ready for your inbox.',
  ),
};
const _week = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class WorkforceAutomations extends StatefulWidget {
  const WorkforceAutomations({
    super.key,
    required this.client,
    required this.orgId,
    required this.members,
    required this.timezone,
  });
  final WorkforceClient client;
  final String orgId, timezone;
  final List<WfJson> members;
  @override
  State<WorkforceAutomations> createState() => _WorkforceAutomationsState();
}

class _WorkforceAutomationsState extends State<WorkforceAutomations>
    with WidgetsBindingObserver {
  WfJson? _data;
  List<WfJson> _recipients = [];
  String? _error;
  bool _busy = false, _loading = false, _visible = true, _dialog = false;
  int _generation = 0;
  String _history = 'all';
  Timer? _poll;
  String get _base => '/${widget.orgId}/automations';
  List<WfJson> get _rules => wfRows(_data?['rules']);
  List<WfJson> get _jobs => wfRows(_data?['jobs']);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addAccessDeniedListener(_accessDenied);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_visible && !_busy && !_dialog) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible && !_dialog) _load();
  }

  void _accessDenied() {
    _generation++;
    _poll?.cancel();
    if (!mounted) return;
    if (_dialog) Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      _data = null;
      _recipients = [];
      _error = 'Sign in again and reopen Workforce.';
    });
  }

  @override
  void didUpdateWidget(covariant WorkforceAutomations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orgId != widget.orgId || oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_accessDenied);
      widget.client.addAccessDeniedListener(_accessDenied);
      _generation++;
      _loading = false;
      _data = null;
      _recipients = [];
      _load();
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_accessDenied);
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || widget.client.sessionChanged) return;
    _loading = true;
    final generation = _generation, org = widget.orgId;
    final base = _base;
    try {
      final data = await widget.client.request('GET', base);
      List<WfJson> recipients = [];
      try {
        recipients = wfRows(
          (await widget.client.request(
            'GET',
            '/$org/email-recipients',
          ))['recipients'],
        );
      } catch (_) {}
      final workspaceRecipients = wfRows(
        (await widget.client.request(
          'GET',
          '$base/email-recipients',
        ))['recipients'],
      );
      recipients = [
        ...recipients,
        ...workspaceRecipients.map((r) => {...r, 'workspace': true}),
      ];
      if (mounted &&
          generation == _generation &&
          !widget.client.sessionChanged) {
        setState(() {
          _data = data;
          _recipients = recipients;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.toString();
          if (e is WorkforceException && [401, 403].contains(e.status)) {
            _data = null;
            _recipients = [];
          }
        });
      }
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  String _person(dynamic id) =>
      widget.members
          .where((m) => m['user_id'] == id)
          .firstOrNull?['display_name']
          ?.toString() ??
      'All active team members';
  String _recipient(dynamic id) {
    final r = _recipients.where((r) => r['id'] == id).firstOrNull;
    return r == null
        ? 'Approved email recipient'
        : '${r['displayName'] ?? r['display_name'] ?? r['name'] ?? ''} <${r['email']}>';
  }

  bool _recipientAvailable(dynamic id) => _recipients.any(
    (r) =>
        r['id'] == id &&
        r['active'] == true &&
        !['unsubscribed', 'suppressed'].contains(r['consentStatus']),
  );

  String _timing(WfJson r) => r['kind'] == 'daily_summary'
      ? '${r['local_time'].toString().substring(0, 5)} · ${widget.timezone} · previous day'
      : '${r['delay_minutes']} min ${r['kind'] == 'missed_update' ? 'after the update grace period' : 'after the scheduled start'}';
  Future<void> _act(String suffix, WfJson body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request('POST', '$_base$suffix', body: body);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(WfJson r) async {
    if (r['enabled'] == true) {
      await _act('/toggle', {
        'rule_id': r['id'],
        'version': r['version'],
        'enabled': false,
      });
      return;
    }
    _dialog = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => _EnableDialog(
        rule: r,
        recipient: _recipient(r['recipient_id']),
        member: _person(r['member_id']),
        timing: _timing(r),
      ),
    );
    _dialog = false;
    if (!mounted || approved != true) return;
    await _act('/toggle', {
      'rule_id': r['id'],
      'version': r['version'],
      'enabled': true,
      'confirmed': true,
    });
  }

  Future<void> _new(String kind, {WfJson? rule}) async {
    // Ignore any poll started before the editor opened.
    final generation = ++_generation;
    _loading = false;
    _dialog = true;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AutomationForm(
        client: widget.client,
        path: _base,
        kind: kind,
        members: widget.members,
        recipients: _recipients,
        timezone: widget.timezone,
        rule: rule,
      ),
    );
    _dialog = false;
    if (!mounted || generation != _generation) return;
    await _load();
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rule == null
                ? 'Reminder saved. Review & enable when ready.'
                : 'Changes saved. Review & enable to resume with the new instructions.',
          ),
        ),
      );
    }
  }

  Future<void> _addRecipient() async {
    _dialog = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkforceEmailRecipientDialog(
        client: widget.client,
        path: '$_base/email-recipients',
      ),
    );
    _dialog = false;
    if (mounted) await _load();
  }

  Future<void> _reviewEmail(WfJson job) async {
    _dialog = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review email draft'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To: ${job['recipient_email'] ?? 'Approved recipient'}'),
                Text(
                  'Replies to: ${wfMap(_data?['workspace_email'])['reply_to'] ?? 'Your verified account email'}',
                ),
                const SizedBox(height: 12),
                Text('Workforce · ${job['subject']}'),
                const SizedBox(height: 12),
                SelectableText(job['body'].toString()),
                const SizedBox(height: 12),
                const Text(
                  'The email includes a KORLIX footer and a link to stop future workspace emails.',
                ),
                Text('Expires: ${_time(job['expires_at'])}'),
                const SizedBox(height: 12),
                const Text(
                  'Approval queues this email within its sending window. KORLIX rechecks the current work record before sending.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve this email'),
          ),
        ],
      ),
    );
    _dialog = false;
    if (!mounted || approved != true) return;
    await _act('/email-review', {
      'action': 'approve',
      'job_id': job['id'],
      'version': job['version'],
      'confirmed': true,
    });
  }

  Widget _card(Widget child, {Color? border}) => Material(
    color: WfStyle.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: border ?? WfStyle.line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
  Widget _text(String text, {Color color = WfStyle.muted, double size = 13}) =>
      Text(
        text,
        style: TextStyle(color: color, fontSize: size, height: 1.5),
      );
  Widget _stat(String value, String label, Color color) => Container(
    width: 160,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: WfStyle.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: WfStyle.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 27,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        _text(label),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.auto_awesome, color: WfStyle.cyan, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'KORLIX AUTOMATIONS',
              style: TextStyle(
                color: WfStyle.cyan,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh automations',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Your team. In sync.',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 8),
      _text(
        'Thoughtful reminders and a clear morning summary. Set the rules once; KORLIX follows up while you focus on your team.',
        size: 15,
      ),
      const SizedBox(height: 22),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _card(
            _text(_error!, color: WfStyle.danger),
            border: WfStyle.danger,
          ),
        ),
      if (_data == null && _error == null)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: CircularProgressIndicator(),
          ),
        ),
      if (_data != null) ...[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat(
              '${_rules.where((r) => r['enabled'] == true).length}',
              'Active automations',
              WfStyle.cyan,
            ),
            _stat(
              '${_jobs.where((j) => j['status'] == 'sent').length}',
              'Emails accepted*',
              WfStyle.violet,
            ),
            _stat(
              '${_jobs.where((j) => j['status'] == 'review').length}',
              'Call reviews',
              WfStyle.gold,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _text(
          '*Latest 100 activity records. Provider accepted and delivered are separate statuses. Email Center rules retain their existing delivery history.',
          size: 11,
        ),
        const SizedBox(height: 24),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  WfBadge(
                    wfMap(_data!['workspace_email'])['ready'] == true
                        ? 'Workforce email ready'
                        : 'Email setup needed',
                    color: wfMap(_data!['workspace_email'])['ready'] == true
                        ? WfStyle.cyan
                        : WfStyle.gold,
                    dot: true,
                  ),
                  const WfBadge('Server scheduling', color: WfStyle.violet),
                ],
              ),
              const SizedBox(height: 12),
              _text(
                wfMap(_data!['workspace_email'])['reason']?.toString() ??
                    'Choose draft review or automatic sending. Replies go to your verified account email. Each rule has its own sending window, with a maximum of 100 Workforce emails per owner in 24 hours.',
              ),
              const SizedBox(height: 8),
              _text(
                'Call escalation creates an owner review item. Automatic outbound calls are not enabled.',
                size: 12,
              ),
              if (_data!['active_plan'] != true)
                _text(
                  'Renew Enterprise to enable automations. You can still pause them and review history.',
                  color: WfStyle.gold,
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Autonomous email',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _data!['active_plan'] != true
                        ? null
                        : _addRecipient,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Add email recipient'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _text(
                'Approve the people who may receive workspace records. New rules start paused; draft review requires approval for each message.',
              ),
              if (!_recipients.any((r) => r['workspace'] == true))
                _text(
                  'Add your first recipient, then choose a recipe below.',
                  color: WfStyle.cyan,
                ),
              for (final recipient in _recipients.where(
                (r) => r['workspace'] == true,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(recipient['name'].toString()),
                  subtitle: Text(
                    '${recipient['email']} · ${recipient['active'] == true ? 'Approved' : wfLabel(recipient['stopped_reason'])}',
                  ),
                  trailing: recipient['active'] == true
                      ? TextButton(
                          onPressed: _busy
                              ? null
                              : () => _act('/email-recipients/revoke', {
                                  'id': recipient['id'],
                                }),
                          child: const Text('Stop'),
                        )
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          'Create a reminder',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final e in _kinds.entries)
                SizedBox(
                  width: box.maxWidth >= 900
                      ? (box.maxWidth - 28) / 3
                      : box.maxWidth,
                  child: _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(e.value.$2, color: WfStyle.violet, size: 27),
                        const SizedBox(height: 18),
                        Text(
                          e.value.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _text(e.value.$3),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: _busy || _data!['active_plan'] != true
                              ? null
                              : () => _new(e.key),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Set up'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            const Text(
              'Your automations',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            TextButton.icon(
              onPressed: _busy || !_rules.any((r) => r['enabled'] == true)
                  ? null
                  : () => _act('/pause-all', {}),
              icon: const Icon(Icons.pause_circle_outline, size: 18),
              label: const Text('Pause all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_rules.isEmpty)
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nothing runs until you enable it.',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _text(
                  'Choose a recipe, select the people and timing, then review your message before enabling. New automations are saved paused.',
                ),
              ],
            ),
          ),
        for (final r in _rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        r['name'].toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      WfBadge(
                        r['enabled'] == true ? 'Active' : 'Paused',
                        color: r['enabled'] == true
                            ? WfStyle.cyan
                            : WfStyle.muted,
                        dot: true,
                      ),
                      WfBadge(
                        r['channel'] == 'workspace_email'
                            ? (r['delivery_mode'] == 'automatic'
                                  ? 'Automatic email'
                                  : 'Review drafts')
                            : r['channel'] == 'email'
                            ? 'Email Center'
                            : 'Call review',
                        color: WfStyle.violet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _text(_timing(r)),
                  _text(
                    '${(r['days'] as List).map((d) => _week[d as int]).join(' · ')}  |  Up to ${r['daily_limit']} per day',
                  ),
                  _text(
                    r['kind'] == 'daily_summary'
                        ? 'Scope: all team records for the previous calendar day'
                        : 'Scope: ${_person(r['member_id'])}',
                  ),
                  _text(
                    r['channel'] != 'call_review'
                        ? 'To: ${_recipient(r['recipient_id'])}'
                        : 'Destination: owner’s call review queue',
                  ),
                  if (r['channel'] == 'workspace_email')
                    _text(
                      'Sending window: ${r['send_start'].toString().substring(0, 5)}–${r['send_end'].toString().substring(0, 5)} · ${widget.timezone}',
                    ),
                  if (r['last_error'] != null)
                    _text(
                      'KORLIX could not check this automation. Refresh or review its settings.',
                      color: WfStyle.gold,
                    ),
                  const SizedBox(height: 14),
                  if (r['channel'] == 'workspace_email') ...[
                    _text(
                      (r['instructions']?.toString().trim().isNotEmpty ?? false)
                          ? 'Instructions: ${r['instructions']}'
                          : 'Instructions: standard reminder message',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy || _data!['active_plan'] != true
                          ? null
                          : () => _new(r['kind'].toString(), rule: r),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit reminder'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            (r['enabled'] != true &&
                                (_data!['active_plan'] != true ||
                                    (r['channel'] == 'workspace_email' &&
                                        (!_recipientAvailable(
                                              r['recipient_id'],
                                            ) ||
                                            (r['delivery_mode'] ==
                                                    'automatic' &&
                                                wfMap(
                                                      _data!['workspace_email'],
                                                    )['ready'] !=
                                                    true))) ||
                                    (r['channel'] == 'email' &&
                                        (_data!['email_ready'] != true ||
                                            !_recipientAvailable(
                                              r['recipient_id'],
                                            )))))
                        ? null
                        : () => _toggle(r),
                    icon: Icon(
                      r['enabled'] == true ? Icons.pause : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(
                      r['enabled'] == true ? 'Pause' : 'Review & enable',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 25),
        const Text(
          'Email drafts & activity',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {
              'all': 'All activity',
              'draft': 'Email drafts',
              'review': 'Call reviews',
              'blocked': 'Needs attention',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _history == entry.key,
                onSelected: (_) => setState(() => _history = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_jobs
            .where((j) => _history == 'all' || j['status'] == _history)
            .isEmpty)
          _card(
            _text(
              'No activity here yet. KORLIX checks enabled automations approximately every minute.',
            ),
          ),
        for (final j in _jobs.where(
          (j) => _history == 'all' || j['status'] == _history,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        j['subject'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      WfBadge(
                        _status(j['status']),
                        color: j['status'] == 'sent'
                            ? WfStyle.cyan
                            : ['blocked', 'review'].contains(j['status'])
                            ? WfStyle.gold
                            : WfStyle.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _text(_time(j['created_at']), size: 11),
                  if (j['status'] == 'blocked')
                    _text(
                      'Delivery needs attention. Check the recipient and sender settings; this message has not been sent again.',
                      color: WfStyle.gold,
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 14),
                    title: const Text(
                      'View message',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          j['body'].toString(),
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ),
                      if (j['result_code'] != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _text(
                            'Status: ${wfLabel(j['result_code'])}',
                            size: 11,
                          ),
                        ),
                    ],
                  ),
                  if (j['status'] == 'draft') ...[
                    _text(
                      'To: ${j['recipient_email'] ?? 'Approved recipient'}',
                    ),
                    _text('Expires: ${_time(j['expires_at'])}', size: 11),
                    Wrap(
                      spacing: 10,
                      children: [
                        FilledButton(
                          onPressed:
                              _busy ||
                                  wfMap(_data!['workspace_email'])['ready'] !=
                                      true
                              ? null
                              : () => _reviewEmail(j),
                          child: const Text('Review draft'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _act('/email-review', {
                                  'action': 'cancel',
                                  'job_id': j['id'],
                                  'version': j['version'],
                                }),
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ],
                  if (j['status'] == 'unknown')
                    _text(
                      'The provider outcome is unknown. KORLIX will not automatically resend this email.',
                      color: WfStyle.gold,
                    ),
                  if (j['status'] == 'review') ...[
                    _text(
                      'No call has been placed. Check the attendance record and the person’s contact preferences before following up.',
                      color: WfStyle.gold,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _act('/review', {'job_id': j['id']}),
                      child: const Text('Mark reviewed'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        _text(
          'Pause stops queued work. An email already handed to the provider cannot be recalled. Automations follow workspace time (${widget.timezone}); emails wait for their sending window and expire when the reminder is no longer relevant.',
          size: 11,
        ),
      ],
    ],
  );
  String _time(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return d == null
        ? ''
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · device time';
  }

  String _status(dynamic value) => switch (value) {
    'sent' => 'Provider accepted',
    'draft' => 'Draft needs approval',
    'sending' => 'Sending',
    'unknown' => 'Outcome unknown',
    'review' => 'Call review needed',
    'reviewed' => 'Reviewed',
    'processing' => 'Processing',
    'pending' => 'Queued',
    'blocked' => 'Needs attention',
    'cancelled' => 'Cancelled',
    'expired' => 'Expired',
    _ => wfLabel(value),
  };
}

String _preview(WfJson r, String member) {
  final instructions = r['instructions']?.toString().trim() ?? '';
  return switch (r['kind']) {
    'daily_summary' =>
      '[Workspace] — Workforce report\n[Previous calendar date] ([Workspace timezone])\n\n[Recorded shifts and full-shift hours overlapping that date]\n[Employee-reported quantities, work updates and blockers]\n[Pending correction count]\n\nWork quantities are employee-reported. Timesheets require manager review.${instructions.isEmpty ? '' : '\n\n$instructions'}',
    'missed_shift' =>
      '[Workspace]\nNo clock-in is recorded for ${member == 'All active team members' ? '[Employee]' : member}’s scheduled shift starting [scheduled time].\n\n${instructions.isEmpty ? 'Please check in through Workforce or contact your employer if plans have changed.' : instructions}\nThis alert is based on attendance records; it does not establish an absence.',
    _ =>
      '[Workspace]\n${member == 'All active team members' ? '[Employee]' : member} has a work update due.\n\n${instructions.isEmpty ? 'Please open Workforce → My day and record completed work, quantities, and any blockers.' : instructions}\nThis reminder reflects recorded updates, not a judgement of productivity.',
  };
}

class _EnableDialog extends StatefulWidget {
  const _EnableDialog({
    required this.rule,
    required this.recipient,
    required this.member,
    required this.timing,
  });
  final WfJson rule;
  final String recipient, member, timing;
  @override
  State<_EnableDialog> createState() => _EnableDialogState();
}

class _EnableDialogState extends State<_EnableDialog> {
  bool _confirmed = false;
  @override
  Widget build(BuildContext context) {
    final email = widget.rule['channel'] != 'call_review';
    final drafts =
        widget.rule['channel'] == 'workspace_email' &&
        widget.rule['delivery_mode'] == 'review';
    return AlertDialog(
      title: const Text('Review your automation'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.rule['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                email
                    ? 'To: ${widget.recipient}'
                    : 'Destination: your call review queue',
              ),
              const SizedBox(height: 8),
              Text(widget.timing),
              if (widget.rule['channel'] == 'workspace_email')
                Text(
                  '${drafts ? 'Review each draft' : 'Send automatically'} · ${widget.rule['send_start'].toString().substring(0, 5)}–${widget.rule['send_end'].toString().substring(0, 5)}',
                ),
              Text(
                'Days: ${(widget.rule['days'] as List).map((d) => _week[d as int]).join(' · ')}',
              ),
              Text(
                widget.rule['kind'] == 'daily_summary'
                    ? 'Scope: all team records for the previous calendar day'
                    : 'Scope: ${widget.member}',
              ),
              Text(
                'Up to ${widget.rule['daily_limit']} per day. Current overdue events may be processed once.',
              ),
              const SizedBox(height: 20),
              const Text(
                'MESSAGE PREVIEW',
                style: TextStyle(
                  fontSize: 11,
                  color: WfStyle.cyan,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bracketed fields are filled from Workforce records. Longer daily summaries link back to the full report.',
                style: TextStyle(fontSize: 12, color: WfStyle.muted),
              ),
              const SizedBox(height: 12),
              SelectableText(
                '${_preview(widget.rule, widget.member)}${email ? '\n\nSent by KORLIX for your approved Workforce automation. Open KORLIX Workforce to review the records.' : ''}',
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v == true),
                title: Text(
                  email
                      ? drafts
                            ? 'Prepare drafts with this scope, recipient and timing. I will approve each email before sending.'
                            : 'I approve recurring emails with this scope, recipient and timing.'
                      : 'Create review items automatically. No outbound calls will be placed.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: const Text('Enable automation'),
        ),
      ],
    );
  }
}

class _AutomationForm extends StatefulWidget {
  const _AutomationForm({
    required this.client,
    required this.path,
    required this.kind,
    required this.members,
    required this.recipients,
    required this.timezone,
    this.rule,
  });
  final WorkforceClient client;
  final String path, kind, timezone;
  final List<WfJson> members, recipients;
  final WfJson? rule;
  @override
  State<_AutomationForm> createState() => _AutomationFormState();
}

class _AutomationFormState extends State<_AutomationForm> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final TextEditingController _name, _instructions, _delay, _limit;
  late String _mode, _start, _end, _channel, _member, _recipient, _time;
  late final Set<int> _days;
  bool _saving = false;
  String? _error;
  bool get _editing => widget.rule != null;
  bool get _email => _channel == 'workspace_email';
  List<WfJson> get _availableRecipients => widget.recipients
      .where(
        (r) =>
            r['workspace'] == true &&
            r['active'] == true &&
            ![
              'unsubscribed',
              'suppressed',
            ].contains(r['consentStatus'] ?? r['consent_status']),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    final r = widget.rule ?? <String, dynamic>{};
    _id = r['id']?.toString() ?? wfId();
    _name = TextEditingController(
      text: r['name']?.toString() ?? _kinds[widget.kind]!.$1,
    );
    _instructions = TextEditingController(
      text: r['instructions']?.toString() ?? '',
    );
    _delay = TextEditingController(text: '${r['delay_minutes'] ?? 10}');
    _limit = TextEditingController(
      text: '${r['daily_limit'] ?? (widget.kind == 'daily_summary' ? 1 : 5)}',
    );
    _mode = r['delivery_mode']?.toString() ?? 'review';
    _start = _clock(r['send_start'], '08:00');
    _end = _clock(r['send_end'], '18:00');
    _time = _clock(r['local_time'], '08:00');
    _channel = r['channel']?.toString() ?? 'workspace_email';
    _member = r['member_id']?.toString() ?? '';
    _recipient = r['recipient_id']?.toString() ?? '';
    _days = (r['days'] as List? ?? [1, 2, 3, 4, 5]).cast<int>().toSet();
  }

  String _clock(dynamic value, String fallback) {
    final text = value?.toString() ?? fallback;
    return text.length >= 5 ? text.substring(0, 5) : fallback;
  }

  @override
  void dispose() {
    for (final controller in [_name, _instructions, _delay, _limit]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      setState(() => _error = 'Choose at least one day.');
      return;
    }
    if (_email && !_availableRecipients.any((r) => r['id'] == _recipient)) {
      setState(() => _error = 'Choose an approved email recipient.');
      return;
    }
    if (_email &&
        widget.kind == 'daily_summary' &&
        (_time.compareTo(_start) < 0 || _time.compareTo(_end) >= 0)) {
      setState(
        () => _error =
            'Choose a summary time inside the sending window in More options.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        '${widget.path}${_editing ? '/update' : ''}',
        body: {
          'id': _id,
          if (_editing) 'version': widget.rule!['version'],
          'name': _name.text.trim(),
          'kind': widget.kind,
          'channel': _channel,
          'instructions': _email ? _instructions.text.trim() : '',
          'member_id': _member.isEmpty ? null : _member,
          'recipient_id': _email ? _recipient : null,
          'delivery_mode': _mode,
          'send_start': _start,
          'send_end': _end,
          'delay_minutes': int.parse(_delay.text),
          'local_time': _time,
          'days': _days.toList()..sort(),
          'daily_limit': int.parse(_limit.text),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  bool _validTime(String? v) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '');
  Widget _gap() => const SizedBox(height: 18);
  String? _number(String? v, int low, int high) {
    final n = int.tryParse(v ?? '');
    return n == null || n < low || n > high ? 'Enter $low–$high' : null;
  }

  Widget _help(String value) => Text(
    value,
    style: const TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
  );
  String get _memberName =>
      widget.members
          .where((m) => m['user_id'] == _member)
          .firstOrNull?['display_name']
          ?.toString() ??
      'All active team members';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_editing ? 'Edit reminder' : _kinds[widget.kind]!.$1),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _help(
                  _editing
                      ? 'Update the instructions below. Saving pauses this reminder so you can review the changes before it runs again.'
                      : 'Choose who receives the email, what it says, and when it runs. Save first, then review & enable.',
                ),
                _gap(),
                if (_email) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('reminder-recipient'),
                    initialValue:
                        _availableRecipients.any((r) => r['id'] == _recipient)
                        ? _recipient
                        : null,
                    decoration: const InputDecoration(labelText: 'Send to'),
                    isExpanded: true,
                    items: [
                      for (final r in _availableRecipients)
                        DropdownMenuItem(
                          value: r['id'].toString(),
                          child: Text(
                            '${r['email']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _recipient = v ?? ''),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Choose an approved recipient'
                        : null,
                  ),
                  if (_availableRecipients.isEmpty) ...[
                    const SizedBox(height: 8),
                    _help(
                      'Add an email recipient in Autonomous email, then return here.',
                    ),
                  ],
                  _gap(),
                  TextFormField(
                    key: const ValueKey('reminder-instructions'),
                    controller: _instructions,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1500,
                    decoration: const InputDecoration(
                      labelText: 'Email instructions',
                      hintText:
                          'Please submit your completed jobs, quantities and any blockers in Workforce.',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  _help(
                    'Included exactly as written in the email. Leave blank for the standard message. Set the schedule using the controls below.',
                  ),
                  _gap(),
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'How to send'),
                    items: const [
                      DropdownMenuItem(
                        value: 'review',
                        child: Text('Review drafts'),
                      ),
                      DropdownMenuItem(
                        value: 'automatic',
                        child: Text('Send automatically'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _mode = v!),
                  ),
                  _gap(),
                ],
                if (widget.kind != 'daily_summary') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _member,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Whose work should trigger this?',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All active team members'),
                      ),
                      if (_member.isNotEmpty &&
                          !widget.members.any((m) => m['user_id'] == _member))
                        DropdownMenuItem(
                          value: _member,
                          enabled: false,
                          child: const Text('Selected member is unavailable'),
                        ),
                      for (final m in widget.members.where(
                        (m) => m['active'] == true || m['user_id'] == _member,
                      ))
                        DropdownMenuItem(
                          value: m['user_id'].toString(),
                          child: Text(
                            m['display_name'].toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _member = v ?? ''),
                  ),
                  _gap(),
                  TextFormField(
                    controller: _delay,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: widget.kind == 'missed_update'
                          ? 'Extra delay after an update is overdue (minutes)'
                          : 'Minutes after the scheduled start',
                    ),
                    validator: (v) => _number(v, 0, 240),
                  ),
                  const SizedBox(height: 8),
                  _help(
                    widget.kind == 'missed_update'
                        ? 'Runs only while the employee is clocked in and a required update is overdue. The shift’s update interval and grace period apply first.'
                        : 'Runs only when a scheduled shift has no recorded clock-in.',
                  ),
                  _gap(),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: int.parse(_time.split(':')[0]),
                                minute: int.parse(_time.split(':')[1]),
                              ),
                            );
                            if (picked != null && mounted) {
                              setState(
                                () => _time =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                              );
                            }
                          },
                    icon: const Icon(Icons.schedule),
                    label: Text('Deliver at $_time · ${widget.timezone}'),
                  ),
                  const SizedBox(height: 8),
                  _help('Summarises the previous calendar day.'),
                  _gap(),
                ],
                const Text(
                  'Days to run',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 0; d < 7; d++)
                      FilterChip(
                        label: Text(_week[d]),
                        selected: _days.contains(d),
                        onSelected: _saving
                            ? null
                            : (v) => setState(
                                () => v ? _days.add(d) : _days.remove(d),
                              ),
                      ),
                  ],
                ),
                _gap(),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  maintainState: true,
                  title: const Text('More options'),
                  subtitle: Text(
                    '$_start–$_end · ${widget.timezone} · up to ${_limit.text}/day',
                  ),
                  children: [
                    _gap(),
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Reminder name',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter a name' : null,
                    ),
                    if (!_editing) ...[
                      _gap(),
                      DropdownButtonFormField<String>(
                        initialValue: _channel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Follow-up action',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'workspace_email',
                            child: Text('Workforce email'),
                          ),
                          if (widget.kind != 'daily_summary')
                            const DropdownMenuItem(
                              value: 'call_review',
                              child: Text('Call escalation for owner review'),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _channel = v!),
                      ),
                      if (!_email)
                        _help(
                          'Creates an owner review item. No outbound calls are placed.',
                        ),
                    ],
                    if (_email) ...[
                      _gap(),
                      TextFormField(
                        initialValue: _start,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Send after (HH:MM)',
                        ),
                        onChanged: (v) => setState(() => _start = v),
                        validator: (v) => _validTime(v) ? null : 'Use HH:MM',
                      ),
                      _gap(),
                      TextFormField(
                        initialValue: _end,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Send before (HH:MM)',
                        ),
                        onChanged: (v) => setState(() => _end = v),
                        validator: (v) =>
                            _validTime(v) && _start.compareTo(v!) < 0
                            ? null
                            : 'End after start',
                      ),
                    ],
                    _gap(),
                    TextFormField(
                      controller: _limit,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maximum follow-ups per day (1–50)',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => _number(v, 1, 50),
                    ),
                    _gap(),
                  ],
                ),
                if (_email)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Email preview'),
                    children: [
                      _help(
                        'Names and dates are filled from Workforce records.',
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          _preview({
                            'kind': widget.kind,
                            'instructions': _instructions.text.trim(),
                          }, _memberName),
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ),
                      _gap(),
                    ],
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
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
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving…'
                : _editing
                ? 'Save changes'
                : 'Save paused',
          ),
        ),
      ],
    ),
  );
}

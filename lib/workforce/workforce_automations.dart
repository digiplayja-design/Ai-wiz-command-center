import 'dart:async';
import 'package:flutter/material.dart';
import 'workforce_client.dart';
import 'workforce_style.dart';

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
  String _history = 'all';
  Timer? _poll;
  String get _base => '/${widget.orgId}/automations';
  List<WfJson> get _rules => wfRows(_data?['rules']);
  List<WfJson> get _jobs => wfRows(_data?['jobs']);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await widget.client.request('GET', _base);
      List<WfJson> recipients = [];
      try {
        recipients = wfRows(
          (await widget.client.request(
            'GET',
            '/${widget.orgId}/email-recipients',
          ))['recipients'],
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          _data = data;
          _recipients = recipients;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (e is WorkforceException && [401, 403].contains(e.status)) {
            _data = null;
            _recipients = [];
          }
        });
      }
    } finally {
      _loading = false;
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
        : '${r['displayName'] ?? r['display_name'] ?? ''} <${r['email']}>';
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

  Future<void> _new(String kind) async {
    _dialog = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AutomationForm(
        client: widget.client,
        path: _base,
        kind: kind,
        members: widget.members,
        recipients: _recipients,
        timezone: widget.timezone,
      ),
    );
    _dialog = false;
    if (mounted) await _load();
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
          const Text(
            'NOVA AUTOMATIONS',
            style: TextStyle(
              color: WfStyle.cyan,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
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
        'Thoughtful reminders and a clear morning summary. Set the rules once; NOVA follows up while you focus on your team.',
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
          '*Latest 100 activity records. Accepted means the email provider accepted it; delivery is tracked in NOVA Email Center.',
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
                    _data!['email_ready'] == true
                        ? 'Email Autopilot ready'
                        : 'Email setup needed',
                    color: _data!['email_ready'] == true
                        ? WfStyle.cyan
                        : WfStyle.gold,
                    dot: true,
                  ),
                  const WfBadge('Server scheduling', color: WfStyle.violet),
                ],
              ),
              const SizedBox(height: 12),
              _text(
                _data!['reason']?.toString() ??
                    'Your NOVA Email Center recipient permissions, quiet hours, and daily sending limits apply to every email.',
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
        const SizedBox(height: 30),
        const Text(
          'Start with a recipe',
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
                        r['channel'] == 'email' ? 'Email' : 'Call review',
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
                    r['channel'] == 'email'
                        ? 'To: ${_recipient(r['recipient_id'])}'
                        : 'Destination: owner’s call review queue',
                  ),
                  if (r['last_error'] != null)
                    _text(
                      'NOVA could not check this automation. Refresh or review its settings.',
                      color: WfStyle.gold,
                    ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            (r['enabled'] != true &&
                                (_data!['active_plan'] != true ||
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
          'Activity & call reviews',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {
              'all': 'All activity',
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
              'No activity here yet. NOVA checks enabled automations approximately every minute.',
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
                      'Review the rule and delivery details in NOVA Email Center. A new send has not been assumed safe.',
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
          'Pause stops queued work. An email already handed to the provider cannot be recalled. Automations follow workspace time (${widget.timezone}); NOVA Email Center may defer emails outside its sending window.',
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

String _preview(WfJson r, String member) => switch (r['kind']) {
  'daily_summary' =>
    '[Workspace] — Workforce report\n[Previous calendar date] ([Workspace timezone])\n\n[Recorded shifts and full-shift hours overlapping that date]\n[Employee-reported quantities, work updates and blockers]\n[Pending correction count]\n\nWork quantities are employee-reported. Timesheets require manager review.',
  'missed_shift' =>
    '[Workspace]\nNo clock-in is recorded for ${member == 'All active team members' ? '[Employee]' : member}’s scheduled shift starting [scheduled time].\n\nPlease check in through Workforce or contact your employer if plans have changed. This alert is based on attendance records; it does not establish an absence.',
  _ =>
    '[Workspace]\n${member == 'All active team members' ? '[Employee]' : member} has a work update due.\n\nPlease open Workforce → My day and record completed work, quantities, and any blockers.\nThis reminder reflects recorded updates, not a judgement of productivity.',
};

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
    final email = widget.rule['channel'] == 'email';
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
                '${_preview(widget.rule, widget.member)}${email ? '\n\nSent by NOVA for your approved Workforce automation. Open KORLIX Workforce to review the records.' : ''}',
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
                      ? 'I approve recurring emails with this scope, recipient and timing.'
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
  });
  final WorkforceClient client;
  final String path, kind, timezone;
  final List<WfJson> members, recipients;
  @override
  State<_AutomationForm> createState() => _AutomationFormState();
}

class _AutomationFormState extends State<_AutomationForm> {
  final _form = GlobalKey<FormState>();
  final _id = wfId();
  late final TextEditingController _name;
  final _delay = TextEditingController(text: '10'),
      _limit = TextEditingController(text: '5');
  String _channel = 'email', _member = '', _recipient = '', _time = '08:00';
  final Set<int> _days = {1, 2, 3, 4, 5};
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _kinds[widget.kind]!.$1);
    if (widget.kind == 'daily_summary') _limit.text = '1';
  }

  @override
  void dispose() {
    _name.dispose();
    _delay.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      setState(() => _error = 'Choose at least one weekday.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        widget.path,
        body: {
          'id': _id,
          'name': _name.text.trim(),
          'kind': widget.kind,
          'channel': _channel,
          'member_id': _member.isEmpty ? null : _member,
          'recipient_id': _channel == 'email' ? _recipient : null,
          'delay_minutes': int.parse(_delay.text),
          'local_time': _time,
          'days': _days.toList()..sort(),
          'daily_limit': int.parse(_limit.text),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  Widget _gap() => const SizedBox(height: 18);
  String? _number(String? v, int low, int high) {
    final n = int.tryParse(v ?? '');
    return n == null || n < low || n > high ? 'Enter $low–$high' : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_kinds[widget.kind]!.$1),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saved paused. You will review and enable it separately.',
                  style: TextStyle(color: WfStyle.muted, fontSize: 13),
                ),
                _gap(),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Automation name',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name' : null,
                ),
                _gap(),
                DropdownButtonFormField<String>(
                  initialValue: _channel,
                  decoration: const InputDecoration(
                    labelText: 'Follow-up action',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: 'email',
                      child: Text('Automatic email'),
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
                _gap(),
                if (_channel == 'email') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _recipient.isEmpty ? null : _recipient,
                    decoration: const InputDecoration(
                      labelText: 'Approved email recipient',
                    ),
                    isExpanded: true,
                    items: [
                      for (final r in widget.recipients.where(
                        (r) =>
                            r['active'] == true &&
                            !['unsubscribed', 'suppressed'].contains(
                              r['consentStatus'] ?? r['consent_status'],
                            ),
                      ))
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
                  const SizedBox(height: 8),
                  const Text(
                    'Add or approve recipients in NOVA Email Center. Choose an employer for a team-wide summary, or the employee for their own reminder.',
                    style: TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                  _gap(),
                ] else ...[
                  const Text(
                    'Creates an item in your review queue. Automatic outbound calling is not enabled.',
                    style: TextStyle(color: WfStyle.gold, fontSize: 13),
                  ),
                  _gap(),
                ],
                if (widget.kind != 'daily_summary') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _member,
                    decoration: const InputDecoration(
                      labelText: 'Whose records should trigger this?',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All active team members'),
                      ),
                      for (final m in widget.members.where(
                        (m) => m['active'] == true,
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
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: widget.kind == 'missed_update'
                          ? 'Extra minutes after the policy grace period'
                          : 'Minutes after the scheduled start',
                    ),
                    validator: (v) => _number(v, 0, 240),
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
                  const Text(
                    'Summarises the previous calendar day. If the server resumes late, it catches up within six hours of this time.',
                    style: TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                  _gap(),
                ],
                const Text(
                  'Active weekdays',
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
                TextFormField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum follow-ups per day (1–50)',
                  ),
                  validator: (v) => _number(v, 1, 50),
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save paused'),
        ),
      ],
    ),
  );
}

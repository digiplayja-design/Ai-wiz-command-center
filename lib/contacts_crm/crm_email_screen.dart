import 'dart:async';
import 'package:flutter/material.dart';
import 'contacts_client.dart';
import 'contacts_style.dart';
import 'contact_editor.dart';

class CrmEmailScreen extends StatefulWidget {
  const CrmEmailScreen({
    super.key,
    required this.client,
    this.contact,
    this.draft,
  });
  final ContactsClient client;
  final CrmJson? contact, draft;
  @override
  State<CrmEmailScreen> createState() => _CrmEmailScreenState();
}

class _CrmEmailScreenState extends State<CrmEmailScreen> {
  CrmJson _state = {};
  bool _loading = true, _busy = false, _locked = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_load(initial: true));
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    setState(() {
      _locked = true;
      _state = {};
    });
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final s = await widget.client.request('GET', '/email');
      if (!mounted || _locked) return;
      setState(() {
        _state = s;
        _loading = false;
        _error = null;
      });
      if (initial && widget.contact != null) {
        await _edit(contact: widget.contact, draft: widget.draft);
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, Widget content) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _act(String action, CrmJson row, {bool? enabled}) async {
    if (action == 'toggle' &&
        enabled == true &&
        !await _confirm(
          'Enable this follow-up?',
          Text(
            '${row['contact_name']} · ${row['email']}\n\n${row['delivery_mode'] == 'automatic' ? 'Send automatically' : 'Prepare a draft for approval'} on the contact’s follow-up date. Sending window: ${row['send_hour']}:00–${(row['send_hour'] as int) + 4}:00 ${row['timezone']}.\n\nSubject: ${row['subject']}\n\n${row['body']}\n\nOnly transactional follow-ups for an existing request.',
          ),
        )) {
      return;
    }
    if (!mounted || _locked) return;
    await _run(() async {
      await widget.client.request(
        'POST',
        '/email/actions',
        body: {
          'action': action,
          'id': row['id'],
          'version': row['version'],
          'enabled': ?enabled,
          'confirmed': true,
        },
      );
      await _load();
    });
  }

  Future<void> _edit({CrmJson? rule, CrmJson? contact, CrmJson? draft}) async {
    if (_locked) return;
    contact ??= rule == null
        ? await showDialog<CrmJson>(
            context: context,
            builder: (_) => _ContactPicker(client: widget.client),
          )
        : crmMap(
            (await widget.client.request(
              'GET',
              '/${rule['contact_id']}',
            ))['contact'],
          );
    if (!mounted || _locked || contact == null) return;
    rule ??= crmRows(
      _state['rules'],
    ).where((r) => r['contact_id'] == contact!['id']).firstOrNull;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CrmEmailEditor(
        client: widget.client,
        contact: contact!,
        rule: rule,
        draft: draft,
      ),
    );
    if (saved == true && mounted && !_locked) await _load();
  }

  Future<void> _review(CrmJson job) async {
    final approve = await _confirm(
      'Review follow-up email',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('To: ${job['recipient']}'),
          Text(
            'Reply to: ${crmMap(_state['capabilities'])['reply_to'] ?? 'Your verified account email'}',
          ),
          const SizedBox(height: 12),
          Text(
            '${job['subject']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SelectableText('${job['body']}'),
          const SizedBox(height: 12),
          const Text(
            'KORLIX adds a sender reply address and stop-emails link. Confirm queues this exact message for the sending window.',
          ),
        ],
      ),
    );
    if (approve && mounted && !_locked) await _act('approve', job);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: CrmStyle.theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('CRM · Autonomous email'),
          actions: [
            IconButton(
              tooltip: 'Refresh email status',
              onPressed: _busy || _locked ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: _locked
              ? const Center(child: Text('Reopen CRM after signing in.'))
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            CrmStyle.violet.withValues(alpha: .18),
                            CrmStyle.cyan.withValues(alpha: .06),
                          ],
                        ),
                        border: Border.all(color: CrmStyle.line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stay in touch. Stay in control.',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Personal follow-ups on your contacts’ follow-up dates. Choose approval first or automatic sending. Each contact/date sends at most once.',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Due dates up to 7 days ago are included. A 4-hour sending window uses your chosen timezone. Limit: 100 emails per account in 24 hours.',
                            style: TextStyle(
                              color: CrmStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => _edit()),
                                icon: const Icon(Icons.add),
                                label: const Text('New follow-up'),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        await widget.client.request(
                                          'POST',
                                          '/email/actions',
                                          body: {'action': 'pause_all'},
                                        );
                                        await _load();
                                      }),
                                child: const Text('Pause all'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: CrmStyle.danger),
                        ),
                      ),
                    if (crmMap(_state['capabilities'])['ready'] != true)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '${crmMap(_state['capabilities'])['reason'] ?? 'Save a paused rule while email delivery is being configured.'}',
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Follow-up rules',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (crmRows(_state['rules']).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No rules yet. Choose a contact and write your first follow-up. It will start paused.',
                        ),
                      ),
                    for (final r in crmRows(_state['rules']))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['contact_name']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${r['email'] ?? 'Email needed'} · ${r['follow_up_on'] ?? 'Follow-up date needed'}',
                              ),
                              Text('${r['subject']}'),
                              const SizedBox(height: 6),
                              Text(
                                '${r['enabled'] == true ? 'Active' : 'Paused'} · ${r['delivery_mode'] == 'automatic' ? 'Automatic sending' : 'Approval first'} · ${r['send_hour']}:00 ${r['timezone']}',
                                style: const TextStyle(color: CrmStyle.violet),
                              ),
                              if (r['suppressed'] == true)
                                const Text(
                                  'Recipient stopped these emails.',
                                  style: TextStyle(color: CrmStyle.danger),
                                ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => _edit(rule: r)),
                                    child: const Text('Edit message'),
                                  ),
                                  FilledButton(
                                    onPressed:
                                        _busy ||
                                            (r['enabled'] != true &&
                                                (crmMap(
                                                          _state['capabilities'],
                                                        )['ready'] !=
                                                        true ||
                                                    r['suppressed'] == true))
                                        ? null
                                        : () => _act(
                                            'toggle',
                                            r,
                                            enabled: r['enabled'] != true,
                                          ),
                                    child: Text(
                                      r['enabled'] == true ? 'Pause' : 'Enable',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Drafts & delivery history',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Drafts appear when a follow-up becomes due. Status updates on refresh. “Sent” means accepted by the email provider; “Unknown” is never automatically resent.',
                      style: TextStyle(color: CrmStyle.muted, fontSize: 12),
                    ),
                    if (crmRows(_state['jobs']).isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No deliveries yet.'),
                      ),
                    for (final j in crmRows(_state['jobs']))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${j['subject']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text('${j['recipient']} · ${j['follow_up_on']}'),
                              Text(
                                contactLabel('${j['status']}'),
                                style: TextStyle(
                                  color: j['status'] == 'draft'
                                      ? CrmStyle.gold
                                      : CrmStyle.cyan,
                                ),
                              ),
                              if (j['code'] != null)
                                Text(
                                  contactLabel('${j['code']}'),
                                  style: const TextStyle(
                                    color: CrmStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              if (j['status'] == 'draft')
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _review(j),
                                      child: const Text('Review & queue'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _act('cancel', j),
                                      child: const Text('Skip'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class CrmEmailEditor extends StatefulWidget {
  const CrmEmailEditor({
    super.key,
    required this.client,
    required this.contact,
    this.rule,
    this.draft,
  });
  final ContactsClient client;
  final CrmJson contact;
  final CrmJson? rule, draft;
  @override
  State<CrmEmailEditor> createState() => _CrmEmailEditorState();
}

class _CrmEmailEditorState extends State<CrmEmailEditor> {
  late final TextEditingController _subject, _body, _timezone;
  late CrmJson _contact;
  late String _mode;
  late int _hour;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _contact = crmClone(widget.contact);
    _subject = TextEditingController(
      text:
          widget.draft?['subject'] ?? widget.rule?['subject'] ?? 'Following up',
    );
    _body = TextEditingController(
      text:
          widget.draft?['body'] ??
          widget.rule?['body'] ??
          'Hi ${_contact['name']},\n\nI’m following up on your request. Is there anything else you need from us?',
    );
    _timezone = TextEditingController(text: widget.rule?['timezone'] ?? 'UTC');
    _mode = widget.rule?['delivery_mode'] ?? 'review';
    _hour = widget.rule?['send_hour'] ?? 9;
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _editContact() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ContactEditor(
        contact: _contact,
        onSave: (body) async {
          final r = await widget.client.request(
            'PUT',
            '/${_contact['id']}',
            body: {...body, 'version': _contact['version']},
          );
          if (mounted) setState(() => _contact = crmMap(r['contact']));
        },
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        '/email/rules',
        body: {
          'contact_id': _contact['id'],
          'version': widget.rule?['version'],
          'subject': _subject.text,
          'body': _body.text,
          'timezone': _timezone.text.trim(),
          'send_hour': _hour,
          'delivery_mode': _mode,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.rule == null ? 'New follow-up email' : 'Edit follow-up email',
    ),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_contact['name']} · ${_contact['email'] ?? 'Email needed'}',
            ),
            Text(
              'Follow-up: ${_contact['follow_up_on'] ?? 'Choose a date'} · Permission: ${contactLabel('${_contact['email_permission']}')}',
            ),
            TextButton(
              onPressed: _saving ? null : _editContact,
              child: const Text('Edit contact, date or permission'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('crm-email-subject'),
              controller: _subject,
              enabled: !_saving,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('crm-email-body'),
              controller: _body,
              enabled: !_saving,
              maxLines: 7,
              maxLength: 6000,
              decoration: const InputDecoration(labelText: 'Exact message'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                  isExpanded: true,
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Delivery'),
              items: const [
                DropdownMenuItem(
                  value: 'review',
                  child: Text('Approval first'),
                ),
                DropdownMenuItem(
                  value: 'automatic',
                  child: Text('Send automatically'),
                ),
              ],
              onChanged: _saving ? null : (v) => setState(() => _mode = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _timezone,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                hintText: 'America/Jamaica or America/New_York',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
                  isExpanded: true,
              initialValue: _hour,
              decoration: const InputDecoration(
                labelText: 'Sending window starts',
              ),
              items: List.generate(
                21,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text('${i.toString().padLeft(2, '0')}:00'),
                ),
              ),
              onChanged: _saving ? null : (v) => setState(() => _hour = v!),
            ),
            const SizedBox(height: 16),
            const Text(
              'Saving pauses this rule and replaces unsent drafts. Review the message, then enable it from the email screen. A sent follow-up is never repeated for the same date.',
              style: TextStyle(color: CrmStyle.muted, fontSize: 12),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: CrmStyle.danger)),
          ],
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
        child: Text(_saving ? 'Saving…' : 'Save paused'),
      ),
    ],
  );
}

class _ContactPicker extends StatefulWidget {
  const _ContactPicker({required this.client});
  final ContactsClient client;
  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final _q = TextEditingController();
  List<CrmJson> _rows = [];
  String? _error;
  bool _loading = true;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final epoch = ++_epoch;
    setState(() => _loading = true);
    try {
      final r = await widget.client.request(
        'GET',
        '',
        query: {'q': _q.text, 'limit': '25'},
      );
      if (mounted && epoch == _epoch) {
        setState(() {
          _rows = crmRows(r['contacts']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = '$e');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a contact'),
    content: SizedBox(
      width: 500,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: _q,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Search name, email or company',
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Showing up to 25 matches. Search to find another contact.',
            style: TextStyle(fontSize: 12),
          ),
          if (_error != null) Text(_error!),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      for (final c in _rows)
                        ListTile(
                          title: Text('${c['name']}'),
                          subtitle: Text('${c['email'] ?? 'Email needed'}'),
                          onTap: () => Navigator.pop(context, c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

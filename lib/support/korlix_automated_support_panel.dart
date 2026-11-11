import 'dart:async';

import 'package:flutter/material.dart';

import '../live_convo/korlix_live_convo_agent_client.dart';

typedef KorlixSupportRequest = Future<Map<String, dynamic>> Function({
  required String method,
  required String path,
  Map<String, dynamic>? body,
});

const _root = '/api/automated-support';
const _states = <String, String>{
  'new': 'New',
  'waiting_for_customer': 'Waiting for customer',
  'needs_review': 'Needs review',
  'resolved': 'Resolved',
};
const _modes = <String, String>{
  'paused': 'Paused',
  'draft': 'Draft for review',
  'automatic': 'Automatic',
};
const _muted = Color(0xFFA9C6CF);
const _ink = Color(0xFFE4EBEE);
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
    : [];
String _text(Object? value) => (value ?? '').toString().trim();
String _id(Object? value) => Uri.encodeComponent(_text(value));
String _when(Object? value) {
  final date = DateTime.tryParse(_text(value))?.toLocal();
  if (date == null) return 'Time unavailable';
  return '${date.month}/${date.day}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
String _error(Object error) {
  if (error is KorlixLiveConvoAgentClientException) {
    if (error.statusCode == 404) {
      return 'Automated support is awaiting setup for this workspace.';
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'Sign in with an account that manages this support address.';
    }
    if (error.statusCode == 503) {
      return 'Support is temporarily unavailable or its setup is incomplete. '
          'Refresh to check again.';
    }
  }
  return 'Support could not complete this request. Refresh to check the latest '
      'status before trying again.';
}
Future<Map<String, dynamic>> _request(
  KorlixSupportRequest request,
  String path, {
  String method = 'GET',
  Map<String, dynamic>? body,
}) async {
  final result = await request(method: method, path: '$_root$path', body: body);
  if (result['ok'] != true) {
    throw const KorlixLiveConvoAgentClientException(
      'Support information could not be confirmed.',
    );
  }
  return result;
}

Future<T?> _supportDialog<T>({required BuildContext context,
  required VoidCallback assertCurrentAccount, required WidgetBuilder builder}) =>
    showDialog<T>(context: context, builder: (_) => _SupportAccountDialog(
      assertCurrentAccount: assertCurrentAccount, builder: builder));

// Dialogs live on a separate route. Clear their customer text as well when the
// account changes while a reply or resolution is being reviewed.
class _SupportAccountDialog extends StatefulWidget {
  const _SupportAccountDialog({required this.assertCurrentAccount, required this.builder});
  final VoidCallback assertCurrentAccount;
  final WidgetBuilder builder;
  @override
  State<_SupportAccountDialog> createState() => _SupportAccountDialogState();
}
class _SupportAccountDialogState extends State<_SupportAccountDialog> {
  bool _current = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_current) return;
      try { widget.assertCurrentAccount(); } catch (_) {
        if (mounted) setState(() => _current = false);
      }
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    try { widget.assertCurrentAccount(); } catch (_) { _current = false; }
    if (_current) return widget.builder(context);
    return AlertDialog(title: const Text('Your account changed'),
      content: const Text('Close this conversation and reopen support with your current account.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]);
  }
}

/// Uses account-scoped Email Center requests. Sender enrollment remains on the
/// server: this screen cannot change ownership, sender identity, or recipients.
class KorlixAutomatedSupportPanel extends StatefulWidget {
  const KorlixAutomatedSupportPanel({
    super.key,
    required this.request,
    required this.assertCurrentAccount,
    this.accent = const Color(0xFF80E2EC),
  });
  final KorlixSupportRequest request;
  final VoidCallback assertCurrentAccount;
  final Color accent;

  @override
  State<KorlixAutomatedSupportPanel> createState() => _SupportPanelState();
}

class _SupportPanelState extends State<KorlixAutomatedSupportPanel> {
  List<Map<String, dynamic>> _profiles = [], _cases = [];
  String _profileId = '', _filter = '', _query = '';
  String? _failure;
  bool _loading = true, _busy = false, _expired = false;
  int _revision = 0;
  Timer? _scopeWatch;

  Map<String, dynamic> get _profile => _profiles.firstWhere(
    (profile) => _text(profile['id']) == _profileId,
    orElse: () => {},
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _scopeWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expired) return;
      try {
        widget.assertCurrentAccount();
      } catch (_) {
        _revision++;
        if (mounted) setState(() {
          _expired = true;
          _profiles = [];
          _cases = [];
          _loading = false;
          _busy = false;
          _failure = 'Your account changed. Close and reopen Email Center.';
        });
      }
    });
  }

  @override
  void dispose() {
    _scopeWatch?.cancel();
    super.dispose();
  }

  Future<void> _load({bool profiles = true}) async {
    if (_busy || _expired) return;
    final revision = ++_revision;
    setState(() { _loading = true; _failure = null; _cases = []; });
    try {
      widget.assertCurrentAccount();
      if (profiles) {
        final response = await _request(widget.request, '/profiles');
        if (!mounted || revision != _revision) return;
        _profiles = _rows(response['profiles']);
        if (_profile.isEmpty) _profileId = _profiles.isEmpty ? '' : _text(_profiles.first['id']);
      }
      if (_profileId.isNotEmpty) {
        final response = await _request(widget.request,
          '/cases?profileId=${_id(_profileId)}${_filter.isEmpty ? '' : '&state=$_filter'}');
        if (!mounted || revision != _revision) return;
        _cases = _rows(response['cases']).where(
          (row) => _text(row['profileId']) == _profileId,
        ).toList();
      }
      widget.assertCurrentAccount();
    } catch (error) {
      if (!mounted || revision != _revision) return;
      _cases = [];
      _failure = _error(error);
      if (profiles) _profiles = [];
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _changeMode(String mode) async {
    final profile = _profile;
    if (_busy || profile.isEmpty || (mode == 'automatic' && profile['ready'] != true)) return;
    if (mode == 'automatic') {
      final accepted = await _supportDialog<bool>(context: context, assertCurrentAccount: widget.assertCurrentAccount, builder: (context) => AlertDialog(
        title: const Text('Enable automatic support?'),
        content: Text('New eligible reports can receive responses from ${_text(profile['fromEmail'])} '
          'within this profile’s sending limits.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable'))],
      ));
      if (accepted != true || !mounted) return;
    }
    setState(() { _busy = true; _failure = null; });
    try {
      await _request(widget.request, '/profiles/${_id(profile['id'])}',
        method: 'PATCH', body: {'mode': mode});
      if (!mounted) return;
      _busy = false;
      await _load();
    } catch (error) {
      if (mounted) setState(() => _failure = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> entry) async {
    if (_busy || _expired) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _SupportCaseScreen(
      request: widget.request, assertCurrentAccount: widget.assertCurrentAccount,
      caseId: _text(entry['id']), profile: Map.of(_profile), accent: widget.accent,
    )));
    if (mounted) unawaited(_load(profiles: false));
  }

  Widget _notice(String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(children: [Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.5))]),
  );

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final words = _query.toLowerCase().trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final visible = _cases.where((row) {
      final haystack = '${row['subject']} ${row['reporterEmail']} ${row['details']}'.toLowerCase();
      return words.every(haystack.contains);
    }).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [const Expanded(child: Text('Automated Support', style: TextStyle(color: _ink, fontSize: 23, fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'Refresh support', onPressed: _busy || _loading || _expired ? null : () => unawaited(_load()),
          icon: Icon(Icons.refresh, color: widget.accent))]),
      const Text('Helpful first responses, with every conversation kept under its support address.',
        style: TextStyle(color: _muted, height: 1.5)),
      if (_failure != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_failure!, style: const TextStyle(color: Color(0xFFFFB4AB)))),
      if (_profiles.isNotEmpty) ...[
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('support-profile-$_profileId'),
          initialValue: _profileId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Support address', border: OutlineInputBorder()),
          items: _profiles.map((p) => DropdownMenuItem(value: _text(p['id']),
            child: Text('${_text(p['displayName'])} · ${_text(p['fromEmail'])}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy || _loading ? null : (value) {
            if (value == null) return;
            setState(() { _profileId = value; _cases = []; });
            unawaited(_load(profiles: false));
          },
        ),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF142638), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customers receive emails from', style: TextStyle(color: _muted, fontSize: 11)),
            SelectableText(_text(profile['fromEmail']), style: const TextStyle(color: _ink)),
            const SizedBox(height: 10), const Text('Customer replies go to', style: TextStyle(color: _muted, fontSize: 11)),
            SelectableText(_text(profile['replyTo']), style: const TextStyle(color: _ink)),
            const SizedBox(height: 12),
            Text(profile['ready'] == true ? 'Sending and replies are ready.' : 'Complete address setup before enabling automatic replies.', style: const TextStyle(color: _muted)),
            if (profile['dailyCap'] != null) Text('Up to ${profile['dailyCap']} support emails per day.', style: const TextStyle(color: _muted, fontSize: 12)),
          ])),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Response mode', border: OutlineInputBorder()),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: _modes.containsKey(profile['mode']) ? profile['mode'] as String : 'paused',
            isExpanded: true,
            items: _modes.entries.map((mode) => DropdownMenuItem(value: mode.key,
              enabled: mode.key != 'automatic' || profile['ready'] == true,
              child: Text(mode.value))).toList(),
            onChanged: _busy || _loading ? null : (value) { if (value != null) unawaited(_changeMode(value)); },
          )),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: {'': 'All cases', ..._states}.entries.map((item) => ChoiceChip(
          label: Text(item.value), selected: _filter == item.key,
          onSelected: _loading || _busy ? null : (_) { setState(() => _filter = item.key); unawaited(_load(profiles: false)); },
        )).toList()),
        const SizedBox(height: 14),
        TextField(onChanged: (value) => setState(() => _query = value),
          style: const TextStyle(color: _ink),
          decoration: const InputDecoration(labelText: 'Search loaded cases', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
      ],
      if (_loading) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
      else if (_failure != null) const SizedBox.shrink()
      else if (_profiles.isEmpty) _notice('No support addresses are enrolled yet.', 'Each enrolled address has its own settings and customer conversations.')
      else if (visible.isEmpty) _notice('No cases in this view.', 'Choose another status or search.')
      else ...visible.map((entry) => Card(color: const Color(0xFF142638), margin: const EdgeInsets.only(top: 12), child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(_text(entry['subject']).isEmpty ? 'Customer report' : _text(entry['subject']), style: const TextStyle(color: _ink, fontWeight: FontWeight.bold)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_text(entry['reporterEmail'])}\n${_states[entry['state']] ?? 'Needs review'}${entry['automationPaused'] == true ? ' · Automation paused' : ''}\n${_when(entry['updatedAt'])}', style: const TextStyle(color: _muted, height: 1.6))),
        trailing: Icon(Icons.chevron_right, color: widget.accent), onTap: () => unawaited(_open(entry)),
      ))),
      const SizedBox(height: 12),
      const Text('The list shows the most recent cases returned by the support service.', style: TextStyle(color: _muted, fontSize: 11)),
    ]);
  }
}

class _SupportCaseScreen extends StatefulWidget {
  const _SupportCaseScreen({required this.request, required this.assertCurrentAccount,
    required this.caseId, required this.profile, required this.accent});
  final KorlixSupportRequest request;
  final VoidCallback assertCurrentAccount;
  final String caseId;
  final Map<String, dynamic> profile;
  final Color accent;
  @override
  State<_SupportCaseScreen> createState() => _SupportCaseState();
}

class _SupportCaseState extends State<_SupportCaseScreen> {
  Map<String, dynamic> _case = {};
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true, _busy = false, _expired = false;
  String? _notice;
  final _reply = TextEditingController();
  Timer? _scopeWatch;
  bool get _canReply => widget.profile['ready'] == true &&
      _case['reporterVerified'] == true && _case['state'] != 'resolved';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _scopeWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expired) return;
      try { widget.assertCurrentAccount(); } catch (_) {
        if (mounted) setState(() {
          _expired = true; _case = {}; _messages = []; _reply.clear();
          _loading = false; _busy = false; _notice = 'Your account changed. Close this conversation.';
        });
      }
    });
  }
  @override
  void dispose() { _scopeWatch?.cancel(); _reply.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final result = await _request(widget.request, '/cases/${_id(widget.caseId)}');
      widget.assertCurrentAccount();
      if (!mounted || _expired) return;
      final row = _map(result['case']);
      if (row['profileId'] != widget.profile['id']) throw StateError('Support profile changed.');
      setState(() { _case = row; _messages = _rows(result['messages']); _loading = false; });
    } catch (error) {
      if (mounted && !_expired) setState(() { _case = {}; _messages = []; _loading = false; _notice = _error(error); });
    }
  }

  Future<void> _mutate(Map<String, dynamic> body, {bool reply = false}) async {
    if (_busy || _expired) return;
    setState(() { _busy = true; _notice = null; });
    try {
      await _request(widget.request, '/cases/${_id(widget.caseId)}${reply ? '/replies' : ''}',
        method: reply ? 'POST' : 'PATCH', body: body);
      widget.assertCurrentAccount();
      if (!mounted || _expired) return;
      if (reply) _reply.clear();
      await _load();
      if (mounted && !_expired) setState(() => _notice = reply
        ? 'Reply recorded. Check its message status for sending progress.' : 'Case updated.');
    } catch (error) {
      if (mounted && !_expired) setState(() => _notice = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status(String value) async {
    String note = '';
    if (value == 'resolved') {
      final controller = TextEditingController();
      final result = await _supportDialog<String>(context: context, assertCurrentAccount: widget.assertCurrentAccount, builder: (context) => AlertDialog(
        title: const Text('Confirm the resolution'),
        content: TextField(controller: controller, maxLength: 2000, maxLines: 4,
          decoration: const InputDecoration(hintText: 'What confirmed that the issue is resolved?')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim()); }, child: const Text('Mark resolved'))],
      ));
      controller.dispose();
      if (result == null || result.isEmpty || !mounted) return;
      note = result;
    }
    await _mutate({'state': value, if (value == 'resolved') 'resolutionNote': note});
  }

  Future<void> _reviewReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || text.length > 12000 || !_canReply) return;
    final accepted = await _supportDialog<bool>(context: context, assertCurrentAccount: widget.assertCurrentAccount, builder: (context) => AlertDialog(
      title: const Text('Review support reply'),
      content: SingleChildScrollView(child: SelectableText('From: ${_text(widget.profile['fromEmail'])}\n'
        'To: ${_text(_case['reporterEmail'])}\n\n$text')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Queue reply'))],
    ));
    if (accepted == true && mounted) await _mutate({'text': text, 'confirmed': true}, reply: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080F1B),
    appBar: AppBar(backgroundColor: const Color(0xFF101D30), foregroundColor: _ink,
      title: const Text('Support conversation'), actions: [IconButton(tooltip: 'Refresh conversation',
        onPressed: _busy || _expired ? null : () => unawaited(_load()), icon: const Icon(Icons.refresh))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(20), children: [
        if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_notice!, style: const TextStyle(color: _muted))),
        if (_case.isNotEmpty) ...[
          Text(_text(_case['subject']), style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10), SelectableText(_text(_case['reporterEmail']), style: const TextStyle(color: _muted)),
          const SizedBox(height: 8), Text('Case ${widget.caseId}', style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 16), SelectableText(_text(_case['details']), style: const TextStyle(color: _ink, height: 1.5)),
          const SizedBox(height: 12), Text([_case['appArea'], _case['appVersion'], _case['platform']].map(_text).where((s) => s.isNotEmpty).join(' · '), style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Case status', border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _states.containsKey(_case['state']) ? _case['state'] as String : 'needs_review',
              isExpanded: true,
              items: _states.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
              onChanged: _busy ? null : (value) { if (value != null) unawaited(_status(value)); },
            )),
          ),
          const SizedBox(height: 12), OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_mutate({'automationPaused': _case['automationPaused'] != true})),
            icon: const Icon(Icons.person_outline), label: Text(_case['automationPaused'] == true ? 'Resume case automation' : 'Take over · pause automation')),
          const SizedBox(height: 18),
          ..._messages.map((message) => Container(
            margin: EdgeInsets.only(bottom: 12, left: message['direction'] == 'outbound' ? 16 : 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: message['direction'] == 'outbound' ? const Color(0xFF18383E) : const Color(0xFF142638), borderRadius: BorderRadius.circular(15)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${message['direction'] == 'outbound' ? 'KORLIX support' : 'Customer'} · ${_text(message['status'])}\n${_when(message['createdAt'])}', style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 10), SelectableText(_text(message['text']), style: const TextStyle(color: _ink, height: 1.5)),
              if (_rows(message['attachments']).isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Attachments: ${_rows(message['attachments']).map((item) => _text(item['filename'] ?? item['name'] ?? 'Attachment')).join(', ')}',
                  style: const TextStyle(color: _muted, fontSize: 12))),
              if (message['kind'] == 'acknowledgment' && message['status'] == 'pending')
                TextButton(onPressed: _busy ? null : () => _reply.text = _text(message['text']), child: const Text('Use this draft')),
            ]))),
          if (_messages.isEmpty) const Text('No email messages recorded yet.', style: TextStyle(color: _muted)),
          const SizedBox(height: 18),
          TextField(controller: _reply, maxLength: 12000, minLines: 4, maxLines: 9,
            enabled: !_busy,
            style: const TextStyle(color: _ink),
            decoration: InputDecoration(labelText: 'Reply to ${_text(_case['reporterEmail'])}', border: const OutlineInputBorder())),
          FilledButton.icon(onPressed: _busy || !_canReply ? null : () => unawaited(_reviewReply()),
            icon: const Icon(Icons.mail_outline), label: const Text('Review reply')),
          if (!_canReply) Padding(padding: const EdgeInsets.only(top: 12), child: Text(
            _case['state'] == 'resolved' ? 'Reopen this case before replying.'
              : _case['reporterVerified'] != true ? 'The customer’s email needs verification before replying.'
              : 'This support address needs setup before replies can be sent.', style: const TextStyle(color: _muted))),
        ],
      ],
    ),
  );
}

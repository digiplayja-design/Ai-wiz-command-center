import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'directory_client.dart';
import 'directory_style.dart';

class ReceptionistScreen extends StatefulWidget {
  const ReceptionistScreen({
    super.key,
    required this.client,
    required this.businessId,
    this.openScheduling,
  });
  final DirectoryClient client;
  final String businessId;
  final Future<void> Function()? openScheduling;
  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen> {
  final _greeting = TextEditingController(),
      _knowledge = TextEditingController(),
      _language = TextEditingController(text: 'English'),
      _monthly = TextEditingController(text: '120'),
      _duration = TextEditingController(text: '5'),
      _question = TextEditingController();
  DirJson _data = {};
  final List<DirJson> _conversation = [];
  Set<String> _events = {};
  bool _busy = false,
      _loaded = false,
      _locked = false,
      _enabled = false,
      _booking = false,
      _consent = false,
      _dirty = false,
      _upgrade = false;
  String _voice = 'coral';
  String? _error, _notice;
  String get _path => '/owner/${widget.businessId}/receptionist';
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
    _run(_load);
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    for (final c in [
      _greeting,
      _knowledge,
      _language,
      _monthly,
      _duration,
      _question,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    setState(() {
      _locked = true;
      _data = {};
      _conversation.clear();
      for (final c in [_greeting, _knowledge, _language, _question]) {
        c.clear();
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = e.toString();
          if (e is DirectoryException && e.status == 402) _upgrade = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final d = await widget.client.request('GET', _path);
    if (!mounted || _locked) return;
    final s = dirMap(d['settings']);
    setState(() {
      _data = d;
      _loaded = true;
      _upgrade = false;
      _enabled = s['enabled'] == true;
      _booking = s['booking_enabled'] == true;
      _consent = s['processing_consent'] == true;
      _voice = s['voice']?.toString() ?? 'coral';
      _greeting.text = s['greeting']?.toString() ?? '';
      _knowledge.text = s['knowledge']?.toString() ?? '';
      _language.text = s['language']?.toString() ?? 'English';
      _monthly.text = (s['monthly_minutes'] ?? 120).toString();
      _duration.text = (s['max_call_minutes'] ?? 5).toString();
      _events = Set<String>.from(s['event_ids'] ?? []);
      final availableIds = dirRows(d['events'])
          .where((e) => e['price_cents'] == 0)
          .map((e) => e['id'].toString())
          .toSet();
      final removed = _events.difference(availableIds).isNotEmpty;
      _events = _events.intersection(availableIds);
      if (removed && _events.isEmpty) _booking = false;
      _dirty = removed;
      if (removed) {
        _notice =
            'An appointment type is no longer available. Review and save your booking settings.';
      }
    });
  }

  Future<void> _save() async {
    await widget.client.request(
      'POST',
      _path,
      body: {
        'version': _data['version'] ?? 0,
        'enabled': _enabled,
        'booking_enabled': _booking,
        'greeting': _greeting.text.trim(),
        'knowledge': _knowledge.text.trim(),
        'language': _language.text.trim(),
        'voice': _voice,
        'monthly_minutes': int.tryParse(_monthly.text),
        'max_call_minutes': int.tryParse(_duration.text),
        'event_ids': _events.toList(),
        'processing_consent': _consent,
      },
    );
    await _load();
    if (mounted && !_locked) {
      setState(() => _notice = 'Receptionist settings saved.');
    }
  }

  Future<void> _preview() async {
    final question = _question.text.trim();
    if (question.isEmpty) return;
    if (_dirty) {
      throw const DirectoryException(
        'Save your settings before testing the receptionist.',
      );
    }
    if (!_consent) {
      throw const DirectoryException(
        'Review AI processing and save your permission before testing.',
      );
    }
    final previous = [..._conversation];
    final history = [
      ...previous,
      {'role': 'user', 'content': question},
    ];
    final result = await widget.client.request(
      'POST',
      '$_path/preview',
      body: {'messages': history, 'processing_consent': true},
      timeout: const Duration(seconds: 150),
    );
    if (!mounted || _locked) return;
    setState(() {
      _conversation
        ..clear()
        ..addAll([
          ...history,
          {'role': 'assistant', 'content': result['reply'] ?? ''},
        ]);
      if (_conversation.length > 20) {
        _conversation.removeRange(0, _conversation.length - 20);
      }
      _question.clear();
    });
  }

  Future<void> _connect() async {
    final d = await widget.client.request('GET', '$_path/lines');
    if (!mounted || _locked) return;
    final lines = dirRows(d['lines']);
    if (lines.isEmpty) {
      throw const DirectoryException(
        'There are no unused business phone lines available. Contact KORLIX support to arrange a line.',
      );
    }
    final selected = await showDialog<DirJson>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Connect an unused phone line'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              'Incoming calls to the number you choose will use this business’s receptionist.',
            ),
          ),
          for (final line in lines)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, line),
              child: Text(line['number'].toString()),
            ),
        ],
      ),
    );
    if (selected == null || !mounted || _locked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Connect ${selected['number']}?'),
        content: Text(
          'Use this line for ${_data['business_name']}. Enable the receptionist after you have reviewed its answers and call limits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Connect number'),
          ),
        ],
      ),
    );
    if (confirmed != true || _locked) return;
    await widget.client.request(
      'POST',
      '$_path/line',
      body: {'phone_id': selected['id'], 'confirmed': true},
    );
    await _load();
  }

  Widget _panel(String title, IconData icon, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.only(bottom: 18),
        decoration: DirectoryVisuals.panel(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: DirectoryVisuals.cyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );
  Widget _field(
    String label,
    TextEditingController c, {
    int lines = 1,
    int max = 400,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: c,
      enabled: !_busy,
      minLines: lines,
      maxLines: lines,
      maxLength: max,
      keyboardType: keyboard,
      onChanged: (_) => setState(() => _dirty = true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  String _callTime(dynamic value) {
    final t = DateTime.tryParse(value?.toString() ?? '');
    if (t == null) return '';
    final local = t.toLocal();
    return '${local.month}/${local.day}/${local.year} · ${TimeOfDay.fromDateTime(local).format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Receptionist')),
        body: const Center(
          child: Text('Sign in again and reopen your receptionist.'),
        ),
      );
    }
    final line = dirMap(_data['line']);
    final available = dirRows(
      _data['events'],
    ).where((e) => (e['price_cents'] ?? 0) == 0).toList();
    final status = switch (_data['setupStatus']) {
      'ready' => 'Ready for incoming calls',
      'paused' => 'Receptionist paused',
      'connect_phone' => 'Phone connection needed',
      'publish_passport' => 'Publish your Passport first',
      _ => 'Finish your setup',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Receptionist'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : () => _run(_load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: DirectoryVisuals.panel(context, colorful: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.support_agent_rounded,
                              size: 34,
                              color: DirectoryVisuals.cyan,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'K-NOVA · ENTERPRISE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'A warm welcome.\nEven when you’re busy.',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _data['business_name']?.toString() ??
                              'Your business receptionist',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Answer questions, capture customer requests and book available appointments through KORLIX 2MEETU.',
                        ),
                        if (_loaded) ...[
                          const SizedBox(height: 18),
                          Chip(
                            avatar: Icon(
                              _data['setupStatus'] == 'ready'
                                  ? Icons.check_circle_outline
                                  : Icons.tune,
                              size: 18,
                            ),
                            label: Text(status),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          LinearProgressIndicator(),
                          SizedBox(height: 8),
                          Text('K-Nova is working…'),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _notice!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (_upgrade)
                    _panel(
                      'Available with Enterprise',
                      Icons.workspace_premium_outlined,
                      [
                        const Text(
                          'AI Receptionist is an Enterprise business tool. Your Business Passport and listing remain free. Upgrade from your KORLIX account to configure a receptionist.',
                        ),
                      ],
                    ),
                  if (_loaded) ...[
                    const SizedBox(height: 20),
                    _panel(
                      '1. Give your business a voice',
                      Icons.record_voice_over_outlined,
                      [
                        const Text(
                          'K-Nova introduces itself as your AI receptionist. Add a short welcome and customer-facing answers you have approved.',
                        ),
                        _field(
                          'Welcome after the AI introduction',
                          _greeting,
                          max: 400,
                          lines: 2,
                        ),
                        _field(
                          'Approved answers, services, prices and policies',
                          _knowledge,
                          max: 8000,
                          lines: 6,
                        ),
                        const Text(
                          'Your published Passport supplies business details. Keep these answers factual and customer-facing; leave out passwords and private company information.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _voice,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Voice',
                            border: OutlineInputBorder(),
                          ),
                          items: dirRows(_data['voices'])
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v['id'].toString(),
                                  child: Text(v['name'].toString()),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _voice = v ?? 'coral';
                                  _dirty = true;
                                }),
                        ),
                        _field('Preferred language', _language, max: 80),
                      ],
                    ),
                    _panel(
                      '2. Choose what callers can book',
                      Icons.event_available_outlined,
                      [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Book appointments during calls'),
                          subtitle: const Text(
                            'K-Nova checks availability and asks the caller to confirm before reserving.',
                          ),
                          value: _booking,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _booking = v;
                                  _dirty = true;
                                }),
                        ),
                        if (available.isEmpty)
                          const Text(
                            'Create and publish an appointment type in KORLIX 2MEETU to offer phone bookings. Appointments requiring online payment use your public booking page.',
                          ),
                        for (final event in available)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _events.contains(event['id']),
                            title: Text(event['title'].toString()),
                            subtitle: Text(
                              '${event['duration_minutes']} minutes',
                            ),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      _events.add(event['id'].toString());
                                    } else {
                                      _events.remove(event['id']);
                                    }
                                    _dirty = true;
                                  }),
                          ),
                        if (widget.openScheduling != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await widget.openScheduling!();
                                      await _load();
                                    }),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open KORLIX 2MEETU'),
                            ),
                          ),
                      ],
                    ),
                    _panel('3. Set your limits and activate', Icons.tune_rounded, [
                      Text(
                        line['number'] != null
                            ? 'Business line: ${line['number']}'
                            : 'Connect a dedicated business line to receive calls.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (line['number'] == null) ...[
                        const SizedBox(height: 8),
                        if (_data['isAdmin'] == true &&
                            _data['phoneConnectionReady'] == true)
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _run(_connect),
                            icon: const Icon(Icons.add_call),
                            label: const Text('Connect phone line'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(
                              Uri(
                                scheme: 'mailto',
                                path: 'support@korlixdeveloper.com',
                                queryParameters: {
                                  'subject':
                                      'KORLIX AI Receptionist phone setup',
                                  'body':
                                      'Please help connect a phone line for ${_data['business_name'] ?? 'my business'}. Business reference: ${widget.businessId}',
                                },
                              ),
                            ),
                            icon: const Icon(Icons.contact_support_outlined),
                            label: const Text('Arrange phone setup'),
                          ),
                      ],
                      _field(
                        'Monthly phone limit (1–1,200 minutes)',
                        _monthly,
                        max: 4,
                        keyboard: TextInputType.number,
                      ),
                      _field(
                        'Maximum call length (1–10 minutes)',
                        _duration,
                        max: 2,
                        keyboard: TextInputType.number,
                      ),
                      Text(
                        '${((_data['used_seconds'] as num? ?? 0) / 60).ceil()} phone minutes used this month. Calls count toward your existing voice allowance. Your limit can be lower than that allowance.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _consent,
                        title: const Text(
                          'I approve AI call processing for this business',
                        ),
                        subtitle: const Text(
                          'Approved business information, caller audio and conversation text are processed by OpenAI and Vapi, with the connected telephone provider such as Twilio. Callers hear an AI introduction. KORLIX stores call details, requested messages and bookings for your business; it does not store call recordings or full transcripts. Call inbox content is kept for 90 days. Text previews also use OpenAI and your AI allowance.',
                        ),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _consent = v == true;
                                _dirty = true;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable receptionist'),
                        subtitle: Text(
                          line.isEmpty
                              ? 'Save your preferences now; calls become available after phone setup.'
                              : 'K-Nova will answer incoming calls on your connected line.',
                        ),
                        value: _enabled,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _enabled = v;
                                _dirty = true;
                              }),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _run(_save),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save receptionist'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    await widget.client.request(
                                      'POST',
                                      '$_path/pause',
                                    );
                                    await _load();
                                  }),
                            icon: const Icon(Icons.pause_circle_outline),
                            label: const Text('Pause now'),
                          ),
                        ],
                      ),
                      if (_dirty)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'You have unsaved settings.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ]),
                    _panel('Try a customer conversation', Icons.forum_outlined, [
                      const Text(
                        'Test your saved answers before taking calls. This text preview creates no appointments and saves no customer messages.',
                      ),
                      for (final message in _conversation)
                        Align(
                          alignment: message['role'] == 'user'
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 7),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: message['role'] == 'user'
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SelectableText(
                              message['content'].toString(),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _question,
                        enabled: !_busy,
                        maxLength: 1500,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Ask as a customer',
                          hintText: 'What services do you offer?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy || _dirty || !_consent
                                ? null
                                : () => _run(_preview),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Test answer'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _conversation.clear()),
                            child: const Text('Start over'),
                          ),
                        ],
                      ),
                      if (_dirty || !_consent)
                        const Text(
                          'Save your settings and AI processing permission to test.',
                          style: TextStyle(fontSize: 12),
                        ),
                    ]),
                    _panel('Your call inbox', Icons.inbox_outlined, [
                      const Text(
                        'Recent calls, customer messages and confirmed bookings. Only your business can access this inbox.',
                      ),
                      const SizedBox(height: 12),
                      if (dirRows(_data['calls']).isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Column(
                            children: [
                              Icon(Icons.phone_in_talk_outlined, size: 40),
                              SizedBox(height: 10),
                              Text(
                                'Your next customer connection starts here.',
                              ),
                            ],
                          ),
                        ),
                      for (final call in dirRows(_data['calls']))
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dirMap(call['note'])['name']?.toString() ??
                                      call['caller_number']?.toString() ??
                                      'Caller',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${_callTime(call['started_at'])} · ${((call['duration_seconds'] as num? ?? 0) / 60).ceil()} min · ${call['state']}',
                                ),
                                if (call['note'] != null) ...[
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    dirMap(
                                          call['note'],
                                        )['message']?.toString() ??
                                        '',
                                  ),
                                  SelectableText(
                                    [
                                          dirMap(call['note'])['phone'],
                                          dirMap(call['note'])['email'],
                                        ]
                                        .where((v) => v != null && v != '')
                                        .join(' · '),
                                  ),
                                ],
                                if (call['booking'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Booked: ${dirMap(call['booking'])['event_title']}',
                                  ),
                                  Text(
                                    '${_callTime(dirMap(call['booking'])['starts_at'])} (your device time)',
                                  ),
                                ],
                                if (call['handled_at'] != null)
                                  const Text('Handled ✓')
                                else
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() async {
                                            await widget.client.request(
                                              'POST',
                                              '$_path/calls/${call['id']}/handled',
                                            );
                                            await _load();
                                          }),
                                    child: const Text('Mark handled'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

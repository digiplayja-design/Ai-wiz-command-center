import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_templates.dart';
import 'funnel_followups.dart';
import 'funnel_campaigns.dart';

class FunnelScreen extends StatefulWidget {
  const FunnelScreen({super.key, required this.client, this.onOpenContacts});
  final FunnelClient client;
  final Future<void> Function()? onOpenContacts;
  @override
  State<FunnelScreen> createState() => _FunnelScreenState();
}

class _FunnelScreenState extends State<FunnelScreen> {
  List<Map<String, dynamic>> _funnels = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic> _draft = {};
  Map<String, dynamic>? _insights;
  String _name = '', _tab = 'Page', _search = '', _status = 'All';
  String? _error;
  bool _busy = false, _dirty = false, _aiReady = false, _denied = false;
  int _revision = 0;
  final Map<String, String> _tags = {
    'source': '',
    'medium': 'paid',
    'campaign': '',
    'content': '',
    'term': '',
  };
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = () {
      if (mounted) {
        setState(() {
          _denied = true;
          _funnels = [];
          _selected = null;
          _draft = {};
          _insights = null;
        });
      }
    };
    unawaited(_refresh());
  }

  @override
  void dispose() {
    widget.client.onAccessDenied = null;
    widget.client.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    final data = await widget.client.request('GET', '');
    if (!mounted) return;
    setState(() {
      _funnels = (data['funnels'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _aiReady = data['ai_ready'] == true;
      _denied = false;
    });
  });
  void _take(Map<String, dynamic> f) {
    setState(() {
      _selected = f;
      _draft = copyFunnel(f['draft'] as Map);
      _name = f['name'].toString();
      _dirty = false;
      _revision++;
      _insights = null;
      final i = _funnels.indexWhere((x) => x['id'] == f['id']);
      if (i < 0) {
        _funnels.insert(0, f);
      } else {
        _funnels[i] = f;
      }
    });
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => Theme(
          data: WfStyle.theme,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(width: 440, child: Text(text)),
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
        ),
      ) ??
      false;
  Future<bool> _discard() async =>
      !_dirty ||
      await _confirm(
        'Discard unsaved edits?',
        'Your saved draft and published page will stay as they are.',
        'Discard edits',
      );
  Future<void> _back() async {
    if (_busy || !await _discard() || !mounted) return;
    if (_selected != null) {
      setState(() {
        _selected = null;
        _dirty = false;
        _insights = null;
        _tab = 'Page';
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _save() => _run(() async {
    final d = await widget.client.request(
      'PUT',
      '/${_selected!['id']}',
      body: {
        'version': _selected!['version'],
        'name': _name,
        'document': _draft,
      },
    );
    if (mounted) {
      _take(Map<String, dynamic>.from(d['funnel'] as Map));
      _notice('Draft saved.');
    }
  });
  Future<void> _publish() async {
    if (_dirty) {
      _notice('Save your draft before publishing.');
      return;
    }
    if (!await _confirm(
          'Publish this page?',
          'Anyone with the link can view this page and submit a request. Check the preview, business contact email, and privacy policy. Leads will appear in CRM. Publishing does not send messages or launch paid ads.',
          'Publish page',
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      final d = await widget.client.request(
        'POST',
        '/${_selected!['id']}/publish',
        body: {'version': _selected!['version'], 'confirmed': true},
      );
      if (mounted) {
        _take(Map<String, dynamic>.from(d['funnel'] as Map));
        _notice('Your page is live. Copy its link to share it.');
      }
    });
  }

  Future<void> _pause() async {
    if (!await _confirm(
          'Pause the public page?',
          'Visitors will no longer be able to view or submit this page. Saved leads stay in CRM.',
          'Pause page',
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      final d = await widget.client.request(
        'POST',
        '/${_selected!['id']}/pause',
        body: {'version': _selected!['version']},
      );
      if (mounted) _take(Map<String, dynamic>.from(d['funnel'] as Map));
    });
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _notice('Link copied.');
  }

  Future<void> _openLive() async {
    try {
      if (!await launchUrl(
            Uri.parse(_selected!['url'].toString()),
            mode: LaunchMode.externalApplication,
          ) &&
          mounted) {
        _notice('Copy the link and open it in your browser.');
      }
    } catch (_) {
      if (mounted) _notice('Copy the link and open it in your browser.');
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(), address = TextEditingController();
    String layout = 'consultation';
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => Theme(
        data: WfStyle.theme,
        child: StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: const Text('Start something great'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a starting point. Every page is fully editable.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: name,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Funnel name',
                      ),
                      onChanged: (v) {
                        if (address.text.isEmpty) update(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: address,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Public address',
                        hintText: 'your-business-offer',
                        helperText:
                            '3–60 lowercase letters, numbers, or hyphens. Cannot be changed later.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: layout,
                      decoration: const InputDecoration(labelText: 'Template'),
                      items: const [
                        DropdownMenuItem(
                          value: 'consultation',
                          child: Text('Consultation · start a conversation'),
                        ),
                        DropdownMenuItem(
                          value: 'product',
                          child: Text('Product · showcase your offer'),
                        ),
                        DropdownMenuItem(
                          value: 'event',
                          child: Text('Event · collect interest'),
                        ),
                      ],
                      isExpanded: true,
                      onChanged: (v) => update(() => layout = v!),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(color: WfStyle.danger),
                        ),
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
                onPressed: () {
                  if (name.text.trim().isEmpty ||
                      !RegExp(
                        r'^[a-z0-9][a-z0-9-]{2,59}$',
                      ).hasMatch(address.text.trim())) {
                    update(
                      () => error = 'Add a name and a valid public address.',
                    );
                    return;
                  }
                  Navigator.pop(c, {
                    'name': name.text.trim(),
                    'slug': address.text.trim(),
                    'document': funnelTemplate(layout),
                  });
                },
                child: const Text('Create draft'),
              ),
            ],
          ),
        ),
      ),
    );
    // Controllers stay alive until the dialog exit animation has finished.
    Future<void>.delayed(const Duration(seconds: 1), () {
      name.dispose();
      address.dispose();
    });
    if (result == null || !mounted) return;
    await _run(() async {
      final d = await widget.client.request('POST', '', body: result);
      if (mounted) _take(Map<String, dynamic>.from(d['funnel'] as Map));
    });
  }

  Future<void> _generate() async {
    final brief = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => Theme(
        data: WfStyle.theme,
        child: AlertDialog(
          title: const Text('Create with NOVA'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Describe your business, audience, offer, and the action you want visitors to take. NOVA will replace the page copy with a draft for you to review.',
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: brief,
                    minLines: 5,
                    maxLines: 9,
                    maxLength: 2400,
                    decoration: const InputDecoration(
                      labelText: 'Your brief',
                      hintText: 'We help… Our offer is… Our audience is…',
                    ),
                  ),
                  const Text(
                    '10 draft requests per day. Your privacy policy, booking link, and contact email are kept. Nothing is published automatically.',
                    style: TextStyle(color: WfStyle.muted, fontSize: 12),
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
              onPressed: () {
                if (brief.text.trim().isNotEmpty) {
                  Navigator.pop(c, brief.text.trim());
                }
              },
              child: const Text('Generate draft'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), brief.dispose);
    if (result == null || !mounted) return;
    await _run(() async {
      final d = await widget.client.request(
        'POST',
        '/generate',
        body: {'brief': result},
      );
      if (mounted) {
        setState(() {
          _draft = generatedCopy(_draft, d['document'] as Map);
          _revision++;
          _dirty = true;
        });
      }
    });
  }

  Future<void> _loadInsights() => _run(() async {
    final id = _selected!['id'];
    final d = await widget.client.request('GET', '/$id/leads');
    if (mounted && _selected?['id'] == id) setState(() => _insights = d);
  });

  Future<void> _queueFollowup(String leadId) async {
    if (!await _confirm(
          'Queue this inquiry?',
          'Create tasks using this funnel’s enabled workflow. Existing tasks will not be duplicated. This does not send an email or place a call.',
          'Queue follow-up',
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      await widget.client.request(
        'POST',
        '/${_selected!['id']}/followups/enqueue',
        body: {'lead_id': leadId},
      );
      if (mounted) setState(() => _tab = 'Follow-ups');
    });
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: WfStyle.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: WfStyle.line),
        ),
        child: child,
      );
  Widget _title(String text, [String? subtitle]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(color: WfStyle.muted, height: 1.5),
        ),
      ],
    ],
  );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: _busy || _denied ? null : action,
          icon: Icon(icon, size: 18),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: _busy || _denied ? null : action,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );

  @override
  Widget build(BuildContext context) => Theme(
    data: WfStyle.theme,
    child: PopScope(
      canPop: !_dirty && !_busy && _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _selected == null ? 'Back' : 'All funnels',
            onPressed: _busy ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/meeting_copilot/korlix_logo.jpeg',
                  width: 34,
                  height: 34,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'NOVA Funnel Studio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          actions: [
            if (MediaQuery.sizeOf(context).width > 520)
              const Padding(
                padding: EdgeInsets.only(right: 20),
                child: WfBadge('ENTERPRISE'),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Container(
                width: double.infinity,
                color: WfStyle.danger.withValues(alpha: .12),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: WfStyle.danger),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _busy,
                child: _denied
                    ? Center(
                        child: _title(
                          'Enterprise access required',
                          'Sign in with an active Enterprise account to open Funnel Studio.',
                        ),
                      )
                    : _selected == null
                    ? _dashboard()
                    : _editor(),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dashboard() {
    final filtered = _funnels
        .where(
          (f) =>
              f['name'].toString().toLowerCase().contains(
                _search.toLowerCase(),
              ) &&
              (_status == 'All' || f['state'] == _status.toLowerCase()),
        )
        .toList();
    final published = _funnels.where((f) => f['state'] == 'published').length;
    final leads = _funnels.fold<int>(
      0,
      (n, f) => n + (f['lead_count'] as num? ?? 0).toInt(),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('funnel-dashboard'),
        padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF163D46), Color(0xFF202342)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: WfStyle.cyan.withValues(alpha: .25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const WfBadge(
                        'FROM FIRST CLICK TO NEW CONNECTION',
                        color: WfStyle.cyan,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Turn interest into\nyour next opportunity.',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Create a beautiful page. Capture the right details. Bring every lead into KORLIX.',
                        style: TextStyle(color: WfStyle.muted, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _button(
                            'Create funnel',
                            Icons.add_rounded,
                            _create,
                            primary: true,
                          ),
                          _button('Refresh', Icons.refresh_rounded, _refresh),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final pair in [
                      ('${_funnels.length}', 'Saved funnels'),
                      ('$published', 'Published pages'),
                      ('$leads', 'Lead submissions'),
                    ])
                      SizedBox(
                        width: constraints.maxWidth < 500
                            ? (constraints.maxWidth - 46) / 2
                            : 220,
                        child: _card(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pair.$1,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                pair.$2,
                                style: const TextStyle(color: WfStyle.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                _title(
                  'Your funnels',
                  'One workspace for your offers, pages, and new leads.',
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search funnels',
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    for (final s in ['All', 'Draft', 'Published', 'Paused'])
                      ChoiceChip(
                        label: Text(s),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (filtered.isEmpty)
                  _card(
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.web_rounded,
                            size: 50,
                            color: WfStyle.cyan,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _funnels.isEmpty
                                ? 'Your next campaign starts here.'
                                : 'No matching funnels.',
                          ),
                          const SizedBox(height: 14),
                          if (_funnels.isEmpty)
                            _button(
                              'Create your first funnel',
                              Icons.add,
                              _create,
                              primary: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    for (final f in filtered)
                      SizedBox(
                        width: constraints.maxWidth < 700
                            ? constraints.maxWidth - 32
                            : 340,
                        child: _card(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_mosaic_rounded,
                                    color: WfStyle.cyan,
                                    size: 32,
                                  ),
                                  const Spacer(),
                                  WfBadge(
                                    f['state'].toString().toUpperCase(),
                                    color: f['state'] == 'published'
                                        ? WfStyle.cyan
                                        : WfStyle.gold,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Text(
                                f['name'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '/f/${f['slug']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: WfStyle.muted),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '${f['lead_count'] ?? 0} leads   ·   ${f['page_requests'] ?? 0} page requests',
                                style: const TextStyle(
                                  color: WfStyle.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _button(
                                'Open studio',
                                Icons.arrow_forward_rounded,
                                () {
                                  _take(f);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 30),
                const Text(
                  'Page requests include repeat visits and bots. Lead submissions are not unique customers or verified identities.',
                  style: TextStyle(color: WfStyle.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      key: ValueKey('editor-${_selected?["id"]}'),
      padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(_name, '/f/${_selected!['slug']}'),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  WfBadge(
                    _dirty
                        ? 'UNSAVED EDITS'
                        : _selected!['state'].toString().toUpperCase(),
                    color: _dirty ? WfStyle.gold : WfStyle.cyan,
                  ),
                  _button(
                    'Save draft',
                    Icons.save_outlined,
                    _dirty ? _save : null,
                  ),
                  _button(
                    'Review & publish',
                    Icons.rocket_launch_outlined,
                    _dirty ? null : _publish,
                    primary: true,
                  ),
                  if (_selected!['state'] == 'published') ...[
                    _button('Open live page', Icons.open_in_new, _openLive),
                    _button(
                      'Copy link',
                      Icons.link,
                      () => _copy(_selected!['url'].toString()),
                    ),
                    _button('Pause page', Icons.pause, _dirty ? null : _pause),
                  ],
                  _button('Reload saved', Icons.refresh, () async {
                    if (await _discard() && mounted) {
                      await _run(() async {
                        final d = await widget.client.request('GET', '');
                        final f = (d['funnels'] as List).cast<Map>().firstWhere(
                          (f) => f['id'] == _selected!['id'],
                        );
                        if (mounted) _take(Map<String, dynamic>.from(f));
                      });
                    }
                  }),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in [
                    'Page',
                    if (box.maxWidth <= 1080) 'Preview',
                    'Ads workspace',
                    'Campaign links',
                    'Leads',
                    'Follow-ups',
                  ])
                    ChoiceChip(
                      label: Text(t),
                      selected: _tab == t,
                      onSelected: (_) {
                        setState(() => _tab = t);
                        if (t == 'Leads') unawaited(_loadInsights());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 22),
              if (_tab == 'Page') ...[
                if (box.maxWidth < 600)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _aiReady
                              ? 'Describe your offer. NOVA will help shape your draft.'
                              : 'Start with a template. NOVA generation is not configured yet.',
                          style: const TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        _button(
                          'Ask NOVA',
                          Icons.auto_awesome,
                          _aiReady ? _generate : null,
                        ),
                      ],
                    ),
                  )
                else
                  _card(
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: WfStyle.violet),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _aiReady
                                ? 'Describe your offer. NOVA will help you shape the first draft.'
                                : 'Start with a template and make it yours. NOVA generation is not configured yet.',
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _button(
                          'Ask NOVA',
                          Icons.auto_awesome,
                          _aiReady ? _generate : null,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                if (box.maxWidth > 1080)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 390, child: _fields()),
                      const SizedBox(width: 22),
                      Expanded(child: _preview()),
                    ],
                  )
                else
                  _fields(),
              ],
              if (_tab == 'Preview') _preview(),
              if (_tab == 'Ads workspace')
                FunnelCampaigns(
                  key: ValueKey('campaigns-${_selected!['id']}'),
                  client: widget.client,
                  funnelId: '${_selected!['id']}',
                ),
              if (_tab == 'Campaign links') _campaigns(),
              if (_tab == 'Leads') _leads(),
              if (_tab == 'Follow-ups')
                FunnelFollowups(
                  key: ValueKey('followups-${_selected!['id']}'),
                  client: widget.client,
                  funnelId: '${_selected!['id']}',
                  onOpenContacts: widget.onOpenContacts,
                ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(
    String key,
    String label,
    int max, {
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('$_revision:$key'),
      initialValue: key == 'name' ? _name : _draft[key]?.toString() ?? '',
      maxLength: max,
      minLines: lines,
      maxLines: lines + 2,
      decoration: InputDecoration(labelText: label, helperText: hint),
      onChanged: (v) => setState(() {
        if (key == 'name') {
          _name = v;
        } else {
          _draft[key] = v;
        }
        _dirty = true;
      }),
    ),
  );
  Widget _fields() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Make it yours',
          'Your edits appear in the preview as you type.',
        ),
        const SizedBox(height: 22),
        _field('name', 'Funnel name', 100),
        _field('brand', 'Business name', 80),
        DropdownButtonFormField<String>(
          key: ValueKey('$_revision:layout'),
          initialValue: _draft['layout'] as String,
          decoration: const InputDecoration(labelText: 'Page style'),
          items: [
            for (final s in ['consultation', 'product', 'event'])
              DropdownMenuItem(
                value: s,
                child: Text(s[0].toUpperCase() + s.substring(1)),
              ),
          ],
          onChanged: (v) => setState(() {
            _draft['layout'] = v;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final c in ['cyan', 'violet', 'gold'])
              ChoiceChip(
                label: Text(c[0].toUpperCase() + c.substring(1)),
                selected: _draft['accent'] == c,
                onSelected: (_) => setState(() {
                  _draft['accent'] = c;
                  _dirty = true;
                }),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _field('headline', 'Headline', 160, lines: 2),
        _field('subheadline', 'Supporting copy', 600, lines: 3),
        _field('cta', 'Button text', 60),
        TextFormField(
          key: ValueKey('$_revision:benefits'),
          initialValue: (_draft['benefits'] as List).join('\n'),
          minLines: 4,
          maxLines: 8,
          maxLength: 1085,
          decoration: const InputDecoration(
            labelText: 'Benefits',
            helperText: 'One per line. Up to six, 180 characters each.',
          ),
          onChanged: (v) => setState(() {
            _draft['benefits'] = v
                .split('\n')
                .where((x) => x.trim().isNotEmpty)
                .toList();
            _dirty = true;
          }),
        ),
        const SizedBox(height: 20),
        const Text(
          'Questions & answers',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < (_draft['faq'] as List).length; i++) ...[
          TextFormField(
            key: ValueKey('$_revision:q$i'),
            initialValue: _draft['faq'][i]['q'] as String,
            maxLength: 180,
            decoration: InputDecoration(
              labelText: 'Question ${i + 1}',
              suffixIcon: IconButton(
                tooltip: 'Remove question',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  (_draft['faq'] as List).removeAt(i);
                  _dirty = true;
                  _revision++;
                }),
              ),
            ),
            onChanged: (v) => setState(() {
              _draft['faq'][i]['q'] = v;
              _dirty = true;
            }),
          ),
          TextFormField(
            key: ValueKey('$_revision:a$i'),
            initialValue: _draft['faq'][i]['a'] as String,
            maxLength: 700,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Answer'),
            onChanged: (v) => setState(() {
              _draft['faq'][i]['a'] = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 12),
        ],
        if ((_draft['faq'] as List).length < 6)
          TextButton.icon(
            onPressed: () => setState(() {
              (_draft['faq'] as List).add({'q': '', 'a': ''});
              _dirty = true;
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add a question'),
          ),
        const Divider(height: 35),
        _field('thank_you', 'Thank-you message', 600, lines: 2),
        _field(
          'privacy_url',
          'Privacy-policy URL',
          1000,
          hint: 'Required to publish. Use a public HTTPS address.',
        ),
        _field(
          'contact_email',
          'Business contact email',
          254,
          hint: 'Shown in your page footer.',
        ),
        _field(
          'booking_url',
          'Booking / next-step URL (optional)',
          1000,
          hint: 'Shown after a visitor submits. Use HTTPS.',
        ),
        const Text(
          'Publish only offers and claims you can support. Review AI-generated copy before sharing.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _preview() {
    final accent = switch (_draft['accent']) {
      'violet' => WfStyle.violet,
      'gold' => WfStyle.gold,
      _ => WfStyle.cyan,
    };
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: WfStyle.muted,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PAGE PREVIEW',
                  style: TextStyle(
                    letterSpacing: 1.5,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              WfBadge('DRAFT', color: accent),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: const Color(0xFFF5F7F7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    color: Colors.white,
                    child: Text(
                      _draft['brand'].toString(),
                      style: const TextStyle(
                        color: Color(0xFF142B38),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 48,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF102C39),
                          _draft['layout'] == 'event'
                              ? const Color(0xFF32294A)
                              : const Color(0xFF123A42),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: _draft['layout'] == 'consultation'
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Text(
                          _draft['headline'].toString(),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _draft['subheadline'].toString(),
                          style: const TextStyle(
                            color: Color(0xFFBDD2DC),
                            height: 1.6,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _draft['cta'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF102C39),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final benefit in _draft['benefits'] as List)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF147467),
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    benefit.toString(),
                                    style: const TextStyle(
                                      color: Color(0xFF142B38),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'Let’s connect',
                          style: TextStyle(
                            color: Color(0xFF142B38),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        for (final field in [
                          'Your name',
                          'Email address',
                          'Phone (optional)',
                          'How can we help?',
                        ])
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFD8E0E3),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              field,
                              style: const TextStyle(color: Color(0xFF71808B)),
                            ),
                          ),
                        Text(
                          '□ I agree that ${_draft['brand']} may contact me about this request.',
                          style: const TextStyle(
                            color: Color(0xFF526776),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 18),
                        for (final faq in _draft['faq'] as List)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  faq['q'].toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF142B38),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  faq['a'].toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF526776),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'Powered by KORLIX AI',
                          style: TextStyle(
                            color: Color(0xFF526776),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Visual preview · the public form becomes active after publishing. Pages adapt to mobile screens.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _campaigns() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Know where interest comes from',
          'Create a tracking link for ads, email, social posts, or QR codes. Matching tags appear alongside each lead.',
        ),
        const SizedBox(height: 22),
        for (final entry in _tags.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              initialValue: entry.value,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: switch (entry.key) {
                  'source' => 'Source · e.g. facebook',
                  'medium' => 'Medium · e.g. paid-social',
                  'campaign' => 'Campaign · e.g. fall-launch',
                  'content' => 'Creative / content (optional)',
                  _ => 'Search term (optional)',
                },
              ),
              onChanged: (v) => setState(() => _tags[entry.key] = v),
            ),
          ),
        SelectableText(
          campaignLink(_selected!['url'].toString(), _tags),
          style: const TextStyle(color: WfStyle.cyan, height: 1.5),
        ),
        const SizedBox(height: 18),
        _button(
          'Copy campaign link',
          Icons.copy,
          _selected!['state'] == 'published'
              ? () => _copy(campaignLink(_selected!['url'].toString(), _tags))
              : null,
          primary: true,
        ),
        const SizedBox(height: 14),
        Text(
          _selected!['state'] != 'published'
              ? 'Publish this page to activate the link.'
              : 'Use this link as the destination in your campaign.',
          style: const TextStyle(color: WfStyle.muted),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tracking records visitor-supplied tags. Use Ads workspace for saved campaign plans, planned budgets, and manual results. Ad-account connections and direct campaign publishing are not available yet.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _leads() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Every conversation starts somewhere',
          '${_insights?['total'] ?? _selected!['lead_count'] ?? 0} submissions · most recent 100 shown',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _button('Refresh leads', Icons.refresh, _loadInsights),
            if (widget.onOpenContacts != null)
              _button(
                'Open Contacts CRM',
                Icons.people_outline,
                widget.onOpenContacts,
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Submitted identities are unverified. A request permits a response to that inquiry; it does not grant marketing or outbound-call permission. Existing CRM preferences are preserved.',
          style: TextStyle(color: WfStyle.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        if (_insights != null && (_insights!['leads'] as List).isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'Your next lead will appear here. Share a published page to get started.',
            ),
          ),
        for (final campaign in _insights?['campaigns'] as List? ?? [])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${campaign['source']} / ${campaign['campaign']}  ·  ${campaign['leads']} leads',
              style: const TextStyle(color: WfStyle.cyan),
            ),
          ),
        const SizedBox(height: 16),
        for (final lead in _insights?['leads'] as List? ?? [])
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: WfStyle.background,
              border: Border.all(color: WfStyle.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead['name'].toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${lead['email']}${lead['phone'].toString().isEmpty ? '' : ' · ${lead['phone']}'}',
                  style: const TextStyle(color: WfStyle.cyan),
                ),
                if (lead['message'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(lead['message'].toString()),
                  ),
                const SizedBox(height: 12),
                Text(
                  '${DateTime.tryParse(lead['created_at'].toString())?.toLocal().toString().split('.').first ?? ''} · ${lead['utm']?['utm_source'] ?? ''} ${lead['utm']?['utm_campaign'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: WfStyle.muted),
                ),
                const SizedBox(height: 14),
                _button(
                  'Queue follow-up',
                  Icons.playlist_add,
                  () => _queueFollowup('${lead['id']}'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

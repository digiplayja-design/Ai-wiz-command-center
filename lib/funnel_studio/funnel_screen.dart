import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_inbox.dart';
import 'funnel_templates.dart';
import 'funnel_sections.dart';
import 'funnel_questions.dart';
import 'funnel_booking.dart';
import 'funnel_images.dart';
import 'funnel_create_dialog.dart';
import 'funnel_launch_checklist.dart';
import 'funnel_followups.dart';
import 'funnel_campaigns.dart';
import 'funnel_rehearsal.dart';

class FunnelScreen extends StatefulWidget {
  const FunnelScreen({
    super.key,
    required this.client,
    this.disposeClient = false,
    this.onOpenContacts,
    this.imagePicker = pickFunnelImage,
  });
  final FunnelClient client;
  final bool disposeClient;
  final Future<FunnelPickedImage?> Function() imagePicker;
  final Future<void> Function()? onOpenContacts;
  @override
  State<FunnelScreen> createState() => _FunnelScreenState();
}

class _FunnelScreenState extends State<FunnelScreen> {
  List<Map<String, dynamic>> _funnels = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic> _draft = {};
  String _name = '', _tab = 'Page', _search = '', _status = 'All';
  String? _error;
  bool _busy = false, _dirty = false, _aiReady = false, _denied = false;
  int _revision = 0;
  int _epoch = 0, _operation = 0;
  final _dialogs = <DialogRoute<dynamic>>{};
  final _fieldAnchors = <String, GlobalKey>{};
  final _fieldFocus = <String, FocusNode>{};
  final _previewAnchor = GlobalKey(), _rehearsalAnchor = GlobalKey();
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
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_refresh());
  }

  bool _current(int epoch) => mounted && !_denied && epoch == _epoch;

  void _clearWorkspace() {
    _epoch++;
    _operation++;
    _funnels = [];
    _selected = null;
    _draft = {};
    _name = '';
    _tab = 'Page';
    _search = '';
    _status = 'All';
    _dirty = false;
    _busy = false;
    _aiReady = false;
    _error = null;
    _revision++;
    _tags.updateAll((key, value) => key == 'medium' ? 'paid' : '');
    final studioRoute = ModalRoute.of(context);
    final staleDialogs = _dialogs.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Child tabs can open their own dialogs (lead details, campaign copy,
      // credentials). Close the whole obsolete route stack above the studio.
      final navigator = studioRoute?.navigator;
      if (studioRoute?.isActive == true && navigator != null) {
        navigator.popUntil((candidate) => candidate == studioRoute);
        return;
      }
      for (final route in staleDialogs) {
        final navigator = route.navigator;
        if (route.isActive && navigator != null) {
          // Close child confirmations with the obsolete studio dialog.
          navigator.popUntil((candidate) => candidate == route);
          if (route.isActive) navigator.removeRoute(route);
        }
      }
    });
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _clearWorkspace();
      _denied = true;
    });
  }

  @override
  void didUpdateWidget(covariant FunnelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      if (oldWidget.disposeClient) oldWidget.client.dispose();
      _clearWorkspace();
      _denied = false;
      widget.client.addAccessDeniedListener(_deny);
      unawaited(_refresh());
    }
  }

  Future<T?> _dialog<T>(
    WidgetBuilder builder, {
    bool dismissible = true,
  }) async {
    if (_denied || !mounted) return null;
    final epoch = _epoch;
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: dismissible,
      builder: builder,
    );
    _dialogs.add(route);
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      return _current(epoch) ? result : null;
    } finally {
      _dialogs.remove(route);
    }
  }

  @override
  void dispose() {
    _epoch++;
    for (final focus in _fieldFocus.values) {
      focus.dispose();
    }
    widget.client.removeAccessDeniedListener(_deny);
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _jumpTo(String tab, GlobalKey anchor, {String? field}) {
    final epoch = _epoch, id = _selected?['id'];
    setState(() => _tab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_current(epoch) || _selected?['id'] != id) return;
      final target = anchor.currentContext;
      if (target == null) return;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: const Duration(milliseconds: 250),
      );
      if (_current(epoch) &&
          _selected?['id'] == id &&
          _tab == tab &&
          field != null) {
        _fieldFocus[field]?.requestFocus();
      }
    });
  }

  void _editField(String field) => _jumpTo(
    'Page',
    _fieldAnchors.putIfAbsent(field, () => GlobalKey()),
    field: field,
  );

  Future<void> _run(Future<void> Function(int, FunnelClient) task) async {
    if (_busy || _denied) return;
    final epoch = _epoch, operation = ++_operation, client = widget.client;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task(epoch, client);
    } catch (e) {
      if (_current(epoch) && operation == _operation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (_current(epoch) && operation == _operation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() => _run((epoch, client) async {
    final data = await client.request('GET', '');
    if (!_current(epoch)) return;
    setState(() {
      _funnels = (data['funnels'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _aiReady = data['ai_ready'] == true;
    });
  });
  void _take(Map<String, dynamic> f) {
    if (_denied || !mounted) return;
    setState(() {
      _selected = f;
      _draft = copyFunnel(f['draft'] as Map);
      _name = f['name'].toString();
      _dirty = false;
      _revision++;
      final i = _funnels.indexWhere((x) => x['id'] == f['id']);
      if (i < 0) {
        _funnels.insert(0, f);
      } else {
        _funnels[i] = f;
      }
    });
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await _dialog<bool>(
        (c) => Theme(
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
    final epoch = _epoch;
    if (_busy || !await _discard() || !mounted || epoch != _epoch) return;
    if (_selected != null) {
      setState(() {
        _selected = null;
        _dirty = false;
        _tab = 'Page';
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _save() => _run((epoch, client) async {
    final d = await client.request(
      'PUT',
      '/${_selected!['id']}',
      body: {
        'version': _selected!['version'],
        'name': _name,
        'document': _draft,
      },
    );
    if (_current(epoch)) {
      _take(Map<String, dynamic>.from(d['funnel'] as Map));
      _notice('Draft saved.');
    }
  });
  Future<void> _publish() async {
    if (_busy || _denied || _selected == null) return;
    final epoch = _epoch,
        id = _selected!['id'],
        version = _selected!['version'];
    if (_dirty) {
      _notice('Save your draft before publishing.');
      return;
    }
    if (!await _confirm(
          'Publish this page?',
          'Anyone with the link can view this page and submit a request. Check the preview, business contact email, and privacy policy. Leads will appear in CRM. Publishing does not send messages or launch paid ads.',
          'Publish page',
        ) ||
        !_current(epoch) ||
        _selected?['id'] != id ||
        _selected?['version'] != version ||
        _dirty) {
      return;
    }
    await _run((runEpoch, client) async {
      final d = await client.request(
        'POST',
        '/$id/publish',
        body: {'version': version, 'confirmed': true},
      );
      if (_current(runEpoch)) {
        _take(Map<String, dynamic>.from(d['funnel'] as Map));
        _notice('Your page is live. Copy its link to share it.');
      }
    });
  }

  Future<void> _pause() async {
    if (_busy || _denied || _selected == null) return;
    final epoch = _epoch,
        id = _selected!['id'],
        version = _selected!['version'];
    if (!await _confirm(
          'Pause the public page?',
          'Visitors will no longer be able to view or submit this page. Saved leads stay in CRM.',
          'Pause page',
        ) ||
        !_current(epoch) ||
        _selected?['id'] != id ||
        _selected?['version'] != version) {
      return;
    }
    await _run((runEpoch, client) async {
      final d = await client.request(
        'POST',
        '/$id/pause',
        body: {'version': version},
      );
      if (_current(runEpoch)) {
        _take(Map<String, dynamic>.from(d['funnel'] as Map));
      }
    });
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy(String text) async {
    final epoch = _epoch;
    await Clipboard.setData(ClipboardData(text: text));
    if (_current(epoch)) _notice('Link copied.');
  }

  Future<void> _openLive() async {
    final epoch = _epoch;
    try {
      if (!await launchUrl(
            Uri.parse(_selected!['url'].toString()),
            mode: LaunchMode.externalApplication,
          ) &&
          _current(epoch)) {
        _notice('Copy the link and open it in your browser.');
      }
    } catch (_) {
      if (_current(epoch)) {
        _notice('Copy the link and open it in your browser.');
      }
    }
  }

  Future<void> _create({Map<String, dynamic>? source}) async {
    if (_busy || _denied) return;
    final epoch = _epoch, client = widget.client;
    if (source != null && _dirty) {
      _notice('Save your edits before duplicating this draft.');
      return;
    }
    final result = await _dialog<Map<String, dynamic>>(
      (c) => Theme(
        data: WfStyle.theme,
        child: FunnelCreateDialog(
          source: source,
          create: (payload) async {
            if (!_current(epoch)) {
              throw const FunnelException(
                'Your workspace changed. Reopen Funnel Studio.',
              );
            }
            final data = await client.request('POST', '', body: payload);
            if (!_current(epoch)) {
              throw const FunnelException(
                'Your workspace changed. Refresh saved drafts before continuing.',
              );
            }
            return Map<String, dynamic>.from(data['funnel'] as Map);
          },
        ),
      ),
      dismissible: false,
    );
    if (result == null || !_current(epoch)) return;
    setState(() {
      _tab = 'Page';
      _error = null;
    });
    _take(result);
    _notice(
      source == null
          ? 'Private draft created.'
          : 'Draft duplicated. Your original is unchanged.',
    );
  }

  Future<void> _generate() async {
    if (_busy || _denied || _selected == null) return;
    final epoch = _epoch, id = _selected!['id'];
    final brief = TextEditingController();
    final result = await _dialog<String>(
      (c) => Theme(
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
                    '10 draft requests per day. Your images, section order, added text sections, inquiry questions, form style, privacy policy, booking link, and contact email are kept. Nothing is published automatically.',
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
    if (result == null || !_current(epoch) || _selected?['id'] != id) return;
    await _run((runEpoch, client) async {
      final d = await client.request(
        'POST',
        '/generate',
        body: {'brief': result},
      );
      if (_current(runEpoch) && _selected?['id'] == id) {
        setState(() {
          _draft = generatedCopy(_draft, d['document'] as Map);
          _revision++;
          _dirty = true;
        });
      }
    });
  }

  Future<void> _queueFollowup(String leadId) async {
    if (_busy || _denied || _selected == null) return;
    final epoch = _epoch, id = _selected!['id'];
    if (!await _confirm(
          'Queue this inquiry?',
          'Create tasks using this funnel’s enabled workflow. Existing tasks will not be duplicated. This does not send an email or place a call.',
          'Queue follow-up',
        ) ||
        !_current(epoch) ||
        _selected?['id'] != id) {
      return;
    }
    await _run((runEpoch, client) async {
      await client.request(
        'POST',
        '/$id/followups/enqueue',
        body: {'lead_id': leadId},
      );
      if (_current(runEpoch)) setState(() => _tab = 'Follow-ups');
    });
  }

  Future<void> _reloadSaved() async {
    if (_busy || _denied || _selected == null) return;
    final epoch = _epoch, id = _selected!['id'];
    if (!await _discard() || !_current(epoch) || _selected?['id'] != id) return;
    await _run((runEpoch, client) async {
      final data = await client.request('GET', '');
      if (!_current(runEpoch) || _selected?['id'] != id) return;
      final rows = (data['funnels'] as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
      final matches = rows.where((f) => f['id'] == id);
      if (matches.isEmpty) {
        setState(() {
          _funnels = rows;
          _selected = null;
          _draft = {};
          _name = '';
          _dirty = false;
          _tab = 'Page';
          _revision++;
        });
        _notice('This funnel is no longer available. Choose a saved funnel.');
        return;
      }
      _take(matches.single);
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
                          widget.client.sessionChanged
                              ? 'Session changed'
                              : 'Enterprise access required',
                          widget.client.sessionChanged
                              ? 'Sign in again and reopen Funnel Studio to continue.'
                              : 'Sign in with an active Enterprise account to open Funnel Studio.',
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: WfStyle.cyan.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: WfStyle.cyan.withValues(alpha: .17),
                          ),
                        ),
                        child: const Text(
                          'FROM FIRST CLICK TO NEW CONNECTION',
                          style: TextStyle(
                            color: WfStyle.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                  _button(
                    'Run rehearsal',
                    Icons.play_circle_outline,
                    () => _jumpTo('Rehearsal', _rehearsalAnchor),
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
                  Tooltip(
                    message: _dirty
                        ? 'Save your edits before duplicating.'
                        : 'Create a private copy of the saved page.',
                    child: _button(
                      'Duplicate draft',
                      Icons.copy_all_outlined,
                      _dirty ? null : () => _create(source: _selected),
                    ),
                  ),
                  _button('Reload saved', Icons.refresh, _reloadSaved),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in [
                    'Page',
                    'Preview',
                    'Rehearsal',
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
                      },
                    ),
                ],
              ),
              const SizedBox(height: 22),
              FunnelLaunchChecklist(
                key: ValueKey('launch-${_selected!['id']}'),
                document: _draft,
                dirty: _dirty,
                onEdit: () => _editField('name'),
                onEditField: _editField,
                onPreview: () => _jumpTo('Preview', _previewAnchor),
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
              if (_tab == 'Preview')
                KeyedSubtree(key: _previewAnchor, child: _preview()),
              if (_tab == 'Rehearsal')
                KeyedSubtree(
                  key: _rehearsalAnchor,
                  child: FunnelRehearsal(
                    key: ValueKey('rehearsal-${_selected!['id']}-$_revision'),
                    client: widget.client,
                    funnel: _selected!,
                    document: copyFunnel(_draft),
                    name: _name,
                    dirty: _dirty,
                  ),
                ),
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
    key: _fieldAnchors.putIfAbsent(key, () => GlobalKey()),
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('$_revision:$key'),
      focusNode: _fieldFocus.putIfAbsent(key, () => FocusNode()),
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
  Future<void> _chooseImage(String slot, String label) async {
    final epoch = _epoch, selectedId = _selected?['id'], client = widget.client;
    final result = await _dialog<Map<String, dynamic>>(
      (c) => Theme(
        data: WfStyle.theme,
        child: FunnelImageLibrary(
          client: client,
          slot: label,
          picker: widget.imagePicker,
          protectedIds: {
            for (final key in ['logo', 'hero_image'])
              if (_draft[key] is Map) _draft[key]['id'].toString(),
          },
        ),
      ),
      dismissible: false,
    );
    if (result == null || !_current(epoch) || _selected?['id'] != selectedId) {
      return;
    }
    setState(() {
      _draft[slot] = result;
      _dirty = true;
      _revision++;
    });
  }

  Widget _imageField(String slot, String label) {
    final asset = _draft[slot] as Map?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _chooseImage(slot, label.toLowerCase()),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Choose ${label.toLowerCase()}'),
              ),
              if (asset != null)
                TextButton(
                  onPressed: () => setState(() {
                    _draft[slot] = null;
                    _dirty = true;
                    _revision++;
                  }),
                  child: Text('Remove ${label.toLowerCase()}'),
                ),
            ],
          ),
          if (asset != null) ...[
            const SizedBox(height: 8),
            FunnelPrivateImage(
              client: widget.client,
              id: asset['id'].toString(),
              description: asset['alt'].toString(),
              height: 88,
            ),
            TextFormField(
              key: ValueKey('$_revision:$slot-alt:${asset['id']}'),
              initialValue: asset['alt'].toString(),
              maxLength: 180,
              decoration: InputDecoration(
                labelText: '$label description',
                helperText:
                    'Required to publish. Describe what the image shows.',
                helperMaxLines: 5,
              ),
              onChanged: (v) => setState(() {
                _draft[slot] = {...asset, 'alt': v};
                _dirty = true;
              }),
            ),
          ],
        ],
      ),
    );
  }

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
        const Text(
          'Page images',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add your logo and a main image. Save and publish to update the live page.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        _imageField('logo', 'Logo'),
        _imageField('hero_image', 'Main image'),
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
        FunnelSectionEditor(
          key: ValueKey('$_revision:sections'),
          document: _draft,
          onChanged: (sections) => setState(() {
            _draft['sections'] = sections;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 16),
        FunnelQuestionEditor(
          key: ValueKey('$_revision:questions'),
          document: _draft,
          onChanged: (questions) => setState(() {
            _draft['booking_routes'] = bookingRoutesAfterQuestions(
              _draft,
              questions,
            );
            _draft['questions'] = questions;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 16),
        _field('headline', 'Headline', 160, lines: 2),
        _field('subheadline', 'Supporting copy', 600, lines: 3),
        _field('cta', 'Button text', 60),
        DropdownButtonFormField<String>(
          key: ValueKey('$_revision:form-mode'),
          initialValue: _draft['form_mode'] as String? ?? 'single',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Inquiry form'),
          items: const [
            DropdownMenuItem(value: 'single', child: Text('Single page')),
            DropdownMenuItem(
              value: 'guided',
              child: Text('Guided · three steps'),
            ),
          ],
          onChanged: (v) => setState(() {
            _draft['form_mode'] = v;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 10),
        const Text(
          'Guided forms collect contact details, then the request and consent, then a final review. Only the final submission creates a lead. Save and publish to change the live page.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 22),
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
          hint:
              'Default when no route matches. Shown after submission. Use HTTPS.',
        ),
        FunnelBookingEditor(
          key: ValueKey('$_revision:booking-routes'),
          document: _draft,
          onChanged: (routes) => setState(() {
            _draft['booking_routes'] = routes;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 16),
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
                    child: Row(
                      children: [
                        if (_draft['logo'] is Map) ...[
                          SizedBox(
                            width: 48,
                            child: FunnelPrivateImage(
                              client: widget.client,
                              id: _draft['logo']['id'].toString(),
                              description: _draft['logo']['alt'].toString(),
                              height: 48,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            _draft['brand'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF142B38),
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
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
                  FunnelSectionsPreview(
                    document: _draft,
                    client: widget.client,
                    accent: accent,
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
          'Tracking records visitor-supplied tags. Ads workspace contains campaign plans, account setup, provider controls and conversion delivery. Provider actions require their own setup and explicit confirmation.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _leads() => _card(
    FunnelInbox(
      key: ValueKey('inbox-${_selected!['id']}'),
      client: widget.client,
      funnelId: _selected!['id'].toString(),
      onQueue: _queueFollowup,
      onOpenContacts: widget.onOpenContacts,
    ),
  );
}

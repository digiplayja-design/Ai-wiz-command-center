import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'defender_client.dart';

typedef DefenderFileSaver =
    Future<void> Function(Uint8List, String, String, Rect);
const _officialSources = {
  'phishing':
      'https://consumer.ftc.gov/articles/how-recognize-avoid-phishing-scams',
  'recovery': 'https://consumer.ftc.gov/articles/what-do-if-you-were-scammed',
  'business':
      'https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business',
  'ransomware': 'https://www.cisa.gov/stopransomware/ransomware-guide',
};

class DefenderScreen extends StatefulWidget {
  const DefenderScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.saveFile = saveBookkeepingFile,
  });
  final DefenderClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final DefenderFileSaver saveFile;
  @override
  State<DefenderScreen> createState() => _DefenderScreenState();
}

class _DefenderScreenState extends State<DefenderScreen> {
  final _message = TextEditingController(),
      _domain = TextEditingController(),
      _search = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic> _data = {}, _profile = {};
  Map<String, dynamic>? _report, _pendingCreate, _pendingEvent;
  String _view = 'check', _channel = 'email';
  String? _error, _notice;
  bool _ai = false,
      _busy = false,
      _loading = true,
      _locked = false,
      _polling = false,
      _dialog = false;
  Timer? _timer;
  ColorScheme get c => Theme.of(context).colorScheme;
  bool get blocked => _busy || _locked || _loading;
  bool get editable => !blocked && _pendingCreate == null;
  List<Map<String, dynamic>> get _reports => defenderItems(_data['reports']);
  List<Map<String, dynamic>> get _habits => defenderItems(_data['habits'])
      .where((h) => _profile['mode'] == 'business' || h['business'] != true)
      .toList();
  Map<String, dynamic> get _checks => defenderMap(_profile['habits']);
  int get _confirmed => _habits.where((h) => _checks[h['id']] == true).length;
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.dispose();
    _message.dispose();
    _domain.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted || _locked) return;
    if (_dialog) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _data = {};
      _profile = {};
      _report = null;
      _pendingCreate = null;
      _pendingEvent = null;
      _message.clear();
      _domain.clear();
      _search.clear();
      _notice = null;
      _error =
          'Your sign-in changed. Close Defender and reopen it after signing in.';
    });
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _tab(String v) {
    if (blocked || _pendingEvent != null) return;
    setState(() {
      _view = v;
      _report = null;
      _notice = null;
    });
    _top();
  }

  Future<void> _work(Future<void> Function() fn) async {
    if (blocked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.list();
      if (!mounted || _locked) return;
      setState(() {
        _data = d;
        _profile = defenderMap(d['profile']);
      });
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final d = await widget.client.list();
    if (_locked || !mounted) return;
    setState(() {
      _data = d;
      _profile = defenderMap(d['profile']);
    });
    final id = _report?['id'] ?? _pendingCreate?['request_key'];
    if (id != null && _reports.any((x) => x['id'] == id)) {
      final r = await widget.client.open(id);
      if (mounted && !_locked) _accept(r);
    }
    if (mounted && !_locked) setState(() => _pendingEvent = null);
  }

  Future<void> _poll() async {
    if (!mounted ||
        _locked ||
        _busy ||
        _loading ||
        _polling ||
        !(_report?['state'] == 'preparing' ||
            _reports.any((r) => r['state'] == 'preparing'))) {
      return;
    }
    _polling = true;
    try {
      final id = _report?['state'] == 'preparing' ? _report!['id'] : null;
      final d = await widget.client.list();
      final r = id == null ? null : await widget.client.open(id);
      if (mounted && !_locked) {
        setState(() {
          _data = d;
          if (r != null &&
              _report?['id'] == id &&
              (r['revision'] as int) >= (_report!['revision'] as int)) {
            _report = r;
          }
        });
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () => _error = 'Updates paused. Refresh to check your saved result.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  void _accept(Map<String, dynamic> r) {
    if (!mounted || _locked) return;
    setState(() {
      _report = r;
      _view = 'report';
      if (_pendingCreate?['request_key'] == r['id']) {
        _pendingCreate = null;
        _message.clear();
        _domain.clear();
      }
      _pendingEvent = null;
    });
    _top();
  }

  Future<void> _create({String? scenario}) async {
    await _work(() async {
      if (_pendingCreate == null) {
        if (scenario == null && _message.text.trim().isEmpty) {
          throw const DefenderException(
            'Paste a suspicious message or link first.',
          );
        }
        final isAi = scenario == null && _ai;
        if (isAi) {
          final yes = await widget.ensureConsent(context);
          if (!mounted || _locked || !yes) return;
        }
        _pendingCreate = {
          'request_key': defenderRequestKey(),
          'kind': scenario == null ? 'message' : 'incident',
          'mode': isAi ? 'ai' : 'quick',
          'scenario': ?scenario,
          if (scenario == null) ...{
            'channel': _channel,
            'content': _message.text.trim(),
            'expectedDomain': _domain.text.trim(),
          },
          if (isAi) 'consent': true,
        };
      }
      try {
        final r = await widget.client.create(_pendingCreate!);
        if (mounted && !_locked) {
          _accept(r);
          await _load();
        }
      } on DefenderException catch (e) {
        if (e.status >= 400 && e.status < 500 && e.status != 409) {
          _pendingCreate = null;
        }
        rethrow;
      }
    });
  }

  Future<void> _open(String id) => _work(() async {
    final r = await widget.client.open(id);
    if (mounted && !_locked) _accept(r);
  });
  Future<void> _change(
    String key, {
    bool? checked,
    String? mode,
    bool report = false,
  }) => _work(() async {
    final target = report ? _report! : _profile;
    _pendingEvent ??= {
      'request_key': defenderRequestKey(),
      'revision': target['revision'] ?? 0,
      'key': key,
      'checked': ?checked,
      'mode': ?mode,
      'reportId': report ? target['id'] : null,
    };
    final event = Map<String, dynamic>.from(_pendingEvent!)..remove('reportId');
    try {
      if (report) {
        final r = await widget.client.progress(target['id'], event);
        if (mounted && !_locked) setState(() => _report = r);
      } else {
        final p = await widget.client.checklist(event);
        if (mounted && !_locked) setState(() => _profile = p);
      }
      if (mounted && !_locked) setState(() => _pendingEvent = null);
    } on DefenderException catch (e) {
      if (e.status >= 400 && e.status < 500 && e.status != 409) {
        _pendingEvent = null;
      }
      rethrow;
    }
  });
  Future<void> _retryChange() async {
    final e = _pendingEvent;
    if (e == null) return;
    await _change(
      e['key'],
      checked: e['checked'],
      mode: e['mode'],
      report: e['reportId'] != null,
    );
  }

  Future<bool> _confirm(String title, String message) async {
    _dialog = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete report'),
          ),
        ],
      ),
    );
    _dialog = false;
    return mounted && !_locked && yes == true;
  }

  Future<void> _delete() async {
    final r = _report;
    if (r == null || blocked || _pendingEvent != null) return;
    if (!await _confirm(
      'Delete this report?',
      'This removes its findings and your action progress from Saved reports.',
    )) {
      return;
    }
    await _work(() async {
      await widget.client.remove(r['id']);
      if (mounted && !_locked) {
        setState(() {
          _report = null;
          _view = 'saved';
        });
        await _load();
      }
    });
  }

  Future<void> _export() => _work(() async {
    final r = _report!;
    final bytes = await widget.client.export(r['id']);
    if (!mounted || _locked) return;
    final box = context.findRenderObject() as RenderBox?;
    await widget.saveFile(
      Uint8List.fromList(bytes),
      'KORLIX-Defender-${r['id']}.txt',
      'text/plain',
      box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : box.localToGlobal(Offset.zero) & box.size,
    );
    if (mounted && !_locked) {
      setState(() => _notice = 'Your report is ready to save.');
    }
  });
  Future<void> _source(String key) => _work(() async {
    final url = _officialSources[key];
    if (url == null) return;
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const DefenderException(
        'The official guidance could not be opened. Try again shortly.',
      );
    }
  });
  String _concern(dynamic v) => switch (v) {
    'high' => 'High concern',
    'review' => 'Needs a closer look',
    'incident' => 'Recovery guide',
    _ => 'No obvious warning signs',
  };
  Color _risk(dynamic v) => switch (v) {
    'high' => c.error,
    'review' =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFD180)
          : const Color(0xFF895400),
    'incident' => c.tertiary,
    _ => c.primary,
  };
  String _effective(Map<String, dynamic> r) {
    final a = defenderMap(r['review'])['concern'],
        b = defenderMap(r['result'])['concern'];
    if (a == 'high' || b == 'high') return 'high';
    if (a == 'review' && b == 'unknown') return 'review';
    return b?.toString() ?? 'unknown';
  }

  Widget _text(String s, {TextStyle? style}) => Text(
    s,
    style:
        style ?? Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
  );
  Widget _panel(
    Widget child, {
    Color? color,
    EdgeInsets padding = const EdgeInsets.all(24),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? c.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: c.outlineVariant.withValues(alpha: .6)),
    ),
    child: child,
  );
  Widget _pill(String s, IconData icon, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: (color ?? c.primary).withValues(alpha: .09),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? c.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            s,
            style: TextStyle(
              color: color ?? c.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _heading(String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      _text(
        description,
        style: TextStyle(color: c.onSurfaceVariant, height: 1.5),
      ),
    ],
  );
  Widget _hero() => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [c.primaryContainer, c.surfaceContainerLow],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: c.primary.withValues(alpha: .16)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pill('KORLIX DEFENDER', Icons.shield_outlined),
              const SizedBox(height: 20),
              Text(
                'A calmer way to\nstay ahead.',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 12),
              _text(
                'Spot suspicious requests. Build stronger habits. Know your next step.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('Free quick checks', Icons.bolt_outlined),
                  _pill('Private saved reports', Icons.lock_outline),
                ],
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width > 650) ...[
          const SizedBox(width: 24),
          Container(
            width: 100,
            height: 118,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(Icons.security_rounded, size: 68, color: c.primary),
          ),
        ],
      ],
    ),
  );
  Widget _navigation() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final item in [
        ('check', 'Check a message', Icons.search_rounded),
        ('habits', 'Safety checklist', Icons.checklist_rounded),
        ('incident', 'Incident help', Icons.health_and_safety_outlined),
        ('saved', 'Saved reports', Icons.folder_outlined),
      ])
        ChoiceChip(
          showCheckmark: false,
          avatar: Icon(item.$3, size: 18),
          label: Text(item.$2),
          selected:
              _view == item.$1 || (_view == 'report' && item.$1 == 'saved'),
          onSelected: blocked || _pendingEvent != null
              ? null
              : (_) => _tab(item.$1),
        ),
    ],
  );
  Widget _start() => LayoutBuilder(
    builder: (context, box) {
      final form = _checkForm(), aside = _habitSummary();
      return box.maxWidth >= 840
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: form),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: aside),
              ],
            )
          : Column(children: [form, const SizedBox(height: 20), aside]);
    },
  );
  Widget _checkForm() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Before you click.',
          'Paste a message or web link and look for common warning signs.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('channel-$_channel'),
          initialValue: _channel,
          decoration: const InputDecoration(
            labelText: 'What are you checking?',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'email', child: Text('Email')),
            DropdownMenuItem(value: 'text', child: Text('Text message')),
            DropdownMenuItem(value: 'social', child: Text('Social message')),
            DropdownMenuItem(
              value: 'invoice',
              child: Text('Invoice / payment request'),
            ),
            DropdownMenuItem(value: 'link', child: Text('Web link')),
          ],
          onChanged: editable ? (v) => setState(() => _channel = v!) : null,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('defender-message'),
          controller: _message,
          enabled: editable,
          maxLength: 12000,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Message or link',
            alignLabelWithHint: true,
            hintText: 'Paste the request you want to check…',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        _text(
          'Remove passwords, codes and personal details first. Reports save findings and destination domains, not your original pasted text.',
          style: TextStyle(
            fontSize: 12,
            color: c.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: editable
                  ? () {
                      setState(() {
                        _message.text =
                            'URGENT: Our bank account details have changed. Please send payment immediately and keep this confidential.';
                        _channel = 'invoice';
                      });
                    }
                  : null,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Try a sample'),
            ),
          ],
        ),
        Material(
          color: Colors.transparent,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Compare with an official domain'),
            subtitle: const Text('Optional · use a domain you already know'),
            children: [
              TextField(
                controller: _domain,
                enabled: editable,
                maxLength: 253,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Expected official domain',
                  hintText: 'example.com',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: const Text('Add a deeper KORLIX review'),
            subtitle: const Text(
              '1 generation credit · Sends this text to OpenAI with your consent. Quick findings appear first.',
            ),
            value: _ai,
            onChanged: editable ? (v) => setState(() => _ai = v) : null,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: editable && _message.text.trim().isNotEmpty
                ? () => _create()
                : null,
            icon: Icon(_ai ? Icons.auto_awesome : Icons.search),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                _ai
                    ? 'Check + KORLIX review · 1 credit'
                    : 'Run free quick check',
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _text(
          'Checks examine the text and link structure only. No sites are opened, and no inbox, device or network is scanned.',
          style: TextStyle(
            fontSize: 12,
            color: c.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
  Widget _habitSummary() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 32, color: c.primary),
        const SizedBox(height: 16),
        Text(
          'Small habits.\nStronger defenses.',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Text(
          '$_confirmed of ${_habits.length} habits confirmed',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: _habits.isEmpty ? 0 : _confirmed / _habits.length,
          minHeight: 7,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 12),
        _text(
          'Your personal checklist is based on what you confirm. It is not a device scan or a security score.',
          style: TextStyle(
            fontSize: 13,
            color: c.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: blocked ? null : () => _tab('habits'),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Build safer habits'),
        ),
        const Divider(height: 36),
        _text(
          'Already clicked or shared something?',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: blocked ? null : () => _tab('incident'),
          icon: const Icon(Icons.health_and_safety_outlined),
          label: const Text('Get incident help'),
        ),
      ],
    ),
  );
  Widget _checklist() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Make the basics second nature.',
          'Confirm the habits you already follow, then choose your next improvement.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ['personal', 'business'])
              ChoiceChip(
                label: Text(mode == 'personal' ? 'Personal' : 'Business'),
                selected: (_profile['mode'] ?? 'personal') == mode,
                onSelected: blocked || _pendingEvent != null
                    ? null
                    : (_) => _change('mode', mode: mode),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _pill(
          '$_confirmed / ${_habits.length} confirmed',
          Icons.check_circle_outline,
        ),
        const SizedBox(height: 16),
        _text(
          'Self-reported progress. These settings are not checked or changed automatically.',
          style: TextStyle(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        for (final h in _habits)
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              key: Key('habit-${h['id']}'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(h['title']),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _text(h['detail']),
              ),
              value: _checks[h['id']] == true,
              onChanged: blocked || _pendingEvent != null
                  ? null
                  : (v) => _change(h['id'], checked: v),
            ),
          ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: blocked ? null : () => _source('business'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Read CISA guidance'),
        ),
      ],
    ),
  );
  Widget _incidents() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Something happened. Let’s take it step by step.',
        'Choose the situation closest to yours. These guides are free and save your progress.',
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth >= 720
              ? (box.maxWidth - 16) / 2
              : box.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final s in defenderItems(_data['incidents']))
                SizedBox(
                  width: width,
                  child: _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pill(
                          '${s['steps']} guided steps',
                          Icons.route_outlined,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s['title'],
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        _text(s['description']),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: editable
                              ? () => _create(scenario: s['id'])
                              : null,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Open recovery guide'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      _text(
        'For a work account or device, involve your IT or security team promptly. Opening a guide does not contact anyone or make changes to your accounts.',
        style: TextStyle(color: c.onSurfaceVariant, height: 1.5),
      ),
    ],
  );
  Widget _saved() {
    final query = _search.text.trim().toLowerCase(),
        rows = _reports
            .where(
              (r) => '${r['title']} ${_concern(r['concern'])}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Your checks, in one place.',
          'Revisit findings, track next steps and export a report.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search saved reports',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        if (rows.isEmpty)
          _panel(
            Column(
              children: [
                Icon(Icons.folder_open, size: 44, color: c.primary),
                const SizedBox(height: 16),
                Text(
                  query.isEmpty
                      ? 'Your first check starts here.'
                      : 'No reports match this search.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (query.isEmpty)
                  FilledButton(
                    onPressed: blocked ? null : () => _tab('check'),
                    child: const Text('Check a message'),
                  ),
              ],
            ),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(
                        _concern(r['concern']),
                        Icons.shield_outlined,
                        color: _risk(r['concern']),
                      ),
                      if (r['state'] == 'preparing')
                        _pill('KORLIX is reviewing', Icons.hourglass_top),
                      if (r['state'] == 'failed')
                        _pill('Quick check available', Icons.info_outline),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    r['title'] ?? 'Saved report',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _text(
                    '${defenderMap(r['progress']).values.where((x) => x == true).length} of ${r['actionCount']} next steps confirmed · ${(r['created_at']?.toString() ?? '').split('T').first}',
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: blocked ? null : () => _open(r['id']),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Open report'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _result() {
    final r = _report!,
        b = defenderMap(r['result']),
        a = defenderMap(r['review']),
        p = defenderMap(r['progress']),
        risk = _effective(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: blocked ? null : () => _tab('saved'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Saved reports'),
        ),
        const SizedBox(height: 10),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pill(_concern(risk), Icons.shield_outlined, color: _risk(risk)),
              const SizedBox(height: 18),
              _heading(b['title'], b['summary']),
              const SizedBox(height: 16),
              _text(
                'This result is guidance, not verification that a message is genuine or that an account is secure.',
                style: TextStyle(color: c.onSurfaceVariant, height: 1.5),
              ),
              if (r['state'] == 'preparing') ...[
                _banner(
                  'Quick findings are ready. KORLIX is looking more closely; you can leave and return to this saved report.',
                  Icons.auto_awesome,
                ),
                const LinearProgressIndicator(),
              ],
              if (r['error'] != null) _banner(r['error'], Icons.info_outline),
              for (final f in defenderItems(b['findings']))
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f['title'],
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _risk(f['severity']),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _text(f['detail']),
                    ],
                  ),
                ),
              if ((b['domains'] as List).isNotEmpty) ...[
                const Divider(height: 36),
                const Text(
                  'Destinations found in the text',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final d in b['domains'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(
                      d.toString(),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                _text(
                  'Dots are separated so these addresses stay as text. Short links and redirects were not followed.',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              if (a.isNotEmpty) ...[
                const Divider(height: 36),
                _pill('KORLIX deeper review', Icons.auto_awesome),
                const SizedBox(height: 16),
                _text(a['summary'] ?? ''),
                for (final observation in (a['observations'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _text('• $observation'),
                  ),
                const SizedBox(height: 12),
                _text(
                  a['uncertainty'] ?? '',
                  style: TextStyle(
                    color: c.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'Your next steps',
                'Mark each action as you complete it. KORLIX does not perform these actions for you.',
              ),
              const SizedBox(height: 16),
              for (final step in defenderItems(b['actions']))
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: p[step['id']] == true,
                    onChanged: blocked || _pendingEvent != null
                        ? null
                        : (v) => _change(step['id'], checked: v, report: true),
                    title: Text(
                      step['title'],
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _text(step['detail']),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: blocked ? null : _export,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export report'),
                  ),
                  TextButton.icon(
                    onPressed: blocked
                        ? null
                        : () => _source(b['source'] ?? 'phishing'),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('Official guidance'),
                  ),
                  TextButton.icon(
                    onPressed:
                        blocked ||
                            _pendingEvent != null ||
                            r['state'] == 'preparing'
                        ? null
                        : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete report'),
                  ),
                ],
              ),
              if (defenderMap(r['details'])['kind'] != 'incident')
                TextButton(
                  onPressed: blocked ? null : () => _tab('incident'),
                  child: const Text('Already clicked or shared something?'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _banner(String message, IconData icon, {bool error = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: error ? c.errorContainer : c.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: error ? c.onErrorContainer : c.onSecondaryContainer,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: error ? c.onErrorContainer : c.onSecondaryContainer,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: c.surfaceContainerLowest,
    appBar: AppBar(
      title: const Text('Cybersecurity Defender'),
      actions: [
        IconButton(
          tooltip: 'Refresh Defender',
          onPressed: blocked ? null : () => _work(_refresh),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 500 ? 16 : 28,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_locked) ...[
                  if (_view == 'check')
                    _hero()
                  else
                    _pill('KORLIX DEFENDER', Icons.shield_outlined),
                  const SizedBox(height: 24),
                  _navigation(),
                  const SizedBox(height: 24),
                ],
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: _banner(_error!, Icons.error_outline, error: true),
                  ),
                if (_notice != null)
                  Semantics(
                    liveRegion: true,
                    child: _banner(_notice!, Icons.check_circle_outline),
                  ),
                if (_pendingCreate != null && !_busy && !_locked)
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _text(
                          'Your request is unconfirmed. Retry the same request or refresh Saved reports before starting another check.',
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: blocked ? null : () => _create(),
                          child: const Text('Retry same request'),
                        ),
                      ],
                    ),
                  ),
                if (_pendingEvent != null && !_busy && !_locked)
                  _panel(
                    Column(
                      children: [
                        _text(
                          'This change is unconfirmed. Retry it, or refresh to load saved progress.',
                        ),
                        TextButton(
                          onPressed: blocked ? null : _retryChange,
                          child: const Text('Retry progress change'),
                        ),
                      ],
                    ),
                  ),
                if (_loading || _busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (!_locked && !_loading)
                  switch (_view) {
                    'habits' => _checklist(),
                    'incident' => _incidents(),
                    'saved' => _saved(),
                    'report' => _report == null ? _saved() : _result(),
                    _ => _start(),
                  },
                const SizedBox(height: 24),
                if (!_locked)
                  _text(
                    'KORLIX Defender · Guidance for people and small businesses. Official resources: FTC and CISA.',
                    style: TextStyle(
                      color: c.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

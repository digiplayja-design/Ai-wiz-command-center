import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'app_studio_client.dart';
import 'app_preview.dart';
import 'app_portal_screen.dart';

typedef AppFileSaver = Future<void> Function(Uint8List, String, String, Rect);
const appStarters = <Map<String, String>>[
  {
    'id': 'crm',
    'name': 'Client CRM',
    'tag': 'Contacts, leads & opportunities',
    'idea':
        'Create a CRM for a small service business to track contacts, sales opportunities and next steps.',
  },
  {
    'id': 'bookings',
    'name': 'Booking tracker',
    'tag': 'Clients, services & appointments',
    'idea':
        'Create an appointment tracker for a salon with services, client names, dates and booking status.',
  },
  {
    'id': 'inventory',
    'name': 'Inventory',
    'tag': 'Products, stock & suppliers',
    'idea':
        'Create an inventory app for a small shop with products, stock counts, prices and suppliers.',
  },
  {
    'id': 'projects',
    'name': 'Project board',
    'tag': 'Tasks, owners & deadlines',
    'idea':
        'Create a project management app with a task board, owners, due dates and project goals.',
  },
  {
    'id': 'fieldwork',
    'name': 'Field service',
    'tag': 'Jobs, visits & technicians',
    'idea':
        'Create a mobile-friendly field service app for scheduling job visits and tracking completion.',
  },
  {
    'id': 'personal',
    'name': 'Personal planner',
    'tag': 'Habits, goals & everyday wins',
    'idea': 'Create a personal planner for tracking daily habits and goals.',
  },
];
Map<String, dynamic> appMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> appRows(dynamic v) =>
    v is List ? v.map(appMap).toList() : [];

class AppStudioScreen extends StatefulWidget {
  const AppStudioScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.saveFile = saveBookkeepingFile,
    this.previewBuilder,
  });
  final AppStudioClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final AppFileSaver saveFile;
  final Widget Function(String)? previewBuilder;
  @override
  State<AppStudioScreen> createState() => _AppStudioScreenState();
}

class _AppStudioScreenState extends State<AppStudioScreen> {
  final _idea = TextEditingController(),
      _audience = TextEditingController(),
      _change = TextEditingController(),
      _name = TextEditingController(),
      _search = TextEditingController();
  final _scroll = ScrollController();
  final _builderKey = GlobalKey();
  List<Map<String, dynamic>> _projects = [], _versions = [];
  Map<String, dynamic>? _project,
      _run,
      _pendingCreate,
      _pendingBuild,
      _pendingStyle,
      _pendingRestore;
  String? _preview, _error, _notice;
  String _view = 'create',
      _tab = 'preview',
      _design = 'Clean & modern',
      _accent = '#176BCA',
      _appTheme = 'light';
  bool _pendingCreateWantsBuild = false;
  bool _busy = false,
      _loading = true,
      _locked = false,
      _phone = false,
      _dialog = false,
      _allowPop = false,
      _polling = false;
  Timer? _timer;
  ColorScheme get colors => Theme.of(context).colorScheme;
  bool get running => _run?['state'] == 'running';
  bool get blocked => _busy || running || _locked;
  bool get hasSpec => (_project?['version'] as int? ?? 0) > 0;
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
    for (final c in [_idea, _audience, _change, _name, _search]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted || _locked) return;
    if (_dialog) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _project = null;
      _run = null;
      _preview = null;
      _projects = [];
      _versions = [];
      _pendingCreate = null;
      _pendingBuild = null;
      _pendingStyle = null;
      _pendingRestore = null;
      for (final c in [_idea, _audience, _change, _name, _search]) {
        c.clear();
      }
      _error =
          'Your sign-in changed. Close App Studio and reopen it after signing in.';
    });
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load() async {
    try {
      final rows = await widget.client.list();
      if (mounted && !_locked) setState(() => _projects = rows);
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _accept(Map<String, dynamic> d) {
    _project = appMap(d['project']);
    _versions = appRows(d['versions']);
    _run = d['run'] == null ? null : appMap(d['run']);
    _preview = d['previewHtml'] as String?;
    final s = appMap(_project!['spec']);
    _name.text = s['name']?.toString() ?? _project!['name'].toString();
    _accent = s['accent']?.toString() ?? '#176BCA';
    _appTheme = s['theme']?.toString() ?? 'light';
    if (_run?['state'] == 'failed' && _change.text.isEmpty) {
      _change.text = _run?['message']?.toString() ?? '';
    }
  }

  Future<void> _open(String id, {bool navigate = true}) async {
    final switching = navigate && _project?['id'] != id;
    if (switching &&
        (_change.text.trim().isNotEmpty ||
            _pendingBuild != null ||
            _pendingStyle != null) &&
        !await _confirm(
          'Open another project?',
          'Unsaved edits will be discarded. Saved versions and submitted builds remain available.',
          'Open project',
        )) {
      return;
    }
    final d = await widget.client.open(id);
    if (!mounted || _locked) return;
    setState(() {
      if (switching) {
        _change.clear();
        _pendingBuild = null;
        _pendingStyle = null;
        _pendingRestore = null;
      }
      _accept(d);
      if (navigate) {
        _view = 'project';
        _tab = 'preview';
      }
      _error = appMap(_run)['state'] == 'failed'
          ? appMap(_run)['error']?.toString()
          : null;
    });
    if (navigate) _top();
  }

  Future<void> _work(Future<void> Function() fn) async {
    if (_busy || _locked) return;
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

  Future<void> _poll() async {
    if (!running || _polling || _busy || _locked || _project == null) return;
    _polling = true;
    try {
      final id = _project!['id'] as String, d = await widget.client.open(id);
      if (!mounted || _locked || _project?['id'] != id) return;
      final next = appMap(d['run']);
      setState(() {
        _run = next;
        if (next['state'] != 'running') {
          _accept(d);
          _pendingBuild = null;
          _notice = next['state'] == 'completed'
              ? 'Your new version is ready. Try it in the preview.'
              : null;
          _error = next['state'] == 'failed' ? next['error']?.toString() : null;
        }
      });
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () => _error =
              'Could not refresh build progress. Your project is saved; use Refresh to check again.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    if (_locked) return false;
    _dialog = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    _dialog = false;
    return yes == true && !_locked;
  }

  Future<bool> _consent() async {
    _dialog = true;
    try {
      return await widget.ensureConsent(context) && !_locked;
    } finally {
      _dialog = false;
    }
  }

  Future<void> _create({String? starter, bool build = false}) async {
    if (_pendingCreate == null &&
        _idea.text.trim().length < 10 &&
        starter == null) {
      setState(
        () => _error =
            'Describe your app in at least 10 characters, or choose a starter.',
      );
      return;
    }
    final wantsBuild = _pendingCreate == null
        ? build
        : _pendingCreateWantsBuild;
    await _work(() async {
      if (wantsBuild && !await _consent()) return;
      if (!mounted || _locked) return;
      final selected = starter == null
          ? null
          : appStarters.firstWhere((s) => s['id'] == starter);
      final body =
          _pendingCreate ??
          {
            'request_key': appRequestKey(),
            'idea': selected?['idea'] ?? _idea.text.trim(),
            'audience': _audience.text.trim(),
            'style': _design,
            'template': starter,
          };
      _pendingCreate = body;
      _pendingCreateWantsBuild = wantsBuild;
      Map<String, dynamic> p;
      try {
        p = await widget.client.create(body);
      } on AppStudioException catch (e) {
        if ([400, 403, 409, 422, 429].contains(e.status)) _pendingCreate = null;
        rethrow;
      }
      if (!mounted || _locked) return;
      _pendingCreate = null;
      _idea.clear();
      _audience.clear();
      await _open(p['id'] as String);
      await _load();
      if (wantsBuild && mounted && !_locked && _project?['id'] == p['id']) {
        await _startBuild(message: 'Build the app described in my saved idea.');
      }
    });
  }

  Future<void> _startBuild({String? message}) async {
    if (_project == null || _locked) return;
    final body =
        _pendingBuild ??
        {
          'request_key': appRequestKey(),
          'version': _project!['version'],
          'message': message ?? _change.text.trim(),
          'consent': true,
        };
    if ((body['message'] as String).trim().isEmpty) {
      throw const AppStudioException('Describe the change you want first.');
    }
    _pendingBuild = body;
    try {
      final run = await widget.client.build(_project!['id'], body);
      if (!mounted || _locked) return;
      setState(() {
        _run = run;
        _change.clear();
        _pendingBuild = null;
        _notice = run['state'] == 'running'
            ? 'KORLIX is designing your app. Your project is saved.'
            : null;
      });
      if (run['state'] != 'running') {
        await _open(_project!['id'], navigate: false);
        if (mounted && !_locked) {
          setState(() {
            if (run['state'] == 'completed') {
              _notice = 'Your new version is ready. Try it in the preview.';
            }
          });
        }
      }
    } on AppStudioException catch (e) {
      if ([400, 403, 409, 422, 429].contains(e.status)) _pendingBuild = null;
      rethrow;
    }
  }

  Future<void> _refine() => _work(() async {
    if (!await _consent()) return;
    await _startBuild(
      message: hasSpec ? null : 'Build the app described in my saved idea.',
    );
  });
  Future<void> _style() => _work(() async {
    final body =
        _pendingStyle ??
        {
          'request_key': appRequestKey(),
          'version': _project!['version'],
          'name': _name.text.trim(),
          'accent': _accent,
          'theme': _appTheme,
        };
    _pendingStyle = body;
    try {
      await widget.client.style(_project!['id'], body);
      if (!mounted || _locked) return;
      _pendingStyle = null;
      await _open(_project!['id'], navigate: false);
      setState(
        () => _notice = 'Style saved as a new version. No AI credit used.',
      );
    } on AppStudioException catch (e) {
      if ([400, 409, 422].contains(e.status)) _pendingStyle = null;
      rethrow;
    }
  });
  Future<void> _restore(Map<String, dynamic> v) async {
    if (!await _confirm(
      'Restore version ${v['version']}?',
      'This creates a new version. Your recent versions remain available.',
      'Restore',
    )) {
      return;
    }
    await _work(() async {
      final body =
          _pendingRestore ??
          {
            'request_key': appRequestKey(),
            'version': _project!['version'],
            'version_id': v['id'],
          };
      _pendingRestore = body;
      try {
        await widget.client.restore(_project!['id'], body);
        if (!mounted || _locked) return;
        _pendingRestore = null;
        await _open(_project!['id'], navigate: false);
        setState(() => _notice = 'Earlier design restored as a new version.');
      } on AppStudioException catch (e) {
        if ([400, 409, 404].contains(e.status)) _pendingRestore = null;
        rethrow;
      }
    });
  }

  Future<void> _export() => _work(() async {
    final p = Map<String, dynamic>.from(_project!),
        bytes = await widget.client.export(p['id']);
    if (!mounted || _locked) return;
    final size = MediaQuery.sizeOf(context);
    await widget.saveFile(
      Uint8List.fromList(bytes),
      'KORLIX-App-${p['id']}-v${p['version']}.zip',
      'application/zip',
      Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1),
    );
    if (mounted && !_locked) {
      setState(
        () => _notice =
            'Download started. Extract the ZIP and open index.html to run your app.',
      );
    }
  });
  Future<void> _portals({bool currentProject = false}) async {
    if (blocked || currentProject && !hasSpec) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppPortalScreen(
          client: widget.client,
          project: currentProject ? Map<String, dynamic>.from(_project!) : null,
          disposeClient: false,
        ),
      ),
    );
  }

  Future<void> _remove(Map<String, dynamic> p) async {
    if (!await _confirm(
      'Delete ${p['name']}?',
      'The saved idea, all app versions and any hosted customer portal will be removed, including its requests and memberships. Download the prototype first if you want a copy.',
      'Delete project',
    )) {
      return;
    }
    await _work(() async {
      await widget.client.remove(p['id']);
      if (!mounted || _locked) return;
      if (_project?['id'] == p['id']) {
        setState(() {
          _project = null;
          _preview = null;
          _run = null;
        });
      }
      await _load();
    });
  }

  Future<void> _leave() async {
    if (_allowPop) return;
    final dirty =
        (_view == 'create' && _idea.text.trim().isNotEmpty) ||
        _pendingCreate != null ||
        _pendingBuild != null ||
        _change.text.trim().isNotEmpty;
    if (dirty &&
        !await _confirm(
          'Leave App Studio?',
          'Your saved projects remain available. Unsaved text on this screen will be discarded. If a build started, reopen the project to check its result.',
          'Leave',
        )) {
      return;
    }
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(padding: padding, child: child),
      );
  Widget _title(String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 7),
      Text(body, style: TextStyle(color: colors.onSurfaceVariant)),
      const SizedBox(height: 18),
    ],
  );
  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    int lines = 1,
    int max = 5000,
    bool enabled = true,
  }) => TextField(
    controller: c,
    enabled: !blocked && enabled,
    maxLength: max,
    maxLines: lines,
    minLines: lines > 1 ? 3 : 1,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
  Widget _banner(String value, bool error) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? colors.errorContainer : colors.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.info_outline : Icons.check_circle_outline,
          color: error ? colors.onErrorContainer : colors.onPrimaryContainer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: error
                  ? colors.onErrorContainer
                  : colors.onPrimaryContainer,
            ),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('KORLIX App Studio'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy || _locked
                ? null
                : () => _work(() async {
                    if (_view == 'project' && _project != null) {
                      await _open(_project!['id'], navigate: false);
                    }
                    await _load();
                  }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _locked
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: _banner(_error!, true),
              )
            : LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Create an app'),
                                selected: _view == 'create',
                                onSelected: _busy
                                    ? null
                                    : (_) {
                                        setState(() => _view = 'create');
                                        _top();
                                      },
                              ),
                              ChoiceChip(
                                label: Text(
                                  'My projects${_projects.isEmpty ? '' : ' (${_projects.length})'}',
                                ),
                                selected: _view == 'library',
                                onSelected: _busy
                                    ? null
                                    : (_) {
                                        setState(() => _view = 'library');
                                        _load();
                                        _top();
                                      },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.public, size: 18),
                                label: const Text('My portals'),
                                onPressed: blocked ? null : () => _portals(),
                              ),
                              if (_project != null)
                                ChoiceChip(
                                  label: const Text('Current project'),
                                  selected: _view == 'project',
                                  onSelected: _busy
                                      ? null
                                      : (_) {
                                          setState(() => _view = 'project');
                                          _top();
                                        },
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) _banner(_error!, true),
                          if (_notice != null) _banner(_notice!, false),
                          if (_busy) const LinearProgressIndicator(),
                          if (_busy) const SizedBox(height: 14),
                          if (_view == 'create') _createView(box.maxWidth),
                          if (_view == 'library') _library(),
                          if (_view == 'project' && _project != null)
                            _projectView(box.maxWidth),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
  Widget _createView(double width) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.primaryContainer, colors.surface],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 32),
            const SizedBox(height: 14),
            Text(
              'Your idea. Your app.\nLet’s make it real.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Describe what you want, try a working preview, then shape it with KORLIX.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _mini(Icons.touch_app_outlined, 'Interactive preview'),
                _mini(Icons.history, 'Saved versions'),
                _mini(Icons.download_outlined, 'Your source code'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'What would you like to build?',
              'One clear sentence is enough to start.',
            ),
            _field(
              _idea,
              'Your app idea',
              'A simple app for my cleaning business to track customers, jobs and payments due…',
              lines: 4,
              enabled: _pendingCreate == null,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Add a little direction'),
              children: [
                _field(
                  _audience,
                  'Who is it for?',
                  'Small business owners, my team, students…',
                  max: 200,
                  enabled: _pendingCreate == null,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            'Clean & modern',
                            'Bold & colorful',
                            'Calm & minimal',
                            'Dark & polished',
                          ]
                          .map(
                            (s) => ChoiceChip(
                              label: Text(s),
                              selected: _design == s,
                              onSelected: blocked || _pendingCreate != null
                                  ? null
                                  : (_) => setState(() => _design = s),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 18),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: blocked ? null : () => _create(build: true),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _pendingCreate != null
                        ? 'Retry saved request'
                        : 'Build my app · 1 credit',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: blocked ? null : () => _create(),
                  icon: const Icon(Icons.bookmark_border),
                  label: const Text('Save idea'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'AI builds use 1 generation credit. Failed builds return it. Starters, styling, previews and exports use no AI credits.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      _title(
        'Or start with something useful',
        'Open a starter instantly. Make it yours as you go.',
      ),
      LayoutBuilder(
        builder: (context, c) {
          final columns = c.maxWidth > 950
              ? 3
              : c.maxWidth > 620
              ? 2
              : 1;
          final item = (c.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: appStarters
                .asMap()
                .entries
                .map(
                  (e) => SizedBox(
                    width: item,
                    child: _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            [
                              Icons.people_outline,
                              Icons.calendar_month_outlined,
                              Icons.inventory_2_outlined,
                              Icons.view_kanban_outlined,
                              Icons.handyman_outlined,
                              Icons.wb_sunny_outlined,
                            ][e.key],
                            size: 28,
                            color: colors.primary,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            e.value['name']!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            e.value['tag']!,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton(
                            onPressed: blocked || _pendingCreate != null
                                ? null
                                : () => _create(starter: e.value['id']),
                            child: const Text('Use starter'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 22),
      Text(
        'Build useful prototypes with records, forms, search and status boards. Publish a customer portal from any saved design for shared requests, replies and private files. Other custom app features remain in your local prototype.',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      ),
    ],
  );
  Widget _mini(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 18), const SizedBox(width: 7), Text(label)],
  );
  Widget _library() {
    final query = _search.text.trim().toLowerCase(),
        rows = _projects
            .where(
              (p) => ('${p['name']} ${appMap(p['brief'])['idea']}')
                  .toLowerCase()
                  .contains(query),
            )
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          'Your ideas, kept together',
          'Pick up where you left off. Up to 50 saved projects.',
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search your projects',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          _card(
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No projects here yet. Describe your idea or open a starter.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...rows.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name'].toString(),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appMap(p['brief'])['idea']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            p['version'] == 0
                                ? 'Saved idea'
                                : 'Version ${p['version']}',
                          ),
                        ),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _work(() => _open(p['id'])),
                          child: const Text('Open project'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _remove(p),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _projectView(double width) {
    final panel = Container(key: _builderKey, child: _builderPanel()),
        preview = _previewPanel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _project!['name'].toString(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasSpec
                      ? 'Version ${_project!['version']} · Local web prototype'
                      : 'Saved idea · Ready to build',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: blocked || !hasSpec
                      ? null
                      : () => _portals(currentProject: true),
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: const Text('Customer portal'),
                ),
                OutlinedButton.icon(
                  onPressed: blocked || !hasSpec ? null : _export,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export app'),
                ),
              ],
            ),
          ],
        ),
        if (width < 1000 && hasSpec)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final c = _builderKey.currentContext;
                  if (c != null) {
                    Scrollable.ensureVisible(
                      c,
                      duration: const Duration(milliseconds: 250),
                    );
                  }
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Make changes'),
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (running)
          _banner(
            'KORLIX is designing your next version. This can take a few minutes. Your project is saved, so you can leave and return.',
            false,
          ),
        if (width >= 1000)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 350, child: panel),
              const SizedBox(width: 22),
              Expanded(child: preview),
            ],
          )
        else ...[
          if (hasSpec) ...[
            preview,
            const SizedBox(height: 20),
            panel,
          ] else ...[
            panel,
            const SizedBox(height: 20),
            preview,
          ],
        ],
      ],
    );
  }

  Widget _builderPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              hasSpec ? 'Build it your way' : 'Ready when you are',
              hasSpec
                  ? 'Tell KORLIX what to change. Each build saves a new version.'
                  : 'Your idea is saved. Build an interactive first version.',
            ),
            if (hasSpec)
              _field(
                _change,
                'Ask for a change',
                'Add a priority field and organize tasks into a status board…',
                lines: 4,
                enabled: _pendingBuild == null,
              ),
            if (hasSpec)
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children:
                    ['Add a status board', 'Simplify the forms', 'Make it dark']
                        .map(
                          (s) => ActionChip(
                            label: Text(s),
                            onPressed: blocked || _pendingBuild != null
                                ? null
                                : () => setState(() => _change.text = s),
                          ),
                        )
                        .toList(),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: blocked ? null : _refine,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _pendingBuild != null
                    ? 'Retry build request'
                    : hasSpec
                    ? 'Build new version · 1 credit'
                    : 'Build first version · 1 credit',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'One credit is reserved while building and returned if the build fails.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      if (hasSpec) ...[
        const SizedBox(height: 16),
        _card(
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Make it yours'),
            subtitle: const Text('Style changes use no AI credits'),
            children: [
              const SizedBox(height: 16),
              _field(
                _name,
                'App name',
                'Your app name',
                max: 80,
                enabled: _pendingStyle == null,
              ),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children:
                    [
                          '#176BCA',
                          '#087F68',
                          '#7C3AED',
                          '#E05C27',
                          '#A33C79',
                          '#2958A3',
                        ]
                        .map(
                          (color) => Tooltip(
                            message: color,
                            child: ChoiceChip(
                              avatar: CircleAvatar(
                                radius: 9,
                                backgroundColor: Color(
                                  int.parse(
                                    'FF${color.substring(1)}',
                                    radix: 16,
                                  ),
                                ),
                              ),
                              label: Text(color == _accent ? 'Selected' : ' '),
                              selected: _accent == color,
                              onSelected: blocked || _pendingStyle != null
                                  ? null
                                  : (_) => setState(() => _accent = color),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: ['light', 'dark']
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t == 'light' ? 'Light' : 'Dark'),
                        selected: _appTheme == t,
                        onSelected: blocked || _pendingStyle != null
                            ? null
                            : (_) => setState(() => _appTheme = t),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: blocked ? null : _style,
                child: Text(
                  _pendingStyle == null ? 'Save style' : 'Retry style save',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A clear path to launch',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              '1. Try the preview with sample data.\n2. Refine the fields and flow.\n3. Export and test your app.\n4. Connect real services before launch.',
            ),
            const SizedBox(height: 10),
            Text(
              'Preview entries are temporary. They are not sent to KORLIX or included in app exports.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _previewPanel() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['preview', 'plan', 'versions']
              .map(
                (t) => ChoiceChip(
                  label: Text(
                    {
                      'preview': 'Preview',
                      'plan': 'App plan',
                      'versions': 'Versions',
                    }[t]!,
                  ),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        if (_tab == 'preview') ...[
          _previewControls(),
          const SizedBox(height: 14),
          if (!hasSpec)
            const SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  'Your interactive app preview will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _phone ? 390 : double.infinity,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 680,
                    child:
                        widget.previewBuilder?.call(_preview ?? '') ??
                        AppPreview(
                          key: ValueKey(
                            '${_project!['id']}-${_project!['version']}',
                          ),
                          html: _preview ?? '',
                        ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Try adding, editing, searching and deleting sample records. Preview data resets when you reload or change versions.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ] else if (_tab == 'plan')
          _plan()
        else
          _history(),
      ],
    ),
  );
  Widget _previewControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ChoiceChip(
        avatar: const Icon(Icons.desktop_windows_outlined, size: 18),
        label: const Text('Desktop'),
        selected: !_phone,
        onSelected: (_) => setState(() => _phone = false),
      ),
      ChoiceChip(
        avatar: const Icon(Icons.phone_iphone, size: 18),
        label: const Text('Phone'),
        selected: _phone,
        onSelected: (_) => setState(() => _phone = true),
      ),
      const Chip(label: Text('Sample data')),
    ],
  );
  Widget _plan() {
    final spec = appMap(_project!['spec']), cols = appRows(spec['collections']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'What your app does',
          spec['description']?.toString() ??
              appMap(_project!['brief'])['idea'].toString(),
        ),
        for (final c in cols)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['label']} · ${c['layout'] == 'board' ? 'Status board' : 'Searchable records'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(appRows(c['fields']).map((f) => f['label']).join(' · ')),
              ],
            ),
          ),
        if (hasSpec) ...[
          const Divider(),
          const Text(
            'Working in this prototype',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Navigation, add/edit/delete, search, field validation, choice filters and status boards. The downloaded app can save data in the same browser.',
          ),
          const SizedBox(height: 20),
          const Text(
            'Before you launch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shared accounts, secure authentication, payments and live integrations are not connected. Hosting and native app-store packaging are separate steps.',
          ),
          for (final s in (spec['nextSteps'] as List? ?? []))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('• $s'),
            ),
          const SizedBox(height: 20),
          const Text(
            'Latest changes',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final s in (spec['changes'] as List? ?? []))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('• $s'),
            ),
        ],
      ],
    );
  }

  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        'Room to experiment',
        'Restore any of the last 30 saved versions. Restoring creates a new version and uses no AI credit.',
      ),
      if (_versions.isEmpty)
        const Text('Your first version will appear after a build.'),
      for (final v in _versions)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${v['version']}${v['version'] == _project!['version'] ? ' · Current' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(v['label']?.toString() ?? 'Saved version'),
                const SizedBox(height: 8),
                if (v['version'] != _project!['version'])
                  OutlinedButton(
                    onPressed: blocked ? null : () => _restore(v),
                    child: Text('Restore version ${v['version']}'),
                  ),
              ],
            ),
            padding: const EdgeInsets.all(16),
          ),
        ),
    ],
  );
}

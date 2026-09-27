import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'study_client.dart';

typedef StudyFileSaver = Future<void> Function(Uint8List, String, String, Rect);
const studyStarters = [
  {
    'id': 'percentages',
    'name': 'Everyday percentages',
    'description': 'Discounts, proportions and changes.',
    'icon': Icons.percent_rounded,
  },
  {
    'id': 'photosynthesis',
    'name': 'Photosynthesis basics',
    'description': 'How plants turn light into stored energy.',
    'icon': Icons.eco_outlined,
  },
  {
    'id': 'paragraphs',
    'name': 'Clearer writing',
    'description': 'Build a paragraph that makes one point well.',
    'icon': Icons.edit_note_rounded,
  },
];

class StudyScreen extends StatefulWidget {
  const StudyScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.saveFile = saveBookkeepingFile,
  });
  final StudyClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final StudyFileSaver saveFile;
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final _topic = TextEditingController(),
      _notes = TextEditingController(),
      _search = TextEditingController();
  final _scroll = ScrollController();
  final _activityKey = GlobalKey();
  List<Map<String, dynamic>> _sets = [];
  Map<String, dynamic>? _pack, _pendingCreate, _pendingEvent;
  String _view = 'start',
      _tab = 'learn',
      _level = 'beginner',
      _goal = 'understand';
  String? _error, _notice;
  int _minutes = 10, _section = 0, _card = 0, _question = 0, _remaining = 600;
  int? _choice;
  bool _busy = false,
      _loading = true,
      _locked = false,
      _dialog = false,
      _allowPop = false,
      _polling = false,
      _revealed = false,
      _hint = false,
      _correcting = false,
      _dueOnly = false;
  DateTime? _endsAt;
  Timer? _clock, _pollTimer;
  ColorScheme get c => Theme.of(context).colorScheme;
  bool get preparing => _pack?['state'] == 'preparing';
  bool get blocked => _busy || _locked;
  bool get editable => !blocked && _pendingEvent == null;
  Map<String, dynamic> get lesson => studyMap(_pack?['lesson']);
  Map<String, dynamic> get progress => studyMap(_pack?['progress']);
  List<Map<String, dynamic>> get cards => studyItems(lesson['cards']);
  List<Map<String, dynamic>> get questions => studyItems(lesson['quiz']);
  List<Map<String, dynamic>> get sections => studyItems(lesson['sections']);
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_endsAt != null && mounted) {
        setState(() {
          _remaining =
              (_endsAt!.difference(DateTime.now()).inMilliseconds / 1000)
                  .ceil()
                  .clamp(0, 1200);
          if (_remaining == 0) {
            _endsAt = null;
            _notice =
                'Focus time complete. Take a break or keep learning at your pace.';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pollTimer?.cancel();
    widget.client.dispose();
    for (final x in [_topic, _notes, _search]) {
      x.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted || _locked) return;
    if (_dialog) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _pack = null;
      _sets = [];
      _pendingCreate = null;
      _pendingEvent = null;
      _endsAt = null;
      _notice = null;
      for (final x in [_topic, _notes, _search]) {
        x.clear();
      }
      _error =
          'Your sign-in changed. Close Study Studio and reopen it after signing in.';
    });
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _focusActivity() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _activityKey.currentContext;
      if (mounted && !_locked && _view == 'study' && target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 180),
            alignment: 0,
          ),
        );
      }
    });
  }

  void _selectTab(String tab) {
    setState(() => _tab = tab);
    _focusActivity();
  }

  Future<void> _work(Future<void> Function() task) async {
    if (blocked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    try {
      final rows = await widget.client.list();
      if (mounted && !_locked) setState(() => _sets = rows);
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    if (_locked) return false;
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
            child: Text(action),
          ),
        ],
      ),
    );
    _dialog = false;
    return mounted && !_locked && yes == true;
  }

  void _accept(Map<String, dynamic> s, {bool reset = false}) {
    _pack = s;
    if (reset) {
      _section = 0;
      _card = 0;
      _question = 0;
      _choice = null;
      _hint = false;
      _revealed = false;
      _correcting = false;
      _dueOnly = false;
      _tab = 'learn';
      _remaining = (studyMap(s['details'])['minutes'] as int? ?? 10) * 60;
      _endsAt = null;
      final reads = studyMap(studyMap(s['progress'])['read']);
      final ss = studyItems(studyMap(s['lesson'])['sections']);
      for (var i = 0; i < ss.length; i++) {
        if (reads['$i'] != true) {
          _section = i;
          break;
        }
      }
    }
  }

  Future<void> _open(String id) async {
    await _work(() async {
      final s = await widget.client.open(id);
      if (!mounted || _locked) return;
      setState(() {
        _accept(s, reset: true);
        _pendingEvent = null;
        _view = 'study';
      });
      _top();
    });
  }

  Future<void> _refresh() async {
    await _work(() async {
      if (_view == 'study' && _pack != null) {
        final id = _pack!['id'];
        final s = await widget.client.open(id);
        if (!mounted || _locked || _pack?['id'] != id) return;
        setState(() {
          _accept(s);
          _pendingEvent = null;
          _choice = null;
          _correcting = false;
          _notice =
              'Progress refreshed. If your last change is missing, try it again.';
        });
      }
      await _load();
    });
  }

  Future<void> _poll() async {
    if (_polling || blocked || !preparing) return;
    _polling = true;
    final id = _pack!['id'];
    try {
      final s = await widget.client.open(id);
      if (mounted && !_locked && _pack?['id'] == id) {
        setState(() => _accept(s));
        if (s['state'] != 'preparing') await _load();
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      _polling = false;
    }
  }

  Future<void> _create({String? starter, String? topic}) async {
    if (blocked) return;
    if (_pendingCreate == null &&
        starter == null &&
        _topic.text.trim().isEmpty) {
      setState(
        () => _error =
            'What would you like to learn? Add a topic to get started.',
      );
      _top();
      return;
    }
    await _work(() async {
      final body =
          _pendingCreate ??
          {
            'request_key': studyRequestKey(),
            'topic': topic ?? _topic.text.trim(),
            'notes': starter == null ? _notes.text.trim() : '',
            'level': starter == null ? _level : 'beginner',
            'goal': starter == null ? _goal : 'understand',
            'minutes': starter == null ? _minutes : 5,
            'starter': starter,
          };
      if (body['starter'] == null) {
        _dialog = true;
        final consent = await widget.ensureConsent(context);
        _dialog = false;
        if (!mounted || _locked || !consent) return;
        body['consent'] = true;
      }
      _pendingCreate = body;
      try {
        final s = await widget.client.create(body);
        if (!mounted || _locked) return;
        setState(() {
          _accept(s, reset: true);
          _pendingCreate = null;
          _pendingEvent = null;
          _topic.clear();
          _notes.clear();
          _view = 'study';
        });
        _top();
        await _load();
      } on StudyException catch (e) {
        if ([400, 403, 404, 409, 422, 429].contains(e.status)) {
          _pendingCreate = null;
        }
        rethrow;
      }
    });
  }

  Future<void> _event(
    Map<String, dynamic> action, {
    VoidCallback? after,
  }) async {
    if (_pack == null || blocked) return;
    await _work(() async {
      final id = _pack!['id'];
      final body =
          _pendingEvent ??
          {
            'request_key': studyRequestKey(),
            'revision': _pack!['revision'],
            ...action,
          };
      _pendingEvent = body;
      try {
        final s = await widget.client.progress(id, body);
        if (!mounted || _locked || _pack?['id'] != id) return;
        setState(() {
          _accept(s);
          _pendingEvent = null;
          _choice = null;
          _correcting = false;
          _notice = 'Progress saved';
          after?.call();
        });
        if (['read', 'card', 'resetQuiz'].contains(body['event'])) {
          _focusActivity();
        }
      } on StudyException catch (e) {
        if ([400, 404, 409].contains(e.status)) _pendingEvent = null;
        rethrow;
      }
    });
  }

  Future<void> _navigate(String view) async {
    if (blocked) return;
    if (_pendingEvent != null) {
      if (!await _confirm(
        'Leave this study pack?',
        'The last save was not confirmed. Reopen this pack to check its saved progress.',
        'Leave pack',
      )) {
        return;
      }
    }
    _pendingEvent = null;
    setState(() {
      _view = view;
      _error = null;
      _notice = null;
      _endsAt = null;
    });
    _top();
    if (view == 'library') await _load();
  }

  Future<void> _leave() async {
    if (_allowPop) return;
    final dirty =
        _topic.text.trim().isNotEmpty ||
        _notes.text.trim().isNotEmpty ||
        _pendingCreate != null ||
        _pendingEvent != null;
    if (dirty &&
        !await _confirm(
          'Leave Study Studio?',
          'Saved study packs remain available. Unsaved text will be discarded. If preparation started, check My learning when you return.',
          'Leave',
        )) {
      return;
    }
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    if (!await _confirm(
      'Delete this study pack?',
      'The lesson, flashcards and saved progress will be removed. Export the guide first if you want a copy.',
      'Delete pack',
    )) {
      return;
    }
    await _work(() async {
      await widget.client.remove(s['id']);
      if (!mounted || _locked) return;
      setState(() {
        if (_pack?['id'] == s['id']) _pack = null;
        _view = 'library';
        _endsAt = null;
      });
      await _load();
    });
  }

  Future<void> _export() async {
    await _work(() async {
      final id = _pack!['id'];
      final bytes = await widget.client.export(id);
      if (!mounted || _locked || _pack?['id'] != id) return;
      final size = MediaQuery.sizeOf(context);
      await widget.saveFile(
        Uint8List.fromList(bytes),
        'KORLIX-Study-$id.txt',
        'text/plain',
        Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1),
      );
      if (mounted && !_locked) {
        setState(
          () => _notice =
              'Study guide export started, including flashcards and the answer key.',
        );
      }
    });
  }

  Widget _panel(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(22),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: c.outlineVariant),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _gap([double h = 16]) => SizedBox(height: h);
  Widget _title(String text, [String? description]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (description != null) ...[
        _gap(6),
        Text(
          description,
          style: TextStyle(color: c.onSurfaceVariant, height: 1.45),
        ),
      ],
    ],
  );
  Widget _badge(IconData icon, String label) => Chip(
    avatar: Icon(icon, size: 17),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
  Widget _message(String text, {bool error = false}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? c.errorContainer : c.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(
          color: error ? c.onErrorContainer : c.onSecondaryContainer,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close Study Studio',
          icon: const Icon(Icons.arrow_back),
          onPressed: _leave,
        ),
        title: const Text('KORLIX Study Studio'),
        actions: [
          IconButton(
            tooltip: 'Refresh study progress',
            onPressed: blocked ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Start learning'),
                        selected: _view == 'start',
                        onSelected: blocked ? null : (_) => _navigate('start'),
                      ),
                      ChoiceChip(
                        label: const Text('My learning'),
                        selected: _view == 'library',
                        onSelected: blocked
                            ? null
                            : (_) => _navigate('library'),
                      ),
                      if (_pack != null)
                        ChoiceChip(
                          label: const Text('Current study pack'),
                          selected: _view == 'study',
                          onSelected: blocked
                              ? null
                              : (_) => _navigate('study'),
                        ),
                    ],
                  ),
                  _gap(),
                  if (_busy) const LinearProgressIndicator(),
                  if (_busy) _gap(),
                  if (_error != null) _message(_error!, error: true),
                  if (_notice != null) _message(_notice!),
                  if (_locked)
                    _panel(
                      _title(
                        'Sign in again to continue',
                        'Your private study content has been cleared from this screen.',
                      ),
                    )
                  else if (_view == 'start')
                    _start()
                  else if (_view == 'library')
                    _library()
                  else
                    _study(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _start() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.primaryContainer, c.secondaryContainer],
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 34,
              color: c.onPrimaryContainer,
            ),
            _gap(14),
            Text(
              'Learn it. Practice it.\nMake it stick.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: c.onPrimaryContainer,
                height: 1.15,
              ),
            ),
            _gap(12),
            Text(
              'Turn a topic or your notes into a small, focused study pack. Pick up where you left off.',
              style: TextStyle(
                color: c.onPrimaryContainer,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            _gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _badge(Icons.menu_book_outlined, 'Short lessons'),
                _badge(Icons.style_outlined, 'Flashcards'),
                _badge(Icons.fact_check_outlined, 'Practice quizzes'),
              ],
            ),
          ],
        ),
      ),
      _gap(22),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              'What would you like to learn?',
              'Start with one topic. KORLIX will break it into manageable steps.',
            ),
            _gap(),
            TextField(
              controller: _topic,
              enabled: !blocked && _pendingCreate == null,
              maxLength: 300,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Your topic',
                hintText:
                    'For example: fractions, persuasive writing or how solar panels work',
                border: OutlineInputBorder(),
              ),
            ),
            FilledButton.icon(
              onPressed: blocked ? null : () => _create(),
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _pendingCreate != null
                    ? 'Retry same request'
                    : 'Create my study pack',
              ),
            ),
            _gap(8),
            const Text(
              'AI preparation uses 1 generation and 1 credit from your existing allowance. Reading, practice and exports use no AI credits.',
            ),
            _gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children:
                  [
                        'Fractions made simple',
                        'Public speaking',
                        'How solar panels work',
                      ]
                      .map(
                        (x) => ActionChip(
                          label: Text(x),
                          onPressed: blocked || _pendingCreate != null
                              ? null
                              : () => setState(() => _topic.text = x),
                        ),
                      )
                      .toList(),
            ),
            _gap(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              title: const Text('Use my notes (optional)'),
              subtitle: const Text(
                'Paste text from your own learning material',
              ),
              children: [
                TextField(
                  controller: _notes,
                  enabled: !blocked && _pendingCreate == null,
                  maxLength: 16000,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Reference notes',
                    hintText: 'Paste the text you want to study…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Text(
                  'Pasted notes go to OpenAI when you create an AI pack. KORLIX removes the source notes when preparation finishes; your generated study pack stays saved.',
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Personalize my session'),
              subtitle: Text(
                '${_level == 'beginner'
                    ? 'Just starting'
                    : _level == 'intermediate'
                    ? 'Know the basics'
                    : 'Go deeper'} · $_minutes minutes',
              ),
              children: [
                _labelChoices(
                  'My starting level',
                  {
                    'beginner': 'Just starting',
                    'intermediate': 'Know the basics',
                    'advanced': 'Go deeper',
                  },
                  _level,
                  (v) => setState(() => _level = v),
                ),
                _gap(),
                _labelChoices(
                  'What I want to do',
                  {
                    'understand': 'Understand it',
                    'exam': 'Prepare for a test',
                    'apply': 'Use it in real life',
                  },
                  _goal,
                  (v) => setState(() => _goal = v),
                ),
                _gap(),
                Text(
                  'Study session',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _gap(6),
                Wrap(
                  spacing: 8,
                  children: [5, 10, 20]
                      .map(
                        (n) => ChoiceChip(
                          label: Text('$n minutes'),
                          selected: _minutes == n,
                          onSelected: blocked || _pendingCreate != null
                              ? null
                              : (_) => setState(() => _minutes = n),
                        ),
                      )
                      .toList(),
                ),
                _gap(18),
              ],
            ),
            if (_pendingCreate != null) ...[
              _gap(10),
              const Text(
                'Your previous request may have started. Retry checks the same request without creating a duplicate.',
              ),
              TextButton(
                onPressed: blocked ? null : () => _navigate('library'),
                child: const Text('Check My learning'),
              ),
            ],
          ],
        ),
      ),
      _gap(24),
      _title(
        'Try something right now',
        'Ready-made lessons. No AI wait and no generation credit.',
      ),
      _gap(14),
      LayoutBuilder(
        builder: (context, b) {
          final width = b.maxWidth > 800 ? (b.maxWidth - 28) / 3 : b.maxWidth;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: studyStarters
                .map(
                  (s) => SizedBox(
                    width: width,
                    child: _panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            s['icon'] as IconData,
                            size: 30,
                            color: c.primary,
                          ),
                          _gap(14),
                          Text(
                            s['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          _gap(8),
                          Text(s['description'] as String),
                          _gap(14),
                          OutlinedButton(
                            onPressed: blocked || _pendingCreate != null
                                ? null
                                : () => _create(
                                    starter: s['id'] as String,
                                    topic: s['name'] as String,
                                  ),
                            child: const Text('Start lesson'),
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
    ],
  );
  Widget _labelChoices(
    String label,
    Map<String, String> options,
    String current,
    ValueChanged<String> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      _gap(6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: options.entries
            .map(
              (e) => ChoiceChip(
                label: Text(e.value),
                selected: current == e.key,
                onSelected: blocked || _pendingCreate != null
                    ? null
                    : (_) => change(e.key),
              ),
            )
            .toList(),
      ),
    ],
  );
  Widget _library() {
    final rows = _sets
        .where(
          (s) =>
              ('${s['title'] ?? ''} ${studyMap(s['details'])['topic'] ?? ''}')
                  .toLowerCase()
                  .contains(_search.text.toLowerCase()),
        )
        .toList();
    final due = _sets
        .where((s) => s['state'] == 'ready')
        .fold<int>(0, (n, s) => n + studyDue(s, DateTime.now()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Your learning, all in one place',
          'Revisit a lesson, review a few cards, or keep practicing.',
        ),
        _gap(),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _badge(Icons.bookmarks_outlined, '${_sets.length} saved packs'),
            _badge(Icons.style_outlined, '$due cards ready to review'),
          ],
        ),
        _gap(),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search your study packs',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        _gap(),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          _panel(
            _title(
              _sets.isEmpty
                  ? 'Start your first study pack'
                  : 'No matching study packs',
              _sets.isEmpty
                  ? 'Choose a topic or try a starter lesson. Your saved progress will appear here.'
                  : 'Try another search.',
            ),
          )
        else
          ...rows.map((s) {
            final details = studyMap(s['details']), p = studyMap(s['progress']);
            final ready = s['state'] == 'ready';
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (s['title'] ?? details['topic'] ?? 'Study pack')
                          .toString(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _gap(8),
                    Text(
                      ready
                          ? '${studyMap(p['read']).length}/${s['sectionCount']} sections read · ${studyDue(s, DateTime.now())} cards ready'
                          : s['state'] == 'preparing'
                          ? 'KORLIX is preparing this pack…'
                          : 'Preparation did not finish. Open for details.',
                    ),
                    _gap(12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: blocked ? null : () => _open(s['id']),
                          child: Text(
                            ready ? 'Continue learning' : 'Open study pack',
                          ),
                        ),
                        if (s['state'] != 'preparing')
                          TextButton.icon(
                            onPressed: blocked ? null : () => _remove(s),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _study() {
    if (_pack == null) {
      return _panel(
        _title(
          'Choose a study pack',
          'Open My learning or create something new.',
        ),
      );
    }
    if (preparing) {
      return _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            _gap(22),
            _title(
              'KORLIX is preparing your study pack',
              'Building a clear lesson, recall cards and practice questions. Preparation can take a few minutes.',
            ),
            _gap(),
            Text(studyMap(_pack!['details'])['topic']?.toString() ?? ''),
            _gap(),
            const Text(
              'You can leave this screen. Check My learning to pick up the completed pack.',
            ),
            _gap(),
            OutlinedButton(
              onPressed: blocked ? null : () => _navigate('library'),
              child: const Text('Go to My learning'),
            ),
          ],
        ),
      );
    }
    if (_pack!['state'] == 'failed') {
      return _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              'Let’s try a smaller step',
              _pack!['error']?.toString() ??
                  'This study pack could not be prepared.',
            ),
            _gap(),
            FilledButton(
              onPressed: blocked
                  ? null
                  : () {
                      setState(() {
                        _topic.text =
                            studyMap(_pack!['details'])['topic']?.toString() ??
                            '';
                        _notes.clear();
                        _pendingCreate = null;
                        _view = 'start';
                        _notice =
                            'You can narrow the topic and try again. Paste any reference notes again if you want to use them.';
                      });
                    },
              child: const Text('Try this topic again'),
            ),
            TextButton(
              onPressed: blocked ? null : () => _remove(_pack!),
              child: const Text('Delete failed pack'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _badge(
                    Icons.school_outlined,
                    _pack!['source'] == 'starter'
                        ? 'KORLIX starter'
                        : 'AI study pack',
                  ),
                  _badge(
                    Icons.check_circle_outline,
                    '${studyMap(progress['read']).length}/${sections.length} sections read',
                  ),
                ],
              ),
              _gap(10),
              Text(
                lesson['title'].toString(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              _gap(10),
              Text(
                lesson['summary'].toString(),
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              _gap(16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: blocked ? null : _export,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export study guide'),
                  ),
                  OutlinedButton.icon(
                    onPressed: blocked
                        ? null
                        : () => setState(() {
                            if (_endsAt == null) {
                              if (_remaining == 0) {
                                _remaining =
                                    (studyMap(_pack!['details'])['minutes']
                                            as int? ??
                                        10) *
                                    60;
                              }
                              _endsAt = DateTime.now().add(
                                Duration(seconds: _remaining),
                              );
                            } else {
                              _endsAt = null;
                            }
                          }),
                    icon: Icon(
                      _endsAt == null
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    label: Text(
                      '${_endsAt == null ? 'Focus' : 'Pause'} ${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}',
                    ),
                  ),
                ],
              ),
              _gap(8),
              Text(
                'Progress saves to your account. The optional focus timer runs only while this workspace is open.',
                style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        _gap(18),
        if (_pendingEvent != null)
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The last save was not confirmed. Retry it or refresh the saved progress before continuing.',
                ),
                _gap(),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: blocked ? null : () => _event({}),
                      child: const Text('Retry saving progress'),
                    ),
                    OutlinedButton(
                      onPressed: blocked ? null : _refresh,
                      child: const Text('Refresh saved progress'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_pendingEvent != null) _gap(),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children:
              [
                    ('learn', 'Learn', Icons.menu_book_outlined),
                    ('cards', 'Flashcards', Icons.style_outlined),
                    ('quiz', 'Practice quiz', Icons.fact_check_outlined),
                    ('recap', 'Recap', Icons.lightbulb_outline),
                  ]
                  .map(
                    (x) => ChoiceChip(
                      avatar: Icon(x.$3, size: 18),
                      label: Text(x.$2),
                      selected: _tab == x.$1,
                      onSelected: blocked ? null : (_) => _selectTab(x.$1),
                    ),
                  )
                  .toList(),
        ),
        _gap(),
        KeyedSubtree(
          key: _activityKey,
          child: _tab == 'learn'
              ? _learn()
              : _tab == 'cards'
              ? _flashcards()
              : _tab == 'quiz'
              ? _quiz()
              : _recap(),
        ),
        _gap(18),
        Text(
          'Study aid • Check important details against your course materials.',
          style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  Widget _learn() {
    final s = sections[_section],
        read = studyMap(progress['read'])['$_section'] == true;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LESSON ${_section + 1} OF ${sections.length}',
            style: TextStyle(
              color: c.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          _gap(10),
          _title(s['heading'].toString()),
          _gap(16),
          SelectableText(
            s['body'].toString(),
            style: const TextStyle(fontSize: 17, height: 1.65),
          ),
          _gap(20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'See it in action',
                  style: TextStyle(
                    color: c.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _gap(8),
                SelectableText(
                  s['example'].toString(),
                  style: TextStyle(color: c.onSecondaryContainer, height: 1.6),
                ),
              ],
            ),
          ),
          _gap(18),
          Text(
            'Remember: ${s['takeaway']}',
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
          ),
          _gap(22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_section > 0)
                OutlinedButton(
                  onPressed: editable ? () => setState(() => _section--) : null,
                  child: const Text('Previous lesson'),
                ),
              FilledButton.icon(
                onPressed: editable
                    ? () {
                        if (read) {
                          setState(() {
                            if (_section < sections.length - 1) {
                              _section++;
                            } else {
                              _tab = 'cards';
                            }
                          });
                        } else {
                          _event(
                            {'event': 'read', 'index': _section},
                            after: () {
                              if (_section < sections.length - 1) {
                                _section++;
                              } else {
                                _tab = 'cards';
                              }
                            },
                          );
                        }
                      }
                    : null,
                icon: Icon(read ? Icons.arrow_forward : Icons.check),
                label: Text(
                  _section == sections.length - 1
                      ? '${read ? 'Continue' : 'Mark read'} & try flashcards'
                      : read
                      ? 'Next lesson'
                      : 'Mark read & continue',
                ),
              ),
            ],
          ),
          _gap(16),
          LinearProgressIndicator(
            value: studyMap(progress['read']).length / sections.length,
          ),
          _gap(8),
          Text(
            '${studyMap(progress['read']).length} of ${sections.length} sections marked read',
          ),
        ],
      ),
    );
  }

  List<int> get _cardIndices =>
      List.generate(cards.length, (i) => i).where((i) {
        if (!_dueOnly) return true;
        final due = DateTime.tryParse(
          studyMap(studyMap(progress['cards'])['$i'])['due']?.toString() ?? '',
        );
        return due == null || !due.isAfter(DateTime.now());
      }).toList();
  Widget _flashcards() {
    final indices = _cardIndices;
    if (indices.isEmpty) {
      return _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              'You’re caught up for now',
              'Your next review dates are saved. You can practice every card again whenever you like.',
            ),
            _gap(),
            OutlinedButton(
              onPressed: () => setState(() {
                _dueOnly = false;
                _card = 0;
                _revealed = false;
              }),
              child: const Text('Practice all cards'),
            ),
          ],
        ),
      );
    }
    final position = _card.clamp(0, indices.length - 1),
        index = indices[position],
        card = cards[index],
        rating = studyMap(studyMap(progress['cards'])['$index']);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All cards'),
                selected: !_dueOnly,
                onSelected: editable
                    ? (_) => setState(() {
                        _dueOnly = false;
                        _card = 0;
                        _revealed = false;
                      })
                    : null,
              ),
              ChoiceChip(
                label: Text(
                  'Ready to review (${studyDue(_pack!, DateTime.now())})',
                ),
                selected: _dueOnly,
                onSelected: editable
                    ? (_) => setState(() {
                        _dueOnly = true;
                        _card = 0;
                        _revealed = false;
                      })
                    : null,
              ),
            ],
          ),
          _gap(16),
          Text(
            'CARD ${position + 1} OF ${indices.length}',
            style: TextStyle(color: c.primary, fontWeight: FontWeight.w700),
          ),
          _gap(16),
          Text(
            card['front'].toString(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          _gap(16),
          const Text('Try answering from memory before you reveal the answer.'),
          _gap(20),
          if (!_revealed)
            FilledButton.icon(
              onPressed: editable
                  ? () => setState(() => _revealed = true)
                  : null,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal answer'),
            )
          else ...[
            _message(card['back'].toString()),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: editable
                      ? () => _rate(index, 'again', indices.length)
                      : null,
                  child: const Text('Review again'),
                ),
                FilledButton(
                  onPressed: editable
                      ? () => _rate(index, 'known', indices.length)
                      : null,
                  child: const Text('I knew this'),
                ),
              ],
            ),
            _gap(10),
            const Text(
              'Review again: in 10 minutes. I knew this: tomorrow, then longer intervals as you practice.',
            ),
          ],
          if (rating['due'] != null) ...[
            _gap(12),
            Text(
              'Next review: ${_dateLabel(rating['due'].toString())}',
              style: TextStyle(color: c.onSurfaceVariant),
            ),
          ],
          _gap(20),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(
                onPressed: editable && position > 0
                    ? () => setState(() {
                        _card = position - 1;
                        _revealed = false;
                      })
                    : null,
                child: const Text('Previous card'),
              ),
              OutlinedButton(
                onPressed: editable && position < indices.length - 1
                    ? () => setState(() {
                        _card = position + 1;
                        _revealed = false;
                      })
                    : null,
                child: const Text('Next card'),
              ),
            ],
          ),
          _gap(18),
          TextButton(
            onPressed: editable ? () => _selectTab('quiz') : null,
            child: const Text('Try the practice quiz →'),
          ),
        ],
      ),
    );
  }

  void _rate(int index, String rating, int count) {
    _event(
      {'event': 'card', 'index': index, 'rating': rating},
      after: () {
        _revealed = false;
        if (_dueOnly) {
          _card = 0;
        } else if (_card < count - 1) {
          _card++;
        } else {
          _notice =
              'Card review saved. Try the practice quiz or review any card again.';
        }
      },
    );
  }

  String _dateLabel(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return 'Soon';
    return '${d.month}/${d.day}/${d.year} at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _quiz() {
    final q = questions[_question],
        answers = studyMap(progress['answers']),
        a = studyMap(answers['$_question']);
    final answered = a.isNotEmpty && !_correcting,
        correct = a['choice'] == q['answer'];
    final first = questions
        .asMap()
        .entries
        .where(
          (e) =>
              studyMap(answers['${e.key}'])['firstChoice'] == e.value['answer'],
        )
        .length;
    final solved = questions
        .asMap()
        .entries
        .where(
          (e) => studyMap(answers['${e.key}'])['choice'] == e.value['answer'],
        )
        .length;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _badge(
                Icons.fact_check_outlined,
                '${answers.length}/${questions.length} attempted',
              ),
              _badge(Icons.check_circle_outline, '$solved correct now'),
            ],
          ),
          _gap(12),
          Text(
            'QUESTION ${_question + 1} OF ${questions.length}',
            style: TextStyle(color: c.primary, fontWeight: FontWeight.w700),
          ),
          _gap(12),
          Text(
            q['question'].toString(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          _gap(18),
          ...List.generate((q['options'] as List).length, (i) {
            final selected = answered ? a['choice'] == i : _choice == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                selected: selected,
                child: OutlinedButton(
                  onPressed: editable && !answered
                      ? () => setState(() => _choice = i)
                      : null,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: selected ? c.secondaryContainer : null,
                    foregroundColor: selected
                        ? c.onSecondaryContainer
                        : c.onSurface,
                    disabledForegroundColor: c.onSurface,
                    side: BorderSide(
                      color: selected ? c.primary : c.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'ABCD'[i]}. ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Expanded(
                        child: Text(
                          q['options'][i].toString(),
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (!answered) ...[
            TextButton.icon(
              onPressed: editable ? () => setState(() => _hint = !_hint) : null,
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(_hint ? 'Hide hint' : 'Give me a hint'),
            ),
            if (_hint) _message(q['hint'].toString()),
            FilledButton(
              onPressed: editable && _choice != null
                  ? () => _event({
                      'event': 'answer',
                      'index': _question,
                      'choice': _choice,
                    })
                  : null,
              child: const Text('Check answer'),
            ),
          ] else ...[
            _message(
              '${correct ? 'That’s right.' : 'Let’s work through it.'}\n\n${q['explanation']}\n\nAnswer: ${'ABCD'[q['answer'] as int]}. ${q['options'][q['answer']]}',
            ),
            if (!correct)
              OutlinedButton(
                onPressed: editable
                    ? () => setState(() {
                        _correcting = true;
                        _choice = null;
                        _hint = false;
                      })
                    : null,
                child: const Text('Try this question again'),
              ),
          ],
          _gap(20),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (_question > 0)
                OutlinedButton(
                  onPressed: editable ? () => _goQuestion(_question - 1) : null,
                  child: const Text('Previous question'),
                ),
              if (_question < questions.length - 1)
                OutlinedButton(
                  onPressed: editable && a.isNotEmpty
                      ? () => _goQuestion(_question + 1)
                      : null,
                  child: const Text('Next question'),
                ),
            ],
          ),
          _gap(18),
          Text(
            'First-try correct: $first of ${questions.length}. Corrections count toward “correct now”, not your first-try result.',
            style: TextStyle(color: c.onSurfaceVariant, height: 1.5),
          ),
          if (answers.length == questions.length) ...[
            _gap(18),
            _title(
              solved == questions.length
                  ? 'Practice complete'
                  : 'You’ve tried every question',
              solved == questions.length
                  ? 'Use the recap to explain the ideas in your own words.'
                  : 'Review the questions that need another look.',
            ),
            _gap(12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (solved < questions.length)
                  FilledButton(
                    onPressed: editable
                        ? () {
                            final n = questions
                                .asMap()
                                .entries
                                .firstWhere(
                                  (e) =>
                                      studyMap(answers['${e.key}'])['choice'] !=
                                      e.value['answer'],
                                )
                                .key;
                            _goQuestion(n);
                          }
                        : null,
                    child: const Text('Review missed questions'),
                  ),
                OutlinedButton(
                  onPressed: editable ? () => _selectTab('recap') : null,
                  child: const Text('Open recap'),
                ),
              ],
            ),
          ],
          if (answers.isNotEmpty) ...[
            _gap(16),
            TextButton(
              onPressed: editable
                  ? () async {
                      if (await _confirm(
                        'Restart this practice quiz?',
                        'This clears the saved quiz answers and first-try result. Lesson and flashcard progress stay saved.',
                        'Restart quiz',
                      )) {
                        await _event(
                          {'event': 'resetQuiz', 'confirmed': true},
                          after: () {
                            _question = 0;
                            _hint = false;
                          },
                        );
                      }
                    }
                  : null,
              child: const Text('Restart quiz'),
            ),
          ],
        ],
      ),
    );
  }

  void _goQuestion(int n) {
    setState(() {
      _question = n;
      _choice = null;
      _hint = false;
      _correcting = false;
    });
    _focusActivity();
  }

  Widget _recap() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Bring it all together',
          'Explain these ideas in your own words, without looking back.',
        ),
        _gap(18),
        ...(lesson['recap'] as List).map(
          (x) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, color: c.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    x.toString(),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        _gap(10),
        _title('Your learning goals'),
        _gap(12),
        ...(lesson['objectives'] as List).map(
          (x) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $x', style: const TextStyle(height: 1.5)),
          ),
        ),
        if ((lesson['limitations'] as List).isNotEmpty) ...[
          _gap(16),
          _title('Keep in mind'),
          _gap(10),
          ...(lesson['limitations'] as List).map(
            (x) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(x.toString(), style: const TextStyle(height: 1.5)),
            ),
          ),
        ],
        _gap(20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: editable
                  ? () => setState(() {
                      _tab = 'cards';
                      _dueOnly = true;
                      _card = 0;
                      _revealed = false;
                    })
                  : null,
              child: const Text('Review ready cards'),
            ),
            OutlinedButton(
              onPressed: blocked ? null : _export,
              child: const Text('Export study guide'),
            ),
          ],
        ),
      ],
    ),
  );
}

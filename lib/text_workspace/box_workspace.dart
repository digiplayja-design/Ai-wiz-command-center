import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'box_store.dart';

class BoxWorkspace extends StatefulWidget {
  const BoxWorkspace({
    super.key,
    required this.store,
    required this.sessionChanges,
    required this.sessionValid,
    required this.rewrite,
    this.speech,
  });
  final SpeechToText? speech;
  final BoxStore store;
  final Listenable sessionChanges;
  final bool Function() sessionValid;
  final Future<String> Function(String action, String text) rewrite;
  @override
  State<BoxWorkspace> createState() => _BoxWorkspaceState();
}

class _BoxWorkspaceState extends State<BoxWorkspace>
    with WidgetsBindingObserver {
  final _title = TextEditingController(),
      _text = TextEditingController(),
      _folder = TextEditingController();
  final _pageScroll = ScrollController(), _entriesScroll = ScrollController();
  late final _speech = widget.speech ?? SpeechToText();
  List<SavedBox> _boxes = [];
  SavedBox? _selected;
  String _query = '', _status = 'Saved on this device', _partial = '';
  bool _favorites = false,
      _busy = false,
      _listening = false,
      _starting = false,
      _locked = false,
      _loadFailed = false;
  int _generation = 0;
  List<LocaleName> _locales = [];
  String? _locale;
  Future<void> _writes = Future.value();
  bool get _valid => mounted && !_locked && widget.sessionValid();
  String get _name => widget.store.voice ? 'VoiceScribe' : 'Copy Box';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessionChanges.addListener(_checkSession);
    try {
      _boxes = widget.store.load();
      // Open a usable editor immediately on a first visit. This empty starter
      // is only persisted when the user edits it or creates another entry.
      if (_boxes.isEmpty) _boxes.add(SavedBox());
      _select(_boxes.first);
    } catch (_) {
      _loadFailed = true;
      _status =
          'Saved data could not be read. Reopen this workspace; existing data has not been replaced.';
    }
    _checkSession();
  }

  void _checkSession() {
    if (widget.sessionValid() || _locked) return;
    _locked = true;
    _generation++;
    unawaited(_speech.cancel());
    _boxes.clear();
    _selected = null;
    _title.clear();
    _text.clear();
    _folder.clear();
    _partial = '';
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).popUntil((r) => r == route);
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    _generation++;
    widget.sessionChanges.removeListener(_checkSession);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    _title.dispose();
    _text.dispose();
    _folder.dispose();
    _pageScroll.dispose();
    _entriesScroll.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (_valid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _save() {
    if (!mounted || !_valid || _loadFailed) return Future.value();
    // Snapshot now; serialize writes so a slower old write cannot overwrite new text.
    final snapshot = _boxes.map((b) => SavedBox.fromJson(b.toJson())).toList();
    _writes = _writes
        .then((_) => widget.store.save(snapshot))
        .then((_) {
          if (_valid) {
            setState(
              () => _status =
                  'Saved on this device • ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            );
          }
        })
        .catchError((Object error) {
          if (_valid) {
            setState(
              () =>
                  _status = 'Save failed. Copy your text, then use Retry save.',
            );
          }
        });
    return _writes;
  }

  void _edit() {
    if (!mounted || !_valid || _selected == null) return;
    _selected!
      ..title = _title.text
      ..text = _text.text
      ..folder = _folder.text
      ..updated = DateTime.now().toIso8601String();
    unawaited(_save());
    setState(() {});
  }

  void _select(SavedBox box) {
    _selected = box;
    _title.text = box.title;
    _text.text = box.text;
    _folder.text = box.folder;
  }

  Future<void> _choose(SavedBox box) async {
    await _stop();
    if (!mounted || !_valid) return;
    setState(() => _select(box));
  }

  Future<void> _new({
    String title = 'Untitled',
    String text = '',
    String folder = '',
  }) async {
    await _stop();
    if (!mounted || !_valid) return;
    try {
      final box = SavedBox(title: title, text: text, folder: folder);
      setState(() {
        _boxes.insert(0, box);
        _select(box);
        _query = '';
        _favorites = false;
      });
      await _save();
    } catch (_) {
      _message('The new entry could not be opened. Please try again.');
    }
  }

  Future<void> _copy(String value) async {
    if (!mounted || !_valid || value.trim().isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _message('Copied to clipboard');
    } catch (_) {
      _message('Clipboard unavailable. Select the text and copy it manually.');
    }
  }

  Future<void> _stop() async {
    _generation++;
    if (_listening && _partial.isNotEmpty && _valid && _selected != null) {
      _selected!.replace(
        '${_text.text.trimRight()}${_text.text.trim().isEmpty ? '' : '\n'}$_partial',
      );
      _text.text = _selected!.text;
      _partial = '';
      unawaited(_save());
    }
    final active = _listening || _starting;
    _listening = false;
    _starting = false;
    if (mounted) setState(() {});
    if (active) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
  }

  Future<void> _dictate() async {
    if (_listening || _starting) {
      await _stop();
      return;
    }
    if (!mounted || !_valid || _selected == null) return;
    final ticket = ++_generation;
    final box = _selected!;
    setState(() => _starting = true);
    bool live() => _valid && ticket == _generation && identical(box, _selected);
    try {
      final ready = await _speech.initialize();
      if (!mounted || !live()) return;
      _speech.errorListener = (error) {
        if (!live()) return;
        _message(
          'Dictation stopped: ${error.errorMsg}. You can still type or paste text.',
        );
        unawaited(_stop());
      };
      _speech.statusListener = (status) {
        // Wait for done/final result; notListening may precede the final words.
        if (live() && status == 'done') unawaited(_stop());
      };
      if (!live()) return;
      if (!ready) {
        _message(
          'Microphone unavailable. Enable microphone permission, or type and paste text.',
        );
        setState(() => _starting = false);
        return;
      }
      _locales = await _speech.locales();
      if (!live()) return;
      setState(() {
        _starting = false;
        _listening = true;
        _partial = '';
      });
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!live()) return;
          setState(() => _partial = result.recognizedWords);
          if (result.finalResult) unawaited(_stop());
        },
      );
      if (!live()) await _speech.cancel();
    } catch (_) {
      if (live()) {
        await _stop();
        _message(
          'Unable to start dictation. Check microphone permission and retry.',
        );
      }
    }
  }

  Future<void> _languages() async {
    await _stop();
    if (!mounted || !_valid) return;
    try {
      if (await _speech.initialize()) _locales = await _speech.locales();
      if (!mounted || !_valid) return;
      final value = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Dictation language'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Device default'),
            ),
            ..._locales.map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, l.localeId),
                child: Text(l.name),
              ),
            ),
          ],
        ),
      );
      if (_valid && value != null) {
        setState(() => _locale = value.isEmpty ? null : value);
      }
    } catch (_) {
      _message('Languages unavailable on this device.');
    }
  }

  Future<void> _ai(String action) async {
    await _stop();
    if (!mounted ||
        !_valid ||
        _selected == null ||
        _text.text.trim().isEmpty ||
        _busy) {
      return;
    }
    final box = _selected!, original = _text.text;
    setState(() => _busy = true);
    try {
      final result = await widget.rewrite(action, original);
      if (!mounted || !_valid) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Review • $action'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Original',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(original),
                  const Divider(),
                  const Text(
                    'AI draft — review facts before use',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(result),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'new'),
              child: const Text('Save as new'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (!mounted || !_valid || choice == null) return;
      if (choice == 'new') {
        await _new(
          title: '${box.title} • $action',
          text: result,
          folder: box.folder,
        );
      } else if (_boxes.contains(box) && box.text == original) {
        setState(() {
          box.replace(result);
          if (identical(box, _selected)) _text.text = result;
        });
        await _save();
      } else {
        _message(
          'The original changed. Run the action again to keep your latest edits.',
        );
      }
    } catch (_) {
      _message(
        'AI could not complete this edit. Your original is unchanged. Try again.',
      );
    } finally {
      if (_valid) setState(() => _busy = false);
    }
  }

  Future<void> _history() async {
    await _stop();
    if (!mounted || !_valid || _selected == null) return;
    final box = _selected!;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Previous versions'),
        children: box.history.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Versions are kept before AI edits, dictation and restores.',
                  ),
                ),
              ]
            : box.history.indexed
                  .map(
                    (e) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, e.$2),
                      child: Text(
                        'Version ${e.$1 + 1}\n${e.$2}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
    if (!mounted || !_valid || value == null) return;
    setState(() {
      box.replace(value);
      _text.text = value;
    });
    await _save();
  }

  Future<void> _delete() async {
    await _stop();
    if (!mounted || !_valid || _selected == null) return;
    final box = _selected!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(box.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || !_valid || yes != true) return;
    setState(() {
      _boxes.remove(box);
      _selected = null;
      if (_boxes.isNotEmpty) _select(_boxes.first);
    });
    await _save();
    if (!mounted || !_valid) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted || !_valid) return;
            setState(() {
              _boxes.insert(0, box);
              _select(box);
            });
            unawaited(_save());
          },
        ),
      ),
    );
  }

  Future<void> _fillTemplate() async {
    final original = _text.text;
    final fields = templateFields(original);
    if (fields.isEmpty) {
      _message(
        'Add placeholders such as {{client}} or {{date}} to make a reusable template.',
      );
      return;
    }
    final controllers = {for (final f in fields) f: TextEditingController()};
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Fill template'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: controllers.entries
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: e.value,
                          decoration: InputDecoration(labelText: e.key),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                c,
                renderTemplate(
                  original,
                  controllers.map((k, v) => MapEntry(k, v.text)),
                ),
              ),
              child: const Text('Preview'),
            ),
          ],
        ),
      );
      if (!mounted || !_valid || value == null) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ready to copy'),
          content: SingleChildScrollView(child: SelectableText(value)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => _copy(value),
              child: const Text('Copy filled text'),
            ),
          ],
        ),
      );
    } finally {
      for (final c in controllers.values) {
        c.dispose();
      }
    }
  }

  Future<void> _import() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import older device boxes?'),
        content: const Text(
          'Older boxes were shared on this device. Import only if they belong to you. They will be copied into this account’s workspace; originals stay intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Import my boxes'),
          ),
        ],
      ),
    );
    if (!mounted || !_valid || yes != true) return;
    // Add entries before taking any later autosave snapshots, then commit the
    // import after earlier writes. Retry IDs are stable, so failures cannot duplicate.
    widget.store.prepareLegacy(_boxes);
    final snapshot = _boxes.map((b) => SavedBox.fromJson(b.toJson())).toList();
    final operation = _writes.then((_) => widget.store.importLegacy(snapshot));
    _writes = operation.catchError((Object _) {});
    try {
      await operation;
      if (_valid) {
        setState(() {
          if (_selected == null && _boxes.isNotEmpty) _select(_boxes.first);
        });
      }
    } catch (_) {
      _message('Import failed. Older boxes remain intact.');
    }
  }

  Future<void> _preset() async {
    final presets = widget.store.voice
        ? <String, String>{
            'Meeting notes':
                'Purpose:\n\nDiscussion:\n\nDecisions:\n\nActions and owners:\n',
            'Interview':
                'Interviewee:\nDate:\n\nQuestions and responses:\n\nFollow-up:\n',
            'Field observation':
                'Location:\nDate:\n\nObservations:\n\nNext steps:\n',
          }
        : <String, String>{
            'Client follow-up':
                'Hi {{client}},\n\nFollowing up on {{topic}}. The next step is {{next step}} by {{date}}.\n\nThank you,\n{{name}}',
            'Project update':
                'Project: {{project}}\nStatus: {{status}}\nCompleted: {{completed}}\nNext: {{next step}}\nOwner: {{owner}}',
            'Customer support':
                'Hi {{customer}},\n\nThank you for contacting us about {{issue}}.\n\n{{resolution}}\n\nBest,\n{{name}}',
          };
    final key = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Start from a template'),
        children: presets.keys
            .map(
              (k) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, k),
                child: Text(k),
              ),
            )
            .toList(),
      ),
    );
    if (_valid && key != null) await _new(title: key, text: presets[key]!);
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: Text(_name)),
        body: const Center(
          child: Text('Sign in again and reopen this workspace.'),
        ),
      );
    }
    final visible =
        _boxes
            .where(
              (b) =>
                  (!_favorites || b.favorite) &&
                  '${b.title} ${b.folder} ${b.text}'.toLowerCase().contains(
                    _query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) => b.updated.compareTo(a.updated));
    final theme = Theme.of(context);
    final palette = _WorkspacePalette(widget.store.voice, theme.brightness);
    final workspaceTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        secondary: palette.accent,
        onSecondary: palette.onAccent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(palette.primary),
        trackColor: WidgetStatePropertyAll(palette.track),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        crossAxisMargin: 3,
        mainAxisMargin: 6,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: palette.input,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
      ),
    );
    return Theme(
      data: workspaceTheme,
      child: PopScope(
        canPop: !_listening && !_starting,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _stop();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(_name),
            backgroundColor: palette.panel,
            foregroundColor: theme.colorScheme.onSurface,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            // Disable platform-generated scrollbars: both scrollable regions
            // below have their own controller and a visible, draggable thumb.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Scrollbar(
                key: const ValueKey('workspace-page-scrollbar'),
                controller: _pageScroll,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                thickness: 10,
                radius: const Radius.circular(8),
                scrollbarOrientation: ScrollbarOrientation.right,
                notificationPredicate: (notification) =>
                    notification.depth == 0,
                child: SingleChildScrollView(
                  key: const ValueKey('workspace-page-scroll'),
                  controller: _pageScroll,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(12, 16, 26, 24),
                  child: LayoutBuilder(
                    builder: (context, size) {
                      final wide =
                          size.maxWidth >= 800 &&
                          MediaQuery.textScalerOf(context).scale(16) <= 24;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            key: const ValueKey('workspace-overview-panel'),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: palette.panel,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: palette.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.store.voice
                                      ? 'Speak it. Shape it. Save it.'
                                      : 'Your words, ready to reuse.',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        color: palette.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Private to this account on this browser/device. No cross-device sync. $_status',
                                ),
                                if (!_loadFailed) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: palette.primary,
                                          foregroundColor: palette.onPrimary,
                                        ),
                                        onPressed: _busy ? null : () => _new(),
                                        icon: const Icon(Icons.add),
                                        label: const Text('New entry'),
                                      ),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: palette.accent,
                                          foregroundColor: palette.onAccent,
                                        ),
                                        onPressed: _busy ? null : _preset,
                                        icon: const Icon(
                                          Icons.description_outlined,
                                        ),
                                        label: const Text('Templates'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _copy(
                                          visible
                                              .map(
                                                (b) => '${b.title}\n${b.text}',
                                              )
                                              .join('\n\n────────\n\n'),
                                        ),
                                        icon: const Icon(Icons.copy_all),
                                        label: const Text('Copy results'),
                                      ),
                                      TextButton(
                                        onPressed: _save,
                                        child: const Text('Retry save'),
                                      ),
                                      if (!widget.store.imported &&
                                          widget.store.legacy.isNotEmpty)
                                        TextButton(
                                          onPressed: _import,
                                          child: const Text(
                                            'Import older boxes',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!_loadFailed) ...[
                            const SizedBox(height: 16),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search titles, folders and text',
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilterChip(
                                  label: const Text('Favorites'),
                                  selected: _favorites,
                                  selectedColor: palette.selection,
                                  onSelected: (v) =>
                                      setState(() => _favorites = v),
                                ),
                                Text('${visible.length} entries'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 260,
                                    child: _entryList(
                                      visible,
                                      palette,
                                      wide: true,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(child: _editorPanel(palette)),
                                ],
                              )
                            else ...[
                              _entryList(visible, palette, wide: false),
                              const SizedBox(height: 16),
                              _editorPanel(palette),
                            ],
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryList(
    List<SavedBox> visible,
    _WorkspacePalette palette, {
    required bool wide,
  }) => Container(
    decoration: BoxDecoration(
      color: palette.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: palette.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Your entries',
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('No entries match your search.'),
            )
          else
            SizedBox(
              height: wide ? 440 : 132,
              child: Scrollbar(
                key: const ValueKey('workspace-entries-scrollbar'),
                controller: _entriesScroll,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                thickness: 7,
                child: ListView(
                  key: const ValueKey('workspace-entries-scroll'),
                  controller: _entriesScroll,
                  primary: false,
                  padding: const EdgeInsets.only(right: 14, bottom: 8),
                  children: visible
                      .map(
                        (b) => ListTile(
                          selected: identical(b, _selected),
                          selectedColor: palette.primary,
                          selectedTileColor: palette.selection,
                          leading: Icon(
                            b.favorite ? Icons.star : Icons.article_outlined,
                          ),
                          title: Text(
                            b.title.isEmpty ? 'Untitled' : b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${b.folder.isEmpty ? '' : '${b.folder} • '}${b.text.replaceAll('\n', ' ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _busy ? null : () => _choose(b),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _editorPanel(_WorkspacePalette palette) => Container(
    key: const ValueKey('workspace-editor-panel'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: palette.editor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: palette.accent, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.store.voice ? 'Transcript studio' : 'Writing desk',
          style: TextStyle(
            color: palette.accent,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        if (_selected == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Create an entry or choose a template to get started.'),
          )
        else
          _editor(palette),
      ],
    ),
  );

  Widget _editor(_WorkspacePalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _title,
              onChanged: (_) => _edit(),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
          ),
          IconButton(
            tooltip: 'Favorite',
            onPressed: () {
              setState(() => _selected!.favorite = !_selected!.favorite);
              unawaited(_save());
            },
            icon: Icon(_selected!.favorite ? Icons.star : Icons.star_border),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _folder,
        onChanged: (_) => _edit(),
        decoration: const InputDecoration(
          labelText: 'Folder / category',
          hintText: 'e.g. Clients, Meetings, Personal',
        ),
      ),
      const SizedBox(height: 12),
      if (widget.store.voice) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
              ),
              onPressed: _busy ? null : _dictate,
              icon: Icon(_listening || _starting ? Icons.stop : Icons.mic),
              label: Text(
                _starting
                    ? 'Cancel microphone'
                    : _listening
                    ? 'Stop & keep transcript'
                    : 'Start dictation',
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _languages,
              icon: const Icon(Icons.language),
              label: Text(_locale ?? 'Device language'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Dictation appends to this entry. Speech recognition availability and processing depend on your browser/device.',
        ),
        const SizedBox(height: 12),
        if (_listening)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _partial.isEmpty ? 'Listening…' : _partial,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
      TextField(
        controller: _text,
        readOnly: _listening || _starting,
        // Let the outer page scrollbar reach every line and editor action.
        minLines: 8,
        maxLines: null,
        onChanged: (_) => _edit(),
        decoration: InputDecoration(
          labelText: widget.store.voice ? 'Transcript / notes' : 'Saved text',
          hintText: widget.store.voice
              ? 'Speak, type or paste your notes…'
              : 'Write reusable text. Use {{client}} for template fields.',
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${_text.text.trim().isEmpty ? 0 : _text.text.trim().split(RegExp(r'\s+')).length} words • ${_text.text.length} characters',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
            ),
            onPressed: () => _copy(_text.text),
            icon: const Icon(Icons.copy),
            label: const Text('Copy text'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _fillTemplate,
            child: const Text('Fill template'),
          ),
          PopupMenuButton<String>(
            enabled: !_busy && _text.text.trim().isNotEmpty,
            onSelected: _ai,
            itemBuilder: (_) => [
              'Polish',
              'Summarize',
              'Action items',
              'Meeting notes',
              'Professional email',
              'Shorten',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.selection,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                _busy ? 'Creating AI draft…' : 'Improve with KORLIX ▾',
                style: TextStyle(
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _history,
            child: const Text('Versions'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _new(
                    title: '${_title.text} (copy)',
                    text: _text.text,
                    folder: _folder.text,
                  ),
            child: const Text('Duplicate'),
          ),
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('Delete'),
          ),
        ],
      ),
    ],
  );
}

class _WorkspacePalette {
  _WorkspacePalette(this.voice, Brightness brightness)
    : dark = brightness == Brightness.dark;

  final bool voice, dark;
  Color get primary => voice
      ? (dark ? const Color(0xFF65DED0) : const Color(0xFF00766D))
      : (dark ? const Color(0xFF8EBBFF) : const Color(0xFF2359BB));
  Color get accent => voice
      ? (dark ? const Color(0xFFC6A9FF) : const Color(0xFF7140BA))
      : (dark ? const Color(0xFFFFB098) : const Color(0xFFAD3F25));
  Color get onPrimary => dark ? const Color(0xFF10242E) : Colors.white;
  Color get onAccent => dark ? const Color(0xFF2B1835) : Colors.white;
  Color get background => voice
      ? (dark ? const Color(0xFF0C2023) : const Color(0xFFECF9F6))
      : (dark ? const Color(0xFF111D30) : const Color(0xFFF0F5FF));
  Color get panel => voice
      ? (dark ? const Color(0xFF173239) : const Color(0xFFD9F3EE))
      : (dark ? const Color(0xFF1B2C48) : const Color(0xFFDDEAFF));
  Color get editor => voice
      ? (dark ? const Color(0xFF2A233A) : const Color(0xFFF4ECFF))
      : (dark ? const Color(0xFF36282A) : const Color(0xFFFFEEE8));
  Color get input => dark ? const Color(0xFF171A24) : Colors.white;
  Color get border => primary.withValues(alpha: dark ? 0.48 : 0.35);
  Color get selection => primary.withValues(alpha: dark ? 0.15 : 0.10);
  Color get track => primary.withValues(alpha: dark ? 0.18 : 0.12);
}

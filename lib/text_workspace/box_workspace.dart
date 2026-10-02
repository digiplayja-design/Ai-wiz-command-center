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
      if (_boxes.isNotEmpty) _select(_boxes.first);
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
    final box = SavedBox(title: title, text: text, folder: folder);
    setState(() {
      _boxes.insert(0, box);
      _select(box);
      _query = '';
      _favorites = false;
    });
    await _save();
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
    await _writes;
    if (!mounted || !_valid) return;
    try {
      await widget.store.importLegacy(_boxes);
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
    return PopScope(
      canPop: !_listening && !_starting,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _stop();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_name)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.store.voice
                      ? 'Speak it. Shape it. Save it.'
                      : 'Your words, ready to reuse.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Private to this account on this browser/device. No cross-device sync. $_status',
                ),
                if (_loadFailed)
                  const SizedBox()
                else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _new(),
                        icon: const Icon(Icons.add),
                        label: const Text('New entry'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _preset,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Templates'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copy(
                          visible
                              .map((b) => '${b.title}\n${b.text}')
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
                          child: const Text('Import older boxes'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search titles, folders and text',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _favorites,
                        onSelected: (v) => setState(() => _favorites = v),
                      ),
                      const SizedBox(width: 12),
                      Text('${visible.length} entries'),
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, size) {
                        final list = ListView(
                          children: visible
                              .map(
                                (b) => ListTile(
                                  selected: identical(b, _selected),
                                  leading: Icon(
                                    b.favorite
                                        ? Icons.star
                                        : Icons.article_outlined,
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
                        );
                        final editor = _selected == null
                            ? const Center(
                                child: Text(
                                  'Create an entry or choose a template to get started.',
                                ),
                              )
                            : _editor();
                        if (size.maxWidth >= 800) {
                          return Row(
                            children: [
                              SizedBox(width: 260, child: list),
                              const VerticalDivider(),
                              Expanded(child: editor),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            SizedBox(
                              height: visible.isEmpty ? 0 : 110,
                              child: list,
                            ),
                            const Divider(),
                            Expanded(child: editor),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() => SingleChildScrollView(
    child: Column(
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
          const Text(
            'Dictation appends to this entry. Speech recognition availability and processing depend on your browser/device.',
          ),
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
          minLines: 8,
          maxLines: 18,
          onChanged: (_) => _edit(),
          decoration: InputDecoration(
            labelText: widget.store.voice ? 'Transcript / notes' : 'Saved text',
            hintText: widget.store.voice
                ? 'Speak, type or paste your notes…'
                : 'Write reusable text. Use {{client}} for template fields.',
            border: const OutlineInputBorder(),
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _busy ? 'Creating AI draft…' : 'Improve with KORLIX ▾',
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
    ),
  );
}

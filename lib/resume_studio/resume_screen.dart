import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_action_grid.dart';
import '../theme/korlix_theme.dart';
import 'resume_client.dart';
import 'resume_design.dart';
import 'resume_export.dart';
import 'resume_model.dart';

part 'resume_editor.dart';

typedef ResumeFileSaver =
    Future<void> Function(Uint8List, String, String, Rect);

class ResumeScreen extends StatefulWidget {
  const ResumeScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.saveFile = saveBookkeepingFile,
  });
  final ResumeClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final ResumeFileSaver saveFile;
  @override
  State<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<ResumeScreen> {
  List<ResumeDraft> _drafts = [];
  ResumeDraft? _draft;
  final List<ResumeDraft> _undo = [];
  bool _reviewing = false;
  bool _loading = true,
      _busy = false,
      _dirty = false,
      _denied = false,
      _loadFailed = false;
  String? _error;
  int _tab = 0, _epoch = 0;
  String _section = 'basics';
  Route<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _deny;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    widget.client.dispose();
    super.dispose();
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _denied = true;
      _draft = null;
      _drafts = [];
      _undo.clear();
      _error = null;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route != null) {
        Navigator.of(context).popUntil((r) => r == _route || r.isFirst);
      }
    });
  }

  Future<void> _load() async {
    try {
      final drafts = await widget.client.drafts();
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _loading = false;
          _loadFailed = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _refreshUi(VoidCallback action) {
    if (mounted) setState(action);
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy || _denied) return;
    setState(() {
      _busy = true;
      _reviewing = false;
      _error = null;
    });
    try {
      widget.client.guard();
      await action();
    } catch (e) {
      if (mounted && !_denied) {
        setState(
          () => _error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _reviewing = false;
        });
      }
    }
  }

  void _change(VoidCallback action, {bool checkpoint = false}) {
    if (_busy || _denied) return;
    widget.client.guard();
    setState(() {
      if (checkpoint) {
        _undo.add(_draft!.clone());
        if (_undo.length > 10) _undo.removeAt(0);
      }
      action();
      _dirty = true;
    });
  }

  void _open(ResumeDraft d, {bool isNew = false}) {
    widget.client.guard();
    setState(() {
      _draft = d.clone();
      _dirty = isNew;
      _undo.clear();
      _tab = 0;
      _section = 'basics';
      _epoch++;
      _error = null;
    });
  }

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(detail),
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
      ) ??
      false;
  Future<bool> _save() async {
    if (_draft == null || _loadFailed) return false;
    final copy = _draft!.clone()
      ..updated = DateTime.now().toUtc().toIso8601String();
    final list = [copy, ..._drafts.where((d) => d.id != copy.id)];
    await widget.client.saveAll(list);
    if (!mounted || _denied) return false;
    setState(() {
      _drafts = list;
      _draft = copy;
      _dirty = false;
    });
    return true;
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_draft != null) {
      if (_dirty) {
        final action = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Keep your changes?'),
            content: const Text(
              'Save this draft on your device before returning to My resumes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'discard'),
                child: const Text('Discard changes'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'save'),
                child: const Text('Save draft'),
              ),
            ],
          ),
        );
        if (!mounted || action == null || _denied) return;
        if (action == 'save') {
          var saved = false;
          await _work(() async {
            saved = await _save();
          });
          if (!saved) return;
        }
      }
      if (mounted) {
        setState(() {
          _draft = null;
          _dirty = false;
          _undo.clear();
          _error = null;
        });
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _remove(ResumeDraft d) async {
    if (!await _confirm(
      'Delete this draft?',
      '“${d.title}” will be removed from this device. Exported copies are unaffected.',
      'Delete draft',
    )) {
      return;
    }
    await _work(() async {
      final next = _drafts.where((x) => x.id != d.id).toList();
      await widget.client.saveAll(next);
      if (mounted) setState(() => _drafts = next);
    });
  }

  Future<void> _suggest({
    required String title,
    required String instruction,
    required String facts,
    required String before,
    required void Function(String) apply,
    int maxLength = 12000,
  }) async {
    await _work(() async {
      if (!await widget.ensureConsent(context) || !mounted) return;
      widget.client.guard();
      final suggestion = await widget.client.suggest(instruction, facts);
      if (!mounted) return;
      if (suggestion.length > maxLength) {
        throw const ResumeException(
          'The suggestion was too long. Shorten the source text and try again.',
        );
      }
      setState(() => _reviewing = true);
      final value = await _reviewSuggestion(
        title,
        suggestion,
        before,
        maxLength,
      );
      widget.client.guard();
      if (value == null || !mounted) return;
      setState(() {
        _undo.add(_draft!.clone());
        if (_undo.length > 10) _undo.removeAt(0);
        apply(value);
        _epoch++;
        _dirty = true;
      });
    });
  }

  Future<String?> _reviewSuggestion(
    String title,
    String suggestion,
    String before,
    int maxLength,
  ) async {
    final controller = TextEditingController(text: suggestion);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Check every fact before applying. You can edit this suggestion.',
                ),
                const SizedBox(height: 16),
                if (before.isNotEmpty)
                  ExpansionTile(
                    title: const Text('Your original wording'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(before),
                      ),
                    ],
                  ),
                TextField(
                  controller: controller,
                  minLines: 6,
                  maxLines: 16,
                  maxLength: 12000,
                  decoration: const InputDecoration(
                    labelText: 'K-Nova suggestion',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Keep original'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Apply to draft'),
          ),
        ],
      ),
    );
    // Let the dialog finish its reverse animation before disposing its editor.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    return result;
  }

  Future<void> _import() async {
    final text = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start with your experience'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Paste an existing resume, or upload a PDF, Word, or text file. K-Nova will organize the facts for your review.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: text,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 25000,
                  decoration: const InputDecoration(
                    labelText: 'Paste resume text',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI actions use your plan’s generation allowance. File import requires a plan with document uploads; scans may require advanced upload access.',
                  style: TextStyle(fontSize: 12),
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
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(c, 'file'),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Choose file'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'text'),
            child: const Text('Organize text'),
          ),
        ],
      ),
    );
    final pasted = text.text.trim();
    Future<void>.delayed(const Duration(milliseconds: 400), text.dispose);
    if (choice == null || !mounted) return;
    await _work(() async {
      if (choice == 'text' && pasted.isEmpty) {
        throw const ResumeException('Paste your resume text first.');
      }
      if (!await widget.ensureConsent(context) || !mounted) return;
      widget.client.guard();
      String response;
      if (choice == 'file') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'docx', 'txt'],
          withData: true,
        );
        widget.client.guard();
        if (picked == null || picked.files.isEmpty) return;
        final f = picked.files.single;
        if (f.size > 5 * 1024 * 1024 || f.bytes == null) {
          throw const ResumeException('Choose a readable file up to 5 MB.');
        }
        response = await widget.client.importFile(f.bytes!, f.name);
      } else {
        response = await widget.client.suggest(resumeImportInstruction, pasted);
      }
      final draft = resumeFromAiImport(response);
      if (!mounted) return;
      setState(() => _reviewing = true);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Review imported facts'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text(
                    'Check names, dates, and achievements against your original. This creates a new draft.',
                  ),
                  const SizedBox(height: 20),
                  ResumePaper(draft: draft),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Use this draft'),
            ),
          ],
        ),
      );
      widget.client.guard();
      if (accepted == true && mounted) _open(draft, isNew: true);
    });
  }

  Future<void> _export(String format, {bool letter = false}) async {
    await _work(() async {
      final draft = _draft!.clone();
      if (draft.get('name').isEmpty) {
        throw const ResumeException('Add your name before exporting.');
      }
      if (letter && draft.get('letter').isEmpty) {
        throw const ResumeException('Write or generate a cover letter first.');
      }
      final bytes = switch (format) {
        'pdf' => await resumePdf(draft, letter: letter),
        'docx' => resumeDocx(draft, letter: letter),
        _ => Uint8List.fromList(
          utf8.encode(
            letter
                ? draft.blocks(letter: true).map((b) => b.text).join('\n\n')
                : draft.text,
          ),
        ),
      };
      widget.client.guard();
      if (!mounted) return;
      final mime = switch (format) {
        'pdf' => 'application/pdf',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => 'text/plain',
      };
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : box.localToGlobal(Offset.zero) & box.size;
      await widget.saveFile(
        bytes,
        '${draft.fileStem}${letter ? '-Cover-Letter' : ''}.$format',
        mime,
        origin,
      );
      widget.client.guard();
      _notice(
        'Your ${letter ? 'cover letter' : 'resume'} is ready. Check your downloads or share sheet.',
      );
    });
  }

  Future<void> _preview({bool letter = false}) async {
    final previewDraft = _draft!.clone();
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close preview',
              onPressed: () => Navigator.pop(c),
              icon: const Icon(Icons.close),
            ),
            title: Text(letter ? 'Cover letter preview' : 'Resume preview'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    const Text(
                      'Content preview. PDF pages flow automatically; Word remains editable.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ResumePaper(draft: previewDraft, letter: letter),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) => KorlixActionButton(
    label: label,
    icon: icon,
    onPressed: _busy || _denied ? null : action,
    selected: selected ? true : null,
    size: KorlixButtonSize.compact,
  );
  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: TextStyle(color: korlixSkinOf(context).mutedText, height: 1.6),
      ),
      const SizedBox(height: 20),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return PopScope(
      canPop: _draft == null && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: s.backgroundBottom,
        appBar: AppBar(
          leading: IconButton(
            tooltip: _draft == null ? 'Back' : 'My resumes',
            onPressed: _busy ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Resume Studio'),
          actions: [
            if (_draft != null && !_denied)
              IconButton(
                tooltip: 'Save draft on this device',
                onPressed: _busy
                    ? null
                    : () => _work(() async {
                        if (await _save()) {
                          _notice('Draft saved on this device.');
                        }
                      }),
                icon: const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: _denied
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _heading(
                    'Sign in again',
                    'Your session changed. Close and reopen Resume Studio.',
                  ),
                ),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_busy && !_reviewing)
                    const LinearProgressIndicator(minHeight: 3),
                  if (_busy && !_reviewing)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Working on your request…',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_error != null)
                    MaterialBanner(
                      content: Text(_error!),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _error = null),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey(
                        _draft == null ? 'resume-hub' : 'resume-editor',
                      ),
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width < 370 ? 14 : 22,
                        16,
                        MediaQuery.sizeOf(context).width < 370 ? 14 : 22,
                        40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: _draft == null ? _hub() : _editor(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _hub() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ResumeHero(),
      const SizedBox(height: 22),
      if (_loadFailed)
        _button('Retry saved drafts', Icons.refresh, () => _load())
      else
        KorlixActionGrid(
          compact: true,
          minimumHeight: 96,
          children: [
            _button(
              'Create a resume',
              Icons.add_rounded,
              () => _open(ResumeDraft(), isNew: true),
            ),
            _button('Import a resume', Icons.upload_file_outlined, _import),
          ],
        ),
      const SizedBox(height: 30),
      _heading(
        'My resumes',
        'Saved on this device for your signed-in account. Save edits before closing; export a copy to keep elsewhere.',
      ),
      if (_drafts.isEmpty && !_loadFailed)
        ResumePanel(
          child: Column(
            children: [
              Icon(
                Icons.description_outlined,
                size: 36,
                color: korlixSkinOf(context).primary,
              ),
              const SizedBox(height: 14),
              const Text(
                'Make your first impression count.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start fresh or bring the resume you already have.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      for (final d in _drafts)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ResumePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      color: korlixSkinOf(context).primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        d.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Draft options',
                      onSelected: (v) {
                        if (v == 'copy') {
                          _open(d.clone(newIdentity: true), isNew: true);
                        } else {
                          _remove(d);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('Duplicate for another job'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete draft'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  d.get('role').isEmpty ? 'Add a target role' : d.get('role'),
                ),
                const SizedBox(height: 8),
                Text(
                  '${d.checks.where((x) => x.done).length} of ${d.checks.length} essentials · ${d.template} · ${d.updated.isEmpty ? 'Not saved' : d.updated.split('T').first}',
                  style: TextStyle(
                    color: korlixSkinOf(context).mutedText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                _button(
                  'Open resume',
                  Icons.arrow_forward_rounded,
                  () => _open(d),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

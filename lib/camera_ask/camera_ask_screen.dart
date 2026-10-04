import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../bookkeeping/bookkeeping_file_save.dart';
import '../theme/korlix_action_button.dart';
import 'camera_ask_client.dart';
import 'camera_capture.dart';

Future<List<CameraPhoto>> pickCameraAskPhotos(int limit) async {
  final picker = ImagePicker();
  final List<XFile> picked;
  if (limit == 1) {
    final p = await picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    picked = p == null ? [] : [p];
  } else {
    picked = await picker.pickMultiImage(
      limit: limit,
      requestFullMetadata: false,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
  }
  if (picked.length > limit) {
    throw const CameraAskException(
      'You can use up to three photos in one question.',
    );
  }
  final result = <CameraPhoto>[];
  for (final p in picked) {
    if (await p.length() > 8 * 1024 * 1024) {
      throw const CameraAskException('Choose photos up to 8 MB each.');
    }
    result.add(CameraPhoto(bytes: await p.readAsBytes(), name: p.name));
  }
  return result;
}

class CameraAskLaunchButton extends StatelessWidget {
  const CameraAskLaunchButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => KorlixActionButton(
    label: 'Camera Ask',
    subtitle: 'See it. Ask it.',
    icon: Icons.center_focus_strong_rounded,
    onPressed: onPressed,
  );
}

class CameraAskScreen extends StatefulWidget {
  const CameraAskScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.initialQuestion = '',
    this.language = 'en',
    this.pickPhotos = pickCameraAskPhotos,
    this.capture = captureCameraAskPhoto,
    this.saveFile = saveBookkeepingFile,
  });
  final CameraAskClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final String initialQuestion, language;
  final Future<List<CameraPhoto>> Function(int) pickPhotos;
  final Future<CameraPhoto?> Function(BuildContext) capture;
  final Future<void> Function(Uint8List, String, String, Rect) saveFile;
  @override
  State<CameraAskScreen> createState() => _CameraAskScreenState();
}

class _CameraAskScreenState extends State<CameraAskScreen> {
  late final TextEditingController _question = TextEditingController(
    text: widget.initialQuestion,
  );
  final _focus = FocusNode(),
      _questionKey = GlobalKey(),
      _answerKey = GlobalKey();
  final List<CameraPhoto> _photos = [];
  final List<CameraAskTurn> _turns = [];
  CameraAskMode _mode = CameraAskMode.understand;
  late String _language = ['en', 'es', 'fr'].contains(widget.language)
      ? widget.language
      : 'en';
  String _detail = 'Brief', _error = '';
  bool _busy = false, _picking = false, _expired = false, _allowLeave = false;
  int _selected = 0;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _canvas =>
      _dark ? const Color(0xFF090F1A) : const Color(0xFFF3F6FA);
  Color get _surface => _dark ? const Color(0xFF111D2C) : Colors.white;
  Color get _ink => _dark ? const Color(0xFFEDF3FC) : const Color(0xFF182C3E);
  Color get _muted => _dark ? const Color(0xFFACBDCF) : const Color(0xFF52677D);
  Color get _accent =>
      _dark ? const Color(0xFF8DE8D9) : const Color(0xFF006F67);
  Color get _line => _dark ? const Color(0xFF293B50) : const Color(0xFFD6E2EC);
  bool get _editable => !_busy && !_picking && _turns.isEmpty && !_expired;

  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _expire;
    scheduleMicrotask(() {
      if (mounted) {
        try {
          widget.client.guard();
        } catch (_) {
          _expire();
        }
      }
    });
  }

  void _expire() {
    if (!mounted || _expired) return;
    setState(() {
      _expired = true;
      _busy = false;
      _picking = false;
      _photos.clear();
      _turns.clear();
      _question.clear();
      _error = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final own = ModalRoute.of(context);
      Navigator.of(context).popUntil((route) => route == own || route.isFirst);
    });
  }

  @override
  void dispose() {
    widget.client.dispose();
    _question.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    if (!mounted || _expired) return;
    setState(
      () => _error = error is CameraAskException ? error.message : 'That action could not be completed. Try again or choose a different photo.',
    );
  }

  Future<void> _pick({bool camera = false, bool replace = false}) async {
    if (!_editable || (!replace && _photos.length >= 3)) return;
    setState(() {
      _picking = true;
      _error = '';
    });
    try {
      widget.client.guard();
      final List<CameraPhoto> chosen;
      if (camera) {
        final p = await widget.capture(context);
        chosen = p == null ? [] : [p];
      } else {
        chosen = await widget.pickPhotos(3 - _photos.length);
      }
      if (!mounted) return;
      widget.client.guard();
      if (chosen.isEmpty) return;
      final next = List<CameraPhoto>.from(_photos);
      if (replace) {
        next[_selected] = chosen.first;
      } else {
        next.addAll(chosen);
      }
      if (next.length > 3 ||
          next.fold<int>(0, (n, p) => n + p.bytes.length) > 16 * 1024 * 1024) {
        throw const CameraAskException(
          'Use up to three photos, up to 16 MB combined.',
        );
      }
      setState(() {
        _photos
          ..clear()
          ..addAll(next);
        _selected = replace ? _selected : next.length - 1;
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted && !_expired) setState(() => _picking = false);
    }
  }

  Future<void> _ask() async {
    if (_busy || _picking || _expired) return;
    if (_photos.isEmpty) {
      _fail(const CameraAskException('Take or choose a photo first.'));
      return;
    }
    if (_mode == CameraAskMode.compare && _photos.length < 2) {
      _fail(const CameraAskException('Add at least two photos to compare.'));
      return;
    }
    if (_turns.isNotEmpty && _question.text.trim().isEmpty) {
      _focusQuestion();
      return;
    }
    final question = _question.text.trim().isEmpty
        ? _mode.question
        : _question.text.trim();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      widget.client.guard();
      if (!await widget.ensureConsent(context) || !mounted) return;
      widget.client.guard();
      final result = await widget.client.ask(
        photos: List.unmodifiable(_photos),
        question: question,
        mode: _mode,
        language: _language,
        detail: _detail,
        history: List.unmodifiable(_turns),
      );
      if (!mounted) return;
      widget.client.guard();
      setState(() {
        _turns.add(result);
        _question.clear();
      });
      _focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _answerKey.currentContext;
        if (mounted && target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
            ),
          );
        }
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted && !_expired) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep working'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _newSession() async {
    if (_busy || _picking || _expired) return;
    if ((_photos.isNotEmpty || _turns.isNotEmpty) &&
        !await _confirm(
          'Start a new photo session?',
          'This clears the current photos and conversation. Export any answers you want to keep.',
          'Start new',
        )) {
      return;
    }
    if (!mounted) return;
    try {
      widget.client.guard();
      setState(() {
        _photos.clear();
        _turns.clear();
        _question.clear();
        _selected = 0;
        _error = '';
        _mode = CameraAskMode.understand;
      });
    } catch (e) {
      _fail(e);
    }
  }

  void _focusQuestion([String? text]) {
    if (_busy || _expired) return;
    if (text != null) setState(() => _question.text = text);
    final target = _questionKey.currentContext;
    if (target != null) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        ),
      );
    }
    _focus.requestFocus();
  }

  Future<void> _copy(CameraAskTurn turn) async {
    try {
      widget.client.guard();
      await Clipboard.setData(ClipboardData(text: turn.answer));
      if (mounted && !_expired) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Answer copied')));
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _export() async {
    try {
      widget.client.guard();
      final body =
          'KORLIX Camera Ask\n\n${_turns.map((t) => 'QUESTION\n${t.question}\n\nANSWER\n${t.answer}').join('\n\n────────\n\n')}';
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 100, 100)
          : box.localToGlobal(Offset.zero) & box.size;
      await widget.saveFile(
        Uint8List.fromList(utf8.encode(body)),
        'KORLIX-Camera-Ask.txt',
        'text/plain',
        origin,
      );
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _zoom() async {
    if (_photos.isEmpty || _expired) return;
    try {
      widget.client.guard();
    } catch (e) {
      _fail(e);
      return;
    }
    final photo = _photos[_selected];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text('Photo ${_selected + 1}'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                photo.bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, e, s) => const Text(
                  'This photo could not be displayed.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(22),
  }) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? .13 : .04),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: _line),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: _accent,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.7,
    ),
  );
  Widget _photoPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _label('YOUR VIEW'),
            const Spacer(),
            Text(
              '${_photos.length} / 3 photos',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_photos.isEmpty) ...[
          SizedBox(
            height: 195,
            child: CustomPaint(painter: _CameraLensPainter(_accent, _dark)),
          ),
          Text(
            'A picture is a great place to start.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'An object, a page, a problem, or something that needs a closer look.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.5),
          ),
        ] else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _photos[_selected].bytes,
                      fit: BoxFit.contain,
                      cacheWidth: 1600,
                      errorBuilder: (_, e, s) => const Center(
                        child: Text(
                          'Photo preview unavailable. Choose another photo.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: IconButton.filled(
                        tooltip: 'Enlarge photo',
                        onPressed: _zoom,
                        icon: const Icon(Icons.zoom_in_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _photos.length,
              (i) => ChoiceChip(
                label: Text('Photo ${i + 1}'),
                selected: i == _selected,
                onSelected: (_) => setState(() => _selected = i),
                avatar: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.memory(
                    _photos[i].bytes,
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    cacheWidth: 100,
                    errorBuilder: (_, e, s) =>
                        const Icon(Icons.photo_outlined, size: 18),
                  ),
                ),
              ),
            ),
          ),
          if (_turns.isEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _editable
                        ? () => _pick(camera: true, replace: true)
                        : null,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Retake'),
                  ),
                  TextButton.icon(
                    onPressed: _editable
                        ? () => setState(() {
                            _photos.removeAt(_selected);
                            _selected = 0;
                          })
                        : null,
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 20),
        if (_turns.isEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const Key('camera-ask-capture'),
                onPressed: _editable && _photos.length < 3
                    ? () => _pick(camera: true)
                    : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
              OutlinedButton.icon(
                key: const Key('camera-ask-gallery'),
                onPressed: _editable && _photos.length < 3
                    ? () => _pick()
                    : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos'),
              ),
            ],
          )
        else
          Text(
            'These photos stay attached to your follow-up questions. Use New for different pictures.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        if (_picking)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 14),
        Text(
          _photos.isEmpty
              ? 'JPG, PNG, or WebP · Up to 8 MB each'
              : 'Preview locally. Send to OpenAI only when you tap Ask.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
        ),
      ],
    ),
  );
  Widget _questionPanel() => _panel(
    Column(
      key: _questionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('MAKE IT USEFUL'),
        const SizedBox(height: 10),
        Text(
          'What would you like to know?',
          style: TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CameraAskMode.values
              .map(
                (mode) => ChoiceChip(
                  label: Text(mode.label),
                  selected: mode == _mode,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _mode = mode),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('camera-ask-question'),
          controller: _question,
          focusNode: _focus,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _turns.isEmpty ? 'Your question' : 'Your follow-up',
            hintText: _turns.isEmpty
                ? _mode.question
                : 'Ask something else about these photos.',
            alignLabelWithHint: true,
            filled: true,
            fillColor: _canvas,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(
                  labelText: 'Answer language',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'es', child: Text('Español')),
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _language = v!),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _detail,
                decoration: const InputDecoration(
                  labelText: 'Answer style',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: ['Brief', 'Detailed', 'Step by step']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _detail = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: _accent, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _mode == CameraAskMode.compare
                    ? 'Add two or three photos. Ask about differences, labels, condition, or visible features.'
                    : 'For better answers, keep labels and small text sharp. Mention the detail you want Rici to focus on.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _answerBody(String answer) {
    final spans = <TextSpan>[];
    for (final line in answer.split('\n')) {
      final heading = RegExp(r'^#{1,4}\s+').hasMatch(line);
      final clean = line.replaceFirst(RegExp(r'^#{1,4}\s+'), '');
      var start = 0;
      final pieces = <TextSpan>[];
      for (final match in RegExp(r'\*\*(.+?)\*\*').allMatches(clean)) {
        pieces.add(TextSpan(text: clean.substring(start, match.start)));
        pieces.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        start = match.end;
      }
      pieces.add(TextSpan(text: '${clean.substring(start)}\n'));
      spans.add(
        TextSpan(
          children: pieces,
          style: heading
              ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 19)
              : null,
        ),
      );
    }
    return SelectableText.rich(
      TextSpan(children: spans),
      style: TextStyle(color: _ink, fontSize: 15, height: 1.6),
    );
  }

  Widget _answers() => Column(
    key: _answerKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 26),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'A closer look',
            style: TextStyle(
              color: _ink,
              fontSize: 27,
              fontWeight: FontWeight.w700,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export answers'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ..._turns.reversed.map(
        (turn) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Rici  /  ${turn.mode.label.toUpperCase()}'),
                const SizedBox(height: 14),
                Text(
                  turn.question,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                _answerBody(turn.answer),
                Divider(color: _line),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copy(turn),
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('Copy answer'),
                    ),
                    Text(
                      turn.generationId?.isNotEmpty == true
                          ? 'Saved to History'
                          : 'Export to keep a copy',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
                if (identical(turn, _turns.last))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Explain it simply'),
                        onPressed: _busy
                            ? null
                            : () => _focusQuestion(
                                'Explain that in simpler terms.',
                              ),
                      ),
                      ActionChip(
                        label: const Text('What should I do next?'),
                        onPressed: _busy
                            ? null
                            : () => _focusQuestion('What should I do next?'),
                      ),
                      ActionChip(
                        label: const Text('Ask a follow-up'),
                        onPressed: _busy ? null : () => _focusQuestion(),
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

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: _accent,
        onPrimary: _dark ? const Color(0xFF082D28) : Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: _muted),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: BorderSide(color: _line),
          minimumSize: const Size(48, 48),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    ),
    child: PopScope(
      canPop: !_busy || _allowLeave,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_busy) return;
        if (await _confirm(
          'Leave while Rici is answering?',
          'The request may finish and use one credit. Check History for its answer.',
          'Leave',
        )) {
          if (!mounted) return;
          setState(() => _allowLeave = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
      child: Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _canvas,
          foregroundColor: _ink,
          titleSpacing: 0,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/branding/korlix_mini_mark.png',
                  width: 27,
                  height: 27,
                ),
              ),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'Camera Ask',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              key: const Key('camera-ask-new'),
              onPressed: _busy || _picking || _expired ? null : _newSession,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('New'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: _expired
            ? null
            : SafeArea(
                top: false,
                child: Material(
                  color: _surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const Key('camera-ask-submit'),
                              onPressed:
                                  _busy ||
                                      _picking ||
                                      (_turns.isNotEmpty &&
                                          _question.text.trim().isEmpty)
                                  ? null
                                  : _photos.isEmpty
                                  ? () => _pick(camera: true)
                                  : _ask,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _photos.isEmpty
                                          ? Icons.camera_alt_outlined
                                          : Icons.auto_awesome_outlined,
                                      size: 20,
                                    ),
                              label: Text(
                                _busy
                                    ? 'Looking closely…'
                                    : _photos.isEmpty
                                    ? 'Take a photo'
                                    : _turns.isEmpty
                                    ? 'Ask Rici'
                                    : 'Ask follow-up',
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _busy
                                ? 'Preparing your answer. You can keep this page open.'
                                : '1 generation credit per answer · AI can make mistakes',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        body: _expired
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 38),
                      const SizedBox(height: 16),
                      const Text(
                        'Your sign-in changed. Reopen Camera Ask after signing in.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close Camera Ask'),
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('KORLIX  /  VISUAL INTELLIGENCE'),
                          const SizedBox(height: 10),
                          Text(
                            'See it. Understand it.',
                            style: TextStyle(
                              color: _ink,
                              fontSize: MediaQuery.sizeOf(context).width < 600
                                  ? 30
                                  : 40,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Turn what is in front of you into something you can use.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Material(
                                  color: _dark
                                      ? const Color(0xFF391E2A)
                                      : const Color(0xFFFFE9ED),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      _error,
                                      style: TextStyle(
                                        color: _dark
                                            ? const Color(0xFFFFB7C0)
                                            : const Color(0xFF8B2238),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          LayoutBuilder(
                            builder: (context, c) => c.maxWidth >= 850
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 6, child: _photoPanel()),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        flex: 5,
                                        child: _questionPanel(),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _photoPanel(),
                                      const SizedBox(height: 18),
                                      _questionPanel(),
                                    ],
                                  ),
                          ),
                          if (_turns.isNotEmpty) _answers(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

class _CameraLensPainter extends CustomPainter {
  const _CameraLensPainter(this.accent, this.dark);
  final Color accent;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2),
        r = math.min(size.width * .3, 78.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(0, r * .92),
        width: r * 2.8,
        height: r * .38,
      ),
      Paint()
        ..color = accent.withValues(alpha: .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      c,
      r * 1.1,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF63819B), const Color(0xFF0A1E2F)]
              : [Colors.white, const Color(0xFF9BB2C8)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.1)),
    );
    canvas.drawCircle(c, r * .98, Paint()..color = const Color(0xFF142D42));
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        c,
        r * (.62 + i * .065),
        Paint()
          ..color = accent.withValues(alpha: .14 + i * .07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    canvas.drawCircle(
      c,
      r * .62,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.4, -.5),
          colors: [accent, const Color(0xFF143C57), const Color(0xFF061322)],
        ).createShader(Rect.fromCircle(center: c, radius: r * .64)),
    );
    canvas.drawCircle(
      c - Offset(r * .19, r * .22),
      r * .18,
      Paint()..color = Colors.white.withValues(alpha: .18),
    );
    final p = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final dx in [-1.0, 1.0]) {
      for (final dy in [-1.0, 1.0]) {
        final corner = c + Offset(dx * r * 1.42, dy * r * 1.0);
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx - dx * 16, corner.dy)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx, corner.dy - dy * 16),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CameraLensPainter old) =>
      old.accent != accent || old.dark != dark;
}

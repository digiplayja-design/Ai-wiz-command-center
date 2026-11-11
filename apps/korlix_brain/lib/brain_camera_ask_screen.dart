import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'brain_api.dart';
import 'brain_camera_ask.dart';
import 'brain_camera_picker.dart';

/// Native photo selection and authenticated uploads never cross the home-page
/// WebView bridge. Photos are reviewed here before an explicit Ask tap.
class BrainCameraAskScreen extends StatefulWidget {
  const BrainCameraAskScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.pickPhotos,
  });
  final BrainCameraAskClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final Future<List<BrainCameraPhoto>> Function(bool camera, int remaining)? pickPhotos;

  @override
  State<BrainCameraAskScreen> createState() => _BrainCameraAskScreenState();
}

class _BrainCameraAskScreenState extends State<BrainCameraAskScreen> {
  final _question = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _photos = <BrainCameraPhoto>[];
  final _turns = <BrainCameraAskTurn>[];
  final _reported = <BrainCameraAskTurn>{};
  final _dialogs = <Route<dynamic>>{};
  late final BrainCameraPicker _picker;
  BrainCameraAskMode _mode = BrainCameraAskMode.understand;
  String _language = 'en', _detail = 'Brief', _error = '', _notice = '';
  bool _busy = false, _picking = false, _reporting = false, _expired = false, _allowExit = false, _confirmingExit = false;
  bool get _editable => !_busy && !_picking && !_expired && _turns.isEmpty;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_accountChanged);
    _picker = BrainCameraPicker(
      owner: widget.client.owner ?? '',
      isCurrent: () => mounted && !_expired && !widget.client.expired,
    );
    scheduleMicrotask(() async {
      try {
        widget.client.guard();
        if (widget.pickPhotos == null) {
          if (mounted) setState(() => _picking = true);
          final recovered = await _picker.recover();
          if (!mounted) return;
          widget.client.guard();
          if (recovered.isNotEmpty) {
            setState(() {
              _photos.addAll(recovered);
              _notice = 'Your selected photo was recovered. Review it before asking Rici.';
            });
          }
        }
      } catch (error) {
        _fail(error);
      } finally {
        if (mounted && !_expired) setState(() => _picking = false);
      }
    });
  }

  void _accountChanged() {
    if (!mounted || _expired || !widget.client.expired) return;
    setState(() {
      _expired = true;
      _busy = false;
      _picking = false;
      _photos.clear();
      _turns.clear();
      _reported.clear();
      _question.clear();
      _error = '';
      _notice = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final route in List<Route<dynamic>>.of(_dialogs)) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  void _fail(Object error) {
    if (!mounted || _expired) return;
    setState(() {
      if (error is BrainCameraAskException) {
        _error = error.message;
      } else if (error is BrainApiException) {
        _error = error.message;
      } else if (error is PlatformException &&
          ['camera_access_denied', 'photo_access_denied', 'camera_access_restricted', 'photo_access_restricted'].contains(error.code)) {
        _error = 'Allow camera or photo access in your device Settings, then try again.';
      } else {
        _error = 'That action could not be completed. Try again or choose a different photo.';
      }
    });
  }

  Future<void> _pick(bool camera) async {
    if (!_editable || _photos.length >= 3) return;
    setState(() { _picking = true; _error = ''; _notice = ''; });
    try {
      widget.client.guard();
      final chosen = await (widget.pickPhotos ?? _picker.pick)(camera, 3 - _photos.length);
      if (!mounted) return;
      widget.client.guard();
      final next = [..._photos, ...chosen];
      if (next.length > 3 || next.fold<int>(0, (n, p) => n + p.bytes.length) > 16 * 1024 * 1024) {
        throw const BrainCameraAskException('Use up to three photos, up to 16 MB combined.');
      }
      setState(() { _photos.clear(); _photos.addAll(next); });
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted && !_expired) setState(() => _picking = false);
    }
  }

  Future<void> _ask() async {
    if (_busy || _picking || _expired) return;
    if (_photos.isEmpty) {
      _fail(const BrainCameraAskException('Take or choose a photo first.'));
      return;
    }
    if (_mode == BrainCameraAskMode.compare && _photos.length < 2) {
      _fail(const BrainCameraAskException('Add at least two photos to compare.'));
      return;
    }
    if (_question.text.trim().isEmpty && _turns.isNotEmpty) {
      _focus.requestFocus();
      return;
    }
    final question = _question.text.trim().isEmpty ? _mode.question : _question.text.trim();
    setState(() { _busy = true; _error = ''; _notice = ''; });
    try {
      widget.client.guard();
      if (!await widget.ensureConsent(context) || !mounted) return;
      widget.client.guard();
      final turn = await widget.client.ask(
        photos: List.unmodifiable(_photos), question: question, mode: _mode,
        language: _language, detail: _detail, history: List.unmodifiable(_turns),
      );
      if (!mounted) return;
      widget.client.guard();
      setState(() { _turns.add(turn); _question.clear(); });
      _focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          unawaited(_scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
        }
      });
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted && !_expired) setState(() => _busy = false);
    }
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    _dialogs.add(route);
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      _dialogs.remove(route);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await _dialog<bool>((c) => AlertDialog(
        title: Text(title), content: Text(body), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      )) ?? false;

  Future<void> _newPhotos() async {
    if (_busy || _picking || _expired) return;
    if (_turns.isNotEmpty && !await _confirm('Start with new photos?',
        'This clears the photos and conversation on this screen. Copy or share any answer you want to keep.', 'New photos')) return;
    if (!mounted) return;
    try {
      widget.client.guard();
      setState(() {
        _photos.clear(); _turns.clear(); _reported.clear(); _question.clear();
        _error = ''; _notice = '';
      });
    } catch (error) { _fail(error); }
  }

  Future<void> _leave() async {
    if (_allowExit || _confirmingExit) return;
    _confirmingExit = true;
    try {
      if (_busy && !await _confirm('Leave Camera Ask?',
          'The answer may still finish in your KORLIX History. Leaving does not guarantee the request or its credit charge is canceled.', 'Leave')) return;
      if (!mounted) return;
      setState(() => _allowExit = true);
      // Update the route's PopScope before retrying the blocked back action.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _copy(BrainCameraAskTurn turn) async {
    try {
      widget.client.guard();
      await Clipboard.setData(ClipboardData(text: turn.shareText));
      if (!mounted) return;
      widget.client.guard();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer copied')));
    } catch (error) { _fail(error); }
  }

  Future<void> _share(BrainCameraAskTurn turn, BuildContext buttonContext) async {
    try {
      widget.client.guard();
      final box = buttonContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || box.size.width <= 0 || box.size.height <= 0) {
        throw const BrainCameraAskException('The share button is not ready. Please try again.');
      }
      await SharePlus.instance.share(ShareParams(
        text: turn.shareText, subject: 'KORLIX Camera Ask',
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (error) { _fail(error); }
  }

  Future<void> _report(BrainCameraAskTurn turn) async {
    if (_reporting || _reported.contains(turn) || _expired) return;
    setState(() => _reporting = true);
    try {
      widget.client.guard();
      final reason = await _dialog<String>((c) => SimpleDialog(
        title: const Text('Report this answer'), children: [
          for (final reason in BrainCameraAskClient.reportReasons)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, reason), child: Text(reason)),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        ],
      ));
      if (reason == null || !mounted) return;
      widget.client.guard();
      await widget.client.report(turn, reason);
      if (!mounted) return;
      widget.client.guard();
      setState(() => _reported.add(turn));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your report has been received for review.')));
    } catch (error) { _fail(error); }
    finally { if (mounted) setState(() => _reporting = false); }
  }

  @override
  void dispose() {
    widget.client.removeListener(_accountChanged);
    widget.client.dispose();
    _question.dispose(); _focus.dispose(); _scroll.dispose();
    super.dispose();
  }

  Widget _answer(BrainCameraAskTurn turn) => Card(child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(turn.question, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      const Text('RICI', style: TextStyle(color: Color(0xff9eeaff), letterSpacing: 2)),
      const SizedBox(height: 8),
      SelectableText(turn.answer),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        TextButton.icon(onPressed: () => _copy(turn), icon: const Icon(Icons.copy_rounded), label: const Text('Copy')),
        Builder(builder: (c) => TextButton.icon(onPressed: () => _share(turn, c), icon: const Icon(Icons.ios_share_rounded), label: const Text('Share'))),
        TextButton.icon(onPressed: _reporting || _reported.contains(turn) ? null : () => _report(turn),
          icon: const Icon(Icons.flag_outlined), label: Text(_reported.contains(turn) ? 'Reported' : 'Report')),
      ]),
      Text('${turn.creditsUsed} ${turn.creditsUsed == 1 ? 'credit' : 'credits'} used${turn.generationId == null ? '' : ' · Saved in KORLIX History'}',
        style: Theme.of(context).textTheme.bodySmall),
    ]),
  ));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit || !_busy,
    onPopInvokedWithResult: (didPop, _) { if (!didPop) unawaited(_leave()); },
    child: Scaffold(
      appBar: AppBar(title: const Text('Camera Ask'), actions: [
        if (!_expired && (_photos.isNotEmpty || _turns.isNotEmpty))
          IconButton(tooltip: 'New photos', onPressed: _busy || _picking ? null : _newPhotos, icon: const Icon(Icons.add_photo_alternate_outlined)),
      ]),
      body: SafeArea(child: _expired
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Your sign-in changed. Close this screen and sign in again to use Camera Ask.')))
        : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(
          controller: _scroll, padding: const EdgeInsets.all(18), children: [
            Text('See it. Ask Rici.', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text('Take a photo or choose up to three. Review them here, then ask a question.'),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(onPressed: _editable && _photos.length < 3 ? () => _pick(true) : null,
                icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo')),
              OutlinedButton.icon(onPressed: _editable && _photos.length < 3 ? () => _pick(false) : null,
                icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photos')),
            ]),
            if (_picking) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
            if (_photos.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: SizedBox(
              height: 174, child: ListView.separated(
                scrollDirection: Axis.horizontal, itemCount: _photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (c, i) => SizedBox(width: 150, child: Column(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photos[i].bytes,
                    fit: BoxFit.contain, cacheWidth: 600,
                    errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                    semanticLabel: 'Photo ${i + 1} selected for Camera Ask'))),
                  Row(children: [Expanded(child: Text('Photo ${i + 1}')),
                    if (_editable) IconButton(tooltip: 'Remove photo ${i + 1}', onPressed: () => setState(() => _photos.removeAt(i)),
                      icon: const Icon(Icons.close_rounded, size: 18)),
                  ]),
                ])),
              ),
            )),
            if (_turns.isNotEmpty) const Padding(padding: EdgeInsets.only(bottom: 12),
              child: Text('Follow-up questions use these same photos. Choose New photos to start a different conversation.')),
            Text('What would you like to do?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 5, children: [
              for (final mode in BrainCameraAskMode.values)
                ChoiceChip(label: Text(mode.label), selected: _mode == mode,
                  onSelected: _busy ? null : (_) => setState(() => _mode = mode)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 10, children: [
              SizedBox(width: 170, child: DropdownButtonFormField<String>(
                initialValue: _language, decoration: const InputDecoration(labelText: 'Answer language'),
                items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'es', child: Text('Spanish')), DropdownMenuItem(value: 'fr', child: Text('French'))],
                onChanged: _busy ? null : (v) => setState(() => _language = v ?? 'en'),
              )),
              SizedBox(width: 150, child: DropdownButtonFormField<String>(
                initialValue: _detail, decoration: const InputDecoration(labelText: 'Detail'),
                items: const [DropdownMenuItem(value: 'Brief', child: Text('Brief')), DropdownMenuItem(value: 'Detailed', child: Text('Detailed'))],
                onChanged: _busy ? null : (v) => setState(() => _detail = v ?? 'Brief'),
              )),
            ]),
            const SizedBox(height: 16),
            TextField(controller: _question, focusNode: _focus, enabled: !_busy,
              minLines: 2, maxLines: 5, maxLength: 2000,
              decoration: InputDecoration(labelText: _turns.isEmpty ? 'Your question' : 'Ask a follow-up', hintText: _mode.question),
            ),
            FilledButton.icon(onPressed: _busy || _picking ? null : _ask,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
              label: Text(_busy ? 'Rici is looking…' : _turns.isEmpty ? 'Ask Rici' : 'Ask follow-up')),
            const SizedBox(height: 8),
            const Text('1 credit per answer from your existing KORLIX allowance. Answers can appear in KORLIX History. Photos and answers are not added to Memory or Training by this screen.', style: TextStyle(fontSize: 12)),
            if (_notice.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_notice)),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true,
              child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
            const SizedBox(height: 18),
            for (final turn in _turns) _answer(turn),
          ],
        ))),
      ),
    ),
  );
}

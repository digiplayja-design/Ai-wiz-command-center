import '../sounds/korlix_sound_service.dart';
import '../sounds/korlix_sound_actions.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' as ip;
import 'fieldproof_client.dart';
import 'fieldproof_email.dart';
import 'fieldproof_email_screen.dart';
import 'fieldproof_report.dart';
import 'fieldproof_saver.dart';
import 'fieldproof_workspace.dart';
import 'fieldproof_photos.dart';

const _ink = Color(0xFF102F43),
    _teal = Color(0xFF087D91),
    _muted = Color(0xFF557080),
    _line = Color(0xFFDCE7EC);

class FieldProofScreen extends StatefulWidget {
  const FieldProofScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.pickPhoto,
    this.pickBatch,
    this.openVoice,
    this.saveFile,
    this.copyText,
    this.renderPdf,
  });
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>? snapshot)?
  openVoice;
  final Future<List<FieldProofQueuedPhoto>> Function(int remaining)? pickBatch;
  final FieldProofClient client;
  final Future<bool> Function() ensureConsent;
  final Future<FieldProofPhoto?> Function(bool camera)? pickPhoto;
  final Future<void> Function(Uint8List bytes, String name, String mime)?
  saveFile;
  final Future<void> Function(String text)? copyText;
  final Future<Uint8List> Function(
    Map<String, dynamic>,
    Map<String, Uint8List>,
  )?
  renderPdf;
  @override
  State<FieldProofScreen> createState() => _FieldProofScreenState();
}

class _FieldProofScreenState extends State<FieldProofScreen> {
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _jobs = [];
  Map<String, dynamic> _templates = {}, _snapshot = {};
  String? _error, _notice, _createKey, _reviewKey;
  String _search = '', _filter = 'all', _sort = 'recent';
  Map<String, dynamic>? _editorDraft;
  int _editorGeneration = 0, _photoLimit = 24;
  bool _loading = true,
      _busy = false,
      _locked = false,
      _editing = false,
      _dirty = false,
      _dialogOpen = false,
      _refreshing = false;
  int _tab = 0;
  Timer? _timer;
  Map<String, dynamic> get _job => fpMap(_snapshot['job']);
  Map<String, dynamic> get _data => fpMap(_job['data']);
  List<Map<String, dynamic>> get _photos => fpRows(_snapshot['evidence']);
  bool get _running =>
      fpRows(_snapshot['reviews']).any((r) => r['state'] == 'running');
  bool get _working => _busy || _refreshing || _running;
  bool get _hasJob => _job.isNotEmpty;
  bool get _editable => _job['state'] == 'active' && !_working;
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    widget.client.onAccessDenied = null;
    widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _timer?.cancel();
    if (_dialogOpen) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _snapshot = {};
      _jobs = [];
      _error = _notice = _createKey = _reviewKey = null;
      _editing = _dirty = false;
      _editorDraft = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _feedback(String s) {
    if (!mounted || _locked) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _openEmail({bool forJob = false}) async {
    if (_working || _locked) return;
    final emailClient = FieldProofEmailClient(
      backendBaseUrl: widget.client.backendBaseUrl,
      headersBuilder: widget.client.headersBuilder,
      sessionChanges: widget.client.sessionChanges,
    );
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FieldProofEmailScreen(
        client: emailClient,
        ownsClient: true,
        jobId: forJob ? fpText(_job['id']) : null,
        jobTitle: forJob ? fpText(_data['title']) : null,
        jobCompleted: forJob && _job['state'] == 'completed',
        saveFile: widget.saveFile,
      ),
    ));
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load() async {
    if (_locked || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final r = await widget.client.load();
      if (!mounted || _locked) return;
      setState(() {
        _jobs = fpRows(r['jobs']);
        _templates = fpMap(r['templates']);
        _photoLimit = (fpMap(r['limits'])['photosPerJob'] as int?) ?? 24;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _accept(Map<String, dynamic> r) {
    if (!mounted || _locked) return;
    setState(() {
      _snapshot = r;
      _error = null;
    });
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (mounted && !_locked && _running) {
      _timer = Timer(
        const Duration(seconds: 3),
        () => unawaited(_refresh(poll: true)),
      );
    }
  }

  Future<void> _refresh({bool poll = false}) async {
    if (_locked || _refreshing) return;
    if (!_hasJob) {
      await _load();
      return;
    }
    final id = fpText(_job['id']);
    _refreshing = true;
    try {
      final r = await widget.client.job(id);
      if (!mounted || _locked || _job['id'] != id) return;
      final wasRunning = _running;
      _accept(r);
      if (wasRunning && !_running) {
        _reviewKey = null;
        final reviews = fpRows(r['reviews']);
        setState(
          () => _notice = reviews.firstOrNull?['state'] == 'completed'
              ? 'KORLIX review is ready. Check every finding.'
              : fpText(reviews.firstOrNull?['error']),
        );
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
      _schedule();
    }
  }

  Future<bool> _confirm(String title, String message) async {
    if (_locked) return false;
    _dialogOpen = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _dialogOpen = false;
    }
  }

  Future<bool> _discard() async =>
      !_dirty ||
      await _confirm(
        'Leave unsaved changes?',
        'Your latest edits have not been saved.',
      );
  Future<void> _open(String id) async {
    if (_busy || !await _discard() || !mounted || _locked) return;
    setState(() => _busy = true);
    try {
      final r = await widget.client.job(id);
      if (!mounted || _locked) return;
      _timer?.cancel();
      setState(() {
        _editing = _dirty = false;
        _editorDraft = null;
        _tab = 0;
        _notice = _reviewKey = null;
      });
      _accept(r);
      _top();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy || !await _discard() || !mounted || _locked) return;
    _timer?.cancel();
    setState(() {
      _snapshot = {};
      _editing = _dirty = false;
      _editorDraft = null;
      _error = _notice = _reviewKey = _createKey = null;
    });
    _top();
    await _load();
  }

  Future<void> _new() async {
    if (_busy || !await _discard() || !mounted || _locked) return;
    _timer?.cancel();
    setState(() {
      _snapshot = {};
      _editing = true;
      _dirty = false;
      _editorDraft = null;
      _editorGeneration++;
      _createKey = fieldProofRequestKey();
      _error = _notice = null;
    });
    _top();
  }

  Future<void> _voice() async {
    if (widget.openVoice == null || _working || _dirty || _locked) return;
    _timer?.cancel();
    try {
      final result = await widget.openVoice!(_hasJob ? _snapshot : null);
      if (!mounted || _locked || result == null) return;
      final id = result['jobId'];
      if (result['action'] == 'open' && id is String) {
        await _open(id);
        return;
      }
      if (result['action'] != 'draft' || result['draft'] is! Map) return;
      Map<String, dynamic> snapshot = {};
      if (id is String) {
        snapshot = await widget.client.job(id);
        if (!mounted || _locked) return;
        if (fpMap(snapshot['job'])['version'] != result['version'] ||
            fpMap(snapshot['job'])['state'] != 'active') {
          throw const FieldProofException(
            'This job changed during voice. Reopen it before drafting again.',
          );
        }
      }
      setState(() {
        _snapshot = snapshot;
        _editorDraft = fpClone(fpMap(result['draft']));
        _editing = true;
        _dirty = true;
        _editorGeneration++;
        _createKey = id == null ? fieldProofRequestKey() : null;
        _notice =
            'Rici prepared an unsaved draft. Review every entry, then save the job.';
      });
      _top();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      _schedule();
    }
  }

  Future<void> _repeat() async {
    if (_working || _locked || !_hasJob || !await _discard() || !mounted) {
      return;
    }
    final draft = fpRepeatDraft(_data);
    _timer?.cancel();
    setState(() {
      _snapshot = {};
      _editorDraft = draft;
      _editorGeneration++;
      _createKey = fieldProofRequestKey();
      _editing = true;
      _dirty = true;
      _notice =
          'Follow-up draft prepared. Work notes, readings, completed checks, photos and approval start fresh.';
    });
    _top();
  }

  Future<void> _batchPhotos() async {
    if (!_editable || _photos.length >= _photoLimit) return;
    _dialogOpen = true;
    _timer?.cancel();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FieldProofBatchDialog(
          remaining: _photoLimit - _photos.length,
          pick: widget.pickBatch ?? pickFieldProofBatch,
          upload: (row, photo) async {
            if (_locked || !mounted) {
              throw const FieldProofException(
                'Sign in again to continue.',
                401,
              );
            }
            final saved = await widget.client.upload(
              fpText(_job['id']),
              _job['version'] as int,
              photo,
              key: row.key,
              tag: row.tag,
              name: row.name.trim(),
              note: row.note.trim(),
            );
            if (!mounted || _locked) return;
            _accept(saved);
          },
        ),
      );
    } finally {
      _dialogOpen = false;
      if (mounted && !_locked) await _refresh();
    }
  }

  Future<void> _comparePhotos() async {
    if (_working || _locked) return;
    await _refresh();
    if (!mounted || _locked) return;
    final rows = _photos.where((p) => p['state'] == 'ready').toList();
    if (rows.length < 2) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => FieldProofCompareDialog(photos: rows),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  Widget _voiceCard() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [_ink, _teal]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.graphic_eq, color: Colors.white),
          const SizedBox(height: 10),
          const Text(
            'Rici · Your field assistant',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Talk through job notes, capture readings, find records and prepare follow-ups.',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('fp-voice'),
            onPressed: _working || _dirty ? null : _voice,
            icon: const Icon(Icons.mic_none),
            label: const Text('Talk to Rici'),
          ),
          if (_dirty)
            const Text(
              'Save your edits before opening voice.',
              style: TextStyle(color: Colors.white70),
            ),
        ],
      ),
    ),
  );

  Future<bool> _action(
    Future<Map<String, dynamic>> Function() work, {
    String? notice,
  }) async {
    if (_busy || _locked) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await work();
      if (!mounted || _locked) return false;
      _accept(r);
      if (notice != null) {
        setState(() => _notice = notice);
        _feedback(notice);
        unawaited(kKorlixSounds.play(KorlixSound.success));
      }
      return true;
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = '$e');
        _feedback('$e');
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save(Map<String, dynamic> data) async {
    final ok = await _action(
      () => _hasJob
          ? widget.client.save(fpText(_job['id']), _job['version'] as int, data)
          : widget.client.create(_createKey ??= fieldProofRequestKey(), data),
      notice: 'Job saved. Add your photos and required records.',
    );
    if (ok && mounted && !_locked) {
      setState(() {
        _editing = _dirty = false;
        _editorDraft = null;
        _tab = 0;
        _reviewKey = null;
      });
      _top();
    }
    return ok;
  }

  Future<void> _update(Map<String, dynamic> data) async {
    await _action(
      () =>
          widget.client.save(fpText(_job['id']), _job['version'] as int, data),
      notice: 'Checklist saved.',
    );
  }

  Future<void> _copy(String value) async {
    try {
      if (widget.copyText != null) {
        await widget.copyText!(value);
      } else {
        await Clipboard.setData(ClipboardData(text: value));
      }
      _feedback('Copied.');
    } catch (e) {
      _feedback('Could not copy. Try again.');
    }
  }

  Future<FieldProofPhoto?> _pick(bool camera) async {
    if (widget.pickPhoto != null) return widget.pickPhoto!(camera);
    if (camera) {
      final f = await ip.ImagePicker().pickImage(source: ip.ImageSource.camera);
      if (f == null) return null;
      if (await f.length() > 10 * 1024 * 1024) {
        throw const FieldProofException('Choose a photo under 10 MB.');
      }
      return FieldProofPhoto(f.name, await f.readAsBytes());
    }
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    if (f.size == 0 || f.size > 10 * 1024 * 1024) {
      throw const FieldProofException('Choose a photo under 10 MB.');
    }
    if (f.bytes != null) return FieldProofPhoto(f.name, f.bytes!);
    if (f.readStream == null) {
      throw const FieldProofException('Choose this photo again.');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in f.readStream!) {
      if (b.length + chunk.length > 10 * 1024 * 1024) {
        throw const FieldProofException('Choose a photo under 10 MB.');
      }
      b.add(chunk);
    }
    return FieldProofPhoto(f.name, b.takeBytes());
  }

  Future<void> _addPhoto() async {
    if (!_editable) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => _PhotoDialog(
          pick: _pick,
          save: (photo, key, tag, name, note) async {
            final r = await widget.client.upload(
              fpText(_job['id']),
              _job['version'] as int,
              photo,
              key: key,
              tag: tag,
              name: name,
              note: note,
            );
            if (mounted && !_locked) _accept(r);
          },
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    if (mounted && !_locked) await _refresh();
  }

  Future<void> _approval() async {
    if (!_editable) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => _ApprovalDialog(
          save: (name, note) async {
            final r = await widget.client.approve(
              fpText(_job['id']),
              _job['version'] as int,
              name,
              note,
            );
            if (mounted && !_locked) _accept(r);
          },
        ),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _review() async {
    if (!_editable) return;
    setState(() => _busy = true);
    try {
      if (!await widget.ensureConsent() || !mounted || _locked) return;
      _reviewKey ??= fieldProofRequestKey();
      final r = await widget.client.startReview(
        fpText(_job['id']),
        _job['version'] as int,
        _reviewKey!,
      );
      if (!mounted || _locked) return;
      if (r['state'] != 'running') _reviewKey = null;
      setState(() {
        _snapshot = {
          ..._snapshot,
          'reviews': [
            r,
            ...fpRows(_snapshot['reviews']).where((v) => v['id'] != r['id']),
          ],
        };
        _tab = 3;
        _error = null;
      });
      _schedule();
      _top();
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = '$e');
        _feedback('$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeJob() async {
    if (!_editable) return;
    if (!await _confirm(
      'Close this job?',
      'Confirm you reviewed the job, evidence and required records. This records your closeout decision; it does not certify workmanship or create an invoice.',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    await _action(
      () => widget.client.complete(fpText(_job['id']), _job['version'] as int),
      notice: 'Job closed. Your report is ready to export.',
    );
  }

  Future<void> _reopen() async {
    if (!await _confirm(
      'Reopen this job?',
      'Edits create a new revision. Existing customer approval and AI review will apply to the earlier revision.',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    await _action(
      () => widget.client.reopen(fpText(_job['id']), _job['version'] as int),
    );
  }

  Future<void> _removeJob() async {
    if (!await _confirm(
      'Delete this job and its photos?',
      'This permanently removes this job, original photos, reviews and activity from FieldProof.',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    setState(() => _busy = true);
    try {
      await widget.client.remove(fpText(_job['id']), _job['version'] as int);
      if (!mounted || _locked) return;
      setState(() {
        _snapshot = {};
        _notice = 'Job and photos removed.';
      });
      await _load();
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = '$e');
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(Map<String, dynamic> p) async {
    if (!await _confirm(
      'Remove this photo?',
      'This removes the original and preview and creates a new job revision.',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    await _action(() => widget.client.removePhoto(fpText(p['id'])));
  }

  Future<void> _export({Map<String, dynamic>? photo}) async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      Uint8List bytes;
      String name, mime;
      if (photo != null) {
        bytes = await widget.client.photoBytes(fpText(photo['id']));
        mime = fpText(photo['mime']);
        name =
            'KORLIX-FieldProof-${photo['id']}.${mime == 'image/jpeg' ? 'jpg' : mime.split('/').last}';
      } else {
        final r = await widget.client.job(fpText(_job['id']));
        final previews = <String, Uint8List>{};
        for (final p in fpRows(
          r['evidence'],
        ).where((p) => p['state'] == 'ready')) {
          previews[fpText(p['id'])] = await widget.client.photoBytes(
            fpText(p['id']),
            preview: true,
          );
        }
        if (!mounted || _locked) return;
        bytes = await (widget.renderPdf ?? buildFieldProofPdf)(r, previews);
        name =
            'KORLIX-FieldProof-${fpMap(r['job'])['id']}-r${fpMap(r['job'])['version']}.pdf';
        mime = 'application/pdf';
      }
      if (!mounted || _locked) return;
      await (widget.saveFile ?? saveFieldProofFile)(bytes, name, mime);
      _feedback('Export ready. Check your downloads or share options.');
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = '$e');
        _feedback('$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(Widget child) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _line),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
  Widget _heading(String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(text, style: const TextStyle(color: _muted, height: 1.5)),
      ],
    ),
  );
  Widget _pair(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 3),
        SelectableText(
          fpText(value).isEmpty ? 'Not entered' : fpText(value),
          style: const TextStyle(color: _ink, height: 1.4),
        ),
      ],
    ),
  );
  Widget _pill(String label, {Color color = _teal}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
  Widget _overview() {
    final shown = _jobs
        .where(
          (j) =>
              (_filter == 'all' ||
                  j['state'] == _filter ||
                  (_filter == 'attention' && fpNeedsAttention(j)) ||
                  (_filter == 'overdue' && fpOverdue(j))) &&
              fpText(j['data']).toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    shown.sort((a, b) {
      final ad = fpMap(a['data']), bd = fpMap(b['data']);
      if (_sort == 'due') {
        final x = fpText(ad['dueOn']), y = fpText(bd['dueOn']);
        return (x.isEmpty ? '9999-12-31' : x).compareTo(
          y.isEmpty ? '9999-12-31' : y,
        );
      }
      if (_sort == 'priority') {
        final order = fpPriorities.keys.toList();
        return order
            .indexOf(fpText(bd['priority']))
            .compareTo(order.indexOf(fpText(ad['priority'])));
      }
      return fpText(b['updatedAt']).compareTo(fpText(a['updatedAt']));
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Leave the site with the right records.',
          'Organize job photos, catch missing evidence and prepare a clear customer handoff.',
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _pill(
                    '${_jobs.where((j) => j['state'] == 'active').length} active jobs',
                  ),
                  _pill(
                    '${_jobs.where((j) => j['state'] == 'completed').length} closed jobs',
                  ),
                  _pill('Original photos preserved'),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('fp-new'),
                onPressed: _busy ? null : _new,
                icon: const Icon(Icons.add),
                label: const Text('New field job'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('fp-email-open'),
                onPressed: korlixSoundAction(_working ? null : () => _openEmail()),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7048B8), foregroundColor: Colors.white),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Autonomous Email'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose from 14 templates covering trades, inspections, service, deliveries and general field work. Private job records and manual reports are available when signed in.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('fp-search'),
          onChanged: (s) => setState(() => _search = s),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Find a job, customer or site',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final item in [
              ('all', 'All jobs'),
              ('active', 'Active'),
              ('completed', 'Closed'),
              ('attention', 'Needs attention'),
              ('overdue', 'Overdue'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: _filter == item.$1,
                onSelected: (_) => setState(() => _filter = item.$1),
              ),
          ],
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: const Key('fp-sort'),
          initialValue: _sort,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sort jobs'),
          items: const [
            DropdownMenuItem(value: 'recent', child: Text('Recently updated')),
            DropdownMenuItem(value: 'due', child: Text('Due date')),
            DropdownMenuItem(value: 'priority', child: Text('Priority')),
          ],
          onChanged: (v) => setState(() => _sort = v ?? 'recent'),
        ),
        const SizedBox(height: 18),
        if (shown.isEmpty)
          _card(
            const Text(
              'Your job records will appear here. Start with New field job.',
            ),
          ),
        for (final j in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(
                        j['state'] == 'completed'
                            ? 'Closed'
                            : j['state'] == 'deleting'
                            ? 'Removal incomplete'
                            : 'Active',
                      ),
                      _pill(fpStages[fpMap(j['data'])['stage']] ?? 'Planned'),
                      _pill(
                        fpPriorities[fpMap(j['data'])['priority']] ?? 'Normal',
                      ),
                      if (fpText(fpMap(j['data'])['dueOn']).isNotEmpty)
                        _pill(
                          'Due ${fpMap(j['data'])['dueOn']}',
                          color: fpOverdue(j) ? Colors.deepOrange : _teal,
                        ),
                      if (j['runningReview'] != null)
                        _pill('KORLIX is reviewing'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fpText(fpMap(j['data'])['title']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${fpMap(j['data'])['customer']} · ${fpMap(j['data'])['site']}',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${j['photoCount'] ?? 0} photos · Revision ${j['version']}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _open(fpText(j['id'])),
                        child: const Text('Open job'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _details() {
    final approval = fpMap(_job['approval']);
    return Column(
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'Job details',
                'Technician-entered information. Keep these records accurate before closeout.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('fp-edit'),
                    onPressed: _editable
                        ? () => setState(() {
                            _editing = true;
                            _dirty = false;
                          })
                        : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit job'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('fp-email-job'),
                    onPressed: korlixSoundAction(_working ? null : () => _openEmail(forJob: true)),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Customer email'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('fp-repeat'),
                    onPressed: _working ? null : _repeat,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Create follow-up job'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final e in {
                'priority': 'Priority',
                'stage': 'Work stage',
                'dueOn': 'Due date',
                'workOrder': 'Work order',
                'customer': 'Customer / company',
                'site': 'Site / location',
                'technician': 'Technician',
                'performedOn': 'Work date (entered)',
                'assetId': 'Asset / new serial (entered)',
                'oldAssetId': 'Previous serial (entered)',
                'summary': 'Work completed (reported)',
                'exceptions': 'Outstanding items',
                'hours': 'Work hours (entered)',
                'materials': 'Materials / quantities (entered)',
                'billingNotes': 'Invoice handoff notes',
              }.entries)
                _pair(e.value, _data[e.key]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'Customer approval',
                'A technician-recorded declaration. This does not capture or independently verify a customer signature.',
              ),
              Text(
                _data['requiresApproval'] == true
                    ? 'Required before closeout.'
                    : 'Optional for this job.',
              ),
              const SizedBox(height: 12),
              if (approval.isNotEmpty) ...[
                _pair('Reported approver', approval['name']),
                _pair('Recorded by', approval['recordedBy']),
                _pair('Recorded at', fpDate(approval['recordedAt'])),
                _pair('Note', approval['note']),
                _pill(
                  approval['version'] == _job['version']
                      ? 'Current revision'
                      : 'Earlier revision — record approval again',
                  color: approval['version'] == _job['version']
                      ? _teal
                      : Colors.deepOrange,
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('fp-approval'),
                onPressed: _editable ? _approval : null,
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Record customer approval'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _evidence() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Photo evidence',
        'Upload originals or use your camera. KORLIX retains the received file unchanged and creates a smaller preview.',
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              key: const Key('fp-add-photo'),
              onPressed: _editable && _photos.length < _photoLimit
                  ? _addPhoto
                  : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('fp-batch'),
                  onPressed: _editable && _photos.length < _photoLimit
                      ? _batchPhotos
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Add several photos'),
                ),
                OutlinedButton.icon(
                  key: const Key('fp-compare'),
                  onPressed:
                      !_working &&
                          _photos.where((p) => p['state'] == 'ready').length >=
                              2
                      ? _comparePhotos
                      : null,
                  icon: const Icon(Icons.compare_outlined),
                  label: const Text('Compare before & after'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_photos.length} / $_photoLimit photos · JPG, PNG or WEBP · 10 MB each',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload only evidence you are allowed to store. Files can contain identifying details or embedded metadata. Upload time is recorded; capture time and location are not independently verified.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      for (final p in _photos)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fpText(p['name']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _pill(fpTagNames[p['tag']] ?? fpText(p['tag'])),
                const SizedBox(height: 12),
                if (p['state'] == 'ready' && p['previewUrl'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      fpText(p['previewUrl']),
                      height: 230,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 100,
                        child: Center(
                          child: Text(
                            'Preview unavailable. Refresh to reload.',
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Incomplete upload or removal. Retry removal after three minutes if this remains unfinished.',
                  ),
                const SizedBox(height: 12),
                if (fpText(p['note']).isNotEmpty)
                  _pair('Photo note', p['note']),
                _pair('Upload time', fpDate(p['uploadedAt'])),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Original file details'),
                  children: [
                    _pair('Photo ID', p['id']),
                    _pair(
                      'File',
                      '${p['mime']} · ${p['bytes']} bytes · ${p['width']} × ${p['height']}',
                    ),
                    _pair('SHA-256', p['sha256']),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || p['state'] != 'ready'
                          ? null
                          : () => _export(photo: p),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download original'),
                    ),
                    TextButton(
                      onPressed: _editable ? () => _removePhoto(p) : null,
                      child: const Text('Remove photo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Future<void> _customCheck() async {
    if (!_editable) return;
    _dialogOpen = true;
    try {
      final label = await showDialog<String>(
        context: context,
        builder: (c) => const _CustomCheckDialog(),
      );
      if (label != null && mounted && !_locked) {
        await _update({
          ..._data,
          'checks': [
            ...fpRows(_data['checks']),
            {
              'id': 'custom-${fieldProofRequestKey()}',
              'label': label,
              'required': true,
              'done': false,
            },
          ],
        });
      }
    } finally {
      _dialogOpen = false;
    }
  }

  Widget _checklist() {
    final check = fpMap(_snapshot['readiness']),
        core =
            fpMap(_templates[_data['template']])['requiredTags'] as List? ?? [];
    return Column(
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading('Required records', fpText(check['limits'])),
              _pill(
                fpText(check['label']),
                color: check['ready'] == true ? _teal : Colors.deepOrange,
              ),
              const SizedBox(height: 14),
              for (final s in check['missing'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '• $s',
                    style: const TextStyle(color: Color(0xFF984600)),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'Required photo categories',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in fpTagNames.entries)
                    FilterChip(
                      label: Text(e.value),
                      selected: (_data['requiredTags'] as List? ?? []).contains(
                        e.key,
                      ),
                      onSelected: !_editable || core.contains(e.key)
                          ? null
                          : (on) {
                              final tags = List<String>.from(
                                _data['requiredTags'] as List,
                              );
                              on ? tags.add(e.key) : tags.remove(e.key);
                              unawaited(
                                _update({..._data, 'requiredTags': tags}),
                              );
                            },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Technician checklist',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final c in fpRows(_data['checks']))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(fpText(c['label'])),
                  secondary: fpText(c['id']).startsWith('custom-')
                      ? IconButton(
                          tooltip: 'Remove custom requirement',
                          icon: const Icon(Icons.close),
                          onPressed: !_editable
                              ? null
                              : () async {
                                  if (await _confirm(
                                        'Remove this requirement?',
                                        fpText(c['label']),
                                      ) &&
                                      mounted &&
                                      !_locked) {
                                    await _update({
                                      ..._data,
                                      'checks': fpRows(_data['checks'])
                                          .where((x) => x['id'] != c['id'])
                                          .toList(),
                                    });
                                  }
                                },
                        )
                      : null,
                  subtitle: Text(
                    c['required'] == true ? 'Required' : 'Optional',
                  ),
                  value: c['done'] == true,
                  onChanged: !_editable
                      ? null
                      : (v) => _update({
                          ..._data,
                          'checks': fpRows(_data['checks'])
                              .map(
                                (x) => x['id'] == c['id']
                                    ? {...x, 'done': v == true}
                                    : x,
                              )
                              .toList(),
                        }),
                ),
              TextButton.icon(
                onPressed: _editable && fpRows(_data['checks']).length < 32
                    ? _customCheck
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add required checklist item'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('fp-close'),
                onPressed: _editable && check['ready'] == true
                    ? _closeJob
                    : null,
                icon: const Icon(Icons.task_alt),
                label: const Text('Review & close job'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Closeout records your decision. KORLIX does not automatically approve jobs.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _report() {
    final current = fpCurrentReview(_snapshot),
        reviews = fpRows(_snapshot['reviews']),
        old = reviews.where((r) => r['state'] == 'completed').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'Your handoff, ready to review.',
                'Export the job record, evidence manifest, photo previews and current KORLIX draft when available.',
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('fp-export'),
                    onPressed: _busy ? null : () => _export(),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Export PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _copy(fpReportText(_snapshot)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy report'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _copy(fpInvoiceText(_snapshot)),
                    child: const Text('Copy invoice handoff'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _job['state'] == 'completed'
                    ? 'Technician-closed job · revision ${_job['version']}'
                    : 'Working draft · close the job after required records are complete.',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Invoice handoff is a scope, hours and materials draft. Verify rates and billing eligibility before invoicing.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'KORLIX photo review',
                'Check image clarity, conflicting details and missing documentation. Review every finding before using it.',
              ),
              FilledButton.icon(
                key: const Key('fp-review'),
                onPressed:
                    _editable &&
                        _photos.any((p) => p['state'] == 'ready') &&
                        !_photos.any((p) => p['state'] != 'ready')
                    ? _review
                    : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Review with KORLIX'),
              ),
              const SizedBox(height: 10),
              const Text(
                '1 credit per completed review · Ultra Premium / Enterprise. Job details and photo previews are shared with OpenAI after your consent. Failed reviews use no credit.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
              if (current == null && old != null) ...[
                const SizedBox(height: 14),
                const Text(
                  'Your previous review applies to an earlier job revision. Review again to include a current draft in the PDF.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ],
              if (current != null) ...[
                const Divider(height: 28),
                SelectableText(fpText(fpMap(current['result'])['summary'])),
                for (final o in fpRows(
                  fpMap(current['result'])['observations'],
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fpText(o['detail'])),
                        Text(
                          'Photo IDs: ${(o['photoIds'] as List? ?? []).join(', ')}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                for (final f
                    in fpMap(current['result'])['followUps'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $f'),
                  ),
                for (final item in [
                  ('customerReport', 'Customer report draft'),
                  ('invoiceHandoff', 'Invoice handoff draft'),
                ])
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(item.$2),
                    children: [
                      SelectableText(fpText(fpMap(current['result'])[item.$1])),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copy(fpText(fpMap(current['result'])[item.$1])),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy draft'),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  fpText(fpMap(current['result'])['limits']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Review history'),
                  children: [
                    for (final r in reviews)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Revision ${r['version']} · ${r['state']}'),
                        subtitle: Text(
                          '${fpDate(r['createdAt'])}${r['error'] == null ? '' : '\n${r['error']}'}',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              for (final e in fpRows(_snapshot['events']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(fpText(e['action']).replaceAll('_', ' ')),
                  subtitle: Text(
                    '${fpDate(e['created_at'])} · revision ${e['version']}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _teal,
      ).copyWith(surface: Colors.white, onSurface: _ink),
      scaffoldBackgroundColor: const Color(0xFFF4F7F9),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFCFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
    );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _discard() || !mounted) return;
        setState(() => _dirty = false);
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Theme(
        data: theme,
        child: LayoutBuilder(
          builder: (context, box) => Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: const Text(
                'KORLIX FieldProof',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh FieldProof',
                  onPressed: _busy || _locked || _dirty
                      ? null
                      : () => _refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: _locked
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Your session changed. Close this screen, sign in and reopen FieldProof.',
                      ),
                    ),
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (box.maxWidth >= 1100)
                        Container(
                          width: 210,
                          color: _ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Image.asset(
                                  'assets/meeting_copilot/korlix_logo.jpeg',
                                  width: 72,
                                  height: 72,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'FIELDPROOF',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 19,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Clear records.\nConfident handoffs.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 30),
                              TextButton.icon(
                                onPressed: _busy ? null : _back,
                                icon: const Icon(
                                  Icons.work_outline,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'All jobs',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _busy ? null : _new,
                                icon: const Icon(Icons.add),
                                label: const Text('New job'),
                              ),
                              const Spacer(),
                              const Text(
                                'Private to your account.\nReview evidence before closeout.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.all(
                            box.maxWidth >= 1100 ? 30 : 16,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1150),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_busy)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 14),
                                      child: LinearProgressIndicator(),
                                    ),
                                  if (_hasJob || _editing)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: TextButton.icon(
                                        key: const Key('fp-back'),
                                        onPressed: _busy ? null : _back,
                                        icon: const Icon(Icons.arrow_back),
                                        label: const Text('All jobs'),
                                      ),
                                    ),
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _card(
                                        Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: Color(0xFFAD2C26),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_notice != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _card(
                                        Text(
                                          _notice!,
                                          style: const TextStyle(color: _teal),
                                        ),
                                      ),
                                    ),
                                  if (_running)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _card(
                                        const Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'KORLIX is reviewing your job evidence.',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 10),
                                            LinearProgressIndicator(),
                                            SizedBox(height: 10),
                                            Text(
                                              'You can leave this screen and reopen the job to follow progress. Editing is paused during review.',
                                              style: TextStyle(color: _muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (widget.openVoice != null) _voiceCard(),
                                  if (_editing)
                                    _card(
                                      _JobEditor(
                                        key: ValueKey(
                                          'editor-${_job['id'] ?? 'new'}-$_editorGeneration',
                                        ),
                                        initial: _editorDraft ?? _data,
                                        onDialogChanged: (open) =>
                                            _dialogOpen = open,
                                        templates: _templates,
                                        onDirty: () =>
                                            setState(() => _dirty = true),
                                        save: (d) async => (await _save(d))
                                            ? null
                                            : _error ??
                                                  'The save could not be confirmed.',
                                      ),
                                    )
                                  else if (!_hasJob)
                                    _overview()
                                  else ...[
                                    _heading(
                                      fpText(_data['title']),
                                      '${_data['customer']} · ${_data['site']}',
                                    ),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        _pill(
                                          _job['state'] == 'completed'
                                              ? 'Technician-closed'
                                              : 'Active job',
                                        ),
                                        _pill('Revision ${_job['version']}'),
                                        _pill(
                                          '${_photos.where((p) => p['state'] == 'ready').length} photos',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    if (_job['state'] == 'deleting')
                                      _card(
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Job removal did not finish. Retry to remove the remaining photos and records.',
                                            ),
                                            TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : _removeJob,
                                              child: const Text(
                                                'Retry job removal',
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else ...[
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          for (final t in [
                                            (0, 'Job details'),
                                            (1, 'Photos'),
                                            (2, 'Checklist'),
                                            (3, 'Report'),
                                            (4, 'Readings & punch list'),
                                          ])
                                            ChoiceChip(
                                              key: Key('fp-tab-${t.$1}'),
                                              label: Text(t.$2),
                                              selected: _tab == t.$1,
                                              onSelected: (_) =>
                                                  setState(() => _tab = t.$1),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      switch (_tab) {
                                        0 => _details(),
                                        1 => _evidence(),
                                        2 => _checklist(),
                                        4 => _card(
                                          FieldProofRecordsEditor(
                                            readings: fpRows(_data['readings']),
                                            issues: fpRows(_data['issues']),
                                            enabled: _editable,
                                            onDialogChanged: (open) =>
                                                _dialogOpen = open,
                                            onChanged:
                                                (readings, issues) async {
                                                  await _action(
                                                    () => widget.client.save(
                                                      fpText(_job['id']),
                                                      _job['version'] as int,
                                                      {
                                                        ..._data,
                                                        'readings': readings,
                                                        'issues': issues,
                                                      },
                                                    ),
                                                    notice:
                                                        'Job records saved.',
                                                  );
                                                },
                                          ),
                                        ),
                                        _ => _report(),
                                      },
                                      const SizedBox(height: 22),
                                      Wrap(
                                        spacing: 12,
                                        children: [
                                          if (_job['state'] == 'completed')
                                            OutlinedButton(
                                              onPressed: _busy ? null : _reopen,
                                              child: const Text('Reopen job'),
                                            ),
                                          TextButton(
                                            onPressed: _working
                                                ? null
                                                : _removeJob,
                                            child: const Text(
                                              'Delete job and photos',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                  const SizedBox(height: 26),
                                  const Text(
                                    'FieldProof organizes supplied records. It does not independently verify capture time, location, work quality, safety or customer identity.',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

const _fields = {
  'title': 'Job title',
  'customer': 'Customer / company',
  'site': 'Site / location',
  'workOrder': 'Work order / reference',
  'technician': 'Technician name',
  'performedOn': 'Work date (YYYY-MM-DD)',
  'dueOn': 'Due date (YYYY-MM-DD)',
  'assetId': 'Asset / new serial number',
  'oldAssetId': 'Previous serial (if relevant)',
  'summary': 'Describe the completed work',
  'exceptions': 'Outstanding items / follow-up',
  'hours': 'Work hours',
  'materials': 'Materials / quantities',
  'billingNotes': 'Invoice handoff notes',
};

class _JobEditor extends StatefulWidget {
  const _JobEditor({
    super.key,
    required this.initial,
    required this.templates,
    required this.onDirty,
    required this.save,
    this.onDialogChanged,
  });
  final ValueChanged<bool>? onDialogChanged;
  final Map<String, dynamic> initial, templates;
  final VoidCallback onDirty;
  final Future<String?> Function(Map<String, dynamic>) save;
  @override
  State<_JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends State<_JobEditor> {
  late final Map<String, TextEditingController> _c;
  late String _template;
  late String _priority, _stage;
  late List<Map<String, dynamic>> _readings, _issues;
  late bool _approval;
  final _anchors = {
        for (final k in ['title', 'customer', 'site']) k: GlobalKey(),
      },
      _focus = {
        for (final k in ['title', 'customer', 'site']) k: FocusNode(),
      };
  final _errorAnchor = GlobalKey();
  bool _saving = false, _attempted = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _c = {
      for (final k in _fields.keys)
        k: TextEditingController(text: fpText(widget.initial[k])),
    };
    _priority = fpText(widget.initial['priority']);
    if (!fpPriorities.containsKey(_priority)) _priority = 'normal';
    _stage = fpText(widget.initial['stage']);
    if (!fpStages.containsKey(_stage)) _stage = 'planned';
    _readings = fpRows(widget.initial['readings']);
    _issues = fpRows(widget.initial['issues']);
    _template = fpText(widget.initial['template']);
    if (!widget.templates.containsKey(_template)) _template = 'utility';
    _approval =
        widget.initial['requiresApproval'] as bool? ??
        fpMap(widget.templates[_template])['requiresApproval'] == true;
    if (_c['performedOn']!.text.isEmpty) {
      _c['performedOn']!.text = DateTime.now().toString().substring(0, 10);
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final missing = [
      'title',
      'customer',
      'site',
    ].where((k) => _c[k]!.text.trim().isEmpty).firstOrNull;
    if (missing != null) {
      setState(() => _attempted = true);
      _focus[missing]!.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final c = _anchors[missing]!.currentContext;
      if (c != null && c.mounted) {
        await Scrollable.ensureVisible(
          c,
          alignment: .15,
          duration: const Duration(milliseconds: 200),
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final same = _template == widget.initial['template'],
        defaults = fpMap(widget.templates[_template]);
    final data = <String, dynamic>{
      ...widget.initial,
      ...{for (final e in _c.entries) e.key: e.value.text.trim()},
      'priority': _priority,
      'stage': _stage,
      'readings': _readings,
      'issues': _issues,
      'template': _template,
      'requiresApproval': _approval,
      'checks': same ? widget.initial['checks'] : defaults['checks'],
      'requiredTags': same
          ? widget.initial['requiredTags']
          : defaults['requiredTags'],
    };
    try {
      final error = await widget.save(data);
      if (!mounted) return;
      setState(() => _error = error);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || _error == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final c = _errorAnchor.currentContext;
    if (c != null && c.mounted) {
      final scroll = Scrollable.maybeOf(c)?.position;
      if (scroll != null) scroll.jumpTo(scroll.pixels);
      await Scrollable.ensureVisible(
        c,
        alignment: .2,
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.initial.isEmpty ? 'Start a field job' : 'Edit job details',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'Job title, customer and site are required to start. Complete the remaining records before closeout.',
        style: TextStyle(color: _muted, height: 1.5),
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        key: const Key('fp-template'),
        initialValue: _template,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Job template'),
        items: widget.templates.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  fpText(fpMap(e.value)['name']),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _saving
            ? null
            : (v) {
                if (v == null) return;
                setState(() {
                  _template = v;
                  _approval =
                      fpMap(widget.templates[v])['requiresApproval'] == true;
                });
                widget.onDirty();
              },
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: const Key('fp-priority'),
        initialValue: _priority,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Priority'),
        items: fpPriorities.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: _saving
            ? null
            : (v) {
                setState(() => _priority = v ?? 'normal');
                widget.onDirty();
              },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('fp-stage'),
        initialValue: _stage,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Work stage'),
        items: fpStages.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: _saving
            ? null
            : (v) {
                setState(() => _stage = v ?? 'planned');
                widget.onDirty();
              },
      ),
      const SizedBox(height: 16),
      for (final e in _fields.entries)
        Padding(
          key: _anchors[e.key],
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
            key: Key('fp-field-${e.key}'),
            controller: _c[e.key],
            focusNode: _focus[e.key],
            enabled: !_saving,
            minLines:
                [
                  'summary',
                  'exceptions',
                  'materials',
                  'billingNotes',
                ].contains(e.key)
                ? 3
                : 1,
            maxLines:
                [
                  'summary',
                  'exceptions',
                  'materials',
                  'billingNotes',
                ].contains(e.key)
                ? 8
                : 2,
            maxLength: switch (e.key) {
              'title' || 'technician' || 'assetId' || 'oldAssetId' => 120,
              'customer' => 160,
              'site' => 350,
              'workOrder' => 100,
              'performedOn' || 'dueOn' => 10,
              'hours' => 8,
              'summary' => 4000,
              _ => 2000,
            },
            keyboardType: e.key == 'hours'
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.multiline,
            onChanged: (_) => widget.onDirty(),
            decoration: InputDecoration(
              labelText:
                  '${e.value}${['title', 'customer', 'site'].contains(e.key) ? ' *' : ''}',
              errorText:
                  _attempted &&
                      ['title', 'customer', 'site'].contains(e.key) &&
                      _c[e.key]!.text.trim().isEmpty
                  ? 'Enter ${e.value.toLowerCase()}.'
                  : null,
              errorMaxLines: 3,
            ),
          ),
        ),
      FieldProofRecordsEditor(
        readings: _readings,
        issues: _issues,
        enabled: !_saving,
        onDialogChanged: widget.onDialogChanged,
        onChanged: (readings, issues) async {
          setState(() {
            _readings = readings;
            _issues = issues;
          });
          widget.onDirty();
        },
      ),
      const SizedBox(height: 18),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Require recorded customer approval before closeout'),
        value: _approval,
        onChanged: _saving
            ? null
            : (v) {
                setState(() => _approval = v == true);
                widget.onDirty();
              },
      ),
      const SizedBox(height: 12),
      const Text(
        'Templates are starter checklists. Add the requirements your company or customer actually needs. Changing job details creates a new revision.',
        style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
      ),
      if (_error != null)
        Padding(
          key: _errorAnchor,
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            _error!,
            key: const Key('fp-save-error'),
            style: const TextStyle(color: Color(0xFFAD2C26)),
          ),
        ),
      const SizedBox(height: 18),
      FilledButton.icon(
        key: const Key('fp-save-job'),
        onPressed: _saving ? null : _submit,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(_saving ? 'Saving job…' : 'Save job'),
      ),
    ],
  );
}

class _PhotoDialog extends StatefulWidget {
  const _PhotoDialog({required this.pick, required this.save});
  final Future<FieldProofPhoto?> Function(bool) pick;
  final Future<void> Function(FieldProofPhoto, String, String, String, String)
  save;
  @override
  State<_PhotoDialog> createState() => _PhotoDialogState();
}

class _PhotoDialogState extends State<_PhotoDialog> {
  final _name = TextEditingController(), _note = TextEditingController();
  FieldProofPhoto? _photo;
  String _key = fieldProofRequestKey(), _tag = 'after';
  String? _error;
  bool _busy = false, _attempted = false;
  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final photo = await widget.pick(camera);
      if (!mounted || photo == null) return;
      if (photo.bytes.isEmpty || photo.bytes.length > 10 * 1024 * 1024) {
        throw const FieldProofException('Choose one photo under 10 MB.');
      }
      setState(() {
        _photo = photo;
        _key = fieldProofRequestKey();
        _attempted = false;
        _error = null;
        final name = photo.name.split('/').last;
        _name.text = name.length > 100 ? name.substring(0, 100) : name;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _photo == null) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give this photo a label.');
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.save(
        _photo!,
        _key,
        _tag,
        _name.text.trim(),
        _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Add job evidence'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('fp-pick-file'),
                    onPressed: _busy ? null : () => _pick(false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('fp-camera'),
                    onPressed: _busy ? null : () => _pick(true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                ],
              ),
              if (_photo != null) ...[
                const SizedBox(height: 14),
                Image.memory(
                  _photo!.bytes,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text(
                    'Preview unavailable. The server will validate this file.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(_photo!.bytes.length / 1024).ceil()} KB · Original file will be retained',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tag,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Photo category'),
                items: fpTagNames.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy || _attempted
                    ? null
                    : (v) => setState(() => _tag = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('fp-photo-name'),
                controller: _name,
                enabled: !_busy && !_attempted,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Photo label *'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('fp-photo-note'),
                controller: _note,
                enabled: !_busy && !_attempted,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'What does this photo document?',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('fp-photo-error'),
                  style: const TextStyle(color: Color(0xFFAD2C26)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your selected photo is kept for retry. An interrupted upload can also be removed from the job after three minutes.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('fp-upload'),
          onPressed: _busy || _photo == null ? null : _save,
          child: Text(_busy ? 'Saving photo…' : 'Save photo'),
        ),
      ],
    ),
  );
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.save});
  final Future<void> Function(String, String) save;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  final _name = TextEditingController(), _note = TextEditingController();
  bool _ack = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_ack) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer approver name.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.save(_name.text.trim(), _note.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Record customer approval'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Record approval you actually received for the current work. This is your declaration, not a customer-authenticated signature.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('fp-approver'),
                controller: _name,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Customer approver name *',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !_busy,
                maxLength: 1500,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'How was approval received? Any limits?',
                ),
              ),
              CheckboxListTile(
                key: const Key('fp-approval-ack'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ack,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _ack = v == true),
                title: const Text(
                  'I received this person’s approval and am authorized to record it for this job revision.',
                ),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFAD2C26))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('fp-save-approval'),
          onPressed: _busy || !_ack ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Record approval'),
        ),
      ],
    ),
  );
}

class _CustomCheckDialog extends StatefulWidget {
  const _CustomCheckDialog();
  @override
  State<_CustomCheckDialog> createState() => _CustomCheckDialogState();
}

class _CustomCheckDialogState extends State<_CustomCheckDialog> {
  final _label = TextEditingController();
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a required record'),
    content: TextField(
      controller: _label,
      maxLength: 180,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'What must be documented?'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _label.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _label.text.trim()),
        child: const Text('Add item'),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'music_client.dart';
import 'music_models.dart';
import 'music_player.dart';
import 'music_voice.dart';

class MusicStudioScreen extends StatefulWidget {
  const MusicStudioScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.onReport,
    this.openVoice,
    this.player,
    this.saveFile,
    this.pollInterval = const Duration(seconds: 20),
  });
  final MusicClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)?
  onReport;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> workingDraft)?
  openVoice;
  final MusicPlayback? player;
  final Future<void> Function(Uint8List, String, String, Rect)? saveFile;
  final Duration pollInterval;
  @override
  State<MusicStudioScreen> createState() => _MusicStudioScreenState();
}

class _MusicStudioScreenState extends State<MusicStudioScreen> {
  final _idea = TextEditingController(),
      _title = TextEditingController(),
      _style = TextEditingController(),
      _lyrics = TextEditingController(),
      _search = TextEditingController();
  late final MusicPlayback _player;
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _jobs = [];
  Map<String, dynamic> _addon = {};
  Map<String, dynamic>? _pendingGenerate, _pendingDraft;
  String _mode = 'idea', _voice = 'auto';
  int? _length;
  int _tab = 0, _version = 0, _epoch = 0, _listSequence = 0, _editRevision = 0;
  bool _loading = true,
      _busy = false,
      _locked = false,
      _dirty = false,
      _dialogOpen = false,
      _polling = false,
      _hasMore = false,
      _favorites = false,
      _listing = false,
      _voiceOpen = false,
      _voicePrepared = false;
  String? _error, _nextBefore, _notice;
  Timer? _timer, _searchTimer;
  bool get _editable => !_busy && !_locked && !_voiceOpen && _pendingGenerate == null;
  ColorScheme get _colors => Theme.of(context).colorScheme;
  Map<String, dynamic> get _data => {
    'mode': _mode,
    'idea': _idea.text,
    'title': _title.text,
    'style': _style.text,
    'lyrics': _lyrics.text,
    'voice': _voice,
    'duration': _length,
  };
  bool _alive(int epoch) {
    if (!mounted || _locked || epoch != _epoch) return false;
    if (widget.client.sessionChanged) {
      _lock();
      return false;
    }
    return true;
  }
  @override
  void initState() {
    super.initState();
    _player = widget.player ?? DeviceMusicPlayback();
    _player.addListener(_playbackChanged);
    widget.client.onAccessDenied = _lock;
    unawaited(_boot());
    _timer = Timer.periodic(widget.pollInterval, (_) => unawaited(_poll()));
  }

  @override
  void dispose() {
    _epoch++;
    _scroll.dispose();
    _timer?.cancel();
    _searchTimer?.cancel();
    widget.client.onAccessDenied = null;
    widget.client.dispose();
    _player.removeListener(_playbackChanged);
    unawaited(_player.stop());
    if (widget.player == null) _player.dispose();
    for (final c in [_idea, _title, _style, _lyrics, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  void _playbackChanged() {
    if (mounted && !_locked) setState(() {});
  }

  void _lock() {
    if (!mounted || _locked) return;
    _epoch++;
    _timer?.cancel();
    _searchTimer?.cancel();
    if (_dialogOpen) Navigator.of(context).pop();
    unawaited(_player.stop());
    setState(() {
      _locked = true;
      _jobs = [];
      _addon = {};
      _pendingGenerate = _pendingDraft = null;
      _busy = false;
      _dirty = false;
      _voicePrepared = false;
      _error = _notice = null;
      for (final c in [_idea, _title, _style, _lyrics, _search]) {
        c.clear();
      }
    });
  }

  void _hydrate(Map<String, dynamic> d) {
    _editRevision++;
    final v = {...blankMusic(), ...d};
    _mode = v['mode'];
    _voice = v['voice'];
    _length = v['duration'];
    _idea.text = v['idea'];
    _title.text = v['title'];
    _style.text = v['style'];
    _lyrics.text = v['lyrics'];
    _dirty = false;
    _pendingDraft = null;
    _voicePrepared = false;
  }

  void _edit([VoidCallback? fn]) {
    if (!_editable) return;
    setState(() {
      fn?.call();
      _editRevision++;
      _dirty = true;
      _pendingDraft = null;
      _error = null;
      _notice = null;
    });
  }

  Future<T?> _dialog<T>(Widget Function(BuildContext) builder) async {
    if (_locked) return null;
    _dialogOpen = true;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: builder,
      );
    } finally {
      _dialogOpen = false;
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await _dialog<bool>(
        (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> _leave() async {
    if (_busy) return false;
    if (!_dirty || _locked) return true;
    final answer = await _dialog<String>(
      (c) => AlertDialog(
        title: const Text('Keep your music idea?'),
        content: const Text('Save this draft so it is ready when you return.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('Discard edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    if (answer == 'discard') {
      if (mounted) setState(() => _dirty = false);
      return true;
    }
    if (answer == 'save') {
      await _saveDraft();
      return !_dirty && !_locked;
    }
    return false;
  }

  Future<void> _back() async {
    if (await _leave() && mounted) Navigator.of(context).pop();
  }

  Future<void> _boot() async {
    final epoch = _epoch;
    try {
      final r = await widget.client.load();
      if (!_alive(epoch)) return;
      setState(() {
        _addon = musicMap(r['addon']);
        _jobs = musicRows(r['jobs']);
        _hasMore = r['hasMore'] == true;
        _nextBefore = r['nextBefore'];
        if (!_dirty) {
          _version = musicMap(r['draft'])['version'];
          _hydrate(musicMap(musicMap(r['draft'])['data']));
        }
        _loading = false;
        _error = null;
      });
      unawaited(_poll());
    } catch (e) {
      if (_alive(epoch)) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _library({bool more = false}) async {
    if (_locked) return;
    final epoch = _epoch, seq = ++_listSequence;
    setState(() => _listing = true);
    try {
      final r = await widget.client.jobs(
        query: _search.text.trim(),
        favorites: _favorites,
        before: more ? _nextBefore : null,
      );
      if (!_alive(epoch) || seq != _listSequence) return;
      setState(() {
        final found = musicRows(r['jobs']);
        _jobs = more
            ? [
                ..._jobs,
                ...found.where(
                  (j) => !_jobs.any((old) => old['id'] == j['id']),
                ),
              ]
            : found;
        _hasMore = r['hasMore'] == true;
        _nextBefore = r['nextBefore'];
        _error = null;
      });
    } catch (e) {
      if (_alive(epoch) && seq == _listSequence) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch) && seq == _listSequence) {
        setState(() => _listing = false);
      }
    }
  }

  void _replaceJob(Map<String, dynamic> job) {
    final index = _jobs.indexWhere((j) => j['id'] == job['id']);
    if (index >= 0) {
      _jobs[index] = job;
    } else {
      _jobs.insert(0, job);
    }
  }

  Future<void> _poll() async {
    if (_locked || _polling || _busy || _loading || _voiceOpen) return;
    final active = _jobs
        .where(musicPending)
        .take(3)
        .map((j) => j['id'] as String)
        .toList();
    if (active.isEmpty) return;
    _polling = true;
    final epoch = _epoch;
    try {
      for (final id in active) {
        final j = await widget.client.status(id);
        if (!_alive(epoch) || _voiceOpen) return;
        setState(() => _replaceJob(j));
      }
    } catch (e) {
      if (_alive(epoch)) {
        setState(
          () => _notice =
              'Your creation is saved. We will check its progress again shortly.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _saveDraft() async {
    if (_busy || _locked || _pendingGenerate != null) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      await _persistDraft(epoch);
      if (_alive(epoch)) {
        setState(
          () => _notice = 'Draft saved. Pick up here whenever you are ready.',
        );
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _persistDraft(int epoch) async {
    final voicePrepared = _voicePrepared;
    _pendingDraft ??= {
      'version': _version,
      'request_key': musicRequestKey(),
      'data': jsonDecode(jsonEncode(_data)),
    };
    final draft = await widget.client.saveDraft(_pendingDraft!);
    if (!_alive(epoch)) return;
    setState(() {
      _version = draft['version'];
      _hydrate(musicMap(draft['data']));
      _voicePrepared = voicePrepared;
      _error = null;
    });
  }

  Future<void> _reloadDraft() async {
    if (_busy || _locked || _pendingGenerate != null) return;
    if (_dirty &&
        !await _confirm(
          'Load your saved draft?',
          'This replaces the unsaved edits on this screen.',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      final d = await widget.client.draft();
      if (_alive(epoch)) {
        setState(() {
          _version = d['version'];
          _hydrate(musicMap(d['data']));
          _error = null;
        });
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  String? get _validation {
    if (_mode == 'lyrics' && _lyrics.text.trim().isEmpty) {
      return 'Add your lyrics to get started.';
    }
    if (_mode != 'lyrics' && _idea.text.trim().isEmpty) {
      return 'Tell us what your music should feel like.';
    }
    final description = [
      _idea.text.trim(),
      if (_style.text.trim().isNotEmpty) 'Style: ${_style.text.trim()}',
    ].join('\n');
    if (_mode != 'lyrics' && description.length > 400) {
      return 'Shorten the idea or style to 400 characters combined.';
    }
    return null;
  }

  Future<bool> _confirmVoiceGeneration() async {
    final recipe = Map<String, dynamic>.from(_data);
    final mode = recipe['mode'] == 'instrumental'
        ? 'Instrumental'
        : recipe['mode'] == 'lyrics' ? 'Song from lyrics' : 'Song from idea';
    final voice = recipe['mode'] == 'instrumental'
        ? 'No vocals'
        : recipe['voice'] == 'f' ? 'Female voice'
        : recipe['voice'] == 'm' ? 'Male voice' : 'Automatic voice';
    return await _dialog<bool>((c) => AlertDialog(
      title: const Text('Create this music?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Uses 1 creation from your Music Production allowance when accepted.'),
            const SizedBox(height: 16),
            Text('${recipe['title'].toString().trim().isEmpty ? 'Untitled creation' : recipe['title']} · $mode',
              style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('$voice · ${recipe['duration'] == null ? 'Automatic length' : 'About ${recipe['duration']} seconds'}'),
            const SizedBox(height: 12),
            Text('Sound & style: ${recipe['style'].toString().trim().isEmpty ? 'Automatic' : recipe['style']}'),
            const SizedBox(height: 12),
            Text(recipe['mode'] == 'lyrics' ? 'Lyrics' : 'Idea',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SelectableText('${recipe['mode'] == 'lyrics' ? recipe['lyrics'] : recipe['idea']}'),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false),
          child: const Text('Keep editing')),
        FilledButton(key: const ValueKey('music-voice-confirm-generation'),
          onPressed: () => Navigator.pop(c, true), child: const Text('Create music')),
      ],
    )) ?? false;
  }

  Future<void> _openVoice() async {
    if (!_editable || widget.openVoice == null) return;
    final epoch = _epoch, revision = _editRevision, version = _version;
    final current = jsonEncode(_data);
    final workingDraft = musicMap(jsonDecode(current));
    setState(() {
      _voiceOpen = true;
      _busy = true;
      _listSequence++;
      _listing = false;
      _error = _notice = null;
    });
    try {
      await _player.pauseForVoice();
      if (!_alive(epoch)) return;
      if (_player.playing) throw StateError('Music has not paused.');
      final result = await widget.openVoice!(workingDraft);
      if (!_alive(epoch) || result == null) return;
      if (revision != _editRevision || version != _version || current != jsonEncode(_data)) {
        setState(() => _notice = 'Your studio changed. Your current edits were kept. Talk to Rici again when you are ready.');
        return;
      }
      if (result['action'] == 'draft' && result.length == 2) {
        final draft = checkedMusicVoiceRecipe(result['draft']);
        setState(() {
          _hydrate(draft);
          _dirty = true;
          _voicePrepared = true;
          _tab = 0;
          _notice = 'Rici prepared your idea. Review or edit it below, then save the draft or create your music. Nothing has been generated.';
        });
        _top();
      } else if (result['action'] == 'listen' && result.length == 3) {
        final id = result['job_id'], index = result['track_index'];
        if (id is! String || !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(id) ||
            index is! int || index < 0) {
          throw const MusicException('That track selection could not be confirmed. Choose a track from My tracks.');
        }
        // Re-read the signed-in owner's job. Voice never supplies a media URL.
        final job = await widget.client.status(id);
        if (!_alive(epoch)) return;
        final checked = widget.client.checkedJob(job, id);
        final tracks = checked['tracks'] as List;
        if (index >= tracks.length || tracks[index] is! Map ||
            tracks[index]['state'] != 'succeeded' || musicUrl(tracks[index]['audioUrl']) == null) {
          throw const MusicException('That version is not ready to play. Check My tracks for the latest status.');
        }
        setState(() {
          _jobs = [checked, ..._jobs.where((j) => j['id'] != id)];
          _search.clear();
          _favorites = false;
          _tab = 1;
          _notice = 'Listen mode · Rici’s microphone is off. Tap Play if your browser needs a tap to start audio.';
        });
        _top();
        // The callback returns only after LIVE CONVO has released its microphone.
        await _player.toggle('$id:$index', tracks[index]['audioUrl']);
        if (_alive(epoch) && _player.error != null) {
          setState(() => _notice = 'Your track is ready. Tap Play in My tracks to begin listening.');
        }
      } else {
        throw const MusicException('Rici’s studio selection could not be confirmed. Your current idea was kept.');
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = e is MusicException
          ? '$e' : 'Could not switch audio modes. Pause your music and try Talk to Rici again.');
    } finally {
      if (_alive(epoch)) setState(() { _voiceOpen = false; _busy = false; });
    }
  }

  Future<void> _generate() async {
    if (_busy || _locked) return;
    if (_pendingGenerate == null && _validation != null) {
      setState(() => _error = _validation);
      return;
    }
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingGenerate == null && _voicePrepared &&
          !await _confirmVoiceGeneration()) return;
      if (!_alive(epoch)) return;
      _dialogOpen = true;
      bool consent;
      try {
        consent = await widget.ensureConsent(context);
      } finally {
        _dialogOpen = false;
      }
      if (!consent || !_alive(epoch)) return;
      if (_pendingGenerate == null) {
        if (_dirty) await _persistDraft(epoch);
        if (!_alive(epoch)) return;
        _pendingGenerate = {
          ..._data,
          'request_key': musicRequestKey(),
          'consent': true,
        };
      }
      final r = await widget.client.generate(_pendingGenerate!);
      if (!_alive(epoch)) return;
      setState(() {
        _replaceJob(musicMap(r['job']));
        if (r['addon'] is Map) _addon = musicMap(r['addon']);
        _pendingGenerate = null;
        _tab = 1;
        _notice =
            'Your creation is saved in My tracks. You can leave and return while the music service works.';
      });
    } catch (e) {
      if (_alive(epoch)) {
        setState(() {
          _error = '$e';
          if (e is MusicException && [400, 403, 422, 429].contains(e.status)) {
            _pendingGenerate = null;
          }
        });
      }
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _recipe(Map<String, dynamic> data) async {
    if (!_editable) return;
    if (_dirty &&
        !await _confirm(
          'Replace this idea?',
          'Your unsaved edits will be replaced by this starting point.',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    setState(() {
      _hydrate({...blankMusic(), ...data});
      _dirty = true;
      _tab = 0;
      _notice = 'Make this idea your own, then create when you are ready.';
    });
  }

  Future<void> _toggleFavorite(Map<String, dynamic> j) async {
    if (_busy || _locked) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      final n = await widget.client.favorite(j['id'], j['favorite'] != true);
      if (_alive(epoch)) {
        setState(() {
          _replaceJob(n);
          if (_favorites && n['favorite'] != true) {
            _jobs.removeWhere((v) => v['id'] == n['id']);
          }
        });
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> j) async {
    if (_busy ||
        _locked ||
        !await _confirm(
          'Remove this creation?',
          'This removes its saved idea and track links from your library. Download any audio you want to keep first. Used allowance is not restored and copies at the music provider are not deleted.',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      await widget.client.remove(j['id']);
      if (!_alive(epoch)) return;
      if (_player.activeId?.startsWith('${j['id']}:') == true) {
        await _player.stop();
      }
      if (_alive(epoch)) {
        setState(() => _jobs.removeWhere((x) => x['id'] == j['id']));
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _download(Map<String, dynamic> j, int index) async {
    if (_busy || _locked) return;
    final epoch = _epoch;
    final screen = MediaQuery.sizeOf(context);
    final origin = Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height / 2),
      width: 1,
      height: 1,
    );
    setState(() => _busy = true);
    try {
      final d = await widget.client.download(j['id'], index);
      if (!_alive(epoch)) return;
      await (widget.saveFile ?? saveBookkeepingFile)(
        d.bytes,
        'KORLIX-Music-${j['id']}-${index + 1}.${d.extension}',
        d.mime,
        origin,
      );
      if (_alive(epoch)) {
        setState(
          () =>
              _notice = 'Your audio was sent to the download or share action.',
        );
      }
    } catch (e) {
      if (_alive(epoch)) setState(() => _error = '$e');
    } finally {
      if (_alive(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _openAudio(dynamic url) async {
    final uri = musicUrl(url);
    if (uri == null || _locked) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      if (mounted && !_locked) {
        setState(
          () => _error = 'Could not open the audio link. Try Download audio.',
        );
      }
    }
  }

  Future<void> _lyricsDialog(Map<String, dynamic> t) async {
    await _dialog<void>(
      (c) => AlertDialog(
        title: Text(t['title'] ?? 'Lyrics'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: SelectableText(t['lyrics'] ?? ''),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: t['lyrics'] ?? ''));
              Navigator.pop(c);
            },
            child: const Text('Copy lyrics'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      SizedBox(
        width: double.infinity,
        child: Material(
          color: _colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _colors.outlineVariant),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
  Widget _text(String text, {bool muted = false}) => Text(
    text,
    style: TextStyle(
      color: muted ? _colors.onSurfaceVariant : _colors.onSurface,
      height: 1.5,
    ),
  );
  Widget _heading(String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );
  Widget _message(String text, {bool error = false}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? _colors.errorContainer : _colors.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: error ? _colors.onErrorContainer : _colors.onSecondaryContainer,
        height: 1.4,
      ),
    ),
  );
  void _top() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _changeTab(int value) {
    setState(() => _tab = value);
    _top();
  }

  Widget _hero() {
    final usage = musicMap(_addon['usage']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_colors.primaryContainer, _colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your next song starts here.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 8),
          _text('Turn your idea into a song or instrumental.'),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  _addon['active'] == true
                      ? Icons.check_circle_outline
                      : Icons.music_note_outlined,
                  size: 18,
                ),
                label: Text(
                  _addon['active'] == true
                      ? '${usage['remainingThisCycle'] ?? 0} creations left this month'
                      : 'Music Production add-on',
                ),
              ),
              if (_version > 0)
                const Chip(
                  avatar: Icon(Icons.cloud_done_outlined, size: 18),
                  label: Text('Saved draft available'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voiceCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        _colors.tertiaryContainer,
        Color.alphaBlend(_colors.primary.withValues(alpha: .06), _colors.surface),
      ]),
      border: Border.all(color: _colors.tertiary.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: _colors.tertiary,
            borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.multitrack_audio_rounded, color: _colors.onTertiary)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rici · YOUR MUSIC PRODUCER',
            style: TextStyle(fontSize: 11, letterSpacing: 1.1,
              fontWeight: FontWeight.w800, color: _colors.onSurfaceVariant)),
          const SizedBox(height: 5),
          _heading('Create with Rici'),
        ])),
      ]),
      const SizedBox(height: 14),
      _text('Talk through an idea, shape your lyrics, or find a saved track. Your current draft comes with you.'),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(key: const ValueKey('music-open-voice'),
          onPressed: _editable ? _openVoice : null,
          icon: const Icon(Icons.mic_rounded), label: const Text('Talk to Rici')),
        Chip(avatar: Icon(_player.playing ? Icons.headphones_rounded : Icons.tune_rounded, size: 17),
          label: Text(_player.playing ? 'Listen mode' : 'Your studio, your direction')),
      ]),
      const SizedBox(height: 10),
      _text('Talk pauses your music. Listen closes the microphone. You review every new creation before it uses your music allowance.', muted: true),
    ]),
  );

  Widget _starterList() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Start with a spark'),
        const SizedBox(height: 6),
        _text('Pick an idea, then change the details.', muted: true),
        const SizedBox(height: 14),
        for (final s in musicStarters)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: _editable ? () => _recipe(s) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 15,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  Icon(
                    s['mode'] == 'instrumental'
                        ? Icons.headphones_outlined
                        : Icons.music_note_outlined,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.north_east, size: 17),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        _text(
          'Square brackets in a starter are details for you to replace.',
          muted: true,
        ),
      ],
    ),
  );
  Widget _creator() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('What would you like to make?'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const {
                  'idea': 'Song idea',
                  'lyrics': 'My lyrics',
                  'instrumental': 'Instrumental',
                }.entries)
                  ChoiceChip(
                    selected: _mode == m.key,
                    label: Text(m.value),
                    onSelected: _editable
                        ? (_) => _edit(() => _mode = m.key)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _text(
              _mode == 'lyrics'
                  ? 'Your words, brought to life with music.'
                  : _mode == 'instrumental'
                  ? 'Background music, beats or a soundtrack without vocals.'
                  : 'Describe the theme, mood and story. KORLIX will send your idea to the music service.',
            ),
            const SizedBox(height: 16),
            if (_mode == 'lyrics') ...[
              TextField(
                key: const ValueKey('music-lyrics'),
                controller: _lyrics,
                enabled: _editable,
                maxLines: 9,
                minLines: 5,
                maxLength: 5000,
                onChanged: (_) => _edit(),
                decoration: const InputDecoration(
                  labelText: 'Your lyrics',
                  alignLabelWithHint: true,
                  hintText:
                      '[Verse]\nYour opening lines...\n\n[Chorus]\nThe part everyone remembers...',
                ),
              ),
              TextButton.icon(
                onPressed: _editable
                    ? () => _edit(
                        () => _lyrics.text +=
                            '\n\n[Verse]\n\n[Chorus]\n\n[Bridge]\n\n[Outro]\n',
                      )
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add song sections'),
              ),
            ] else
              TextField(
                key: const ValueKey('music-idea'),
                controller: _idea,
                enabled: _editable,
                maxLines: 4,
                minLines: 3,
                maxLength: 400,
                onChanged: (_) => _edit(),
                decoration: InputDecoration(
                  labelText: _mode == 'instrumental'
                      ? 'Describe the sound'
                      : 'What is your song about?',
                  alignLabelWithHint: true,
                  hintText: _mode == 'instrumental'
                      ? 'Soft piano and warm strings for a peaceful evening.'
                      : 'A hopeful reggae song about a fresh start, with a chorus people can sing together.',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('music-style'),
              controller: _style,
              enabled: _editable,
              maxLength: _mode == 'lyrics' ? 1000 : 180,
              onChanged: (_) => _edit(),
              decoration: const InputDecoration(
                labelText: 'Sound & style',
                hintText: 'Genre, mood or instruments',
              ),
            ),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final genre in [
                  'Dancehall',
                  'Reggae',
                  'Afrobeats',
                  'Pop',
                  'Gospel',
                  'R&B',
                  'Lo-fi',
                ])
                  ActionChip(
                    label: Text(genre),
                    onPressed: _editable
                        ? () => _edit(() => _style.text = genre.toLowerCase())
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 12),
              title: const Text('Make it yours'),
              subtitle: Text(
                '${_length == null ? 'Automatic length' : 'About ${_length}s'} · ${_mode == 'instrumental'
                    ? 'No vocals'
                    : _voice == 'auto'
                    ? 'Automatic voice'
                    : _voice == 'f'
                    ? 'Female voice'
                    : 'Male voice'}',
              ),
              children: [
                TextField(
                  key: const ValueKey('music-title'),
                  controller: _title,
                  enabled: _editable,
                  maxLength: 100,
                  onChanged: (_) => _edit(),
                  decoration: const InputDecoration(
                    labelText: 'Working title (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('music-length-$_length'),
                  initialValue: _length ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Target length'),
                  items: [
                    if (_length != null && ![30, 60, 90, 180].contains(_length))
                      DropdownMenuItem(
                        value: _length,
                        child: Text('About $_length seconds'),
                      ),
                    const DropdownMenuItem(value: 0, child: Text('Automatic')),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('30 seconds · quick jingle'),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text('1 minute · short track'),
                    ),
                    DropdownMenuItem(value: 90, child: Text('90 seconds')),
                    DropdownMenuItem(
                      value: 180,
                      child: Text('3 minutes · full song'),
                    ),
                  ],
                  onChanged: _editable
                      ? (v) => _edit(() => _length = v == 0 ? null : v)
                      : null,
                ),
                const SizedBox(height: 8),
                _text(
                  'Length is a target; the finished track may vary.',
                  muted: true,
                ),
                if (_mode != 'instrumental') ...[
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey('music-voice-$_voice'),
                    initialValue: _voice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Voice preference',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text('Let the song decide'),
                      ),
                      DropdownMenuItem(value: 'f', child: Text('Female voice')),
                      DropdownMenuItem(value: 'm', child: Text('Male voice')),
                    ],
                    onChanged: _editable
                        ? (v) => _edit(() => _voice = v!)
                        : null,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            if (_pendingGenerate != null)
              _message(
                'A request needs confirmation. Check it below before changing the idea or starting another creation.',
              ),
            if (_addon['active'] != true)
              _message(
                'Save and shape your idea now. Creating audio requires an active Music Production add-on.',
              ),
            if (_addon['active'] == true && _addon['providerReady'] != true)
              _message(
                'Music creation is temporarily unavailable. You can still work on your draft.',
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('music-generate'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 19,
                  ),
                ),
                onPressed:
                    _busy ||
                        (_pendingGenerate == null &&
                            (_addon['active'] != true ||
                                _addon['providerReady'] != true ||
                                (musicMap(
                                          _addon['usage'],
                                        )['remainingThisCycle'] ??
                                        0) <=
                                    0))
                    ? null
                    : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _busy
                      ? 'Working…'
                      : _pendingGenerate != null
                      ? 'Check / retry this request'
                      : _mode == 'instrumental'
                      ? 'Create instrumental'
                      : 'Create my song',
                ),
              ),
            ),
            const SizedBox(height: 10),
            _text(
              'Uses 1 creation from your Music Production allowance when accepted. Your draft is saved first.',
              muted: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _editable && _dirty ? _saveDraft : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Save draft'),
                ),
                TextButton.icon(
                  onPressed: _editable && _version > 0 ? _reloadDraft : null,
                  icon: const Icon(Icons.restore),
                  label: const Text('Load saved draft'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _text(
              'Your idea and lyrics are processed by MusicAPI.ai after your AI-sharing permission. Review the result and usage rights before publishing.',
              muted: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _card(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Music Production allowance'),
          subtitle: const Text('A separate add-on for any KORLIX tier'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _text(
                'Used: ${musicMap(_addon['usage'])['usedThisCycle'] ?? 0} · Reserved: ${musicMap(_addon['usage'])['reservedThisCycle'] ?? 0} · Cycle: ${musicMap(_addon['usage'])['cycle'] ?? '—'}',
                muted: true,
              ),
            ),
            for (final p in musicRows(_addon['plans']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p['name']}'),
                subtitle: Text(
                  '${p['monthlyGenerations']} creations per month · \$${p['priceMonthly']}/month',
                ),
              ),
            _text(
              'These are the existing add-on plans. This screen does not start a subscription or make a purchase.',
              muted: true,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      ),
    ],
  );
  Widget _jobCard(Map<String, dynamic> j) {
    final s = musicMap(j['settings']),
        tracks = musicRows(j['tracks']),
        pending = musicPending(j),
        uncertain = j['status'] == 'uncertain';
    final title = (s['title'] ?? '').toString().trim();
    final date = DateTime.tryParse(j['createdAt'] ?? '')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.graphic_eq),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty
                            ? (s['mode'] == 'instrumental'
                                  ? 'Instrumental idea'
                                  : 'Untitled song')
                            : title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (date != null)
                        _text(
                          '${date.month}/${date.day}/${date.year}',
                          muted: true,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: j['favorite'] == true
                      ? 'Remove favorite'
                      : 'Favorite creation',
                  onPressed: _busy ? null : () => _toggleFavorite(j),
                  icon: Icon(
                    j['favorite'] == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    pending
                        ? Icons.hourglass_top
                        : uncertain
                        ? Icons.info_outline
                        : tracks.any((t) => t['audioUrl'] != null)
                        ? Icons.check_circle_outline
                        : Icons.music_note,
                    size: 17,
                  ),
                  label: Text(musicStatuses[j['status']] ?? 'Saved'),
                ),
                if ((s['style'] ?? '').toString().isNotEmpty)
                  Text(
                    (s['style'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _colors.onSurfaceVariant),
                  ),
              ],
            ),
            if (pending) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              _text(
                'The music service is working on this creation. It can take several minutes. You can safely leave and find it here later.',
                muted: true,
              ),
            ],
            if (j['error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _message(j['error'], error: j['status'] == 'failed'),
              ),
            if (j['refreshError'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _text(j['refreshError'], muted: true),
              ),
            for (var i = 0; i < tracks.length; i++) _track(j, tracks[i], i),
            if (tracks.isEmpty && !pending && !uncertain)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _text(
                  'No playable audio was returned for this creation.',
                  muted: true,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _editable ? () => _recipe(s) : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Use this idea'),
                ),
                if (!pending && !uncertain)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _remove(j),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
              ],
            ),
            if (uncertain)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(
                  'Support reference: ${j['id']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _track(Map<String, dynamic> j, Map<String, dynamic> t, int index) {
    final id = '${j['id']}:$index',
        active = _player.activeId == id,
        ready = t['state'] == 'succeeded' && musicUrl(t['audioUrl']) != null;
    final duration = active
        ? _player.duration
        : Duration(milliseconds: ((t['duration'] ?? 0) * 1000).round());
    final position = active ? _player.position : Duration.zero;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? _colors.primary : _colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filled(
                tooltip: active && _player.playing
                    ? 'Pause track'
                    : 'Play track',
                onPressed: ready && !_player.busy
                    ? () => _player.toggle(id, t['audioUrl'])
                    : null,
                icon: Icon(
                  active && _player.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: _colors.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t['title'] ?? 'Track'} · Version ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    _text(
                      ready
                          ? musicTime(duration)
                          : t['state'] == 'failed'
                          ? 'This version did not finish'
                          : 'Finishing this version…',
                      muted: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active) ...[
            Slider(
              semanticFormatterCallback: (v) =>
                  musicTime(Duration(milliseconds: v.round())),
              value: position.inMilliseconds
                  .clamp(
                    0,
                    duration.inMilliseconds > 0 ? duration.inMilliseconds : 1,
                  )
                  .toDouble(),
              max: duration.inMilliseconds > 0
                  ? duration.inMilliseconds.toDouble()
                  : 1,
              onChanged: duration.inMilliseconds > 0
                  ? (v) => _player.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(musicTime(position)), Text(musicTime(duration))],
            ),
            if (_player.error != null) _text(_player.error!),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              OutlinedButton.icon(
                onPressed: ready && !_busy ? () => _download(j, index) : null,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download audio'),
              ),
              TextButton(
                onPressed: ready ? () => _openAudio(t['audioUrl']) : null,
                child: const Text('Open audio'),
              ),
              if ((t['lyrics'] ?? '').toString().trim().isNotEmpty)
                TextButton(
                  onPressed: () => _lyricsDialog(t),
                  child: const Text('Lyrics'),
                ),
              if (widget.onReport != null)
                TextButton(
                  onPressed: () async {
                    if (_locked) return;
                    _dialogOpen = true;
                    try {
                      await widget.onReport!(j, t);
                    } finally {
                      _dialogOpen = false;
                    }
                  },
                  child: const Text('Report'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _libraryView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('My tracks'),
      const SizedBox(height: 6),
      _text(
        'Your saved creations, from first idea to final audio.',
        muted: true,
      ),
      const SizedBox(height: 18),
      TextField(
        key: const ValueKey('music-search'),
        controller: _search,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Search your library',
          hintText: 'Title, style or lyrics',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (_) {
          _searchTimer?.cancel();
          _searchTimer = Timer(
            const Duration(milliseconds: 350),
            () => _library(),
          );
        },
      ),
      Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          FilterChip(
            label: const Text('Favorites'),
            selected: _favorites,
            onSelected: (v) {
              setState(() => _favorites = v);
              unawaited(_library());
            },
          ),
          TextButton.icon(
            onPressed: _listing
                ? null
                : () async {
                    await _library();
                    await _poll();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh tracks'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_listing) const LinearProgressIndicator(),
      if (_jobs.isEmpty && !_listing)
        _card(
          Column(
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 48,
                color: _colors.primary,
              ),
              const SizedBox(height: 14),
              _heading(
                _search.text.isNotEmpty || _favorites
                    ? 'No matching creations'
                    : 'Your first song belongs here',
              ),
              const SizedBox(height: 8),
              _text(
                'Create a song or instrumental and it will appear in this library.',
                muted: true,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _changeTab(0),
                child: const Text('Create music'),
              ),
            ],
          ),
        ),
      for (final j in _jobs) _jobCard(j),
      if (_hasMore)
        OutlinedButton(
          onPressed: _listing ? null : () => _library(more: true),
          child: const Text('Load more creations'),
        ),
      const SizedBox(height: 16),
      _text(
        'Save audio you want to keep to your device. Track links are hosted by the music provider and can expire. Older creations from the previous temporary studio are not available here.',
        muted: true,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_back());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: const Text('KORLIX Music Studio'),
        actions: [
          IconButton(
            tooltip: 'Refresh Music Studio',
            onPressed: _busy || _locked ? null : _boot,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _locked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _text(
                  'Your session changed. Sign in again and reopen Music Studio.',
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              key: const ValueKey('music-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_tab == 0) ...[_hero(), const SizedBox(height: 20)],
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          ChoiceChip(
                            selected: _tab == 0,
                            label: const Text('Create'),
                            avatar: const Icon(Icons.add, size: 18),
                            onSelected: (_) => _changeTab(0),
                          ),
                          ChoiceChip(
                            selected: _tab == 1,
                            label: Text(
                              'My tracks${_jobs.isNotEmpty ? ' · ${_jobs.length}' : ''}',
                            ),
                            avatar: const Icon(
                              Icons.library_music_outlined,
                              size: 18,
                            ),
                            onSelected: (_) {
                              _changeTab(1);
                              unawaited(_library());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (widget.openVoice != null) ...[
                        _voiceCard(),
                        const SizedBox(height: 20),
                      ],
                      if (_error != null) _message(_error!, error: true),
                      if (_notice != null) _message(_notice!),
                      if (_tab == 1)
                        _libraryView()
                      else
                        LayoutBuilder(
                          builder: (context, box) => box.maxWidth >= 850
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: _creator()),
                                    const SizedBox(width: 22),
                                    Expanded(flex: 4, child: _starterList()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      title: const Text(
                                        'Need an idea? Choose a starter',
                                      ),
                                      children: [_starterList()],
                                    ),
                                    const SizedBox(height: 12),
                                    _creator(),
                                  ],
                                ),
                        ),
                      const SizedBox(height: 24),
                      _text(
                        'Made with KORLIX · Music powered by MusicAPI.ai',
                        muted: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'live_studio_client.dart';

class LiveStudioScreen extends StatefulWidget {
  const LiveStudioScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
  });
  final LiveStudioClient client;
  final Future<bool> Function() ensureConsent;
  @override
  State<LiveStudioScreen> createState() => _LiveStudioScreenState();
}

class _LiveStudioScreenState extends State<LiveStudioScreen> {
  final _title = TextEditingController(text: 'KORLIX Live');
  final _topic = TextEditingController(
    text: 'How can AI help a small business?',
  );
  final _question = TextEditingController();
  String _category = 'business';
  int _duration = 900, _hosts = 2;
  Map<String, dynamic> _access = {};
  List<Map<String, dynamic>> _shows = [];
  Map<String, dynamic>? _selected;
  bool _busy = false, _loading = true, _invalid = false;
  String? _error, _notice, _saveHash, _saveKey, _startHash, _startKey;
  Timer? _poll;
  int _epoch = 0;
  VideoPlayerController? _player;
  static const _active = {'queued', 'preparing', 'live', 'paused'};
  static const _violet = Color(0xffa18bff), _mint = Color(0xff57dfc5);
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _deny;
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy && !_invalid) unawaited(_load(silent: true));
    });
  }

  void _deny() {
    if (!mounted) return;
    _epoch++;
    _poll?.cancel();
    _closePlayer();
    setState(() {
      _invalid = true;
      _selected = null;
      _shows = [];
      _access = {};
      _error = 'Your session changed. Reopen Live Studio after signing in.';
    });
  }

  void _closePlayer() {
    final p = _player;
    _player = null;
    if (p != null) unawaited(p.dispose());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _closePlayer();
    _title.dispose();
    _topic.dispose();
    _question.dispose();
    widget.client.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> show) {
    final index = _shows.indexWhere((s) => s['id'] == show['id']);
    if (index < 0) {
      _shows.insert(0, show);
    } else if ((show['version'] as num? ?? 0) >=
        (_shows[index]['version'] as num? ?? 0)) {
      _shows[index] = show;
    }
    if (_selected?['id'] == show['id'] &&
        (show['version'] as num? ?? 0) >= (_selected?['version'] as num? ?? 0))
      _selected = show;
  }

  Future<void> _load({bool silent = false}) async {
    final epoch = _epoch;
    try {
      final result = await widget.client.load();
      if (!mounted || _invalid || epoch != _epoch) return;
      setState(() {
        _access = Map<String, dynamic>.from(result['access'] as Map? ?? {});
        final incoming = (result['shows'] as List? ?? [])
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        for (final show in incoming) {
          _apply(show);
        }
        _shows.removeWhere((s) => !incoming.any((n) => n['id'] == s['id']));
        _loading = false;
        if (!silent) _error = null;
      });
    } catch (e) {
      if (mounted && !_invalid && epoch == _epoch)
        setState(() {
          _loading = false;
          _error = '$e';
        });
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy || _invalid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted && !_invalid) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> get _input => {
    'title': _title.text.trim(),
    'topic': _topic.text.trim(),
    'category': _category,
    'durationSeconds': _duration,
    'hostCount': _hosts,
  };
  Future<void> _save() => _action(() async {
    final hash = jsonEncode(_input);
    if (hash != _saveHash) {
      _saveHash = hash;
      _saveKey = liveStudioRequestId();
    }
    final show = await widget.client.save(_input, _saveKey!);
    if (!mounted || _invalid) return;
    _closePlayer();
    setState(() {
      _apply(show);
      _selected = show;
      _notice =
          'Show saved. Create a private rehearsal to hear and see your setup.';
    });
  });
  Future<bool> _confirm(String title, String message, String button) async =>
      await showDialog<bool>(
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
              child: Text(button),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _start(String mode, {bool scheduled = false}) async {
    final show = _selected;
    if (show == null) return;
    DateTime? when;
    if (scheduled) {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 7)),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          now.add(const Duration(minutes: 5)),
        ),
      );
      if (time == null || !mounted) return;
      when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    final message = mode == 'rehearsal'
        ? 'KORLIX will research your topic and generate a private video of up to 60 seconds with AI voices. This pilot allows 3 starts in 24 hours. It uses provider resources; no audience broadcast will start.'
        : 'Start an unlisted YouTube show${when == null ? ' now' : ' at ${when.toLocal()}'}? Anyone with its link can watch. KORLIX will send AI voices, visuals and selected chat questions to the configured providers. The show is limited to ${(show['config']['durationSeconds'] as num) ~/ 60} minutes and 200 generation calls. You can end it from this screen.';
    if (!await _confirm(
          mode == 'rehearsal'
              ? 'Create private rehearsal?'
              : 'Start YouTube pilot?',
          message,
          mode == 'rehearsal' ? 'Create rehearsal' : 'Confirm broadcast',
        ) ||
        !mounted)
      return;
    await _action(() async {
      if (!await widget.ensureConsent() || !mounted || _invalid) return;
      final hash = '${show['id']}/$mode/${when?.toIso8601String()}';
      if (hash != _startHash) {
        _startHash = hash;
        _startKey = liveStudioRequestId();
      }
      final result = await widget.client.start(
        show['id'],
        mode,
        _startKey!,
        scheduledAt: when,
      );
      if (!mounted || _invalid) return;
      _startHash = null;
      _startKey = null;
      _closePlayer();
      setState(() => _apply(result));
    });
  }

  Future<void> _control(String action) async {
    final show = _selected;
    if (show == null) return;
    if (action == 'end' &&
        !await _confirm(
          'End this show?',
          'The producer will stop the running show. It will not restart automatically.',
          'End show',
        ))
      return;
    await _action(() async {
      final result = await widget.client.control(
        show['id'],
        action,
        text: action == 'question' ? _question.text.trim() : null,
      );
      if (!mounted || _invalid) return;
      setState(() => _apply(result));
      if (action == 'question') _question.clear();
    });
  }

  Future<void> _replay() => _action(() async {
    final id = _selected?['id'];
    if (id == null) return;
    final url = await widget.client.replay(id);
    if (!mounted || _invalid || _selected?['id'] != id) return;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https')
      throw const LiveStudioException(
        'The rehearsal link could not be verified.',
      );
    final player = VideoPlayerController.networkUrl(uri);
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    if (!mounted || _invalid || _selected?['id'] != id) {
      await player.dispose();
      return;
    }
    _closePlayer();
    setState(() => _player = player);
  });
  Future<void> _remove() async {
    final id = _selected?['id'];
    if (id == null ||
        !await _confirm(
          'Remove saved show?',
          'This removes its private rehearsal and saved settings. A YouTube replay is managed separately in YouTube.',
          'Remove',
        ))
      return;
    await _action(() async {
      await widget.client.remove(id);
      if (!mounted || _invalid) return;
      _epoch++;
      _closePlayer();
      setState(() {
        _shows.removeWhere((s) => s['id'] == id);
        _selected = null;
      });
    });
  }

  Widget _pill(IconData icon, String label, {Color color = _violet}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
  Widget _host(
    String name,
    String role,
    Color color, {
    bool speaking = false,
  }) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: .035),
        border: Border.all(
          color: color.withValues(alpha: speaking ? 0.85 : 0.25),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: .3),
                  color.withValues(alpha: .05),
                ],
              ),
              border: Border.all(color: color.withValues(alpha: .7)),
            ),
            child: Icon(
              name == 'K-Nova' ? Icons.mic_rounded : Icons.graphic_eq_rounded,
              color: color,
              size: 35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            role,
            style: const TextStyle(color: Color(0xffaebcd5), fontSize: 12),
          ),
        ],
      ),
    ),
  );
  Widget _stage() {
    final show = _selected, config = show?['config'] as Map?;
    final title = (config?['title'] ?? _title.text).toString(),
        hosts = config?['hostCount'] ?? _hosts;
    final state = show?['state'] ?? 'draft',
        progress = show?['progress'] as Map? ?? {};
    final onAir = state == 'live' && show?['mode'] == 'youtube';
    return Container(
      key: const ValueKey('live-studio-stage'),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff202448), Color(0xff080f21)],
        ),
        border: Border.all(color: const Color(0xff343e66)),
        boxShadow: [
          BoxShadow(
            color: _violet.withValues(alpha: .12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                Icons.sensors_rounded,
                onAir
                    ? 'ON AIR'
                    : state == 'paused'
                    ? 'PAUSED'
                    : state == 'preparing'
                    ? 'PREPARING'
                    : 'STUDIO PREVIEW',
                color: onAir ? _mint : _violet,
              ),
              _pill(
                Icons.auto_awesome,
                'AI HOSTED',
                color: const Color(0xffcad5ed),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title.isEmpty ? 'Your next live show' : title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your show. Your voice. Your audience.',
            style: TextStyle(color: Color(0xffaebcd5), fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _host(
                'K-Nova',
                'AI host',
                _violet,
                speaking: progress['speaker'] == 'host',
              ),
              if (hosts == 2) ...[
                const SizedBox(width: 14),
                _host(
                  'The Analyst',
                  'AI cohost',
                  _mint,
                  speaking: progress['speaker'] == 'analyst',
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(painter: _WavePainter()),
          ),
          if (progress['caption'] is String) ...[
            const SizedBox(height: 16),
            Text(
              progress['caption'],
              style: const TextStyle(color: Color(0xffe4eaff), height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            onAir
                ? 'Broadcasting to your configured YouTube channel'
                : 'Preview artwork · AI-generated voices and visuals',
            style: const TextStyle(color: Color(0xff98a8c9), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _panel(String title, Widget content) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          content,
        ],
      ),
    ),
  );
  Widget _setup() => _panel(
    'Create your show',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _title,
          maxLength: 80,
          enabled: !_busy && !_invalid,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Show title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _topic,
          maxLength: 240,
          maxLines: 3,
          enabled: !_busy && !_invalid,
          decoration: const InputDecoration(
            labelText: 'What should the hosts discuss?',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Topic'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 4,
          children:
              [
                    'business',
                    'technology',
                    'sports',
                    'culture',
                    'politics',
                    'religion',
                  ]
                  .map(
                    (c) => ChoiceChip(
                      label: Text('${c[0].toUpperCase()}${c.substring(1)}'),
                      selected: _category == c,
                      onSelected: _busy || _invalid
                          ? null
                          : (_) => setState(() => _category = c),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 20),
        const Text('On-air voices'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('K-Nova'),
              selected: _hosts == 1,
              onSelected: _busy || _invalid
                  ? null
                  : (_) => setState(() => _hosts = 1),
            ),
            ChoiceChip(
              label: const Text('K-Nova + Analyst'),
              selected: _hosts == 2,
              onSelected: _busy || _invalid
                  ? null
                  : (_) => setState(() => _hosts = 2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Maximum broadcast length'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final n in [900, 1800])
              ChoiceChip(
                label: Text('${n ~/ 60} minutes'),
                selected: _duration == n,
                onSelected: _busy || _invalid
                    ? null
                    : (_) => setState(() => _duration = n),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('live-studio-save'),
          onPressed: _busy || _invalid ? null : _save,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Save show'),
        ),
        const SizedBox(height: 10),
        Text(
          'Saving settings does not generate audio or start a broadcast.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
  String _status(Map show) => switch (show['state']) {
    'draft' => 'Saved show',
    'queued' => show['scheduled_at'] == null ? 'Queued' : 'Scheduled',
    'preparing' => 'Preparing',
    'live' => 'On air',
    'paused' => 'Paused',
    'completed' => 'Completed',
    'failed' => 'Needs attention',
    'cancelled' => 'Ended',
    _ => 'Check status',
  };
  Widget _controls() {
    final s = _selected;
    if (s == null)
      return _panel(
        'Producer controls',
        const Text(
          'Save or select a show to create a private rehearsal and prepare your broadcast.',
        ),
      );
    final running = _active.contains(s['state']),
        onAir = ['live', 'paused'].contains(s['state']),
        progress = s['progress'] as Map? ?? {};
    return _panel(
      'Producer controls',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s['config']['title'],
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(Icons.radio_button_checked, _status(s)),
              _pill(
                Icons.timer_outlined,
                '${(s['config']['durationSeconds'] as num) ~/ 60} min maximum',
              ),
            ],
          ),
          if (s['scheduled_at'] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Scheduled: ${DateTime.tryParse(s['scheduled_at'])?.toLocal()}',
            ),
          ],
          if (running) ...[
            const SizedBox(height: 15),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              progress['stage']?.toString() ??
                  (s['mode'] == 'rehearsal'
                      ? 'Creating a private rehearsal…'
                      : 'Waiting for the broadcast worker…'),
            ),
            if (progress['seconds'] is num)
              Text('${progress['seconds']} seconds prepared'),
            const SizedBox(height: 10),
            const Text(
              'You can leave this screen. The server continues the job.',
            ),
          ],
          if (s['error'] is String) ...[
            const SizedBox(height: 12),
            Text(
              s['error'],
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('live-studio-rehearse'),
                onPressed:
                    _busy ||
                        running ||
                        _invalid ||
                        _access['rehearsalReady'] != true
                    ? null
                    : () => _start('rehearsal'),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Private rehearsal'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        running ||
                        _invalid ||
                        _access['youtubeReady'] != true
                    ? null
                    : () => _start('youtube'),
                icon: const Icon(Icons.sensors),
                label: const Text('Go live · unlisted'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        running ||
                        _invalid ||
                        _access['youtubeReady'] != true
                    ? null
                    : () => _start('youtube', scheduled: true),
                icon: const Icon(Icons.schedule),
                label: const Text('Schedule'),
              ),
              if (onAir) ...[
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _control(
                          s['state'] == 'paused' ? 'resume' : 'pause',
                        ),
                  icon: Icon(
                    s['state'] == 'paused' ? Icons.play_arrow : Icons.pause,
                  ),
                  label: Text(s['state'] == 'paused' ? 'Resume' : 'Pause'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _control('skip'),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Skip next segment'),
                ),
              ],
              if (running)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _control('end'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('End show'),
                ),
              if (s['has_replay'] == true)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _replay,
                  icon: const Icon(Icons.movie_outlined),
                  label: const Text('Watch rehearsal'),
                ),
              if (!running)
                TextButton.icon(
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
            ],
          ),
          if (s['watch_url'] is String) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _openYouTube(s['watch_url']),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open YouTube show'),
            ),
          ],
          if (onAir && s['mode'] == 'youtube') ...[
            const SizedBox(height: 20),
            TextField(
              controller: _question,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: 'Question for the next segment',
                border: OutlineInputBorder(),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _control('question'),
              icon: const Icon(Icons.queue),
              label: const Text('Queue question'),
            ),
          ],
          if ((progress['sources'] as List?)?.isNotEmpty == true) ...[
            const Divider(height: 28),
            const Text('Sources checked for this discussion'),
            for (final source in (progress['sources'] as List).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  source['title']?.toString() ?? source['url'].toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openYouTube(String raw) async {
    final url = Uri.tryParse(raw);
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'www.youtube.com' ||
        url.path != '/watch')
      return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted)
      setState(() => _error = 'YouTube could not be opened. Try again.');
  }

  Widget _video() {
    final p = _player!;
    return _panel(
      'Private rehearsal',
      Column(
        children: [
          AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: p,
            builder: (_, value, _) => Column(
              children: [
                VideoProgressIndicator(
                  p,
                  allowScrubbing: true,
                  padding: const EdgeInsets.only(top: 12),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => value.isPlaying ? p.pause() : p.play(),
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                      iconSize: 44,
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                    ),
                    Text(
                      '${value.position.inSeconds} / ${value.duration.inSeconds} sec',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('KORLIX Live Studio'),
      actions: [
        IconButton(
          tooltip: 'Refresh studio',
          onPressed: _busy || _invalid ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_notice!),
                  ),
                _stage(),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _access['youtubeReady'] == true
                              ? Icons.check_circle_outline
                              : Icons.link_off,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Single-channel pilot',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _access['message']?.toString() ??
                                    'Private rehearsals first. YouTube broadcasting requires the connected channel and worker.',
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Up to 60 seconds per rehearsal · 3 starts per 24 hours · No public broadcasts in this pilot',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, c) {
                    final setup = _setup(), controls = _controls();
                    return c.maxWidth >= 850
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: setup),
                              const SizedBox(width: 18),
                              Expanded(child: controls),
                            ],
                          )
                        : Column(
                            children: [
                              setup,
                              const SizedBox(height: 18),
                              controls,
                            ],
                          );
                  },
                ),
                if (_player != null) ...[const SizedBox(height: 18), _video()],
                const SizedBox(height: 18),
                _panel(
                  'Saved shows',
                  _shows.isEmpty
                      ? const Text('Your saved shows will appear here.')
                      : Column(
                          children: [
                            for (final show in _shows)
                              ListTile(
                                selected: _selected?['id'] == show['id'],
                                leading: const Icon(Icons.podcasts_rounded),
                                title: Text(show['config']['title']),
                                subtitle: Text(
                                  '${_status(show)} · ${(show['config']['durationSeconds'] as num) ~/ 60} minutes',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _busy || _invalid
                                    ? null
                                    : () {
                                        _epoch++;
                                        _closePlayer();
                                        setState(() => _selected = show);
                                      },
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff8b78ee).withValues(alpha: .65)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (double x = 0; x < size.width; x += 8) {
      final h =
          3 +
          math.sin(x * .06).abs() *
              math.cos(x * .019).abs() *
              (size.height - 5);
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}

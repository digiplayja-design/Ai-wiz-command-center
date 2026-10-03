import 'dart:async';
import 'dart:typed_data';
import 'social_note_playback.dart';
import 'social_note_playback_native.dart'
    if (dart.library.js_interop) 'social_note_playback_web.dart'
    as playback;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

class SocialAttachmentDraft {
  SocialAttachmentDraft({
    required this.bytes,
    required this.filename,
    required this.kind,
    String? id,
  }) : id = id ?? socialId();
  final Uint8List bytes;
  final String filename, kind, id;
  SocialMap? uploaded;
}

String socialFileSize(num bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';
String _time(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class SocialVoicePlayer extends StatefulWidget {
  const SocialVoicePlayer({
    super.key,
    this.bytes,
    this.url,
    this.durationMs,
    this.refreshUrl,
    this.resolveBeforePlay = false,
    this.accessClient,
    this.playbackFactory,
  });
  final Uint8List? bytes;
  final String? url;
  final int? durationMs;
  final Future<String> Function()? refreshUrl;

  /// Wall audio is permission checked on every new play, including resume.
  final bool resolveBeforePlay;
  final SocialClient? accessClient;
  final SocialNotePlayback Function()? playbackFactory;
  @override
  State<SocialVoicePlayer> createState() => _SocialVoicePlayerState();
}

class _SocialVoicePlayerState extends State<SocialVoicePlayer>
    with WidgetsBindingObserver {
  late final SocialNotePlayback _player =
      widget.playbackFactory?.call() ?? playback.createSocialNotePlayback();
  bool _busy = false, _foreground = true;
  int _request = 0;
  Duration? _resumePosition;
  double _speed = 1;
  String? _error;
  Duration get _position => _player.position;
  Duration get _duration => _player.duration > Duration.zero
      ? _player.duration
      : Duration(
          milliseconds:
              widget.durationMs ??
              ((widget.bytes?.length ?? 44) - 44) * 1000 ~/ 48000,
        );
  bool get _playing => _player.playing;
  void _changed() {
    if (!mounted) return;
    if (_playing && ModalRoute.of(context)?.isCurrent == false) {
      unawaited(_player.pause());
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_changed);
    widget.accessClient?.addListener(_accessChanged);
    if (!widget.resolveBeforePlay) {
      _player.source(bytes: widget.bytes, url: widget.url);
    }
  }

  bool _current(int request) =>
      mounted &&
      request == _request &&
      _foreground &&
      widget.accessClient?.available != false &&
      ModalRoute.of(context)?.isCurrent != false;

  void _accessChanged() {
    if (widget.accessClient?.available == false) {
      _invalidate(clear: true);
      if (mounted) {
        setState(() => _error = 'Your session changed. Reopen KORLIX Social.');
      }
    }
  }

  void _invalidate({required bool clear, bool retainPosition = false}) {
    _request++;
    _busy = false;
    if (retainPosition) _resumePosition ??= _position;
    unawaited(_player.pause());
    if (clear) _player.source();
  }

  @override
  void didUpdateWidget(covariant SocialVoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessClient != widget.accessClient) {
      oldWidget.accessClient?.removeListener(_accessChanged);
      widget.accessClient?.addListener(_accessChanged);
      _invalidate(clear: true);
      _resumePosition = null;
    }
    if (((oldWidget.url != widget.url || oldWidget.bytes != widget.bytes) &&
            (widget.resolveBeforePlay || !_playing)) ||
        oldWidget.resolveBeforePlay != widget.resolveBeforePlay) {
      _invalidate(clear: true);
      _resumePosition = null;
      if (!widget.resolveBeforePlay) {
        _player.source(bytes: widget.bytes, url: widget.url);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      if (widget.resolveBeforePlay) {
        _invalidate(clear: true, retainPosition: true);
      } else {
        unawaited(_player.pause());
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    widget.accessClient?.removeListener(_accessChanged);
    _player.removeListener(_changed);
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy || !_foreground || widget.accessClient?.available == false) {
      return;
    }
    if (_playing) {
      await _player.pause();
      return;
    }
    final request = ++_request;
    final resumeAt = _resumePosition ?? _position;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.resolveBeforePlay) {
        // Begin the silent HTML play in the tap gesture, before any network wait.
        await _player.activate();
        if (!_current(request)) return;
        final refresh = widget.refreshUrl;
        if (refresh == null) {
          throw const SocialException('Voice note unavailable.');
        }
        final url = await refresh();
        if (!_current(request)) return;
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !uri.hasAuthority ||
            (uri.scheme != 'https' && uri.scheme != 'http')) {
          throw const SocialException('Voice note unavailable. Try again.');
        }
        _player.source(url: url);
        await _player.seek(resumeAt);
        if (!_current(request)) return;
        await _player.speed(_speed);
        if (!_current(request)) return;
        _resumePosition = null;
      }
      await _player.play();
    } catch (error) {
      if (!_current(request)) return;
      if (widget.resolveBeforePlay) {
        _player.source();
        _resumePosition = resumeAt;
        setState(
          () => _error = error is SocialException
              ? error.status == 403 || error.status == 404
                    ? 'This voice note is no longer available to you.'
                    : error.message
              : 'Could not play this voice note. Check your volume and tap play to retry.',
        );
      } else {
        setState(() => _error = 'Tap play to retry. Check your device volume.');
        if (widget.refreshUrl != null) {
          try {
            final url = await widget.refreshUrl!();
            if (_current(request)) _player.source(url: url);
          } catch (_) {}
        }
      }
    } finally {
      if (mounted && request == _request) {
        if (!_current(request) && widget.resolveBeforePlay) _player.source();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: s.inputFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filled(
                tooltip: _playing ? 'Pause voice note' : 'Play voice note',
                onPressed: _busy ? null : _toggle,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: s.textOnAccent,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice note',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_time(_position)} / ${_time(_duration)}',
                      style: TextStyle(color: s.mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  final next = _speed == 1
                      ? 1.5
                      : _speed == 1.5
                      ? 2.0
                      : 1.0;
                  try {
                    await _player.speed(next);
                    if (mounted) setState(() => _speed = next);
                  } catch (_) {
                    if (mounted) {
                      setState(() => _error = 'Playback speed is unavailable.');
                    }
                  }
                },
                child: Text(
                  '${_speed == 1
                      ? '1'
                      : _speed == 2
                      ? '2'
                      : '1.5'}×',
                ),
              ),
            ],
          ),
          if (_duration.inMilliseconds > 0)
            Slider(
              value: _position.inMilliseconds
                  .clamp(0, _duration.inMilliseconds)
                  .toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              label: _time(_position),
              onChanged: _busy
                  ? null
                  : (v) async {
                      await _player.seek(Duration(milliseconds: v.toInt()));
                    },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SocialAttachmentView extends StatefulWidget {
  const SocialAttachmentView({
    super.key,
    required this.client,
    required this.attachment,
  });
  final SocialClient client;
  final SocialMap attachment;
  @override
  State<SocialAttachmentView> createState() => _SocialAttachmentViewState();
}

class _SocialAttachmentViewState extends State<SocialAttachmentView> {
  bool _opening = false;
  String? _imageUrl;
  Future<String> _link({bool download = false}) async {
    final r = await widget.client.get('attachment_link', {
      'id': widget.attachment['id'],
      if (download) 'download': true,
    });
    if (!widget.client.available) {
      throw const SocialException('Your session changed.');
    }
    return '${r['url']}';
  }

  Future<void> _download() async {
    setState(() => _opening = true);
    try {
      final url = await _link(download: true);
      if (!mounted || !widget.client.available) return;
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      )) {
        throw const SocialException(
          'Your browser could not open the download. Try again.',
        );
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _preview() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final url = await _link();
      if (!mounted || !widget.client.available) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: widget.client,
          builder: (context, _) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Photo'),
                leading: IconButton(
                  tooltip: 'Close photo',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: widget.client.available
                  ? InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: Center(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            'Photo unavailable. Close and reopen it.',
                          ),
                        ),
                      ),
                    )
                  : const Center(child: Text('Your session changed.')),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment, s = korlixSkinOf(context);
    if (a['kind'] == 'voice') {
      return SocialVoicePlayer(
        key: ValueKey(a['id']),
        url: a['url'] as String?,
        durationMs: (a['duration_ms'] as num?)?.toInt(),
        refreshUrl: _link,
        resolveBeforePlay: a['scope'] == 'wall',
        accessClient: a['scope'] == 'wall' ? widget.client : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (a['kind'] == 'image') ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GestureDetector(
              onTap: _opening ? null : _preview,
              child: Image.network(
                _imageUrl ?? '${a['url'] ?? ''}',
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 190,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (_, _, _) => SizedBox(
                  height: 110,
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        try {
                          final url = await _link();
                          if (mounted) setState(() => _imageUrl = url);
                        } catch (e) {
                          if (context.mounted) socialNotice(context, e);
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reload photo'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (a['kind'] != 'image') ...[
              Icon(Icons.description_outlined, color: s.primary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a['filename']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    socialFileSize(a['size_bytes'] as num? ?? 0),
                    style: TextStyle(color: s.mutedText, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Download attachment',
              onPressed: _opening ? null : _download,
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

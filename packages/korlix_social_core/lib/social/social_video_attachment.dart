import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'social_alert_scope.dart';
import 'social_client.dart';

bool socialAttachmentIsVideo(SocialMap attachment) =>
    attachment['kind'] == 'video' || attachment['content_type'] == 'video/mp4';

/// Opens private video only after Play. Navigating away or losing access stops
/// playback; returning never silently resumes someone else's message.
class SocialVideoAttachment extends StatefulWidget {
  const SocialVideoAttachment({
    super.key,
    required this.client,
    required this.attachment,
  });
  final SocialClient client;
  final SocialMap attachment;
  @override
  State<SocialVideoAttachment> createState() => _SocialVideoAttachmentState();
}

class _SocialVideoAttachmentState extends State<SocialVideoAttachment>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _player;
  RouteObserver<ModalRoute<dynamic>>? _observer;
  bool _loading = false;
  bool _visible = true;
  int _revision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_accessChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = SocialAlertScope.maybeOf(context)?.routeObserver;
    if (observer != _observer) {
      _observer?.unsubscribe(this);
      _observer = observer;
      final route = ModalRoute.of(context);
      if (route != null) observer?.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant SocialVideoAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.attachment['id'] != widget.attachment['id']) {
      oldWidget.client.removeListener(_accessChanged);
      widget.client.addListener(_accessChanged);
      _release();
    }
  }

  void _release() {
    _revision++;
    final player = _player;
    _player = null;
    _loading = false;
    if (player != null) unawaited(player.dispose());
  }

  void _accessChanged() {
    if (!widget.client.available) {
      _release();
      if (mounted) setState(() {});
    }
  }

  @override
  void didPushNext() {
    _visible = false;
    _revision++;
    unawaited(_player?.pause());
  }

  @override
  void didPopNext() => _visible = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _revision++;
      unawaited(_player?.pause());
    }
  }

  Future<void> _play() async {
    if (_loading || !widget.client.available) return;
    final current = _player;
    if (current != null && !current.value.hasError) {
      if (current.value.isPlaying) {
        await current.pause();
      } else {
        if (current.value.position >= current.value.duration)
          await current.seekTo(Duration.zero);
        await current.play();
      }
      return;
    }
    _release();
    final revision = _revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    VideoPlayerController? next;
    bool available() =>
        mounted && widget.client.available && _visible && revision == _revision;
    try {
      final link = await widget.client.get('attachment_link', {
        'id': widget.attachment['id'],
      });
      if (!available()) return;
      next = VideoPlayerController.networkUrl(Uri.parse('${link['url']}'));
      await next.initialize();
      if (!available()) return;
      _player = next;
      next = null;
      await _player!.play();
    } catch (_) {
      if (available()) _error = 'Video unavailable. Tap to try again.';
    } finally {
      await next?.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_accessChanged);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (player == null) {
      return TextButton.icon(
        onPressed: _loading || !widget.client.available ? null : _play,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle_outline),
        label: Text(_loading ? 'Opening video…' : _error ?? 'Play video'),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) => Column(
        children: [
          AspectRatio(
            aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
            child: VideoPlayer(player),
          ),
          if (value.hasError)
            const Text('Playback interrupted. Tap play to reload.'),
          Row(
            children: [
              IconButton(
                tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                onPressed: _play,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: VideoProgressIndicator(player, allowScrubbing: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../social_client.dart';
import 'domino_media.dart';

class DominoController extends ChangeNotifier {
  DominoController({
    required this.client,
    required SocialMap initial,
    DominoMedia Function()? mediaFactory,
    this.polling = true,
  }) : table = initial,
       mediaFactory = mediaFactory ?? DominoMedia.new {
    client.addListener(_access);
  }
  final SocialClient client;
  final DominoMedia Function() mediaFactory;
  final bool polling;
  SocialMap table;
  DominoMedia? media;
  Timer? _timer;
  bool closed = false,
      busy = false,
      syncing = false,
      connectingVideo = false,
      videoJoined = false,
      foreground = true;
  String? error, videoError;
  SocialMap videoConfig = {};
  int cursor = 0;
  DateTime? updated;
  Future<void> _outbox = Future.value();
  String get id => '${table['id']}';
  String get me => '${table['me']}';
  bool get available => !closed && client.available;
  bool get fresh =>
      updated != null && DateTime.now().difference(updated!).inSeconds < 12;
  bool get myTurn =>
      table['phase'] == 'playing' && table['turn'] == me && fresh;
  List<SocialMap> get players => socialItems(table['players']);
  SocialMap? get mine => players.where((p) => p['id'] == me).firstOrNull;
  void _notify() {
    if (!closed) notifyListeners();
  }

  void _access() {
    if (!client.available) {
      table = {};
      unawaited(stopVideo());
      _timer?.cancel();
      _notify();
    }
  }

  Future<void> initialize() async {
    await sync();
    if (!available) return;
    if (polling) {
      _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (foreground) unawaited(sync());
      });
    }
  }

  void _apply(SocialMap result) {
    if (!available) return;
    final next = socialMap(result['table']);
    if (next.isNotEmpty &&
        (next['revision'] as num? ?? 0) >= (table['revision'] as num? ?? 0)) {
      table = next;
    }
    updated = DateTime.now();
    if (result['videoConfig'] != null) {
      videoConfig = socialMap(result['videoConfig']);
    }
    _notify();
  }

  Future<void> sync() async {
    if (!available || syncing || !foreground) return;
    syncing = true;
    try {
      final current = media;
      final r = await client.post('domino', {
        'action': 'sync',
        'id': id,
        'after': cursor,
        'device': client.callDevice,
        'session': videoJoined ? current?.session : null,
      });
      if (!available) return;
      _apply(r);
      error = null;
      if (table['phase'] == 'closed') {
        await stopVideo();
        return;
      }
      if (current != null && current == media && videoJoined) {
        if (mine?['mediaSession'] != current.session) {
          await stopVideo();
          videoError =
              'Your video session ended or moved to another device. Join video again when ready.';
          return;
        }
        await current.sync(
          me,
          players,
          (videoConfig['iceServers'] as List?) ?? [],
        );
        for (final s in socialItems(socialMap(r['table'])['signals'])) {
          if (!available || current != media) break;
          try {
            await current.receive(s);
          } catch (_) {
            videoError =
                'A video connection needs a retry. Tap Reconnect video.';
          } finally {
            cursor = (s['seq'] as num).toInt();
          }
        }
      }
    } catch (e) {
      if (available) {
        error = e is SocialException
            ? e.message
            : 'Connection interrupted. Refresh the table.';
      }
    } finally {
      syncing = false;
      _notify();
    }
  }

  Future<void> move(
    String action, {
    String? tile,
    String? side,
    bool? ready,
  }) async {
    if (!available || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final r = await client.post('domino', {
        'action': 'move',
        'id': id,
        'move': {
          'action': action,
          'revision': table['revision'],
          'requestId': socialId(),
          'tile': ?tile,
          'side': ?side,
          'ready': ?ready,
        },
      });
      _apply(r);
    } catch (e) {
      if (available) {
        await sync();
        error = e is SocialException
            ? e.message
            : 'Your move could not be confirmed. Refresh before retrying.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  void _mediaChanged() {
    _notify();
  }

  Future<void> startVideo() async {
    if (!available ||
        connectingVideo ||
        media != null ||
        table['phase'] == 'closed') {
      return;
    }
    if (videoConfig['enabled'] == false) {
      videoError = 'Video is temporarily unavailable. You can still play.';
      _notify();
      return;
    }
    final m = mediaFactory();
    media = m;
    cursor = 0;
    connectingVideo = true;
    videoError = null;
    m.addListener(_mediaChanged);
    m.activate();
    _notify();
    m.onSignal = (peer, targetSession, kind, payload) {
      final job = _outbox.then((_) async {
        if (!available || media != m || !videoJoined) return;
        await client.post('domino', {
          'action': 'signal',
          'id': id,
          'session': m.session,
          'peer': peer,
          'targetSession': targetSession,
          'kind': kind,
          'payload': payload,
          'signalId': socialId(),
        });
      });
      _outbox = job.catchError((_) {
        if (available) {
          videoError =
              'The video connection needs a retry. Tap Reconnect video.';
          _notify();
        }
      });
      return job;
    };
    try {
      await m.open();
      if (!available || media != m || !foreground) {
        await m.close();
        return;
      }
      await _publishMedia(m, start: true);
      if (!available || media != m || !foreground) {
        await _disableMedia(m);
        await m.close();
        return;
      }
      videoJoined = true;
      await sync();
    } catch (e) {
      if (available) {
        videoError = e is SocialException
            ? e.message
            : 'Camera or microphone could not start. Allow access, then try Join video again.';
      }
      await stopVideo();
    } finally {
      connectingVideo = false;
      _notify();
    }
  }

  Future<void> _publishMedia(DominoMedia m, {bool start = false}) => client
      .post('domino', {
        'action': 'media',
        'id': id,
        'session': m.session,
        'device': client.callDevice,
        'enabled': true,
        'start': start,
        'camera': m.camera,
        'microphone': m.microphone,
      })
      .then((_) {});
  Future<void> _disableMedia(DominoMedia m) async {
    if (!client.available || id == 'null') return;
    try {
      await client.post('domino', {
        'action': 'media',
        'id': id,
        'session': m.session,
        'enabled': false,
      });
    } catch (_) {}
  }

  Future<void> stopVideo() async {
    final old = media;
    media = null;
    videoJoined = false;
    cursor = 0;
    if (old == null) return;
    old.removeListener(_mediaChanged);
    final done = old.close();
    _notify();
    await _disableMedia(old);
    await done;
    old.dispose();
  }

  Future<void> mediaControl(String kind) async {
    final m = media;
    if (!available || !foreground || m == null || !videoJoined) return;
    try {
      if (kind == 'mic') {
        m.toggleMicrophone();
      } else if (kind == 'camera') {
        m.toggleCamera();
      } else if (kind == 'flip') {
        await m.switchCamera();
        return;
      } else if (kind == 'sound') {
        await m.speaker();
        return;
      }
      await _publishMedia(m);
    } catch (_) {
      videoError =
          'That video control could not be updated. Reconnect video if needed.';
      _notify();
    }
  }

  Future<void> reconnectVideo() async {
    await stopVideo();
    if (available && foreground) await startVideo();
  }

  Future<void> leave() async {
    await stopVideo();
    if (!available) return;
    try {
      await client.post('domino', {'action': 'leave', 'id': id});
    } finally {
      _timer?.cancel();
    }
  }

  void background() {
    foreground = false;
    unawaited(stopVideo());
    _notify();
  }

  void resume() {
    foreground = true;
    unawaited(sync());
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    _timer?.cancel();
    client.removeListener(_access);
    unawaited(stopVideo());
    table = {};
    super.dispose();
  }
}

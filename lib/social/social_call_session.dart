import 'dart:async';
import 'package:flutter/material.dart';
import 'social_call_controller.dart';
import 'social_call_screen.dart';
import 'social_client.dart';
import 'social_notifications.dart';
import '../sounds/korlix_sound_service.dart';

/// Keeps media alive above Social routes. Only an explicit minimize retains a
/// call; Back, End, logout and account replacement release the devices.
class SocialCallSession extends ChangeNotifier {
  SocialCallSession({
    required this.notifications,
    required this.navigatorKey,
    required this.sounds,
    this.beforeOpenCall,
  });
  final SocialNotifications notifications;
  final GlobalKey<NavigatorState> navigatorKey;
  final KorlixSoundService sounds;
  final VoidCallback? beforeOpenCall;
  SocialCallController? current;
  bool minimized = false, routeOpen = false, _disposed = false;

  Future<void> start(
    SocialMap peer,
    bool video, {
    SocialMap? incoming,
    DateTime? ringExpiresAt,
    SocialCallMedia? media,
  }) async {
    if (current != null) {
      await restore();
      return;
    }
    final client = notifications.client;
    if (client == null ||
        !client.available ||
        navigatorKey.currentState == null ||
        !notifications.beginCall()) {
      return;
    }
    beforeOpenCall?.call();
    final call = SocialCallController(
      client: client,
      peer: peer,
      video: video,
      incoming: incoming,
      ringExpiresAt: ringExpiresAt,
      media: media,
      sounds: sounds,
    );
    current = call;
    call.addListener(_changed);
    if (incoming == null) unawaited(call.media.audio.activate());
    _changed();
    await restore();
  }

  void _changed() {
    if (_disposed) return;
    if (current?.ended == true && minimized) {
      scheduleMicrotask(() {
        if (!_disposed && current?.ended == true && minimized) _release();
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> restore() async {
    final call = current, navigator = navigatorKey.currentState;
    if (call == null || navigator == null || routeOpen || _disposed) return;
    minimized = false;
    routeOpen = true;
    notifyListeners();
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/social/call'),
      builder: (_) => SocialCallScreen(
        client: call.client,
        peer: call.peer,
        video: call.video,
        incoming: call.incoming ? {'id': call.id, 'state': call.state} : null,
        controller: call,
        onMinimize: () {
          if (call.ended) return;
          minimized = true;
          navigator.pop();
        },
      ),
    );
    await navigator.push<void>(route);
    await route.completed;
    routeOpen = false;
    if (_disposed || !identical(current, call)) return;
    if (!minimized || call.ended) {
      await call.end('Call ended');
      _release();
    } else {
      notifyListeners();
    }
  }

  Future<void> end() async {
    final call = current;
    if (call == null) return;
    await call.end('Call ended');
    if (minimized) _release();
  }

  void _release() {
    final call = current;
    if (call == null) return;
    current = null;
    minimized = false;
    call.removeListener(_changed);
    call.dispose();
    // Never alter a newly signed-in account's notification reservation.
    if (identical(call.client, notifications.client)) notifications.endCall();
    if (!_disposed) notifyListeners();
  }

  void resume() => current?.resume();

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}

class SocialActiveCallBar extends StatelessWidget {
  const SocialActiveCallBar({super.key, required this.session});
  final SocialCallSession session;
  @override
  Widget build(BuildContext context) {
    final call = session.current;
    if (call == null || !session.minimized) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF166B67),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => unawaited(session.restore()),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: Icon(
                  call.video ? Icons.videocam_rounded : Icons.call_rounded,
                ),
                label: Text(
                  'Return to call · ${call.peer['name'] ?? 'KORLIX Social'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(call.status, style: const TextStyle(color: Colors.white)),
              TextButton.icon(
                label: Text(call.media.microphone ? 'Mute' : 'Unmute'),
                onPressed: call.toggleMicrophone,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: Icon(
                  call.media.microphone
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                ),
              ),
              TextButton.icon(
                label: const Text('End call'),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFCC3857),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => unawaited(session.end()),
                icon: const Icon(Icons.call_end_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

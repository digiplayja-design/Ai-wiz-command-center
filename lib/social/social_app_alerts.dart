import 'dart:async';

import 'package:flutter/material.dart';

import '../sounds/korlix_sound_service.dart';
import 'social_alert_overlay.dart';
import 'social_alert_scope.dart';
import 'social_call_session.dart';
import 'social_client.dart';
import 'social_notifications.dart';
import 'social_screen.dart';
import 'social_push_platform.dart';
import 'social_push_native.dart'
    if (dart.library.js_interop) 'social_push_web.dart';

/// Lives above the root Navigator, so pushed tools and dialogs keep receiving
/// Social alerts without replacing their routes or interrupting their drafts.
class SocialAppAlerts extends StatefulWidget {
  const SocialAppAlerts({
    super.key,
    required this.baseUrl,
    required this.headersBuilder,
    required this.sessionChanges,
    required this.navigatorKey,
    required this.routeObserver,
    required this.child,
    this.beforeOpenCall,
    this.notifications,
    this.clientBuilder,
    this.sounds,
  });

  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable sessionChanges;
  final GlobalKey<NavigatorState> navigatorKey;
  final RouteObserver<ModalRoute<dynamic>> routeObserver;
  final Widget child;
  final VoidCallback? beforeOpenCall;
  final SocialNotifications? notifications;
  final SocialClient Function()? clientBuilder;
  final KorlixSoundService? sounds;

  @override
  State<SocialAppAlerts> createState() => _SocialAppAlertsState();
}

class _SocialAppAlertsState extends State<SocialAppAlerts>
    with WidgetsBindingObserver {
  late final SocialNotifications _notifications;
  late final SocialCallSession _calls;
  final _push = createSocialPushPlatform();
  bool _pushOpening = false, _pushLaunchPending = false;
  bool _declining = false;
  String? _callError;
  SocialClient? _lastClient;
  String? _lastCall;
  late final KorlixSoundService _sounds;
  late int _messageRevision;
  late int _onlineRevision;
  DateTime? _ringExpiresAt;
  final Set<String> _silencedCalls = {};

  @override
  void initState() {
    super.initState();
    _notifications =
        widget.notifications ??
        SocialNotifications(
          baseUrl: widget.baseUrl,
          headersBuilder: widget.headersBuilder,
          sessionChanges: widget.sessionChanges,
          shouldPoll: () => mounted,
          enableCalls: true,
          enablePresence: true,
          enableOnlineAlerts: true,
          clientBuilder: widget.clientBuilder,
        );
    _lastClient = _notifications.client;
    _sounds = widget.sounds ?? kKorlixSounds;
    _calls = SocialCallSession(
      notifications: _notifications,
      navigatorKey: widget.navigatorKey,
      sounds: _sounds,
      beforeOpenCall: widget.beforeOpenCall,
    );
    _calls.addListener(_callChanged);
    _pushLaunchPending = _push.launchRequested;
    _push.onOpen(() => unawaited(_openPush()));
    unawaited(_syncPush());
    // A restored unread count or a pre-existing popup is not a new message.
    _messageRevision = _notifications.messageRevision;
    _onlineRevision = _notifications.onlineRevision;
    _notifications.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      _notifications.setForeground(
        state == null || state == AppLifecycleState.resumed,
      );
      _changed();
      unawaited(_notifications.refreshCalls());
      if (_pushLaunchPending) unawaited(_openPush());
    });
  }

  Future<void> _syncPush() async {
    try {
      await _push.syncOwner(socialPushOwner(widget.headersBuilder()));
    } catch (_) {}
  }

  Future<void> _openPush() async {
    if (_pushOpening || !mounted || !_notifications.available) return;
    final navigator = widget.navigatorKey.currentState;
    final owner = _notifications.client;
    if (navigator == null || owner == null) return;
    _pushOpening = true;
    _pushLaunchPending = false;
    try {
      if (_calls.current != null) {
        await _calls.restore();
        return;
      }
      await _notifications.refreshCalls();
      if (!mounted ||
          !identical(owner, _notifications.client) ||
          !owner.available) {
        return;
      }
      final incoming = _notifications.incomingCall;
      if (incoming != null) {
        await _openCall(incoming);
        return;
      }
      final client =
          widget.clientBuilder?.call() ??
          SocialClient(
            baseUrl: widget.baseUrl,
            headersBuilder: widget.headersBuilder,
            sessionChanges: widget.sessionChanges,
          );
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/social/push'),
          builder: (_) => SocialScreen(client: client),
        ),
      );
    } finally {
      _pushOpening = false;
    }
  }

  void _callChanged() {
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  void _changed() {
    final client = _notifications.client;
    final id = _notifications.incomingCall?['id']?.toString();
    final replaced = !identical(client, _lastClient);
    if (replaced) {
      unawaited(_syncPush());
      if (_pushLaunchPending) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_openPush()),
        );
      }
      _silencedCalls.clear();
      _ringExpiresAt = null;
      _sounds.setRinging(this, false);
    } else if (_notifications.messageRevision != _messageRevision &&
        _notifications.messageAlert != null &&
        _notifications.available &&
        !_notifications.callOpen) {
      unawaited(
        _sounds.play(
          KorlixSound.message,
          eventId:
              'social-message:${identityHashCode(client)}:${_notifications.messageRevision}',
        ),
      );
    }
    final online = _notifications.onlineAlert;
    if (!replaced &&
        online != null &&
        online.sound != 'silent' &&
        _onlineRevision != _notifications.onlineRevision &&
        _notifications.available &&
        !_notifications.callOpen &&
        id == null) {
      unawaited(
        _sounds.play(
          online.sound == 'ring' ? KorlixSound.ringtone : KorlixSound.bell,
          eventId: 'social-online:${identityHashCode(client)}:${online.id}',
        ),
      );
    }
    _onlineRevision = _notifications.onlineRevision;
    _messageRevision = _notifications.messageRevision;
    if (id != null && (replaced || id != _lastCall)) {
      _ringExpiresAt = DateTime.now().add(const Duration(seconds: 45));
    }
    _sounds.setRinging(
      this,
      id != null &&
          _notifications.available &&
          !_notifications.callOpen &&
          !_declining &&
          !_silencedCalls.contains(id),
      callId: id,
      expiresAt: _ringExpiresAt,
    );
    if (!replaced && id == _lastCall) return;
    _lastClient = client;
    _lastCall = id;
    if (mounted && (_declining || _callError != null)) {
      setState(() {
        _declining = false;
        _callError = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notifications.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) _calls.resume();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _calls.current?.backgrounded();
    }
    if (state == AppLifecycleState.detached) unawaited(_calls.end());
  }

  Future<void> _openMessage(SocialUnreadConversation conversation) async {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null ||
        !_notifications.available ||
        _notifications.callOpen ||
        !_notifications.conversations.contains(conversation)) {
      return;
    }
    final owner = _notifications.client;
    final client =
        widget.clientBuilder?.call() ??
        SocialClient(
          baseUrl: widget.baseUrl,
          headersBuilder: widget.headersBuilder,
          sessionChanges: widget.sessionChanges,
        );
    _notifications.dismissMessage();
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/social/message-alert'),
        builder: (_) => SocialScreen(
          client: client,
          initialConversation: conversation.card,
          initialGroupChat: conversation.group,
        ),
      ),
    );
    // SocialScreen owns its navigation client. The receiver remains alive.
    if (mounted && identical(owner, _notifications.client)) {
      unawaited(_notifications.refresh());
    }
  }

  Future<void> _openOnline(SocialOnlineAlert alert) async {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null ||
        !_notifications.available ||
        _notifications.callOpen ||
        alert.id != _notifications.onlineAlert?.id) {
      return;
    }
    final client =
        widget.clientBuilder?.call() ??
        SocialClient(
          baseUrl: widget.baseUrl,
          headersBuilder: widget.headersBuilder,
          sessionChanges: widget.sessionChanges,
        );
    _notifications.dismissOnline();
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/social/online-alert'),
        builder: (_) =>
            SocialScreen(client: client, initialConversation: alert.peer),
      ),
    );
  }

  Future<void> _openCall(SocialMap incoming) async {
    final navigator = widget.navigatorKey.currentState;
    final client = _notifications.client;
    if (navigator == null ||
        client == null ||
        !client.available ||
        incoming['id'] != _notifications.incomingCall?['id'] ||
        _notifications.callOpen) {
      return;
    }
    // The route takes over the same bounded invitation; opening is not Answer.
    // Remember it so a failed hang-up response cannot ring again on return.
    final ringExpiresAt = _ringExpiresAt;
    _silenceCall('${incoming['id']}');
    unawaited(_sounds.activate());
    await _calls.start(
      socialMap(incoming['peer']),
      incoming['mode'] == 'video',
      incoming: incoming,
      ringExpiresAt: ringExpiresAt,
    );
  }

  Future<void> _declineCall(SocialMap incoming) async {
    final client = _notifications.client;
    final id = incoming['id'];
    if (_declining ||
        client == null ||
        !client.available ||
        _notifications.callOpen ||
        id != _notifications.incomingCall?['id']) {
      return;
    }
    setState(() {
      _declining = true;
      _callError = null;
    });
    _silenceCall('$id');
    try {
      await client.post('call_end', {'id': id, 'device': client.callDevice});
      if (mounted && identical(client, _notifications.client)) {
        await _notifications.refreshCalls();
      }
    } catch (_) {
      if (mounted &&
          identical(client, _notifications.client) &&
          id == _notifications.incomingCall?['id']) {
        setState(
          () => _callError = 'Could not decline the call. Please retry.',
        );
      }
    } finally {
      if (mounted && identical(client, _notifications.client)) {
        setState(() => _declining = false);
      }
    }
  }

  void _silenceCall(String id) {
    _silencedCalls.add(id);
    if (_silencedCalls.length > 64) _silencedCalls.remove(_silencedCalls.first);
    _sounds.setRinging(this, false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _push.onOpen(null);
    _calls.removeListener(_callChanged);
    _calls.dispose();
    _notifications.removeListener(_changed);
    _sounds.setRinging(this, false);
    if (widget.notifications == null) _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SocialAlertScope(
    notifications: _notifications,
    routeObserver: widget.routeObserver,
    calls: _calls,
    child: SocialAlertOverlay(
      notifications: _notifications,
      onOpenMessage: _openMessage,
      onOpenOnline: _openOnline,
      onOpenCall: _openCall,
      onDeclineCall: _declineCall,
      callActionBusy: _declining,
      callError: _callError,
      child: Column(
        children: [
          Expanded(child: widget.child),
          if (_calls.minimized) SocialActiveCallBar(session: _calls),
        ],
      ),
    ),
  );
}

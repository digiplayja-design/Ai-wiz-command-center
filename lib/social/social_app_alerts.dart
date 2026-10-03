import 'dart:async';

import 'package:flutter/material.dart';

import 'social_alert_overlay.dart';
import 'social_alert_scope.dart';
import 'social_call_screen.dart';
import 'social_client.dart';
import 'social_notifications.dart';
import 'social_screen.dart';

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

  @override
  State<SocialAppAlerts> createState() => _SocialAppAlertsState();
}

class _SocialAppAlertsState extends State<SocialAppAlerts>
    with WidgetsBindingObserver {
  late final SocialNotifications _notifications;
  bool _declining = false;
  String? _callError;
  SocialClient? _lastClient;
  String? _lastCall;

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
          clientBuilder: widget.clientBuilder,
        );
    _lastClient = _notifications.client;
    _notifications.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      _notifications.setForeground(
        state == null || state == AppLifecycleState.resumed,
      );
      unawaited(_notifications.refreshCalls());
    });
  }

  void _changed() {
    final client = _notifications.client;
    final id = _notifications.incomingCall?['id']?.toString();
    if (identical(client, _lastClient) && id == _lastCall) return;
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

  Future<void> _openCall(SocialMap incoming) async {
    final navigator = widget.navigatorKey.currentState;
    final client = _notifications.client;
    if (navigator == null ||
        client == null ||
        !client.available ||
        incoming['id'] != _notifications.incomingCall?['id'] ||
        !_notifications.beginCall()) {
      return;
    }
    try {
      widget.beforeOpenCall?.call();
      // Opening a ringing call never opens the microphone or camera. The
      // existing call screen still requires the user's explicit Answer tap.
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/social/incoming-call'),
        builder: (_) => SocialCallScreen(
          client: client,
          peer: socialMap(incoming['peer']),
          video: incoming['mode'] == 'video',
          incoming: incoming,
        ),
      );
      await navigator.push<void>(route);
      // A pop result arrives before its exit animation finishes. Keep the
      // receiver reserved until the call screen has disposed its media.
      await route.completed;
    } finally {
      if (mounted && identical(client, _notifications.client)) {
        _notifications.endCall();
      }
    }
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications.removeListener(_changed);
    if (widget.notifications == null) _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SocialAlertScope(
    notifications: _notifications,
    routeObserver: widget.routeObserver,
    child: SocialAlertOverlay(
      notifications: _notifications,
      onOpenMessage: _openMessage,
      onOpenCall: _openCall,
      onDeclineCall: _declineCall,
      callActionBusy: _declining,
      callError: _callError,
      child: widget.child,
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as transport;
import 'package:korlix_receipt_core/auth/korlix_http.dart' as korlix_http;
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';
import 'package:korlix_social_core/auth/social_identity.dart';
import 'package:korlix_social_core/social/social_app_alerts.dart';
import 'package:korlix_social_core/social/social_appearance.dart';
import 'package:korlix_social_core/social/social_client.dart';
import 'package:korlix_social_core/social/social_screen.dart';
import 'package:korlix_social_core/sounds/korlix_sound_host.dart';
import 'package:korlix_social_core/theme/korlix_theme.dart';

import 'messenger_account_screen.dart';
import 'messenger_auth.dart';
import 'messenger_auth_screen.dart';

class KorlixMessengerApp extends StatefulWidget {
  const KorlixMessengerApp({super.key, required this.auth});
  final MessengerAuthController auth;

  @override
  State<KorlixMessengerApp> createState() => _KorlixMessengerAppState();
}

class _KorlixMessengerAppState extends State<KorlixMessengerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    korlix_http.configureClientFactory(
      () => KorlixSessionHttpClient(
        inner: transport.Client(),
        sessions: widget.auth.sessions,
        baseUrl: widget.auth.backendUrl,
      ),
    );
    unawaited(widget.auth.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.auth.resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    korlix_http.configureClientFactory(null);
    widget.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) => _MessengerSessionApp(
      // A new account/login removes every route, attachment draft, and call
      // controller. Token rotation keeps the same session and current chat.
      key: ValueKey(
        widget.auth.session == null
            ? 'signed-out'
            : agentAccountScope(widget.auth.headers()),
      ),
      auth: widget.auth,
    ),
  );
}

class _MessengerSessionApp extends StatefulWidget {
  const _MessengerSessionApp({super.key, required this.auth});
  final MessengerAuthController auth;
  @override
  State<_MessengerSessionApp> createState() => _MessengerSessionAppState();
}

class _MessengerSessionAppState extends State<_MessengerSessionApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _observer = RouteObserver<ModalRoute<dynamic>>();
  SocialClient? _client;

  @override
  void initState() {
    super.initState();
    if (widget.auth.session != null) {
      _client = SocialClient(
        baseUrl: widget.auth.backendUrl,
        headersBuilder: widget.auth.headers,
        sessionChanges: widget.auth,
      );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'KORLIX Messenger',
    navigatorKey: _navigator,
    navigatorObservers: [_observer],
    theme: korlixBuildTheme(messengerDefaultAppearance.themeId),
    builder: (_, child) => SocialAppearance(
      defaultChoice: messengerDefaultAppearance,
      child: KorlixSoundHost(
        child: SocialAppAlerts(
          baseUrl: widget.auth.backendUrl,
          headersBuilder: widget.auth.headers,
          sessionChanges: widget.auth,
          sessionReady: () => widget.auth.ready,
          navigatorKey: _navigator,
          routeObserver: _observer,
          messengerMode: true,
          child: child!,
        ),
      ),
    ),
    home: !widget.auth.ready
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _client == null
        ? Theme(
            data: korlixBuildTheme('lavender_mist'),
            child: MessengerAuthScreen(auth: widget.auth),
          )
        : SocialScreen(
            client: _client!,
            messengerMode: true,
            onOpenAccount: () => _navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => MessengerAccountScreen(auth: widget.auth),
              ),
            ),
          ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_screen.dart';

import 'brain_auth.dart';
import 'brain_workspace.dart';

const brainPurple = Color(0xff100b1b);
const brainGold = Color(0xffffdf91);

class BrainApp extends StatefulWidget {
  const BrainApp({super.key, required this.auth});
  final BrainAuthController auth;
  @override
  State<BrainApp> createState() => _BrainAppState();
}

class _BrainAppState extends State<BrainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.auth.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.auth.resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KORLIX Brain',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Rajdhani',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: brainPurple,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa273ed),
        brightness: Brightness.dark,
        primary: brainGold,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      useMaterial3: true,
    ),
    home: ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        if (!widget.auth.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.auth.session == null) {
          return BrainAuthScreen(auth: widget.auth);
        }
        return BrainWorkspace(
          key: ValueKey(widget.auth.revision),
          auth: widget.auth,
        );
      },
    ),
  );
}

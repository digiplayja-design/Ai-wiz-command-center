import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'copybox_auth.dart';
import 'copybox_home.dart';
import 'copybox_theme.dart';

class CopyBoxApp extends StatefulWidget {
  const CopyBoxApp({super.key, required this.auth});
  final CopyBoxAuthController auth;
  @override
  State<CopyBoxApp> createState() => _CopyBoxAppState();
}

class _CopyBoxAppState extends State<CopyBoxApp> with WidgetsBindingObserver {
  SharedPreferences? _prefs;
  ThemeMode _theme = ThemeMode.light;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await widget.auth.initialize();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        final saved = prefs.getString('copybox_theme');
        _theme = saved == 'dark'
            ? ThemeMode.dark
            : saved == 'system'
            ? ThemeMode.system
            : ThemeMode.light;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'Your workspace could not be opened. Please try again.',
        );
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    final saved = await _prefs!.setString('copybox_theme', mode.name);
    if (!saved)
      throw StateError('Appearance could not be saved. Please try again.');
    if (mounted) setState(() => _theme = mode);
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (_, __) => MaterialApp(
      key: ValueKey(widget.auth.accountScope ?? 'local'),
      debugShowCheckedModeBanner: false,
      title: 'KORLIX COPY Box',
      theme: copyboxTheme(Brightness.light),
      darkTheme: copyboxTheme(Brightness.dark),
      themeMode: _theme,
      home: _prefs == null
          ? Scaffold(
              body: Center(
                child: _error == null
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CopyBoxBrand(),
                          SizedBox(height: 30),
                          CircularProgressIndicator(
                            semanticsLabel: 'Opening COPY Box',
                          ),
                        ],
                      )
                    : CopyBoxEmpty(
                        icon: Icons.folder_off_outlined,
                        title: 'Let’s try that again',
                        message: _error!,
                        action: FilledButton(
                          onPressed: _initialize,
                          child: const Text('Retry'),
                        ),
                      ),
              ),
            )
          : CopyBoxHome(
              prefs: _prefs!,
              auth: widget.auth,
              themeMode: _theme,
              onThemeChanged: _changeTheme,
            ),
    ),
  );
}

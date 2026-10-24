import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as transport;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_receipt_core/auth/korlix_http.dart' as korlix_http;
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_client.dart';
import 'package:korlix_receipt_core/receipt_wiz/receipt_wiz_screen.dart';

import 'receipt_auth.dart';
import 'receipt_auth_screen.dart';
import 'receipt_account_screen.dart';

class ReceiptWizApp extends StatefulWidget {
  const ReceiptWizApp({super.key, required this.auth});
  final ReceiptAuthController auth;
  @override
  State<ReceiptWizApp> createState() => _ReceiptWizAppState();
}

class _ReceiptWizAppState extends State<ReceiptWizApp>
    with WidgetsBindingObserver {
  bool _largeText = false, _highContrast = false, _reduceMotion = false;
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
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _largeText = p.getBool('receipt_large_text') ?? false;
        _highContrast = p.getBool('receipt_high_contrast') ?? false;
        _reduceMotion = p.getBool('receipt_reduce_motion') ?? false;
      });
    } catch (_) {
      /* Device accessibility remains effective without saved preferences. */
    }
  }

  Future<void> _preference(String name, bool value) async {
    setState(() {
      if (name == 'large_text') _largeText = value;
      if (name == 'high_contrast') _highContrast = value;
      if (name == 'reduce_motion') _reduceMotion = value;
    });
    final p = await SharedPreferences.getInstance();
    if (!await p.setBool('receipt_$name', value)) {
      throw StateError('Preference could not be saved');
    }
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

  ThemeData _theme({bool contrast = false}) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: receiptTeal,
      brightness: Brightness.light,
      contrastLevel: contrast ? 1 : 0,
    ),
    scaffoldBackgroundColor: Colors.white,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F9F9),
      errorMaxLines: 4,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        backgroundColor: receiptTeal,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: receiptTeal,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) {
      final auth = widget.auth;
      final identity = auth.session == null
          ? 'signed-out'
          : korlixSessionIdentity(auth.session!.accessToken);
      return MaterialApp(
        key: ValueKey(identity),
        debugShowCheckedModeBanner: false,
        title: 'KORLIX Receipt Wiz',
        theme: _theme(contrast: _highContrast),
        highContrastTheme: _theme(contrast: true),
        themeAnimationDuration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        builder: (context, child) {
          final m = MediaQuery.of(context);
          return MediaQuery(
            data: m.copyWith(
              textScaler: _largeText
                  ? TextScaler.linear(math.max(m.textScaler.scale(1), 1.3))
                  : m.textScaler,
              highContrast: _highContrast || m.highContrast,
              disableAnimations: _reduceMotion || m.disableAnimations,
            ),
            child: child!,
          );
        },
        home: !auth.ready
            ? const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Opening Receipt Wiz',
                  ),
                ),
              )
            : auth.session == null
            ? ReceiptAuthScreen(auth: auth)
            : _ReceiptHome(
                key: ValueKey(identity),
                auth: auth,
                largeText: _largeText,
                highContrast: _highContrast,
                reduceMotion: _reduceMotion,
                preference: _preference,
              ),
      );
    },
  );
}

class _ReceiptHome extends StatefulWidget {
  const _ReceiptHome({
    super.key,
    required this.auth,
    required this.largeText,
    required this.highContrast,
    required this.reduceMotion,
    required this.preference,
  });
  final ReceiptAuthController auth;
  final bool largeText, highContrast, reduceMotion;
  final Future<void> Function(String, bool) preference;
  @override
  State<_ReceiptHome> createState() => _ReceiptHomeState();
}

class _ReceiptHomeState extends State<_ReceiptHome> {
  late final ReceiptWizClient _client = ReceiptWizClient(
    backendBaseUrl: widget.auth.backendUrl,
    headersBuilder: widget.auth.headers,
    sessionChanges: widget.auth,
  );
  @override
  Widget build(BuildContext context) => ReceiptWizScreen(
    client: _client,
    ensureConsent: () => ensureKorlixThirdPartyAiConsent(
      context: context,
      featureName: 'KORLIX Receipt Wiz',
      providers: const {KorlixThirdPartyAiProvider.openAi},
      dataCategories: const {
        KorlixThirdPartyAiDataCategory.imagesAndPhotos,
        KorlixThirdPartyAiDataCategory.filesAndDocuments,
      },
    ),
    onOpenAccount: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptAccountScreen(
          auth: widget.auth,
          largeText: widget.largeText,
          highContrast: widget.highContrast,
          reduceMotion: widget.reduceMotion,
          preference: widget.preference,
        ),
      ),
    ),
  );
}

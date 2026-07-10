import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:image_picker/image_picker.dart' as ip;
import 'package:speech_to_text/speech_to_text.dart' as speech_to_text;
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:url_launcher/url_launcher.dart';

import 'korlix_video_downloader.dart';
import 'korlix_image_saver.dart';
import 'korlix_video_preview_source.dart';
import 'korlix_ai_quality_policy.dart';
import 'korlix_cyber_widgets.dart';

import 'improve_picture/screens/portrait_studio_home.dart';
import 'image_to_video/image_to_video_screen.dart';

const String kKorlixImaginePicturePrompt =
    'Describe the picture you want Korlix AI to create.';

// Music Distribution is intentionally hidden until Korlix AI is live.
// Flip this to true after launch to re-enable the existing dormant UI.
const bool kKorlixMusicDistributionPrelaunchVisible = false;

bool get kKorlixHideTipDeveloperOnIos =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool kSupabaseReady = false;
String? kKorlixAccessToken;
String? kKorlixRefreshToken;
String? kKorlixUserEmail;

final ValueNotifier<int> kKorlixAuthRevision = ValueNotifier<int>(0);

void korlixSetInMemorySession(KorlixAuthSession? session) {
  kKorlixAccessToken = session?.accessToken;
  kKorlixRefreshToken = session?.refreshToken;
  kKorlixUserEmail = session?.email;
  kKorlixAuthRevision.value = kKorlixAuthRevision.value + 1;
}

Future<void> korlixClearLocalAuthSession() async {
  await KorlixSessionStore.clear();
  korlixSetInMemorySession(null);
}

bool korlixIsSessionTimeoutStatus(int statusCode) {
  return statusCode == 401 || statusCode == 419 || statusCode == 440;
}

String? kKorlixDeviceId;
String? kKorlixDeviceLabel;

final ValueNotifier<int> kKorlixStopCharacterSpeechSignal = ValueNotifier<int>(
  0,
);

void stopKorlixCharacterSpeechGlobally() {
  kKorlixStopCharacterSpeechSignal.value =
      kKorlixStopCharacterSpeechSignal.value + 1;
}

final List<String> kKorlixBootWarnings = <String>[];

const String kKorlixBackendBaseUrl =
    'https://chee-chai-chee-backend.onrender.com';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installKorlixErrorSurface();

      // Paint the app immediately. On web, waiting for startup services before
      // runApp can create a white screen if a plugin/storage/network step stalls.
      runApp(const CheeChaiCheeApp());

      Future<void>.microtask(() async {
        try {
          await _korlixRunBootStep('Device setup', () async {
            await KorlixDeviceStore.ensureLoaded().timeout(
              const Duration(seconds: 5),
            );
          });

          await _korlixRunBootStep('Supabase setup', () async {
            const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
            const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

            if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
              await Supabase.initialize(
                url: supabaseUrl,
                anonKey: supabaseAnonKey,
              ).timeout(const Duration(seconds: 8));

              kSupabaseReady = true;
            }
          });

          await _korlixRunBootStep('Mobile ads setup', () async {
            if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS)) {
              try {
                await MobileAds.instance.initialize().timeout(
                  const Duration(seconds: 8),
                );
              } catch (e) {
                debugPrint("AdMob init failed: $e");
              }
            }
          });
        } catch (error, stack) {
          final message = 'Background startup warning: $error';
          kKorlixBootWarnings.add(message);
          debugPrint(message);
          debugPrintStack(stackTrace: stack);
        }
      });
    },
    (error, stack) {
      debugPrint('Korlix uncaught startup/runtime error: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

void _installKorlixErrorSurface() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Korlix Flutter error: ${details.exceptionAsString()}');

    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF040612),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF071B27),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.redAccent.withOpacity(0.55)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Korlix AI startup error',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The web app loaded, but Flutter hit a runtime error. Copy this message and send it for the next patch.',
                    style: TextStyle(color: Color(0xFFE4EBEE), height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFE4EBEE),
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };
}

Future<void> _korlixRunBootStep(
  String label,
  Future<void> Function() step,
) async {
  try {
    await step().timeout(const Duration(seconds: 8));
  } catch (error, stack) {
    final warning = '$label failed: $error';
    kKorlixBootWarnings.add(warning);
    debugPrint('Korlix startup warning: $warning');
    debugPrintStack(stackTrace: stack);
  }
}

String backendUrl() {
  const overrideUrl = String.fromEnvironment('AI_WIZARD_BACKEND_URL');

  if (overrideUrl.isNotEmpty) {
    if (overrideUrl.endsWith('/api/generate')) {
      return overrideUrl;
    }
    return '$overrideUrl/api/generate';
  }

  const productionBackendUrl = 'https://chee-chai-chee-backend.onrender.com';

  if (productionBackendUrl.isNotEmpty) {
    return '$productionBackendUrl/api/generate';
  }

  return 'http://localhost:8787/api/generate';
}

String korlixFriendlyErrorMessage(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('429') ||
      lower.contains('quota') ||
      lower.contains('billing') ||
      lower.contains('usage limit') ||
      lower.contains('current quota') ||
      lower.contains('insufficient_quota') ||
      lower.contains('rate limit') ||
      lower.contains('korlix ai is temporarily down')) {
    return 'Korlix AI is temporarily down. Please try again later.';
  }

  return raw.replaceFirst('Exception: ', '');
}

class CheeChaiCheeApp extends StatelessWidget {
  const CheeChaiCheeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Korlix AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: korlixThemeIsLight(kKorlixThemeNotifier.value)
            ? Brightness.light
            : Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: korlixThemeAccentFor(kKorlixThemeNotifier.value),
          brightness: korlixThemeIsLight(kKorlixThemeNotifier.value)
              ? Brightness.light
              : Brightness.dark,
        ),
        scaffoldBackgroundColor: korlixSkinPaletteFor(
          kKorlixThemeNotifier.value,
        ).backgroundMid,
      ),
      home: const AuthGate(),
    );
  }
}

class KorlixDeviceStore {
  static const String deviceIdKey = 'korlix_device_id';
  static const String deviceLabelKey = 'korlix_device_label';

  static String defaultDeviceLabel() {
    if (kIsWeb) {
      return 'Web browser';
    }

    return defaultTargetPlatform.name;
  }

  static Future<String> loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getString(deviceIdKey);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = math.Random().nextInt(0x7fffffff);
    final created = 'korlix_${DateTime.now().millisecondsSinceEpoch}_$random';

    await prefs.setString(deviceIdKey, created);

    return created;
  }

  static Future<String> loadOrCreateDeviceLabel() async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getString(deviceLabelKey);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final label = defaultDeviceLabel();

    await prefs.setString(deviceLabelKey, label);

    return label;
  }

  static Future<void> ensureLoaded() async {
    kKorlixDeviceId = await loadOrCreateDeviceId();
    kKorlixDeviceLabel = await loadOrCreateDeviceLabel();
  }

  static Map<String, String> headers() {
    final headers = <String, String>{};

    if (kKorlixDeviceId != null && kKorlixDeviceId!.isNotEmpty) {
      headers['X-Korlix-Device-Id'] = kKorlixDeviceId!;
    }

    if (kKorlixDeviceLabel != null && kKorlixDeviceLabel!.isNotEmpty) {
      headers['X-Korlix-Device-Label'] = kKorlixDeviceLabel!;
    }

    headers['X-Korlix-Platform'] = kIsWeb ? 'web' : defaultTargetPlatform.name;

    headers.addAll(korlixOpenAIQualityHeaders());
    return headers;
  }

  static Map<String, dynamic> bodyFields() {
    return {
      'device_id': kKorlixDeviceId,
      'device_label': kKorlixDeviceLabel,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    };
  }
}

class KorlixSessionStore {
  static const String accessTokenKey = 'korlix_access_token';
  static const String refreshTokenKey = 'korlix_refresh_token';
  static const String emailKey = 'korlix_user_email';

  static Future<KorlixAuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();

    final accessToken = prefs.getString(accessTokenKey);
    final refreshToken = prefs.getString(refreshTokenKey);
    final email = prefs.getString(emailKey);

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    return KorlixAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: email,
    );
  }

  static Future<void> save(KorlixAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(accessTokenKey, session.accessToken);

    if (session.refreshToken != null && session.refreshToken!.isNotEmpty) {
      await prefs.setString(refreshTokenKey, session.refreshToken!);
    }

    if (session.email != null && session.email!.isNotEmpty) {
      await prefs.setString(emailKey, session.email!);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(emailKey);
  }

  static Future<KorlixAuthSession?> refresh(KorlixAuthSession session) async {
    final refreshToken = session.refreshToken;

    if (refreshToken == null || refreshToken.isEmpty) {
      return session;
    }

    try {
      final response = await http.post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        return null;
      }

      final refreshedSession = data['session'] as Map<String, dynamic>?;

      if (refreshedSession == null ||
          refreshedSession['access_token'] == null) {
        return null;
      }

      final newSession = KorlixAuthSession(
        accessToken: refreshedSession['access_token'].toString(),
        refreshToken: refreshedSession['refresh_token']?.toString(),
        email: data['user']?['email']?.toString() ?? session.email,
      );

      await save(newSession);

      return newSession;
    } catch (_) {
      return session;
    }
  }
}

class KorlixAuthSession {
  final String accessToken;
  final String? refreshToken;
  final String? email;

  const KorlixAuthSession({
    required this.accessToken,
    this.refreshToken,
    this.email,
  });
}

Future<Map<String, String>> korlixAuthenticatedBackendHeaders() async {
  KorlixAuthSession? session;

  final inMemoryAccessToken = kKorlixAccessToken?.trim();

  if (inMemoryAccessToken != null && inMemoryAccessToken.isNotEmpty) {
    session = KorlixAuthSession(
      accessToken: inMemoryAccessToken,
      refreshToken: kKorlixRefreshToken,
      email: kKorlixUserEmail,
    );
  }

  if (session == null) {
    try {
      session = await KorlixSessionStore.load().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      session = null;
    }
  }

  if (session != null) {
    try {
      final refreshed = await KorlixSessionStore.refresh(
        session,
      ).timeout(const Duration(seconds: 8));

      if (refreshed != null) {
        await KorlixSessionStore.save(refreshed);
        korlixSetInMemorySession(refreshed);
      } else {
        korlixSetInMemorySession(session);
      }
    } catch (_) {
      korlixSetInMemorySession(session);
    }
  }

  final headers = KorlixDeviceStore.headers();
  final accessToken = kKorlixAccessToken?.trim();
  final email = kKorlixUserEmail?.trim();

  if (accessToken != null && accessToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $accessToken';
  }

  if (email != null && email.isNotEmpty) {
    headers['X-Korlix-User-Email'] = email;
  }

  return headers;
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

Uri _assertValidKorlixBackendUri(String rawUri) {
  final placeholder = String.fromCharCode(36) + 'kKorlixBackendBaseUrl';

  if (rawUri.contains(placeholder)) {
    throw ArgumentError(
      'Korlix backend URL was not interpolated before request: $rawUri',
    );
  }

  final uri = Uri.parse(rawUri);

  if (!uri.hasScheme || !uri.hasAuthority) {
    throw ArgumentError('Korlix backend URL is missing host: $rawUri');
  }

  return uri;
}

class _AuthGateState extends State<AuthGate> {
  bool _booting = true;

  bool get _signedIn =>
      kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    kKorlixAuthRevision.addListener(_handleAuthRevisionChanged);
    _restoreSession();
  }

  @override
  void dispose() {
    kKorlixAuthRevision.removeListener(_handleAuthRevisionChanged);
    super.dispose();
  }

  void _handleAuthRevisionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _restoreSession() async {
    try {
      await KorlixDeviceStore.ensureLoaded().timeout(
        const Duration(seconds: 5),
      );

      final saved = await KorlixSessionStore.load().timeout(
        const Duration(seconds: 5),
      );

      if (saved == null) {
        await korlixClearLocalAuthSession();
      } else {
        final refreshed = await KorlixSessionStore.refresh(
          saved,
        ).timeout(const Duration(seconds: 8));

        if (refreshed != null) {
          await KorlixSessionStore.save(refreshed);
          korlixSetInMemorySession(refreshed);
        } else {
          await korlixClearLocalAuthSession();
        }
      }
    } catch (error, stack) {
      final warning = 'Session restore failed: $error';
      kKorlixBootWarnings.add(warning);
      debugPrint('Korlix startup warning: $warning');
      debugPrintStack(stackTrace: stack);

      // If restore/refresh fails, do not leave a stale token making the user
      // appear signed in. Force a complete local signout.
      await korlixClearLocalAuthSession();
    }

    if (mounted) {
      setState(() {
        _booting = false;
      });
    }
  }

  Future<void> _handleSignedIn(KorlixAuthSession session) async {
    await KorlixSessionStore.save(session);

    if (!mounted) {
      return;
    }

    setState(() {
      korlixSetInMemorySession(session);
    });
  }

  Future<void> _handleSignOut() async {
    try {
      await KorlixDeviceStore.ensureLoaded();

      await http.post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/auth/signout'),
        headers: {
          'Content-Type': 'application/json',
          if (kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty)
            'Authorization': 'Bearer $kKorlixAccessToken',
          ...KorlixDeviceStore.headers(),
        },
        body: jsonEncode(KorlixDeviceStore.bodyFields()),
      );
    } catch (_) {
      // Local sign-out should still happen even if the server cleanup fails.
    }

    await korlixClearLocalAuthSession();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: korlixThemeBackgroundFor(kKorlixThemeNotifier.value),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/korlix_mini_mark.png',
                  height: 72,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
                const Text(
                  'KORLIX AI',
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 18),
                const CircularProgressIndicator(color: Color(0xFF69D9E8)),
              ],
            ),
          ),
        ),
      );
    }

    if (!_signedIn) {
      return AuthScreen(onSignedIn: _handleSignedIn);
    }

    return Stack(
      children: [
        const CommandCenterScreen(),
        const Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: KorlixAccountButton(),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(top: false, child: KorlixBasicAdBanner()),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: TextButton.icon(
                onPressed: _handleSignOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE4EBEE),
                  backgroundColor: Colors.black.withOpacity(0.32),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthScreen extends StatefulWidget {
  final Future<void> Function(KorlixAuthSession) onSignedIn;

  const AuthScreen({super.key, required this.onSignedIn});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _loading = false;
  bool _resetLoading = false;
  bool _showForgotPassword = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('AuthException(message: ', '')
        .replaceFirst(', statusCode: 400, errorCode: invalid_credentials)', '');
  }

  bool _shouldOfferPasswordReset(String message) {
    final lower = message.toLowerCase();

    return lower.contains('invalid') ||
        lower.contains('credential') ||
        lower.contains('password') ||
        lower.contains('authentication failed') ||
        lower.contains('login');
  }

  Future<void> _requestPasswordReset() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _error = 'Enter your email first, then tap Forgot password.';
        _message = null;
      });
      return;
    }

    setState(() {
      _resetLoading = true;
      _error = null;
      _message = null;
    });

    try {
      final response = await http.post(
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/auth/password-reset',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw Exception(
          data['error'] ?? 'Could not send password reset email.',
        );
      }

      setState(() {
        _showForgotPassword = false;
        _message =
            data['message']?.toString() ??
            'If that email belongs to a Korlix AI account, a password reset link has been sent.';
      });
    } catch (error) {
      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _resetLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Enter your email and password.';
        _message = null;
        _showForgotPassword = false;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
        _message = null;
        _showForgotPassword = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _showForgotPassword = false;
    });

    try {
      await KorlixDeviceStore.ensureLoaded();
      final path = _isSignUp ? '/api/auth/signup' : '/api/auth/signin';

      final response = await http.post(
        Uri.parse('$kKorlixBackendBaseUrl$path'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Authentication failed.');
      }

      final session = data['session'] as Map<String, dynamic>?;

      if (session == null || session['access_token'] == null) {
        setState(() {
          _message =
              data['message']?.toString() ??
              'Account created. Check your email to confirm your account, then sign in.';
          _isSignUp = false;
        });
        return;
      }

      await widget.onSignedIn(
        KorlixAuthSession(
          accessToken: session['access_token'].toString(),
          refreshToken: session['refresh_token']?.toString(),
          email: data['user']?['email']?.toString() ?? email,
        ),
      );
    } catch (error) {
      final cleanedError = _cleanError(error);

      setState(() {
        _error = cleanedError;
        _showForgotPassword =
            !_isSignUp && _shouldOfferPasswordReset(cleanedError);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp
        ? 'Create your Korlix AI account'
        : 'Sign in to Korlix AI';
    final buttonText = _isSignUp ? 'Create account' : 'Sign in';

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: korlixThemeBackgroundFor(kKorlixThemeNotifier.value),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.34),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFF2EC7DF).withOpacity(0.38),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2EC7DF).withOpacity(0.12),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/branding/korlix_mini_mark.png',
                        height: 74,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'KORLIX AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          color: Color(0xFFE4EBEE),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFFA9C6CF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Color(0xFFA9C6CF)),
                          filled: true,
                          fillColor: const Color(0xFF071B27).withOpacity(0.86),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Color(0xFFA9C6CF)),
                          filled: true,
                          fillColor: const Color(0xFF071B27).withOpacity(0.86),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      if (!_isSignUp && _showForgotPassword) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: (_loading || _resetLoading)
                              ? null
                              : _requestPasswordReset,
                          icon: _resetLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF69D9E8),
                                  ),
                                )
                              : const Icon(Icons.lock_reset_rounded, size: 18),
                          label: Text(
                            _resetLoading
                                ? 'Sending reset email...'
                                : 'Forgot password? Send reset email',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF69D9E8),
                          ),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF69D9E8)),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF143B4A),
                            foregroundColor: const Color(0xFFE4EBEE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFE4EBEE),
                                  ),
                                )
                              : Text(
                                  buttonText,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _error = null;
                                  _message = null;
                                  _showForgotPassword = false;
                                });
                              },
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign in'
                              : 'New here? Create account',
                          style: const TextStyle(color: Color(0xFF69D9E8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KorlixHomeCharacterHero extends StatelessWidget {
  const KorlixHomeCharacterHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF071B27).withOpacity(0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2EC7DF).withOpacity(0.34)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2EC7DF).withOpacity(0.12),
            blurRadius: 34,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Selected Character',
            style: TextStyle(
              color: Color(0xFF69D9E8),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'JJ',
            style: TextStyle(
              color: Color(0xFFE4EBEE),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Basic starter character. Open Settings → View characters to preview and unlock more Korlix AI characters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFA9C6CF),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: const KorlixCharacterIntroPreview(
              assetPath: 'assets/characters/jj/intro.mp4',
              muted: false,
              showSoundButton: true,
            ),
          ),
        ],
      ),
    );
  }
}

class KorlixGeneratedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> headers;

  const KorlixGeneratedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.headers,
  });

  @override
  State<KorlixGeneratedVideoPlayer> createState() =>
      _KorlixGeneratedVideoPlayerState();
}

class _KorlixGeneratedVideoPlayerState
    extends State<KorlixGeneratedVideoPlayer> {
  VideoPlayerController? _controller;
  KorlixVideoPreviewSource? _previewSource;
  bool _ready = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KorlixGeneratedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.headers.toString() != widget.headers.toString()) {
      _load();
    }
  }

  Future<void> _load() async {
    final oldController = _controller;
    final oldPreviewSource = _previewSource;

    if (mounted) {
      setState(() {
        _controller = null;
        _previewSource = null;
        _ready = false;
        _loading = true;
        _error = null;
      });
    } else {
      _controller = null;
      _previewSource = null;
      _ready = false;
      _loading = true;
      _error = null;
    }

    await oldController?.dispose();
    await releaseKorlixVideoPreviewSource(oldPreviewSource);

    KorlixVideoPreviewSource? previewSource;
    VideoPlayerController? controller;

    try {
      previewSource = await prepareKorlixVideoPreviewSource(
        url: widget.videoUrl,
        headers: widget.headers,
      );

      controller = VideoPlayerController.networkUrl(
        Uri.parse(previewSource.url),
        httpHeaders: previewSource.headers,
      );

      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);

      try {
        await controller.play();
      } catch (playError) {
        debugPrint('Korlix video preview autoplay warning: $playError');
      }

      if (!mounted) {
        await controller.dispose();
        await releaseKorlixVideoPreviewSource(previewSource);
        return;
      }

      setState(() {
        _controller = controller;
        _previewSource = previewSource;
        _ready = true;
        _loading = false;
      });
    } catch (error) {
      await controller?.dispose();
      await releaseKorlixVideoPreviewSource(previewSource);

      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Could not load video preview. Use Download Video, or tap Retry Preview.';
        });
      }
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    final previewSource = _previewSource;
    _controller = null;
    _previewSource = null;
    controller?.dispose();
    unawaited(releaseKorlixVideoPreviewSource(previewSource));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Preview'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB7FF00),
                side: const BorderSide(color: Color(0xFFB7FF00)),
              ),
            ),
          ],
        ),
      );
    }

    if (!_ready || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF69D9E8)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class KorlixCharacterIntroPreview extends StatefulWidget {
  final String assetPath;
  final bool muted;
  final bool showSoundButton;
  final bool autoplay;
  final bool loop;
  final double aspectRatio;
  final bool fillParent;
  final BoxFit fit;

  const KorlixCharacterIntroPreview({
    super.key,
    required this.assetPath,
    this.muted = true,
    this.showSoundButton = false,
    this.autoplay = true,
    this.loop = true,
    this.aspectRatio = 9 / 16,
    this.fillParent = false,
    this.fit = BoxFit.cover,
  });

  @override
  State<KorlixCharacterIntroPreview> createState() =>
      _KorlixCharacterIntroPreviewState();
}

class _KorlixCharacterIntroPreviewState
    extends State<KorlixCharacterIntroPreview> {
  static const int _maxAutoLoops = 3;

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _soundOn = false;
  int _completedLoops = 0;
  bool _handlingEnd = false;

  @override
  void initState() {
    super.initState();
    _soundOn = false;
    kKorlixStopCharacterSpeechSignal.addListener(_handleGlobalStopSignal);
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant KorlixCharacterIntroPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.muted != widget.muted ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.loop != widget.loop) {
      _soundOn = false;
      _completedLoops = 0;
      _loadVideo();
    }
  }

  void _handleGlobalStopSignal() {
    _stopTalkingCompletely();
  }

  Future<void> _loadVideo() async {
    final oldController = _controller;

    if (oldController != null) {
      oldController.removeListener(_handleVideoProgress);
    }

    _controller = null;
    _ready = false;
    _completedLoops = 0;
    _handlingEnd = false;

    await oldController?.dispose();

    try {
      final controller = VideoPlayerController.asset(widget.assetPath);

      await controller.initialize();

      // We manually control looping so talking never loops forever.
      // Start muted first so web/mobile browsers allow autoplay.
      await controller.setLooping(false);
      await controller.setVolume(0.0);
      controller.addListener(_handleVideoProgress);

      if (widget.autoplay) {
        try {
          await controller.play();
        } catch (error) {
          debugPrint('Korlix character autoplay warning: $error');
        }
      }

      _soundOn = false;

      if (!mounted) {
        controller.removeListener(_handleVideoProgress);
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
        });
      }
    }
  }

  void _handleVideoProgress() {
    final controller = _controller;

    if (controller == null || _handlingEnd) {
      return;
    }

    final value = controller.value;

    if (!value.isInitialized || !value.isPlaying) {
      return;
    }

    final duration = value.duration;

    if (duration == Duration.zero) {
      return;
    }

    final remaining = duration - value.position;

    if (remaining <= const Duration(milliseconds: 250)) {
      _handleVideoReachedEnd();
    }
  }

  Future<void> _handleVideoReachedEnd() async {
    final controller = _controller;

    if (controller == null || _handlingEnd) {
      return;
    }

    _handlingEnd = true;
    _completedLoops += 1;

    final allowedLoops = widget.loop ? _maxAutoLoops : 1;

    try {
      if (_completedLoops >= allowedLoops) {
        await _stopTalkingCompletely(seekToEnd: true);
      } else {
        await controller.seekTo(Duration.zero);
        await controller.play();
      }
    } finally {
      _handlingEnd = false;
    }
  }

  Future<void> _stopTalkingCompletely({bool seekToEnd = false}) async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {
      await controller.setVolume(0.0);
      await controller.pause();

      if (!seekToEnd) {
        await controller.seekTo(Duration.zero);
      }
    } catch (_) {
      // Video/audio stopping should never block the app.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _soundOn = false;
    });
  }

  Future<void> _toggleSound() async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    final next = !_soundOn;

    try {
      await controller.setVolume(next ? 1.0 : 0.0);

      if (next && !controller.value.isPlaying) {
        _completedLoops = 0;
        await controller.seekTo(Duration.zero);
        await controller.play();
      }
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _soundOn = next;
    });
  }

  Future<void> _replayWithSound() async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {
      _completedLoops = 0;
      await controller.setVolume(1.0);
      await controller.seekTo(Duration.zero);
      await controller.play();
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _soundOn = true;
    });
  }

  @override
  void dispose() {
    kKorlixStopCharacterSpeechSignal.removeListener(_handleGlobalStopSignal);
    _controller?.removeListener(_handleVideoProgress);
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildVideoContent() {
    final controller = _controller;
    final effectiveFit = widget.assetPath.contains('/phil/')
        ? BoxFit.contain
        : widget.fit;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.black.withOpacity(0.45),
          child: _ready && controller != null && controller.value.isInitialized
              ? GestureDetector(
                  onTap: widget.showSoundButton ? _replayWithSound : null,
                  child: FittedBox(
                    fit: effectiveFit,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              : const Center(
                  child: Icon(
                    Icons.movie_creation_outlined,
                    color: Color(0xFF69D9E8),
                    size: 34,
                  ),
                ),
        ),
        if (widget.showSoundButton)
          Positioned(
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.68),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF69D9E8).withOpacity(0.65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF69D9E8).withOpacity(0.20),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _toggleSound,
                icon: Icon(
                  _soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                ),
                color: const Color(0xFFE4EBEE),
                tooltip: _soundOn ? 'Mute' : 'Unmute',
              ),
            ),
          ),
        // The text replay button was removed to keep the character cards cleaner.
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildVideoContent();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: widget.fillParent
          ? SizedBox.expand(child: content)
          : AspectRatio(aspectRatio: widget.aspectRatio, child: content),
    );
  }
}

class KorlixBasicAdBanner extends StatefulWidget {
  const KorlixBasicAdBanner({super.key});

  @override
  State<KorlixBasicAdBanner> createState() => _KorlixBasicAdBannerState();
}

class _KorlixBasicAdBannerState extends State<KorlixBasicAdBanner> {
  BannerAd? _bannerAd;
  bool _loaded = false;
  bool _shouldShow = false;

  static const String _androidTestBannerAdUnit =
      'ca-app-pub-3940256099942544/6300978111';

  static const String _androidProductionBannerAdUnit =
      'ca-app-pub-1549134869666707/4852386901';

  bool get _mobileAdsSupported {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  String get _adUnitId {
    return kReleaseMode
        ? _androidProductionBannerAdUnit
        : _androidTestBannerAdUnit;
  }

  @override
  void initState() {
    super.initState();
    _prepareAd();
  }

  Future<void> _prepareAd() async {
    if (!_mobileAdsSupported) {
      return;
    }

    if (kKorlixAccessToken == null || kKorlixAccessToken!.isEmpty) {
      return;
    }

    try {
      final response = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kKorlixAccessToken',
        },
      );

      if (response.statusCode >= 400) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final profile =
          (data['profile'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final tier = (profile['tier'] ?? 'basic').toString();
      final preferredTheme = (profile['preferred_theme'] ?? 'korlix_blue')
          .toString();

      if (tier != 'basic') {
        return;
      }

      _shouldShow = true;

      final ad = BannerAd(
        size: AdSize.banner,
        adUnitId: _adUnitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) {
              return;
            }

            setState(() {
              _bannerAd = ad as BannerAd;
              _loaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();

            if (!mounted) {
              return;
            }

            setState(() {
              _loaded = false;
              _bannerAd = null;
            });
          },
        ),
        request: const AdRequest(),
      );

      await ad.load();
    } catch (_) {
      // Ads should never block app usage.
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mobileAdsSupported || !_shouldShow || !_loaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble() + 12,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.72),
        border: Border(
          top: BorderSide(color: const Color(0xFF2EC7DF).withOpacity(0.25)),
        ),
      ),
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}

class KorlixCharacterIntroVideo extends StatefulWidget {
  final String assetPath;
  final bool selected;
  final bool locked;

  const KorlixCharacterIntroVideo({
    super.key,
    required this.assetPath,
    required this.selected,
    required this.locked,
  });

  @override
  State<KorlixCharacterIntroVideo> createState() =>
      _KorlixCharacterIntroVideoState();
}

class _KorlixCharacterIntroVideoState extends State<KorlixCharacterIntroVideo> {
  static const int _maxAutoLoops = 3;

  late final VideoPlayerController _controller;
  bool _ready = false;
  int _completedLoops = 0;
  bool _handlingEnd = false;

  @override
  void initState() {
    super.initState();

    kKorlixStopCharacterSpeechSignal.addListener(_handleGlobalStopSignal);

    _controller = VideoPlayerController.asset(widget.assetPath)
      ..setLooping(false)
      ..setVolume(0);

    _controller.addListener(_handleVideoProgress);

    _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _ready = true;
      });

      _controller.play();
    });
  }

  @override
  void didUpdateWidget(covariant KorlixCharacterIntroVideo oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_ready &&
        !_controller.value.isPlaying &&
        _completedLoops < _maxAutoLoops) {
      _controller.play();
    }
  }

  void _handleGlobalStopSignal() {
    _stopCompletely();
  }

  void _handleVideoProgress() {
    if (!_ready || _handlingEnd) {
      return;
    }

    final value = _controller.value;

    if (!value.isInitialized || !value.isPlaying) {
      return;
    }

    final duration = value.duration;

    if (duration == Duration.zero) {
      return;
    }

    final remaining = duration - value.position;

    if (remaining <= const Duration(milliseconds: 250)) {
      _handleVideoReachedEnd();
    }
  }

  Future<void> _handleVideoReachedEnd() async {
    if (_handlingEnd) {
      return;
    }

    _handlingEnd = true;
    _completedLoops += 1;

    try {
      if (_completedLoops >= _maxAutoLoops) {
        await _stopCompletely(seekToEnd: true);
      } else {
        await _controller.seekTo(Duration.zero);
        await _controller.play();
      }
    } finally {
      _handlingEnd = false;
    }
  }

  Future<void> _stopCompletely({bool seekToEnd = false}) async {
    try {
      await _controller.setVolume(0);
      await _controller.pause();

      if (!seekToEnd) {
        await _controller.seekTo(Duration.zero);
      }
    } catch (_) {
      // Character video stopping should never block the app.
    }
  }

  @override
  void dispose() {
    kKorlixStopCharacterSpeechSignal.removeListener(_handleGlobalStopSignal);
    _controller.removeListener(_handleVideoProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.selected
        ? const Color(0xFF69D9E8)
        : widget.locked
        ? const Color(0xFFFFD166)
        : const Color(0xFF2EC7DF);

    return Container(
      height: 210,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor.withOpacity(widget.selected ? 0.82 : 0.38),
          width: widget.selected ? 1.4 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF69D9E8),
                strokeWidth: 2,
              ),
            ),
          if (widget.locked)
            Container(
              color: Colors.black.withOpacity(0.34),
              child: const Center(
                child: Icon(
                  Icons.lock_rounded,
                  color: Color(0xFFFFD166),
                  size: 36,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class KorlixAccountButton extends StatefulWidget {
  const KorlixAccountButton({super.key});

  @override
  State<KorlixAccountButton> createState() => _KorlixAccountButtonState();
}

class _KorlixAccountButtonState extends State<KorlixAccountButton> {
  bool _loading = false;

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $kKorlixAccessToken';
    }

    headers.addAll(KorlixDeviceStore.headers());

    headers.addAll(korlixOpenAIQualityHeaders());
    return headers;
  }

  String _cleanError(Object error) {
    return korlixFriendlyErrorMessage(error);
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _showKorlixNotice({
    required String title,
    required String message,
    bool danger = false,
  }) async {
    if (!mounted) {
      return;
    }

    final accent = danger ? Colors.redAccent : const Color(0xFF69D9E8);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.62),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF071B27),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.65), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.22),
                  blurRadius: 34,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.48),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  danger
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: accent,
                  size: 44,
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF143B4A),
                      foregroundColor: const Color(0xFFE4EBEE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reportHistoryItem({
    required String? generationId,
    required String prompt,
  }) async {
    try {
      final response = await http.post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/reports'),
        headers: _headers(),
        body: jsonEncode({
          'generation_id': generationId,
          'reason': 'User reported AI output',
          'details': 'Reported from saved settings. Prompt: $prompt',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Report failed.');
      }

      await _showKorlixNotice(
        title: 'Report submitted',
        message: 'Thank you. The Korlix team will review this output.',
      );
    } catch (error) {
      await _showKorlixNotice(
        title: 'Report failed',
        message: _cleanError(error),
        danger: true,
      );
    }
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071B27),
          title: const Text(
            'Request account deletion?',
            style: TextStyle(color: Color(0xFFE4EBEE)),
          ),
          content: const Text(
            'This will submit a request to delete your Korlix AI account and related data. You may be contacted by support if more information is needed.',
            style: TextStyle(color: Color(0xFFA9C6CF)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Request deletion',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final response = await http.post(
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/account/delete-request',
        ),
        headers: _headers(),
        body: jsonEncode({
          'email': kKorlixUserEmail,
          'reason':
              'User requested account deletion from Korlix Account panel.',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Could not submit deletion request.');
      }

      await _showKorlixNotice(
        title: 'Deletion request submitted',
        message: 'Your account deletion request has been recorded.',
        danger: true,
      );
    } catch (error) {
      await _showKorlixNotice(
        title: 'Deletion request failed',
        message: _cleanError(error),
        danger: true,
      );
    }
  }

  Widget _planCard({
    required String title,
    required String subtitle,
    required String price,
    required List<String> features,
    required Color accent,
    bool current = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: current ? accent.withOpacity(0.78) : accent.withOpacity(0.28),
          width: current ? 1.3 : 1,
        ),
        boxShadow: [
          if (current)
            BoxShadow(
              color: accent.withOpacity(0.18),
              blurRadius: 22,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(0.45)),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      color: Color(0xFFE4EBEE),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: const TextStyle(
              color: Color(0xFFE4EBEE),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: accent, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlansPanel({required String currentTier}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071B27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.86,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.all(22),
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/branding/korlix_mini_mark.png',
                        height: 38,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Korlix AI Plans',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose your character access, generation limits, and premium tools. Payments will be connected later through Google Play Billing.',
                    style: TextStyle(
                      color: Color(0xFFA9C6CF),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _planCard(
                    title: 'Basic',
                    subtitle: 'Free entry plan for light use.',
                    price: 'Free',
                    accent: const Color(0xFF69D9E8),
                    current: currentTier == 'basic',
                    features: const [
                      '3 generations per day',
                      'Access to 1 character',
                      'Ads included',
                      'Limited saved settings',
                      '1 Create Video per month',
                      'No music production',
                    ],
                  ),
                  _planCard(
                    title: 'Pro',
                    subtitle: 'For regular creators and daily productivity.',
                    price: '\$34.99 / month',
                    accent: const Color(0xFFB794F4),
                    current: currentTier == 'pro',
                    features: const [
                      'Higher text generation limits',
                      'Access to up to 3 characters',
                      'PDF/export access',
                      'Saved settings access',
                      'Reduced or no ads',
                      'Voice input and document upload',
                    ],
                  ),
                  _planCard(
                    title: 'Ultra Premium',
                    subtitle:
                        'For power users who want the full Korlix experience.',
                    price: '\$124.99 / month',
                    accent: const Color(0xFFFFD166),
                    current: currentTier == 'ultra',
                    features: const [
                      'Access to all 9+ characters',
                      'Highest personal generation limits',
                      'Beta feature access',
                      '30 Create Video credits per month',
                      'OCR / handwriting / scanned image reading',
                      'Eligible for paid Music Production add-on when released',
                      'No ads',
                    ],
                  ),
                  _planCard(
                    title: 'Enterprise',
                    subtitle:
                        'For teams, schools, agencies, and custom business access.',
                    price: 'support@korlixdeveloper.com',
                    accent: const Color(0xFFE4EBEE),
                    current: currentTier == 'enterprise',
                    features: const [
                      'All available characters',
                      'Team seats and admin controls',
                      'Custom text, video, and usage limits',
                      'Custom add-on options by account',
                      'Email support@korlixdeveloper.com',
                      'Enterprise onboarding',
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2B3D).withOpacity(0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF2EC7DF).withOpacity(0.28),
                      ),
                    ),
                    child: const Text(
                      'Music Production add-ons are optional monthly add-ons available to any Korlix tier: \$25/mo for 75 generations, \$120/mo for 580 generations, \$450/mo for 4,000 generations, and \$950/mo for 10,000 generations. One generation equals one MusicAPI.ai create request. Add-ons do not change your base plan.',
                      style: TextStyle(
                        color: Color(0xFFA9C6CF),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  int _tierRank(String tier) {
    switch (tier) {
      case 'enterprise':
        return 4;
      case 'ultra':
        return 3;
      case 'pro':
        return 2;
      default:
        return 1;
    }
  }

  Color _tierAccent(String tier) {
    switch (tier) {
      case 'enterprise':
        return const Color(0xFFE4EBEE);
      case 'ultra':
        return const Color(0xFFFFD166);
      case 'pro':
        return const Color(0xFFB794F4);
      default:
        return const Color(0xFF69D9E8);
    }
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'enterprise':
        return 'Enterprise';
      case 'ultra':
        return 'Ultra Premium';
      case 'pro':
        return 'Pro';
      default:
        return 'Basic';
    }
  }

  String? _characterIntroAsset(String id) {
    switch (normalizeKorlixCharacterId(id)) {
      case 'jj':
        return 'assets/characters/jj/intro.mp4';
      case 'phil':
        return 'assets/characters/phil/intro.mp4';
      case 'yuna':
        return 'assets/characters/yuna/intro.mp4';
      case 'ji_a':
        return 'assets/characters/ji-a/intro.mp4';
      case 'chee_chai_chee':
        return 'assets/characters/chee_chai_chee/intro.mp4';
      default:
        return null;
    }
  }

  bool _tierCanSelectCharacter({
    required String tier,
    required String characterId,
  }) {
    final normalizedCharacterId = normalizeKorlixCharacterId(characterId);

    if (tier == 'enterprise' || tier == 'ultra') {
      return true;
    }

    if (tier == 'pro') {
      return ['jj', 'chee_chai_chee', 'phil'].contains(normalizedCharacterId);
    }

    return normalizedCharacterId == 'jj';
  }

  Future<bool> _selectCharacter(String characterId) async {
    final normalizedCharacterId = normalizeKorlixCharacterId(characterId);

    try {
      final response = await http.post(
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/characters/select',
        ),
        headers: _headers(),
        body: jsonEncode({'character_id': normalizedCharacterId}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        await _showKorlixNotice(
          title: 'Upgrade required',
          message:
              data['error']?.toString() ??
              'This character is not available on your current plan.',
        );
        return false;
      }

      kKorlixSelectedCharacterNotifier.value = normalizedCharacterId;

      await _showKorlixNotice(
        title: 'Character selected',
        message: 'Your Korlix AI character has been updated.',
      );

      return true;
    } catch (error) {
      await _showKorlixNotice(
        title: 'Character update failed',
        message: korlixFriendlyErrorMessage(error),
      );

      return false;
    }
  }

  Future<void> _openCharactersPanel({
    required String currentTier,
    required String selectedCharacterId,
    required List<dynamic> characters,
    required List<dynamic> characterAccess,
  }) async {
    final accessIds = characterAccess
        .whereType<Map>()
        .map((item) => item['character_id']?.toString())
        .whereType<String>()
        .map(normalizeKorlixCharacterId)
        .toSet();

    var selectedId = normalizeKorlixCharacterId(selectedCharacterId);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071B27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.88,
                minChildSize: 0.45,
                maxChildSize: 0.96,
                builder: (context, controller) {
                  return ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(22),
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/branding/korlix_mini_mark.png',
                            height: 38,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Korlix Characters',
                              style: TextStyle(
                                color: Color(0xFFE4EBEE),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Intro videos autoplay muted. Tap Select to choose an available character. Locked characters stay visible so you can preview what higher tiers unlock.',
                        style: TextStyle(
                          color: Color(0xFFA9C6CF),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ...characters.map((raw) {
                        final character = (raw as Map).cast<String, dynamic>();
                        final rawId = character['id']?.toString() ?? '';
                        final id = normalizeKorlixCharacterId(rawId);
                        final name =
                            character['name']?.toString() ?? 'Korlix Character';
                        final description =
                            character['description']?.toString() ?? '';
                        final tierRequired =
                            character['tier_required']?.toString() ?? 'basic';
                        final isActive = character['is_active'] == true;
                        final comingSoon = character['is_coming_soon'] == true;
                        final selected =
                            normalizeKorlixCharacterId(id) ==
                            normalizeKorlixCharacterId(selectedId);
                        final tierAllows = _tierCanSelectCharacter(
                          tier: currentTier,
                          characterId: id,
                        );
                        final explicitlyGranted = accessIds.contains(id);
                        final available =
                            isActive && (tierAllows || explicitlyGranted);
                        final accent = _tierAccent(tierRequired);
                        final videoAsset = _characterIntroAsset(id);

                        String status;

                        if (selected) {
                          status = 'Selected';
                        } else if (comingSoon) {
                          status = 'Coming soon';
                        } else if (available) {
                          status = 'Available';
                        } else {
                          status = 'Locked';
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.24),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF69D9E8).withOpacity(0.78)
                                  : accent.withOpacity(0.30),
                              width: selected ? 1.3 : 1,
                            ),
                            boxShadow: [
                              if (selected)
                                BoxShadow(
                                  color: const Color(
                                    0xFF69D9E8,
                                  ).withOpacity(0.18),
                                  blurRadius: 22,
                                  spreadRadius: 2,
                                ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 96,
                                child: videoAsset == null
                                    ? Container(
                                        height: 150,
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: accent.withOpacity(0.45),
                                          ),
                                        ),
                                        child: Icon(
                                          comingSoon
                                              ? Icons.hourglass_top_rounded
                                              : Icons.person_rounded,
                                          color: accent,
                                          size: 32,
                                        ),
                                      )
                                    : KorlixCharacterIntroPreview(
                                        assetPath: videoAsset,
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              color: Color(0xFFE4EBEE),
                                              fontSize: 17,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: accent.withOpacity(0.40),
                                            ),
                                          ),
                                          child: Text(
                                            status,
                                            style: const TextStyle(
                                              color: Color(0xFFE4EBEE),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      description,
                                      style: const TextStyle(
                                        color: Color(0xFFA9C6CF),
                                        fontSize: 12.5,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Required tier: ${_tierLabel(tierRequired)}',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: selected || comingSoon
                                            ? null
                                            : () async {
                                                if (!available) {
                                                  await _showKorlixNotice(
                                                    title: 'Upgrade required',
                                                    message:
                                                        '$name is available on ${_tierLabel(tierRequired)} and higher.',
                                                  );
                                                  return;
                                                }

                                                final success =
                                                    await _selectCharacter(id);

                                                if (success) {
                                                  setModalState(() {
                                                    selectedId = id;
                                                  });
                                                }
                                              },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: available
                                              ? const Color(0xFF143B4A)
                                              : const Color(0xFF334155),
                                          foregroundColor: const Color(
                                            0xFFE4EBEE,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          selected
                                              ? 'Selected'
                                              : comingSoon
                                              ? 'Coming soon'
                                              : available
                                              ? 'Select'
                                              : 'Upgrade',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openComingSoonPanel() async {
    await _showKorlixNotice(
      title: 'Coming Soon',
      message:
          'New Korlix AI features are being prepared, including advanced video generation, music production add-ons, more characters, and enterprise tools.',
    );
  }

  String _themeLabel(String theme) {
    return korlixThemeLabelFor(theme);
  }

  Future<void> _setTheme({required String theme}) async {
    kKorlixThemeNotifier.value = korlixNormalizeSkinId(theme);

    if (mounted) {
      setState(() {}); // rebuild current screen for global skin
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('korlix_ui_theme', korlixNormalizeSkinId(theme));

    try {
      await http.post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/theme/set'),
        headers: KorlixDeviceStore.headers(),
        body: jsonEncode({'theme': korlixNormalizeSkinId(theme)}),
      );
    } catch (_) {
      // Local persistence is enough for the frontend theme switcher.
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      korlixThemeAppliedSnackBar(korlixNormalizeSkinId(theme)),
    );
  }

  Future<void> _openThemePanel({
    required String currentTheme,
    String? currentTier,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: korlixSkinPaletteFor(
        kKorlixThemeNotifier.value,
      ).panelDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        final activeSkin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

        final skinIds = <String>[
          'korlix_blue',
          'matrix_green',
          'ultra_gold',
          'pink_white',
          'dark_crimson',
          'white_gray',
        ];

        Widget themeTile(String theme) {
          final tileSkin = korlixSkinPaletteFor(theme);
          final selected =
              korlixNormalizeSkinId(kKorlixThemeNotifier.value) == tileSkin.id;

          return ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tileSkin.primary,
                    tileSkin.secondary,
                    tileSkin.panel,
                  ],
                ),
                border: Border.all(
                  color: selected
                      ? activeSkin.text
                      : tileSkin.border.withOpacity(0.40),
                  width: selected ? 2.2 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tileSkin.glow.withOpacity(selected ? 0.42 : 0.16),
                    blurRadius: selected ? 18 : 10,
                    spreadRadius: selected ? 1.2 : 0,
                  ),
                ],
              ),
            ),
            title: Text(
              tileSkin.label,
              style: TextStyle(
                color: activeSkin.text,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              selected ? 'Active skin' : 'Tap to apply',
              style: TextStyle(
                color: activeSkin.mutedText.withOpacity(0.82),
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: selected
                ? Icon(Icons.check_circle_rounded, color: tileSkin.primary)
                : Icon(
                    Icons.chevron_right_rounded,
                    color: activeSkin.mutedText,
                  ),
            onTap: () async {
              Navigator.of(context).pop();
              await _setTheme(theme: tileSkin.id);
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: activeSkin.mutedText.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Color Theme',
                  style: TextStyle(
                    color: activeSkin.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose one of the six full frontend skins.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: activeSkin.mutedText,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                ...skinIds.map(themeTile),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPanel() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final meResponse = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/me'),
        headers: _headers(),
      );

      final historyResponse = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/history'),
        headers: _headers(),
      );

      final meData = jsonDecode(meResponse.body) as Map<String, dynamic>;
      final historyData =
          jsonDecode(historyResponse.body) as Map<String, dynamic>;

      if (meResponse.statusCode >= 400) {
        throw Exception(meData['error'] ?? 'Could not load account.');
      }

      if (historyResponse.statusCode >= 400) {
        throw Exception(historyData['error'] ?? 'Could not load history.');
      }

      if (!mounted) {
        return;
      }

      final profile =
          (meData['profile'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final usage =
          (meData['usage'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final limits =
          (meData['limits'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final history = (historyData['history'] as List?) ?? [];
      final characters = (meData['characters'] as List?) ?? [];
      final characterAccess = (meData['characterAccess'] as List?) ?? [];

      final tier = (profile['tier'] ?? 'basic').toString();
      final dailyLimit = _asInt(limits['dailyRequestLimit']);
      final usedToday =
          _asInt(usage['standard_generations']) +
          _asInt(usage['live_search_generations']) +
          _asInt(usage['pdf_generations']);
      final remaining = dailyLimit <= 0
          ? 0
          : ((dailyLimit - usedToday) < 0 ? 0 : dailyLimit - usedToday);

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF071B27),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) {
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              builder: (context, controller) {
                return ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(22),
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/branding/korlix_mini_mark.png',
                          height: 38,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Korlix Account',
                            style: TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF2EC7DF).withOpacity(0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tier.toUpperCase()} PLAN',
                            style: const TextStyle(
                              color: Color(0xFF69D9E8),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dailyLimit > 0
                                ? '$remaining of $dailyLimit daily generations remaining'
                                : 'Custom usage limits',
                            style: const TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Signed in as ${kKorlixUserEmail ?? 'Korlix user'}',
                            style: const TextStyle(
                              color: Color(0xFFA9C6CF),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _openPlansPanel(currentTier: tier),
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('View plans / upgrade'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF143B4A),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => _openCharactersPanel(
                        currentTier: tier,
                        selectedCharacterId:
                            (profile['selected_character'] ?? 'jj').toString(),
                        characters: characters,
                        characterAccess: characterAccess,
                      ),
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('View characters'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0A2B3D),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _openComingSoonPanel,
                      icon: const Icon(Icons.upcoming_rounded),
                      label: const Text('Coming Soon'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF143B4A),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openThemePanel(
                        currentTier: tier,
                        currentTheme:
                            (profile['preferred_theme'] ?? 'korlix_blue')
                                .toString(),
                      ),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Color Theme'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tier == 'ultra' || tier == 'enterprise'
                            ? const Color(0xFFFFD166)
                            : const Color(0xFFA9C6CF),
                        side: BorderSide(
                          color:
                              (tier == 'ultra' || tier == 'enterprise'
                                      ? const Color(0xFFFFD166)
                                      : const Color(0xFFA9C6CF))
                                  .withOpacity(0.50),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _requestAccountDeletion,
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('Request account deletion'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(
                          color: Colors.redAccent.withOpacity(0.55),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Saved Settings',
                      style: TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (history.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          'No saved generations yet.',
                          style: TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                      )
                    else
                      ...history.take(20).map((item) {
                        final row = (item as Map).cast<String, dynamic>();
                        final prompt = (row['prompt'] ?? '').toString();
                        final response = (row['response'] ?? '').toString();
                        final resultType = (row['result_type'] ?? 'answer')
                            .toString()
                            .toUpperCase();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF2EC7DF).withOpacity(0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resultType,
                                style: const TextStyle(
                                  color: Color(0xFF69D9E8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                prompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFE4EBEE),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                response,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFA9C6CF),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _reportHistoryItem(
                                    generationId: row['id']?.toString(),
                                    prompt: prompt,
                                  ),
                                  icon: const Icon(
                                    Icons.flag_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('Report Output'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF69D9E8),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _showKorlixNotice(
        title: 'Account panel failed',
        message: _cleanError(error),
        danger: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _loading ? null : _openPanel,
      icon: _loading
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF69D9E8),
              ),
            )
          : const Icon(Icons.settings_rounded, size: 18),
      label: const Text('Settings'),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE4EBEE),
        backgroundColor: Colors.black.withOpacity(0.32),
      ),
    );
  }
}

const String kKorlixCreateVideoPrompt = r"""
Create a flawless, ultra-clean cinematic video masterpiece in 4K resolution at 24 frames per second, shot on ARRI Alexa 65 with anamorphic lenses and mastered for IMAX.

[Insert your detailed scene description here — be specific about what is happening, who or what is in the frame, the environment, time of day, emotion/mood, and key actions. Example: “A lone female cybernetic detective stands on a rain-slicked neon rooftop in a futuristic Tokyo night, coat fluttering in the wind as holographic billboards reflect in puddles below her.”]

Use world-class cinematography and directing techniques inspired by Roger Deakins, Hoyte van Hoytema, and Christopher Nolan. Apply smooth, deliberate camera movements — slow dolly zooms, elegant crane shots, subtle parallax tracking, and perfectly timed reveals — never shaky or amateur.

Lighting must be cinematic and dramatic: rich volumetric god rays, soft practical sources, beautiful rim lighting, and subtle lens flares that feel organic and expensive. Color grade the footage with a premium Hollywood LUT — balanced contrast, deep blacks, vibrant yet natural colors, and cinematic teal-orange or cool desaturated tones depending on the mood.

Render in hyper-realistic photorealism with perfect physics, realistic motion blur, natural depth of field, razor-sharp details, and zero artifacts, noise, or AI glitches. Composition follows the rule of thirds and golden ratio for maximum visual impact. Include subtle film grain and anamorphic lens characteristics for authentic big-budget film texture.

The final video must look and feel like a $200 million blockbuster trailer — clean, immersive, emotionally powerful, and undeniably world-class in every single frame.

Duration: [specify desired length, e.g., 8–12 seconds].

Aspect ratio: 16:9 cinematic widescreen.
""";

class KorlixSkinPalette {
  final String id;
  final String label;
  final bool isLight;

  final Color backgroundTop;
  final Color backgroundMid;
  final Color backgroundBottom;

  final Color panel;
  final Color panelSoft;
  final Color panelDeep;
  final Color inputFill;
  final Color buttonFill;

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color border;
  final Color glow;

  final Color text;
  final Color mutedText;
  final Color hintText;
  final Color textOnAccent;

  final Color success;
  final Color danger;
  final Color premium;

  const KorlixSkinPalette({
    required this.id,
    required this.label,
    required this.isLight,
    required this.backgroundTop,
    required this.backgroundMid,
    required this.backgroundBottom,
    required this.panel,
    required this.panelSoft,
    required this.panelDeep,
    required this.inputFill,
    required this.buttonFill,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.border,
    required this.glow,
    required this.text,
    required this.mutedText,
    required this.hintText,
    required this.textOnAccent,
    required this.success,
    required this.danger,
    required this.premium,
  });
}

String korlixNormalizeSkinId(String theme) {
  final id = theme.trim().toLowerCase();

  switch (id) {
    case 'blue':
    case 'korlix':
    case 'korlix_blue_neon':
    case 'korlix_blue':
      return 'korlix_blue';

    case 'green':
    case 'matrix':
    case 'purple_green':
    case 'cyber_purple':
    case 'matrix_green':
      return 'matrix_green';

    case 'gold':
    case 'black_gold':
    case 'gold_black':
    case 'ultra_gold':
      return 'ultra_gold';

    case 'pink':
    case 'pink_luxe':
    case 'pink_white':
      return 'pink_white';

    case 'crimson':
    case 'red_ice':
    case 'dark_crimson':
      return 'dark_crimson';

    case 'white':
    case 'gray':
    case 'silver':
    case 'black_white':
    case 'white_gray':
      return 'white_gray';

    default:
      return 'korlix_blue';
  }
}

KorlixSkinPalette korlixSkinPaletteFor(String theme) {
  switch (korlixNormalizeSkinId(theme)) {
    case 'matrix_green':
      return const KorlixSkinPalette(
        id: 'matrix_green',
        label: 'Matrix Green',
        isLight: false,
        backgroundTop: Color(0xFF06010B),
        backgroundMid: Color(0xFF170022),
        backgroundBottom: Color(0xFF08030F),
        panel: Color(0xFF13051E),
        panelSoft: Color(0xFF1E0930),
        panelDeep: Color(0xFF08030F),
        inputFill: Color(0xFF190820),
        buttonFill: Color(0xFF110817),
        primary: Color(0xFF7CFF6B),
        secondary: Color(0xFFB794F4),
        tertiary: Color(0xFF1CE66D),
        border: Color(0xFF7CFF6B),
        glow: Color(0xFF7CFF6B),
        text: Color(0xFFF3FBFF),
        mutedText: Color(0xFFC8F7C4),
        hintText: Color(0xFFD7C9EA),
        textOnAccent: Color(0xFF061008),
        success: Color(0xFFB7FF00),
        danger: Color(0xFFFF4D6D),
        premium: Color(0xFFB7FF00),
      );

    case 'ultra_gold':
      return const KorlixSkinPalette(
        id: 'ultra_gold',
        label: 'Black / Gold Ultra',
        isLight: false,
        backgroundTop: Color(0xFF050503),
        backgroundMid: Color(0xFF111009),
        backgroundBottom: Color(0xFF050504),
        panel: Color(0xFF0C0B07),
        panelSoft: Color(0xFF19130A),
        panelDeep: Color(0xFF030302),
        inputFill: Color(0xFF11100B),
        buttonFill: Color(0xFF0D0C08),
        primary: Color(0xFFFFD166),
        secondary: Color(0xFFFFB000),
        tertiary: Color(0xFFFFE8A3),
        border: Color(0xFFFFD166),
        glow: Color(0xFFFFB000),
        text: Color(0xFFFFF1C2),
        mutedText: Color(0xFFD8B963),
        hintText: Color(0xFFE7C46F),
        textOnAccent: Color(0xFF080704),
        success: Color(0xFFFFD166),
        danger: Color(0xFFFF5C5C),
        premium: Color(0xFFFFD166),
      );

    case 'pink_white':
      return const KorlixSkinPalette(
        id: 'pink_white',
        label: 'Pink / White Luxe',
        isLight: true,
        backgroundTop: Color(0xFFFFF8FC),
        backgroundMid: Color(0xFFFFEEF6),
        backgroundBottom: Color(0xFFFFFBFD),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFFFF3F9),
        panelDeep: Color(0xFFFFE7F2),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFFFFBFD),
        primary: Color(0xFFFF7AB8),
        secondary: Color(0xFFE83E8C),
        tertiary: Color(0xFFFFB7D8),
        border: Color(0xFFFF7AB8),
        glow: Color(0xFFFF7AB8),
        text: Color(0xFF63122F),
        mutedText: Color(0xFF8B4964),
        hintText: Color(0xFF8D6C7A),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFFE83E8C),
        danger: Color(0xFFD92D20),
        premium: Color(0xFFE83E8C),
      );

    case 'dark_crimson':
      return const KorlixSkinPalette(
        id: 'dark_crimson',
        label: 'Crimson / Ice',
        isLight: false,
        backgroundTop: Color(0xFF120205),
        backgroundMid: Color(0xFF27050D),
        backgroundBottom: Color(0xFF050308),
        panel: Color(0xFF1B060C),
        panelSoft: Color(0xFF2A0811),
        panelDeep: Color(0xFF090306),
        inputFill: Color(0xFF12090E),
        buttonFill: Color(0xFF0C070B),
        primary: Color(0xFFB7F3FF),
        secondary: Color(0xFFFF5C7A),
        tertiary: Color(0xFFFFFFFF),
        border: Color(0xFFB7F3FF),
        glow: Color(0xFFFF5C7A),
        text: Color(0xFFF3FBFF),
        mutedText: Color(0xFFFFB3C1),
        hintText: Color(0xFFDCEEFF),
        textOnAccent: Color(0xFF120205),
        success: Color(0xFFB7F3FF),
        danger: Color(0xFFFF5C7A),
        premium: Color(0xFFFF5C7A),
      );

    case 'white_gray':
      return const KorlixSkinPalette(
        id: 'white_gray',
        label: 'White / Gray Cyber',
        isLight: true,
        backgroundTop: Color(0xFFF8FBFD),
        backgroundMid: Color(0xFFEFF4F7),
        backgroundBottom: Color(0xFFFFFFFF),
        panel: Color(0xFFF9FCFE),
        panelSoft: Color(0xFFFFFFFF),
        panelDeep: Color(0xFFE6EEF3),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFF5F8FA),
        primary: Color(0xFF69D9E8),
        secondary: Color(0xFF8B95A1),
        tertiary: Color(0xFFB8DDE6),
        border: Color(0xFF9FDCE7),
        glow: Color(0xFFBDEFFF),
        text: Color(0xFF10202C),
        mutedText: Color(0xFF60707B),
        hintText: Color(0xFF6F7C86),
        textOnAccent: Color(0xFF071B27),
        success: Color(0xFF69D9E8),
        danger: Color(0xFFE5484D),
        premium: Color(0xFF69D9E8),
      );

    case 'korlix_blue':
    default:
      return const KorlixSkinPalette(
        id: 'korlix_blue',
        label: 'Korlix Blue Neon',
        isLight: false,
        backgroundTop: Color(0xFF040612),
        backgroundMid: Color(0xFF10173A),
        backgroundBottom: Color(0xFF250032),
        panel: Color(0xFF071B27),
        panelSoft: Color(0xFF0C2844),
        panelDeep: Color(0xFF07111F),
        inputFill: Color(0xFF08101F),
        buttonFill: Color(0xFF07111D),
        primary: Color(0xFF69D9E8),
        secondary: Color(0xFFFF4AF3),
        tertiary: Color(0xFF2D8CFF),
        border: Color(0xFF2EC7DF),
        glow: Color(0xFF6DF7FF),
        text: Color(0xFFE4EBEE),
        mutedText: Color(0xFFA9C6CF),
        hintText: Color(0xFFD3D9EA),
        textOnAccent: Color(0xFF061008),
        success: Color(0xFFB7FF00),
        danger: Color(0xFFFF5C7A),
        premium: Color(0xFFFFD166),
      );
  }
}

String korlixThemeLabelFor(String theme) {
  return korlixSkinPaletteFor(theme).label;
}

bool korlixThemeIsLight(String theme) {
  return korlixSkinPaletteFor(theme).isLight;
}

Color korlixThemeAccentFor(String theme) {
  return korlixSkinPaletteFor(theme).primary;
}

Color korlixThemePanelFor(String theme) {
  return korlixSkinPaletteFor(theme).panel;
}

Color korlixThemeSecondaryFor(String theme) {
  return korlixSkinPaletteFor(theme).secondary;
}

Color korlixThemeBorderFor(String theme) {
  return korlixSkinPaletteFor(theme).border;
}

Color korlixThemeTextFor(String theme) {
  return korlixSkinPaletteFor(theme).text;
}

Color korlixThemeMutedTextFor(String theme) {
  return korlixSkinPaletteFor(theme).mutedText;
}

List<Color> korlixThemeBackgroundFor(String theme) {
  final skin = korlixSkinPaletteFor(theme);

  return <Color>[skin.backgroundTop, skin.backgroundMid, skin.backgroundBottom];
}

SnackBar korlixThemeAppliedSnackBar(String theme) {
  final normalizedTheme = korlixNormalizeSkinId(theme);
  final skin = korlixSkinPaletteFor(normalizedTheme);

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1600),
    elevation: 0,
    backgroundColor: Colors.transparent,
    margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
    padding: EdgeInsets.zero,
    content: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.panelDeep.withValues(alpha: skin.isLight ? 0.94 : 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: skin.border.withValues(alpha: skin.isLight ? 0.54 : 0.62),
          width: 1.05,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.glow.withValues(alpha: skin.isLight ? 0.14 : 0.24),
            blurRadius: 18,
            spreadRadius: 0.5,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [skin.primary, skin.secondary, skin.panelDeep],
              ),
              border: Border.all(
                color: skin.text.withValues(alpha: skin.isLight ? 0.42 : 0.34),
              ),
            ),
            child: Icon(
              Icons.palette_rounded,
              color: skin.textOnAccent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Theme applied: ${korlixThemeLabelFor(normalizedTheme)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.text,
                fontSize: 13.2,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final ValueNotifier<String> kKorlixThemeNotifier = ValueNotifier<String>(
  'korlix_blue',
);

final ValueNotifier<String> kKorlixSelectedCharacterNotifier =
    ValueNotifier<String>('jj');

String normalizeKorlixCharacterId(String? id) {
  final raw = (id ?? '').trim().toLowerCase();

  if (raw.isEmpty) {
    return 'jj';
  }

  final normalized = raw.replaceAll('-', '_').replaceAll(' ', '_');

  switch (normalized) {
    case 'ji_a':
    case 'jia':
      return 'ji_a';
    case 'chee_chai_chee':
    case 'cheechai':
    case 'cheechaichee':
      return 'chee_chai_chee';
    case 'jj':
    case 'phil':
    case 'yuna':
    case 'enterprise':
      return normalized;
    default:
      return normalized;
  }
}

class KorlixCharacterDisplayData {
  final String id;
  final String name;
  final String eyebrow;
  final String description;
  final String assetPath;
  final bool soundOn;

  const KorlixCharacterDisplayData({
    required this.id,
    required this.name,
    required this.eyebrow,
    required this.description,
    required this.assetPath,
    this.soundOn = false,
  });
}

KorlixCharacterDisplayData korlixCharacterDisplayFor(String id) {
  switch (normalizeKorlixCharacterId(id)) {
    case 'chee_chai_chee':
      return const KorlixCharacterDisplayData(
        id: 'chee_chai_chee',
        name: 'Chee Chai Chee',
        eyebrow: 'PRO AI CHARACTER',
        description:
            'A dark cyber-mystic wizard built for strategy, wisdom, and powerful answers.',
        assetPath: 'assets/characters/chee_chai_chee/intro.mp4',
        soundOn: true,
      );
    case 'phil':
      return const KorlixCharacterDisplayData(
        id: 'phil',
        name: 'Phil',
        eyebrow: 'PRO AI CHARACTER',
        description:
            'Helpful, clear, and easy to talk to. Phil helps you get things done.',
        assetPath: 'assets/characters/phil/intro.mp4',
        soundOn: true,
      );
    case 'yuna':
      return const KorlixCharacterDisplayData(
        id: 'yuna',
        name: 'Yuna',
        eyebrow: 'ULTRA PREMIUM CHARACTER',
        description:
            'Elegant, creative, and strategic. Yuna is built for premium-level ideas.',
        assetPath: 'assets/characters/yuna/intro.mp4',
        soundOn: true,
      );
    case 'ji_a':
      return const KorlixCharacterDisplayData(
        id: 'ji_a',
        name: 'Ji-A',
        eyebrow: 'ULTRA PREMIUM CHARACTER',
        description:
            'A premium AI character built for focused, cinematic, high-value assistance.',
        assetPath: 'assets/characters/ji-a/intro.mp4',
        soundOn: true,
      );
    case 'jj':
    default:
      return const KorlixCharacterDisplayData(
        id: 'jj',
        name: 'JJ',
        eyebrow: 'FEATURED AI CHARACTER',
        description:
            'Curious, thoughtful, and always ready to chat. Ask JJ anything!',
        assetPath: 'assets/characters/jj/intro.mp4',
        soundOn: true,
      );
  }
}

class QuickAction {
  final String label;
  final String prompt;

  const QuickAction({required this.label, required this.prompt});
}

class LanguageCopy {
  final String code;
  final String label;
  final String assetPath;
  final String appSubtitle;
  final String backendConnected;
  final String awaitingTitle;
  final String awaitingSubtitle;
  final String awakenText;
  final String replayGreeting;
  final String reloadWizard;
  final String askCreateTitle;
  final String commandHint;
  final String askButton;
  final String thinkingButton;
  final String matrixMessage;
  final String resultsTitle;
  final String open;
  final String copy;
  final String delete;
  final String clearAll;
  final String pdf;
  final String exportPdf;
  final String close;
  final String cancel;
  final String commandEmpty;
  final String createError;
  final String pdfError;
  final String preparing;
  final String generatedBy;
  final String originalCommand;
  final String copied;
  final String deleted;
  final String cleared;
  final String clearConfirmTitle;
  final String clearConfirmMessage;
  final String answerBadge;
  final String fileBadge;
  final String considerDone;
  final List<QuickAction> quickActions;

  const LanguageCopy({
    required this.code,
    required this.label,
    required this.assetPath,
    required this.appSubtitle,
    required this.backendConnected,
    required this.awaitingTitle,
    required this.awaitingSubtitle,
    required this.awakenText,
    required this.replayGreeting,
    required this.reloadWizard,
    required this.askCreateTitle,
    required this.commandHint,
    required this.askButton,
    required this.thinkingButton,
    required this.matrixMessage,
    required this.resultsTitle,
    required this.open,
    required this.copy,
    required this.delete,
    required this.clearAll,
    required this.pdf,
    required this.exportPdf,
    required this.close,
    required this.cancel,
    required this.commandEmpty,
    required this.createError,
    required this.pdfError,
    required this.preparing,
    required this.generatedBy,
    required this.originalCommand,
    required this.copied,
    required this.deleted,
    required this.cleared,
    required this.clearConfirmTitle,
    required this.clearConfirmMessage,
    required this.answerBadge,
    required this.fileBadge,
    required this.considerDone,
    required this.quickActions,
  });
}

class AppLanguages {
  static const List<LanguageCopy> all = [
    LanguageCopy(
      code: 'en',
      label: 'English',
      assetPath: 'assets/characters/chee_chai_chee/intro.mp4',
      appSubtitle: 'Choose your AI character. Ask anything. Create anything.',
      backendConnected: 'Korlix System Online',
      awaitingTitle: 'Chee Chai Chee awaits.',
      awaitingSubtitle: 'Tap once to awaken the wizard.',
      awakenText: 'Select Character',
      replayGreeting: 'Replay Greeting',
      reloadWizard: 'Reload Wizard',
      askCreateTitle: 'Ask or create anything',
      commandHint: 'Ask a question or type what you want created...',
      askButton: 'Ask',
      thinkingButton: 'Reading the matrix...',
      matrixMessage: 'Chee Chai Chee is reading the data stream.',
      resultsTitle: 'Results',
      open: 'Open',
      copy: 'Copy',
      delete: 'Delete',
      clearAll: 'Clear All',
      pdf: 'PDF',
      exportPdf: 'Export PDF',
      close: 'Close',
      cancel: 'Cancel',
      commandEmpty: 'Type a question or command first.',
      createError: 'Creation failed. Try again in a moment.',
      pdfError: 'PDF export failed. Try again.',
      preparing: 'Preparing English...',
      generatedBy: 'Generated by Chee Chai Chee',
      originalCommand: 'Original command',
      copied: 'Copied to clipboard.',
      deleted: 'Result deleted.',
      cleared: 'Results cleared.',
      clearConfirmTitle: 'Clear all results?',
      clearConfirmMessage: 'This will remove all results from this session.',
      answerBadge: 'Answer',
      fileBadge: 'File',
      considerDone: 'Consider it done.',
      quickActions: [
        QuickAction(
          label: 'Improve my picture',
          prompt:
              'Transform this image into a breathtaking professional photograph captured by a world-class photographer. Cinematic composition with masterful framing, perfect balance, and strong visual storytelling. Flawless cinematic lighting with soft, flattering key light, gentle natural fill, elegant rim lighting for beautiful subject separation, and subtle volumetric atmosphere. Photorealistic skin tones with accurate, lifelike coloration, natural subsurface scattering, realistic skin texture, visible pores, and authentic micro-details while maintaining a natural, believable appearance. Razor-sharp focus on the eyes and key facial features, with a dreamy shallow depth of field and creamy, smooth bokeh in the background. Exceptional fine detail in individual hair strands, fabric textures, and environmental elements. High dynamic range with rich tonal gradation, deep yet detailed shadows, and luminous highlights without clipping. Sophisticated cinematic color grading with natural yet refined vibrancy and filmic contrast. Shot on a high-end full-frame camera (Sony A1 or Canon EOS R5) using an 85mm f/1.4 prime lens at f/1.8–f/2.2. Ultra-photorealistic, hyper-detailed, 8K resolution, award-winning photography quality, emotionally evocative, timeless masterpiece, National Geographic / high-fashion editorial level.',
        ),
        QuickAction(
          label: 'Write my Resume',
          prompt:
              r'''You are an expert professional resume writer and modern resume designer with 15+ years of experience creating resumes for executives, professionals, and career changers. Your resumes are known for being both **highly effective (ATS-friendly + achievement-driven)** and **aesthetically excellent** — clean, modern, visually balanced, and premium-looking.

Before you write or design anything, you must first gather the necessary information by asking me questions.

Ask me all the questions below in a clean, organized bullet-point format. Do **not** generate the resume until I have answered your questions.

### Questions you must ask me:

**Personal & Contact Information**
- What is your full name as you want it to appear on the resume?
- What is your phone number, professional email address, city and state (or country), and LinkedIn URL or personal website/portfolio (if any)?

**Target Role**
- What specific job title or role are you targeting? What industry or company type are you applying to? (If you have a job description, please paste it.)

**Professional Experience**
- Please list your work experience in reverse chronological order. For each position, provide: Job title, Company name, Location, Employment dates (Month/Year – Month/Year), and 4–6 strong bullet points describing your responsibilities and achievements (ideally with numbers, percentages, or results).

**Education**
- What is your educational background? Please include degree(s), major/field of study, school/university name, graduation year, and any honors, GPA (if above 3.5), or relevant coursework.

**Skills, Tools & Certifications**
- What are your strongest technical/hard skills and tools/software you’re proficient in?
- What soft skills or leadership qualities do you want to highlight?
- Do you have any certifications, licenses, or professional development worth including?

**Additional Sections**
- Do you have any notable projects, volunteer work, publications, awards, speaking engagements, or leadership roles outside of work that should be included?
- Are there any employment gaps, career transitions, or specific situations you want me to handle strategically?

**Design & Formatting Preferences**
- Do you prefer a **1-page** or **2-page** resume?
- What design style do you like? (Examples: Modern minimalist, Clean corporate, Slightly creative, Premium executive, Tech-focused, etc.)
- Any preferred color scheme or accent color? (I usually recommend elegant, professional palettes like deep navy + charcoal, teal accents, or sophisticated gray + black.)
- Any sections you specifically want or don’t want on the resume?

**Final Instructions**
- Once I answer all your questions, create a **visually stunning, modern, and aesthetically pleasing resume**.
- Use excellent visual hierarchy, generous but balanced white space, professional typography, and a clean layout that looks premium (not generic or outdated).
- Make every bullet point achievement-oriented and results-driven.
- Ensure the resume is ATS-friendly while still looking beautiful.
- Present the final resume in well-formatted Markdown that I can easily copy into a design tool or convert to PDF.
- Offer 2–3 different layout/style variations if appropriate.

Start by asking me the questions now.''',
        ),
        QuickAction(
          label: 'Email enhancer',
          prompt:
              r'''You are an expert at writing clear, professional, and effective emails. First ask me:
- Who is the recipient and what’s our relationship?
- What’s the main purpose of the email?
- Any specific points or tone I want (friendly, firm, persuasive, apologetic, etc.)

Then write a polished email with a good subject line and clear call-to-action.''',
        ),
        QuickAction(
          label: 'Study / learn',
          prompt: 'Create a study guide for ',
        ),
        QuickAction(
          label: 'Fix My Credit Report',
          prompt:
              r'''You are a senior FCRA/FDCPA credit repair strategist and consumer rights expert with deep knowledge of the Fair Credit Reporting Act (15 U.S.C. §§ 1681–1681x), Fair Debt Collection Practices Act (15 U.S.C. § 1692 et seq.), Regulation V, FACTA, and current CFPB enforcement standards. You specialize in creating aggressive yet fully compliant credit repair strategies that maximize deletions while remaining legally sound.

**IMPORTANT USER INSTRUCTION (display this clearly):**
Please attach your full credit reports from AnnualCreditReport.com and/or directly from Equifax, Experian, and TransUnion before proceeding. The more complete the reports (including all tradelines, collections, and account details), the more powerful and targeted the strategy and letters will be.

**Your Task:**
The user has attached their credit reports. Carefully analyze every page and extract all negative, inaccurate, outdated, unverifiable, or questionable items. Then generate a complete, professional, and potent credit repair package.

Create the following deliverables in this exact order:

### 1. Credit Report Analysis & Prioritized Strategy
- Summarize the current state of the credit reports across all three bureaus.
- Identify and list every negative item (late payments, collections, charge-offs, bankruptcies, inquiries, judgments, etc.) with:
  - Creditor / Collection agency name
  - Account number (last 4)
  - Date of first delinquency / Date reported
  - Current status
  - Which bureaus it appears on
- Create a **prioritized action plan** ranked by potential score impact and ease of removal.
- Include a 30/60/90-day timeline with clear milestones.

### 2. Complete Set of Ready-to-Send Letters
Generate professional, legally grounded letters for the following (customized based on the actual reports):

**A. Credit Bureau Dispute Letters** (one for each major issue or grouped strategically)
- Cite **15 U.S.C. § 1681i** (reinvestigation requirements) and **§ 1681e(b)** (reasonable procedures for accuracy).
- Demand a full investigation and Method of Verification (MOV).
- Clearly state why the information is inaccurate, incomplete, or unverifiable.
- Request deletion if the information cannot be verified within 30 days.

**B. Direct Dispute Letters to Furnishers** (per **15 U.S.C. § 1681s-2**)
- Send to the original creditors or collection agencies.
- Demand they investigate and correct or delete the information they are reporting.

**C. Debt Validation / Cease & Desist Letters** (for any collection accounts)
- Cite **FDCPA § 1692g**.
- Request full validation of the debt and demand they cease collection activity until verification is provided.

**D. 30-Day Follow-Up / Failure to Investigate Letters**
- Templates to send if a bureau or furnisher fails to respond properly within the legal timeline.

**E. Goodwill Letters** (for accurate but negative items the user may want removed through negotiation)

### 3. Escalation & Enforcement Templates
- Ready-to-use **CFPB complaint** language (for when bureaus or furnishers violate FCRA timelines or fail to investigate reasonably).
- State Attorney General complaint template.
- Instructions on when and how to escalate.

### 4. Record-Keeping & Documentation System
- Provide a simple tracking table format the user can use.
- Checklist of what to document (dates sent, certified mail receipts, responses received, etc.).
- Guidance on how to prove violations if needed for complaints or legal action.

### 5. Post-Repair Recommendations
- Steps to take immediately after successful deletions.
- Credit rebuilding strategy tailored to the user’s current situation.
- Warnings about what not to do (e.g., applying for new credit too soon).

**Letter Requirements:**
- All letters must be professional, factual, and assertive.
- Use precise legal citations where they strengthen the position.
- Never use threats, abusive language, or anything that could be considered harassment.
- Make each letter ready to print, sign, and mail via certified mail with return receipt requested.
- Clearly instruct the user on how and where to send each letter.

Analyze the attached credit reports thoroughly and produce a complete, high-impact credit repair package. Focus on maximum legal pressure while staying fully compliant with consumer protection laws.''',
        ),
        QuickAction(
          label: 'Imagine a picture',
          prompt: kKorlixImaginePicturePrompt,
        ),
        QuickAction(label: 'Create an App', prompt: 'Create an App'),
        QuickAction(label: 'Create a video', prompt: kKorlixCreateVideoPrompt),
      ],
    ),
    LanguageCopy(
      code: 'es',
      label: 'Español',
      assetPath: 'assets/characters/chee_chai_chee/intro.mp4',
      appSubtitle:
          'Elige tu personaje de IA. Pregunta cualquier cosa. Crea cualquier cosa.',
      backendConnected: 'Sistema Korlix en línea',
      awaitingTitle: 'Chee Chai Chee espera.',
      awaitingSubtitle: 'Toca una vez para despertar al mago.',
      awakenText: 'Despertar a Chee Chai Chee',
      replayGreeting: 'Repetir saludo',
      reloadWizard: 'Recargar mago',
      askCreateTitle: 'Pregunta o crea cualquier cosa',
      commandHint: 'Haz una pregunta o escribe lo que quieres crear...',
      askButton: 'Preguntar',
      thinkingButton: 'Leyendo la matriz...',
      matrixMessage: 'Chee Chai Chee está leyendo el flujo de datos.',
      resultsTitle: 'Resultados',
      open: 'Abrir',
      copy: 'Copiar',
      delete: 'Eliminar',
      clearAll: 'Borrar todo',
      pdf: 'PDF',
      exportPdf: 'Exportar PDF',
      close: 'Cerrar',
      cancel: 'Cancelar',
      commandEmpty: 'Escribe una pregunta o comando primero.',
      createError: 'La creación falló. Inténtalo de nuevo en un momento.',
      pdfError: 'La exportación del PDF falló. Inténtalo de nuevo.',
      preparing: 'Preparando español...',
      generatedBy: 'Generado por Chee Chai Chee',
      originalCommand: 'Comando original',
      copied: 'Copiado al portapapeles.',
      deleted: 'Resultado eliminado.',
      cleared: 'Resultados borrados.',
      clearConfirmTitle: '¿Borrar todos los resultados?',
      clearConfirmMessage:
          'Esto eliminará todos los resultados de esta sesión.',
      answerBadge: 'Respuesta',
      fileBadge: 'Archivo',
      considerDone: 'Considéralo hecho.',
      quickActions: [
        QuickAction(label: 'Preguntar', prompt: 'Responde esto claramente: '),
        QuickAction(
          label: 'Crear plan',
          prompt: 'Crea un plan paso a paso para ',
        ),
        QuickAction(
          label: 'Escribir',
          prompt: 'Escribe un texto pulido sobre ',
        ),
        QuickAction(
          label: 'Estudiar',
          prompt: 'Crea una guía de estudio para ',
        ),
        QuickAction(
          label: 'Negocios',
          prompt: 'Dame consejos prácticos de negocio para ',
        ),
        QuickAction(
          label: 'Ideas de contenido',
          prompt: 'Dame ideas de contenido para ',
        ),
      ],
    ),
    LanguageCopy(
      code: 'fr',
      label: 'Français',
      assetPath: 'assets/wizard_greeting_fr.mp4',
      appSubtitle:
          'Choisissez votre personnage IA. Posez n’importe quelle question. Créez n’importe quoi.',
      backendConnected: 'Système Korlix en ligne',
      awaitingTitle: 'Chee Chai Chee attend.',
      awaitingSubtitle: 'Touchez une fois pour réveiller le sorcier.',
      awakenText: 'Réveiller Chee Chai Chee',
      replayGreeting: 'Rejouer le salut',
      reloadWizard: 'Recharger le sorcier',
      askCreateTitle: 'Demandez ou créez n’importe quoi',
      commandHint: 'Posez une question ou tapez ce que vous voulez créer...',
      askButton: 'Demander',
      thinkingButton: 'Lecture de la matrice...',
      matrixMessage: 'Chee Chai Chee lit le flux de données.',
      resultsTitle: 'Résultats',
      open: 'Ouvrir',
      copy: 'Copier',
      delete: 'Supprimer',
      clearAll: 'Tout effacer',
      pdf: 'PDF',
      exportPdf: 'Exporter en PDF',
      close: 'Fermer',
      cancel: 'Annuler',
      commandEmpty: 'Tapez d’abord une question ou une commande.',
      createError: 'La création a échoué. Réessayez dans un instant.',
      pdfError: 'L’export PDF a échoué. Réessayez.',
      preparing: 'Préparation du français...',
      generatedBy: 'Généré par Chee Chai Chee',
      originalCommand: 'Commande originale',
      copied: 'Copié dans le presse-papiers.',
      deleted: 'Résultat supprimé.',
      cleared: 'Résultats effacés.',
      clearConfirmTitle: 'Effacer tous les résultats ?',
      clearConfirmMessage:
          'Cela supprimera tous les résultats de cette session.',
      answerBadge: 'Réponse',
      fileBadge: 'Fichier',
      considerDone: 'Considérez que c’est fait.',
      quickActions: [
        QuickAction(label: 'Demander', prompt: 'Réponds clairement à ceci : '),
        QuickAction(
          label: 'Rédiger mon CV',
          prompt:
              r'''You are an expert professional resume writer and modern resume designer with 15+ years of experience creating resumes for executives, professionals, and career changers. Your resumes are known for being both **highly effective (ATS-friendly + achievement-driven)** and **aesthetically excellent** — clean, modern, visually balanced, and premium-looking.

Before you write or design anything, you must first gather the necessary information by asking me questions.

Ask me all the questions below in a clean, organized bullet-point format. Do **not** generate the resume until I have answered your questions.

### Questions you must ask me:

**Personal & Contact Information**
- What is your full name as you want it to appear on the resume?
- What is your phone number, professional email address, city and state (or country), and LinkedIn URL or personal website/portfolio (if any)?

**Target Role**
- What specific job title or role are you targeting? What industry or company type are you applying to? (If you have a job description, please paste it.)

**Professional Experience**
- Please list your work experience in reverse chronological order. For each position, provide: Job title, Company name, Location, Employment dates (Month/Year – Month/Year), and 4–6 strong bullet points describing your responsibilities and achievements (ideally with numbers, percentages, or results).

**Education**
- What is your educational background? Please include degree(s), major/field of study, school/university name, graduation year, and any honors, GPA (if above 3.5), or relevant coursework.

**Skills, Tools & Certifications**
- What are your strongest technical/hard skills and tools/software you’re proficient in?
- What soft skills or leadership qualities do you want to highlight?
- Do you have any certifications, licenses, or professional development worth including?

**Additional Sections**
- Do you have any notable projects, volunteer work, publications, awards, speaking engagements, or leadership roles outside of work that should be included?
- Are there any employment gaps, career transitions, or specific situations you want me to handle strategically?

**Design & Formatting Preferences**
- Do you prefer a **1-page** or **2-page** resume?
- What design style do you like? (Examples: Modern minimalist, Clean corporate, Slightly creative, Premium executive, Tech-focused, etc.)
- Any preferred color scheme or accent color? (I usually recommend elegant, professional palettes like deep navy + charcoal, teal accents, or sophisticated gray + black.)
- Any sections you specifically want or don’t want on the resume?

**Final Instructions**
- Once I answer all your questions, create a **visually stunning, modern, and aesthetically pleasing resume**.
- Use excellent visual hierarchy, generous but balanced white space, professional typography, and a clean layout that looks premium (not generic or outdated).
- Make every bullet point achievement-oriented and results-driven.
- Ensure the resume is ATS-friendly while still looking beautiful.
- Present the final resume in well-formatted Markdown that I can easily copy into a design tool or convert to PDF.
- Offer 2–3 different layout/style variations if appropriate.

Start by asking me the questions now.''',
        ),
        QuickAction(
          label: 'Écrire',
          prompt: 'Rédige un texte professionnel sur ',
        ),
        QuickAction(label: 'Étudier', prompt: 'Crée un guide d’étude pour '),
        QuickAction(
          label: 'Fix My Credit Report',
          prompt:
              r'''You are a senior FCRA/FDCPA credit repair strategist and consumer rights expert with deep knowledge of the Fair Credit Reporting Act (15 U.S.C. §§ 1681–1681x), Fair Debt Collection Practices Act (15 U.S.C. § 1692 et seq.), Regulation V, FACTA, and current CFPB enforcement standards. You specialize in creating aggressive yet fully compliant credit repair strategies that maximize deletions while remaining legally sound.

**IMPORTANT USER INSTRUCTION (display this clearly):**
Please attach your full credit reports from AnnualCreditReport.com and/or directly from Equifax, Experian, and TransUnion before proceeding. The more complete the reports (including all tradelines, collections, and account details), the more powerful and targeted the strategy and letters will be.

**Your Task:**
The user has attached their credit reports. Carefully analyze every page and extract all negative, inaccurate, outdated, unverifiable, or questionable items. Then generate a complete, professional, and potent credit repair package.

Create the following deliverables in this exact order:

### 1. Credit Report Analysis & Prioritized Strategy
- Summarize the current state of the credit reports across all three bureaus.
- Identify and list every negative item (late payments, collections, charge-offs, bankruptcies, inquiries, judgments, etc.) with:
  - Creditor / Collection agency name
  - Account number (last 4)
  - Date of first delinquency / Date reported
  - Current status
  - Which bureaus it appears on
- Create a **prioritized action plan** ranked by potential score impact and ease of removal.
- Include a 30/60/90-day timeline with clear milestones.

### 2. Complete Set of Ready-to-Send Letters
Generate professional, legally grounded letters for the following (customized based on the actual reports):

**A. Credit Bureau Dispute Letters** (one for each major issue or grouped strategically)
- Cite **15 U.S.C. § 1681i** (reinvestigation requirements) and **§ 1681e(b)** (reasonable procedures for accuracy).
- Demand a full investigation and Method of Verification (MOV).
- Clearly state why the information is inaccurate, incomplete, or unverifiable.
- Request deletion if the information cannot be verified within 30 days.

**B. Direct Dispute Letters to Furnishers** (per **15 U.S.C. § 1681s-2**)
- Send to the original creditors or collection agencies.
- Demand they investigate and correct or delete the information they are reporting.

**C. Debt Validation / Cease & Desist Letters** (for any collection accounts)
- Cite **FDCPA § 1692g**.
- Request full validation of the debt and demand they cease collection activity until verification is provided.

**D. 30-Day Follow-Up / Failure to Investigate Letters**
- Templates to send if a bureau or furnisher fails to respond properly within the legal timeline.

**E. Goodwill Letters** (for accurate but negative items the user may want removed through negotiation)

### 3. Escalation & Enforcement Templates
- Ready-to-use **CFPB complaint** language (for when bureaus or furnishers violate FCRA timelines or fail to investigate reasonably).
- State Attorney General complaint template.
- Instructions on when and how to escalate.

### 4. Record-Keeping & Documentation System
- Provide a simple tracking table format the user can use.
- Checklist of what to document (dates sent, certified mail receipts, responses received, etc.).
- Guidance on how to prove violations if needed for complaints or legal action.

### 5. Post-Repair Recommendations
- Steps to take immediately after successful deletions.
- Credit rebuilding strategy tailored to the user’s current situation.
- Warnings about what not to do (e.g., applying for new credit too soon).

**Letter Requirements:**
- All letters must be professional, factual, and assertive.
- Use precise legal citations where they strengthen the position.
- Never use threats, abusive language, or anything that could be considered harassment.
- Make each letter ready to print, sign, and mail via certified mail with return receipt requested.
- Clearly instruct the user on how and where to send each letter.

Analyze the attached credit reports thoroughly and produce a complete, high-impact credit repair package. Focus on maximum legal pressure while staying fully compliant with consumer protection laws.''',
        ),
        QuickAction(
          label: 'Idées contenu',
          prompt: 'Donne-moi des idées de contenu pour ',
        ),
      ],
    ),
  ];

  static LanguageCopy byCode(String code) {
    return all.firstWhere((item) => item.code == code, orElse: () => all.first);
  }
}

class GeneratedItem {
  final String command;
  final String title;
  final String content;
  final String language;
  final bool allowPdf;
  final String? imageDataUrl;
  final String? imageUrl;

  const GeneratedItem({
    required this.command,
    required this.title,
    required this.content,
    required this.language,
    required this.allowPdf,
    this.imageDataUrl,
    this.imageUrl,
  });

  bool get hasImageResult =>
      (imageDataUrl != null && imageDataUrl!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
}

// ── ChatMessage: represents one turn in the persistent chat thread ──
class ChatMessage {
  final String userText;
  final String aiText;
  final bool isImage;
  final String? imageDataUrl;
  final String? imageUrl;
  final String language;
  final bool allowPdf;
  final GeneratedItem? generatedItem;
  final DateTime createdAt;
  // Credit dispute letter fields
  final bool isCreditDispute;
  final String? equifaxDocxBase64;
  final String? experianDocxBase64;
  final String? transunionDocxBase64;
  final String? consumerName;

  const ChatMessage({
    required this.userText,
    required this.aiText,
    this.isImage = false,
    this.imageDataUrl,
    this.imageUrl,
    required this.language,
    this.allowPdf = false,
    this.generatedItem,
    required this.createdAt,
    this.isCreditDispute = false,
    this.equifaxDocxBase64,
    this.experianDocxBase64,
    this.transunionDocxBase64,
    this.consumerName,
  });
}

// ── End ChatMessage ──

class KorlixLocalChatTopic {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  const KorlixLocalChatTopic({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  KorlixLocalChatTopic copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return KorlixLocalChatTopic(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }
}

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen>
    with WidgetsBindingObserver {
  bool _showSavedTopicsPanel = false;
  final ScrollController _savedTopicsScrollController = ScrollController();
  final TextEditingController _renameTopicController = TextEditingController();
  String? _renamingTopicId;

  // Demo topic list for the slide-out topic picker.
  // Later you can swap this to your real saved conversation titles.

  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _wizardCuePlayer = AudioPlayer();
  final speech_to_text.SpeechToText _speechToText =
      speech_to_text.SpeechToText();

  bool _loading = false;
  bool _selectedCharacterFetchStarted = false;
  bool _featuredAnswerDismissed = false;
  bool _createVideoMode = false;
  bool _improvePictureMode = false;
  String? _portraitStudioPromptOverride;
  bool _imaginePictureMode = false;
  bool _fixCreditReportMode = false;
  bool _creditDebtValidationRoundsVisible = false;
  int? _creditDebtValidationRound;

  bool _utilityPanelOpen = false;
  bool _enterpriseCopyboxArmed = false;
  bool _enterpriseToolsOpen = false;

  // KORLIX_CUSTOM_ACCESS_FRONTEND_V1_STATE_BEGIN
  bool _customAccessLoading = false;
  String? _customAccessMessage;
  List<Map<String, dynamic>> _customAccessFeatures = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _customAccessCatalog = <Map<String, dynamic>>[];
  // KORLIX_CUSTOM_ACCESS_FRONTEND_V1_STATE_END

  String? _selectedUtilityTool;

  // KORLIX_BUILD109_VISIBLE_UTILITY_TOOLS_BEGIN
  // Build 109 product decision:
  // Hide inactive Utility tools until full native workflows are ready.
  // Keep active Utility tools visible.
  static const List<String> _utilityTools = <String>[
    'Background remover',
    'Songwriter',
  ];

  static const Set<String> _hiddenInactiveUtilityTools = <String>{
    'Voice recorder',
    'Video splitter',
    'Notebook',
    'Alarm',
    'Weather',
    'Outside temperature',
    'GIF maker',
    'Reel maker',
    'Ringtone maker',
    'PDF editor',
    'Photo editor',
  };
  // KORLIX_BUILD109_VISIBLE_UTILITY_TOOLS_END

  bool _createAppMode = false;
  bool _voiceListening = false;
  fp.PlatformFile? _pickedUploadFile;
  final List<fp.PlatformFile> _pickedUploadFiles = <fp.PlatformFile>[];
  bool _loadingTier = false;
  String _currentTier = 'basic';
  String? _error;
  String _selectedLanguage = 'en';

  final List<GeneratedItem> _results = [];
  final List<ChatMessage> _chatMessages = [];
  final ScrollController _chatScrollController = ScrollController();
  static const String _localChatTopicsPrefsKey =
      'korlix_local_chat_topics_strict_v1';
  final Map<String, KorlixLocalChatTopic> _chatTopicsById =
      <String, KorlixLocalChatTopic>{};
  String? _activeChatTopicId;
  static const String _pendingGenerationJobsPrefsKey =
      'korlix_pending_generation_jobs_v1';
  bool _appLifecyclePaused = false;
  bool _resumePendingGenerationJobsRunning = false;
  OverlayEntry? _savedTopicsOverlayEntry;
  final LayerLink _savedTopicsMenuLayerLink = LayerLink();
  bool _chatHistoryLoaded = false;
  bool _chatMinimized = true;
  bool _answerMinimized = false;
  // Per-message minimize/delete state (tracked by index in _chatMessages)
  final Set<int> _minimizedMessages = {};
  final Set<int> _deletedMessages = {};

  LanguageCopy get _t => AppLanguages.byCode(_selectedLanguage);

  Map<String, String> _authHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $kKorlixAccessToken';
    }

    headers.addAll(KorlixDeviceStore.headers());

    headers.addAll(korlixOpenAIQualityHeaders());
    return headers;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedKorlixTheme();
    _loadCurrentTier();
    _loadLocalChatTopics();
    unawaited(_resumePendingGenerationJobs());
  }

  Future<void> _loadSavedKorlixTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('korlix_ui_theme');

    if (savedTheme != null && savedTheme.trim().isNotEmpty) {
      kKorlixThemeNotifier.value = korlixNormalizeSkinId(savedTheme.trim());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savedTopicsOverlayEntry?.remove();
    _savedTopicsOverlayEntry = null;
    _renameTopicController.dispose();
    _savedTopicsScrollController.dispose();
    _chatScrollController.dispose();
    _controller.dispose();
    _wizardCuePlayer.dispose();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _stopAiCharacterTalkingForQuery() async {
    stopKorlixCharacterSpeechGlobally();

    try {
      await _wizardCuePlayer.stop();
    } catch (_) {
      // Character cue audio should never block a request.
    }

    try {
      await _speechToText.stop();
    } catch (_) {
      // Voice input should never block a request.
    }

    if (mounted && _voiceListening) {
      setState(() {
        _voiceListening = false;
      });
    }
  }

  Future<void> _speakConsiderItDone() async {
    // Intentionally silent: when the user submits a query, Korlix should stop
    // character talking instead of starting another voice cue.
    await _stopAiCharacterTalkingForQuery();
  }

  bool _shouldAllowPdf(String command) {
    final lower = command.toLowerCase();

    final triggers = [
      'pdf',
      'word',
      'docx',
      'document',
      'download',
      'export',
      'file',
      'printable',
      'save as',
      'guardar',
      'exportar',
      'archivo',
      'documento',
      'imprimible',
      'télécharger',
      'exporter',
      'fichier',
      'document',
      'imprimable',
    ];

    return triggers.any(lower.contains);
  }

  bool get _hasDocumentUploadAccess {
    return true;
  }

  bool get _hasAdvancedUploadAccess {
    return true;
  }

  bool _isAdvancedUploadName(String name) {
    final lower = name.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  List<fp.PlatformFile> get _activeUploadFiles {
    if (_pickedUploadFiles.isNotEmpty) {
      return List<fp.PlatformFile>.unmodifiable(_pickedUploadFiles);
    }

    final single = _pickedUploadFile;

    if (single == null) {
      return const <fp.PlatformFile>[];
    }

    return <fp.PlatformFile>[single];
  }

  String get _uploadSummaryLabel {
    final files = _activeUploadFiles;

    if (files.isEmpty) {
      return '';
    }

    if (files.length == 1) {
      return files.first.name;
    }

    return '${files.length} files selected';
  }

  String _uploadDetailsLabel(List<fp.PlatformFile> files) {
    if (files.isEmpty) {
      return '';
    }

    if (files.length <= 3) {
      return files.map((file) => file.name).join(', ');
    }

    final firstThree = files.take(3).map((file) => file.name).join(', ');

    return '$firstThree, +${files.length - 3} more';
  }

  String _formatUploadFileSize(int? bytes) {
    final size = bytes ?? 0;

    if (size <= 0) {
      return '';
    }

    if (size < 1024) {
      return '$size B';
    }

    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }

    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _removePickedUploadFileAt(int index) {
    final files = List<fp.PlatformFile>.from(_activeUploadFiles);

    if (index < 0 || index >= files.length) {
      return;
    }

    files.removeAt(index);

    setState(() {
      _pickedUploadFiles
        ..clear()
        ..addAll(files);

      _pickedUploadFile = files.isEmpty ? null : files.first;

      if (files.isEmpty) {
        _error = null;
      }
    });
  }

  Widget _buildSelectedUploadFilesPanel() {
    final files = _activeUploadFiles;

    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2EC7DF).withOpacity(0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                files.length == 1
                    ? Icons.attach_file_rounded
                    : Icons.file_copy_rounded,
                color: const Color(0xFF69D9E8),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  files.length == 1
                      ? '1 file attached'
                      : '${files.length} files attached',
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _clearPickedUploadFiles,
                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                label: const Text('Clear all'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...files.asMap().entries.map((entry) {
            final index = entry.key;
            final file = entry.value;
            final sizeLabel = _formatUploadFileSize(file.size);

            return Container(
              margin: EdgeInsets.only(top: index == 0 ? 0 : 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF071B27).withOpacity(0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF69D9E8).withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _mimeTypeForPickedFile(file).startsWith('image/')
                        ? Icons.image_rounded
                        : Icons.description_rounded,
                    color: const Color(0xFF69D9E8),
                    size: 18,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        if (sizeLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            sizeLabel,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove this file',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removePickedUploadFileAt(index),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _clearPickedUploadFiles() {
    setState(() {
      _pickedUploadFile = null;
      _pickedUploadFiles.clear();
    });
  }

  bool _isSupportedMultiUploadName(String name) {
    final lower = name.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.ppt') ||
        lower.endsWith('.pptx');
  }

  String _mimeTypeForPickedFile(fp.PlatformFile file) {
    final lower = file.name.toLowerCase();

    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';

    return 'application/octet-stream';
  }

  http_parser.MediaType _mediaTypeForPickedFile(fp.PlatformFile file) {
    final mimeType = _mimeTypeForPickedFile(file);
    final slashIndex = mimeType.indexOf('/');

    if (slashIndex <= 0 || slashIndex == mimeType.length - 1) {
      return http_parser.MediaType('application', 'octet-stream');
    }

    return http_parser.MediaType(
      mimeType.substring(0, slashIndex),
      mimeType.substring(slashIndex + 1),
    );
  }

  Future<String?> _showIosUploadSourceSheet() async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo Library'),
                subtitle: const Text(
                  'Choose a picture from your iPhone photos',
                ),
                onTap: () => Navigator.of(sheetContext).pop('photos'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Files'),
                subtitle: const Text(
                  'Choose documents, PDFs, CSV, or other files',
                ),
                onTap: () => Navigator.of(sheetContext).pop('files'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetContext).pop(null),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickSinglePhotoFromIosLibrary() async {
    try {
      final pickedImage = await ip.ImagePicker().pickImage(
        source: ip.ImageSource.gallery,
        requestFullMetadata: false,
        imageQuality: 95,
      );

      if (pickedImage == null) {
        return;
      }

      final bytes = await pickedImage.readAsBytes();
      final fallbackName = pickedImage.name.trim().isNotEmpty
          ? pickedImage.name.trim()
          : 'korlix-photo.jpg';

      final platformFile = fp.PlatformFile(
        name: fallbackName,
        size: bytes.length,
        bytes: bytes,
        path: pickedImage.path,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _error = null;
        _pickedUploadFile = platformFile;
        _pickedUploadFiles
          ..clear()
          ..add(platformFile);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'Could not open your photo library. Please try again or choose Files.';
      });
    }
  }

  Future<void> _handleUploadPressed() async {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final source = await _showIosUploadSourceSheet();

      if (source == 'photos') {
        await _pickSinglePhotoFromIosLibrary();
        return;
      }

      if (source == null) {
        return;
      }
    }

    try {
      final result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: fp.FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'pdf',
          'txt',
          'md',
          'csv',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final selectedFiles = result.files
          .where((file) => file.bytes != null && file.bytes!.isNotEmpty)
          .toList();

      if (selectedFiles.isEmpty) {
        setState(() {
          _error = 'Could not read the selected file. Try again.';
        });
        return;
      }

      const maxFiles = 8;

      if (selectedFiles.length > maxFiles) {
        setState(() {
          _error = 'You can upload up to $maxFiles files at once.';
        });
        return;
      }

      final unsupported = selectedFiles
          .where((file) => !_isSupportedMultiUploadName(file.name))
          .map((file) => file.name)
          .toList();

      if (unsupported.isNotEmpty) {
        setState(() {
          _error =
              'Unsupported file type: ${unsupported.join(', ')}. Use image, PDF, TXT, CSV, DOCX, XLSX, or PPTX files.';
        });
        return;
      }

      setState(() {
        _pickedUploadFile = selectedFiles.first;
        _pickedUploadFiles
          ..clear()
          ..addAll(selectedFiles);
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = korlixFriendlyErrorMessage(error);
      });
    }
  }

  void _clearPickedUploadFile() {
    setState(() {
      _pickedUploadFile = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;

    _appLifecyclePaused = paused;

    if (state == AppLifecycleState.resumed) {
      _appLifecyclePaused = false;
      unawaited(_resumePendingGenerationJobs());
    }
  }

  Future<void> _forceSignOutForSessionTimeout() async {
    await korlixClearLocalAuthSession();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _error = 'Your session timed out. Please sign in again.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session timed out. Please sign in again.'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  String _makePendingGenerationJobId(String kind) {
    final safeKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
    return 'korlix-$safeKind-${DateTime.now().microsecondsSinceEpoch}-${_chatMessages.length}-${_results.length}';
  }

  Future<List<Map<String, dynamic>>> _loadPendingGenerationJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingGenerationJobsPrefsKey);

      if (raw == null || raw.trim().isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) => (item['localJobId'] ?? '').toString().trim().isNotEmpty,
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _savePendingGenerationJobs(
    List<Map<String, dynamic>> jobs,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingGenerationJobsPrefsKey, jsonEncode(jobs));
    } catch (_) {
      // Pending job persistence should never block the app.
    }
  }

  Future<void> _upsertPendingGenerationJob(Map<String, dynamic> job) async {
    final localJobId = (job['localJobId'] ?? '').toString().trim();

    if (localJobId.isEmpty) {
      return;
    }

    final jobs = await _loadPendingGenerationJobs();
    jobs.removeWhere((item) => item['localJobId'] == localJobId);
    jobs.add(<String, dynamic>{
      ...job,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    await _savePendingGenerationJobs(jobs);
  }

  Future<void> _removePendingGenerationJob(String localJobId) async {
    final safeId = localJobId.trim();

    if (safeId.isEmpty) {
      return;
    }

    final jobs = await _loadPendingGenerationJobs();
    jobs.removeWhere((item) => item['localJobId'] == safeId);
    await _savePendingGenerationJobs(jobs);
  }

  void _showBackgroundProcessingSnack(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
  }

  Future<Map<String, dynamic>> _startKorlixBackendJsonJob({
    required String localJobId,
    required String kind,
    required String endpoint,
    required Map<String, dynamic> payload,
    required String prompt,
    required String language,
    required String? topicId,
    bool allowPdf = false,
  }) async {
    final pendingJob = <String, dynamic>{
      'localJobId': localJobId,
      'kind': kind,
      'endpoint': endpoint,
      'prompt': prompt,
      'language': language,
      'topicId': topicId,
      'allowPdf': allowPdf,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'creating',
    };

    await _upsertPendingGenerationJob(pendingJob);

    final response = await http
        .post(
          _assertValidKorlixBackendUri(
            '$kKorlixBackendBaseUrl/api/korlix/jobs',
          ),
          headers: _authHeaders(),
          body: jsonEncode({
            'kind': kind,
            'endpoint': endpoint,
            'payload': payload,
            'clientRequestId': localJobId,
          }),
        )
        .timeout(const Duration(seconds: 18));

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['details'] ?? data['error'] ?? response.body);
    }

    final backendJobId = (data['jobId'] ?? '').toString().trim();

    if (backendJobId.isEmpty) {
      throw Exception('Backend did not return a resumable job ID.');
    }

    await _upsertPendingGenerationJob(<String, dynamic>{
      ...pendingJob,
      'backendJobId': backendJobId,
      'status': 'processing',
    });

    return data;
  }

  Future<Map<String, dynamic>> _fetchKorlixBackendJobStatus(
    String backendJobId,
  ) async {
    final response = await http
        .get(
          _assertValidKorlixBackendUri(
            '$kKorlixBackendBaseUrl/api/korlix/jobs/$backendJobId',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 18));

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['details'] ?? data['error'] ?? response.body);
    }

    return data;
  }

  Future<Map<String, dynamic>?> _waitForKorlixBackendJob({
    required String localJobId,
    required String backendJobId,
    int maxPolls = 90,
    Duration pollEvery = const Duration(seconds: 5),
  }) async {
    for (var attempt = 0; attempt < maxPolls; attempt += 1) {
      if (!mounted || _appLifecyclePaused) {
        return null;
      }

      final statusData = await _fetchKorlixBackendJobStatus(backendJobId);
      final status = (statusData['status'] ?? '').toString().toLowerCase();

      if (status == 'completed') {
        await _removePendingGenerationJob(localJobId);
        return statusData;
      }

      if (status == 'failed') {
        await _removePendingGenerationJob(localJobId);
        throw Exception(
          statusData['details'] ?? statusData['error'] ?? 'Korlix job failed.',
        );
      }

      await Future<void>.delayed(pollEvery);
    }

    return null;
  }

  Map<String, dynamic> _jsonFromCompletedKorlixJob(
    Map<String, dynamic> statusData,
  ) {
    final result =
        (statusData['result'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    final statusCode =
        int.tryParse((result['statusCode'] ?? 200).toString()) ?? 200;

    if (korlixIsSessionTimeoutStatus(statusCode)) {
      unawaited(_forceSignOutForSessionTimeout());
      throw Exception('Your session timed out. Please sign in again.');
    }

    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        result['body'] ??
            result['error'] ??
            'Backend job returned status $statusCode.',
      );
    }

    final jsonResult = result['json'];

    if (jsonResult is Map) {
      return jsonResult.cast<String, dynamic>();
    }

    final body = (result['body'] ?? '').toString().trim();

    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(body);

    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }

    throw Exception('Backend job returned unexpected JSON.');
  }

  Future<Map<String, dynamic>?> _runResumableJsonPost({
    required String localJobId,
    required String kind,
    required String endpoint,
    required Map<String, dynamic> payload,
    required String prompt,
    required String language,
    required String? topicId,
    bool allowPdf = false,
    Duration directTimeout = const Duration(seconds: 300),
  }) async {
    var submittedToBackendJob = false;

    try {
      final startData = await _startKorlixBackendJsonJob(
        localJobId: localJobId,
        kind: kind,
        endpoint: endpoint,
        payload: payload,
        prompt: prompt,
        language: language,
        topicId: topicId,
        allowPdf: allowPdf,
      );

      submittedToBackendJob = true;

      final backendJobId = (startData['jobId'] ?? '').toString();

      final completed = await _waitForKorlixBackendJob(
        localJobId: localJobId,
        backendJobId: backendJobId,
      );

      if (completed == null) {
        return null;
      }

      return _jsonFromCompletedKorlixJob(completed);
    } catch (error) {
      if (submittedToBackendJob || _appLifecyclePaused) {
        rethrow;
      }

      // Compatibility fallback for older backend deployments.
      final response = await http
          .post(
            Uri.parse('$kKorlixBackendBaseUrl$endpoint'),
            headers: _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(directTimeout);

      final data = _decodeKorlixJsonMap(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      await _removePendingGenerationJob(localJobId);
      return data;
    }
  }

  void _applyCompletedTextGeneration({
    required String command,
    required String content,
    required String language,
    required bool allowPdf,
    String? topicId,
    DateTime? createdAt,
  }) {
    final completedAt = createdAt ?? DateTime.now();

    final newItem = GeneratedItem(
      command: command,
      title: _makeResultTitle(command),
      content: content,
      language: language,
      allowPdf: allowPdf,
    );

    final message = ChatMessage(
      userText: command,
      aiText: content,
      language: language,
      allowPdf: allowPdf,
      generatedItem: newItem,
      createdAt: completedAt,
    );

    final safeTopicId = topicId?.trim();

    if (safeTopicId != null &&
        safeTopicId.isNotEmpty &&
        safeTopicId != _activeChatTopicId &&
        _chatTopicsById.containsKey(safeTopicId)) {
      final topic = _chatTopicsById[safeTopicId]!;
      final messages = List<ChatMessage>.from(topic.messages)..add(message);

      _chatTopicsById[safeTopicId] = topic.copyWith(
        messages: messages,
        updatedAt: completedAt,
        title: topic.title.trim().isEmpty || topic.title == 'New Chat'
            ? _deriveTopicTitle(command)
            : topic.title,
      );

      unawaited(_persistLocalChatTopics());
      return;
    }

    _results.insert(0, newItem);
    _addChatMessage(message);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _resumePendingGenerationJobs() async {
    if (_resumePendingGenerationJobsRunning) {
      return;
    }

    _resumePendingGenerationJobsRunning = true;

    try {
      final jobs = await _loadPendingGenerationJobs();

      if (jobs.isEmpty) {
        return;
      }

      for (final job in jobs) {
        if (!mounted || _appLifecyclePaused) {
          return;
        }

        final kind = (job['kind'] ?? '').toString();
        final localJobId = (job['localJobId'] ?? '').toString();
        final backendJobId = (job['backendJobId'] ?? '').toString();

        if (kind == 'video_status') {
          final videoId = (job['videoId'] ?? '').toString().trim();
          final prompt = (job['prompt'] ?? '').toString();

          if (videoId.isNotEmpty && mounted) {
            unawaited(
              _showVideoProgressDialog(videoId: videoId, prompt: prompt),
            );
          }

          continue;
        }

        if (backendJobId.isEmpty) {
          continue;
        }

        try {
          final statusData = await _fetchKorlixBackendJobStatus(backendJobId);
          final status = (statusData['status'] ?? '').toString().toLowerCase();

          if (status == 'failed') {
            await _removePendingGenerationJob(localJobId);
            continue;
          }

          if (status != 'completed') {
            continue;
          }

          final data = _jsonFromCompletedKorlixJob(statusData);

          if (kind == 'text') {
            final command = (job['prompt'] ?? '').toString();
            final content = (data['content'] ?? '').toString().trim();

            if (command.isEmpty || content.isEmpty) {
              await _removePendingGenerationJob(localJobId);
              continue;
            }

            if (mounted) {
              setState(() {
                _loading = false;
                _error = null;
                _featuredAnswerDismissed = false;
                _answerMinimized = false;
                _applyCompletedTextGeneration(
                  command: command,
                  content: content,
                  language: (job['language'] ?? _selectedLanguage).toString(),
                  allowPdf: job['allowPdf'] == true,
                  topicId: job['topicId']?.toString(),
                  createdAt: DateTime.tryParse(
                    (job['createdAt'] ?? '').toString(),
                  ),
                );
              });

              _showBackgroundProcessingSnack(
                'Korlix finished your answer while the phone was locked.',
              );
            }

            await _removePendingGenerationJob(localJobId);
          }

          if (kind == 'video_start') {
            final videoId = (data['videoId'] ?? data['video']?['id'])
                .toString();
            final prompt = (job['prompt'] ?? '').toString();

            await _removePendingGenerationJob(localJobId);

            if (videoId.isNotEmpty && videoId != 'null' && mounted) {
              _showBackgroundProcessingSnack(
                'Korlix video generation resumed.',
              );
              unawaited(
                _showVideoProgressDialog(videoId: videoId, prompt: prompt),
              );
            }
          }
        } catch (_) {
          // Keep pending jobs. Resume can try again later.
        }
      }
    } finally {
      _resumePendingGenerationJobsRunning = false;
    }
  }

  Map<String, dynamic> _decodeKorlixJsonMap(http.Response response) {
    if (korlixIsSessionTimeoutStatus(response.statusCode)) {
      unawaited(_forceSignOutForSessionTimeout());
      throw Exception('Your session timed out. Please sign in again.');
    }

    final body = response.body.trim();

    if (body.isEmpty) {
      throw Exception(
        'Backend returned an empty response with status ${response.statusCode}.',
      );
    }

    if (body.startsWith('<!DOCTYPE') ||
        body.startsWith('<html') ||
        body.startsWith('<')) {
      final preview = body.length > 220 ? body.substring(0, 220) : body;

      throw Exception(
        'Backend returned an HTML page instead of JSON. '
        'This usually means the backend route is not deployed yet or the URL is wrong. '
        'Status: ${response.statusCode}. Response: $preview',
      );
    }

    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception(
      'Backend returned JSON, but not the expected object format.',
    );
  }

  Future<void> _generateImaginedPicture() async {
    await _stopAiCharacterTalkingForQuery();

    final prompt = korlixApplyProductionQualityDirective(
      _controller.text.trim(),
    );

    if (prompt.isEmpty) {
      setState(() {
        _error = 'Describe the picture you want Korlix AI to create.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _imaginePictureMode = false;
    });

    try {
      final response = await http
          .post(
            _assertValidKorlixBackendUri(
              '$kKorlixBackendBaseUrl/api/image/create',
            ),
            headers: _authHeaders(),
            body: jsonEncode({'prompt': prompt, 'language': _selectedLanguage}),
          )
          .timeout(const Duration(seconds: 180));

      final data = _decodeKorlixJsonMap(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      final imageDataUrl = data['imageDataUrl']?.toString();
      final imageUrl = data['imageUrl']?.toString();

      if ((imageDataUrl == null || imageDataUrl.isEmpty) &&
          (imageUrl == null || imageUrl.isEmpty)) {
        throw Exception('No image was returned.');
      }

      final imaginedItem = GeneratedItem(
        command: 'Imagine a picture: $prompt',
        title: data['title']?.toString() ?? 'Imagined picture',
        content: data['content']?.toString() ?? 'Image generated.',
        language: _selectedLanguage,
        allowPdf: false,
        imageDataUrl: imageDataUrl,
        imageUrl: imageUrl,
      );

      setState(() {
        _loading = false;
        _controller.clear();
        _results.insert(0, imaginedItem);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showResult(imaginedItem);
        }
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  Future<void> _generateImprovedPicture() async {
    await _stopAiCharacterTalkingForQuery();

    final files = _activeUploadFiles;

    if (files.length > 1) {
      setState(() {
        _error =
            'Improve my picture works with one image at a time. Remove extra files and try again.';
      });
      return;
    }

    final file = files.isEmpty ? null : files.first;
    final command = korlixApplyProductionQualityDirective(
      _controller.text.trim(),
    );

    if (file == null) {
      setState(() {
        _error = 'Upload an image first, then use Improve my picture.';
      });
      return;
    }

    final mimeType = _mimeTypeForPickedFile(file);

    if (!mimeType.startsWith('image/')) {
      setState(() {
        _error = 'Improve my picture requires JPG, PNG, or WEBP image upload.';
      });
      return;
    }

    if (file.bytes == null || file.bytes!.isEmpty) {
      setState(() {
        _error = 'Could not read this image. Try uploading it again.';
      });
      return;
    }

    final prompt =
        (_portraitStudioPromptOverride != null &&
            _portraitStudioPromptOverride!.trim().isNotEmpty)
        ? _portraitStudioPromptOverride!.trim()
        : command.isEmpty
        ? 'Improve this picture and return an enhanced professional version.'
        : command;

    _portraitStudioPromptOverride = null;

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _improvePictureMode = false;
    });

    _speakConsiderItDone();

    try {
      final request = http.MultipartRequest(
        'POST',
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/image/improve',
        ),
      );

      final headers = Map<String, String>.from(_authHeaders())
        ..remove('Content-Type');
      request.headers.addAll(headers);

      request.fields['prompt'] = prompt;
      request.fields['language'] = _selectedLanguage;

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          file.bytes!,
          filename: file.name,
          contentType: _mediaTypeForPickedFile(file),
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 360),
      );

      final response = await http.Response.fromStream(streamedResponse);
      final data = _decodeKorlixJsonMap(response);

      if (response.statusCode == 403 && data['upgradeRequired'] == true) {
        setState(() {
          _loading = false;
        });

        await _showPremiumFeaturePrompt(
          title: 'Ultra Premium required',
          availability: 'Ultra Premium, Enterprise',
          description:
              data['error']?.toString() ??
              'Image improvement requires Ultra Premium or Enterprise.',
        );

        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      final imageDataUrl = data['imageDataUrl']?.toString();
      final imageUrl = data['imageUrl']?.toString();

      if ((imageDataUrl == null || imageDataUrl.isEmpty) &&
          (imageUrl == null || imageUrl.isEmpty)) {
        throw Exception('No enhanced image was returned.');
      }

      final content = (data['content'] ?? 'Enhanced image generated.')
          .toString();

      final improvedItem = GeneratedItem(
        command: 'Improved image: ${file.name}\nInstructions: $prompt',
        title: 'Improved picture: ${file.name}',
        content: content,
        language: _selectedLanguage,
        allowPdf: false,
        imageDataUrl: imageDataUrl,
        imageUrl: imageUrl,
      );

      setState(() {
        _loading = false;
        _controller.clear();
        _pickedUploadFile = null;
        _pickedUploadFiles.clear();
        _results.insert(0, improvedItem);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showResult(improvedItem);
        }
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  Future<void> _generateWithUpload() async {
    await _stopAiCharacterTalkingForQuery();

    final files = _activeUploadFiles;

    if (files.isEmpty) {
      setState(() {
        _error = 'Upload one or more files first.';
      });
      return;
    }

    final command = korlixApplyProductionQualityDirective(
      _controller.text.trim(),
    );
    final isCreditMode = _fixCreditReportMode;

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _fixCreditReportMode = false;

      _creditDebtValidationRoundsVisible = false;

      _creditDebtValidationRound = null;
      _createAppMode = false;
    });

    try {
      if (isCreditMode) {
        // ── CREDIT DISPUTE MODE: call /api/credit-dispute-letters ──
        final request = http.MultipartRequest(
          'POST',
          _assertValidKorlixBackendUri(
            '$kKorlixBackendBaseUrl/api/credit-dispute-letters',
          ),
        );
        final headers = Map<String, String>.from(_authHeaders())
          ..remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['prompt'] = _buildTopicIsolatedPrompt(command);
        request.fields.addAll(_strictTopicRequestFields());
        request.fields['language'] = _selectedLanguage;
        for (final file in files) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'files',
              file.bytes!,
              filename: file.name,
              contentType: _mediaTypeForPickedFile(file),
            ),
          );
        }
        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 360),
        );
        final response = await http.Response.fromStream(streamedResponse);
        final data = _decodeKorlixJsonMap(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(data['details'] ?? data['error'] ?? response.body);
        }
        final content = (data['content'] ?? '').toString();
        final equifaxDocx = data['equifaxDocxBase64'] as String?;
        final experianDocx = data['experianDocxBase64'] as String?;
        final transunionDocx = data['transunionDocxBase64'] as String?;
        final consumerName = (data['consumerName'] ?? 'Consumer').toString();
        final fileList = files.map((f) => '- ${f.name}').join('\n');
        setState(() {
          _loading = false;
          _controller.clear();
          _pickedUploadFile = null;
          _pickedUploadFiles.clear();
          _results.insert(
            0,
            GeneratedItem(
              command: 'Credit dispute letters for:\n$fileList',
              title: 'Credit Dispute Letters',
              content: content,
              language: _selectedLanguage,
              allowPdf: false,
            ),
          );
          _addChatMessage(
            ChatMessage(
              userText:
                  'Please generate dispute letters for my credit report:\n$fileList',
              aiText: content,
              language: _selectedLanguage,
              createdAt: DateTime.now(),
              isCreditDispute: true,
              equifaxDocxBase64: equifaxDocx,
              experianDocxBase64: experianDocx,
              transunionDocxBase64: transunionDocx,
              consumerName: consumerName,
            ),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScrollController.hasClients) {
              _chatScrollController.animateTo(
                _chatScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              );
            }
          });
        });
        return;
      }

      // ── NORMAL FILE UPLOAD MODE ──
      final prompt = command.isEmpty
          ? 'Please summarize and explain the uploaded file${files.length == 1 ? '' : 's'}.'
          : command;

      final request = http.MultipartRequest(
        'POST',
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/analyze-documents',
        ),
      );

      final headers = Map<String, String>.from(_authHeaders())
        ..remove('Content-Type');
      request.headers.addAll(headers);

      request.fields['prompt'] = prompt;
      request.fields['question'] = prompt;
      request.fields['language'] = _selectedLanguage;

      for (final file in files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            file.bytes!,
            filename: file.name,
            contentType: _mediaTypeForPickedFile(file),
          ),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 360),
      );

      final response = await http.Response.fromStream(streamedResponse);
      final data = _decodeKorlixJsonMap(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      final content = (data['content'] ?? data['answer'] ?? '').toString();

      if (content.trim().isEmpty) {
        throw Exception('No answer was returned for the uploaded files.');
      }

      final title = files.length == 1
          ? 'File answer: ${files.first.name}'
          : 'File answer: ${files.length} files';

      final fileList = files.map((file) => '- ${file.name}').join('\n');

      setState(() {
        _loading = false;
        _controller.clear();
        _pickedUploadFile = null;
        _pickedUploadFiles.clear();
        _results.insert(
          0,
          GeneratedItem(
            command:
                'Uploaded file${files.length == 1 ? '' : 's'}:\n$fileList\n\nQuestion: $prompt',
            title: title,
            content: content,
            language: _selectedLanguage,
            allowPdf: false,
          ),
        );
        _addChatMessage(
          ChatMessage(
            userText: 'Uploaded file(s):\n$fileList\n\nQuestion: $prompt',
            aiText: content,
            language: _selectedLanguage,
            createdAt: DateTime.now(),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
          }
        });
      });

      // Legacy: Show PDF + DOCX download buttons if available from old endpoint
      final String? legacyPdfBase64 = data['pdf_base64'] as String?;
      final String? legacyDocxBase64 = data['docx_base64'] as String?;
      if (legacyPdfBase64 != null && legacyPdfBase64.isNotEmpty) {
        setState(() {
          _results.insert(
            0,
            GeneratedItem(
              command: '__DOWNLOAD_CARD__',
              title: 'Credit Dispute Letter Downloads',
              content:
                  '__DOWNLOAD_CARD__|' +
                  legacyPdfBase64 +
                  '|' +
                  (legacyDocxBase64 ?? ''),
              language: _selectedLanguage,
              allowPdf: false,
            ),
          );
        });
      }
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  List<ChatMessage> _strictActiveTopicMessages() {
    final topicId = _activeChatTopicId;

    if (topicId == null || topicId.trim().isEmpty) {
      return const <ChatMessage>[];
    }

    final topic = _chatTopicsById[topicId];

    if (topic == null) {
      return const <ChatMessage>[];
    }

    return List<ChatMessage>.unmodifiable(topic.messages);
  }

  int? _strictMemoryNormalizeNumber(String value) {
    final cleaned = value.toLowerCase().trim();

    final parsed = int.tryParse(cleaned);

    if (parsed != null) {
      return parsed;
    }

    const words = <String, int>{
      'zero': 0,
      'no': 0,
      'one': 1,
      'a': 1,
      'an': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
      'twenty': 20,
    };

    return words[cleaned];
  }

  String _strictMemoryCleanFactName(String value) {
    var cleaned = value.trim();

    cleaned = cleaned.replaceAll(RegExp(r'[.!?,;:]+$'), '');

    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s+(and|but|because|so|with|from|in|at|for|about)\s+.*$',
        caseSensitive: false,
      ),
      '',
    );

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.length > 40) {
      cleaned = cleaned.substring(0, 40).trim();
    }

    return cleaned;
  }

  String? _strictExtractNameFromTopic() {
    final messages = _strictActiveTopicMessages();

    final patterns = <RegExp>[
      RegExp(
        r"\bmy\s+name\s+is\s+([a-z][a-z .'\-]{0,50})",
        caseSensitive: false,
      ),
      RegExp(r"\bi\s+am\s+([a-z][a-z .'\-]{0,50})", caseSensitive: false),
      RegExp(r"\bi'm\s+([a-z][a-z .'\-]{0,50})", caseSensitive: false),
    ];

    final badStarts = <String>{
      'not',
      'going',
      'looking',
      'trying',
      'asking',
      'wondering',
      'working',
      'using',
      'here',
      'from',
      'sure',
      'ready',
      'confused',
    };

    for (final message in messages.reversed) {
      final text = message.userText.trim();

      if (text.isEmpty) {
        continue;
      }

      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);

        if (match == null) {
          continue;
        }

        final name = _strictMemoryCleanFactName(match.group(1) ?? '');

        if (name.isEmpty) {
          continue;
        }

        final firstWord = name.toLowerCase().split(RegExp(r'\s+')).first;

        if (badStarts.contains(firstWord)) {
          continue;
        }

        return name;
      }
    }

    return null;
  }

  String? _strictExtractSiblingFactFromTopic() {
    final messages = _strictActiveTopicMessages();

    int? brothers;
    int? sisters;
    int? siblings;

    for (final message in messages) {
      final text = message.userText.toLowerCase();

      final brotherMatch = RegExp(
        r'\bi\s+have\s+(\d+|zero|no|one|a|an|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\s+brothers?\b',
      ).firstMatch(text);

      if (brotherMatch != null) {
        brothers = _strictMemoryNormalizeNumber(brotherMatch.group(1) ?? '');
      }

      final sisterMatch = RegExp(
        r'\bi\s+have\s+(\d+|zero|no|one|a|an|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\s+sisters?\b',
      ).firstMatch(text);

      if (sisterMatch != null) {
        sisters = _strictMemoryNormalizeNumber(sisterMatch.group(1) ?? '');
      }

      final siblingMatch = RegExp(
        r'\bi\s+have\s+(\d+|zero|no|one|a|an|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\s+siblings?\b',
      ).firstMatch(text);

      if (siblingMatch != null) {
        siblings = _strictMemoryNormalizeNumber(siblingMatch.group(1) ?? '');
      }
    }

    if (brothers == null && sisters == null && siblings == null) {
      return null;
    }

    final parts = <String>[];

    if (brothers != null) {
      parts.add('$brothers brother${brothers == 1 ? '' : 's'}');
    }

    if (sisters != null) {
      parts.add('$sisters sister${sisters == 1 ? '' : 's'}');
    }

    if (siblings != null && brothers == null && sisters == null) {
      parts.add('$siblings sibling${siblings == 1 ? '' : 's'}');
    }

    if (parts.isEmpty) {
      return null;
    }

    if (parts.length == 1) {
      return 'In this chat, you told me you have ${parts.first}.';
    }

    return 'In this chat, you told me you have ${parts.join(' and ')}.';
  }

  bool _strictIsNameQuestion(String command) {
    final lower = command.toLowerCase();

    return RegExp(r"\bwhat'?s\s+my\s+name\b").hasMatch(lower) ||
        RegExp(r'\bwhat\s+is\s+my\s+name\b').hasMatch(lower) ||
        RegExp(r'\bwho\s+am\s+i\b').hasMatch(lower) ||
        RegExp(r'\bdo\s+you\s+know\s+my\s+name\b').hasMatch(lower);
  }

  bool _strictIsSiblingQuestion(String command) {
    final lower = command.toLowerCase();

    final mentionsSibling =
        lower.contains('brother') ||
        lower.contains('sister') ||
        lower.contains('sibling');

    if (!mentionsSibling) {
      return false;
    }

    return lower.contains('how many') ||
        lower.contains('do i have') ||
        lower.contains('do you know') ||
        lower.contains('remember');
  }

  bool _strictIsPersonalMemoryQuestion(String command) {
    final lower = command.toLowerCase();

    if (_strictIsNameQuestion(command) || _strictIsSiblingQuestion(command)) {
      return true;
    }

    final asksAboutUser =
        RegExp(r"\bwhat'?s\s+my\b").hasMatch(lower) ||
        RegExp(r'\bwhat\s+is\s+my\b').hasMatch(lower) ||
        RegExp(r'\bwhat\s+do\s+i\s+have\b').hasMatch(lower) ||
        RegExp(r'\bhow\s+many\b.*\bdo\s+i\s+have\b').hasMatch(lower) ||
        RegExp(r'\bdo\s+you\s+remember\b').hasMatch(lower) ||
        RegExp(r'\bdid\s+i\s+tell\s+you\b').hasMatch(lower) ||
        RegExp(r'\bwhat\s+do\s+you\s+know\s+about\s+me\b').hasMatch(lower);

    return asksAboutUser;
  }

  String? _strictTopicMemoryGuardAnswer(String command) {
    if (!_strictIsPersonalMemoryQuestion(command)) {
      return null;
    }

    if (_strictIsNameQuestion(command)) {
      final name = _strictExtractNameFromTopic();

      if (name != null && name.trim().isNotEmpty) {
        return 'In this chat, you told me your name is $name.';
      }

      return 'You have not told me your name in this chat.';
    }

    if (_strictIsSiblingQuestion(command)) {
      final siblingFact = _strictExtractSiblingFactFromTopic();

      if (siblingFact != null && siblingFact.trim().isNotEmpty) {
        return siblingFact;
      }

      return 'You have not told me how many brothers or sisters you have in this chat.';
    }

    final hasSelectedTopicMemory = _strictActiveTopicMessages().isNotEmpty;

    if (!hasSelectedTopicMemory) {
      return 'You have not provided that information in this chat.';
    }

    return 'I do not see that information in this chat.';
  }

  bool _respondWithStrictTopicMemoryGuard(String command) {
    final answer = _strictTopicMemoryGuardAnswer(command);

    if (answer == null) {
      return false;
    }

    final item = GeneratedItem(
      command: command,
      title: 'Topic Memory',
      content: answer,
      language: _selectedLanguage,
      allowPdf: false,
    );

    final message = ChatMessage(
      userText: command,
      aiText: answer,
      language: _selectedLanguage,
      allowPdf: false,
      generatedItem: item,
      createdAt: DateTime.now(),
    );

    setState(() {
      _controller.clear();
      _error = null;
      _featuredAnswerDismissed = false;
      _answerMinimized = false;

      _results
        ..clear()
        ..add(item);

      _addChatMessage(message);
    });

    _scrollChatThreadToBottomSoon();

    return true;
  }

  Future<void> _generate() async {
    // KORLIX_CREDIT_ALL_THREE_REPORTS_GUARD
    if (_fixCreditReportMode && !_hasRequiredCreditReportsUploaded) {
      setState(() {
        _error = _creditReportUploadRequirementMessage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_creditReportUploadRequirementMessage)),
      );
      return;
    }

    if (_fixCreditReportMode && !_hasRequiredCreditReportsUploaded) {
      setState(() {
        _error =
            'Upload all 3 credit reports first: Equifax, Experian, and TransUnion. Then tap submit.';
      });
      return;
    }

    if (_imaginePictureMode) {
      await _generateImaginedPicture();
      return;
    }

    await _stopAiCharacterTalkingForQuery();

    final attachedImageForImprove = _pickedUploadFile;
    final typedCommandForImprove = _controller.text.trim();

    if (_improvePictureMode ||
        (attachedImageForImprove != null &&
            _mimeTypeForPickedFile(
              attachedImageForImprove,
            ).startsWith('image/') &&
            _isImprovePicturePromptText(typedCommandForImprove))) {
      await _generateImprovedPicture();
      return;
    }

    if (_improvePictureMode) {
      await _generateImprovedPicture();
      return;
    }

    if (_activeUploadFiles.isNotEmpty) {
      await _generateWithUpload();
      return;
    }

    final command = korlixApplyProductionQualityDirective(
      _controller.text.trim(),
    );

    if (command.isNotEmpty &&
        !_fixCreditReportMode &&
        !_improvePictureMode &&
        !_imaginePictureMode &&
        !_createVideoMode &&
        _activeUploadFiles.isEmpty &&
        _respondWithStrictTopicMemoryGuard(command)) {
      return;
    }

    if (_createVideoMode ||
        command.toLowerCase().contains('create a video') ||
        command.toLowerCase().contains('cinematic video masterpiece')) {
      await _startOpenAIVideoGeneration(command);
      return;
    }

    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.commandEmpty)));
      return;
    }

    final allowPdf = _shouldAllowPdf(command);
    final localJobId = _makePendingGenerationJobId('text');
    final topicId = _activeChatTopicId;

    setState(() {
      _featuredAnswerDismissed = false;
      _answerMinimized = false;
      _loading = true;
      _error = null;
    });

    _speakConsiderItDone();

    try {
      final data = await _runResumableJsonPost(
        localJobId: localJobId,
        kind: 'text',
        endpoint: '/api/generate',
        payload: {'command': command, 'language': _selectedLanguage},
        prompt: command,
        language: _selectedLanguage,
        topicId: topicId,
        allowPdf: allowPdf,
        directTimeout: const Duration(seconds: 300),
      );

      if (data == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
            _controller.clear();
          });

          _showBackgroundProcessingSnack(
            'Korlix is still processing. If your phone locks, reopen the app and this answer will resume.',
          );
        }

        return;
      }

      final content = (data['content'] ?? '').toString().trim();

      if (content.isEmpty) {
        throw Exception('No AI content returned.');
      }

      await _removePendingGenerationJob(localJobId);

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _controller.clear();
        _applyCompletedTextGeneration(
          command: command,
          content: content,
          language: _selectedLanguage,
          allowPdf: allowPdf,
          topicId: topicId,
        );
      });
    } catch (error) {
      if (_appLifecyclePaused) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }

        return;
      }

      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  // KORLIX_POLICY_LEAK_VISIBLE_HELPERS_BEGIN
  String _korlixVisibleUserText(String text) {
    return korlixStripProductionQualityDirective(
      text,
    ).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  GeneratedItem _korlixVisibleGeneratedItem(GeneratedItem item) {
    final visibleCommand = _korlixVisibleUserText(item.command);
    final titleSource = item.title.trim().isNotEmpty
        ? item.title
        : visibleCommand;

    return GeneratedItem(
      command: visibleCommand,
      title: _makeResultTitle(titleSource),
      content: item.content,
      language: item.language,
      allowPdf: item.allowPdf,
      imageDataUrl: item.imageDataUrl,
      imageUrl: item.imageUrl,
    );
  }

  ChatMessage _korlixVisibleChatMessage(ChatMessage message) {
    return ChatMessage(
      userText: _korlixVisibleUserText(message.userText),
      aiText: message.aiText,
      isImage: message.isImage,
      imageDataUrl: message.imageDataUrl,
      imageUrl: message.imageUrl,
      language: message.language,
      allowPdf: message.allowPdf,
      generatedItem: message.generatedItem == null
          ? null
          : _korlixVisibleGeneratedItem(message.generatedItem!),
      createdAt: message.createdAt,
      isCreditDispute: message.isCreditDispute,
      equifaxDocxBase64: message.equifaxDocxBase64,
      experianDocxBase64: message.experianDocxBase64,
      transunionDocxBase64: message.transunionDocxBase64,
      consumerName: message.consumerName,
    );
  }
  // KORLIX_POLICY_LEAK_VISIBLE_HELPERS_END

  String _makeResultTitle(String text) {
    final clean = _cleanMarkdown(text.trim());

    if (clean.isEmpty) {
      return 'Chee Chai Chee';
    }

    if (clean.length <= 64) {
      return clean[0].toUpperCase() + clean.substring(1);
    }

    final words = RegExp(
      r'[A-Za-zÀ-ÿ0-9]+',
    ).allMatches(clean).map((match) => match.group(0)!).take(8).toList();

    return words.isEmpty ? 'Chee Chai Chee' : words.join(' ');
  }

  String _makePdfFileName(String text, String language) {
    final words = RegExp(r'[A-Za-zÀ-ÿ0-9]+')
        .allMatches(text)
        .map((match) => match.group(0)!.toLowerCase())
        .take(6)
        .toList();

    if (words.isEmpty) {
      return 'chee_chai_chee_$language.pdf';
    }

    return '${words.join('_')}_$language.pdf';
  }

  String _cleanMarkdown(String text) {
    var value = text
        .replaceAll('\r', '')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('`', '')
        .replaceAll('�', "'")
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'^#{1,6}\s*'), '')
        .replaceAll(RegExp(r'[✅☑✔✓☐☒]'), '-')
        .replaceAll(RegExp(r'[•●▪▫◦]'), '-')
        .trim();

    value = value.replaceAll(RegExp(r'\s+'), ' ');

    return value.trim();
  }

  String _cleanDisplayText(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final output = <String>[];

    bool skipNextTitleValue = false;

    for (final line in lines) {
      final cleaned = _cleanMarkdown(line.trim());

      if (cleaned.isEmpty) {
        if (output.isNotEmpty && output.last.isNotEmpty) {
          output.add('');
        }
        continue;
      }

      final lower = cleaned.toLowerCase();

      if (['title', 'titre', 'título', 'titulo'].contains(lower)) {
        skipNextTitleValue = true;
        continue;
      }

      if (skipNextTitleValue) {
        skipNextTitleValue = false;
        continue;
      }

      output.add(cleaned);
    }

    return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  List<pw.Widget> _pdfContentWidgets(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final widgets = <pw.Widget>[];

    for (final rawLine in lines) {
      final clean = _cleanMarkdown(rawLine.trim());

      if (clean.isEmpty) {
        widgets.add(pw.SizedBox(height: 5));
        continue;
      }

      final isNumbered = RegExp(r'^\d+\.\s+').hasMatch(clean);
      final isBullet = clean.startsWith('- ');

      final isHeading =
          clean.length <= 48 &&
          !clean.endsWith('.') &&
          !isNumbered &&
          !isBullet &&
          !clean.contains(',');

      if (isHeading) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
            padding: const pw.EdgeInsets.only(bottom: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColor.fromHex('#E5E7EB'),
                  width: 0.6,
                ),
              ),
            ),
            child: pw.Text(
              clean.replaceAll(':', ''),
              style: pw.TextStyle(
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#111827'),
              ),
            ),
          ),
        );
        continue;
      }

      if (isNumbered && clean.length <= 95) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 7, bottom: 3),
            child: pw.Text(
              clean,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#111827'),
              ),
            ),
          ),
        );
        continue;
      }

      if (isBullet) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 3.5,
                  height: 3.5,
                  margin: const pw.EdgeInsets.only(top: 5, right: 7),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#111827'),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    clean.substring(2),
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5.5),
          child: pw.Text(
            clean,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
          ),
        ),
      );
    }

    return widgets;
  }

  Future<Uint8List> _buildPdf(GeneratedItem item) async {
    final pdf = pw.Document();
    final title = item.title;
    final cleanedContent = _cleanDisplayText(item.content);
    final t = AppLanguages.byCode(item.language);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColor.fromHex('#E5E7EB'),
                  width: 0.7,
                ),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Chee Chai Chee',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColor.fromHex('#6B7280'),
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColor.fromHex('#6B7280'),
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 15),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#111827'),
                borderRadius: pw.BorderRadius.circular(9),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'KORLIX AI',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      color: PdfColor.fromHex('#A5F3FC'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 20,
                      lineSpacing: 3,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Text(
                    t.generatedBy,
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor.fromHex('#D1D5DB'),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.fromLTRB(11, 9, 11, 9),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(7),
                border: pw.Border.all(
                  color: PdfColor.fromHex('#E5E7EB'),
                  width: 0.8,
                ),
              ),
              child: pw.Text(
                '${t.originalCommand}: ${_cleanMarkdown(item.command)}',
                style: pw.TextStyle(
                  fontSize: 8.8,
                  color: PdfColor.fromHex('#374151'),
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            ..._pdfContentWidgets(cleanedContent),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _exportPdf(GeneratedItem item) async {
    try {
      final bytes = await _buildPdf(item);

      await Printing.sharePdf(
        bytes: bytes,
        filename: _makePdfFileName(item.command, item.language),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.pdfError)));
    }
  }

  Future<void> _copyResultText(GeneratedItem item) async {
    await Clipboard.setData(
      ClipboardData(text: _cleanDisplayText(item.content)),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t.copied)));
  }

  void _deleteResult(GeneratedItem item) {
    setState(() {
      _results.remove(item);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t.deleted)));
  }

  Future<void> _clearAllResults() async {
    if (_results.isEmpty) {
      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_t.clearConfirmTitle),
          content: Text(_t.clearConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t.clearAll),
            ),
          ],
        );
      },
    );

    if (shouldClear != true) {
      return;
    }

    setState(() {
      _results.clear();
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t.cleared)));
  }

  Uint8List? _imageBytesFromDataUrl(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) {
      return null;
    }

    final commaIndex = dataUrl.indexOf(',');

    if (commaIndex < 0 || commaIndex == dataUrl.length - 1) {
      return null;
    }

    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  String _korlixAiDisclaimerText() {
    return 'KORLIX AI can make mistakes. Always exercise caution and double-check important facts before relying on any answer, image, video, document, or recommendation.';
  }

  Widget _buildKorlixAiDisclaimerBanner({bool compact = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD166).withValues(alpha: 0.42),
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFFFD166),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _korlixAiDisclaimerText(),
              style: TextStyle(
                color: const Color(0xFFE4EBEE).withValues(alpha: 0.90),
                fontSize: compact ? 11.5 : 12.5,
                height: 1.32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _generatedContentReportCategories() {
    return const <String>[
      'Offensive or abusive',
      'Unsafe or harmful',
      'False or misleading',
      'Sexual content',
      'Hate or harassment',
      'Other',
    ];
  }

  String _generatedContentReportSummary({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) {
    final buffer = StringBuffer()
      ..writeln('Korlix AI Reported Output')
      ..writeln('Type: $contentType')
      ..writeln('Time: ${DateTime.now().toIso8601String()}');

    if ((contentId ?? '').trim().isNotEmpty) {
      buffer.writeln('Content ID: ${contentId!.trim()}');
    }

    if ((videoId ?? '').trim().isNotEmpty) {
      buffer.writeln('Video ID: ${videoId!.trim()}');
    }

    if ((imageUrl ?? '').trim().isNotEmpty) {
      buffer.writeln('Image URL: ${imageUrl!.trim()}');
    }

    if (prompt.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Prompt:')
        ..writeln(prompt.trim());
    }

    if (outputSummary.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Generated output summary:')
        ..writeln(outputSummary.trim());
    }

    return buffer.toString();
  }

  Future<bool> _submitGeneratedContentReport({
    required String contentType,
    required String prompt,
    required String outputSummary,
    required String reason,
    required String details,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) async {
    final payload = <String, dynamic>{
      'contentType': contentType,
      'reason': reason,
      'details': details,
      'prompt': prompt,
      'outputSummary': outputSummary,
      'contentId': contentId,
      'imageUrl': imageUrl,
      'videoId': videoId,
      'language': _selectedLanguage,
      'appVersion': 'Korlix AI',
      'createdAt': DateTime.now().toIso8601String(),
    };

    final endpoints = <String>[
      '$kKorlixBackendBaseUrl/api/reports/content',
      '$kKorlixBackendBaseUrl/api/report-output',
      '$kKorlixBackendBaseUrl/api/report',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: _authHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 18));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
      } catch (_) {
        // Try the next endpoint/fallback.
      }
    }

    return false;
  }

  Future<void> _openGeneratedContentReportEmailFallback({
    required String contentType,
    required String prompt,
    required String outputSummary,
    required String reason,
    required String details,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) async {
    final body = StringBuffer()
      ..writeln(
        _generatedContentReportSummary(
          contentType: contentType,
          prompt: prompt,
          outputSummary: outputSummary,
          contentId: contentId,
          imageUrl: imageUrl,
          videoId: videoId,
        ),
      )
      ..writeln()
      ..writeln('Reason:')
      ..writeln(reason)
      ..writeln()
      ..writeln('Additional details:')
      ..writeln(
        details.trim().isEmpty ? '[No extra details provided]' : details.trim(),
      );

    final uri = Uri(
      scheme: 'mailto',
      path: 'support@korlixdeveloper.com',
      queryParameters: <String, String>{
        'subject': 'Report AI Output - Korlix AI',
        'body': body.toString(),
      },
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        return;
      }
    } catch (_) {}

    await Clipboard.setData(ClipboardData(text: body.toString()));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report details copied. Email support@korlixdeveloper.com if the email app did not open.',
        ),
      ),
    );
  }

  Future<void> _showReportGeneratedContentSheet({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) async {
    final detailsController = TextEditingController();
    var selectedReason = _generatedContentReportCategories().first;

    try {
      final result = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF07111F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 22 + bottomInset),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFA9C6CF,
                            ).withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Icon(
                          Icons.flag_rounded,
                          color: Colors.redAccent,
                          size: 36,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Report generated content',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tell us why this $contentType may be offensive, unsafe, misleading, or inappropriate.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFA9C6CF),
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _generatedContentReportCategories().map((
                            reason,
                          ) {
                            final selected = selectedReason == reason;

                            return ChoiceChip(
                              selected: selected,
                              label: Text(reason),
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedReason = reason;
                                });
                              },
                              selectedColor: Colors.redAccent.withValues(
                                alpha: 0.22,
                              ),
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.20,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? Colors.redAccent
                                    : const Color(
                                        0xFF69D9E8,
                                      ).withValues(alpha: 0.30),
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(
                                        0xFFE4EBEE,
                                      ).withValues(alpha: 0.86),
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: detailsController,
                          minLines: 3,
                          maxLines: 5,
                          style: const TextStyle(color: Color(0xFFE4EBEE)),
                          cursorColor: const Color(0xFF69D9E8),
                          decoration: InputDecoration(
                            hintText: 'Optional details...',
                            hintStyle: TextStyle(
                              color: const Color(
                                0xFFA9C6CF,
                              ).withValues(alpha: 0.72),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.24),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: const Color(
                                  0xFF69D9E8,
                                ).withValues(alpha: 0.26),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF69D9E8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildKorlixAiDisclaimerBanner(compact: true),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFE4EBEE),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(
                                    sheetContext,
                                  ).pop(<String, String>{
                                    'reason': selectedReason,
                                    'details': detailsController.text.trim(),
                                  });
                                },
                                icon: const Icon(Icons.flag_rounded),
                                label: const Text('Submit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (result == null || !mounted) {
        return;
      }

      final reason = result['reason'] ?? 'Other';
      final details = result['details'] ?? '';

      final sent = await _submitGeneratedContentReport(
        contentType: contentType,
        prompt: prompt,
        outputSummary: outputSummary,
        reason: reason,
        details: details,
        contentId: contentId,
        imageUrl: imageUrl,
        videoId: videoId,
      );

      if (!mounted) {
        return;
      }

      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not submit automatically. Opening support email fallback.',
          ),
        ),
      );

      await _openGeneratedContentReportEmailFallback(
        contentType: contentType,
        prompt: prompt,
        outputSummary: outputSummary,
        reason: reason,
        details: details,
        contentId: contentId,
        imageUrl: imageUrl,
        videoId: videoId,
      );
    } finally {
      detailsController.dispose();
    }
  }

  Widget _buildReportGeneratedContentPill({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showReportGeneratedContentSheet(
          contentType: contentType,
          prompt: prompt,
          outputSummary: outputSummary,
          contentId: contentId,
          imageUrl: imageUrl,
          videoId: videoId,
        ),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xDD14090E),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.70),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_rounded, color: Colors.redAccent, size: 15),
              SizedBox(width: 5),
              Text(
                'Report',
                style: TextStyle(
                  color: Color(0xFFF3FBFF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedImagePreview(
    GeneratedItem item, {
    double height = 260,
  }) {
    final bytes = _imageBytesFromDataUrl(item.imageDataUrl);
    final imageUrl = item.imageUrl;
    final prompt = _korlixVisibleUserText(item.command).trim();
    final outputSummary = item.content.trim().isEmpty
        ? 'Generated image'
        : _cleanDisplayText(item.content).trim();

    Widget imageChild;

    if (bytes != null) {
      imageChild = Image.memory(
        bytes,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      imageChild = Image.network(
        imageUrl,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            alignment: Alignment.center,
            color: Colors.black.withValues(alpha: 0.24),
            child: const Text(
              'Generated image could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA9C6CF)),
            ),
          );
        },
      );
    } else {
      imageChild = Container(
        height: height,
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.24),
        child: const Text(
          'Generated image is not available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFA9C6CF)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          SizedBox(width: double.infinity, height: height, child: imageChild),
          Positioned(
            top: 10,
            right: 10,
            child: _buildReportGeneratedContentPill(
              contentType: 'image',
              prompt: prompt,
              outputSummary: outputSummary,
              contentId: item.title,
              imageUrl: imageUrl,
            ),
          ),
        ],
      ),
    );
  }

  String _generatedImageFilename(GeneratedItem item) {
    final rawTitle = item.title.trim().isEmpty ? 'korlix-image' : item.title;
    final safeTitle = rawTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    final name = safeTitle.isEmpty ? 'korlix-image' : safeTitle;

    return '$name.png';
  }

  Future<Uint8List> _generatedImageBytes(GeneratedItem item) async {
    final dataBytes = _imageBytesFromDataUrl(item.imageDataUrl);

    if (dataBytes != null && dataBytes.isNotEmpty) {
      return dataBytes;
    }

    final imageUrl = item.imageUrl;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      final response = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }

      throw Exception(
        'Could not download generated image. Status: ${response.statusCode}',
      );
    }

    throw Exception('No image data is available to save or share.');
  }

  Future<void> _saveGeneratedImage(GeneratedItem item) async {
    try {
      final bytes = await _generatedImageBytes(item);

      await saveKorlixGeneratedImage(
        bytes: bytes,
        filename: _generatedImageFilename(item),
        mimeType: 'image/png',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image save started.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(korlixFriendlyErrorMessage(error)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _shareGeneratedImage(GeneratedItem item) async {
    try {
      final bytes = await _generatedImageBytes(item);

      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: _generatedImageFilename(item),
            mimeType: 'image/png',
          ),
        ],
        text: 'Korlix AI improved image',
        subject: 'Korlix AI improved image',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(korlixFriendlyErrorMessage(error)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showResult(GeneratedItem item) {
    showDialog(
      context: context,
      builder: (context) {
        final language = AppLanguages.byCode(item.language);

        return AlertDialog(
          title: Text(item.title),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: item.hasImageResult
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGeneratedImagePreview(item, height: 420),
                        const SizedBox(height: 14),
                        SelectableText(_cleanDisplayText(item.content)),
                      ],
                    )
                  : SelectableText(_cleanDisplayText(item.content)),
            ),
          ),
          actions: [
            if (item.hasImageResult) ...[
              TextButton.icon(
                onPressed: () => _saveGeneratedImage(item),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Save'),
              ),
              TextButton.icon(
                onPressed: () => _shareGeneratedImage(item),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share'),
              ),
            ] else ...[
              TextButton(
                onPressed: () => _copyResultText(item),
                child: Text(language.copy),
              ),
              if (item.allowPdf)
                TextButton(
                  onPressed: () => _exportPdf(item),
                  child: Text(language.exportPdf),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(language.close),
            ),
          ],
        );
      },
    );
  }

  void _changeLanguage(String code) {
    setState(() {
      _selectedLanguage = code;
    });
  }

  bool _isCreateAppQuickAction(QuickAction action) {
    final label = action.label.toLowerCase();
    return label.contains('create an app') || label.contains('build an app');
  }

  bool _isCreateVideoQuickAction(QuickAction action) {
    final label = action.label.toLowerCase();
    return label.contains('video') || action.prompt == kKorlixCreateVideoPrompt;
  }

  bool _isImageToVideoQuickAction(QuickAction action) {
    final label = action.label.toLowerCase();
    final prompt = action.prompt.toLowerCase();

    return label.contains('image to video') ||
        label.contains('image → video') ||
        label.contains('photo to video') ||
        prompt.contains('image to video') ||
        prompt.contains('photo to video') ||
        prompt.contains('animate this still image');
  }

  bool _isImprovePictureQuickAction(QuickAction action) {
    final label = action.label.toLowerCase();
    final prompt = action.prompt.toLowerCase();

    return (label.contains('improve') &&
            (label.contains('picture') || label.contains('photo'))) ||
        prompt.contains('world-class photographer') ||
        prompt.contains('professional photograph');
  }

  bool _isImaginePictureQuickAction(QuickAction action) {
    final label = action.label.toLowerCase();
    final prompt = action.prompt.toLowerCase();

    return (label.contains('imagine') &&
            (label.contains('picture') ||
                label.contains('image') ||
                label.contains('photo'))) ||
        prompt == kKorlixImaginePicturePrompt.toLowerCase();
  }

  bool _isImprovePicturePromptText(String text) {
    final lower = text.toLowerCase();

    final mentionsImage =
        lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('image') ||
        lower.contains('selfie') ||
        lower.contains('portrait');

    final asksImprove =
        lower.contains('improve') ||
        lower.contains('enhance') ||
        lower.contains('make me look') ||
        lower.contains('make it look') ||
        lower.contains('look better') ||
        lower.contains('better quality') ||
        lower.contains('clean up') ||
        lower.contains('retouch') ||
        lower.contains('sharpen') ||
        lower.contains('brighten') ||
        lower.contains('fix my picture') ||
        lower.contains('fix my photo') ||
        lower.contains('fix my image');

    return mentionsImage && asksImprove;
  }

  bool _isCreditReportActionSafeUi(QuickAction action) {
    final label = action.label.toLowerCase();
    final prompt = action.prompt.toLowerCase();

    return label.contains('fix my credit') ||
        label.contains('credit report') ||
        prompt.contains('fix my credit') ||
        prompt.contains('credit report') ||
        prompt.contains('credit repair') ||
        prompt.contains('fcra') ||
        prompt.contains('fdcpa') ||
        prompt.contains('fair credit reporting') ||
        prompt.contains('fair debt collection') ||
        prompt.contains('consumer rights');
  }

  String _creditDebtValidationRoundTitle(int round) {
    switch (round) {
      case 1:
        return 'Validation of Debt Round 1';
      case 2:
        return 'Validation of Debt Round 2';
      case 3:
        return 'Validation of Debt Round 3';
      default:
        return 'Validation of Debt';
    }
  }

  bool get _hasRequiredCreditReportsUploaded {
    if (!_fixCreditReportMode) {
      return true;
    }

    return _activeUploadFiles.length >= 3;
  }

  String get _creditReportUploadRequirementMessage {
    return 'Upload all 3 credit reports first: Equifax, Experian, and TransUnion. Add collector letters, notices, or prior responses too if you have them.';
  }

  String _creditDebtValidationRoundPromptSafeUi({
    required int round,
    required String userNotes,
  }) {
    final notes = userNotes.trim();
    final roundTitle = _creditDebtValidationRoundTitle(round);

    final shared = <String>[
      'KORLIX AI CREDIT VALIDATION WORKFLOW: $roundTitle',
      '',
      'IMPORTANT SAFETY AND COMPLIANCE RULES:',
      'This output is educational drafting assistance only. Do not guarantee deletion, score increases, settlement, legal victory, or any particular outcome. The user must verify all facts, account numbers, dates, addresses, laws, deadlines, balances, creditor identities, bureau names, and debt collector information before sending anything. Recommend review by a qualified attorney or licensed professional when legal advice is needed.',
      '',
      'REQUIRED USER UPLOADS:',
      'The user should upload all three complete credit reports: Equifax, Experian, and TransUnion. If one or more bureau reports are missing, clearly label which bureau is missing and draft only from available evidence. Also use any uploaded collection letters, validation notices, account statements, contracts, screenshots, prior dispute letters, prior responses, certified-mail receipts, tracking numbers, and identity-theft documents.',
      '',
      'USER NOTES:',
      notes.isEmpty ? 'No extra user notes provided.' : notes,
      '',
      'OUTPUT FORMAT REQUIREMENTS:',
      'Produce print-ready editable letter documents. Use clean document titles, recipient blocks, applicant/consumer blocks with placeholders, date placeholders, subject lines, account tables, evidence exhibits, body text, signature blocks, certified-mail instructions, and attachment checklists. Keep language professional, firm, factual, and legally grounded. Do not invent facts. Use placeholders where facts are missing.',
      '',
      'DOCUMENT SET REQUIRED:',
      '1. Applicant master case summary and action checklist.',
      '2. Equifax-ready editable letter, if Equifax data is available.',
      '3. Experian-ready editable letter, if Experian data is available.',
      '4. TransUnion-ready editable letter, if TransUnion data is available.',
      '5. Debt collector / collection agency validation letter.',
      '6. Furnisher / original creditor investigation letter where appropriate.',
      '7. Mailing and tracking checklist.',
      '8. Missing evidence checklist.',
      '',
    ];

    switch (round) {
      case 1:
        return <String>[
          ...shared,
          '''ROUND 1 OBJECTIVE - INITIAL VALIDATION AND INVESTIGATION PACKAGE

Act as an elite consumer-rights credit report strategist preparing the first aggressive but compliant validation round.

Analyze every uploaded Equifax, Experian, and TransUnion report and every uploaded debt/collection document.

Round 1 strategy:
- Identify every negative, inaccurate, incomplete, outdated, unverifiable, duplicate, suspicious, mixed-file, identity-theft-related, balance-inconsistent, date-inconsistent, ownership-inconsistent, status-inconsistent, or questionable account.
- Separate items by bureau and compare differences between Equifax, Experian, and TransUnion.
- Identify collection agencies, furnishers, original creditors, account numbers, partial account numbers, balances, open dates, last reported dates, date of first delinquency, payment status, charge-off language, collection status, dispute comments, and any missing fields.
- Prioritize debts/accounts where validation, ownership, amount, chain of assignment, date of first delinquency, reporting authority, or itemization is weak or missing.
- Prepare the strongest first-round paper trail.

Round 1 documents to draft:
A. Applicant Master Strategy Memo
B. Debt Collector Validation Letter
C. Furnisher Investigation Letter
D. Separate Equifax, Experian, and TransUnion dispute letters
E. Mailing packet instructions

Tone:
Aggressive, precise, professional, and compliant. No legal threats without a factual basis. No guaranteed deletion claims.''',
        ].join('\n');

      case 2:
        return <String>[
          ...shared,
          '''ROUND 2 OBJECTIVE - INADEQUATE RESPONSE / NON-RESPONSE ESCALATION PACKAGE

Act as an elite credit-repair litigation-prep strategist preparing a second-round validation attack after Round 1 was ignored, answered generically, answered incompletely, or produced weak/unverifiable documents.

Analyze all uploaded credit reports plus any Round 1 letters, certified-mail receipts, delivery confirmations, debt collector responses, creditor responses, and bureau responses.

Round 2 strategy:
- Build a timeline: Round 1 send date, delivery date, response date, response content, missing validation, bureau dispute results, and continued reporting.
- Compare the collector/furnisher/bureau response against the specific documents requested.
- Identify unresolved defects: missing itemization, missing original creditor, missing contract, missing chain of title, balance mismatch, DOFD mismatch, ownership mismatch, duplicate reporting, stale reporting, re-aging risk, generic verification, failure to mark disputed, or continued collection/reporting without sufficient support.

Round 2 documents to draft:
A. Round 2 Master Escalation Memo
B. Second Demand for Validation / Inadequate Validation Letter
C. Separate Equifax, Experian, and TransUnion reinvestigation dispute letters
D. Furnisher direct dispute letter
E. CFPB and state complaint-ready factual drafts
F. Mailing packet instructions

Tone:
More forceful than Round 1, but factual, professional, and compliant.''',
        ].join('\n');

      case 3:
        return <String>[
          ...shared,
          '''ROUND 3 OBJECTIVE - FINAL NOTICE, REGULATORY ESCALATION, AND LITIGATION-READY RECORD PACKAGE

Act as a high-level consumer-rights strategist preparing the final round after Round 1 and Round 2 did not produce adequate validation, correction, deletion, or reasonable reinvestigation.

Analyze all uploaded documents, especially all three bureau reports, Round 1 and Round 2 letters, certified-mail receipts, debt collector responses, creditor/furnisher responses, bureau reinvestigation results, CFPB/state complaint drafts, and any identity-theft, payment, settlement, account closure, statute-of-limitations, or mixed-file evidence.

Round 3 strategy:
- Create a litigation-ready paper trail summary.
- Identify every party: collector, furnisher, current creditor, original creditor, Equifax, Experian, TransUnion.
- Identify every unresolved failure after Round 1 and Round 2.
- Separate facts from assumptions.
- Prepare final notices and regulatory complaint packages.

Round 3 documents to draft:
A. Final Case Summary and Evidence Index
B. Final Notice to Debt Collector
C. Final Furnisher Direct Dispute
D. Separate final Equifax, Experian, and TransUnion dispute letters
E. CFPB complaint package
F. State attorney general / regulator complaint package
G. Attorney review packet
H. Mailing packet instructions

Tone:
Maximum pressure while staying accurate, professional, evidence-based, and compliant. Avoid guaranteeing deletion or claiming legal violations as fact unless the uploaded documents clearly prove them.''',
        ].join('\n');

      default:
        return _creditReportPromptSafeUi(notes);
    }
  }

  void _activateCreditDebtValidationRoundSafeUi(int round) {
    final title = _creditDebtValidationRoundTitle(round);

    setState(() {
      _creditDebtValidationRoundsVisible = true;
      _creditDebtValidationRound = round;
      _fixCreditReportMode = true;
      _createVideoMode = false;
      _improvePictureMode = false;
      _imaginePictureMode = false;
      _createAppMode = false;
      _error = null;
      _controller.text =
          '$title selected. Upload all 3 credit reports - Equifax, Experian, and TransUnion - plus any debt letters, collector notices, prior disputes, responses, certified-mail receipts, or account statements. Add applicant notes here, then tap submit.';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title selected. Upload all 3 bureau reports, then submit.',
        ),
      ),
    );
  }

  Widget _buildCreditDebtValidationRoundChip(int round) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final selected =
        _fixCreditReportMode && _creditDebtValidationRound == round;
    final title = _creditDebtValidationRoundTitle(round);

    return _buildKorlixBelowInputBeveledButton(
      icon: selected ? Icons.check_circle_rounded : Icons.gavel_rounded,
      label: title,
      onPressed: _loading
          ? null
          : () => _activateCreditDebtValidationRoundSafeUi(round),
      active: selected,
      success: selected,
      accentColor: selected ? skin.success : skin.premium,
    );
  }

  Widget _buildCreditDebtValidationRoundsPanel() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildCreditDebtValidationRoundChip(1),
              _buildCreditDebtValidationRoundChip(2),
              _buildCreditDebtValidationRoundChip(3),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a round, upload Equifax + Experian + TransUnion, then submit to create print-ready editable letters.',
            style: TextStyle(
              color: skin.mutedText,
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _creditReportPromptSafeUi(String userNotes) {
    final notes = userNotes.trim();

    if (_creditDebtValidationRound != null) {
      return _creditDebtValidationRoundPromptSafeUi(
        round: _creditDebtValidationRound!,
        userNotes: notes,
      );
    }

    return <String>[
      'Korlix AI credit report review request.',
      '',
      'Important disclaimer:',
      'Korlix AI does not guarantee deletion of accounts, collections, inquiries, late payments, charge-offs, bankruptcies, repossessions, judgments, or any other credit-report item. Korlix AI also does not guarantee a credit score increase. This tool provides educational, organizational, and drafting assistance only. The user is responsible for reviewing all letters, facts, account details, addresses, dates, and legal claims before sending anything to a credit bureau, creditor, furnisher, or collection agency.',
      '',
      'User instruction:',
      'The user attached credit report files. Analyze the uploaded credit report files and create a practical credit-report review and dispute-preparation package.',
      '',
      'User notes:',
      notes.isEmpty ? 'No extra user notes provided.' : notes,
      '',
      'Required output:',
      '1. Start with a clear reminder that deletion is not guaranteed.',
      '2. Summarize the uploaded credit report information.',
      '3. Identify negative, inaccurate, outdated, incomplete, unverifiable, or questionable items.',
      '4. Group items by bureau if bureau information appears in the uploaded reports.',
      '5. Create a prioritized action plan.',
      '6. Draft dispute-letter language the user can review and customize.',
      '7. Flag missing information needed before sending letters.',
    ].join('\n');
  }

  Future<bool> _showCreditReportDisclaimerSafeUi() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Credit validation disclaimer'),
          content: const SingleChildScrollView(
            child: Text(
              'Korlix AI does not guarantee deletion of any credit-report item, debt, collection, inquiry, late payment, charge-off, or account. Korlix AI does not guarantee a credit score increase.\n\n'
              'This tool provides educational drafting, organization, and document-preparation assistance only. It is not legal advice or financial advice.\n\n'
              'How to use this feature:\n'
              '1. Tap I understand and agree.\n'
              '2. Choose Validation of Debt Round 1, 2, or 3.\n'
              '3. Upload all 3 credit reports: Equifax, Experian, and TransUnion.\n'
              '4. Add any collection letters, debt notices, prior dispute letters, responses, certified-mail receipts, or applicant notes.\n'
              '5. Tap submit.\n\n'
              'The app will draft print-ready editable letters and checklists that you must review before sending.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('I understand and agree'),
            ),
          ],
        );
      },
    );

    return accepted == true;
  }

  Future<void> _activateCreditReportModeSafeUi() async {
    final accepted = await _showCreditReportDisclaimerSafeUi();

    if (!accepted || !mounted) {
      return;
    }

    setState(() {
      _creditDebtValidationRoundsVisible = true;
      _creditDebtValidationRound = null;
      _fixCreditReportMode = true;
      _createVideoMode = false;
      _improvePictureMode = false;
      _imaginePictureMode = false;
      _createAppMode = false;
      _error = null;
      _controller.text = '';
      _controller.selection = const TextSelection.collapsed(offset: 0);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Choose Validation of Debt Round 1, 2, or 3.'),
      ),
    );
  }

  Widget _buildSafeUiQuickActionChip(QuickAction action) {
    // KORLIX_BUILD113_FIX_CREDIT_TOGGLE_BEGIN
    if (_isCreditReportActionSafeUi(action)) {
      final fixCreditSkin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
      final creditButton = _buildKorlixBelowInputBeveledButton(
        icon: Icons.credit_score_rounded,
        label: action.label,
        onPressed: _loading ? null : () => _useQuickAction(action),
        active: _fixCreditReportMode,
        success: _fixCreditReportMode,
        accentColor: fixCreditSkin.primary,
      );

      if (!_fixCreditReportMode || !_creditDebtValidationRoundsVisible) {
        return creditButton;
      }

      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            creditButton,
            const SizedBox(height: 8),
            _buildCreditDebtValidationRoundsPanel(),
          ],
        ),
      );
    }
    // KORLIX_BUILD113_FIX_CREDIT_TOGGLE_END
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final isVideoAction = _isCreateVideoQuickAction(action);
    final isImproveAction = _isImprovePictureQuickAction(action);
    final isImagineAction = _isImaginePictureQuickAction(action);
    final isCreditAction = _isCreditReportActionSafeUi(action);

    if (isCreditAction && _creditDebtValidationRoundsVisible) {
      return _buildCreditDebtValidationRoundsPanel();
    }

    final isAppAction = _isCreateAppQuickAction(action);

    final attachedImageForImprove = _pickedUploadFile;
    final typedCommandForImprove = _controller.text.trim();

    final hasAttachedImageImproveIntent =
        attachedImageForImprove != null &&
        _mimeTypeForPickedFile(attachedImageForImprove).startsWith('image/') &&
        _isImprovePicturePromptText(typedCommandForImprove);

    final isVideoActive = isVideoAction && _createVideoMode && !_loading;
    final isImproveActive =
        isImproveAction &&
        (_improvePictureMode || hasAttachedImageImproveIntent) &&
        !_loading;
    final isImagineActive = isImagineAction && _imaginePictureMode && !_loading;
    final isCreditActive = isCreditAction && _fixCreditReportMode && !_loading;
    final isAppActive = isAppAction && _createAppMode && !_loading;

    final isHighlighted =
        isVideoActive ||
        isImproveActive ||
        isImagineActive ||
        isCreditActive ||
        isAppActive;

    final label = isVideoAction
        ? 'Create Video'
        : isImproveAction
        ? 'Improve my picture'
        : isImagineAction
        ? 'Imagine a picture'
        : isCreditAction
        ? 'Fix My Credit Report'
        : isAppAction
        ? 'Create an App'
        : action.label;

    final icon = isVideoAction
        ? Icons.movie_creation_outlined
        : isImproveAction
        ? Icons.auto_fix_high_rounded
        : isImagineAction
        ? Icons.image_search_rounded
        : isCreditAction
        ? Icons.credit_score_rounded
        : isAppAction
        ? Icons.app_shortcut_rounded
        : null;

    final lightQuickActionFill =
        Color.lerp(skin.buttonFill, const Color(0xFFFFFFFF), 0.82) ??
        const Color(0xFFFFFFFF);

    final enabledTextColor = isHighlighted
        ? const Color(0xFF061008)
        : skin.isLight
        ? skin.text
        : const Color(0xFFF7FCFF);

    final disabledTextColor = skin.isLight
        ? skin.text.withValues(alpha: 0.78)
        : const Color(0xFFE4EBEE).withValues(alpha: 0.72);

    final enabledBackgroundColor = isHighlighted
        ? const Color(0xFFB7FF00)
        : skin.isLight
        ? lightQuickActionFill
        : const Color(0xFF120D18);

    final disabledBackgroundColor = skin.isLight
        ? (Color.lerp(lightQuickActionFill, skin.panel, 0.18) ??
              lightQuickActionFill)
        : const Color(0xFF120D18).withValues(alpha: 0.92);

    final enabledBorderColor = isHighlighted
        ? const Color(0xFFD9FF5A)
        : skin.isLight
        ? skin.border.withValues(alpha: 0.92)
        : skin.primary.withValues(alpha: 0.88);

    final disabledBorderColor = skin.isLight
        ? skin.border.withValues(alpha: 0.72)
        : skin.primary.withValues(alpha: 0.42);

    return _korlixBeveledButtonSurface(
      skin: skin,
      fill: _loading ? disabledBackgroundColor : enabledBackgroundColor,
      border: _loading ? disabledBorderColor : enabledBorderColor,
      active: isHighlighted,
      disabled: false,
      borderRadius: BorderRadius.circular(13),
      borderWidth: isHighlighted ? 2.2 : 1.85,
      depth: _loading ? 0.84 : 1.16,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _loading ? null : () => _useQuickAction(action),
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 17,
                    color: _loading ? disabledTextColor : enabledTextColor,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: _loading ? disabledTextColor : enabledTextColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openImageToVideoStudio() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KorlixImageToVideoScreen(
          backendBaseUrl: kKorlixBackendBaseUrl,
          headersBuilder: () async => KorlixDeviceStore.headers(),
        ),
      ),
    );
  }

  Future<void> _openImprovePictureStudio() async {
    if (_loading) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PortraitStudioHome(
          previewHeadersBuilder: korlixAuthenticatedBackendHeaders,
          onGeneratePrompt: (prompt, pickedImageFile, autoSubmit) {
            final cleanedPrompt = prompt.trim();

            if (cleanedPrompt.isEmpty) {
              return;
            }

            if (Navigator.of(context).canPop()) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }

            setState(() {
              _portraitStudioPromptOverride = cleanedPrompt;
              _improvePictureMode = true;
              _createVideoMode = false;
              _imaginePictureMode = false;
              _fixCreditReportMode = false;

              _creditDebtValidationRoundsVisible = false;

              _creditDebtValidationRound = null;
              _createAppMode = false;
              _error = null;

              if (pickedImageFile != null) {
                _pickedUploadFile = pickedImageFile;
                _pickedUploadFiles
                  ..clear()
                  ..add(pickedImageFile);
              }

              _controller.text = cleanedPrompt;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: cleanedPrompt.length),
              );
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  autoSubmit
                      ? 'Generating selected Portrait Studio template...'
                      : 'Portrait Studio prompt ready. Upload one image, then tap submit.',
                ),
              ),
            );

            if (autoSubmit) {
              Future<void>.delayed(const Duration(milliseconds: 350), () async {
                if (!mounted || _loading) {
                  return;
                }

                await _generateImprovedPicture();
              });
            }
          },
        ),
      ),
    );
  }

  void _useQuickAction(QuickAction action) {
    // KORLIX_IMAGE_TO_VIDEO_CREATE_VIDEO_V1_GATE
    // Build 106: route the visible Create Video action into Image to Video V1.
    if (_isCreateVideoQuickAction(action)) {
      unawaited(_openImageToVideoStudio());
      return;
    }

    if (_isImageToVideoQuickAction(action)) {
      unawaited(_openImageToVideoStudio());
      return;
    }

    if (_isCreditReportActionSafeUi(action)) {
      // Toggle off if already active
      if (_fixCreditReportMode) {
        setState(() {
          _fixCreditReportMode = false;

          _creditDebtValidationRoundsVisible = false;

          _creditDebtValidationRound = null;
          _error = null;
          _controller.text = '';
          _controller.selection = const TextSelection.collapsed(offset: 0);
        });
        return;
      }
      unawaited(_activateCreditReportModeSafeUi());
      return;
    }

    if (_isCreateAppQuickAction(action)) {
      _showAppCreationDialog();
      return;
    }

    if (_isCreateVideoQuickAction(action)) {
      setState(() {
        _createVideoMode = true;
        _improvePictureMode = false;
        _imaginePictureMode = false;
        _fixCreditReportMode = false;

        _creditDebtValidationRoundsVisible = false;

        _creditDebtValidationRound = null;
        _createAppMode = false;
        _error = null;
        _controller.text = '';
        _controller.selection = TextSelection.fromPosition(
          const TextPosition(offset: 0),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Describe the video you want, then tap submit to generate it.',
          ),
        ),
      );

      return;
    }

    if (_isImprovePictureQuickAction(action)) {
      _openImprovePictureStudio();
      return;
    }

    if (_isImaginePictureQuickAction(action)) {
      // Toggle off if already active.
      if (_imaginePictureMode) {
        setState(() {
          _imaginePictureMode = false;
          _error = null;
          _controller.text = '';
          _controller.selection = const TextSelection.collapsed(offset: 0);
        });
        return;
      }

      setState(() {
        _imaginePictureMode = true;
        _createVideoMode = false;
        _improvePictureMode = false;
        _fixCreditReportMode = false;

        _creditDebtValidationRoundsVisible = false;

        _creditDebtValidationRound = null;
        _createAppMode = false;
        _error = null;
        _controller.text = '';
        _controller.selection = TextSelection.fromPosition(
          const TextPosition(offset: 0),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Describe the picture you want Korlix AI to create, then tap submit.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _createVideoMode = false;
      _improvePictureMode = false;
      _imaginePictureMode = false;
      _fixCreditReportMode = false;

      _creditDebtValidationRoundsVisible = false;

      _creditDebtValidationRound = null;
      _createAppMode = false;
      _controller.text = action.prompt;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  Future<void> _showAppCreationDialog() async {
    int currentStep = 0;
    final List<String> questions = [
      "What is your app idea or name?",
      "Who is the target audience for this app?",
      "What are the 3-5 main features?",
      "Which platforms? (iOS, Android, Web, All)",
      "Any design preferences? (colors, style, theme)",
    ];
    final List<TextEditingController> controllers = List.generate(
      questions.length,
      (index) => TextEditingController(),
    );

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0A1526),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: const Color(0xFF2EC7DF).withOpacity(0.3),
                ),
              ),
              title: const Text(
                'Create an App',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${currentStep + 1} of ${questions.length}',
                      style: const TextStyle(
                        color: Color(0xFF69D9E8),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      questions[currentStep],
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controllers[currentStep],
                      style: const TextStyle(color: Colors.white),
                      autofocus: true,
                      maxLines: currentStep == 2 ? 3 : 1,
                      decoration: InputDecoration(
                        hintText: 'Type your answer here...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF2EC7DF),
                          ),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (controllers[currentStep].text.trim().isNotEmpty) {
                          if (currentStep < questions.length - 1) {
                            setStateDialog(() {
                              currentStep++;
                            });
                          } else {
                            Navigator.of(context).pop(true);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                if (currentStep > 0)
                  TextButton(
                    onPressed: () {
                      setStateDialog(() {
                        currentStep--;
                      });
                    },
                    child: const Text(
                      'Back',
                      style: TextStyle(color: Color(0xFF2EC7DF)),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () {
                    if (controllers[currentStep].text.trim().isEmpty) return;

                    if (currentStep < questions.length - 1) {
                      setStateDialog(() {
                        currentStep++;
                      });
                    } else {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB7FF00),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    currentStep == questions.length - 1
                        ? 'Generate App Spec'
                        : 'Next',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((completed) {
      if (completed == true) {
        // Compile the answers into a prompt
        final appIdea = controllers[0].text.trim();
        final audience = controllers[1].text.trim();
        final features = controllers[2].text.trim();
        final platforms = controllers[3].text.trim();
        final design = controllers[4].text.trim();

        // Choose tech stack based on platform
        final platformLower = platforms.toLowerCase();
        final String techStack;
        final String codeInstructions;
        if (platformLower.contains('ios') &&
            !platformLower.contains('android') &&
            !platformLower.contains('web')) {
          techStack = 'Swift + SwiftUI (iOS native)';
          codeInstructions =
              'Write the starter code in Swift/SwiftUI including: ContentView.swift, main app entry point, navigation structure, and at least 3 core screen files with full UI code.';
        } else if (platformLower.contains('android') &&
            !platformLower.contains('ios') &&
            !platformLower.contains('web')) {
          techStack = 'Kotlin + Jetpack Compose (Android native)';
          codeInstructions =
              'Write the starter code in Kotlin/Jetpack Compose including: MainActivity.kt, navigation setup, and at least 3 core screen composables with full UI code.';
        } else if (platformLower.contains('web') &&
            !platformLower.contains('ios') &&
            !platformLower.contains('android')) {
          techStack = 'React + TypeScript + TailwindCSS (Web)';
          codeInstructions =
              'Write the starter code including: App.tsx, index.tsx, tailwind config, and at least 3 core page/component files with full JSX/TSX code.';
        } else {
          techStack = 'Flutter + Dart (Cross-platform: iOS, Android, Web)';
          codeInstructions =
              'Write the starter code in Flutter/Dart including: main.dart, pubspec.yaml dependencies, and at least 3 core screen files with full Widget code.';
        }

        final prompt =
            '''You are an expert App Architect, Senior Product Manager, and Senior Software Engineer.

Your task has TWO parts. Complete BOTH in full.

---

## PART 1 — App Specification & Development Plan

App details:
**App Idea/Name:** $appIdea
**Target Audience:** $audience
**Core Features:** $features
**Target Platforms:** $platforms
**Design Preferences:** $design
**Tech Stack:** $techStack

Include:
1. Executive Summary & Value Proposition
2. User Personas & Core Use Cases
3. Detailed Feature Breakdown (MVP vs V2)
4. Screen-by-Screen UI/UX Flow
5. Estimated Development Timeline & Milestones
6. Monetization Strategy (if applicable)

---

## PART 2 — Starter Code (Ready to Run)

$codeInstructions

For each file:
- Show the full filename as a header (e.g., `### main.dart`)
- Provide complete, working, copy-paste-ready code in a code block
- Include comments explaining key sections
- The code must implement the core features listed above
- Use the design preferences for colors/style

Do NOT truncate or summarize the code. Write every file completely.

Make the entire output professional, well-structured using Markdown, and production-ready.''';

        setState(() {
          _createAppMode = true;
          _controller.text = prompt;
        });

        // Auto-submit the generated prompt
        _generate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: korlixThemeBackgroundFor(kKorlixThemeNotifier.value),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                child: Column(
                  children: [
                    _buildMockupHomeHeader(),
                    _buildMockupLanguageTabs(),
                    _buildMockupFeaturedCharacterCard(),
                    _buildReportCurrentAiOutputButton(),
                    _buildThemeShortcutCircles(),
                    _buildPersistentSavedTopicsMenuRow(),
                    const SizedBox(height: 18),
                    if (_chatMessages.length >= 2) ...[
                      _buildResults(),
                      const SizedBox(height: 18),
                    ],
                    _buildCommandPanel(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPremiumFeaturePrompt({
    required String title,
    required String availability,
    required String description,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.62),
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071B27),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFF69D9E8).withOpacity(0.50)),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFFFD166),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '$description\n\nAvailable on: $availability\n\nOpen Settings, then tap View plans / upgrade to see plan options.',
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: Color(0xFFA9C6CF)),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF143B4A),
                foregroundColor: const Color(0xFFE4EBEE),
              ),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Widget _premiumToolChip({
    required String label,
    required String title,
    required String availability,
    required String description,
    required IconData icon,
    bool comingSoon = false,
  }) {
    return ActionChip(
      avatar: Icon(
        comingSoon ? Icons.hourglass_top_rounded : icon,
        size: 18,
        color: comingSoon ? const Color(0xFFFFD166) : const Color(0xFF69D9E8),
      ),
      label: Text(label),
      labelStyle: const TextStyle(
        color: Color(0xFFE4EBEE),
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
      ),
      backgroundColor: Colors.black.withOpacity(0.28),
      side: BorderSide(
        color: comingSoon
            ? const Color(0xFFFFD166).withOpacity(0.40)
            : const Color(0xFF69D9E8).withOpacity(0.34),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onPressed: () => _showPremiumFeaturePrompt(
        title: title,
        availability: availability,
        description: description,
      ),
    );
  }

  Widget _chatPremiumIconButton({
    required IconData icon,
    required String title,
    required String availability,
    required String description,
    bool comingSoon = false,
  }) {
    final accent = comingSoon
        ? const Color(0xFFFFD166)
        : const Color(0xFF69D9E8);

    return SizedBox(
      width: 50,
      height: 56,
      child: OutlinedButton(
        onPressed: _loading
            ? null
            : () => _showPremiumFeaturePrompt(
                title: title,
                availability: availability,
                description: description,
              ),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: accent,
          backgroundColor: Colors.black.withOpacity(0.18),
          side: BorderSide(color: accent.withOpacity(0.42)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 23),
            Positioned(
              right: 5,
              top: 5,
              child: Icon(
                comingSoon ? Icons.hourglass_top_rounded : Icons.lock_rounded,
                size: 11,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasVoiceAccess {
    return true;
  }

  Future<void> _loadCurrentTier() async {
    if (kKorlixAccessToken == null || kKorlixAccessToken!.isEmpty) {
      return;
    }

    if (_loadingTier) {
      return;
    }

    setState(() {
      _loadingTier = true;
    });

    try {
      final response = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/me'),
        headers: _authHeaders(),
      );

      if (response.statusCode >= 400) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final profile =
          (data['profile'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      if (!mounted) {
        return;
      }

      setState(() {
        _currentTier = (profile['tier'] ?? 'basic').toString();
      });
    } catch (_) {
      // Tier loading should never block the app.
    } finally {
      if (mounted) {
        setState(() {
          _loadingTier = false;
        });
      }
    }
  }

  Future<void> _loadChatHistory() async {
    if (kKorlixAccessToken == null || kKorlixAccessToken!.isEmpty) return;
    if (_chatHistoryLoaded) return;
    try {
      final response = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/history'),
        headers: _authHeaders(),
      );
      if (response.statusCode >= 400) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final history = (data['history'] as List?) ?? [];
      if (!mounted) return;
      final msgs = <ChatMessage>[];
      for (final item in history.reversed) {
        final prompt = (item['prompt'] ?? '').toString();
        final resp = (item['response'] ?? '').toString();
        final lang = (item['language'] ?? 'en').toString();
        final resultType = (item['result_type'] ?? 'answer').toString();
        final createdAt =
            DateTime.tryParse((item['created_at'] ?? '').toString()) ??
            DateTime.now();
        if (prompt.isEmpty || resp.isEmpty) continue;
        msgs.add(
          ChatMessage(
            userText: prompt,
            aiText: resp,
            isImage: resultType == 'image',
            language: lang,
            allowPdf: resultType == 'file',
            createdAt: createdAt,
          ),
        );
      }
      setState(() {
        // Strict topic isolation: flat backend history is not loaded into
        // a new selected topic. Saved topics are restored only from
        // _localChatTopicsPrefsKey.
        if (_chatTopicsById.isEmpty) {
          _chatMessages.clear();
        }
        _chatHistoryLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.jumpTo(
            _chatScrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (_) {
      // Chat history loading should never block the app.
    }
  }

  String _utilityToolDescription(String tool) {
    switch (tool) {
      case 'Photo editor':
        return 'Upload a photo, describe the edits you want, then submit.';
      case 'Video splitter':
        return 'Upload a video and describe how you want it split.';
      case 'Background remover':
        return 'Upload a photo and Korlix AI will prepare it for background removal.';
      case 'PDF editor':
        return 'Upload a PDF and describe what you want edited, summarized, or extracted.';
      case 'Songwriter':
        return 'Describe the song style, topic, mood, hook, verse, or chorus you want.';
      case 'Voice recorder':
        return 'Record or upload voice notes for transcription, cleanup, or summaries.';
      case 'Notebook':
        return 'Create notes, ideas, reminders, plans, or saved thoughts.';
      case 'Alarm':
        return 'Create an in-app reminder or alarm-style note.';
      case 'Weather':
        return 'Use your location to ask for current weather or forecasts.';
      case 'Outside temperature':
        return 'Use your location to ask for the current outside temperature.';
      case 'GIF maker':
        return 'Upload media and describe the GIF you want to create.';
      case 'Ringtone maker':
        return 'Create or trim audio ideas for ringtone-style clips.';
      case 'Reel maker':
        return 'Plan or generate short-form reel concepts, captions, scenes, and scripts.';
      default:
        return 'Select a utility, then type what you want Korlix AI to do.';
    }
  }

  void _clearUtilitySelection() {
    _selectedUtilityTool = null;
    _utilityPanelOpen = false;
    _improvePictureMode = false;
    _fixCreditReportMode = false;

    _creditDebtValidationRoundsVisible = false;

    _creditDebtValidationRound = null;
  }

  void _toggleUtilityPanel() {
    if (_loading) {
      return;
    }

    setState(() {
      if (_utilityPanelOpen || _selectedUtilityTool != null) {
        _clearUtilitySelection();
      } else {
        _utilityPanelOpen = true;
      }
    });
  }

  String _utilityStarterPrompt(String tool) {
    switch (tool) {
      case 'Photo editor':
        return "Photo editor: Upload a photo, then describe the exact edits you want. Example: brighten it, sharpen details, remove blemishes, change the background, or make it look professional.";
      case 'Background remover':
        return "Background remover: Upload an image, then submit this request: remove the background cleanly, keep the main subject sharp, and return a polished cutout-style result.";
      case 'Songwriter':
        return "Songwriter: Write a song about [topic]. Genre: [genre]. Mood: [mood]. Include a title, verse 1, chorus, verse 2, bridge, and final chorus.";
      case 'Notebook':
        return "Notebook: Organize these notes into a clean notebook entry with headings, bullets, action items, and a short summary: ";
      case 'PDF editor':
        return "PDF editor: Upload a PDF, then tell me what you want done. Example: summarize it, rewrite a section, extract key points, turn it into notes, or draft edits.";
      case 'Video splitter':
        return "Video splitter: Upload or describe your video, then tell me how you want it split. Example: split into 30-second clips, chapters, scenes, reels, or highlights.";
      case 'Voice recorder':
        return "Voice recorder: Record or dictate your thoughts with the Voice button, then ask me to clean the transcript, summarize it, turn it into notes, or create action items.";
      case 'Alarm':
        return "Alarm: Tell me what you need to remember, the date, the time, and the repeat schedule. I can help format a reminder plan you can add to your device.";
      case 'Weather':
        return "Weather: Tell me the city or location you want weather for, or use Locator first, then ask for current conditions, forecast, and practical advice.";
      case 'Outside temperature':
        return "Outside temperature: Tell me your city or location, or use Locator first, then ask for the current outside temperature and what to wear.";
      case 'GIF maker':
        return "GIF maker: Upload media or describe the scene, then tell me the GIF style, length, captions, and motion you want.";
      case 'Ringtone maker':
        return "Ringtone maker: Describe the ringtone style, mood, length, instruments, and whether it should loop. I can draft the concept, lyrics, or sound direction.";
      case 'Reel maker':
        return "Reel maker: Tell me the topic, audience, tone, and target length. I can create a reel script, shot list, captions, hooks, and scene-by-scene plan.";
      default:
        return "Utility: Tell me what you want to do with $tool.";
    }
  }

  void _applyUtilityToolPrompt(String tool) {
    final prompt = _utilityStarterPrompt(tool);

    _controller.text = prompt;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _selectUtilityTool(String tool) {
    // KORLIX_BUILD109_HIDE_INACTIVE_UTILITY_GUARD
    if (_hiddenInactiveUtilityTools.contains(tool)) {
      setState(() {
        _clearUtilitySelection();
      });
      return;
    }

    if (_loading) {
      return;
    }

    setState(() {
      if (_selectedUtilityTool == tool) {
        _clearUtilitySelection();
        return;
      } else {
        _selectedUtilityTool = tool;
        _applyUtilityToolPrompt(tool);
      }

      _utilityPanelOpen = true;

      if (tool == 'Photo editor' || tool == 'Background remover') {
        _improvePictureMode = true;
        _fixCreditReportMode = false;

        _creditDebtValidationRoundsVisible = false;

        _creditDebtValidationRound = null;
      } else if (tool == 'PDF editor') {
        _improvePictureMode = false;
        _fixCreditReportMode = false;

        _creditDebtValidationRoundsVisible = false;

        _creditDebtValidationRound = null;
      } else {
        _improvePictureMode = false;
        _fixCreditReportMode = false;

        _creditDebtValidationRoundsVisible = false;

        _creditDebtValidationRound = null;
      }
    });
  }

  // KORLIX_MUSIC_STUDIO_PHASE1_BEGIN
  List<Map<String, dynamic>> _korlixMusicAddonPlans() {
    return <Map<String, dynamic>>[
      {
        'id': 'music_starter_75_monthly',
        'name': 'Music Starter',
        'priceMonthly': 25,
        'monthlyGenerations': 75,
        'description': 'Best for light creators testing hooks and song ideas.',
      },
      {
        'id': 'music_creator_580_monthly',
        'name': 'Music Creator',
        'priceMonthly': 120,
        'monthlyGenerations': 580,
        'description': 'For steady creators making music every week.',
      },
      {
        'id': 'music_studio_4000_monthly',
        'name': 'Music Studio',
        'priceMonthly': 450,
        'monthlyGenerations': 4000,
        'description': 'For high-volume content teams and agencies.',
      },
      {
        'id': 'music_producer_10000_monthly',
        'name': 'Music Producer',
        'priceMonthly': 950,
        'monthlyGenerations': 10000,
        'description': 'For serious production-scale music generation.',
      },
    ];
  }

  String _korlixMusicPlanLine(Map<String, dynamic> plan) {
    final name = (plan['name'] ?? 'Music Plan').toString();
    final price = (plan['priceMonthly'] ?? 0).toString();
    final generations = (plan['monthlyGenerations'] ?? 0).toString();

    return '$name • \$$price/mo • $generations generations';
  }

  Future<Map<String, dynamic>> _fetchMusicAddonStatus() async {
    final response = await http.get(
      _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/music/addon'),
      headers: _authHeaders(),
    );

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['details'] ?? data['error'] ?? response.body);
    }

    return data;
  }

  Future<Map<String, dynamic>> _startMusicGeneration({
    required String prompt,
    required String title,
    required String tags,
    required bool customMode,
    required String lyrics,
    required String vocalGender,
    required bool instrumentalOnly,
    required String model,
  }) async {
    final response = await http.post(
      _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/music/generate'),
      headers: _authHeaders(),
      body: jsonEncode({
        'prompt': prompt,
        'title': title,
        'tags': tags,
        'customMode': customMode,
        'lyrics': lyrics,
        'vocalGender': vocalGender,
        'instrumentalOnly': instrumentalOnly,
        'model': model,
      }),
    );

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['details'] ?? data['error'] ?? response.body);
    }

    return data;
  }

  Future<Map<String, dynamic>> _fetchMusicGenerationStatus(String jobId) async {
    final response = await http.get(
      _assertValidKorlixBackendUri(
        '$kKorlixBackendBaseUrl/api/music/status/$jobId',
      ),
      headers: _authHeaders(),
    );

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['details'] ?? data['error'] ?? response.body);
    }

    return data;
  }

  Future<void> _openMusicTrackUrl(String audioUrl) async {
    final trimmed = audioUrl.trim();

    if (trimmed.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(trimmed);

    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the music track.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildMusicPlanCard(
    KorlixSkinPalette skin,
    Map<String, dynamic> plan,
  ) {
    final name = (plan['name'] ?? 'Music Plan').toString();
    final price = (plan['priceMonthly'] ?? 0).toString();
    final generations = (plan['monthlyGenerations'] ?? 0).toString();
    final description = (plan['description'] ?? '').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.panel.withValues(alpha: skin.isLight ? 0.92 : 0.70),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: skin.primary.withValues(alpha: skin.isLight ? 0.55 : 0.70),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: skin.isLight ? 0.12 : 0.34),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: skin.primary.withValues(alpha: 0.16),
              border: Border.all(color: skin.primary.withValues(alpha: 0.68)),
            ),
            child: Icon(Icons.music_note_rounded, color: skin.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: _korlixReadableForeground(skin),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '\$$price/month • $generations generations',
                  style: TextStyle(
                    color: skin.secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      color: _korlixReadableForeground(skin, muted: true),
                      fontSize: 12,
                      height: 1.24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicTrackCard({
    required KorlixSkinPalette skin,
    required Map<String, dynamic> track,
    required String prompt,
    required AudioPlayer player,
  }) {
    final title = (track['title'] ?? 'Generated track').toString();
    final tags = (track['tags'] ?? '').toString();
    final lyrics = (track['lyrics'] ?? '').toString();
    final audioUrl = (track['audio_url'] ?? track['audioUrl'] ?? '').toString();
    final imageUrl = (track['image_url'] ?? track['imageUrl'] ?? '').toString();
    final clipId = (track['clip_id'] ?? track['clipId'] ?? '').toString();
    final duration = (track['duration'] ?? '').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.panelDeep.withValues(alpha: skin.isLight ? 0.94 : 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.secondary.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl.startsWith('http')
                    ? Image.network(
                        imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: skin.buttonFill,
                          child: Icon(Icons.album_rounded, color: skin.primary),
                        ),
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: skin.buttonFill,
                        child: Icon(Icons.album_rounded, color: skin.primary),
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _korlixReadableForeground(skin),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (tags.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tags,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _korlixReadableForeground(skin, muted: true),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (duration.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$duration seconds',
                        style: TextStyle(
                          color: skin.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (lyrics.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              lyrics,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _korlixReadableForeground(skin, muted: true),
                fontSize: 12.4,
                height: 1.32,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: audioUrl.trim().isEmpty
                    ? null
                    : () async {
                        try {
                          await player.stop();
                          await player.play(UrlSource(audioUrl));
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not play this track.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
              OutlinedButton.icon(
                onPressed: audioUrl.trim().isEmpty
                    ? null
                    : () => _openMusicTrackUrl(audioUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open'),
              ),
              _buildReportGeneratedContentPill(
                contentType: 'music',
                prompt: prompt,
                outputSummary:
                    'Generated music track: $title${clipId.isEmpty ? '' : ' • Clip ID: $clipId'}',
                contentId: clipId.isEmpty ? title : clipId,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKorlixBelowInputBeveledButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool locked = false,
    bool active = false,
    bool success = false,
    Color? accentColor,
    bool showStopIconWhenActive = false,
  }) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final disabled = onPressed == null;
    final isGreen = active || success;
    final accent =
        accentColor ?? (locked ? skin.premium : _korlixDefinitionBorder(skin));

    final normalFill = skin.isLight
        ? (Color.lerp(skin.buttonFill, const Color(0xFFFFFFFF), 0.76) ??
              const Color(0xFFFFFFFF))
        : skin.buttonFill.withValues(alpha: 0.80);

    final fill = isGreen ? skin.success : normalFill;
    final foreground = isGreen
        ? skin.textOnAccent
        : skin.isLight
        ? skin.text
        : _korlixReadableToolForeground(skin);

    final disabledForeground = skin.isLight
        ? skin.text.withValues(alpha: 0.72)
        : skin.mutedText.withValues(alpha: 0.70);

    final borderColor = isGreen ? skin.success : accent.withValues(alpha: 0.94);

    return _korlixBeveledButtonSurface(
      skin: skin,
      fill: fill,
      border: borderColor,
      active: isGreen,
      disabled: false,
      borderRadius: BorderRadius.circular(999),
      borderWidth: isGreen ? 2.2 : 1.85,
      depth: disabled ? 0.84 : 1.18,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              showStopIconWhenActive && active
                  ? Icons.stop_circle_outlined
                  : icon,
              size: 18,
            ),
            if (locked)
              Positioned(
                right: -7,
                top: -7,
                child: Icon(Icons.lock_rounded, size: 10, color: skin.premium),
              ),
          ],
        ),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: disabled ? disabledForeground : foreground,
          disabledForegroundColor: disabledForeground,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          side: BorderSide.none,
          padding: EdgeInsets.symmetric(
            horizontal: label.length > 18 ? 12 : 14,
            vertical: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  static const String _enterpriseCopyboxStorageKey =
      'korlix_enterprise_copybox_entries_v1';

  List<String> _normalizeEnterpriseCopyboxEntries(List<String> entries) {
    final normalized = List<String>.from(entries);

    while (normalized.length < 12) {
      normalized.add('');
    }

    return normalized;
  }

  Future<List<String>> _loadEnterpriseCopyboxEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries =
          prefs.getStringList(_enterpriseCopyboxStorageKey) ?? const <String>[];

      return _normalizeEnterpriseCopyboxEntries(entries);
    } catch (_) {
      return _normalizeEnterpriseCopyboxEntries(const <String>[]);
    }
  }

  Future<void> _saveEnterpriseCopyboxEntries(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _enterpriseCopyboxStorageKey,
      entries.map((entry) => entry.trimRight()).toList(growable: false),
    );
  }

  Future<void> _openEnterpriseCopyboxSheet() async {
    final loadedEntries = await _loadEnterpriseCopyboxEntries();

    if (!mounted) {
      return;
    }

    final controllers = loadedEntries
        .map((entry) => TextEditingController(text: entry))
        .toList();

    List<String> currentEntries() {
      return controllers
          .map((controller) => controller.text.trimRight())
          .toList(growable: false);
    }

    Future<void> saveEntries({bool showSnack = true}) async {
      await _saveEnterpriseCopyboxEntries(currentEntries());

      if (!mounted || !showSnack) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copybox saved.')));
    }

    Future<void> copyEntry(int index) async {
      final value = controllers[index].text.trimRight();

      await Clipboard.setData(ClipboardData(text: value));
      await _saveEnterpriseCopyboxEntries(currentEntries());

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value.trim().isEmpty
                ? 'Blank Copybox ${index + 1} copied.'
                : 'Copybox ${index + 1} copied.',
          ),
        ),
      );
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF07111F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
              final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.88,
                    minChildSize: 0.52,
                    maxChildSize: 0.96,
                    builder: (context, scrollController) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.business_center_rounded,
                                color: skin.premium,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Enterprise Copybox',
                                  style: TextStyle(
                                    color: skin.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                                color: skin.text,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Paste or type reusable text into separate boxes. Save them, then copy any box instantly.',
                            style: TextStyle(
                              color: skin.mutedText,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setSheetState(() {
                                      controllers.add(TextEditingController());
                                    });
                                  },
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: const Text('Add Box'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => saveEntries(),
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text('Save All'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: ListView.builder(
                              controller: scrollController,
                              itemCount: controllers.length,
                              itemBuilder: (context, index) {
                                final controller = controllers[index];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: skin.panel.withValues(
                                      alpha: skin.isLight ? 0.94 : 0.76,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: skin.premium.withValues(
                                        alpha: 0.44,
                                      ),
                                      width: 1.15,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: skin.premium.withValues(
                                          alpha: 0.10,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Box ${index + 1}',
                                            style: TextStyle(
                                              color: skin.premium,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.35,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: 'Copy Box ${index + 1}',
                                            onPressed: () => copyEntry(index),
                                            icon: const Icon(
                                              Icons.copy_rounded,
                                            ),
                                            color: skin.premium,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: controller,
                                        minLines: 2,
                                        maxLines: 7,
                                        onChanged: (_) {
                                          // Keep the controller state live. The
                                          // Save All button persists every box.
                                        },
                                        style: TextStyle(
                                          color: skin.text,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Type or paste text here...',
                                          hintStyle: TextStyle(
                                            color: skin.hintText.withValues(
                                              alpha: 0.76,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: skin.inputFill.withValues(
                                            alpha: skin.isLight ? 0.96 : 0.72,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: skin.border.withValues(
                                                alpha: 0.46,
                                              ),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: skin.premium,
                                              width: 1.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      );

      await saveEntries(showSnack: false);
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  static const String _enterpriseVoiceScribeStorageKey =
      'korlix_enterprise_voice_scribe_boxes_v1';

  List<String> _normalizeEnterpriseVoiceBoxEntries(List<String> entries) {
    final normalized = List<String>.from(entries);

    while (normalized.length < 8) {
      normalized.add('');
    }

    return normalized;
  }

  Future<List<String>> _loadEnterpriseVoiceBoxes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries =
          prefs.getStringList(_enterpriseVoiceScribeStorageKey) ??
          const <String>[];

      return _normalizeEnterpriseVoiceBoxEntries(entries);
    } catch (_) {
      return _normalizeEnterpriseVoiceBoxEntries(const <String>[]);
    }
  }

  Future<void> _saveEnterpriseVoiceBoxes(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _enterpriseVoiceScribeStorageKey,
      entries.map((entry) => entry.trimRight()).toList(growable: false),
    );
  }

  Future<void> _openEnterpriseVoiceScribeSheet() async {
    final loadedEntries = await _loadEnterpriseVoiceBoxes();

    if (!mounted) {
      return;
    }

    final controllers = loadedEntries
        .map((entry) => TextEditingController(text: entry))
        .toList();

    final voice = speech_to_text.SpeechToText();
    int? listeningIndex;
    bool voiceReady = false;
    bool voiceInitAttempted = false;
    String statusText = 'Tap a Voice Box microphone, speak, then press Stop.';
    String activeSessionBaseText = '';

    List<String> currentEntries() {
      return controllers
          .map((controller) => controller.text.trimRight())
          .toList(growable: false);
    }

    Future<void> saveEntries({bool showSnack = false}) async {
      await _saveEnterpriseVoiceBoxes(currentEntries());

      if (!mounted || !showSnack) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice-scribe saved.')));
    }

    Future<void> copyEntry(int index) async {
      final value = controllers[index].text.trimRight();

      await Clipboard.setData(ClipboardData(text: value));
      await _saveEnterpriseVoiceBoxes(currentEntries());

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice Box ${index + 1} copied.')));
    }

    Future<void> stopListening(StateSetter setSheetState) async {
      try {
        await voice.stop();
      } catch (_) {
        // Stop failures should not block saving the voice box text.
      }

      listeningIndex = null;
      statusText = 'Voice-scribe stopped. Text auto-saved.';
      await saveEntries();

      setSheetState(() {});
    }

    Future<void> startListening(int index, StateSetter setSheetState) async {
      if (listeningIndex != null && listeningIndex != index) {
        await stopListening(setSheetState);
      }

      if (listeningIndex == index) {
        await stopListening(setSheetState);
        return;
      }

      if (!voiceInitAttempted) {
        voiceInitAttempted = true;
        voiceReady = await voice.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              listeningIndex = null;
              statusText = 'Voice-scribe paused. Tap the mic to continue.';
              unawaited(saveEntries());
              try {
                setSheetState(() {});
              } catch (_) {}
            }
          },
          onError: (error) {
            listeningIndex = null;
            statusText = 'Voice-scribe error: ${error.errorMsg}';
            unawaited(saveEntries());
            try {
              setSheetState(() {});
            } catch (_) {}
          },
        );
      }

      if (!voiceReady) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voice-scribe microphone is not available. Check microphone and speech permissions.',
            ),
          ),
        );
        return;
      }

      activeSessionBaseText = controllers[index].text.trimRight();
      listeningIndex = index;
      statusText = 'Listening to Voice Box ${index + 1}. Press Stop when done.';
      setSheetState(() {});

      try {
        await voice.listen(
          partialResults: true,
          cancelOnError: false,
          onResult: (result) {
            final recognized = result.recognizedWords.trim();

            if (recognized.isEmpty) {
              return;
            }

            final combined = activeSessionBaseText.isEmpty
                ? recognized
                : '$activeSessionBaseText\n$recognized';

            controllers[index].value = TextEditingValue(
              text: combined,
              selection: TextSelection.collapsed(offset: combined.length),
            );

            unawaited(saveEntries());

            try {
              setSheetState(() {});
            } catch (_) {}
          },
        );
      } catch (_) {
        listeningIndex = null;
        statusText =
            'Voice-scribe could not start. Check microphone permission.';
        setSheetState(() {});
      }
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF07111F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
              final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.90,
                    minChildSize: 0.55,
                    maxChildSize: 0.97,
                    builder: (context, scrollController) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.mic_rounded, color: skin.premium),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Enterprise Voice-scribe',
                                  style: TextStyle(
                                    color: skin.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                                color: skin.text,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Each Voice Box can be typed, pasted, dictated, edited, copied, and auto-saved.',
                            style: TextStyle(
                              color: skin.mutedText,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: skin.panel.withValues(
                                alpha: skin.isLight ? 0.92 : 0.62,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: skin.premium.withValues(alpha: 0.42),
                              ),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: skin.text,
                                fontSize: 12.8,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setSheetState(() {
                                      controllers.add(TextEditingController());
                                    });
                                    unawaited(saveEntries());
                                  },
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: const Text('Add Voice Box'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => saveEntries(showSnack: true),
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text('Save All'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: ListView.builder(
                              controller: scrollController,
                              itemCount: controllers.length,
                              itemBuilder: (context, index) {
                                final controller = controllers[index];
                                final isListening = listeningIndex == index;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: skin.panel.withValues(
                                      alpha: skin.isLight ? 0.95 : 0.74,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isListening
                                          ? skin.success.withValues(alpha: 0.86)
                                          : skin.premium.withValues(
                                              alpha: 0.42,
                                            ),
                                      width: isListening ? 1.9 : 1.15,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isListening
                                                    ? skin.success
                                                    : skin.premium)
                                                .withValues(alpha: 0.12),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Voice Box ${index + 1}',
                                            style: TextStyle(
                                              color: isListening
                                                  ? skin.success
                                                  : skin.premium,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.35,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip:
                                                'Copy Voice Box ${index + 1}',
                                            onPressed: () => copyEntry(index),
                                            icon: const Icon(
                                              Icons.copy_rounded,
                                            ),
                                            color: skin.premium,
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Clear Voice Box ${index + 1}',
                                            onPressed: () {
                                              controller.clear();
                                              unawaited(saveEntries());
                                              setSheetState(() {});
                                            },
                                            icon: const Icon(
                                              Icons.clear_rounded,
                                            ),
                                            color: skin.mutedText,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: controller,
                                        minLines: 3,
                                        maxLines: 9,
                                        onChanged: (_) =>
                                            unawaited(saveEntries()),
                                        style: TextStyle(
                                          color: skin.text,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Speak, type, or paste script text here...',
                                          hintStyle: TextStyle(
                                            color: skin.hintText.withValues(
                                              alpha: 0.76,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: skin.inputFill.withValues(
                                            alpha: skin.isLight ? 0.96 : 0.72,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: skin.border.withValues(
                                                alpha: 0.46,
                                              ),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: skin.premium,
                                              width: 1.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Center(
                                        child: FilledButton.icon(
                                          onPressed: () => startListening(
                                            index,
                                            setSheetState,
                                          ),
                                          icon: Icon(
                                            isListening
                                                ? Icons.stop_circle_rounded
                                                : Icons.mic_rounded,
                                          ),
                                          label: Text(
                                            isListening
                                                ? 'Stop Voice Box ${index + 1}'
                                                : 'Start Mic',
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isListening
                                                ? skin.success
                                                : skin.premium,
                                            foregroundColor: skin.textOnAccent,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 13,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      );

      await saveEntries();
    } finally {
      try {
        await voice.stop();
      } catch (_) {}

      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  // KORLIX_CUSTOM_ACCESS_FRONTEND_V1_BEGIN
  List<Map<String, dynamic>> _customAccessMapList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => item.map<String, dynamic>(
            (key, itemValue) => MapEntry(key.toString(), itemValue),
          ),
        )
        .toList(growable: false);
  }

  String _customAccessFeatureKey(Map<String, dynamic> item) {
    return (item['featureKey'] ?? item['feature_key'] ?? '').toString().trim();
  }

  bool _customAccessItemBool(
    Map<String, dynamic> item,
    String camel,
    String snake,
  ) {
    return item[camel] == true || item[snake] == true;
  }

  bool _customAccessFeatureExpired(Map<String, dynamic> item) {
    final raw = (item['expiresAt'] ?? item['expires_at'] ?? '')
        .toString()
        .trim();

    if (raw.isEmpty || raw.toLowerCase() == 'null') {
      return false;
    }

    final expiresAt = DateTime.tryParse(raw);

    if (expiresAt == null) {
      return false;
    }

    return !expiresAt.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool _customAccessHasFeature(String featureKey) {
    final normalizedFeature = featureKey.trim().toLowerCase();

    if (normalizedFeature.isEmpty) {
      return false;
    }

    return _customAccessFeatures.any((item) {
      final key = _customAccessFeatureKey(item).toLowerCase();
      final status = (item['status'] ?? 'active').toString().toLowerCase();

      return key == normalizedFeature &&
          status == 'active' &&
          !_customAccessFeatureExpired(item);
    });
  }

  String _customAccessFeatureLabel(String featureKey) {
    switch (featureKey.trim().toLowerCase()) {
      case 'copybox':
        return 'Copybox';
      case 'voice_scribe':
      case 'voice-scribe':
      case 'voiceScribe':
        return 'Voice-scribe';
      case 'image_to_video':
      case 'image-to-video':
        return 'Image to Video';
      case 'music_studio':
      case 'music-studio':
        return 'Music Studio';
      case 'document_upload':
      case 'document-upload':
        return 'Advanced Document Upload';
      default:
        return featureKey.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    }
  }

  String _customAccessFeatureDescription(String featureKey) {
    switch (featureKey.trim().toLowerCase()) {
      case 'copybox':
        return 'Reusable saved text blocks for business workflows.';
      case 'voice_scribe':
      case 'voice-scribe':
      case 'voiceScribe':
        return 'Voice transcription saved into reusable boxes.';
      case 'image_to_video':
      case 'image-to-video':
        return 'Turn a still image into a generated video.';
      case 'music_studio':
      case 'music-studio':
        return 'Music workflow and creation support.';
      case 'document_upload':
      case 'document-upload':
        return 'Custom document workflow add-on.';
      default:
        return 'Custom Korlix add-on.';
    }
  }

  IconData _customAccessFeatureIcon(String featureKey) {
    switch (featureKey.trim().toLowerCase()) {
      case 'copybox':
        return Icons.content_copy_rounded;
      case 'voice_scribe':
      case 'voice-scribe':
      case 'voiceScribe':
        return Icons.mic_rounded;
      case 'image_to_video':
      case 'image-to-video':
        return Icons.movie_creation_outlined;
      case 'music_studio':
      case 'music-studio':
        return Icons.music_note_rounded;
      case 'document_upload':
      case 'document-upload':
        return Icons.upload_file_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  List<Map<String, dynamic>> _customAccessFallbackCatalog() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'featureKey': 'copybox',
        'label': 'Copybox',
        'description': 'Reusable saved text blocks for business workflows.',
        'includedInTrial': true,
        'requiresPayment': false,
      },
      <String, dynamic>{
        'featureKey': 'voice_scribe',
        'label': 'Voice-scribe',
        'description': 'Voice transcription saved into reusable boxes.',
        'includedInTrial': true,
        'requiresPayment': false,
      },
      <String, dynamic>{
        'featureKey': 'image_to_video',
        'label': 'Image to Video',
        'description': 'Turn a still image into a generated video.',
        'includedInTrial': false,
        'requiresPayment': true,
      },
      <String, dynamic>{
        'featureKey': 'music_studio',
        'label': 'Music Studio',
        'description': 'Music workflow and creation support.',
        'includedInTrial': false,
        'requiresPayment': true,
      },
    ];
  }

  List<Map<String, dynamic>> get _customAccessCatalogOrFallback {
    if (_customAccessCatalog.isNotEmpty) {
      return _customAccessCatalog;
    }

    return _customAccessFallbackCatalog();
  }

  Future<void> _showKorlixNotice({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }

    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: skin.panelDeep,
          title: Text(
            title,
            style: TextStyle(color: skin.text, fontWeight: FontWeight.w900),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: skin.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _customAccessPostJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .post(
          _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl$path'),
          headers: _authHeaders(),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 35));

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ??
            data['error']?.toString() ??
            'Custom Access request failed.',
      );
    }

    return data;
  }

  Future<void> _refreshCustomAccess({
    StateSetter? sheetSetState,
    bool showErrors = false,
  }) async {
    if (mounted) {
      setState(() {
        _customAccessLoading = true;
        _customAccessMessage = null;
      });
    }
    sheetSetState?.call(() {});

    try {
      final response = await http
          .get(
            _assertValidKorlixBackendUri(
              '$kKorlixBackendBaseUrl/api/custom-access/me',
            ),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 35));

      final data = _decodeKorlixJsonMap(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['message']?.toString() ??
              data['error']?.toString() ??
              'Could not load Custom Access.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _customAccessFeatures = _customAccessMapList(data['features']);
        _customAccessCatalog = _customAccessMapList(data['catalog']);
        _customAccessLoading = false;
        _customAccessMessage = null;
      });
      sheetSetState?.call(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = korlixFriendlyErrorMessage(error);

      setState(() {
        _customAccessLoading = false;
        _customAccessMessage = message;
      });
      sheetSetState?.call(() {});

      if (showErrors) {
        await _showKorlixNotice(title: 'Custom Access', message: message);
      }
    }
  }

  Future<void> _requestCustomAccessCode(StateSetter sheetSetState) async {
    if (mounted) {
      setState(() {
        _customAccessLoading = true;
        _customAccessMessage = null;
      });
    }
    sheetSetState(() {});

    try {
      final data = await _customAccessPostJson(
        '/api/custom-access/request-code',
      );

      final message =
          data['message']?.toString() ??
          'Request received. A Korlix access code will be sent to your account email within 24 hours.';

      if (!mounted) {
        return;
      }

      setState(() {
        _customAccessLoading = false;
        _customAccessMessage = message;
      });
      sheetSetState(() {});

      await _showKorlixNotice(title: 'Request received', message: message);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = korlixFriendlyErrorMessage(error);

      setState(() {
        _customAccessLoading = false;
        _customAccessMessage = message;
      });
      sheetSetState(() {});

      await _showKorlixNotice(
        title: 'Custom Access request failed',
        message: message,
      );
    }
  }

  Future<void> _promptAndRedeemCustomAccessCode(
    StateSetter sheetSetState,
  ) async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071B27),
          title: const Text(
            'Enter Custom Access Code',
            style: TextStyle(color: Color(0xFFE4EBEE)),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Access code',
              hintText: 'KX-AB12-CD34-EF56',
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Redeem'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (code == null || code.trim().isEmpty) {
      return;
    }

    await _redeemCustomAccessCode(code.trim(), sheetSetState);
  }

  Future<void> _redeemCustomAccessCode(
    String code,
    StateSetter sheetSetState,
  ) async {
    if (mounted) {
      setState(() {
        _customAccessLoading = true;
        _customAccessMessage = null;
      });
    }
    sheetSetState(() {});

    try {
      final data = await _customAccessPostJson(
        '/api/custom-access/redeem-code',
        body: <String, dynamic>{'code': code},
      );

      final message = data['message']?.toString() ?? 'Custom Access unlocked.';

      await _refreshCustomAccess(sheetSetState: sheetSetState);

      if (!mounted) {
        return;
      }

      setState(() {
        _customAccessLoading = false;
        _customAccessMessage = message;
      });
      sheetSetState(() {});

      await _showKorlixNotice(
        title: 'Custom Access unlocked',
        message: message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = korlixFriendlyErrorMessage(error);

      setState(() {
        _customAccessLoading = false;
        _customAccessMessage = message;
      });
      sheetSetState(() {});

      await _showKorlixNotice(title: 'Code not accepted', message: message);
    }
  }

  Future<void> _openCustomAccessFeature(String featureKey) async {
    switch (featureKey.trim().toLowerCase()) {
      case 'copybox':
        await _openEnterpriseCopyboxSheet();
        return;
      case 'voice_scribe':
      case 'voice-scribe':
      case 'voicescribe':
        await _openEnterpriseVoiceScribeSheet();
        return;
      case 'image_to_video':
      case 'image-to-video':
        await _openImageToVideoStudio();
        return;
      case 'music_studio':
      case 'music-studio':
        await _showMusicStudio();
        return;
      default:
        await _showKorlixNotice(
          title: 'Custom add-on active',
          message:
              '${_customAccessFeatureLabel(featureKey)} is active for your account.',
        );
    }
  }

  Widget _buildCustomAccessFeatureTile({
    required BuildContext sheetContext,
    required Map<String, dynamic> item,
    required bool included,
  }) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final featureKey = _customAccessFeatureKey(item);
    final label = (item['label'] ?? _customAccessFeatureLabel(featureKey))
        .toString();
    final description =
        (item['description'] ?? _customAccessFeatureDescription(featureKey))
            .toString();
    final requiresPayment = _customAccessItemBool(
      item,
      'requiresPayment',
      'requires_payment',
    );
    final unlocked = _customAccessHasFeature(featureKey);

    final statusLabel = unlocked
        ? 'Active'
        : included
        ? 'Included with code'
        : requiresPayment
        ? 'Paid add-on'
        : 'Available';

    final statusColor = unlocked
        ? const Color(0xFFB7FF00)
        : included
        ? skin.primary
        : skin.premium;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skin.panel.withValues(alpha: skin.isLight ? 0.92 : 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: unlocked ? 0.70 : 0.38),
          width: unlocked ? 1.6 : 1.1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_customAccessFeatureIcon(featureKey), color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: skin.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: skin.mutedText,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: unlocked
                ? () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_openCustomAccessFeature(featureKey));
                  }
                : null,
            child: Text(unlocked ? 'Open' : 'Locked'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomAccessSheet() async {
    await _refreshCustomAccess();

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
            final catalog = _customAccessCatalogOrFallback;
            final included = catalog
                .where(
                  (item) => _customAccessItemBool(
                    item,
                    'includedInTrial',
                    'included_in_trial',
                  ),
                )
                .toList(growable: false);
            final paidAddons = catalog
                .where(
                  (item) => !_customAccessItemBool(
                    item,
                    'includedInTrial',
                    'included_in_trial',
                  ),
                )
                .toList(growable: false);

            final hasIncludedAccess =
                _customAccessHasFeature('copybox') ||
                _customAccessHasFeature('voice_scribe');

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.90,
                  minChildSize: 0.56,
                  maxChildSize: 0.96,
                  builder: (context, scrollController) {
                    return ListView(
                      controller: scrollController,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              hasIncludedAccess
                                  ? Icons.verified_user_rounded
                                  : Icons.business_center_rounded,
                              color: hasIncludedAccess
                                  ? const Color(0xFFB7FF00)
                                  : skin.premium,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Custom Access',
                                style: TextStyle(
                                  color: skin.text,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: skin.text,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Request a 7-day access code or enter a code sent by Korlix support. Codes unlock Copybox and Voice-scribe for your account email. Paid add-ons appear here and become openable only after payment/entitlement is active.',
                          style: TextStyle(
                            color: skin.mutedText,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _customAccessLoading
                                    ? null
                                    : () => unawaited(
                                        _requestCustomAccessCode(setSheetState),
                                      ),
                                icon: const Icon(Icons.mail_outline_rounded),
                                label: const Text('Request a Code'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _customAccessLoading
                                    ? null
                                    : () => unawaited(
                                        _promptAndRedeemCustomAccessCode(
                                          setSheetState,
                                        ),
                                      ),
                                icon: const Icon(Icons.password_rounded),
                                label: const Text('Enter a Code'),
                              ),
                            ),
                          ],
                        ),
                        if (_customAccessLoading) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                        if (_customAccessMessage != null &&
                            _customAccessMessage!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: skin.panelDeep.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: skin.primary.withValues(alpha: 0.34),
                              ),
                            ),
                            child: Text(
                              _customAccessMessage!,
                              style: TextStyle(
                                color: skin.text,
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          'Included with free 7-day access',
                          style: TextStyle(
                            color: skin.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final item in included)
                          _buildCustomAccessFeatureTile(
                            sheetContext: sheetContext,
                            item: item,
                            included: true,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Paid add-ons',
                          style: TextStyle(
                            color: skin.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A paid add-on button becomes active only after payment or support grants that specific add-on to your account.',
                          style: TextStyle(
                            color: skin.mutedText,
                            fontSize: 12.5,
                            height: 1.28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final item in paidAddons)
                          _buildCustomAccessFeatureTile(
                            sheetContext: sheetContext,
                            item: item,
                            included: false,
                          ),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
  // KORLIX_CUSTOM_ACCESS_FRONTEND_V1_END

  // KORLIX_CUSTOM_ACCESS_GATE_BUTTON_V1
  Widget _buildEnterpriseCopyboxButton() {
    final hasCustomAccess =
        _customAccessHasFeature('copybox') ||
        _customAccessHasFeature('voice_scribe');

    return _buildKorlixBelowInputBeveledButton(
      icon: hasCustomAccess
          ? Icons.verified_user_rounded
          : Icons.business_center_rounded,
      label: 'Custom Access',
      onPressed: _loading ? null : () => unawaited(_showCustomAccessSheet()),
      active: hasCustomAccess,
      success: hasCustomAccess,
      locked: false,
    );
  }

  Widget _buildMusicStudioButton() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return _buildKorlixBelowInputBeveledButton(
      icon: Icons.library_music_rounded,
      label: 'Music Studio',
      onPressed: _loading ? null : _showMusicStudio,
      accentColor: skin.secondary,
    );
  }

  // KORLIX_MUSIC_DISTRIBUTION_PRELAUNCH_SLOT_BEGIN
  List<Widget> _korlixMusicDistributionPrelaunchButtonSlots() {
    if (!kKorlixMusicDistributionPrelaunchVisible) {
      return const <Widget>[];
    }

    return <Widget>[Builder(builder: (_) => _buildMusicDistributionButton())];
  }
  // KORLIX_MUSIC_DISTRIBUTION_PRELAUNCH_SLOT_END

  Widget _buildMusicDistributionButton() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return _buildKorlixBelowInputBeveledButton(
      icon: Icons.public_rounded,
      label: 'Music Distribution',
      onPressed: _loading ? null : _showMusicDistribution,
      accentColor: skin.secondary,
    );
  }

  Future<void> _showMusicDistribution() async {
    if (!kKorlixMusicDistributionPrelaunchVisible) {
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Music Distribution'),
        content: const Text(
          'Welcome to Korlix Music Distribution.\n\n'
          'The new dashboard will be added in Build 90.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMusicStudio() async {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final promptController = TextEditingController();
    final titleController = TextEditingController();
    final tagsController = TextEditingController(
      text: 'dancehall, reggae, pop, polished, radio-ready',
    );
    final lyricsController = TextEditingController();
    final musicPlayer = AudioPlayer();

    var customMode = false;
    var instrumentalOnly = false;
    var vocalGender = 'auto';
    var model = 'sonic-v5';

    var startedLoad = false;
    var loadingAddon = true;
    var generating = false;
    var polling = false;
    var statusText = 'Checking Music Production add-on…';
    String? errorText;
    Map<String, dynamic>? addonStatus;
    String? jobId;
    List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[];

    Future<void> loadAddon(StateSetter setDialogState) async {
      try {
        final data = await _fetchMusicAddonStatus();

        setDialogState(() {
          addonStatus = data;
          loadingAddon = false;
          statusText = data['active'] == true
              ? 'Music Production add-on active.'
              : 'Music Production add-on required.';
        });
      } catch (error) {
        setDialogState(() {
          loadingAddon = false;
          errorText = korlixFriendlyErrorMessage(error);
          statusText = 'Could not check Music Production access.';
        });
      }
    }

    Future<void> pollMusicJob(
      StateSetter setDialogState,
      String safeJobId,
    ) async {
      polling = true;

      for (var attempt = 0; attempt < 36; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 5));

        if (!mounted) {
          return;
        }

        try {
          final data = await _fetchMusicGenerationStatus(safeJobId);
          final status = (data['status'] ?? 'processing').toString();
          final rawTracks = (data['tracks'] as List?) ?? <dynamic>[];

          setDialogState(() {
            statusText = 'Status: $status';
            tracks = rawTracks
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList();
          });

          if (status == 'completed' || status == 'failed') {
            setDialogState(() {
              generating = false;
              polling = false;
              if (status == 'failed') {
                errorText =
                    data['error']?.toString() ?? 'Music generation failed.';
              }
            });
            return;
          }
        } catch (error) {
          setDialogState(() {
            generating = false;
            polling = false;
            errorText = korlixFriendlyErrorMessage(error);
          });
          return;
        }
      }

      if (mounted) {
        setDialogState(() {
          generating = false;
          polling = false;
          statusText =
              'Still processing. Reopen Music Studio and check the task later.';
        });
      }
    }

    Future<void> generateMusic(StateSetter setDialogState) async {
      final prompt = promptController.text.trim();
      final title = titleController.text.trim();
      final tags = tagsController.text.trim();
      final lyrics = lyricsController.text.trim();

      if (prompt.isEmpty && lyrics.isEmpty) {
        setDialogState(() {
          errorText = 'Describe the song, or paste lyrics first.';
        });
        return;
      }

      setDialogState(() {
        generating = true;
        errorText = null;
        tracks = <Map<String, dynamic>>[];
        statusText = 'Submitting MusicAPI.ai generation…';
      });

      try {
        final data = await _startMusicGeneration(
          prompt: prompt,
          title: title,
          tags: tags,
          customMode: customMode,
          lyrics: lyrics,
          vocalGender: vocalGender,
          instrumentalOnly: instrumentalOnly,
          model: model,
        );

        final safeJobId = (data['jobId'] ?? '').toString();

        if (safeJobId.trim().isEmpty) {
          throw Exception('Music job ID was not returned.');
        }

        setDialogState(() {
          jobId = safeJobId;
          statusText = 'Music job submitted. Waiting for tracks…';
        });

        await pollMusicJob(setDialogState, safeJobId);
      } catch (error) {
        setDialogState(() {
          generating = false;
          polling = false;
          errorText = korlixFriendlyErrorMessage(error);
          statusText = 'Music generation could not start.';
        });
      }
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!startedLoad) {
              startedLoad = true;
              Future.microtask(() => loadAddon(setDialogState));
            }

            final addon = addonStatus ?? <String, dynamic>{};
            final active = addon['active'] == true;
            final providerReady = addon['providerReady'] == true;
            final usage =
                (addon['usage'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final used = (usage['usedThisCycle'] ?? 0).toString();
            final limit = (usage['monthlyLimit'] ?? 0).toString();
            final plans =
                ((addon['plans'] as List?) ?? _korlixMusicAddonPlans())
                    .whereType<Map>()
                    .map((item) => item.cast<String, dynamic>())
                    .toList();

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 20,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 650),
                decoration: BoxDecoration(
                  color: skin.panelDeep.withValues(
                    alpha: skin.isLight ? 0.98 : 0.96,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: skin.secondary.withValues(alpha: 0.80),
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: skin.secondary.withValues(alpha: 0.20),
                      blurRadius: 35,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    skin.primary,
                                    skin.secondary,
                                    skin.premium,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.library_music_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Korlix Music Studio',
                                    style: TextStyle(
                                      color: _korlixReadableForeground(skin),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'Powered by MusicAPI.ai • Paid add-on for any Korlix tier.',
                                    style: TextStyle(
                                      color: _korlixReadableForeground(
                                        skin,
                                        muted: true,
                                      ),
                                      fontSize: 12.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await musicPlayer.stop();
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: _korlixReadableForeground(skin),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: skin.panel.withValues(
                              alpha: skin.isLight ? 0.94 : 0.72,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: active
                                  ? skin.success.withValues(alpha: 0.80)
                                  : skin.premium.withValues(alpha: 0.80),
                            ),
                          ),
                          child: Text(
                            loadingAddon
                                ? 'Checking Music Production access…'
                                : active
                                ? 'Add-on active • $used / $limit generations used this cycle.'
                                : 'Music Production add-on required. Choose a monthly add-on plan to unlock generation.',
                            style: TextStyle(
                              color: _korlixReadableForeground(skin),
                              fontWeight: FontWeight.w800,
                              height: 1.32,
                            ),
                          ),
                        ),
                        if (!active) ...[
                          const SizedBox(height: 14),
                          for (final plan in plans)
                            _buildMusicPlanCard(skin, plan),
                          const SizedBox(height: 8),
                          Text(
                            'Payment connection note: Android should map these plans to Google Play Billing subscriptions, iOS to Apple subscriptions, and web to Stripe or your payment provider. Backend entitlement is already prepared for plan activation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _korlixReadableForeground(
                                skin,
                                muted: true,
                              ),
                              fontSize: 12.2,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 14),
                          if (!providerReady)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Backend is missing MUSICAPI_KEY or MUSICAPI_API_KEY. Add the key to the backend environment before generating.',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          TextField(
                            controller: promptController,
                            minLines: 2,
                            maxLines: 4,
                            style: TextStyle(
                              color: _korlixReadableForeground(skin),
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Song prompt',
                              hintText:
                                  'Example: upbeat dancehall anthem about winning, clean radio vocals, powerful chorus',
                              labelStyle: TextStyle(color: skin.primary),
                              hintStyle: TextStyle(
                                color: _korlixReadableForeground(
                                  skin,
                                  hint: true,
                                ).withValues(alpha: 0.72),
                              ),
                              filled: true,
                              fillColor: skin.inputFill.withValues(alpha: 0.86),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: titleController,
                                  style: TextStyle(
                                    color: _korlixReadableForeground(skin),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Title optional',
                                    labelStyle: TextStyle(color: skin.primary),
                                    filled: true,
                                    fillColor: skin.inputFill.withValues(
                                      alpha: 0.86,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: tagsController,
                                  style: TextStyle(
                                    color: _korlixReadableForeground(skin),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Genres / tags',
                                    labelStyle: TextStyle(color: skin.primary),
                                    filled: true,
                                    fillColor: skin.inputFill.withValues(
                                      alpha: 0.86,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            value: customMode,
                            activeThumbColor: skin.secondary,
                            title: Text(
                              'Use my lyrics',
                              style: TextStyle(
                                color: _korlixReadableForeground(skin),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              'Turn on to paste structured lyrics with [Verse] and [Chorus].',
                              style: TextStyle(
                                color: _korlixReadableForeground(
                                  skin,
                                  muted: true,
                                ),
                              ),
                            ),
                            onChanged: generating
                                ? null
                                : (value) => setDialogState(() {
                                    customMode = value;
                                  }),
                          ),
                          if (customMode) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: lyricsController,
                              minLines: 4,
                              maxLines: 8,
                              style: TextStyle(
                                color: _korlixReadableForeground(skin),
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Lyrics',
                                hintText: '[Verse]\n...\n\n[Chorus]\n...',
                                labelStyle: TextStyle(color: skin.primary),
                                filled: true,
                                fillColor: skin.inputFill.withValues(
                                  alpha: 0.86,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              ChoiceChip(
                                selected: model == 'sonic-v5',
                                label: const Text('Sonic v5'),
                                onSelected: generating
                                    ? null
                                    : (_) => setDialogState(() {
                                        model = 'sonic-v5';
                                      }),
                              ),
                              ChoiceChip(
                                selected: vocalGender == 'auto',
                                label: const Text('Auto vocal'),
                                onSelected: generating
                                    ? null
                                    : (_) => setDialogState(() {
                                        vocalGender = 'auto';
                                      }),
                              ),
                              ChoiceChip(
                                selected: vocalGender == 'm',
                                label: const Text('Male vocal'),
                                onSelected: generating
                                    ? null
                                    : (_) => setDialogState(() {
                                        vocalGender = 'm';
                                      }),
                              ),
                              ChoiceChip(
                                selected: vocalGender == 'f',
                                label: const Text('Female vocal'),
                                onSelected: generating
                                    ? null
                                    : (_) => setDialogState(() {
                                        vocalGender = 'f';
                                      }),
                              ),
                              ChoiceChip(
                                selected: instrumentalOnly,
                                label: const Text('Instrumental direction'),
                                onSelected: generating
                                    ? null
                                    : (_) => setDialogState(() {
                                        instrumentalOnly = !instrumentalOnly;
                                      }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: generating || !providerReady
                                  ? null
                                  : () => generateMusic(setDialogState),
                              icon: generating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                generating || polling
                                    ? 'Generating music…'
                                    : 'Generate Music',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _korlixReadableForeground(
                                skin,
                                muted: true,
                              ),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (jobId != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Job: $jobId',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _korlixReadableForeground(
                                  skin,
                                  muted: true,
                                ),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (errorText != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              errorText!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          for (final track in tracks)
                            _buildMusicTrackCard(
                              skin: skin,
                              track: track,
                              prompt: promptController.text,
                              player: musicPlayer,
                            ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'AI-generated music may contain mistakes or unintended similarities. Review lyrics, rights, and commercial-use terms before publishing.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _korlixReadableForeground(skin, muted: true),
                            fontSize: 11.8,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await musicPlayer.dispose();
    promptController.dispose();
    titleController.dispose();
    tagsController.dispose();
    lyricsController.dispose();
  }
  // KORLIX_MUSIC_STUDIO_PHASE1_END

  Widget _buildUtilityButton() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final isActive = _utilityPanelOpen || _selectedUtilityTool != null;

    return _buildKorlixBelowInputBeveledButton(
      icon: Icons.build_circle_outlined,
      label: 'Utility',
      onPressed: _loading ? null : _toggleUtilityPanel,
      active: isActive,
      success: isActive,
      accentColor: _korlixDefinitionBorder(skin),
    );
  }

  Widget _buildUtilityPanel() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final selectedTool = _selectedUtilityTool;

    final guidedOnlyTools = <String>{
      'Video splitter',
      'Alarm',
      'Weather',
      'Outside temperature',
      'GIF maker',
      'Ringtone maker',
      'Reel maker',
    };

    final uploadAssistedTools = <String>{
      'Photo editor',
      'Background remover',
      'PDF editor',
    };

    String statusFor(String tool) {
      if (guidedOnlyTools.contains(tool)) {
        return 'Guided workflow — not a full native tool yet';
      }

      if (uploadAssistedTools.contains(tool)) {
        return 'Upload-assisted workflow';
      }

      if (tool == 'Voice recorder') {
        return 'Voice/dictation workflow';
      }

      return 'Prompt workflow';
    }

    Color statusColorFor(String tool) {
      if (guidedOnlyTools.contains(tool)) {
        return skin.premium;
      }

      if (uploadAssistedTools.contains(tool)) {
        return skin.secondary;
      }

      return skin.success;
    }

    Widget statusPill(String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: skin.isLight ? 0.16 : 0.22),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.92), width: 1.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: skin.isLight ? const Color(0xFF07111F) : color,
            fontSize: 11.2,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: skin.panelDeep.withValues(alpha: skin.isLight ? 0.96 : 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _korlixDefinitionBorder(skin), width: 2.7),
        boxShadow: [
          BoxShadow(
            color: _korlixDefinitionShadow(skin),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: skin.glow.withValues(alpha: skin.isLight ? 0.10 : 0.18),
            blurRadius: 34,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: skin.primary, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Utility',
                  style: TextStyle(
                    color: _korlixReadableForeground(skin),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close utilities',
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _clearUtilitySelection();
                        });
                      },
                icon: Icon(Icons.close, color: _korlixReadableForeground(skin)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: skin.panel.withValues(alpha: skin.isLight ? 0.92 : 0.68),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _korlixDefinitionBorder(
                  skin,
                  secondary: true,
                ).withValues(alpha: skin.isLight ? 0.70 : 0.90),
                width: 1.8,
              ),
            ),
            child: Text(
              'Status note: Only active Utility tools are shown. Inactive tools are hidden until their full workflows are ready.',
              style: TextStyle(
                color: _korlixReadableForeground(skin, muted: true),
                fontSize: 12.4,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _utilityTools.map((tool) {
              final selected = selectedTool == tool;
              final status = statusFor(tool);
              final statusColor = statusColorFor(tool);

              return Tooltip(
                message: status,
                child: ActionChip(
                  label: Text(tool),
                  labelStyle: TextStyle(
                    color: selected
                        ? skin.textOnAccent
                        : _korlixReadableForeground(skin),
                    fontWeight: FontWeight.w900,
                  ),
                  backgroundColor: selected
                      ? skin.success
                      : skin.buttonFill.withValues(
                          alpha: skin.isLight ? 0.94 : 0.76,
                        ),
                  side: BorderSide(
                    color: selected
                        ? skin.success.withValues(alpha: 0.96)
                        : statusColor.withValues(alpha: 0.88),
                    width: selected ? 2.25 : 1.75,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onPressed: _loading ? null : () => _selectUtilityTool(tool),
                ),
              );
            }).toList(),
          ),
          if (selectedTool != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: skin.panel.withValues(alpha: skin.isLight ? 0.96 : 0.76),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: statusColorFor(selectedTool).withValues(alpha: 0.96),
                  width: 2.1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusPill(
                        statusFor(selectedTool),
                        statusColorFor(selectedTool),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _utilityToolDescription(selectedTool),
                    style: TextStyle(
                      color: _korlixReadableForeground(skin),
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleVoiceInput() async {
    await _loadCurrentTier();

    if (!_hasVoiceAccess) {
      await _showPremiumFeaturePrompt(
        title: 'Voice Input',
        availability: 'Pro, Ultra Premium, Enterprise',
        description:
            'Speak your request instead of typing. Voice input is available for Pro and higher tiers.',
      );
      return;
    }

    if (_voiceListening) {
      await _speechToText.stop();

      if (!mounted) {
        return;
      }

      setState(() {
        _voiceListening = false;
      });

      return;
    }

    try {
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() {
                _voiceListening = false;
              });
            }
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              _voiceListening = false;
            });
          }
        },
      );

      if (!available) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is not available on this device.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() {
        _voiceListening = true;
      });

      await _speechToText.listen(
        listenMode: speech_to_text.ListenMode.dictation,
        onResult: (result) {
          final words = result.recognizedWords.trim();

          if (words.isEmpty) {
            return;
          }

          setState(() {
            _controller.text = words;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });
        },
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _voiceListening = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice input could not start. Check microphone permission.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildPremiumHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;

        final logo = Container(
          width: compact ? 58 : 74,
          height: compact ? 58 : 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF061A25),
            border: Border.all(
              color: const Color(0xFF2EC7DF).withOpacity(0.42),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2EC7DF).withOpacity(0.20),
                blurRadius: 24,
              ),
            ],
          ),
          padding: EdgeInsets.all(compact ? 8 : 10),
          child: Image.asset(
            'assets/branding/korlix_mini_mark.png',
            fit: BoxFit.contain,
          ),
        );

        final titleBlock = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: compact ? Alignment.center : Alignment.centerLeft,
              child: Text(
                'KORLIX AI',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: const Color(0xFFE4EBEE),
                  fontSize: compact ? 42 : 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? 4.2 : 3.6,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'THE FUTURE IS HERE',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textAlign: compact ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                color: const Color(0xFF69D9E8),
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 3.2 : 3.8,
              ),
            ),
          ],
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: logo),
                const SizedBox(height: 16),
                Center(child: titleBlock),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Row(
            children: [
              logo,
              const SizedBox(width: 18),
              Expanded(child: titleBlock),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPremiumLanguageTabs() {
    Widget tab({required String code, required String label}) {
      final selected = _selectedLanguage == code;

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (_loading) {
              return;
            }

            setState(() {
              _selectedLanguage = code;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0A3A4A).withOpacity(0.72)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: const Color(0xFF2EC7DF).withOpacity(0.42))
                  : null,
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: const Color(0xFF2EC7DF).withOpacity(0.18),
                    blurRadius: 18,
                  ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFFE4EBEE)
                    : const Color(0xFFA9C6CF),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF071B27).withOpacity(0.62),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF2EC7DF).withOpacity(0.24)),
        ),
        child: Row(
          children: [
            tab(code: 'en', label: 'English'),
            Container(
              width: 1,
              height: 32,
              color: const Color(0xFF2EC7DF).withOpacity(0.18),
            ),
            tab(code: 'es', label: 'Español'),
            Container(
              width: 1,
              height: 32,
              color: const Color(0xFF2EC7DF).withOpacity(0.18),
            ),
            tab(code: 'fr', label: 'Français'),
          ],
        ),
      ),
    );
  }

  Widget _buildMockupHomeHeader() {
    return ValueListenableBuilder<String>(
      valueListenable: kKorlixThemeNotifier,
      builder: (context, theme, _) {
        final skin = korlixSkinPaletteFor(theme);
        final compact = MediaQuery.of(context).size.width < 560;

        final logo = Container(
          width: compact ? 58 : 74,
          height: compact ? 58 : 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: skin.panel.withOpacity(skin.isLight ? 0.84 : 0.94),
            border: Border.all(color: skin.primary.withOpacity(0.52)),
            boxShadow: [
              BoxShadow(
                color: skin.glow.withOpacity(skin.isLight ? 0.12 : 0.28),
                blurRadius: 26,
              ),
            ],
          ),
          padding: EdgeInsets.all(compact ? 8 : 10),
          child: Image.asset(
            'assets/branding/korlix_mini_mark.png',
            fit: BoxFit.contain,
          ),
        );

        final titleBlock = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'KORLIX AI',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: skin.text,
                  fontSize: compact ? 42 : 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? 4.2 : 3.6,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'THE FUTURE IS HERE',
              maxLines: 1,
              softWrap: false,
              textAlign: compact ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                color: skin.primary,
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 3.2 : 3.8,
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              logo,
              const SizedBox(width: 16),
              Expanded(child: titleBlock),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMockupLanguageTabs() {
    return ValueListenableBuilder<String>(
      valueListenable: kKorlixThemeNotifier,
      builder: (context, theme, _) {
        final skin = korlixSkinPaletteFor(theme);

        Widget tab({required String code, required String label}) {
          final selected = _selectedLanguage == code;

          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (_loading) {
                  return;
                }

                setState(() {
                  _selectedLanguage = code;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? skin.primary.withOpacity(skin.isLight ? 0.24 : 0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: selected
                      ? Border.all(
                          color: skin.primary.withOpacity(
                            skin.isLight ? 0.72 : 0.54,
                          ),
                        )
                      : null,
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: skin.glow.withOpacity(
                          skin.isLight ? 0.14 : 0.22,
                        ),
                        blurRadius: 18,
                      ),
                  ],
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? skin.text : skin.mutedText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: skin.panel.withOpacity(skin.isLight ? 0.56 : 0.66),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: skin.border.withOpacity(skin.isLight ? 0.36 : 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: skin.glow.withOpacity(skin.isLight ? 0.06 : 0.12),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Row(
              children: [
                tab(code: 'en', label: 'English'),
                Container(
                  width: 1,
                  height: 32,
                  color: skin.border.withOpacity(0.18),
                ),
                tab(code: 'es', label: 'Español'),
                Container(
                  width: 1,
                  height: 32,
                  color: skin.border.withOpacity(0.18),
                ),
                tab(code: 'fr', label: 'Français'),
              ],
            ),
          ),
        );
      },
    );
  }

  String _featuredResultShareText(GeneratedItem item) {
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : item.command.trim();

    return '$title\n\n${item.content.trim()}\n\nGenerated by Korlix AI';
  }

  Future<void> _copyFeaturedResult(GeneratedItem item) async {
    await Clipboard.setData(
      ClipboardData(text: _featuredResultShareText(item)),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Result copied.')));
  }

  Future<void> _shareFeaturedResult(GeneratedItem item) async {
    final box = context.findRenderObject() as RenderBox?;

    await Share.share(
      _featuredResultShareText(item),
      subject: item.title.trim().isNotEmpty
          ? item.title.trim()
          : 'Korlix AI result',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _refreshSelectedCharacterFromBackend({
    bool force = false,
  }) async {
    if (!force && _selectedCharacterFetchStarted) {
      return;
    }

    if (kKorlixAccessToken == null || kKorlixAccessToken!.isEmpty) {
      return;
    }

    _selectedCharacterFetchStarted = true;

    try {
      final response = await http.get(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/me'),
        headers: _authHeaders(),
      );

      if (response.statusCode >= 400) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final profile =
          (data['profile'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final selected = (profile['selected_character'] ?? 'jj')
          .toString()
          .trim();

      if (selected.isNotEmpty) {
        kKorlixSelectedCharacterNotifier.value = normalizeKorlixCharacterId(
          selected,
        );
      }
    } catch (_) {
      // The home screen should still load even if character sync fails.
    }
  }

  Future<void> _showVideoEnginePending(String scenePrompt) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF071B27),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFFFD166).withOpacity(0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD166).withOpacity(0.16),
                  blurRadius: 34,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.48),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFFE4EBEE),
                  ),
                ),
                const Icon(
                  Icons.movie_creation_outlined,
                  color: Color(0xFFFFD166),
                  size: 46,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Video generation is not connected yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The Create a video button is ready on the front end, but it is not connected to a real video generation provider yet. Until we connect the video API, Korlix AI will not return fake text results for video requests.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD166).withOpacity(0.26),
                    ),
                  ),
                  child: Text(
                    scenePrompt.trim().isEmpty
                        ? 'No scene description entered yet.'
                        : scenePrompt.trim(),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4EBEE),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF143B4A),
                      foregroundColor: const Color(0xFFE4EBEE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildFullKorlixVideoPrompt(String sceneDescription) {
    return '$kKorlixCreateVideoPrompt\n\nUser scene description:\n$sceneDescription';
  }

  Future<void> _startOpenAIVideoGeneration(String sceneDescription) async {
    await _stopAiCharacterTalkingForQuery();

    final scene = sceneDescription.trim();

    if (scene.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe the video you want first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final localJobId = _makePendingGenerationJobId('video-start');
    final topicId = _activeChatTopicId;

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _createVideoMode = false;
    });

    try {
      final data = await _runResumableJsonPost(
        localJobId: localJobId,
        kind: 'video_start',
        endpoint: '/api/video/generate',
        payload: {
          'prompt': _buildFullKorlixVideoPrompt(scene),
          'language': _selectedLanguage,
          'size': '1280x720',
          'seconds': 8,
        },
        prompt: scene,
        language: _selectedLanguage,
        topicId: topicId,
        directTimeout: const Duration(seconds: 60),
      );

      if (data == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
            _controller.clear();
            _createVideoMode = false;
          });

          _showBackgroundProcessingSnack(
            'Korlix is still starting your video. Reopen the app and progress will resume.',
          );
        }

        return;
      }

      if (data['upgradeRequired'] == true) {
        setState(() {
          _loading = false;
        });

        await _showPremiumFeaturePrompt(
          title: 'Ultra Premium required',
          availability: 'Ultra Premium, Enterprise',
          description:
              data['error']?.toString() ??
              'Video generation is available on Ultra Premium and Enterprise.',
        );
        return;
      }

      final videoId = (data['videoId'] ?? data['video']?['id']).toString();

      if (videoId.isEmpty || videoId == 'null') {
        throw Exception('No video ID returned.');
      }

      await _removePendingGenerationJob(localJobId);

      setState(() {
        _loading = false;
        _createVideoMode = false;
        _controller.clear();
      });

      await _showVideoProgressDialog(videoId: videoId, prompt: scene);
    } catch (error) {
      if (_appLifecyclePaused) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }

        return;
      }

      setState(() {
        _loading = false;
        _error = korlixFriendlyErrorMessage(error);
      });
    }
  }

  Future<void> _downloadGeneratedVideo(String videoId) async {
    final safeVideoId = videoId.trim();

    if (safeVideoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video is not ready to download yet.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final headers = Map<String, String>.from(_authHeaders())
      ..remove('Content-Type');
    final url = '$kKorlixBackendBaseUrl/api/video/content/$safeVideoId';
    final filename = 'korlix-video-$safeVideoId.mp4';

    try {
      await downloadKorlixVideo(url: url, headers: headers, filename: filename);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video download started.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(korlixFriendlyErrorMessage(error)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showVideoProgressDialog({
    required String videoId,
    required String prompt,
  }) async {
    Timer? timer;
    StateSetter? updateDialog;

    String status = 'queued';
    int progress = 0;
    String? errorMessage;
    bool completed = false;

    final videoStatusJobId = 'video-status-$videoId';

    await _upsertPendingGenerationJob({
      'localJobId': videoStatusJobId,
      'kind': 'video_status',
      'videoId': videoId,
      'prompt': prompt,
      'language': _selectedLanguage,
      'topicId': _activeChatTopicId,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'processing',
    });

    Future<void> poll() async {
      if (_appLifecyclePaused) {
        status = 'processing while phone is locked';
        updateDialog?.call(() {});
        return;
      }

      try {
        final response = await http.get(
          _assertValidKorlixBackendUri(
            '$kKorlixBackendBaseUrl/api/video/status/$videoId',
          ),
          headers: _authHeaders(),
        );

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(data['details'] ?? data['error'] ?? response.body);
        }

        final video =
            (data['video'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

        status = (data['status'] ?? video['status'] ?? 'queued').toString();
        progress =
            int.tryParse(
              (data['progress'] ?? video['progress'] ?? 0).toString(),
            ) ??
            0;

        if (status == 'completed') {
          completed = true;
          timer?.cancel();
          unawaited(_removePendingGenerationJob(videoStatusJobId));
        }

        if (status == 'failed') {
          errorMessage =
              video['error']?.toString() ?? 'Video generation failed.';
          timer?.cancel();
          unawaited(_removePendingGenerationJob(videoStatusJobId));
        }

        updateDialog?.call(() {});
      } catch (error) {
        final message = error.toString();

        if (message.contains('SocketException') ||
            message.contains('Failed host lookup') ||
            message.contains('Network is unreachable')) {
          status = 'waiting for connection';
          updateDialog?.call(() {});
          return;
        }

        errorMessage = message;
        updateDialog?.call(() {});
      }
    }

    timer = Timer.periodic(const Duration(seconds: 12), (_) => poll());

    await poll();

    if (!mounted) {
      timer.cancel();
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            updateDialog = setDialogState;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 22,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF071B27),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF69D9E8).withOpacity(0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF69D9E8).withOpacity(0.18),
                      blurRadius: 32,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.movie_creation_outlined,
                          color: Color(0xFF69D9E8),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Korlix Video Generation',
                            style: TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFE4EBEE),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!completed && errorMessage == null) ...[
                      const Text(
                        'Rendering your video. This can take a few minutes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFA9C6CF),
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: progress > 0 ? progress / 100 : null,
                        color: const Color(0xFF69D9E8),
                        backgroundColor: Colors.black26,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: $status ${progress > 0 ? "• $progress%" : ""}',
                        style: const TextStyle(
                          color: Color(0xFFE4EBEE),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (errorMessage != null) ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (completed) ...[
                      SizedBox(
                        height: 240,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: KorlixGeneratedVideoPlayer(
                                videoUrl:
                                    '$kKorlixBackendBaseUrl/api/video/content/$videoId',
                                headers: _authHeaders(),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: _buildReportGeneratedContentPill(
                                contentType: 'video',
                                prompt: prompt,
                                outputSummary: 'Generated video ID: $videoId',
                                contentId: videoId,
                                videoId: videoId,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        prompt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFA9C6CF),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _downloadGeneratedVideo(videoId),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download Video'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF143B4A),
                                foregroundColor: const Color(0xFFE4EBEE),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Share.share(
                                  'I created a video with Korlix AI. Video ID: $videoId',
                                  subject: 'Korlix AI video',
                                );
                              },
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF69D9E8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    timer.cancel();
  }

  Future<geo.Position?> _getKorlixLocation() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location services are disabled. Please turn on location.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return null;
    }

    var permission = await geo.Geolocator.checkPermission();

    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission denied.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return null;
    }

    if (permission == geo.LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is permanently denied. Enable it in app settings.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return null;
    }

    return geo.Geolocator.getCurrentPosition(
      desiredAccuracy: geo.LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  Future<void> _recordLocatorEvent({
    required geo.Position position,
    required String queryType,
  }) async {
    try {
      await http.post(
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/location/record',
        ),
        headers: _authHeaders(),
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'feature': 'locator',
          'query_type': queryType,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        }),
      );
    } catch (_) {
      // Location recording should not block the locator feature.
    }
  }

  String _cleanLocatorSearchText(String value) {
    var text = value.trim();

    text = text.replaceFirst(
      RegExp(
        r'^(find|show|locate|search|get)\s+(me\s+)?(a\s+|an\s+|the\s+)?',
        caseSensitive: false,
      ),
      '',
    );

    text = text.replaceAll(
      RegExp(r'\s+(near me|around me|nearby)$', caseSensitive: false),
      '',
    );

    return text.trim().isEmpty ? value.trim() : text.trim();
  }

  Uri _buildLocatorMapUri({
    required String searchText,
    double? latitude,
    double? longitude,
  }) {
    final cleanedSearchText = _cleanLocatorSearchText(searchText);
    final encodedQuery = Uri.encodeQueryComponent(cleanedSearchText);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final params = <String>['q=$encodedQuery'];

      if (latitude != null && longitude != null) {
        final coordinates =
            '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

        // Apple Maps search-near-location format.
        // Do not use ll here, because ll can turn q into a pin label.
        params.add('sll=$coordinates');
        params.add('z=14');
      }

      return Uri.parse('http://maps.apple.com/?${params.join('&')}');
    }

    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encodedQuery',
    );
  }

  Future<void> _openLocatorSearch({
    required String queryType,
    required String searchText,
  }) async {
    final position = await _getKorlixLocation();

    if (position == null) {
      return;
    }

    await _recordLocatorEvent(position: position, queryType: queryType);

    final mapsUri = _buildLocatorMapUri(
      searchText: searchText,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    final launched = await launchUrl(
      mapsUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open maps.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showLocatorOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF071B27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        Widget option({
          required IconData icon,
          required String title,
          required String queryType,
          required String searchText,
        }) {
          return ListTile(
            leading: Icon(icon, color: const Color(0xFF69D9E8)),
            title: Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE4EBEE),
                fontWeight: FontWeight.w800,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFA9C6CF),
            ),
            onTap: () {
              Navigator.of(context).pop();

              _openLocatorSearch(queryType: queryType, searchText: searchText);
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFA9C6CF).withOpacity(0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Locator',
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose what you want to find near your current location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                option(
                  icon: Icons.restaurant_rounded,
                  title: 'Find me a restaurant',
                  queryType: 'restaurant',
                  searchText: 'restaurant',
                ),
                option(
                  icon: Icons.local_gas_station_rounded,
                  title: 'Find me a gas station',
                  queryType: 'gas_station',
                  searchText: 'gas station',
                ),
                option(
                  icon: Icons.account_balance_outlined,
                  title: 'Find me an ATM',
                  queryType: 'atm',
                  searchText: 'ATM',
                ),
                option(
                  icon: Icons.church_rounded,
                  title: 'Find me a church',
                  queryType: 'church',
                  searchText: 'church',
                ),
                option(
                  icon: Icons.local_bar_rounded,
                  title: 'Find me a bar',
                  queryType: 'bar',
                  searchText: 'bar',
                ),
                option(
                  icon: Icons.local_police_rounded,
                  title: 'Find me a police station',
                  queryType: 'police_station',
                  searchText: 'police station',
                ),
                option(
                  icon: Icons.local_grocery_store_rounded,
                  title: 'Find me a grocery store',
                  queryType: 'grocery_or_supermarket',
                  searchText: 'grocery store',
                ),
                option(
                  icon: Icons.local_car_wash_rounded,
                  title: 'Find me a car wash',
                  queryType: 'car_wash',
                  searchText: 'car wash',
                ),
                option(
                  icon: Icons.tire_repair_rounded,
                  title: 'Find me a tire shop',
                  queryType: 'tire_shop',
                  searchText: 'tire shop',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDonateCashApp() async {
    final uri = Uri.parse('https://cash.app/\$cashapp');

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Cash App donation link.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildCreditDownloadCard(String pdfBase64, String docxBase64) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A90D9), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_rounded,
                color: Color(0xFF4A90D9),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Credit Dispute Letter Ready',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Download your print-ready dispute letter:',
            style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (pdfBase64.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: const Text(
                'Download PDF',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () =>
                  _saveCreditDocFile(pdfBase64, 'credit_dispute_letter.pdf'),
            ),
          if (pdfBase64.isNotEmpty) const SizedBox(height: 8),
          if (docxBase64.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.article_rounded, size: 20),
              label: const Text(
                'Download Word Doc',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () =>
                  _saveCreditDocFile(docxBase64, 'credit_dispute_letter.docx'),
            ),
        ],
      ),
    );
  }

  Future<void> _saveCreditDocFile(String base64Data, String fileName) async {
    try {
      final bytes = base64Decode(base64Data);
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: fileName,
          mimeType: fileName.endsWith('.pdf')
              ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
      ], text: 'Credit Dispute Letter');
    } catch (e) {
      debugPrint('[CreditDocs] Save error: ' + e.toString());
    }
  }

  Widget _buildMockupFeaturedCharacterCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSelectedCharacterFromBackend();
    });

    final GeneratedItem? activeResult = null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      child: ValueListenableBuilder<String>(
        valueListenable: kKorlixSelectedCharacterNotifier,
        builder: (context, selectedCharacterId, _) {
          final character = korlixCharacterDisplayFor(selectedCharacterId);
          final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final cardHeight = compact ? 315.0 : 300.0;

              return Container(
                height: cardHeight,
                decoration: BoxDecoration(
                  color: skin.panel.withOpacity(skin.isLight ? 0.88 : 0.72),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: skin.border.withOpacity(skin.isLight ? 0.52 : 0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: skin.glow.withOpacity(skin.isLight ? 0.08 : 0.12),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: compact ? 10 : 10,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 16 : 28,
                              compact ? 16 : 24,
                              compact ? 10 : 18,
                              compact ? 16 : 24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  character.eyebrow,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: skin.primary,
                                    fontSize: compact ? 11.5 : 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: compact ? 9 : 14),
                                Text(
                                  character.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: skin.text,
                                    fontSize: compact ? 34 : 44,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                SizedBox(height: compact ? 10 : 16),
                                Text(
                                  character.description,
                                  maxLines: compact ? 4 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: skin.mutedText.withOpacity(0.96),
                                    fontSize: compact ? 13.5 : 19,
                                    height: 1.28,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: compact ? 12 : 22),
                                SizedBox(
                                  height: compact ? 38 : 46,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Open Settings → View characters to preview and unlock more characters.',
                                          ),
                                        ),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: skin.primary,
                                      side: BorderSide(
                                        color: skin.border.withOpacity(0.62),
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: compact ? 14 : 24,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      compact ? 'View' : 'View Character',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: compact ? 12 : 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: compact ? 11 : 12,
                          child: Container(
                            height: double.infinity,
                            color: Colors.black.withOpacity(0.16),
                            child: KorlixCharacterIntroPreview(
                              key: ValueKey(character.assetPath),
                              assetPath: character.assetPath,
                              muted: !character.soundOn,
                              showSoundButton: character.soundOn,
                              autoplay: true,
                              loop: true,
                              fillParent: true,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_loading)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.76),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: skin.primary.withOpacity(0.48),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: skin.primary,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${character.name} is preparing your answer...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: skin.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 520),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation);

                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: activeResult == null
                          ? const SizedBox.shrink()
                          : _buildNeonAnswerReadyFrame(
                              child: Container(
                                key: ValueKey(
                                  '${activeResult.title}-${activeResult.command}-${activeResult.content.hashCode}',
                                ),
                                width: double.infinity,
                                height: _answerMinimized
                                    ? null
                                    : double.infinity,
                                padding: EdgeInsets.all(compact ? 13 : 16),
                                // CYBER PANEL FRONT: this is the visible ANSWER READY card face.
                                // CYBER PANEL FRONT: visible ANSWER READY card face.
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: skin.panelDeep,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      skin.panelSoft,
                                      skin.panel,
                                      skin.panelDeep,
                                    ],
                                    stops: [0.0, 0.52, 1.0],
                                  ),
                                  border: Border.all(
                                    color: skin.border.withValues(alpha: 0.62),
                                    width: 1.15,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: skin.glow.withValues(alpha: 0.16),
                                      blurRadius: 18,
                                      spreadRadius: 0.8,
                                      offset: const Offset(-2, -1),
                                    ),
                                    BoxShadow(
                                      color: skin.secondary.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 0.8,
                                      offset: const Offset(2, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: _answerMinimized
                                      ? MainAxisSize.min
                                      : MainAxisSize.max,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_rounded,
                                          color: skin.primary,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'ANSWER READY',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: skin.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),
                                        // Minimize/Maximize button
                                        IconButton(
                                          onPressed: () => setState(
                                            () => _answerMinimized =
                                                !_answerMinimized,
                                          ),
                                          tooltip: _answerMinimized
                                              ? 'Maximize'
                                              : 'Minimize',
                                          icon: Icon(
                                            _answerMinimized
                                                ? Icons.keyboard_arrow_down
                                                : Icons.keyboard_arrow_up,
                                            color: skin.primary,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _featuredAnswerDismissed = true;
                                            });
                                          },
                                          icon: Icon(Icons.close_rounded),
                                          color: skin.text,
                                          tooltip: 'Close',
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 34,
                                            minHeight: 34,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Body content — hidden when minimized
                                    if (!_answerMinimized) ...[
                                      SizedBox(height: 8),
                                      Expanded(
                                        child:
                                            _buildAnswerReadyConversationView(
                                              activeResult,
                                              compact: compact,
                                            ),
                                      ),
                                    ], // end if (!_answerMinimized)
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _answerChatMessageHasVisibleTurn(ChatMessage message) {
    return message.userText.trim().isNotEmpty ||
        message.aiText.trim().isNotEmpty ||
        message.generatedItem?.hasImageResult == true ||
        (message.imageDataUrl != null && message.imageDataUrl!.isNotEmpty) ||
        (message.imageUrl != null && message.imageUrl!.isNotEmpty);
  }

  ChatMessage _copyChatMessageForAnswerDeletion(
    ChatMessage message, {
    String? userText,
    String? aiText,
    bool clearAiPayload = false,
  }) {
    return ChatMessage(
      userText: userText ?? message.userText,
      aiText: aiText ?? message.aiText,
      isImage: clearAiPayload ? false : message.isImage,
      imageDataUrl: clearAiPayload ? null : message.imageDataUrl,
      imageUrl: clearAiPayload ? null : message.imageUrl,
      language: message.language,
      allowPdf: clearAiPayload ? false : message.allowPdf,
      generatedItem: clearAiPayload ? null : message.generatedItem,
      createdAt: message.createdAt,
      isCreditDispute: clearAiPayload ? false : message.isCreditDispute,
      equifaxDocxBase64: clearAiPayload ? null : message.equifaxDocxBase64,
      experianDocxBase64: clearAiPayload ? null : message.experianDocxBase64,
      transunionDocxBase64: clearAiPayload
          ? null
          : message.transunionDocxBase64,
      consumerName: message.consumerName,
    );
  }

  GeneratedItem _answerPanelGeneratedItemFromChatMessage(ChatMessage message) {
    if (message.generatedItem != null) {
      return _korlixVisibleGeneratedItem(message.generatedItem!);
    }

    return GeneratedItem(
      command: _korlixVisibleUserText(message.userText),
      title: _makeResultTitle(
        _korlixVisibleUserText(message.userText).isNotEmpty
            ? _korlixVisibleUserText(message.userText)
            : message.aiText,
      ),
      content: message.aiText,
      language: message.language,
      allowPdf: message.allowPdf,
      imageDataUrl: message.imageDataUrl,
      imageUrl: message.imageUrl,
    );
  }

  GeneratedItem? _latestVisibleAnswerItem() {
    for (final message in _chatMessages.reversed) {
      if (_answerChatMessageHasVisibleTurn(message)) {
        return _answerPanelGeneratedItemFromChatMessage(message);
      }
    }

    return null;
  }

  void _syncActiveTopicAfterAnswerTurnDeletion() {
    final topicId = _activeChatTopicId;

    if (topicId == null) {
      return;
    }

    final existing = _chatTopicsById[topicId];

    if (existing == null) {
      return;
    }

    final visibleMessages = _chatMessages
        .where(_answerChatMessageHasVisibleTurn)
        .toList();

    if (visibleMessages.isEmpty) {
      _chatTopicsById.remove(topicId);
      _activeChatTopicId = null;
    } else {
      _chatTopicsById[topicId] = existing.copyWith(
        updatedAt: DateTime.now(),
        messages: visibleMessages,
      );
    }

    unawaited(_persistLocalChatTopics());
  }

  void _deleteAnswerBoxTurn({
    required int messageIndex,
    required bool deleteUser,
  }) {
    if (messageIndex < 0 || messageIndex >= _chatMessages.length) {
      return;
    }

    final original = _chatMessages[messageIndex];

    final updated = _copyChatMessageForAnswerDeletion(
      original,
      userText: deleteUser ? '' : original.userText,
      aiText: deleteUser ? original.aiText : '',
      clearAiPayload: !deleteUser,
    );

    setState(() {
      _chatMessages[messageIndex] = updated;
      _chatMessages.removeWhere(
        (message) => !_answerChatMessageHasVisibleTurn(message),
      );

      _minimizedMessages.clear();
      _deletedMessages.clear();

      _results.clear();

      final latest = _latestVisibleAnswerItem();

      if (latest != null) {
        _results.add(latest);
        _featuredAnswerDismissed = false;
      } else {
        _featuredAnswerDismissed = true;
      }
    });

    _syncActiveTopicAfterAnswerTurnDeletion();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleteUser ? 'Your question was deleted.' : 'The answer was deleted.',
        ),
      ),
    );
  }

  void _deleteLooseActiveResultTurn({required bool deleteUser}) {
    if (_results.isEmpty) {
      return;
    }

    final item = _results.first;

    final command = deleteUser ? '' : item.command;
    final content = deleteUser ? item.content : '';

    if (command.trim().isEmpty && content.trim().isEmpty && !deleteUser) {
      setState(() {
        _results.clear();
        _featuredAnswerDismissed = true;
      });
      return;
    }

    final updated = GeneratedItem(
      command: command,
      title: item.title,
      content: content,
      language: item.language,
      allowPdf: deleteUser ? item.allowPdf : false,
      imageDataUrl: deleteUser ? item.imageDataUrl : null,
      imageUrl: deleteUser ? item.imageUrl : null,
    );

    setState(() {
      _results
        ..clear()
        ..add(updated);
      _featuredAnswerDismissed = false;
    });
  }

  Future<void> _confirmDeleteAnswerBoxTurn({
    required int messageIndex,
    required bool deleteUser,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFA9C6CF).withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Icon(
                  deleteUser
                      ? Icons.person_remove_alt_1_rounded
                      : Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  deleteUser ? 'Delete your question?' : 'Delete this answer?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  deleteUser
                      ? 'Only your question will be removed from this answer box.'
                      : 'Only the AI answer will be removed from this answer box.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE4EBEE),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      _deleteAnswerBoxTurn(messageIndex: messageIndex, deleteUser: deleteUser);
    }
  }

  Future<void> _confirmDeleteLooseAnswerResultTurn({
    required bool deleteUser,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  deleteUser ? 'Delete your question?' : 'Delete this answer?',
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      _deleteLooseActiveResultTurn(deleteUser: deleteUser);
    }
  }

  Widget _buildAnswerTurnLabel({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.35,
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerTurnBubble({
    required bool isUser,
    required IconData icon,
    required String label,
    required Color accent,
    required Widget child,
    required VoidCallback onDelete,
    required String deleteTooltip,
  }) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isUser ? 20 : 7),
      topRight: Radius.circular(isUser ? 7 : 20),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.96
            : double.infinity;

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              margin: EdgeInsets.only(
                left: isUser ? 26 : 0,
                right: isUser ? 0 : 26,
                bottom: 12,
              ),
              padding: const EdgeInsets.fromLTRB(13, 10, 9, 12),
              decoration: BoxDecoration(
                color: isUser
                    ? skin.primary.withValues(alpha: skin.isLight ? 0.12 : 0.18)
                    : skin.secondary.withValues(
                        alpha: skin.isLight ? 0.10 : 0.18,
                      ),
                borderRadius: radius,
                border: Border.all(
                  color: accent.withValues(alpha: 0.96),
                  width: 2.05,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildAnswerTurnLabel(
                        icon: icon,
                        label: label,
                        color: accent,
                      ),
                      Spacer(),
                      Tooltip(
                        message: deleteTooltip,
                        child: InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.48),
                                width: 1.35,
                              ),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _korlixReadableForeground(
    KorlixSkinPalette skin, {
    bool muted = false,
    bool hint = false,
  }) {
    if (skin.isLight) {
      if (hint) {
        return const Color(0xFF2F3F4E);
      }

      if (muted) {
        return const Color(0xFF243444);
      }

      return const Color(0xFF07111F);
    }

    if (hint) {
      return const Color(0xFFE3F8FF);
    }

    if (muted) {
      return const Color(0xFFD7F1F8);
    }

    return const Color(0xFFF7FCFF);
  }

  Color _korlixReadableToolForeground(KorlixSkinPalette skin) {
    return skin.isLight ? const Color(0xFF07111F) : const Color(0xFFF7FCFF);
  }

  Color _korlixDefinitionBorder(
    KorlixSkinPalette skin, {
    bool secondary = false,
  }) {
    if (skin.isLight) {
      return secondary ? const Color(0xFF334155) : const Color(0xFF07111F);
    }

    return (secondary ? skin.secondary : skin.primary).withValues(alpha: 0.96);
  }

  Color _korlixDefinitionShadow(KorlixSkinPalette skin) {
    return skin.isLight
        ? const Color(0xFF07111F).withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.52);
  }

  // KORLIX_3D_BEVEL_HELPERS_BEGIN
  Widget _korlixBeveledButtonSurface({
    required KorlixSkinPalette skin,
    required Widget child,
    required Color fill,
    required Color border,
    BorderRadius? borderRadius,
    bool active = false,
    bool disabled = false,
    double borderWidth = 1.55,
    double depth = 1.0,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(999);
    final disabledFillAlpha = skin.isLight ? 0.92 : 0.58;
    final safeFill = fill.withValues(alpha: disabled ? disabledFillAlpha : 1.0);
    final topFace =
        Color.lerp(safeFill, Colors.white, skin.isLight ? 0.42 : 0.18) ??
        safeFill;
    final midFace = safeFill;
    final lowerFace =
        Color.lerp(safeFill, Colors.black, skin.isLight ? 0.08 : 0.30) ??
        safeFill;

    final edgeColor = disabled
        ? (skin.isLight
              ? border.withValues(alpha: 0.72)
              : skin.mutedText.withValues(alpha: 0.46))
        : border.withValues(alpha: active ? 0.98 : 0.78);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topFace, midFace, lowerFace],
          stops: const [0.0, 0.48, 1.0],
        ),
        border: Border.all(color: edgeColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: skin.isLight ? 0.72 : 0.07),
            blurRadius: 1.6 * depth,
            spreadRadius: 0,
            offset: Offset(-0.9 * depth, -0.9 * depth),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: skin.isLight ? 0.18 : 0.44),
            blurRadius: 7.5 * depth,
            spreadRadius: 0.15,
            offset: Offset(0, 3.7 * depth),
          ),
          BoxShadow(
            color: border.withValues(alpha: active ? 0.24 : 0.11),
            blurRadius: 10.0 * depth,
            spreadRadius: active ? 0.35 : 0.05,
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: skin.isLight ? 0.38 : 0.18),
            Colors.transparent,
            Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.30),
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
  // KORLIX_3D_BEVEL_HELPERS_END

  Widget _buildAnswerText(String value, {required bool compact}) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return Text(
      value,
      style: TextStyle(
        color: _korlixReadableForeground(skin),
        fontSize: compact ? 13.5 : 14.5,
        height: 1.38,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildAnswerReadyConversationView(
    GeneratedItem item, {
    required bool compact,
  }) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final userAccent = skin.primary;
    final aiAccent = skin.secondary;

    final entries = <MapEntry<int, ChatMessage>>[];

    for (var index = 0; index < _chatMessages.length; index++) {
      final message = _chatMessages[index];

      if (_answerChatMessageHasVisibleTurn(message)) {
        entries.add(MapEntry(index, message));
      }
    }

    final recentEntries = entries.length > 4
        ? entries.sublist(entries.length - 4)
        : entries;

    // Keep the conversation timeline natural: older turns above, newest turn
    // below. The scroll view starts at the bottom so the newest dialog is
    // visible first and the user scrolls up for older messages.
    final latestAnswerTurnKey = recentEntries.isNotEmpty
        ? 'chat-${recentEntries.last.key}'
        : 'loose-${item.command.hashCode}-${item.content.hashCode}';

    Widget userBubble({required int? messageIndex, required String text}) {
      final visibleText = _korlixVisibleUserText(text);

      return _buildAnswerTurnBubble(
        isUser: true,
        icon: Icons.person_rounded,
        label: 'You',
        accent: userAccent,
        deleteTooltip: 'Delete your question',
        onDelete: messageIndex == null
            ? () => _confirmDeleteLooseAnswerResultTurn(deleteUser: true)
            : () => _confirmDeleteAnswerBoxTurn(
                messageIndex: messageIndex,
                deleteUser: true,
              ),
        child: _buildAnswerText(visibleText, compact: compact),
      );
    }

    Widget aiBubble({
      required int? messageIndex,
      required String text,
      GeneratedItem? generatedItem,
    }) {
      final hasImage = generatedItem?.hasImageResult == true;

      return _buildAnswerTurnBubble(
        isUser: false,
        icon: Icons.auto_awesome_rounded,
        label: 'Korlix AI',
        accent: aiAccent,
        deleteTooltip: 'Delete this answer',
        onDelete: messageIndex == null
            ? () => _confirmDeleteLooseAnswerResultTurn(deleteUser: false)
            : () => _confirmDeleteAnswerBoxTurn(
                messageIndex: messageIndex,
                deleteUser: false,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _buildGeneratedImagePreview(
                  generatedItem!,
                  height: compact ? 175 : 230,
                ),
              ),
              if (text.trim().isNotEmpty) SizedBox(height: 10),
            ],
            if (text.trim().isNotEmpty)
              _buildAnswerText(_cleanDisplayText(text), compact: compact),
          ],
        ),
      );
    }

    return Scrollbar(
      thumbVisibility: false,
      child: SingleChildScrollView(
        key: ValueKey('answer-ready-bottom-$latestAnswerTurnKey'),
        reverse: true,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recentEntries.isEmpty) ...[
              if (item.content.trim().isNotEmpty || item.hasImageResult)
                aiBubble(
                  messageIndex: null,
                  text: item.content,
                  generatedItem: item.hasImageResult ? item : null,
                ),
              if (_korlixVisibleUserText(item.command).isNotEmpty)
                userBubble(
                  messageIndex: null,
                  text: _korlixVisibleUserText(item.command),
                ),
            ] else ...[
              for (final entry in recentEntries) ...[
                if (entry.value.aiText.trim().isNotEmpty ||
                    entry.value.generatedItem?.hasImageResult == true)
                  aiBubble(
                    messageIndex: entry.key,
                    text: entry.value.aiText,
                    generatedItem: entry.value.generatedItem,
                  ),
                if (_korlixVisibleUserText(entry.value.userText).isNotEmpty)
                  userBubble(
                    messageIndex: entry.key,
                    text: _korlixVisibleUserText(entry.value.userText),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommandPanel() {
    final t = _t;
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final hasText = _controller.text.trim().isNotEmpty;

    final canSubmit = _fixCreditReportMode
        ? (hasText && _activeUploadFiles.isNotEmpty)
        : hasText;

    final hintText = _selectedLanguage == 'es'
        ? 'Escribe aquí...'
        : _selectedLanguage == 'fr'
        ? 'Écrivez ici...'
        : 'Type your message...';

    final GeneratedItem? activeResult =
        (!_loading && _results.isNotEmpty && !_featuredAnswerDismissed)
        ? _results.first
        : null;

    Widget toolButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool locked = false,
      bool active = false,
      bool success = false,
    }) {
      final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

      return _buildKorlixBelowInputBeveledButton(
        icon: icon,
        label: label,
        onPressed: onPressed,
        locked: locked,
        active: active,
        success: success,
        accentColor: locked ? skin.premium : skin.primary,
        showStopIconWhenActive: active,
      );
    }

    Widget answerReadyBody() {
      final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
      if (_loading && activeResult == null) {
        return Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: skin.primary,
            ),
          ),
        );
      }

      if (activeResult == null) {
        return const SizedBox.expand();
      }

      return _buildAnswerReadyConversationView(
        activeResult,
        compact: MediaQuery.sizeOf(context).width < 430,
      );
    }

    Widget answerReadyPanel() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: activeResult == null ? null : () => _showResult(activeResult),
        onLongPress: activeResult == null
            ? null
            : () => _copyFeaturedResult(activeResult),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(31),
            border: Border.all(
              color: _korlixDefinitionBorder(
                skin,
              ).withValues(alpha: skin.isLight ? 0.72 : 0.96),
              width: 2.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _korlixDefinitionShadow(skin),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: _KorlixCleanAnswerReadyBox(child: answerReadyBody()),
        ),
      );
    }

    Widget singleInputBoard() {
      final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
      final inputTextColor = _korlixReadableForeground(skin);
      final inputHintColor = _korlixReadableForeground(skin, hint: true);

      return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: skin.inputFill.withOpacity(skin.isLight ? 0.98 : 0.90),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _korlixDefinitionBorder(
                skin,
              ).withValues(alpha: skin.isLight ? 0.74 : 0.96),
              width: 2.4,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                korlixSkinPaletteFor(
                  kKorlixThemeNotifier.value,
                ).panelSoft.withOpacity(0.78),
                korlixSkinPaletteFor(
                  kKorlixThemeNotifier.value,
                ).panel.withOpacity(0.88),
                korlixSkinPaletteFor(
                  kKorlixThemeNotifier.value,
                ).panelDeep.withOpacity(0.70),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.32),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  cursorColor: skin.primary,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.28,
                    color: inputTextColor,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: inputHintColor.withOpacity(0.96),
                      fontSize: 15.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Send',
                child: InkWell(
                  onTap: (_loading || !canSubmit) ? null : _generate,
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: canSubmit
                          ? const Color(0xFF69D9E8).withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.06),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: canSubmit
                            ? [
                                Color.lerp(
                                  skin.primary,
                                  Colors.white,
                                  skin.isLight ? 0.36 : 0.20,
                                )!,
                                const Color(0xFF69D9E8).withValues(alpha: 0.23),
                                Color.lerp(
                                  skin.primary,
                                  Colors.black,
                                  skin.isLight ? 0.08 : 0.34,
                                )!,
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.14),
                                skin.panel.withValues(alpha: 0.42),
                                Colors.black.withValues(alpha: 0.22),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: canSubmit
                            ? skin.primary.withValues(alpha: 0.82)
                            : inputHintColor.withValues(alpha: 0.32),
                        width: 1.65,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(
                            alpha: skin.isLight ? 0.58 : 0.08,
                          ),
                          blurRadius: 1.4,
                          offset: const Offset(-1, -1),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: skin.isLight ? 0.20 : 0.46,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _loading
                        ? SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: inputTextColor,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 25,
                            color: canSubmit
                                ? const Color(0xFF69D9E8)
                                : inputHintColor.withOpacity(0.64),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          answerReadyPanel(),

          SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: skin.panel.withOpacity(skin.isLight ? 0.96 : 0.88),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: _korlixDefinitionBorder(
                  skin,
                  secondary: true,
                ).withValues(alpha: skin.isLight ? 0.74 : 0.94),
                width: 2.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                singleInputBoard(),

                SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    toolButton(
                      icon: Icons.attach_file_rounded,
                      label: 'Upload',
                      locked: !_hasDocumentUploadAccess,
                      success: _activeUploadFiles.isNotEmpty,
                      active: false,
                      onPressed: _loading ? null : _handleUploadPressed,
                    ),
                    toolButton(
                      icon: Icons.mic_rounded,
                      label: 'Voice',
                      locked: !_hasVoiceAccess,
                      active: _voiceListening,
                      onPressed: _loading ? null : _handleVoiceInput,
                    ),
                    _buildKorlixBelowInputBeveledButton(
                      icon: Icons.location_on_outlined,
                      label: 'Locator',
                      onPressed: _loading ? null : _showLocatorOptions,
                      accentColor: skin.primary,
                    ),
                    _buildEnterpriseCopyboxButton(),
                    _buildMusicStudioButton(),
                    ..._korlixMusicDistributionPrelaunchButtonSlots(),
                    _buildUtilityButton(),
                    if (_currentTier == 'basic' &&
                        !kKorlixHideTipDeveloperOnIos)
                      _buildKorlixBelowInputBeveledButton(
                        icon: Icons.favorite_rounded,
                        label: 'Tip the developer',
                        onPressed: _loading ? null : _openDonateCashApp,
                        accentColor: skin.premium,
                      ),
                  ],
                ),

                if (_utilityPanelOpen) ...[
                  SizedBox(height: 12),
                  _buildUtilityPanel(),
                ],

                if (_activeUploadFiles.isNotEmpty) ...[
                  SizedBox(height: 12),
                  _buildSelectedUploadFilesPanel(),
                ],

                if (_loading) ...[
                  SizedBox(height: 14),
                  MatrixThinkingPanel(message: t.matrixMessage),
                ],

                SizedBox(height: 14),

                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  alignment: WrapAlignment.center,
                  children: t.quickActions
                      .map(_buildSafeUiQuickActionChip)
                      .toList(),
                ),

                if (_error != null) ...[
                  SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _encodeGeneratedItem(GeneratedItem item) {
    return <String, dynamic>{
      'command': _korlixVisibleUserText(item.command),
      'title': _makeResultTitle(item.title),
      'content': item.content,
      'language': item.language,
      'allowPdf': item.allowPdf,
      'imageDataUrl': item.imageDataUrl,
      'imageUrl': item.imageUrl,
    };
  }

  GeneratedItem _decodeGeneratedItem(Map<String, dynamic> data) {
    return GeneratedItem(
      command: _korlixVisibleUserText((data['command'] ?? '').toString()),
      title: _makeResultTitle((data['title'] ?? 'Korlix AI').toString()),
      content: (data['content'] ?? '').toString(),
      language: (data['language'] ?? 'en').toString(),
      allowPdf: data['allowPdf'] == true,
      imageDataUrl: data['imageDataUrl']?.toString(),
      imageUrl: data['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> _encodeChatMessage(ChatMessage message) {
    return <String, dynamic>{
      'userText': _korlixVisibleUserText(message.userText),
      'aiText': message.aiText,
      'isImage': message.isImage,
      'imageDataUrl': message.imageDataUrl,
      'imageUrl': message.imageUrl,
      'language': message.language,
      'allowPdf': message.allowPdf,
      'createdAt': message.createdAt.toIso8601String(),
      'isCreditDispute': message.isCreditDispute,
      'equifaxDocxBase64': message.equifaxDocxBase64,
      'experianDocxBase64': message.experianDocxBase64,
      'transunionDocxBase64': message.transunionDocxBase64,
      'consumerName': message.consumerName,
      if (message.generatedItem != null)
        'generatedItem': _encodeGeneratedItem(message.generatedItem!),
    };
  }

  ChatMessage _decodeChatMessage(Map<String, dynamic> data) {
    final generatedRaw = data['generatedItem'];
    GeneratedItem? generatedItem;

    if (generatedRaw is Map) {
      generatedItem = _decodeGeneratedItem(
        generatedRaw.cast<String, dynamic>(),
      );
    }

    final isImage = data['isImage'] == true;
    final imageDataUrl = data['imageDataUrl']?.toString();
    final imageUrl = data['imageUrl']?.toString();

    if (generatedItem == null &&
        (isImage ||
            (imageDataUrl != null && imageDataUrl.isNotEmpty) ||
            (imageUrl != null && imageUrl.isNotEmpty))) {
      generatedItem = GeneratedItem(
        command: _korlixVisibleUserText((data['userText'] ?? '').toString()),
        title: 'Image',
        content: (data['aiText'] ?? '').toString(),
        language: (data['language'] ?? 'en').toString(),
        allowPdf: data['allowPdf'] == true,
        imageDataUrl: imageDataUrl,
        imageUrl: imageUrl,
      );
    }

    final createdAt =
        DateTime.tryParse((data['createdAt'] ?? '').toString()) ??
        DateTime.now();

    return ChatMessage(
      userText: _korlixVisibleUserText((data['userText'] ?? '').toString()),
      aiText: (data['aiText'] ?? '').toString(),
      isImage: isImage,
      imageDataUrl: imageDataUrl,
      imageUrl: imageUrl,
      language: (data['language'] ?? 'en').toString(),
      allowPdf: data['allowPdf'] == true,
      generatedItem: generatedItem,
      createdAt: createdAt,
      isCreditDispute: data['isCreditDispute'] == true,
      equifaxDocxBase64: data['equifaxDocxBase64']?.toString(),
      experianDocxBase64: data['experianDocxBase64']?.toString(),
      transunionDocxBase64: data['transunionDocxBase64']?.toString(),
      consumerName: data['consumerName']?.toString(),
    );
  }

  Map<String, dynamic> _encodeLocalChatTopic(KorlixLocalChatTopic topic) {
    return <String, dynamic>{
      'id': topic.id,
      'title': topic.title,
      'updatedAt': topic.updatedAt.toIso8601String(),
      'messages': topic.messages.map(_encodeChatMessage).toList(),
    };
  }

  KorlixLocalChatTopic? _decodeLocalChatTopic(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString().trim();

    if (id.isEmpty) {
      return null;
    }

    final rawMessages = data['messages'];
    final messages = <ChatMessage>[];

    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is Map) {
          try {
            messages.add(_decodeChatMessage(raw.cast<String, dynamic>()));
          } catch (_) {
            // Skip corrupt rows.
          }
        }
      }
    }

    return KorlixLocalChatTopic(
      id: id,
      title: (data['title'] ?? 'Untitled chat').toString(),
      updatedAt:
          DateTime.tryParse((data['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
      messages: messages,
    );
  }

  List<KorlixLocalChatTopic> get _sortedChatTopicThreads {
    final topics = _chatTopicsById.values
        .where((topic) => topic.messages.isNotEmpty)
        .toList();

    topics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return topics;
  }

  Future<void> _loadLocalChatTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawText = prefs.getString(_localChatTopicsPrefsKey);

      if (rawText == null || rawText.trim().isEmpty) {
        return;
      }

      final raw = jsonDecode(rawText);

      if (raw is! List) {
        return;
      }

      final loaded = <String, KorlixLocalChatTopic>{};

      for (final item in raw) {
        if (item is Map) {
          final topic = _decodeLocalChatTopic(item.cast<String, dynamic>());

          if (topic != null && topic.messages.isNotEmpty) {
            loaded[topic.id] = topic;
          }
        }
      }

      if (loaded.isEmpty || !mounted) {
        return;
      }

      final sorted = loaded.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      setState(() {
        _chatTopicsById
          ..clear()
          ..addAll(loaded);

        _activeChatTopicId = sorted.first.id;

        _chatMessages
          ..clear()
          ..addAll(sorted.first.messages);

        _results.clear();

        if (sorted.first.messages.isNotEmpty) {
          _results.add(
            _generatedItemFromChatMessage(sorted.first.messages.last),
          );
        }

        _featuredAnswerDismissed = false;
        _answerMinimized = false;
        _chatMinimized = true;
      });

      _scrollChatThreadToBottomSoon();
    } catch (_) {
      // Strict local topic loading should never block the command center.
    }
  }

  Future<void> _persistLocalChatTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _sortedChatTopicThreads.map(_encodeLocalChatTopic).toList(),
      );

      await prefs.setString(_localChatTopicsPrefsKey, encoded);
    } catch (_) {
      // Local persistence should never block generation.
    }
  }

  String _makeLocalChatTopicId() {
    return 'topic_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _deriveTopicTitle(String prompt) {
    var cleaned = prompt
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(
            r'^(please|can you|could you|help me)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (cleaned.isEmpty) {
      return 'New Chat';
    }

    if (cleaned.length > 42) {
      cleaned = '${cleaned.substring(0, 42).trim()}...';
    }

    return cleaned;
  }

  void _ensureActiveChatTopicForPrompt(String prompt) {
    final currentId = _activeChatTopicId;

    if (currentId != null && _chatTopicsById.containsKey(currentId)) {
      final topic = _chatTopicsById[currentId]!;

      if ((topic.title == 'New Chat' || topic.title.trim().isEmpty) &&
          topic.messages.isEmpty &&
          prompt.trim().isNotEmpty) {
        _chatTopicsById[currentId] = topic.copyWith(
          title: _deriveTopicTitle(prompt),
          updatedAt: DateTime.now(),
        );
      }

      return;
    }

    final id = _makeLocalChatTopicId();

    _activeChatTopicId = id;
    _chatTopicsById[id] = KorlixLocalChatTopic(
      id: id,
      title: _deriveTopicTitle(prompt),
      updatedAt: DateTime.now(),
      messages: const <ChatMessage>[],
    );
  }

  GeneratedItem _generatedItemFromChatMessage(ChatMessage message) {
    if (message.generatedItem != null) {
      return _korlixVisibleGeneratedItem(message.generatedItem!);
    }

    return GeneratedItem(
      command: _korlixVisibleUserText(message.userText),
      title: _makeResultTitle(_korlixVisibleUserText(message.userText)),
      content: message.aiText,
      language: message.language,
      allowPdf: message.allowPdf,
      imageDataUrl: message.imageDataUrl,
      imageUrl: message.imageUrl,
    );
  }

  void _addChatMessage(ChatMessage message) {
    message = _korlixVisibleChatMessage(message);
    _ensureActiveChatTopicForPrompt(message.userText);

    _chatMessages.add(message);

    final topicId = _activeChatTopicId;

    if (topicId == null) {
      return;
    }

    final existing = _chatTopicsById[topicId];

    if (existing == null) {
      return;
    }

    final messages = List<ChatMessage>.from(existing.messages)..add(message);
    var title = existing.title.trim();

    if (title.isEmpty || title == 'New Chat' || title == 'Untitled chat') {
      title = _deriveTopicTitle(message.userText);
    }

    _chatTopicsById[topicId] = existing.copyWith(
      title: title,
      updatedAt: DateTime.now(),
      messages: messages,
    );

    unawaited(_persistLocalChatTopics());
  }

  void _seedLegacyTopicFromLoadedHistory(List<ChatMessage> messages) {
    // Strict isolation: legacy flat backend history must not become active
    // memory for newly created topics.
  }

  String _buildThreadAwarePrompt(String command) {
    return _buildTopicIsolatedPrompt(command);
  }

  Map<String, String> _strictTopicRequestFields() {
    final topicId = _activeChatTopicId ?? '';

    return <String, String>{
      'topicId': topicId,
      'threadId': topicId,
      'conversationId': topicId,
      'memoryScope': 'selected_topic_only',
      'strictTopicOnly': 'true',
      'ignoreGlobalMemory': 'true',
      'disableAccountMemory': 'true',
      'disableUserProfileMemory': 'true',
      'disableHistoryLookup': 'true',
    };
  }

  String _buildTopicIsolatedPrompt(String command) {
    _ensureActiveChatTopicForPrompt(command);

    final topicId = _activeChatTopicId;
    final topic = topicId == null ? null : _chatTopicsById[topicId];

    final messages = topic?.messages ?? const <ChatMessage>[];

    final buffer = StringBuffer()
      ..writeln('STRICT CHAT TOPIC ISOLATION MODE.')
      ..writeln(
        'Only use the messages listed under SELECTED TOPIC MEMORY below.',
      )
      ..writeln(
        'Do not use profile memory, global history, other chat topics, or previous sessions.',
      )
      ..writeln(
        'If the user asks for a fact that is not present in SELECTED TOPIC MEMORY, say that it has not been provided in this chat.',
      )
      ..writeln(
        'Example: if the user asks "what is my name?" and no name appears in SELECTED TOPIC MEMORY, answer that the user has not told you their name in this chat.',
      )
      ..writeln()
      ..writeln('SELECTED TOPIC MEMORY:');

    if (messages.isEmpty) {
      buffer.writeln('[No previous messages in this selected topic.]');
    } else {
      final recentMessages = messages.length > 8
          ? messages.sublist(messages.length - 8)
          : List<ChatMessage>.from(messages);

      for (final message in recentMessages) {
        final userText = _korlixVisibleUserText(message.userText);
        final aiText = _cleanDisplayText(message.aiText).trim();

        if (userText.isNotEmpty) {
          buffer.writeln('User: $userText');
        }

        if (aiText.isNotEmpty) {
          buffer.writeln('Korlix AI: $aiText');
        }

        buffer.writeln();
      }
    }

    buffer
      ..writeln()
      ..writeln('CURRENT USER MESSAGE:')
      ..writeln(command.trim());

    return buffer.toString();
  }

  void _scrollChatThreadToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(
          _chatScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _closeSavedTopicsOverlay() {
    _savedTopicsOverlayEntry?.remove();
    _savedTopicsOverlayEntry = null;

    if (mounted && _showSavedTopicsPanel) {
      setState(() {
        _showSavedTopicsPanel = false;
      });
    }
  }

  void _openSavedTopicsOverlay() {
    FocusScope.of(context).unfocus();

    _savedTopicsOverlayEntry?.remove();
    _savedTopicsOverlayEntry = null;

    setState(() {
      _showSavedTopicsPanel = true;
    });

    final overlay = Overlay.of(context, rootOverlay: true);

    _savedTopicsOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.sizeOf(overlayContext);
        var drawerWidth = screenSize.width * 0.70;

        if (drawerWidth < 250) {
          drawerWidth = 250;
        }

        if (drawerWidth > 315) {
          drawerWidth = 315;
        }

        var drawerHeight = screenSize.height * 0.46;

        if (drawerHeight < 330) {
          drawerHeight = 330;
        }

        if (drawerHeight > 430) {
          drawerHeight = 430;
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeSavedTopicsOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _savedTopicsMenuLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 52),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: drawerWidth,
                  height: drawerHeight,
                  child: _buildSavedTopicsOverlay(),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_savedTopicsOverlayEntry!);
  }

  void _toggleSavedTopicsPanel() {
    if (_savedTopicsOverlayEntry != null) {
      _closeSavedTopicsOverlay();
      return;
    }

    _openSavedTopicsOverlay();
  }

  void _startNewTopicChat() {
    _closeSavedTopicsOverlay();

    final newId = _makeLocalChatTopicId();

    setState(() {
      _activeChatTopicId = newId;
      _chatTopicsById[newId] = KorlixLocalChatTopic(
        id: newId,
        title: 'New Chat',
        updatedAt: DateTime.now(),
        messages: const <ChatMessage>[],
      );

      _controller.clear();
      _results.clear();
      _chatMessages.clear();
      _featuredAnswerDismissed = false;
      _answerMinimized = false;
      _chatMinimized = true;
      _error = null;

      _createVideoMode = false;
      _improvePictureMode = false;
      _imaginePictureMode = false;
      _fixCreditReportMode = false;

      _creditDebtValidationRoundsVisible = false;

      _creditDebtValidationRound = null;
      _createAppMode = false;

      _utilityPanelOpen = false;
      _selectedUtilityTool = null;
      _pickedUploadFile = null;
      _pickedUploadFiles.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('New isolated chat started.')));
  }

  void _openSavedTopic(String topicId) {
    final topic = _chatTopicsById[topicId];

    if (topic == null) {
      return;
    }

    _closeSavedTopicsOverlay();

    setState(() {
      _activeChatTopicId = topic.id;

      _chatMessages
        ..clear()
        ..addAll(topic.messages);

      _results.clear();

      if (topic.messages.isNotEmpty) {
        _results.add(_generatedItemFromChatMessage(topic.messages.last));
      }

      _controller.clear();
      _featuredAnswerDismissed = false;
      _answerMinimized = false;
      _chatMinimized = true;
      _error = null;
    });

    _scrollChatThreadToBottomSoon();
  }

  Future<void> _showMoreSavedTopics() async {
    if (!_savedTopicsScrollController.hasClients) {
      return;
    }

    final max = _savedTopicsScrollController.position.maxScrollExtent;
    final next = (_savedTopicsScrollController.offset + 132.0)
        .clamp(0.0, max)
        .toDouble();

    await _savedTopicsScrollController.animateTo(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _refreshSavedTopicsOverlay() {
    _savedTopicsOverlayEntry?.markNeedsBuild();
  }

  String _cleanSavedTopicRename(String value, String fallback) {
    var cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) {
      cleaned = fallback.trim().isEmpty ? 'Untitled chat' : fallback.trim();
    }

    if (cleaned.length > 48) {
      cleaned = '${cleaned.substring(0, 48).trim()}...';
    }

    return cleaned;
  }

  void _beginRenameSavedTopic(KorlixLocalChatTopic topic) {
    _renameTopicController.text = topic.title;
    _renameTopicController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _renameTopicController.text.length,
    );

    setState(() {
      _renamingTopicId = topic.id;
    });

    _refreshSavedTopicsOverlay();
  }

  void _cancelRenameSavedTopic() {
    setState(() {
      _renamingTopicId = null;
      _renameTopicController.clear();
    });

    _refreshSavedTopicsOverlay();
  }

  Future<void> _submitRenameSavedTopic(String topicId) async {
    final topic = _chatTopicsById[topicId];

    if (topic == null) {
      _cancelRenameSavedTopic();
      return;
    }

    final renamed = _cleanSavedTopicRename(
      _renameTopicController.text,
      topic.title,
    );

    setState(() {
      _chatTopicsById[topicId] = topic.copyWith(
        title: renamed,
        updatedAt: DateTime.now(),
      );
      _renamingTopicId = null;
      _renameTopicController.clear();
    });

    await _persistLocalChatTopics();

    if (!mounted) {
      return;
    }

    _refreshSavedTopicsOverlay();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Renamed to "$renamed".')));
  }

  Future<void> _confirmDeleteSavedTopic(String topicId) async {
    final topic = _chatTopicsById[topicId];

    if (topic == null) {
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  size: 38,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Delete chat topic?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Delete "${topic.title}" and all messages inside this thread?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await _deleteSavedTopic(topicId);
    }
  }

  Future<void> _deleteSavedTopic(String topicId) async {
    final deletingActive = topicId == _activeChatTopicId;
    final topic = _chatTopicsById[topicId];

    if (topic == null) {
      return;
    }

    setState(() {
      _chatTopicsById.remove(topicId);
      _renamingTopicId = null;
      _renameTopicController.clear();

      if (deletingActive) {
        final remaining = _sortedChatTopicThreads;

        if (remaining.isEmpty) {
          _activeChatTopicId = null;
          _chatMessages.clear();
          _results.clear();
          _featuredAnswerDismissed = true;
          _answerMinimized = false;
          _chatMinimized = true;
        } else {
          final next = remaining.first;
          _activeChatTopicId = next.id;

          _chatMessages
            ..clear()
            ..addAll(next.messages);

          _results.clear();

          if (next.messages.isNotEmpty) {
            _results.add(_generatedItemFromChatMessage(next.messages.last));
            _featuredAnswerDismissed = false;
          } else {
            _featuredAnswerDismissed = true;
          }

          _answerMinimized = false;
          _chatMinimized = true;
        }
      }
    });

    await _persistLocalChatTopics();

    if (!mounted) {
      return;
    }

    _refreshSavedTopicsOverlay();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted "${topic.title}".')));
  }

  Widget _buildSavedTopicsMenuButton() {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return CompositedTransformTarget(
      link: _savedTopicsMenuLayerLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleSavedTopicsPanel,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _showSavedTopicsPanel
                  ? skin.panelSoft.withOpacity(skin.isLight ? 0.88 : 0.96)
                  : skin.panel.withOpacity(skin.isLight ? 0.88 : 0.80),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _showSavedTopicsPanel ? skin.secondary : skin.primary,
                width: 1.25,
              ),
            ),
            child: Icon(Icons.menu_rounded, color: skin.text, size: 27),
          ),
        ),
      ),
    );
  }

  int _chatTopicMessageCount(KorlixLocalChatTopic topic) {
    var count = 0;

    for (final message in topic.messages) {
      if (message.userText.trim().isNotEmpty) {
        count += 1;
      }

      if (message.aiText.trim().isNotEmpty ||
          message.generatedItem?.hasImageResult == true ||
          (message.imageDataUrl != null && message.imageDataUrl!.isNotEmpty) ||
          (message.imageUrl != null && message.imageUrl!.isNotEmpty)) {
        count += 1;
      }
    }

    return count;
  }

  String _formatChatTopicExportDate(DateTime value) {
    final local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _chatTopicExportFileName(
    KorlixLocalChatTopic topic,
    String extension,
  ) {
    final raw = topic.title.trim().isEmpty ? 'korlix-chat' : topic.title.trim();

    var safe = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (safe.isEmpty) {
      safe = 'korlix_chat';
    }

    if (safe.length > 42) {
      safe = safe.substring(0, 42).replaceAll(RegExp(r'_+$'), '');
    }

    return '${safe}_chat_log.$extension';
  }

  String _chatTopicExportText(KorlixLocalChatTopic topic) {
    final buffer = StringBuffer();

    buffer
      ..writeln('KORLIX AI CHAT EXPORT')
      ..writeln(
        'Topic: ${topic.title.trim().isEmpty ? 'Untitled chat' : topic.title.trim()}',
      )
      ..writeln('Messages: ${_chatTopicMessageCount(topic)}')
      ..writeln('Last updated: ${_formatChatTopicExportDate(topic.updatedAt)}')
      ..writeln('Exported: ${_formatChatTopicExportDate(DateTime.now())}')
      ..writeln()
      ..writeln('----------------------------------------')
      ..writeln();

    if (topic.messages.isEmpty) {
      buffer.writeln('No messages were saved in this chat topic.');
    } else {
      for (var index = 0; index < topic.messages.length; index++) {
        final message = topic.messages[index];
        final userText = _korlixVisibleUserText(message.userText);
        final aiText = _cleanDisplayText(message.aiText).trim();
        final hasImage =
            message.generatedItem?.hasImageResult == true ||
            (message.imageDataUrl != null &&
                message.imageDataUrl!.isNotEmpty) ||
            (message.imageUrl != null && message.imageUrl!.isNotEmpty);

        if (userText.isNotEmpty) {
          buffer
            ..writeln('YOU')
            ..writeln(_formatChatTopicExportDate(message.createdAt))
            ..writeln(userText)
            ..writeln();
        }

        if (aiText.isNotEmpty || hasImage) {
          buffer
            ..writeln('KORLIX AI')
            ..writeln(_formatChatTopicExportDate(message.createdAt));

          if (aiText.isNotEmpty) {
            buffer.writeln(aiText);
          }

          if (hasImage) {
            buffer.writeln('[Generated image included in app preview]');
          }

          if (message.isCreditDispute) {
            buffer.writeln('[Credit dispute letter package generated]');
          }

          buffer.writeln();
        }

        if (index < topic.messages.length - 1) {
          buffer
            ..writeln('----------------------------------------')
            ..writeln();
        }
      }
    }

    buffer
      ..writeln()
      ..writeln('Generated by Korlix AI');

    return buffer.toString();
  }

  Future<void> _copySavedTopicExport(KorlixLocalChatTopic topic) async {
    await Clipboard.setData(ClipboardData(text: _chatTopicExportText(topic)));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied "${topic.title}" chat log.')),
    );
  }

  Future<void> _exportSavedTopicAsTxt(KorlixLocalChatTopic topic) async {
    final exportText = _chatTopicExportText(topic);
    final bytes = Uint8List.fromList(utf8.encode(exportText));
    final filename = _chatTopicExportFileName(topic, 'txt');

    try {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: filename, mimeType: 'text/plain')],
        text: 'Korlix AI chat export: ${topic.title}',
        subject: 'Korlix AI chat export',
      );
    } catch (_) {
      await Share.share(
        exportText,
        subject: 'Korlix AI chat export: ${topic.title}',
      );
    }
  }

  Future<void> _exportSavedTopicAsPdf(KorlixLocalChatTopic topic) async {
    final exportText = _chatTopicExportText(topic);

    final item = GeneratedItem(
      command: 'Export chat topic: ${topic.title}',
      title: 'Chat Log: ${topic.title}',
      content: exportText,
      language: _selectedLanguage,
      allowPdf: true,
    );

    await _exportPdf(item);
  }

  Future<void> _showExportSavedTopicSheet(KorlixLocalChatTopic topic) async {
    _closeSavedTopicsOverlay();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget exportOption({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF0B2438).withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF69D9E8).withValues(alpha: 0.34),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF69D9E8), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFFF3FBFF),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: const Color(
                              0xFFF3FBFF,
                            ).withValues(alpha: 0.64),
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFA9C6CF),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFA9C6CF).withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Icon(
                  Icons.ios_share_rounded,
                  color: Color(0xFF69D9E8),
                  size: 38,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Export Chat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Export "${topic.title}" with all ${_chatTopicMessageCount(topic)} saved messages.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                exportOption(
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'Export as PDF',
                  subtitle: 'Best for printing, saving, or sharing.',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _exportSavedTopicAsPdf(topic);
                  },
                ),
                const SizedBox(height: 10),
                exportOption(
                  icon: Icons.description_outlined,
                  title: 'Export as TXT',
                  subtitle: 'Plain text file with the complete chat log.',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _exportSavedTopicAsTxt(topic);
                  },
                ),
                const SizedBox(height: 10),
                exportOption(
                  icon: Icons.copy_rounded,
                  title: 'Copy chat log',
                  subtitle: 'Copy the full topic transcript to clipboard.',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _copySavedTopicExport(topic);
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF69D9E8),
                      side: BorderSide(
                        color: const Color(0xFF69D9E8).withValues(alpha: 0.42),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSavedTopicsOverlay() {
    final topics = _sortedChatTopicThreads;
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    Widget topicIconButton({
      required String tooltip,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      );
    }

    Widget topicRow(KorlixLocalChatTopic topic) {
      final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
      final selected = topic.id == _activeChatTopicId;
      final renaming = topic.id == _renamingTopicId;

      if (renaming) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: skin.panelSoft.withValues(alpha: skin.isLight ? 0.88 : 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: skin.secondary.withValues(alpha: 0.88),
              width: 1.15,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _renameTopicController,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 1,
                  cursorColor: skin.primary,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitRenameSavedTopic(topic.id),
                  style: TextStyle(
                    color: skin.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Rename chat',
                    hintStyle: TextStyle(
                      color: skin.hintText.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _submitRenameSavedTopic(topic.id),
                icon: Icon(Icons.check_rounded, color: skin.primary),
              ),
              IconButton(
                onPressed: _cancelRenameSavedTopic,
                icon: Icon(Icons.close_rounded, color: skin.mutedText),
              ),
            ],
          ),
        );
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? skin.panelSoft.withValues(alpha: skin.isLight ? 0.88 : 0.78)
              : skin.panel.withValues(alpha: skin.isLight ? 0.86 : 0.58),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? skin.secondary.withValues(alpha: 0.82)
                : skin.border.withValues(alpha: 0.42),
            width: 1.05,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openSavedTopic(topic.id),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '${_chatTopicMessageCount(topic)} messages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(
                            0xFFF3FBFF,
                          ).withValues(alpha: 0.54),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            topicIconButton(
              tooltip: 'Rename chat',
              icon: Icons.edit_outlined,
              color: skin.primary,
              onTap: () => _beginRenameSavedTopic(topic),
            ),
            topicIconButton(
              tooltip: 'Export chat',
              icon: Icons.ios_share_rounded,
              color: skin.primary,
              onTap: () => _showExportSavedTopicSheet(topic),
            ),
            topicIconButton(
              tooltip: 'Delete chat',
              icon: Icons.delete_outline_rounded,
              color: Colors.redAccent,
              onTap: () => _confirmDeleteSavedTopic(topic.id),
            ),
            SizedBox(width: 6),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: skin.panelDeep.withValues(alpha: skin.isLight ? 0.94 : 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: skin.border.withValues(alpha: 0.76),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.glow.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: skin.secondary.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(8, 10),
          ),
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _startNewTopicChat,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: skin.panelSoft.withValues(
                  alpha: skin.isLight ? 0.86 : 0.78,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: skin.border.withValues(alpha: 0.62),
                  width: 1.0,
                ),
              ),
              child: Text(
                'New Chat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: skin.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: topics.isEmpty
                ? Center(
                    child: Text(
                      'No saved chats yet.\nTap New Chat, send a message, and it will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: skin.text.withValues(alpha: 0.72),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _savedTopicsScrollController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: topics.length,
                    separatorBuilder: (_, __) => SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      return topicRow(topics[index]);
                    },
                  ),
          ),
          SizedBox(height: 10),
          Center(
            child: InkWell(
              onTap: _showMoreSavedTopics,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 48,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: skin.text.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: skin.border.withOpacity(0.42),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: skin.text,
                  size: 25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyThemeShortcut({required String theme}) async {
    final normalizedTheme = korlixNormalizeSkinId(theme);

    kKorlixThemeNotifier.value = normalizedTheme;

    if (mounted) {
      setState(() {});
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('korlix_ui_theme', normalizedTheme);
    } catch (_) {
      // Local theme switching should still work even if persistence fails.
    }

    try {
      await http
          .post(
            _assertValidKorlixBackendUri(
              '$kKorlixBackendBaseUrl/api/theme/set',
            ),
            headers: KorlixDeviceStore.headers(),
            body: jsonEncode({'theme': normalizedTheme}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Backend theme sync should not block the visible shortcut switch.
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(korlixThemeAppliedSnackBar(normalizedTheme));
  }

  Widget _buildThemeShortcutCircles() {
    const skinIds = <String>[
      'korlix_blue',
      'matrix_green',
      'ultra_gold',
      'pink_white',
      'dark_crimson',
      'white_gray',
    ];

    return ValueListenableBuilder<String>(
      valueListenable: kKorlixThemeNotifier,
      builder: (context, theme, _) {
        final activeId = korlixNormalizeSkinId(theme);

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 2),
          child: Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: korlixSkinPaletteFor(activeId).panel.withValues(
                  alpha: korlixSkinPaletteFor(activeId).isLight ? 0.64 : 0.38,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: korlixSkinPaletteFor(activeId).border.withValues(
                    alpha: korlixSkinPaletteFor(activeId).isLight ? 0.32 : 0.24,
                  ),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: skinIds.map((skinId) {
                  final skin = korlixSkinPaletteFor(skinId);
                  final selected = skin.id == activeId;

                  return Tooltip(
                    message: skin.label,
                    child: Semantics(
                      button: true,
                      label: 'Apply ${skin.label} theme',
                      selected: selected,
                      child: InkWell(
                        onTap: () => _applyThemeShortcut(theme: skin.id),
                        customBorder: const CircleBorder(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: selected ? 38 : 32,
                          height: selected ? 38 : 32,
                          padding: EdgeInsets.all(selected ? 3.0 : 2.3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? skin.text
                                  : skin.border.withValues(alpha: 0.62),
                              width: selected ? 2.0 : 1.05,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: skin.glow.withValues(
                                  alpha: selected ? 0.36 : 0.16,
                                ),
                                blurRadius: selected ? 14 : 8,
                                spreadRadius: selected ? 1 : 0,
                              ),
                            ],
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  skin.primary,
                                  skin.secondary,
                                  skin.panelDeep,
                                ],
                                stops: const [0.0, 0.62, 1.0],
                              ),
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: skin.textOnAccent,
                                    size: 16,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _googlePlayAiReportReasons() {
    return const <String>[
      'Offensive or abusive',
      'Unsafe or harmful',
      'False or misleading',
      'Hate or harassment',
      'Sexual content',
      'Other',
    ];
  }

  GeneratedItem? _latestReportableAiOutput() {
    if (_results.isEmpty) {
      return null;
    }

    for (final item in _results) {
      final hasContent =
          item.content.trim().isNotEmpty ||
          item.hasImageResult ||
          (item.imageDataUrl != null && item.imageDataUrl!.isNotEmpty) ||
          (item.imageUrl != null && item.imageUrl!.isNotEmpty);

      if (hasContent) {
        return item;
      }
    }

    return null;
  }

  String _reportableOutputSummary(GeneratedItem item) {
    final cleaned = _cleanDisplayText(item.content).trim();

    if (cleaned.isNotEmpty) {
      return cleaned;
    }

    if (item.hasImageResult) {
      return 'Generated image output';
    }

    return 'Generated AI output';
  }

  Future<bool> _submitGooglePlayAiReport({
    required String contentType,
    required String prompt,
    required String outputSummary,
    required String reason,
    required String details,
    String? contentId,
  }) async {
    final payload = <String, dynamic>{
      'contentType': contentType,
      'reason': reason,
      'details': details,
      'prompt': prompt,
      'outputSummary': outputSummary,
      'contentId': contentId,
      'language': _selectedLanguage,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appArea': 'google_play_ai_generated_content_report',
      'createdAt': DateTime.now().toIso8601String(),
    };

    final endpoints = <String>[
      '$kKorlixBackendBaseUrl/api/report-output',
      '$kKorlixBackendBaseUrl/api/reports/content',
      '$kKorlixBackendBaseUrl/api/report',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: _authHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 18));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
      } catch (_) {
        // Try next endpoint.
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final pending =
          prefs.getStringList('korlix_pending_ai_output_reports') ?? <String>[];
      pending.add(jsonEncode(payload));
      await prefs.setStringList('korlix_pending_ai_output_reports', pending);
    } catch (_) {
      // Local fallback should never crash the app.
    }

    return false;
  }

  Future<void> _showGooglePlayAiReportSheet({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
  }) async {
    final detailsController = TextEditingController();
    var selectedReason = _googlePlayAiReportReasons().first;

    try {
      final result = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF07111F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 22 + bottomInset),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFA9C6CF,
                            ).withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Icon(
                          Icons.flag_rounded,
                          color: Colors.redAccent,
                          size: 36,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Report AI Output',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Report offensive, unsafe, misleading, or policy-violating AI-generated content without leaving the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFA9C6CF),
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _googlePlayAiReportReasons().map((reason) {
                            final selected = selectedReason == reason;

                            return ChoiceChip(
                              selected: selected,
                              label: Text(reason),
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedReason = reason;
                                });
                              },
                              selectedColor: Colors.redAccent.withValues(
                                alpha: 0.22,
                              ),
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.20,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? Colors.redAccent
                                    : const Color(
                                        0xFF69D9E8,
                                      ).withValues(alpha: 0.30),
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(
                                        0xFFE4EBEE,
                                      ).withValues(alpha: 0.86),
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: detailsController,
                          minLines: 3,
                          maxLines: 5,
                          style: const TextStyle(color: Color(0xFFE4EBEE)),
                          cursorColor: const Color(0xFF69D9E8),
                          decoration: InputDecoration(
                            hintText:
                                'Optional details for the Korlix AI safety team...',
                            hintStyle: TextStyle(
                              color: const Color(
                                0xFFA9C6CF,
                              ).withValues(alpha: 0.72),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.24),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: const Color(
                                  0xFF69D9E8,
                                ).withValues(alpha: 0.26),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF69D9E8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFF69D9E8,
                              ).withValues(alpha: 0.20),
                            ),
                          ),
                          child: Text(
                            outputSummary.trim().isEmpty
                                ? 'No generated output text available.'
                                : outputSummary.trim(),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA9C6CF),
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFE4EBEE),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(
                                    sheetContext,
                                  ).pop(<String, String>{
                                    'reason': selectedReason,
                                    'details': detailsController.text.trim(),
                                  });
                                },
                                icon: const Icon(Icons.flag_rounded),
                                label: const Text('Submit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (result == null || !mounted) {
        return;
      }

      final sent = await _submitGooglePlayAiReport(
        contentType: contentType,
        prompt: prompt,
        outputSummary: outputSummary,
        reason: result['reason'] ?? 'Other',
        details: result['details'] ?? '',
        contentId: contentId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Report submitted. Thank you for helping improve Korlix AI safety.'
                : 'Report saved in the app. It will be available for Korlix AI review.',
          ),
        ),
      );
    } finally {
      detailsController.dispose();
    }
  }

  Widget _buildReportAiOutputButton({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
    bool compact = false,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => _showGooglePlayAiReportSheet(
          contentType: contentType,
          prompt: prompt,
          outputSummary: outputSummary,
          contentId: contentId,
        ),
        icon: const Icon(Icons.flag_outlined, size: 17),
        label: const Text('Report AI Output'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.redAccent,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 9,
          ),
          textStyle: TextStyle(
            fontSize: compact ? 11.5 : 12.5,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.52)),
          ),
          backgroundColor: Colors.black.withValues(alpha: 0.20),
        ),
      ),
    );
  }

  Widget _buildReportCurrentAiOutputButton() {
    final item = _latestReportableAiOutput();

    if (item == null) {
      return const SizedBox.shrink();
    }

    final isImage =
        item.hasImageResult ||
        (item.imageDataUrl != null && item.imageDataUrl!.isNotEmpty) ||
        (item.imageUrl != null && item.imageUrl!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: _buildReportAiOutputButton(
        contentType: isImage ? 'image' : 'text answer',
        prompt: _korlixVisibleUserText(item.command),
        outputSummary: _reportableOutputSummary(item),
        contentId: item.title.trim().isEmpty
            ? _korlixVisibleUserText(item.command)
            : _makeResultTitle(item.title),
      ),
    );
  }

  Widget _buildPersistentSavedTopicsMenuRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildSavedTopicsMenuButton(),
      ),
    );
  }

  Widget _buildResultsWithTopicOverlay() {
    return const SizedBox.shrink();
  }

  Widget _buildResults() {
    return const SizedBox.shrink();
  }

  Widget _buildChatThread() {
    if (_chatMessages.isEmpty && !_loading) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Row(
          children: [
            const Expanded(
              child: Text(
                'Chat',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            // Minimize/Maximize button
            IconButton(
              onPressed: () => setState(() => _chatMinimized = !_chatMinimized),
              tooltip: _chatMinimized ? 'Maximize chat' : 'Minimize chat',
              icon: Icon(
                _chatMinimized
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                color: const Color(0xFF2EC7DF),
                size: 22,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await _clearAllResults();
                setState(() {
                  _chatMessages.clear();
                });
              },
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        // Chat bubble list (hidden when minimized)
        if (!_chatMinimized) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 600),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shrinkWrap: true,
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                final msg = _chatMessages[index];
                final bubblePair = _buildChatBubblePair(msg, index);
                return _buildNeonChatBubbleFrame(
                  index: index,
                  child: bubblePair,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNeonAnswerReadyFrame({required Widget child}) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(2.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            skin.primary.withOpacity(skin.isLight ? 0.82 : 0.96),
            skin.tertiary.withOpacity(skin.isLight ? 0.28 : 0.46),
            skin.secondary.withOpacity(skin.isLight ? 0.70 : 0.96),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: skin.glow.withOpacity(skin.isLight ? 0.14 : 0.26),
            blurRadius: skin.isLight ? 18 : 24,
            spreadRadius: skin.isLight ? 0.2 : 1.0,
            offset: const Offset(-2, -1),
          ),
          BoxShadow(
            color: skin.secondary.withOpacity(skin.isLight ? 0.10 : 0.22),
            blurRadius: skin.isLight ? 18 : 26,
            spreadRadius: skin.isLight ? 0.2 : 0.8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [skin.panelSoft, skin.panel, skin.panelDeep],
            stops: [0.0, 0.54, 1.0],
          ),
          border: Border.all(
            color: skin.isLight
                ? skin.border.withOpacity(0.56)
                : Colors.white.withOpacity(0.08),
            width: 0.95,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: RadialGradient(
                      center: const Alignment(0.6, -0.9),
                      radius: 1.25,
                      colors: [
                        Colors.white.withOpacity(skin.isLight ? 0.30 : 0.10),
                        skin.primary.withOpacity(skin.isLight ? 0.05 : 0.05),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.24, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeonChatBubbleFrame({
    required int index,
    required Widget child,
  }) {
    if (child is SizedBox && child.width == 0 && child.height == 0) {
      return child;
    }

    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final primary = index.isEven ? skin.primary : skin.secondary;
    final secondary = index.isEven ? skin.secondary : skin.primary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(1.9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withOpacity(skin.isLight ? 0.74 : 0.94),
            skin.tertiary.withOpacity(skin.isLight ? 0.16 : 0.22),
            secondary.withOpacity(skin.isLight ? 0.70 : 0.94),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(skin.isLight ? 0.10 : 0.18),
            blurRadius: 18,
            spreadRadius: 0.7,
            offset: const Offset(-2, -1),
          ),
          BoxShadow(
            color: secondary.withOpacity(skin.isLight ? 0.10 : 0.18),
            blurRadius: 18,
            spreadRadius: 0.7,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [skin.panelSoft, skin.panel, skin.panelDeep],
            stops: [0.0, 0.58, 1.0],
          ),
          border: Border.all(
            color: skin.isLight
                ? skin.border.withOpacity(0.42)
                : Colors.white.withOpacity(0.07),
            width: 0.9,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildChatBubblePair(ChatMessage msg, int index) {
    // If this message has been closed/deleted, render nothing
    if (_deletedMessages.contains(index)) return const SizedBox.shrink();

    // Skip messages with empty user text or empty AI text (e.g. incomplete history entries)
    if (msg.userText.trim().isEmpty || msg.aiText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final isMinimized = _minimizedMessages.contains(index);
    final aiPreview = _cleanDisplayText(msg.aiText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── User message (right-aligned) with per-message controls ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Minimize / Maximize / Close controls (left of user bubble)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimize / Maximize
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: isMinimized
                        ? 'Maximize message'
                        : 'Minimize message',
                    onPressed: () => setState(() {
                      if (isMinimized) {
                        _minimizedMessages.remove(index);
                      } else {
                        _minimizedMessages.add(index);
                      }
                    }),
                    icon: Icon(
                      isMinimized
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 16,
                      color: const Color(0xFF69D9E8).withOpacity(0.7),
                    ),
                  ),
                ),
                // Close / Delete
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove message',
                    onPressed: () =>
                        setState(() => _deletedMessages.add(index)),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            // User bubble
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A4A5C),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: null,
                  ),
                  child: Text(
                    _korlixVisibleUserText(msg.userText),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
        // ── AI response (left-aligned) — hidden when minimized ──
        if (!isMinimized)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 18, right: 48),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F2E),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI avatar row
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF69D9E8).withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF69D9E8).withOpacity(0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF69D9E8),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Korlix AI',
                        style: TextStyle(
                          color: Color(0xFF69D9E8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // AI response text
                  if (msg.isImage && msg.generatedItem != null) ...[
                    _buildGeneratedImagePreview(
                      msg.generatedItem!,
                      height: 200,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    aiPreview,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Action buttons: Copy, Share, Open, PDF, Credit Dispute
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // Copy
                      _chatActionButton(
                        icon: Icons.copy_rounded,
                        label: 'Copy',
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: msg.aiText),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      // Share
                      _chatActionButton(
                        icon: Icons.share_rounded,
                        label: 'Share',
                        onTap: () => Share.share(msg.aiText),
                      ),
                      // Open full
                      _chatActionButton(
                        icon: Icons.open_in_full_rounded,
                        label: 'Open',
                        onTap: () {
                          if (msg.generatedItem != null) {
                            _showResult(msg.generatedItem!);
                          } else {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF071B27),
                                title: const Text(
                                  'Full Response',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: SingleChildScrollView(
                                  child: Text(
                                    msg.aiText,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                      // PDF export if applicable
                      if (msg.allowPdf && msg.generatedItem != null)
                        _chatActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'PDF',
                          onTap: () => _exportPdf(msg.generatedItem!),
                        ),
                      // Credit dispute letter downloads
                      if (msg.isCreditDispute)
                        ..._buildCreditDisputeDownloadButtons(msg),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCreditDisputeDownloadButtons(ChatMessage msg) {
    void downloadDocx(String? base64Data, String bureauName) {
      if (base64Data == null || base64Data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No $bureauName letter available.')),
        );
        return;
      }
      final safeName = (msg.consumerName ?? 'Consumer').replaceAll(' ', '_');
      final fileName = 'Dispute_Letter_${bureauName}_$safeName.docx';
      _saveCreditDocFile(base64Data, fileName);
    }

    return [
      _chatActionButton(
        icon: Icons.download_rounded,
        label: 'Equifax Letter',
        onTap: () => downloadDocx(msg.equifaxDocxBase64, 'Equifax'),
      ),
      _chatActionButton(
        icon: Icons.download_rounded,
        label: 'Experian Letter',
        onTap: () => downloadDocx(msg.experianDocxBase64, 'Experian'),
      ),
      _chatActionButton(
        icon: Icons.download_rounded,
        label: 'TransUnion Letter',
        onTap: () => downloadDocx(msg.transunionDocxBase64, 'TransUnion'),
      ),
    ];
  }

  Widget _chatActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);

    return _korlixBeveledButtonSurface(
      skin: skin,
      fill: skin.buttonFill.withValues(alpha: skin.isLight ? 0.96 : 0.72),
      border: skin.primary.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      borderWidth: 1.35,
      depth: 0.78,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: skin.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _korlixReadableToolForeground(skin),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(GeneratedItem item) {
    if (item.command == '__DOWNLOAD_CARD__') {
      final parts = item.content.split('|');
      final pdfB64 = parts.length > 1 ? parts[1] : '';
      final docxB64 = parts.length > 2 ? parts[2] : '';
      return _buildCreditDownloadCard(pdfB64, docxB64);
    }
    final language = AppLanguages.byCode(item.language);
    final preview = _cleanDisplayText(item.content);
    final isImage = item.hasImageResult;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isImage
                    ? Icons.image_rounded
                    : item.allowPdf
                    ? Icons.picture_as_pdf
                    : Icons.chat_bubble_outline,
                color: isImage
                    ? const Color(0xFFB7FF00)
                    : item.allowPdf
                    ? Colors.redAccent
                    : Colors.cyanAccent,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  isImage
                      ? 'Image'
                      : item.allowPdf
                      ? language.fileBadge
                      : language.answerBadge,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _korlixVisibleUserText(item.command),
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 10),
          if (isImage) ...[
            _buildGeneratedImagePreview(item, height: 260),
            const SizedBox(height: 10),
          ],
          Text(
            preview,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _showResult(item),
                child: Text(language.open),
              ),
              if (isImage) ...[
                OutlinedButton.icon(
                  onPressed: () => _saveGeneratedImage(item),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Save'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _shareGeneratedImage(item),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ] else ...[
                OutlinedButton(
                  onPressed: () => _copyResultText(item),
                  child: Text(language.copy),
                ),
                if (item.allowPdf)
                  OutlinedButton(
                    onPressed: () => _exportPdf(item),
                    child: Text(language.pdf),
                  ),
              ],
              TextButton(
                onPressed: () => _deleteResult(item),
                child: Text(
                  language.delete,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KorlixCyberPanelClipper extends CustomClipper<Path> {
  final double cut;

  const _KorlixCyberPanelClipper({this.cut = 24});

  @override
  Path getClip(Size size) {
    final safeCut = cut.clamp(0.0, size.shortestSide / 3).toDouble();

    return Path()
      ..moveTo(safeCut, 0)
      ..lineTo(size.width - safeCut, 0)
      ..lineTo(size.width, safeCut)
      ..lineTo(size.width, size.height - safeCut)
      ..lineTo(size.width - safeCut, size.height)
      ..lineTo(safeCut, size.height)
      ..lineTo(0, size.height - safeCut)
      ..lineTo(0, safeCut)
      ..close();
  }

  @override
  bool shouldReclip(covariant _KorlixCyberPanelClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

// BEGIN KORLIX CLEAN ANSWER READY BOX

class _KorlixCleanAnswerReadyBox extends StatelessWidget {
  final Widget child;

  const _KorlixCleanAnswerReadyBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KorlixCleanAnswerReadyBoxPainter(
        korlixSkinPaletteFor(kKorlixThemeNotifier.value),
      ),
      child: Container(
        height: 318,
        padding: const EdgeInsets.fromLTRB(34, 30, 34, 30),
        child: child,
      ),
    );
  }
}

class _KorlixCleanAnswerReadyBoxPainter extends CustomPainter {
  final KorlixSkinPalette skin;

  const _KorlixCleanAnswerReadyBoxPainter(this.skin);

  Path _panelPath(Size size, double inset) {
    final width = size.width;
    final height = size.height;
    final cut = math.max(14.0, math.min(width, height) * 0.075);

    return Path()
      ..moveTo(inset + cut, inset)
      ..lineTo(width - inset - cut * 0.82, inset)
      ..lineTo(width - inset, inset + cut)
      ..lineTo(width - inset, height - inset - cut)
      ..lineTo(width - inset - cut * 0.88, height - inset)
      ..lineTo(inset + cut * 0.92, height - inset)
      ..lineTo(inset, height - inset - cut)
      ..lineTo(inset, inset + cut)
      ..close();
  }

  void _strokeSolid(
    Canvas canvas,
    Path path,
    Color color,
    double width,
    double alpha,
  ) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha),
    );
  }

  void _strokeGradient(
    Canvas canvas,
    Path path,
    Rect rect,
    double width,
    double alpha,
  ) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            skin.primary.withValues(alpha: alpha),
            skin.tertiary.withValues(alpha: alpha * 0.62),
            skin.secondary.withValues(alpha: alpha),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) {
      return;
    }

    final rect = Offset.zero & size;
    final outer = _panelPath(size, 2.5);
    final middle = _panelPath(size, 13.5);

    canvas.drawPath(
      outer.shift(const Offset(0, 7)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            skin.panelSoft.withValues(alpha: skin.isLight ? 0.84 : 0.78),
            skin.panel.withValues(alpha: skin.isLight ? 0.92 : 0.72),
            skin.panelDeep.withValues(alpha: skin.isLight ? 0.88 : 0.84),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    canvas.drawPath(
      middle,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          center: const Alignment(0.52, -0.35),
          radius: 1.15,
          colors: [
            skin.primary.withValues(alpha: skin.isLight ? 0.055 : 0.095),
            skin.panelDeep.withValues(alpha: skin.isLight ? 0.18 : 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Two clean border lines only: outer + middle.
    // No decorative short remnants are drawn here.
    _strokeSolid(canvas, outer, Colors.white, 2.3, skin.isLight ? 0.26 : 0.16);
    _strokeGradient(canvas, outer, rect, 1.75, skin.isLight ? 0.74 : 0.82);

    _strokeSolid(canvas, middle, Colors.white, 0.9, skin.isLight ? 0.22 : 0.12);
    _strokeGradient(canvas, middle, rect, 1.25, skin.isLight ? 0.46 : 0.54);
  }

  @override
  bool shouldRepaint(covariant _KorlixCleanAnswerReadyBoxPainter oldDelegate) {
    return oldDelegate.skin.id != skin.id ||
        oldDelegate.skin.primary != skin.primary ||
        oldDelegate.skin.secondary != skin.secondary ||
        oldDelegate.skin.panel != skin.panel ||
        oldDelegate.skin.panelDeep != skin.panelDeep;
  }
}

// END KORLIX CLEAN ANSWER READY BOX

class MatrixThinkingPanel extends StatefulWidget {
  final String message;

  const MatrixThinkingPanel({super.key, required this.message});

  @override
  State<MatrixThinkingPanel> createState() => _MatrixThinkingPanelState();
}

class _MatrixThinkingPanelState extends State<MatrixThinkingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const String _chars = '01AIWIZCHEECHAIDATASTREAM';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _line(int seed, int length) {
    final buffer = StringBuffer();

    for (var i = 0; i < length; i++) {
      final index =
          ((seed * 7) + i * 11 + (_controller.value * 100).floor()) %
          _chars.length;
      buffer.write(_chars[index]);
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.48),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.30)),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.12),
                blurRadius: 22,
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_line(1, 38)}\n${_line(2, 38)}\n${_line(3, 38)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.cyanAccent.withOpacity(0.62),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TalkingWizardHost extends StatefulWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageChanged;

  const TalkingWizardHost({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  @override
  State<TalkingWizardHost> createState() => _TalkingWizardHostState();
}

class _TalkingWizardHostState extends State<TalkingWizardHost> {
  VideoPlayerController? _controller;

  bool _loading = true;
  bool _started = false;
  bool _needsTap = false;
  String? _error;

  LanguageCopy get _currentLanguage {
    return AppLanguages.byCode(widget.selectedLanguage);
  }

  @override
  void initState() {
    super.initState();
    _loadWizardVideo();
  }

  @override
  void didUpdateWidget(covariant TalkingWizardHost oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedLanguage != widget.selectedLanguage) {
      _loadWizardVideo();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadWizardVideo() async {
    setState(() {
      _loading = true;
      _started = false;
      _needsTap = false;
      _error = null;
    });

    try {
      final oldController = _controller;
      _controller = null;
      await oldController?.dispose();

      final controller = VideoPlayerController.asset(
        _currentLanguage.assetPath,
      );

      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1.0);
      await controller.seekTo(Duration.zero);

      if (!mounted) return;

      setState(() {
        _controller = controller;
        _loading = false;
        _started = false;
        _needsTap = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _started = false;
        _needsTap = false;
        _error = 'Chee Chai Chee could not load this language. Tap retry.';
      });
    }
  }

  void _playWizard() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _started = false;
        _needsTap = false;
      });
      return;
    }

    setState(() {
      _started = true;
      _needsTap = false;
      _error = null;
    });

    controller.setVolume(1.0);
    controller.seekTo(Duration.zero);

    controller
        .play()
        .then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;

            final currentController = _controller;

            if (currentController != null &&
                !currentController.value.isPlaying) {
              setState(() {
                _started = false;
                _needsTap = false;
              });
            }
          });
        })
        .catchError((_) {
          if (!mounted) return;

          setState(() {
            _started = false;
            _needsTap = false;
          });
        });
  }

  void _replayWizard() {
    _playWizard();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final current = _currentLanguage;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: AppLanguages.all.map((language) {
              final selected = language.code == widget.selectedLanguage;

              return ChoiceChip(
                selected: selected,
                label: Text(language.label),
                onSelected: _loading
                    ? null
                    : (_) {
                        widget.onLanguageChanged(language.code);
                      },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 365,
          constraints: const BoxConstraints(maxWidth: 365),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2EC7DF).withOpacity(0.18),
                blurRadius: 72,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(0.18),
                blurRadius: 110,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Color(0xFF10173A),
                          Color(0xFF050816),
                          Color(0xFF02030A),
                        ],
                        radius: 1.1,
                      ),
                    ),
                  ),
                  if (controller != null && controller.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  if (_loading)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(current.preparing),
                        ],
                      ),
                    ),
                  if (!_loading && !_started && _needsTap && _error == null)
                    Container(
                      color: Colors.black.withOpacity(0.52),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(28),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.76),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.cyanAccent.withOpacity(0.35),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Colors.cyanAccent,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                current.awaitingTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                current.awaitingSubtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _playWizard,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(current.awakenText),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadWizardVideo,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          children: [
            FilledButton.icon(
              onPressed: controller == null ? null : _replayWizard,
              icon: const Icon(Icons.replay),
              label: Text(current.replayGreeting),
            ),
            OutlinedButton.icon(
              onPressed: _loadWizardVideo,
              icon: const Icon(Icons.refresh),
              label: Text(current.reloadWizard),
            ),
          ],
        ),
      ],
    );
  }
}

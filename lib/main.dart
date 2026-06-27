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
import 'korlix_cyber_widgets.dart';

const String kKorlixImaginePicturePrompt =
    'Describe the picture you want Korlix AI to create.';

bool kSupabaseReady = false;
String? kKorlixAccessToken;
String? kKorlixRefreshToken;
String? kKorlixUserEmail;
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

      await _korlixRunBootStep('Device setup', () async {
        await KorlixDeviceStore.ensureLoaded();
      });

      await _korlixRunBootStep('Supabase setup', () async {
        const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
        const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

        if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
          await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
          kSupabaseReady = true;
        }
      });

      await _korlixRunBootStep('Mobile ads setup', () async {
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) {
          try {
            await MobileAds.instance.initialize();
          } catch (e) {
            debugPrint("AdMob init failed: $e");
          }
        }
      });

      runApp(const CheeChaiCheeApp());
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
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/auth/refresh'),
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _booting = true;

  bool get _signedIn =>
      kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      await KorlixDeviceStore.ensureLoaded().timeout(
        const Duration(seconds: 5),
      );

      final saved = await KorlixSessionStore.load().timeout(
        const Duration(seconds: 5),
      );

      if (saved != null) {
        final refreshed = await KorlixSessionStore.refresh(
          saved,
        ).timeout(const Duration(seconds: 8));

        if (refreshed != null) {
          kKorlixAccessToken = refreshed.accessToken;
          kKorlixRefreshToken = refreshed.refreshToken;
          kKorlixUserEmail = refreshed.email;
        } else {
          await KorlixSessionStore.clear();
        }
      }
    } catch (error, stack) {
      final warning = 'Session restore failed: $error';
      kKorlixBootWarnings.add(warning);
      debugPrint('Korlix startup warning: $warning');
      debugPrintStack(stackTrace: stack);
    }

    if (mounted) {
      setState(() {
        _booting = false;
      });
    }
  }

  Future<void> _handleSignedIn(KorlixAuthSession session) async {
    await KorlixSessionStore.save(session);

    setState(() {
      kKorlixAccessToken = session.accessToken;
      kKorlixRefreshToken = session.refreshToken;
      kKorlixUserEmail = session.email;
    });
  }

  Future<void> _handleSignOut() async {
    try {
      await KorlixDeviceStore.ensureLoaded();

      await http.post(
        Uri.parse('$kKorlixBackendBaseUrl/api/auth/signout'),
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

    await KorlixSessionStore.clear();

    setState(() {
      kKorlixAccessToken = null;
      kKorlixRefreshToken = null;
      kKorlixUserEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF040612), Color(0xFF071B27), Color(0xFF0A2B3D)],
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
        Uri.parse('$kKorlixBackendBaseUrl/api/auth/password-reset'),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF040612), Color(0xFF071B27), Color(0xFF0A2B3D)],
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
        Uri.parse('$kKorlixBackendBaseUrl/api/me'),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/reports'),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/account/delete-request'),
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
                      'No video generation',
                      'No music production',
                    ],
                  ),
                  _planCard(
                    title: 'Pro',
                    subtitle: 'For regular creators and daily productivity.',
                    price: '\$9.99 / month',
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
                    price: '\$39.99 / month',
                    accent: const Color(0xFFFFD166),
                    current: currentTier == 'ultra',
                    features: const [
                      'Access to all 9+ characters',
                      'Highest personal generation limits',
                      'Beta feature access',
                      'Limited video generation',
                      'OCR / handwriting / scanned image reading',
                      'Eligible for paid Music Production add-on when released',
                      'No ads',
                    ],
                  ),
                  _planCard(
                    title: 'Enterprise',
                    subtitle: 'For teams, businesses, schools, and agencies.',
                    price: 'Contact Sales',
                    accent: const Color(0xFFE4EBEE),
                    current: currentTier == 'enterprise',
                    features: const [
                      'All available characters',
                      'Team seats and admin controls',
                      'Custom text, video, and usage limits',
                      'Custom Music Production add-on options',
                      'Priority support',
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
                      'Music Production is a coming soon paid add-on. It is not included automatically in any tier unless purchased separately or included in an Enterprise agreement.',
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
        Uri.parse('$kKorlixBackendBaseUrl/api/characters/select'),
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
    switch (theme) {
      case 'black_white':
        return 'Black / White';
      case 'purple_green':
        return 'Purple / Green';
      case 'white_gray':
        return 'White / Gray';
      case 'gold_black':
        return 'Gold / Black';
      case 'pink_white':
        return 'Pink / White';
      case 'cyber_purple':
        return 'Cyber Purple';
      case 'ultra_gold':
        return 'Ultra Gold';
      case 'matrix_green':
        return 'Matrix Green';
      case 'dark_crimson':
        return 'Dark Crimson';
      case 'korlix_blue':
      default:
        return 'Korlix Blue';
    }
  }

  Future<void> _setTheme({required String theme}) async {
    kKorlixThemeNotifier.value = theme;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('korlix_ui_theme', theme);

    try {
      await http.post(
        Uri.parse('$kKorlixBackendBaseUrl/api/theme/set'),
        headers: KorlixDeviceStore.headers(),
        body: jsonEncode({'theme': theme}),
      );
    } catch (_) {
      // Local persistence is enough for the frontend theme switcher.
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Theme applied: ${_themeLabel(theme)}')),
    );
  }

  Future<void> _openThemePanel({
    required String currentTheme,
    String? currentTier,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF07111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        Widget themeTile(String theme, Color colorA, Color colorB) {
          final selected = kKorlixThemeNotifier.value == theme;

          return ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [colorA, colorB]),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorA.withValues(alpha: 0.30),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            title: Text(
              _themeLabel(theme),
              style: const TextStyle(
                color: Color(0xFFE4EBEE),
                fontWeight: FontWeight.w800,
              ),
            ),
            trailing: selected
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF69D9E8),
                  )
                : const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFA9C6CF),
                  ),
            onTap: () async {
              Navigator.of(context).pop();
              await _setTheme(theme: theme);
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
                    color: const Color(0xFFA9C6CF).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Color Theme',
                  style: TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the frontend glow and panel contrast.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA9C6CF),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                themeTile(
                  'korlix_blue',
                  const Color(0xFF69D9E8),
                  const Color(0xFFB794F4),
                ),
                themeTile('black_white', Colors.white, const Color(0xFF5B6472)),
                themeTile(
                  'purple_green',
                  const Color(0xFFB794F4),
                  const Color(0xFF7CFF6B),
                ),
                themeTile('white_gray', Colors.white, const Color(0xFF9CA3AF)),
                themeTile(
                  'gold_black',
                  const Color(0xFFFFD166),
                  const Color(0xFF0B0B0B),
                ),
                themeTile('pink_white', const Color(0xFFFF7AB8), Colors.white),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/me'),
        headers: _headers(),
      );

      final historyResponse = await http.get(
        Uri.parse('$kKorlixBackendBaseUrl/api/history'),
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

Color korlixThemeAccentFor(String theme) {
  switch (theme) {
    case 'black_white':
      return const Color(0xFFEDEDED);
    case 'purple_green':
      return const Color(0xFFB794F4);
    case 'white_gray':
      return const Color(0xFFF5F5F5);
    case 'gold_black':
      return const Color(0xFFFFD166);
    case 'pink_white':
      return const Color(0xFFFF7AB8);
    case 'cyber_purple':
      return const Color(0xFFB794F4);
    case 'ultra_gold':
      return const Color(0xFFFFD166);
    case 'matrix_green':
      return const Color(0xFF7CFF6B);
    case 'dark_crimson':
      return const Color(0xFFFF5C7A);
    case 'korlix_blue':
    default:
      return const Color(0xFF69D9E8);
  }
}

Color korlixThemePanelFor(String theme) {
  switch (theme) {
    case 'black_white':
      return const Color(0xFF030303);
    case 'purple_green':
      return const Color(0xFF12051E);
    case 'white_gray':
      return const Color(0xFF101214);
    case 'gold_black':
      return const Color(0xFF080704);
    case 'pink_white':
      return const Color(0xFF170711);
    case 'cyber_purple':
      return const Color(0xFF180C2B);
    case 'ultra_gold':
      return const Color(0xFF241B05);
    case 'matrix_green':
      return const Color(0xFF071F10);
    case 'dark_crimson':
      return const Color(0xFF260812);
    case 'korlix_blue':
    default:
      return const Color(0xFF071B27);
  }
}

Color korlixThemeSecondaryFor(String theme) {
  switch (theme) {
    case 'black_white':
      return const Color(0xFF8B95A1);
    case 'purple_green':
      return const Color(0xFF7CFF6B);
    case 'white_gray':
      return const Color(0xFF9CA3AF);
    case 'gold_black':
      return const Color(0xFFFFB000);
    case 'pink_white':
      return const Color(0xFFFFFFFF);
    case 'cyber_purple':
      return const Color(0xFFFF4AF3);
    case 'ultra_gold':
      return const Color(0xFFFFB000);
    case 'matrix_green':
      return const Color(0xFFB7FF00);
    case 'dark_crimson':
      return const Color(0xFFFFB3C1);
    case 'korlix_blue':
    default:
      return const Color(0xFFFF4AF3);
  }
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

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  bool _showSavedTopicsPanel = false;
  final ScrollController _savedTopicsScrollController = ScrollController();

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
  bool _imaginePictureMode = false;
  bool _fixCreditReportMode = false;

  bool _utilityPanelOpen = false;
  String? _selectedUtilityTool;

  static const List<String> _utilityTools = <String>[
    'Photo editor',
    'Video splitter',
    'Background remover',
    'PDF editor',
    'Songwriter',
    'Voice recorder',
    'Notebook',
    'Alarm',
    'Weather',
    'Outside temperature',
    'GIF maker',
    'Ringtone maker',
    'Reel maker',
  ];

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
  static const String _localChatTopicsPrefsKey = 'korlix_local_chat_topics_v1';
  final Map<String, KorlixLocalChatTopic> _chatTopicsById =
      <String, KorlixLocalChatTopic>{};
  String? _activeChatTopicId;
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

    return headers;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedKorlixTheme();
    _loadCurrentTier();
    _loadLocalChatTopics().then((_) {
      if (mounted && _chatTopicsById.isEmpty) {
        _loadChatHistory();
      }
    });
  }

  Future<void> _loadSavedKorlixTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('korlix_ui_theme');

    if (savedTheme != null && savedTheme.trim().isNotEmpty) {
      kKorlixThemeNotifier.value = savedTheme.trim();
    }
  }

  @override
  void dispose() {
    _savedTopicsOverlayEntry?.remove();
    _savedTopicsOverlayEntry = null;
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

  Map<String, dynamic> _decodeKorlixJsonMap(http.Response response) {
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

    final prompt = _controller.text.trim();

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
            Uri.parse('$kKorlixBackendBaseUrl/api/image/create'),
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
    final command = _controller.text.trim();

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

    final prompt = command.isEmpty
        ? 'Improve this picture and return an enhanced professional version.'
        : command;

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
        Uri.parse('$kKorlixBackendBaseUrl/api/image/improve'),
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

    final command = _controller.text.trim();
    final isCreditMode = _fixCreditReportMode;

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _fixCreditReportMode = false;
      _createAppMode = false;
    });

    try {
      if (isCreditMode) {
        // ── CREDIT DISPUTE MODE: call /api/credit-dispute-letters ──
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$kKorlixBackendBaseUrl/api/credit-dispute-letters'),
        );
        final headers = Map<String, String>.from(_authHeaders())
          ..remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['prompt'] = _buildThreadAwarePrompt(command);
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
        Uri.parse('\$kKorlixBackendBaseUrl/api/analyze-documents'),
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

  Future<void> _generate() async {
    if (_fixCreditReportMode && _activeUploadFiles.isEmpty) {
      setState(() {
        _error =
            'Attach your credit report first using the Upload button, then tap submit.';
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

    final command = _controller.text.trim();

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

    setState(() {
      _featuredAnswerDismissed = false;
      _answerMinimized = false;
      _loading = true;
      _error = null;
    });

    _speakConsiderItDone();

    try {
      final response = await http
          .post(
            Uri.parse(backendUrl()),
            headers: _authHeaders(),
            body: jsonEncode({
              'command': command,
              'language': _selectedLanguage,
            }),
          )
          .timeout(const Duration(seconds: 300));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] ?? '').toString().trim();

      if (content.isEmpty) {
        throw Exception('No AI content returned.');
      }

      setState(() {
        _loading = false;
        _controller.clear();
        final newItem = GeneratedItem(
          command: command,
          title: _makeResultTitle(command),
          content: content,
          language: _selectedLanguage,
          allowPdf: allowPdf,
        );
        _results.insert(0, newItem);
        _addChatMessage(
          ChatMessage(
            userText: command,
            aiText: content,
            language: _selectedLanguage,
            allowPdf: allowPdf,
            generatedItem: newItem,
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
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

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

  Widget _buildGeneratedImagePreview(
    GeneratedItem item, {
    double height = 280,
  }) {
    final bytes = _imageBytesFromDataUrl(item.imageDataUrl);

    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(
          bytes,
          width: double.infinity,
          height: height,
          fit: BoxFit.contain,
        ),
      );
    }

    final imageUrl = item.imageUrl;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          imageUrl,
          width: double.infinity,
          height: height,
          fit: BoxFit.contain,
        ),
      );
    }

    return const SizedBox.shrink();
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

  String _creditReportPromptSafeUi(String userNotes) {
    final notes = userNotes.trim();

    return <String>[
      'Korlix AI credit report review request.',
      '',
      'Important disclaimer:',
      'Korlix AI does not guarantee deletion of accounts, collections, inquiries, late payments, charge-offs, bankruptcies, repossessions, judgments, or any other credit-report item. Korlix AI also does not guarantee a credit score increase. This tool provides educational, organizational, and drafting assistance only. The user is responsible for reviewing all letters, facts, account details, addresses, dates, and legal claims before sending anything to a credit bureau, creditor, furnisher, or collection agency.',
      '',
      'User instruction:',
      'The user attached one or more credit report files. Analyze the uploaded credit report files and create a practical credit-report review and dispute-preparation package.',
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
      '8. Use cautious wording. Do not claim guaranteed deletion, guaranteed approval, or guaranteed score increase.',
      '9. Do not invent account numbers, dates, balances, addresses, or bureau names that are not visible in the uploaded files.',
    ].join('\n');
  }

  Future<void> _showCreditReportDisclaimerSafeUi() async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Credit report disclaimer'),
          content: const SingleChildScrollView(
            child: Text(
              'Korlix AI does not guarantee deletion of any credit-report item and does not guarantee a credit score increase.\n\n'
              'This tool helps review uploaded credit report files, organize possible issues, and draft educational dispute-preparation language. It is not a guarantee, legal advice, financial advice, or a substitute for reviewing your own reports carefully.\n\n'
              'How to use it:\n'
              '1. Tap Fix My Credit Report.\n'
              '2. Tap Upload.\n'
              '3. Attach your credit report file or files.\n'
              '4. Tap submit.\n\n'
              'You can close this popup and continue.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('I understand'),
            ),
          ],
        );
      },
    );
  }

  void _activateCreditReportModeSafeUi() {
    setState(() {
      _fixCreditReportMode = true;
      _createVideoMode = false;
      _improvePictureMode = false;
      _imaginePictureMode = false;
      _error = null;
      _controller.text =
          'Please analyze my attached credit report and generate 3 separate dispute letters (Equifax, Experian, TransUnion) for any negative or inaccurate items.';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showCreditReportDisclaimerSafeUi();
      }
    });
  }

  Widget _buildSafeUiQuickActionChip(QuickAction action) {
    final isVideoAction = _isCreateVideoQuickAction(action);
    final isImproveAction = _isImprovePictureQuickAction(action);
    final isImagineAction = _isImaginePictureQuickAction(action);
    final isCreditAction = _isCreditReportActionSafeUi(action);
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

    final enabledTextColor = isHighlighted
        ? const Color(0xFF061008)
        : const Color(0xFFE4EBEE);

    final enabledBackgroundColor = isHighlighted
        ? const Color(0xFFB7FF00)
        : const Color(0xFF120D18);

    final enabledBorderColor = isHighlighted
        ? const Color(0xFFD9FF5A)
        : const Color(0xFF2EC7DF).withOpacity(0.34);

    return ActionChip(
      avatar: isVideoAction
          ? Icon(
              Icons.movie_creation_outlined,
              size: 17,
              color: _loading ? Colors.white38 : enabledTextColor,
            )
          : isImproveAction
          ? Icon(
              Icons.auto_fix_high_rounded,
              size: 17,
              color: _loading ? Colors.white38 : enabledTextColor,
            )
          : isImagineAction
          ? Icon(
              Icons.image_search_rounded,
              size: 17,
              color: _loading ? Colors.white38 : enabledTextColor,
            )
          : isCreditAction
          ? Icon(
              Icons.credit_score_rounded,
              size: 17,
              color: _loading ? Colors.white38 : enabledTextColor,
            )
          : isAppAction
          ? Icon(
              Icons.app_shortcut_rounded,
              size: 17,
              color: _loading ? Colors.white38 : enabledTextColor,
            )
          : null,
      label: Text(
        isVideoAction
            ? 'Create Video'
            : isImproveAction
            ? 'Improve my picture'
            : isImagineAction
            ? 'Imagine a picture'
            : isCreditAction
            ? 'Fix My Credit Report'
            : isAppAction
            ? 'Create an App'
            : action.label,
      ),
      labelStyle: TextStyle(
        color: _loading ? Colors.white38 : enabledTextColor,
        fontWeight: FontWeight.w900,
        fontSize: 12.5,
      ),
      backgroundColor: enabledBackgroundColor,
      disabledColor: Colors.black.withOpacity(0.25),
      side: BorderSide(color: _loading ? Colors.white10 : enabledBorderColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: _loading ? null : () => _useQuickAction(action),
    );
  }

  void _useQuickAction(QuickAction action) {
    if (_isCreditReportActionSafeUi(action)) {
      // Toggle off if already active
      if (_fixCreditReportMode) {
        setState(() {
          _fixCreditReportMode = false;
          _error = null;
          _controller.text = '';
          _controller.selection = const TextSelection.collapsed(offset: 0);
        });
        return;
      }
      _activateCreditReportModeSafeUi();
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
      // Toggle off if already active
      if (_improvePictureMode) {
        setState(() {
          _improvePictureMode = false;
          _error = null;
          _controller.text = '';
          _controller.selection = const TextSelection.collapsed(offset: 0);
        });
        return;
      }

      const defaultImprovePrompt =
          'Enhance this photo with professional quality: improve lighting, sharpness, color, contrast, and background polish. Preserve the subject identity, face, and overall realism. Make it look like a high-end professional photograph.';
      setState(() {
        _improvePictureMode = true;
        _createVideoMode = false;
        _imaginePictureMode = false;
        _fixCreditReportMode = false;
        _createAppMode = false;
        _error = null;
        _controller.text = defaultImprovePrompt;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: defaultImprovePrompt.length),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Upload an image, then tap submit — or edit the prompt first.',
          ),
        ),
      );

      return;
    }

    if (_isImaginePictureQuickAction(action)) {
      setState(() {
        _imaginePictureMode = true;
        _createVideoMode = false;
        _improvePictureMode = false;
        _fixCreditReportMode = false;
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF040612), Color(0xFF10173A), Color(0xFF250032)],
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
        Uri.parse('$kKorlixBackendBaseUrl/api/me'),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/history'),
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
        _chatMessages.clear();
        _chatMessages.addAll(msgs);
        _seedLegacyTopicFromLoadedHistory(msgs);
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
      } else if (tool == 'PDF editor') {
        _improvePictureMode = false;
        _fixCreditReportMode = false;
      } else {
        _improvePictureMode = false;
        _fixCreditReportMode = false;
      }
    });
  }

  Widget _buildUtilityButton() {
    final isActive = _utilityPanelOpen || _selectedUtilityTool != null;

    return ActionChip(
      avatar: Icon(
        Icons.build_circle_outlined,
        size: 18,
        color: isActive ? Colors.white : const Color(0xFF67E8F9),
      ),
      label: const Text('Utility'),
      labelStyle: TextStyle(
        color: isActive ? Colors.white : const Color(0xFFE5E7EB),
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: isActive
          ? const Color(0xFF16A34A)
          : const Color(0xFF111827),
      side: BorderSide(
        color: isActive ? const Color(0xFF22C55E) : const Color(0xFF0891B2),
      ),
      onPressed: _loading ? null : _toggleUtilityPanel,
    );
  }

  Widget _buildUtilityPanel() {
    final selectedTool = _selectedUtilityTool;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF071923),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF0891B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Color(0xFF67E8F9), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Utility',
                  style: TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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
                icon: const Icon(Icons.close, color: Color(0xFFE5E7EB)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _utilityTools.map((tool) {
              final selected = selectedTool == tool;

              return ActionChip(
                label: Text(tool),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFE5E7EB),
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: selected
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF111827),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF0891B2),
                ),
                onPressed: _loading ? null : () => _selectUtilityTool(tool),
              );
            }).toList(),
          ),
          if (selectedTool != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF145369)),
              ),
              child: Text(
                _utilityToolDescription(selectedTool),
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 13,
                  height: 1.35,
                ),
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
        final accent = korlixThemeAccentFor(theme);
        final panel = korlixThemePanelFor(theme);
        final compact = MediaQuery.of(context).size.width < 560;

        final logo = Container(
          width: compact ? 58 : 74,
          height: compact ? 58 : 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: panel.withOpacity(0.94),
            border: Border.all(color: accent.withOpacity(0.52)),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(0.28), blurRadius: 26),
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
              textAlign: compact ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                color: accent,
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

  Widget _buildMockupLanguageTabs() {
    return ValueListenableBuilder<String>(
      valueListenable: kKorlixThemeNotifier,
      builder: (context, theme, _) {
        final accent = korlixThemeAccentFor(theme);
        final panel = korlixThemePanelFor(theme);

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
                      ? accent.withOpacity(0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: selected
                      ? Border.all(color: accent.withOpacity(0.54))
                      : null,
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: accent.withOpacity(0.22),
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
              color: panel.withOpacity(0.66),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: accent.withOpacity(0.28)),
            ),
            child: Row(
              children: [
                tab(code: 'en', label: 'English'),
                Container(
                  width: 1,
                  height: 32,
                  color: accent.withOpacity(0.18),
                ),
                tab(code: 'es', label: 'Español'),
                Container(
                  width: 1,
                  height: 32,
                  color: accent.withOpacity(0.18),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/me'),
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

    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = true;
      _createVideoMode = false;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$kKorlixBackendBaseUrl/api/video/generate'),
            headers: _authHeaders(),
            body: jsonEncode({
              'prompt': _buildFullKorlixVideoPrompt(scene),
              'language': _selectedLanguage,
              'size': '1280x720',
              'seconds': 8,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 403 && data['upgradeRequired'] == true) {
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

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      final videoId = (data['videoId'] ?? data['video']?['id']).toString();

      if (videoId.isEmpty || videoId == 'null') {
        throw Exception('No video ID returned.');
      }

      setState(() {
        _loading = false;
        _createVideoMode = false;
        _controller.clear();
      });

      await _showVideoProgressDialog(videoId: videoId, prompt: scene);
    } catch (error) {
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

    Future<void> poll() async {
      try {
        final response = await http.get(
          Uri.parse('$kKorlixBackendBaseUrl/api/video/status/$videoId'),
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
        }

        if (status == 'failed') {
          errorMessage =
              video['error']?.toString() ?? 'Video generation failed.';
          timer?.cancel();
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
                        child: KorlixGeneratedVideoPlayer(
                          videoUrl:
                              '$kKorlixBackendBaseUrl/api/video/content/$videoId',
                          headers: _authHeaders(),
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
        Uri.parse('$kKorlixBackendBaseUrl/api/location/record'),
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final cardHeight = compact ? 315.0 : 300.0;

              return Container(
                height: cardHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF071B27).withOpacity(0.72),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF2EC7DF).withOpacity(0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2EC7DF).withOpacity(0.12),
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
                                    color: const Color(0xFF69D9E8),
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
                                    color: const Color(0xFFE4EBEE),
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
                                    color: const Color(
                                      0xFFE4EBEE,
                                    ).withOpacity(0.92),
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
                                      foregroundColor: const Color(0xFF69D9E8),
                                      side: BorderSide(
                                        color: const Color(
                                          0xFF2EC7DF,
                                        ).withOpacity(0.62),
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
                              color: const Color(0xFF69D9E8).withOpacity(0.48),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF69D9E8),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${character.name} is preparing your answer...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE4EBEE),
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
                                  color: const Color(0xFF07111F),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF0C2844),
                                      Color(0xFF07111F),
                                      Color(0xFF19103A),
                                    ],
                                    stops: [0.0, 0.52, 1.0],
                                  ),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF6DF7FF,
                                    ).withValues(alpha: 0.62),
                                    width: 1.15,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6DF7FF,
                                      ).withValues(alpha: 0.16),
                                      blurRadius: 18,
                                      spreadRadius: 0.8,
                                      offset: const Offset(-2, -1),
                                    ),
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFF4DFF,
                                      ).withValues(alpha: 0.16),
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
                                        const Icon(
                                          Icons.auto_awesome_rounded,
                                          color: Color(0xFF69D9E8),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'ANSWER READY',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Color(0xFF69D9E8),
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
                                            color: const Color(0xFF69D9E8),
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _featuredAnswerDismissed = true;
                                            });
                                          },
                                          icon: const Icon(Icons.close_rounded),
                                          color: const Color(0xFFE4EBEE),
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
                                      const SizedBox(height: 6),
                                      Text(
                                        activeResult.command,
                                        maxLines: compact ? 2 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFE4EBEE),
                                          fontSize: compact ? 13 : 15,
                                          fontWeight: FontWeight.w900,
                                          height: 1.18,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.22,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF2EC7DF,
                                              ).withOpacity(0.18),
                                            ),
                                          ),
                                          child: activeResult.hasImageResult
                                              ? _buildGeneratedImagePreview(
                                                  activeResult,
                                                  height: 300,
                                                )
                                              : SingleChildScrollView(
                                                  child: Text(
                                                    activeResult.content,
                                                    style: TextStyle(
                                                      color: const Color(
                                                        0xFFA9C6CF,
                                                      ),
                                                      fontSize: compact
                                                          ? 12.5
                                                          : 13.5,
                                                      height: 1.32,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: compact ? 40 : 44,
                                              child: FilledButton.icon(
                                                onPressed: () =>
                                                    _copyFeaturedResult(
                                                      activeResult,
                                                    ),
                                                icon: const Icon(
                                                  Icons.copy_rounded,
                                                  size: 17,
                                                ),
                                                label: const Text('Copy'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFB794F4,
                                                  ),
                                                  foregroundColor: const Color(
                                                    0xFF120D18,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SizedBox(
                                              height: compact ? 40 : 44,
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _shareFeaturedResult(
                                                      activeResult,
                                                    ),
                                                icon: const Icon(
                                                  Icons.share_rounded,
                                                  size: 17,
                                                ),
                                                label: const Text('Share'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFF69D9E8,
                                                  ),
                                                  side: BorderSide(
                                                    color: const Color(
                                                      0xFF69D9E8,
                                                    ).withOpacity(0.58),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
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

  Widget _buildCommandPanel() {
    final t = _t;
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
      final accent = locked ? const Color(0xFFFFD166) : const Color(0xFF69D9E8);
      final isGreen = active || success;

      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(active ? Icons.stop_circle_outlined : icon, size: 18),
            if (locked)
              const Positioned(
                right: -7,
                top: -7,
                child: Icon(
                  Icons.lock_rounded,
                  size: 10,
                  color: Color(0xFFFFD166),
                ),
              ),
          ],
        ),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: isGreen ? const Color(0xFF061008) : accent,
          backgroundColor: isGreen
              ? const Color(0xFFB7FF00)
              : Colors.black.withOpacity(0.20),
          side: BorderSide(
            color: isGreen ? const Color(0xFFD9FF5A) : accent.withOpacity(0.42),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }

    Widget answerReadyBody() {
      if (_loading && activeResult == null) {
        return const Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF69D9E8),
            ),
          ),
        );
      }

      if (activeResult == null) {
        return const SizedBox.expand();
      }

      if (activeResult.hasImageResult) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildGeneratedImagePreview(activeResult, height: 210),
        );
      }

      return SingleChildScrollView(
        child: Text(
          activeResult.content,
          style: const TextStyle(
            color: Color(0xFFE4EBEE),
            fontSize: 14,
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget answerReadyPanel() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: activeResult == null ? null : () => _showResult(activeResult),
        onLongPress: activeResult == null
            ? null
            : () => _copyFeaturedResult(activeResult),
        child: _KorlixCleanAnswerReadyBox(child: answerReadyBody()),
      );
    }

    Widget singleInputBoard() {
      return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.40),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF69D9E8).withOpacity(0.48),
              width: 1.15,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A2B3D).withOpacity(0.78),
                const Color(0xFF07111F).withOpacity(0.88),
                const Color(0xFF19103A).withOpacity(0.70),
              ],
              stops: const [0.0, 0.55, 1.0],
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
                  cursorColor: const Color(0xFF69D9E8),
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.28,
                    color: Color(0xFFE4EBEE),
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: const Color(0xFFA9C6CF).withOpacity(0.74),
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
              const SizedBox(width: 8),
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
                          ? const Color(0xFF69D9E8).withOpacity(0.16)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE4EBEE),
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 25,
                            color: canSubmit
                                ? const Color(0xFF69D9E8)
                                : Colors.white38,
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

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF071B27).withOpacity(0.88),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: const Color(0xFF2EC7DF).withOpacity(0.46),
                width: 1.1,
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

                const SizedBox(height: 12),

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
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _showLocatorOptions,
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Locator'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF69D9E8),
                        backgroundColor: Colors.black.withOpacity(0.20),
                        side: BorderSide(
                          color: const Color(0xFF69D9E8).withOpacity(0.42),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    _buildUtilityButton(),
                    if (_currentTier == 'basic')
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _openDonateCashApp,
                        icon: const Icon(Icons.favorite_rounded, size: 18),
                        label: const Text(r'$cashapp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFD166),
                          backgroundColor: Colors.black.withOpacity(0.20),
                          side: BorderSide(
                            color: const Color(0xFFFFD166).withOpacity(0.46),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ],
                ),

                if (_utilityPanelOpen) ...[
                  const SizedBox(height: 12),
                  _buildUtilityPanel(),
                ],

                if (_activeUploadFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSelectedUploadFilesPanel(),
                ],

                if (_loading) ...[
                  const SizedBox(height: 14),
                  MatrixThinkingPanel(message: t.matrixMessage),
                ],

                const SizedBox(height: 14),

                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  alignment: WrapAlignment.center,
                  children: t.quickActions
                      .map(_buildSafeUiQuickActionChip)
                      .toList(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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

  List<KorlixLocalChatTopic> get _sortedChatTopicThreads {
    final topics = _chatTopicsById.values
        .where((topic) => topic.messages.isNotEmpty)
        .toList();

    topics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return topics;
  }

  Map<String, dynamic> _encodeGeneratedItem(GeneratedItem item) {
    return <String, dynamic>{
      'command': item.command,
      'title': item.title,
      'content': item.content,
      'language': item.language,
      'allowPdf': item.allowPdf,
      'imageDataUrl': item.imageDataUrl,
      'imageUrl': item.imageUrl,
    };
  }

  GeneratedItem _decodeGeneratedItem(Map<String, dynamic> data) {
    return GeneratedItem(
      command: (data['command'] ?? '').toString(),
      title: (data['title'] ?? 'Korlix AI').toString(),
      content: (data['content'] ?? '').toString(),
      language: (data['language'] ?? 'en').toString(),
      allowPdf: data['allowPdf'] == true,
      imageDataUrl: data['imageDataUrl']?.toString(),
      imageUrl: data['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> _encodeChatMessage(ChatMessage message) {
    return <String, dynamic>{
      'userText': message.userText,
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
        command: (data['userText'] ?? '').toString(),
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
      userText: (data['userText'] ?? '').toString(),
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
          } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> _persistLocalChatTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _sortedChatTopicThreads.map(_encodeLocalChatTopic).toList(),
      );

      await prefs.setString(_localChatTopicsPrefsKey, encoded);
    } catch (_) {}
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
      return;
    }

    final now = DateTime.now();
    final id = _makeLocalChatTopicId();

    _activeChatTopicId = id;
    _chatTopicsById[id] = KorlixLocalChatTopic(
      id: id,
      title: _deriveTopicTitle(prompt),
      updatedAt: now,
      messages: const <ChatMessage>[],
    );
  }

  GeneratedItem _generatedItemFromChatMessage(ChatMessage message) {
    if (message.generatedItem != null) {
      return message.generatedItem!;
    }

    return GeneratedItem(
      command: message.userText,
      title: _makeResultTitle(message.userText),
      content: message.aiText,
      language: message.language,
      allowPdf: message.allowPdf,
      imageDataUrl: message.imageDataUrl,
      imageUrl: message.imageUrl,
    );
  }

  void _addChatMessage(ChatMessage message) {
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
    if (messages.isEmpty || _chatTopicsById.isNotEmpty) {
      return;
    }

    final id = _makeLocalChatTopicId();

    final topic = KorlixLocalChatTopic(
      id: id,
      title: _deriveTopicTitle(messages.first.userText),
      updatedAt: messages.last.createdAt,
      messages: List<ChatMessage>.from(messages),
    );

    _chatTopicsById[id] = topic;
    _activeChatTopicId = id;

    unawaited(_persistLocalChatTopics());
  }

  String _buildThreadAwarePrompt(String command) {
    final topicId = _activeChatTopicId;
    final topic = topicId == null ? null : _chatTopicsById[topicId];

    final messages = topic?.messages ?? _chatMessages;

    if (messages.isEmpty) {
      return command;
    }

    final recentMessages = messages.length > 8
        ? messages.sublist(messages.length - 8)
        : List<ChatMessage>.from(messages);

    final buffer = StringBuffer()
      ..writeln('Continue this existing chat topic with memory.')
      ..writeln()
      ..writeln('Previous conversation in this topic:');

    for (final message in recentMessages) {
      final userText = message.userText.trim();
      final aiText = _cleanDisplayText(message.aiText).trim();

      if (userText.isNotEmpty) {
        buffer.writeln('User: $userText');
      }

      if (aiText.isNotEmpty) {
        buffer.writeln('Korlix AI: $aiText');
      }

      buffer.writeln();
    }

    buffer
      ..writeln('Current user message:')
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

    setState(() {
      _activeChatTopicId = null;
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
      _createAppMode = false;

      _utilityPanelOpen = false;
      _selectedUtilityTool = null;
      _pickedUploadFile = null;
      _pickedUploadFiles.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New chat started. Send a message to save this topic.'),
      ),
    );
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

  Widget _buildSavedTopicsMenuButton() {
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
                  ? const Color(0xFF12213A).withOpacity(0.96)
                  : const Color(0xCC10192E),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _showSavedTopicsPanel
                    ? const Color(0xFFFF4AF3)
                    : const Color(0xFF8BEFFF),
                width: 1.25,
              ),
            ),
            child: const Icon(
              Icons.menu_rounded,
              color: Color(0xFFF2FBFF),
              size: 27,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedTopicsOverlay() {
    final topics = _sortedChatTopicThreads;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xF20B1428),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF89EAFF).withOpacity(0.76),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69D9E8).withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFFFF4AF3).withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(8, 10),
          ),
          const BoxShadow(
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
                color: const Color(0xFF0B2438).withOpacity(0.78),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF69D9E8).withOpacity(0.62),
                  width: 1.0,
                ),
              ),
              child: const Text(
                'New Chat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFF3FBFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: topics.isEmpty
                ? Center(
                    child: Text(
                      'No saved chats yet.\nTap New Chat, send a message, and it will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFF3FBFF).withOpacity(0.72),
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
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final topic = topics[index];
                      final selected = topic.id == _activeChatTopicId;

                      return InkWell(
                        onTap: () => _openSavedTopic(topic.id),
                        borderRadius: BorderRadius.circular(13),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF183050).withOpacity(0.78)
                                : const Color(0xFF07111F).withOpacity(0.58),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFFF4AF3).withOpacity(0.82)
                                  : const Color(0xFF69D9E8).withOpacity(0.36),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            topic.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF3FBFF),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 10),

          Center(
            child: InkWell(
              onTap: _showMoreSavedTopics,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 48,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x668BEFFF), width: 1),
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFFF2FBFF),
                  size: 25,
                ),
              ),
            ),
          ),
        ],
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
    const cyan = Color(0xFF63F3FF);
    const magenta = Color(0xFFFF4AF3);

    Widget rail({
      required double width,
      required double height,
      required Color color,
    }) {
      return IgnorePointer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.70),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(2.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cyan.withValues(alpha: 0.96),
            const Color(0xFF2D8CFF).withValues(alpha: 0.54),
            magenta.withValues(alpha: 0.96),
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: cyan.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: 1.2,
            offset: const Offset(-3, -2),
          ),
          BoxShadow(
            color: magenta.withValues(alpha: 0.30),
            blurRadius: 28,
            spreadRadius: 1.2,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C2844), Color(0xFF08101F), Color(0xFF160B2F)],
            stops: [0.0, 0.54, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
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
                        Colors.white.withValues(alpha: 0.10),
                        cyan.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.24, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: rail(width: 74, height: 3, color: cyan),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: rail(width: 62, height: 3, color: magenta),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              child: rail(
                width: 58,
                height: 2,
                color: magenta.withValues(alpha: 0.90),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 16,
              child: rail(
                width: 76,
                height: 2,
                color: cyan.withValues(alpha: 0.90),
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
    // Preserve empty/deleted chat rows exactly as-is.
    if (child is SizedBox && child.width == 0 && child.height == 0) {
      return child;
    }

    final primary = index.isEven
        ? const Color(0xFF63F3FF)
        : const Color(0xFFFF4AF3);
    final secondary = index.isEven
        ? const Color(0xFFFF4AF3)
        : const Color(0xFF63F3FF);

    Widget rail({
      required double width,
      required double height,
      required Color color,
    }) {
      return IgnorePointer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.65),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(1.9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.94),
            const Color(0xFF3A52FF).withValues(alpha: 0.18),
            secondary.withValues(alpha: 0.94),
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 18,
            spreadRadius: 0.7,
            offset: const Offset(-2, -1),
          ),
          BoxShadow(
            color: secondary.withValues(alpha: 0.18),
            blurRadius: 18,
            spreadRadius: 0.7,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF091522), Color(0xFF07111D), Color(0xFF140A2C)],
            stops: [0.0, 0.58, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
            width: 0.9,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 14,
              child: rail(width: 68, height: 2.5, color: primary),
            ),
            Positioned(
              top: 10,
              right: 14,
              child: rail(width: 52, height: 2.5, color: secondary),
            ),
            Positioned(
              bottom: 10,
              left: 14,
              child: rail(
                width: 46,
                height: 2,
                color: secondary.withValues(alpha: 0.90),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 14,
              child: rail(
                width: 70,
                height: 2,
                color: primary.withValues(alpha: 0.90),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: child,
            ),
          ],
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
                    border: Border.all(
                      color: const Color(0xFF69D9E8).withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    msg.userText,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF69D9E8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
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
          Text(item.command, style: const TextStyle(color: Colors.white60)),
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
      painter: const _KorlixCleanAnswerReadyBoxPainter(),
      child: Container(
        height: 318,
        padding: const EdgeInsets.fromLTRB(34, 30, 34, 30),
        child: child,
      ),
    );
  }
}

class _KorlixCleanAnswerReadyBoxPainter extends CustomPainter {
  const _KorlixCleanAnswerReadyBoxPainter();

  Path _octPath(Rect rect, double cut) {
    return Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - cut, rect.top)
      ..lineTo(rect.right, rect.top + cut)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + cut, rect.bottom)
      ..lineTo(rect.left, rect.bottom - cut)
      ..lineTo(rect.left, rect.top + cut)
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
        ..strokeJoin = StrokeJoin.bevel
        ..strokeCap = StrokeCap.square
        ..strokeWidth = width
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
        ..strokeJoin = StrokeJoin.bevel
        ..strokeCap = StrokeCap.square
        ..strokeWidth = width
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF69D9E8).withValues(alpha: alpha),
            const Color(0xFF2D8CFF).withValues(alpha: alpha * 0.52),
            const Color(0xFFFF4AF3).withValues(alpha: alpha),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final rect = Offset.zero & size;

    // Clean two-border Answer panel.
    // Removed all decorative accent bars:
    // - top-right magenta remnant
    // - bottom-left cyan remnant
    // - bottom-right magenta remnant
    final outer = _octPath(rect.deflate(6), 30);
    final inner = _octPath(rect.deflate(19), 23);

    canvas.drawPath(
      outer.shift(const Offset(0, 8)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18283A), Color(0xFF07111F), Color(0xFF21103A)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2438), Color(0xFF07111F), Color(0xFF160B2F)],
        ).createShader(rect),
    );

    // Border line 1: outer.
    _strokeSolid(canvas, outer, Colors.white, 2.4, 0.16);
    _strokeGradient(canvas, outer, rect, 1.7, 0.78);

    // Border line 2: inner.
    _strokeSolid(canvas, inner, Colors.white, 0.9, 0.12);
    _strokeGradient(canvas, inner, rect, 1.25, 0.52);
  }

  @override
  bool shouldRepaint(covariant _KorlixCleanAnswerReadyBoxPainter oldDelegate) {
    return false;
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

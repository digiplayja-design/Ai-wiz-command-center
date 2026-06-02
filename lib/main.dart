import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:speech_to_text/speech_to_text.dart' as speech_to_text;
import 'package:video_player/video_player.dart';

bool kSupabaseReady = false;
String? kKorlixAccessToken;
String? kKorlixRefreshToken;
String? kKorlixUserEmail;

const String kKorlixBackendBaseUrl =
    'https://chee-chai-chee-backend.onrender.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

    kSupabaseReady = true;
  }

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await MobileAds.instance.initialize();
  }

  runApp(const CheeChaiCheeApp());
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
    final saved = await KorlixSessionStore.load();

    if (saved != null) {
      final refreshed = await KorlixSessionStore.refresh(saved);

      if (refreshed != null) {
        kKorlixAccessToken = refreshed.accessToken;
        kKorlixRefreshToken = refreshed.refreshToken;
        kKorlixUserEmail = refreshed.email;
      } else {
        await KorlixSessionStore.clear();
      }
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

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Enter your email and password.';
        _message = null;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
        _message = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
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
      setState(() {
        _error = _cleanError(error);
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
            'Basic starter character. Open History → View characters to preview and unlock more Korlix AI characters.',
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
            ),
          ),
        ],
      ),
    );
  }
}

class KorlixCharacterIntroPreview extends StatefulWidget {
  final String assetPath;
  final bool muted;

  const KorlixCharacterIntroPreview({
    super.key,
    required this.assetPath,
    this.muted = true,
  });

  @override
  State<KorlixCharacterIntroPreview> createState() =>
      _KorlixCharacterIntroPreviewState();
}

class _KorlixCharacterIntroPreviewState
    extends State<KorlixCharacterIntroPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant KorlixCharacterIntroPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.assetPath != widget.assetPath) {
      _loadVideo();
    }
  }

  Future<void> _loadVideo() async {
    final oldController = _controller;
    _controller = null;
    _ready = false;
    await oldController?.dispose();

    try {
      final controller = VideoPlayerController.asset(widget.assetPath);

      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0.0 : 1.0);
      await controller.play();

      if (!mounted) {
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          child: _ready && controller != null && controller.value.isInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
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
      ),
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
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(widget.assetPath)
      ..setLooping(true)
      ..setVolume(0);

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

    if (_ready && !_controller.value.isPlaying) {
      _controller.play();
    }
  }

  @override
  void dispose() {
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

    return headers;
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
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
          'details': 'Reported from saved history. Prompt: $prompt',
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
                      'Limited saved history',
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
                      'Saved history access',
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
    switch (id) {
      case 'jj':
        return 'assets/characters/jj/intro.mp4';
      case 'phil':
        return 'assets/characters/phil/intro.mp4';
      case 'yuna':
        return 'assets/characters/yuna/intro.mp4';
      case 'ji_a':
        return 'assets/characters/ji_a/intro.mp4';
      case 'chee_chai_chee':
        return 'assets/wizard_greeting_en.mp4';
      default:
        return null;
    }
  }

  bool _tierCanSelectCharacter({
    required String tier,
    required String characterId,
  }) {
    if (tier == 'enterprise' || tier == 'ultra') {
      return true;
    }

    if (tier == 'pro') {
      return ['jj', 'chee_chai_chee', 'phil'].contains(characterId);
    }

    return characterId == 'jj';
  }

  Future<bool> _selectCharacter(String characterId) async {
    try {
      final response = await http.post(
        Uri.parse('$kKorlixBackendBaseUrl/api/characters/select'),
        headers: _headers(),
        body: jsonEncode({'character_id': characterId}),
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

      await _showKorlixNotice(
        title: 'Character selected',
        message: 'Your Korlix AI character has been updated.',
      );

      return true;
    } catch (error) {
      await _showKorlixNotice(
        title: 'Character selection failed',
        message: _cleanError(error),
        danger: true,
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
        .toSet();

    var selectedId = selectedCharacterId;

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
                        final id = character['id']?.toString() ?? '';
                        final name =
                            character['name']?.toString() ?? 'Korlix Character';
                        final description =
                            character['description']?.toString() ?? '';
                        final tierRequired =
                            character['tier_required']?.toString() ?? 'basic';
                        final isActive = character['is_active'] == true;
                        final comingSoon = character['is_coming_soon'] == true;
                        final selected = id == selectedId;
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
                      'Saved History',
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
          : const Icon(Icons.history_rounded, size: 18),
      label: const Text('History'),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE4EBEE),
        backgroundColor: Colors.black.withOpacity(0.32),
      ),
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
      assetPath: 'assets/wizard_greeting_en.mp4',
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
        QuickAction(label: 'Ask anything', prompt: 'Answer this clearly: '),
        QuickAction(
          label: 'Build a plan',
          prompt: 'Build a step-by-step plan for ',
        ),
        QuickAction(label: 'Write for me', prompt: 'Write a polished '),
        QuickAction(
          label: 'Study / learn',
          prompt: 'Create a study guide for ',
        ),
        QuickAction(
          label: 'Business help',
          prompt: 'Give me practical business advice for ',
        ),
        QuickAction(
          label: 'Content ideas',
          prompt: 'Give me content ideas for ',
        ),
      ],
    ),
    LanguageCopy(
      code: 'es',
      label: 'Español',
      assetPath: 'assets/wizard_greeting_es.mp4',
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
          label: 'Créer un plan',
          prompt: 'Crée un plan étape par étape pour ',
        ),
        QuickAction(
          label: 'Écrire',
          prompt: 'Rédige un texte professionnel sur ',
        ),
        QuickAction(label: 'Étudier', prompt: 'Crée un guide d’étude pour '),
        QuickAction(
          label: 'Business',
          prompt: 'Donne-moi des conseils pratiques pour ',
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

  const GeneratedItem({
    required this.command,
    required this.title,
    required this.content,
    required this.language,
    required this.allowPdf,
  });
}

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _wizardCuePlayer = AudioPlayer();
  final speech_to_text.SpeechToText _speechToText =
      speech_to_text.SpeechToText();

  bool _loading = false;
  bool _voiceListening = false;
  fp.PlatformFile? _pickedUploadFile;
  bool _loadingTier = false;
  String _currentTier = 'basic';
  String? _error;
  String _selectedLanguage = 'en';

  final List<GeneratedItem> _results = [];

  LanguageCopy get _t => AppLanguages.byCode(_selectedLanguage);

  Map<String, String> _authHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $kKorlixAccessToken';
    }

    return headers;
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentTier();
  }

  @override
  void dispose() {
    _controller.dispose();
    _wizardCuePlayer.dispose();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _speakConsiderItDone() async {
    try {
      await _wizardCuePlayer.stop();

      final asset = switch (_selectedLanguage) {
        'es' => 'consider_done_es.mp3',
        'fr' => 'consider_done_fr.mp3',
        _ => 'consider_done_en.mp3',
      };

      await _wizardCuePlayer.play(AssetSource(asset), volume: 1.0);
    } catch (_) {
      // The wizard cue is optional. The app should still answer if audio fails.
    }
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
    return _currentTier == 'pro' ||
        _currentTier == 'ultra' ||
        _currentTier == 'enterprise';
  }

  bool get _hasAdvancedUploadAccess {
    return _currentTier == 'ultra' || _currentTier == 'enterprise';
  }

  bool _isAdvancedUploadName(String name) {
    final lower = name.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  Future<void> _handleUploadPressed() async {
    await _loadCurrentTier();

    if (!_hasDocumentUploadAccess) {
      await _showPremiumFeaturePrompt(
        title: 'Document Upload',
        availability: 'Pro, Ultra Premium, Enterprise',
        description:
            'Upload documents and ask Korlix AI questions about them. Basic users can see this feature but must upgrade to use it.',
      );
      return;
    }

    final extensions = _hasAdvancedUploadAccess
        ? ['pdf', 'docx', 'txt', 'md', 'csv', 'jpg', 'jpeg', 'png', 'webp']
        : ['pdf', 'docx', 'txt', 'md', 'csv'];

    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;

    if (file.size > 15 * 1024 * 1024) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File is too large. Maximum size is 15 MB.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isAdvancedUploadName(file.name) && !_hasAdvancedUploadAccess) {
      await _showPremiumFeaturePrompt(
        title: 'OCR and Handwriting Reader',
        availability: 'Ultra Premium, Enterprise',
        description:
            'Images, scans, screenshots, handwriting, and OCR-style reading are available on Ultra Premium and Enterprise.',
      );
      return;
    }

    setState(() {
      _pickedUploadFile = file;
    });
  }

  void _clearPickedUploadFile() {
    setState(() {
      _pickedUploadFile = null;
    });
  }

  Future<void> _generateWithUpload() async {
    final command = _controller.text.trim();
    final file = _pickedUploadFile;

    if (file == null) {
      return;
    }

    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.commandEmpty)));
      return;
    }

    if (file.bytes == null || file.bytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read this file. Try uploading it again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    _speakConsiderItDone();

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$kKorlixBackendBaseUrl/api/analyze-document'),
      );

      request.fields['command'] = command;
      request.fields['language'] = _selectedLanguage;

      if (kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $kKorlixAccessToken';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 403 && data['upgradeRequired'] == true) {
        setState(() {
          _loading = false;
        });

        await _showPremiumFeaturePrompt(
          title: data['requiredTier']?.toString() == 'ultra'
              ? 'Ultra Premium required'
              : 'Upgrade required',
          availability: data['requiredTier']?.toString() == 'ultra'
              ? 'Ultra Premium, Enterprise'
              : 'Pro, Ultra Premium, Enterprise',
          description:
              data['error']?.toString() ??
              'This upload feature requires a higher plan.',
        );

        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }

      final content = (data['content'] ?? '').toString().trim();

      if (content.isEmpty) {
        throw Exception('No AI content returned.');
      }

      final allowPdf =
          data['fileRequested'] == true || _shouldAllowPdf(command);

      setState(() {
        _loading = false;
        _controller.clear();
        _pickedUploadFile = null;
        _results.insert(
          0,
          GeneratedItem(
            command: 'Uploaded file: ${file.name}\nQuestion: $command',
            title: 'File answer: ${file.name}',
            content: content,
            language: _selectedLanguage,
            allowPdf: allowPdf,
          ),
        );
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\nDetails: $error';
      });
    }
  }

  Future<void> _generate() async {
    if (_pickedUploadFile != null) {
      await _generateWithUpload();
      return;
    }

    final command = _controller.text.trim();

    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.commandEmpty)));
      return;
    }

    final allowPdf = _shouldAllowPdf(command);

    setState(() {
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
          .timeout(const Duration(seconds: 90));

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
        _results.insert(
          0,
          GeneratedItem(
            command: command,
            title: _makeResultTitle(command),
            content: content,
            language: _selectedLanguage,
            allowPdf: allowPdf,
          ),
        );
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\nDetails: $error';
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
              child: SelectableText(_cleanDisplayText(item.content)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _copyResultText(item),
              child: Text(language.copy),
            ),
            if (item.allowPdf)
              TextButton(
                onPressed: () => _exportPdf(item),
                child: Text(language.exportPdf),
              ),
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

  void _useQuickAction(QuickAction action) {
    setState(() {
      _controller.text = action.prompt;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
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
                    Image.asset(
                      'assets/branding/korlix_mini_mark.png',
                      height: 72,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'KORLIX AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.appSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        t.backendConnected,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A2B3D).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFF2EC7DF).withOpacity(0.45),
                        ),
                      ),
                      child: const Text(
                        'Selected Character: JJ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF69D9E8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const KorlixHomeCharacterHero(),
                    const SizedBox(height: 28),
                    _buildCommandPanel(),
                    const SizedBox(height: 26),
                    _buildResults(),
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
            '$description\n\nAvailable on: $availability\n\nOpen History, then tap View plans / upgrade to see plan options.',
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
    return _currentTier == 'pro' ||
        _currentTier == 'ultra' ||
        _currentTier == 'enterprise';
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

  Widget _buildCommandPanel() {
    final t = _t;
    final hasText = _controller.text.trim().isNotEmpty;
    final hasResults = _results.isNotEmpty;

    final hintText = _selectedLanguage == 'es'
        ? 'Escribe aquí...'
        : _selectedLanguage == 'fr'
        ? 'Écrivez ici...'
        : 'Type here...';

    final readyText = _selectedLanguage == 'es'
        ? 'La respuesta está lista.'
        : _selectedLanguage == 'fr'
        ? 'La réponse est prête.'
        : 'The response is ready.';

    Widget toolButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool locked = false,
      bool active = false,
    }) {
      final accent = locked ? const Color(0xFFFFD166) : const Color(0xFF69D9E8);

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
          foregroundColor: accent,
          backgroundColor: active
              ? const Color(0xFF143B4A).withOpacity(0.58)
              : Colors.black.withOpacity(0.20),
          side: BorderSide(
            color: active ? const Color(0xFF69D9E8) : accent.withOpacity(0.42),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      );
    }

    return Container(
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
            color: const Color(0xFF2EC7DF).withOpacity(0.14),
            blurRadius: 34,
            spreadRadius: 3,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.40),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main chat row. The text box now replaces the old "Ask or create" title area.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  cursorColor: const Color(0xFF69D9E8),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (!_loading && _controller.text.trim().isNotEmpty) {
                      _generate();
                    }
                  },
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.30,
                    color: Color(0xFFE4EBEE),
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: const Color(0xFFA9C6CF).withOpacity(0.74),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.42),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.09),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF69D9E8),
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: hasText
                        ? const Color(0xFF143B4A)
                        : const Color(0xFF334155),
                    foregroundColor: const Color(0xFFE4EBEE),
                    disabledBackgroundColor: const Color(0xFF334155),
                    disabledForegroundColor: Colors.white54,
                    elevation: 0,
                    side: BorderSide(
                      color: hasText
                          ? const Color(0xFF69D9E8).withOpacity(0.70)
                          : Colors.white12,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  onPressed: (_loading || !hasText) ? null : _generate,
                  child: _loading
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFE4EBEE),
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded, size: 28),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Small tool row. Moving these below the input makes the Type Here box wider on phones.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              toolButton(
                icon: Icons.attach_file_rounded,
                label: 'Upload',
                locked: !_hasDocumentUploadAccess,
                onPressed: _loading ? null : _handleUploadPressed,
              ),
              toolButton(
                icon: Icons.mic_rounded,
                label: 'Voice',
                locked: !_hasVoiceAccess,
                active: _voiceListening,
                onPressed: _loading ? null : _handleVoiceInput,
              ),
            ],
          ),

          if (_pickedUploadFile != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2B3D).withOpacity(0.80),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFD166).withOpacity(0.42),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: Color(0xFFFFD166),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pickedUploadFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _clearPickedUploadFile,
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFFA9C6CF),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],

          if (hasResults && !_loading) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2B3D).withOpacity(0.84),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF69D9E8).withOpacity(0.34),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF69D9E8),
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      readyText,
                      style: const TextStyle(
                        color: Color(0xFFE4EBEE),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
            children: t.quickActions.map((action) {
              return ActionChip(
                label: Text(action.label),
                labelStyle: TextStyle(
                  color: _loading ? Colors.white38 : const Color(0xFFE4EBEE),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
                backgroundColor: const Color(0xFF120D18),
                disabledColor: Colors.black.withOpacity(0.25),
                side: BorderSide(
                  color: _loading
                      ? Colors.white10
                      : const Color(0xFF2EC7DF).withOpacity(0.34),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onPressed: _loading ? null : () => _useQuickAction(action),
              );
            }).toList(),
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
    );
  }

  Widget _buildResults() {
    final t = _t;

    if (_results.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.resultsTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _clearAllResults,
              icon: const Icon(Icons.delete_sweep),
              label: Text(t.clearAll),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._results.map(_buildResultCard),
      ],
    );
  }

  Widget _buildResultCard(GeneratedItem item) {
    final language = AppLanguages.byCode(item.language);
    final preview = _cleanDisplayText(item.content);

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
                item.allowPdf
                    ? Icons.picture_as_pdf
                    : Icons.chat_bubble_outline,
                color: item.allowPdf ? Colors.redAccent : Colors.cyanAccent,
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
                  item.allowPdf ? language.fileBadge : language.answerBadge,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.command, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 10),
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
              OutlinedButton(
                onPressed: () => _copyResultText(item),
                child: Text(language.copy),
              ),
              if (item.allowPdf)
                OutlinedButton(
                  onPressed: () => _exportPdf(item),
                  child: Text(language.pdf),
                ),
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
        _needsTap = true;
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
        _needsTap = true;
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
                _needsTap = true;
              });
            }
          });
        })
        .catchError((_) {
          if (!mounted) return;

          setState(() {
            _started = false;
            _needsTap = true;
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

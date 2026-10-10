import 'sounds/korlix_sound_service.dart';
import 'sounds/korlix_sound_host.dart';
import 'sounds/korlix_sound_actions.dart';
import 'sounds/korlix_sound_settings_screen.dart';
import 'directory/directory_client.dart';
import 'directory/directory_screen.dart';
import 'text_workspace/box_workspace.dart';
import 'text_workspace/box_store.dart';
import 'workforce/workforce_voice.dart';
import 'fieldproof/fieldproof_voice.dart';
import 'chat/chat_memory_client.dart';
import 'chat/chat_memory_screen.dart';
import 'resume_studio/resume_client.dart';
import 'resume_studio/resume_screen.dart';
import 'social/social_client.dart';
import 'social/social_screen.dart';
import 'social/social_notifications.dart';
import 'social/social_notification_banner.dart';
import 'social/social_alert_scope.dart';
import 'social/social_app_alerts.dart';
import 'camera_ask/camera_ask_client.dart';
import 'camera_ask/camera_ask_screen.dart';
import 'inventory/inventory_client.dart';
import 'inventory/inventory_screen.dart';
import 'cyber_defender/defender_client.dart';
import 'cyber_defender/defender_screen.dart';
import 'study_studio/study_client.dart';
import 'study_studio/study_screen.dart';
import 'app_studio/app_studio_client.dart';
import 'app_studio/app_studio_screen.dart';
import 'app_studio/app_portal_screen.dart';
import 'music_studio/music_client.dart';
import 'music_studio/music_studio_screen.dart';
import 'music_studio/music_voice.dart';
import 'chat/chat_workspace.dart';
import 'theme/korlix_theme.dart';
import 'theme/korlix_action_button.dart';
import 'theme/korlix_action_grid.dart';
import 'auth/korlix_welcome_confirmation.dart';
import 'auth/korlix_signup_eligibility.dart';
import 'auth/knova_welcome_controller.dart';
import 'auth/rici_welcome_button.dart';
import 'navigation/home_tool_catalog.dart';
import 'navigation/home_quick_access.dart';
import 'navigation/home_tool_finder.dart';
import 'launch/korlix_launch_countdown.dart';
import 'characters/character_catalog.dart';
import 'characters/character_orbit.dart';
import 'characters/character_selection_controller.dart';
import 'characters/character_video_gestures.dart';
export 'characters/character_catalog.dart' show normalizeKorlixCharacterId;
import 'auth/korlix_october_welcome.dart';
import 'auth/korlix_login_preferences.dart';
import 'auth/korlix_token_store.dart';
import 'ads/korlix_ad_consent.dart';
import 'account/korlix_account_deletion_dialog.dart';
import 'support/korlix_ai_report_client.dart';
import 'support/korlix_saved_output_report_dialog.dart';
import 'reviews/korlix_app_feedback_dialog.dart';
import 'reviews/korlix_review_host.dart';
import 'reviews/korlix_review_invitation.dart';
import 'reviews/korlix_store_review.dart';
import 'sharing/korlix_share.dart';
import 'auth/korlix_portal_launch.dart';
import 'input_tools/upload_studio.dart';
import 'input_tools/voice_composer.dart';
import 'locator/locator_screen.dart';
import 'theme/korlix_theme_picker.dart';
import 'theme/korlix_screen_skin.dart';
import 'theme/korlix_appearance_preferences.dart';
import 'theme/korlix_appearance_picker.dart';
import 'theme/korlix_screensaver_controller.dart';
import 'theme/korlix_smoke_screensaver.dart';
export 'theme/korlix_theme.dart';
import 'chat/chat_request.dart';
import 'bookkeeping/bookkeeping_client.dart';
import 'bookkeeping/bookkeeping_screen.dart';
import 'receipt_wiz/receipt_wiz_entry.dart';
import 'bookkeeping/bookkeeping_voice.dart';
import 'payroll/payroll_client.dart';
import 'payroll/payroll_screen.dart';
import 'scheduling/scheduling_client.dart';
import 'scheduling/scheduling_screen.dart';
import 'scheduling/scheduling_voice.dart';
import 'virtual_closet/closet_client.dart';
import 'virtual_closet/closet_screen.dart';
import 'contract_radar/radar_client.dart';
import 'contract_radar/radar_screen.dart';
import 'fieldproof/fieldproof_client.dart';
import 'fieldproof/fieldproof_screen.dart';
import 'babyblend/babyblend_client.dart';
import 'babyblend/babyblend_screen.dart';
import 'tax_prep/tax_prep_screen.dart';
import 'ai_visibility/visibility_client.dart';
import 'ai_visibility/visibility_screen.dart';
import 'pod/pod_client.dart';
import 'pod/pod_screen.dart';
import 'live_studio/live_studio_client.dart';
import 'live_studio/live_studio_screen.dart';
import 'seo_agent/seo_client.dart';
import 'seo_agent/seo_screen.dart';
import 'funnel_studio/funnel_client.dart';
import 'funnel_studio/funnel_screen.dart';
import 'workforce/workforce_client.dart';
import 'workforce/workforce_screen.dart';
import 'contacts_crm/contacts_client.dart';
import 'contacts_crm/contacts_screen.dart';
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
import 'package:url_launcher/url_launcher.dart';

import 'korlix_video_downloader.dart';
import 'korlix_image_saver.dart';
import 'korlix_video_preview_source.dart';
import 'korlix_ai_quality_policy.dart';
import 'korlix_cyber_widgets.dart';

import 'improve_picture/screens/portrait_studio_home.dart';
import 'improve_picture/picture_studio_client.dart';
import 'improve_picture/picture_studio_screen.dart';
import 'improve_picture/picture_studio_session.dart';
import 'improve_picture/picture_artwork.dart';
import 'imagine_studio/imagine_catalog.dart';
import 'imagine_studio/imagine_client.dart';
import 'imagine_studio/imagine_screen.dart';
import 'imagine_studio/imagine_art.dart';
import 'logo_studio/logo_client.dart';
import 'email_enhancer/email_client.dart';
import 'email_enhancer/email_screen.dart';
import 'email_enhancer/email_artwork.dart';
import 'logo_studio/logo_screen.dart';
import 'image_to_video/image_to_video_screen.dart';

import 'live_convo/korlix_live_convo_test_screen.dart';

import 'billing/korlix_apple_billing.dart';
import 'billing/web_billing_screen.dart';
import 'privacy/korlix_third_party_ai_consent.dart';
import 'privacy/korlix_privacy_settings.dart';

import 'meeting_copilot/korlix_meeting_copilot_route.dart';
import 'meeting_copilot/k135z_copilot_entry.dart';
import 'meeting_copilot/korlix_meeting_copilot_auth_bridge.dart';
import 'meeting_copilot/korlix_meeting_copilot_access.dart';

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
String? _korlixReviewAccountScope;
KorlixPortalLaunch? _korlixInitialPortalLaunch;
bool _korlixPortalLaunchRequested = false;

final ValueNotifier<int> kKorlixAuthRevision = ValueNotifier<int>(0);
final ValueNotifier<int> kKorlixBillingRevision = ValueNotifier<int>(0);

String? korlixConsentAccountScope(KorlixAuthSession? session) {
  if (session == null) return null;
  try {
    final parts = session.accessToken.split('.');
    if (parts.length != 3) return null;
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (claims is! Map<String, dynamic>) return null;
    final issuer = claims['iss'];
    final subject = claims['sub'];
    if (issuer is! String || issuer.isEmpty || subject is! String || subject.isEmpty) return null;
    // This is only a local privacy-preference namespace. Authorization still
    // requires the backend to validate the token and active device session.
    return jsonEncode([issuer, subject]);
  } catch (_) {
    return null;
  }
}

void korlixSetInMemorySession(KorlixAuthSession? session) {
  KorlixThirdPartyAiConsent.setAccountScope(korlixConsentAccountScope(session));
  _korlixReviewAccountScope = korlixConsentAccountScope(session);
  if (session == null || session.email != kKorlixUserEmail) {
    kKorlixSounds.clearSession();
  }
  kKorlixAccessToken = session?.accessToken;
  kKorlixRefreshToken = session?.refreshToken;
  kKorlixUserEmail = session?.email;
  kKorlixAuthRevision.value = kKorlixAuthRevision.value + 1;
}

Future<void> korlixClearLocalAuthSession() async {
  // Invalidate visible sessions before waiting on a locked device's storage.
  korlixSetInMemorySession(null);
  try {
    await KorlixSessionStore.clear().timeout(const Duration(seconds: 5));
  } catch (_) {
    kKorlixBootWarnings.add(
      'Session storage could not be cleared. Unlock your device and try again.',
    );
  }
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

const bool _kKorlixBackendOverrideDeclared = bool.hasEnvironment(
  'AI_WIZARD_BACKEND_URL',
);

const String _kKorlixBackendOverrideUrl = String.fromEnvironment(
  'AI_WIZARD_BACKEND_URL',
);

const String kKorlixBackendBaseUrl = _kKorlixBackendOverrideDeclared
    ? _kKorlixBackendOverrideUrl
    : 'https://chee-chai-chee-backend.onrender.com';
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installKorlixErrorSurface();
      _korlixPortalLaunchRequested =
          Uri.base.queryParametersAll.containsKey('app_portal');
      _korlixInitialPortalLaunch = captureKorlixPortalLaunch();

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
  const overrideUrl = kKorlixBackendBaseUrl;

  if (overrideUrl.isNotEmpty) {
    if (overrideUrl.endsWith('/api/generate')) {
      return overrideUrl;
    }
    return '$overrideUrl/api/generate';
  }

  const productionBackendUrl = kKorlixBackendBaseUrl;
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

final _korlixNavigatorKey = GlobalKey<NavigatorState>();
final _korlixReviewHomeKey = GlobalKey<_CommandCenterScreenState>();
final _korlixReviewRouteObserver = KorlixReviewRouteObserver();
final _korlixReviewChanges = Listenable.merge([
  kKorlixAuthRevision,
  kKorlixScreensaver.visibility,
  _korlixReviewRouteObserver,
]);
final _korlixSocialRouteObserver = RouteObserver<ModalRoute<dynamic>>();
final _korlixScreensaverObserver = KorlixScreensaverObserver(kKorlixScreensaver);

class CheeChaiCheeApp extends StatelessWidget {
  const CheeChaiCheeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return KorlixThemeScope(builder: (context, theme) => MaterialApp(
      navigatorKey: _korlixNavigatorKey,
      // Invitation fragments are credentials for explicit acceptance, not
      // Flutter route names. Account sign-in always happens first.
      initialRoute: _korlixPortalLaunchRequested ? '/' : null,
      navigatorObservers: <NavigatorObserver>[
        kKorlixMeetingCopilotAuthObserver,
        _korlixSocialRouteObserver,
        _korlixScreensaverObserver,
        _korlixReviewRouteObserver,
      ],
      builder: (context, child) => KorlixReviewHost(
        sessionChanges: _korlixReviewChanges,
        accountScope: () => _korlixReviewAccountScope,
        isAvailable: () => !kKorlixScreensaver.visibility.value,
        canPrompt: () => _korlixReviewRouteObserver.atHome &&
            (_korlixReviewHomeKey.currentState?._canShowReviewPrompt ?? false),
        navigatorKey: _korlixNavigatorKey,
        onPromptCancelled: cancelKorlixStoreReviewRequest,
        onPrompt: (context) async {
          if (kIsWeb) {
            await showKorlixReviewInvitation(context,
              baseUrl: kKorlixBackendBaseUrl,
              headersBuilder: () => {
                ...KorlixDeviceStore.headers(),
                if (kKorlixAccessToken?.isNotEmpty == true)
                  'Authorization': 'Bearer $kKorlixAccessToken',
              },
              sessionChanges: kKorlixAuthRevision,
            );
          } else {
            await requestKorlixStoreReview();
          }
        },
        child: KorlixSoundHost(child: SocialAppAlerts(
        baseUrl: kKorlixBackendBaseUrl,
        headersBuilder: () => {
          ...KorlixDeviceStore.headers(),
          if (kKorlixAccessToken?.isNotEmpty == true)
            'Authorization': 'Bearer $kKorlixAccessToken',
        },
        sessionChanges: kKorlixAuthRevision,
        navigatorKey: _korlixNavigatorKey,
        routeObserver: _korlixSocialRouteObserver,
        beforeOpenCall: stopKorlixCharacterSpeechGlobally,
        child: KorlixSmokeScreensaver(sessionChanges: kKorlixAuthRevision,
          child: child ?? const SizedBox.shrink()),
      ))),

      routes: <String, WidgetBuilder>{
        KorlixMeetingCopilotRoute.routeName: (_) =>
            K135zCopilotEntry(
              backendBaseUri: Uri.parse(kKorlixBackendBaseUrl),
              authChanges: kKorlixAuthRevision,
              headersBuilder: () => {
                ...KorlixDeviceStore.headers(),
                if (kKorlixAccessToken?.isNotEmpty == true)
                  'Authorization': 'Bearer $kKorlixAccessToken',
              },
            ),
      },
      title: 'Korlix AI',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const AuthGate(),
    ));
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
    final tokens = await KorlixTokenStore.instance.read();
    final accessToken = tokens?.accessToken;
    final refreshToken = tokens?.refreshToken;
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

    await KorlixTokenStore.instance.write(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    if (session.email != null && session.email!.isNotEmpty) {
      await prefs.setString(emailKey, session.email!);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await KorlixTokenStore.instance.clear();
    await prefs.remove(emailKey);
  }

  static Future<KorlixAuthSession?> refresh(
    KorlixAuthSession session, {
    http.Client? client,
  }) async {
    final refreshToken = session.refreshToken;

    if (refreshToken == null || refreshToken.isEmpty) {
      return session;
    }

    try {
      await KorlixDeviceStore.ensureLoaded();
      final post = client?.post ?? http.post;
      final response = await post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          ...KorlixDeviceStore.headers(),
        },
        body: jsonEncode({
          'refresh_token': refreshToken,
          ...KorlixDeviceStore.bodyFields(),
        }),
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

      // The caller must verify the originating session is still current
      // before persisting a response that arrived after an account switch.
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

Future<Map<String, String>> korlixAuthenticatedBackendHeaders({http.Client? client}) async {
  final revision = kKorlixAuthRevision.value;
  KorlixAuthSession? session;
  final inMemoryAccessToken = kKorlixAccessToken?.trim();
  if (inMemoryAccessToken != null && inMemoryAccessToken.isNotEmpty) {
    session = KorlixAuthSession(
      accessToken: inMemoryAccessToken,
      refreshToken: kKorlixRefreshToken,
      email: kKorlixUserEmail,
    );
  } else {
    try {
      session = await KorlixSessionStore.load().timeout(const Duration(seconds: 3));
    } catch (_) {
      session = null;
    }
  }
  if (session != null && revision == kKorlixAuthRevision.value) {
    KorlixAuthSession? refreshed;
    try {
      refreshed = await KorlixSessionStore.refresh(session, client: client)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      refreshed = session;
    }
    if (revision != kKorlixAuthRevision.value) {
      throw StateError('Your account changed. Please try again.');
    }
    if (refreshed == null) {
      await korlixClearLocalAuthSession();
      return KorlixDeviceStore.headers();
    }
    await KorlixSessionStore.save(refreshed);
    if (revision != kKorlixAuthRevision.value) {
      throw StateError('Your account changed. Please try again.');
    }
    korlixSetInMemorySession(refreshed);
  } else if (revision != kKorlixAuthRevision.value) {
    throw StateError('Your account changed. Please try again.');
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
  String? _restoreNotice;
  late final KnovaWelcomeController _welcome;
  bool _portalLaunchScheduled = false;

  void _schedulePortalLaunch() {
    final launch = _korlixInitialPortalLaunch;
    if (launch == null || _portalLaunchScheduled || !_signedIn) return;
    _portalLaunchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_signedIn) {
        _portalLaunchScheduled = false;
        return;
      }
      _korlixInitialPortalLaunch = null;
      final client = AppStudioClient(
        backendBaseUrl: kKorlixBackendBaseUrl,
        headersBuilder: () => {
          ...KorlixDeviceStore.headers(),
          if (kKorlixAccessToken?.isNotEmpty == true)
            'Authorization': 'Bearer $kKorlixAccessToken',
        },
        sessionChanges: kKorlixAuthRevision,
      );
      unawaited(Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AppPortalScreen(
          client: client,
          portalId: launch.portalId,
          inviteToken: launch.inviteToken,
        ),
      )));
    });
  }

  bool get _signedIn =>
      kKorlixAccessToken != null && kKorlixAccessToken!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _welcome = KnovaWelcomeController(backendBaseUrl: kKorlixBackendBaseUrl, sounds: kKorlixSounds);
    unawaited(_welcome.preload());
    kKorlixAuthRevision.addListener(_handleAuthRevisionChanged);
    _restoreSession();
  }

  @override
  void dispose() {
    _welcome.dispose();
    kKorlixAuthRevision.removeListener(_handleAuthRevisionChanged);
    super.dispose();
  }

  void _handleAuthRevisionChanged() {
    if (!_signedIn) _welcome.signedOut();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _restoreSession() async {
    final revision = kKorlixAuthRevision.value;
    try {
      await KorlixDeviceStore.ensureLoaded().timeout(
        const Duration(seconds: 5),
      );

      final saved = await KorlixSessionStore.load().timeout(
        const Duration(seconds: 5),
      );

      if (!mounted || revision != kKorlixAuthRevision.value) return;
      if (saved == null) {
        await korlixClearLocalAuthSession();
      } else {
        final refreshed = await KorlixSessionStore.refresh(
          saved,
        ).timeout(const Duration(seconds: 8));

        if (!mounted || revision != kKorlixAuthRevision.value) return;
        if (refreshed != null) {
          await KorlixSessionStore.save(refreshed).timeout(const Duration(seconds: 5));
          if (!mounted || revision != kKorlixAuthRevision.value) return;
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

      // A locked keychain or interrupted migration must not erase the only
      // recoverable credentials. Start signed out and allow a later retry.
      if (revision == kKorlixAuthRevision.value) korlixSetInMemorySession(null);
      _restoreNotice =
          'We could not restore your session. Unlock your device and sign in again.';
    } finally {
      if (mounted) {
        setState(() => _booting = false);
      }
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
    unawaited(_welcome.signedIn());
  }

  Future<void> _handleSignOut() async {
    _welcome.signedOut();
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
      ).timeout(const Duration(seconds: 8));
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
      return AuthScreen(
        onSignedIn: _handleSignedIn,
        onSignInGesture: _welcome.prepareGesture,
        initialNotice: _restoreNotice,
      );
    }

    _schedulePortalLaunch();

    return Stack(
      children: [
        CommandCenterScreen(key: _korlixReviewHomeKey),
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const KorlixAccountButton(),
                const _KorlixSoundSettingsButton(),
                RiciWelcomeButton(controller: _welcome),
              ]),
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
              child: MediaQuery.sizeOf(context).width < 460 &&
                      MediaQuery.textScalerOf(context).scale(14) > 18
                  ? IconButton(
                      tooltip: 'Sign out',
                      enableFeedback: false,
                      onPressed: korlixSoundAction(_handleSignOut),
                      icon: const Icon(Icons.logout, color: Color(0xFFE4EBEE)),
                    )
                  : TextButton.icon(
                onPressed: korlixSoundAction(_handleSignOut),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: korlixSoundButtonStyle(TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE4EBEE),
                  backgroundColor: Colors.black.withOpacity(0.32),
                )),
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
  final http.Client? client;
  final DateTime? seasonalDate;
  final VoidCallback? onSignInGesture;
  final String? initialNotice;

  const AuthScreen({super.key, required this.onSignedIn, this.client, this.seasonalDate, this.onSignInGesture, this.initialNotice});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  late final Future<void> _preferencesLoaded;
  bool _preferencesReady = false;
  bool _rememberEmail = false;
  bool _offerPasswordSave = true;
  bool _emailEdited = false;
  String? _preferenceMessage;

  bool _isSignUp = false;
  KorlixSignupAgeBand? _signupAgeBand;
  bool _acceptedSignupPolicies = false;
  bool _parentPermission = false;
  bool _obscurePassword = true;
  bool _loading = false;
  bool _resetLoading = false;
  bool _showForgotPassword = false;
  String? _message;
  String? _confirmationEmail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _message = widget.initialNotice;
    _preferencesLoaded = _restoreLoginPreferences();
  }

  Future<void> _restoreLoginPreferences() async {
    final preferences = await KorlixLoginPreferences.load();
    if (!mounted) return;
    setState(() {
      _rememberEmail = preferences.rememberEmail;
      _offerPasswordSave = preferences.offerPasswordSave;
      if (!_emailEdited && _emailController.text.isEmpty && _rememberEmail) {
        _emailController.text = preferences.email;
      }
      _preferencesReady = true;
    });
  }

  Future<void> _saveLoginPreferences() async {
    final saved = await KorlixLoginPreferences(
      rememberEmail: _rememberEmail,
      email: _emailController.text.trim(),
      offerPasswordSave: _offerPasswordSave,
    ).save();
    if (!mounted) return;
    final message = saved ? null : 'Your device could not save these preferences. You can still sign in.';
    if (message != _preferenceMessage) {
      setState(() => _preferenceMessage = message);
    }
  }

  @override
  void dispose() {
    _passwordFocus.dispose();
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
    if (_loading || _resetLoading) return;
    widget.onSignInGesture?.call();
    await _preferencesLoaded;
    if (!mounted || _loading || _resetLoading) return;
    final signingUp = _isSignUp;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (signingUp) {
      final eligibilityError = korlixSignupEligibilityError(
        ageBand: _signupAgeBand,
        acceptedPolicies: _acceptedSignupPolicies,
        parentPermission: _parentPermission,
      );
      if (eligibilityError != null) {
        setState(() { _error = eligibilityError; _message = null; });
        return;
      }
    }

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
      _obscurePassword = true;
      _error = null;
      _message = null;
      _showForgotPassword = false;
    });

    try {
      await KorlixDeviceStore.ensureLoaded();
      final path = signingUp ? '/api/auth/signup' : '/api/auth/signin';

      final post = widget.client?.post ?? http.post;
      final response = await post(
        Uri.parse('$kKorlixBackendBaseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          ...KorlixDeviceStore.headers(),
        },
        body: jsonEncode({
          'email': email,
          'password': password,
          ...KorlixDeviceStore.bodyFields(),
          if (signingUp) 'signup_eligibility': {
            'age_band': _signupAgeBand!.value,
            'terms_accepted': _acceptedSignupPolicies,
            'privacy_acknowledged': _acceptedSignupPolicies,
            'parent_permission': _parentPermission,
            'policy_version': korlixSignupPolicyVersion,
          },
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw Exception(data['error'] ?? 'Authentication failed.');
      }

      final session = data['session'] as Map<String, dynamic>?;

      if (session == null || session['access_token'] == null) {
        if (!signingUp) throw Exception('Sign-in did not return a session. Please try again.');
        await _saveLoginPreferences();
        if (!mounted) return;
        TextInput.finishAutofillContext(shouldSave: _offerPasswordSave);
        _passwordController.clear();
        setState(() {
          _confirmationEmail = email;
          _message = null;
          _isSignUp = false;
        });
        return;
      }

      if (session['access_token'].toString().trim().isEmpty) {
        throw Exception('Sign-in did not return a session. Please try again.');
      }
      await _saveLoginPreferences();
      if (!mounted) return;
      TextInput.finishAutofillContext(shouldSave: _offerPasswordSave);
      await widget.onSignedIn(
        KorlixAuthSession(
          accessToken: session['access_token'].toString(),
          refreshToken: session['refresh_token']?.toString(),
          email: data['user']?['email']?.toString() ?? email,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final cleanedError = _cleanError(error);

      setState(() {
        final lower = cleanedError.toLowerCase();
        final unconfirmed = lower.contains('email not confirmed') || lower.contains('email_not_confirmed');
        if (unconfirmed) {
          _confirmationEmail = email;
          _passwordController.clear();
        }
        _error = unconfirmed ? null : cleanedError;
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
    final skin = korlixSkinOf(context);
    final title = _isSignUp
        ? 'Create your Korlix AI account'
        : 'Sign in to Korlix AI';
    final buttonText = _isSignUp ? 'Create account' : 'Sign in';
    final seasonalDate = widget.seasonalDate ?? DateTime.now();
    final october = korlixIsOctober(seasonalDate);

    return Scaffold(
      body: KorlixOctoberWelcome(
        date: seasonalDate,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: skin.panel,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: (october ? const Color(0xFFFFBD69) : const Color(0xFF2EC7DF)).withValues(alpha: .38),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (october ? const Color(0xFFCE83FF) : const Color(0xFF2EC7DF)).withValues(alpha: .12),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: _confirmationEmail != null
                    ? KorlixWelcomeConfirmation(
                        email: _confirmationEmail!,
                        onSignIn: () => setState(() { _confirmationEmail = null; _isSignUp = false; }),
                        onChangeEmail: () => setState(() { _confirmationEmail = null; _isSignUp = true; _signupAgeBand = null; _acceptedSignupPolicies = false; _parentPermission = false; _emailController.clear(); _passwordController.clear(); }),
                      )
                    : AutofillGroup(
                    key: ValueKey('auth-autofill-$_isSignUp'),
                    onDisposeAction: AutofillContextAction.cancel,
                    child: Material(
                    color: Colors.transparent,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (october) ...[
                        KorlixOctoberGreeting(date: seasonalDate),
                      ],
                      Image.asset(
                        'assets/branding/korlix_mini_mark.png',
                        height: 74,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'KORLIX AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          color: skin.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: skin.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const KorlixAgeNotice(),
                      const SizedBox(height: 16),
                      if (_isSignUp) ...[
                        KorlixSignupAgeField(
                          ageBand: _signupAgeBand,
                          enabled: !_loading && !_resetLoading,
                          onChanged: (value) => setState(() {
                            _signupAgeBand = value;
                            _acceptedSignupPolicies = false;
                            _parentPermission = false;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 18),
                      ],
                      TextField(
                        key: const Key('auth-email'),
                        controller: _emailController,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        enabled: !_loading && !_resetLoading,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        onChanged: (_) {
                          _emailEdited = true;
                          if (_preferencesReady && _rememberEmail) unawaited(_saveLoginPreferences());
                        },
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: skin.text),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: skin.mutedText),
                          filled: true,
                          fillColor: skin.inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('auth-password'),
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
                        enabled: !_loading && !_resetLoading,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        obscureText: _obscurePassword,
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        style: TextStyle(color: skin.text),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(color: skin.mutedText),
                          suffixIcon: IconButton(enableFeedback: false,
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: korlixSoundAction(_loading
                                ? null
                                : () => setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  })),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: skin.mutedText,
                            ),
                          ),
                          filled: true,
                          fillColor: skin.inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        key: const Key('remember-email'),
                        value: _rememberEmail,
                        onChanged: !_preferencesReady || _loading || _resetLoading ? null : (value) {
                          setState(() => _rememberEmail = value ?? false);
                          unawaited(_saveLoginPreferences());
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('Remember my email', style: TextStyle(color: skin.text, fontSize: 14)),
                      ),
                      CheckboxListTile(
                        key: const Key('offer-password-save'),
                        value: _offerPasswordSave,
                        onChanged: !_preferencesReady || _loading || _resetLoading ? null : (value) {
                          setState(() => _offerPasswordSave = value ?? false);
                          unawaited(_saveLoginPreferences());
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('Offer to save password', style: TextStyle(color: skin.text, fontSize: 14)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _preferenceMessage ?? 'Your browser or password manager can save and autofill your password.',
                          style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.35),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      if (!_isSignUp && _showForgotPassword) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: korlixSoundAction((_loading || _resetLoading)
                              ? null
                              : _requestPasswordReset),
                          icon: _resetLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: skin.primary,
                                  ),
                                )
                              : const Icon(Icons.lock_reset_rounded, size: 18),
                          label: Text(
                            _resetLoading
                                ? 'Sending reset email...'
                                : 'Forgot password? Send reset email',
                          ),
                          style: korlixSoundButtonStyle(TextButton.styleFrom(
                            foregroundColor: const Color(0xFF69D9E8),
                          )),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: skin.primary),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_isSignUp)
                        KorlixSignupAcknowledgments(
                          ageBand: _signupAgeBand,
                          acceptedPolicies: _acceptedSignupPolicies,
                          parentPermission: _parentPermission,
                          enabled: !_loading && !_resetLoading,
                          onPoliciesChanged: (value) => setState(() {
                            _acceptedSignupPolicies = value;
                            _error = null;
                          }),
                          onParentPermissionChanged: (value) => setState(() {
                            _parentPermission = value;
                            _error = null;
                          }),
                        ),
                      const KorlixSignupPolicyLinks(),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: korlixSoundAction(_loading || _resetLoading ||
                              (_isSignUp && _signupAgeBand == KorlixSignupAgeBand.under16)
                              ? null : _submit),
                          style: korlixSoundButtonStyle(ElevatedButton.styleFrom(
                            backgroundColor: october ? const Color(0xFFFFBD69) : const Color(0xFF143B4A),
                            foregroundColor: october ? const Color(0xFF352100) : const Color(0xFFE4EBEE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          )),
                          child: _loading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: october ? const Color(0xFF352100) : skin.text,
                                  ),
                                )
                              : Text(
                                  buttonText,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(style: korlixSoundButtonStyle(null),
                        onPressed: korlixSoundAction(_loading
                            ? null
                            : () {
                                TextInput.finishAutofillContext(shouldSave: false);
                                _passwordController.clear();
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _signupAgeBand = null;
                                  _acceptedSignupPolicies = false;
                                  _parentPermission = false;
                                  _obscurePassword = true;
                                  _error = null;
                                  _message = null;
                                  _showForgotPassword = false;
                                });
                              }),
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign in'
                              : 'New here? Create account',
                          style: TextStyle(color: skin.primary),
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
        ),
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
              onPressed: korlixSoundAction(_loading ? null : _load),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Preview'),
              style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB7FF00),
                side: const BorderSide(color: Color(0xFFB7FF00)),
              )),
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
  final bool dragSurface;
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
    this.dragSurface = false,
    this.fit = BoxFit.cover,
  });

  @override
  State<KorlixCharacterIntroPreview> createState() =>
      _KorlixCharacterIntroPreviewState();
}

class _KorlixCharacterIntroPreviewState
    extends State<KorlixCharacterIntroPreview> {
  // First play plus one repeat, then mute and hold the final frame.
  static const int _maxAutoLoops = 2;

  final Object _soundQuietOwner = Object();
  VideoPlayerController? _controller;
  VoidCallback? _releaseVideoGestures;
  bool _ready = false;
  bool _soundOn = false;
  int _completedLoops = 0;
  bool _handlingEnd = false;
  int _playbackRevision = 0;

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
    ++_playbackRevision;
    final oldController = _controller;
    _releaseVideoGestures?.call();
    _releaseVideoGestures = null;

    if (oldController != null) {
      oldController.removeListener(_handleVideoProgress);
    }

    _controller = null;
    kKorlixSounds.setQuiet(_soundQuietOwner, false);
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

      if (widget.dragSurface) {
        _releaseVideoGestures = allowCharacterVideoGestures(widget.assetPath);
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
    kKorlixSounds.setQuiet(_soundQuietOwner,
      controller != null && controller.value.isPlaying && controller.value.volume > 0);

    if (controller == null || _handlingEnd) {
      return;
    }

    final value = controller.value;
    if (_completedLoops >= (widget.loop ? _maxAutoLoops : 1)) return;

    if (!value.isInitialized || (!value.isPlaying && !value.isCompleted)) {
      return;
    }

    final duration = value.duration;

    if (duration == Duration.zero) {
      return;
    }

    // Use the actual completion signal; do not cut off the final words.
    if (value.isCompleted || value.position >= duration) {
      _handleVideoReachedEnd();
    }
  }

  Future<void> _handleVideoReachedEnd() async {
    final controller = _controller;

    if (controller == null || _handlingEnd) {
      return;
    }

    _handlingEnd = true;
    final revision = _playbackRevision;
    _completedLoops += 1;

    final allowedLoops = widget.loop ? _maxAutoLoops : 1;

    try {
      // Settle the player's own end-of-stream pause before seeking the repeat.
      await controller.pause();
      if (!mounted || revision != _playbackRevision || controller != _controller) {
        return;
      }
      if (_completedLoops >= allowedLoops) {
        await _stopTalkingCompletely(seekToEnd: true);
      } else {
        await controller.seekTo(Duration.zero);
        if (!mounted || revision != _playbackRevision || controller != _controller) {
          return;
        }
        await controller.play();
      }
    } finally {
      _handlingEnd = false;
    }
  }

  Future<void> _stopTalkingCompletely({bool seekToEnd = false}) async {
    ++_playbackRevision;
    _completedLoops = widget.loop ? _maxAutoLoops : 1;
    kKorlixSounds.setQuiet(_soundQuietOwner, false);
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
    if (!_soundOn) {
      await _replayWithSound();
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setVolume(0.0);
    } catch (_) {
      return;
    }
    kKorlixSounds.setQuiet(_soundQuietOwner, false);
    if (mounted) setState(() => _soundOn = false);
  }

  Future<void> _replayWithSound() async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    final revision = ++_playbackRevision;
    kKorlixSounds.setQuiet(_soundQuietOwner, true);
    try {
      // Seek while the old cycle is still exhausted to ignore stale end events.
      await controller.seekTo(Duration.zero);
      if (!mounted || revision != _playbackRevision || controller != _controller) {
        return;
      }
      _completedLoops = 0;
      await controller.setVolume(1.0);
      if (!mounted || revision != _playbackRevision || controller != _controller) {
        return;
      }
      await controller.play();
    } catch (_) {
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
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
    ++_playbackRevision;
    kKorlixSounds.setQuiet(_soundQuietOwner, false);
    kKorlixStopCharacterSpeechSignal.removeListener(_handleGlobalStopSignal);
    _controller?.removeListener(_handleVideoProgress);
    _releaseVideoGestures?.call();
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
              child: IconButton(enableFeedback: false,
                onPressed: korlixSoundAction(_toggleSound),
                icon: Icon(
                  _soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                ),
                color: const Color(0xFFE4EBEE),
                tooltip: _soundOn
                    ? 'Mute'
                    : _completedLoops >= _maxAutoLoops
                    ? 'Replay intro (2 plays)'
                    : 'Unmute',
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
  final KorlixAdConsent _consent = KorlixAdConsent.instance;
  BannerAd? _bannerAd;
  BannerAd? _pendingAd;
  bool _loaded = false;
  bool _preparing = false;
  bool _prepareAgain = false;
  bool _lastConsentReady = false;
  int _generation = 0;

  static const String _androidTestBannerAdUnit =
      'ca-app-pub-3940256099942544/6300978111';

  static const String _androidProductionBannerAdUnit =
      'ca-app-pub-1549134869666707/4852386901';

  bool get _mobileAdsSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String get _adUnitId =>
      kReleaseMode ? _androidProductionBannerAdUnit : _androidTestBannerAdUnit;

  @override
  void initState() {
    super.initState();
    _lastConsentReady = _consent.adsReady;
    _consent.addListener(_handleConsentChanged);
    kKorlixAuthRevision.addListener(_handleAccountChanged);
    kKorlixBillingRevision.addListener(_handleAccountChanged);
    unawaited(_prepareAd());
  }

  void _disposeAd(Ad ad) {
    unawaited(ad.dispose().catchError((Object _) {}));
  }

  void _invalidateAd() {
    _generation++;
    final pending = _pendingAd;
    final current = _bannerAd;
    _pendingAd = null;
    _bannerAd = null;
    _loaded = false;
    if (pending != null) _disposeAd(pending);
    if (current != null && !identical(current, pending)) _disposeAd(current);
    if (mounted) setState(() {});
  }

  void _handleAccountChanged() {
    _invalidateAd();
    _queuePreparation();
  }

  void _handleConsentChanged() {
    final ready = _consent.adsReady;
    if (ready == _lastConsentReady) return;
    _lastConsentReady = ready;
    if (!ready) {
      _invalidateAd();
    } else {
      _queuePreparation();
    }
  }

  void _queuePreparation() {
    if (!mounted) return;
    if (_preparing) {
      _prepareAgain = true;
    } else {
      unawaited(_prepareAd());
    }
  }

  Future<void> _prepareAd() async {
    if (!_mobileAdsSupported ||
        !mounted ||
        _preparing ||
        _pendingAd != null ||
        _bannerAd != null) {
      return;
    }
    final token = kKorlixAccessToken;
    if (token == null || token.isEmpty) return;
    final generation = _generation;
    final authRevision = kKorlixAuthRevision.value;
    final billingRevision = kKorlixBillingRevision.value;
    bool current() =>
        mounted &&
        generation == _generation &&
        authRevision == kKorlixAuthRevision.value &&
        billingRevision == kKorlixBillingRevision.value &&
        token == kKorlixAccessToken;

    _preparing = true;
    try {
      if (kKorlixDeviceId == null) {
        await KorlixDeviceStore.ensureLoaded().timeout(
          const Duration(seconds: 5),
        );
      }
      if (!current()) return;
      final response = await http
          .get(
            _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/me'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              ...KorlixDeviceStore.headers(),
            },
          )
          .timeout(const Duration(seconds: 15));
      if (!current() || response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>();
      // Missing account data must never be interpreted as eligibility for ads.
      if (profile?['tier'] != 'basic') return;
      if (!await _consent.prepareAds() || !current() || !_consent.adsReady) {
        return;
      }

      final ad = BannerAd(
        size: AdSize.banner,
        adUnitId: _adUnitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!current() ||
                !_consent.adsReady ||
                !identical(_pendingAd, ad)) {
              _disposeAd(ad);
              return;
            }
            setState(() {
              _pendingAd = null;
              _bannerAd = ad as BannerAd;
              _loaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            _disposeAd(ad);
            if (!mounted ||
                (!identical(_pendingAd, ad) && !identical(_bannerAd, ad))) {
              return;
            }
            setState(() {
              if (identical(_pendingAd, ad)) _pendingAd = null;
              if (identical(_bannerAd, ad)) _bannerAd = null;
              _loaded = false;
            });
          },
        ),
        request: const AdRequest(),
      );
      _pendingAd = ad;
      await ad.load();
    } catch (_) {
      // Ads should never block app usage or reveal SDK/network error details.
      if (current()) {
        final pending = _pendingAd;
        _pendingAd = null;
        if (pending != null) _disposeAd(pending);
      }
    } finally {
      _preparing = false;
      if (_prepareAgain && mounted) {
        _prepareAgain = false;
        unawaited(_prepareAd());
      }
    }
  }

  @override
  void dispose() {
    _consent.removeListener(_handleConsentChanged);
    kKorlixAuthRevision.removeListener(_handleAccountChanged);
    kKorlixBillingRevision.removeListener(_handleAccountChanged);
    _generation++;
    final pending = _pendingAd;
    final current = _bannerAd;
    if (pending != null) _disposeAd(pending);
    if (current != null && !identical(current, pending)) _disposeAd(current);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mobileAdsSupported ||
        !_consent.adsReady ||
        !_loaded ||
        _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Advertisement',
      child: Container(
        width: double.infinity,
        height: _bannerAd!.size.height.toDouble() + 12,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          border: Border(
            top: BorderSide(color: const Color(0xFF2EC7DF).withValues(alpha: 0.25)),
          ),
        ),
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
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
  // First play plus one repeat, then mute and hold the final frame.
  static const int _maxAutoLoops = 2;

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

    if (!value.isInitialized || (!value.isPlaying && !value.isCompleted)) {
      return;
    }

    final duration = value.duration;

    if (duration == Duration.zero) {
      return;
    }

    // Use the actual completion signal; do not cut off the final words.
    if (value.isCompleted || value.position >= duration) {
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
      await _controller.pause();
      if (!mounted) return;
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

class _KorlixSoundSettingsButton extends StatelessWidget {
  const _KorlixSoundSettingsButton();
  @override
  Widget build(BuildContext context) => IconButton(enableFeedback: false,
    key: const Key('korlix-open-sounds'),
    tooltip: 'Sounds & Alerts',
    icon: const Icon(Icons.volume_up_outlined, color: Color(0xFF69D9E8)),
    onPressed: korlixSoundAction(() => Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => const KorlixSoundSettingsScreen(),
    ))),
  );
}

class KorlixAccountButton extends StatefulWidget {
  const KorlixAccountButton({super.key});

  @override
  State<KorlixAccountButton> createState() => _KorlixAccountButtonState();
}

class _KorlixAccountButtonState extends State<KorlixAccountButton> {
  bool _loading = false;
  bool _deletionRequestBusy = false;
  bool _historyReportBusy = false;

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
                    onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
                    style: korlixSoundButtonStyle(FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF143B4A),
                      foregroundColor: const Color(0xFFE4EBEE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )),
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
    required String outputSummary,
  }) async {
    if (!mounted || _historyReportBusy) return;
    final revision = kKorlixAuthRevision.value;
    final token = kKorlixAccessToken;
    if (token == null || token.isEmpty) {
      await _showKorlixNotice(
        title: 'Sign in required',
        message: 'Sign in to report this saved output.',
      );
      return;
    }
    final headers = Map<String, String>.from(_headers());
    bool current() => mounted && revision == kKorlixAuthRevision.value &&
        token == kKorlixAccessToken;
    _historyReportBusy = true;
    try {
      final reportId = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => KorlixSavedOutputReportDialog(
          sessionChanges: kKorlixAuthRevision,
          isSessionCurrent: current,
          submitReport: (reason, details) {
            if (!current()) throw StateError('Sign-in changed.');
            return submitKorlixAiReport(
              endpoint: _assertValidKorlixBackendUri(
                '$kKorlixBackendBaseUrl/api/report-output',
              ),
              headers: headers,
              contentId: generationId,
              prompt: prompt,
              outputSummary: outputSummary,
              reason: reason,
              details: details,
            );
          },
        ),
      );
      if (reportId == null || !current()) return;
      await _showKorlixNotice(
        title: 'Report received',
        message: 'Your report was saved for review. Reference: $reportId',
      );
    } finally {
      _historyReportBusy = false;
    }
  }


  // KORLIX_SAVED_SETTINGS_DELETE_BUILD131_V1_BEGIN

  Map<String, dynamic> _savedSettingsResponseJson(http.Response response) {
    final body = response.body.trim();

    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(body);

    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }

    return <String, dynamic>{};
  }

  Future<bool> _confirmSavedSettingsDeletion({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    if (!mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071B27),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE4EBEE),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFA9C6CF),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop(false)),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop(true)),
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(confirmLabel),
              style: korlixSoundButtonStyle(FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              )),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _deleteSavedHistoryById(String historyId) async {
    final id = historyId.trim();

    if (id.isEmpty) {
      throw Exception('This saved generation has no valid record ID.');
    }

    final response = await http
        .delete(
          _assertValidKorlixBackendUri(
            '$kKorlixBackendBaseUrl/api/history/${Uri.encodeComponent(id)}',
          ),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 20));

    final data = _savedSettingsResponseJson(response);

    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Could not delete the saved generation.');
    }
  }

  Future<List<Map<String, dynamic>>> _loadSavedHistoryBatch() async {
    final response = await http
        .get(
          _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/history'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 20));

    final data = _savedSettingsResponseJson(response);

    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Could not refresh Saved Settings.');
    }

    final rawHistory = data['history'];

    if (rawHistory is! List) {
      return const <Map<String, dynamic>>[];
    }

    return rawHistory
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<bool> _deleteSavedHistoryItem({
    required String historyId,
    required String prompt,
  }) async {
    final confirmed = await _confirmSavedSettingsDeletion(
      title: 'Delete saved generation?',
      message:
          'Delete this Saved Settings record permanently? This cannot be '
          'undone. Any copy already downloaded to your device will remain '
          'on that device.\n\n${prompt.trim().isEmpty ? 'Saved generation' : prompt.trim()}',
      confirmLabel: 'Delete',
    );

    if (!confirmed) {
      return false;
    }

    try {
      await _deleteSavedHistoryById(historyId);
      return true;
    } catch (error) {
      await _showKorlixNotice(
        title: 'Delete failed',
        message: _cleanError(error),
        danger: true,
      );
      return false;
    }
  }

  Future<int?> _deleteAllSavedHistoryItems({required int loadedCount}) async {
    final confirmed = await _confirmSavedSettingsDeletion(
      title: 'Delete all Saved Settings?',
      message:
          'Permanently delete every saved generation associated with your '
          'signed-in KORLIX account${loadedCount > 0 ? ' ($loadedCount currently loaded)' : ''}? '
          'This cannot be undone. Files already downloaded to your device '
          'will not be removed.',
      confirmLabel: 'Delete All',
    );

    if (!confirmed) {
      return null;
    }

    var deletedCount = 0;

    try {
      while (true) {
        final rows = await _loadSavedHistoryBatch();

        if (rows.isEmpty) {
          break;
        }

        final ids = rows
            .map((row) => (row['id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toList(growable: false);

        if (ids.isEmpty) {
          throw Exception(
            'KORLIX could not identify the remaining Saved Settings records.',
          );
        }

        for (final id in ids) {
          await _deleteSavedHistoryById(id);
          deletedCount += 1;
        }

        if (deletedCount > 10000) {
          throw Exception(
            'The Saved Settings deletion safety limit was reached. Please '
            'contact KORLIX support before trying again.',
          );
        }
      }

      return deletedCount;
    } catch (error) {
      await _showKorlixNotice(
        title: 'Delete All failed',
        message: _cleanError(error),
        danger: true,
      );
      return null;
    }
  }

  // KORLIX_SAVED_SETTINGS_DELETE_BUILD131_V1_END

  // KORLIX_BRAIN_VAULT_SECURITY_SETTINGS_UI_BUILD131_V1_BEGIN

  bool _brainVaultSecurityBool(Object? value) {
    if (value is bool) {
      return value;
    }

    return value?.toString().trim().toLowerCase() == 'true';
  }

  int _brainVaultSecurityInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _brainVaultSecurityDate(Object? value) {
    final raw = value?.toString().trim() ?? '';

    if (raw.isEmpty) {
      return 'Not available';
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed == null) {
      return raw;
    }

    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '${local.year}-$month-$day $hour:$minute';
  }

  Future<Map<String, dynamic>> _brainVaultSecurityRequest({
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl$path');
    final response = body == null
        ? await http
              .get(uri, headers: _headers())
              .timeout(const Duration(seconds: 25))
        : await http
              .post(
                uri,
                headers: _headers(),
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 25));
    final data = _savedSettingsResponseJson(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['error'] ?? 'Could not update BRAIN VAULT security.',
      );
    }

    return data;
  }

  Future<bool> _openBrainVaultCredentialDialog({
    required String mode,
  }) async {
    final isSet = mode == 'set';
    final isChange = mode == 'change';
    final isReset = mode == 'reset';

    if (!isSet && !isChange && !isReset) {
      throw ArgumentError.value(mode, 'mode', 'Unsupported BRAIN VAULT action');
    }

    final accountPasswordController = TextEditingController();
    final currentVaultPasswordController = TextEditingController();
    final newVaultPasswordController = TextEditingController();
    final confirmationController = TextEditingController();
    var working = false;
    var obscurePasswords = true;
    String? errorText;

    final title = isSet
        ? 'Set BRAIN VAULT Password'
        : isChange
        ? 'Change BRAIN VAULT Password'
        : 'Reset BRAIN VAULT Password';
    final actionLabel = isSet
        ? 'Set Password'
        : isChange
        ? 'Change Password'
        : 'Reset Password';

    try {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (statefulDialogContext, setDialogState) {
              Widget passwordField({
                required TextEditingController controller,
                required String label,
                required TextInputAction textInputAction,
                VoidCallback? onSubmitted,
              }) {
                return TextField(
                  controller: controller,
                  enabled: !working,
                  obscureText: obscurePasswords,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: textInputAction,
                  autofillHints: const <String>[],
                  style: const TextStyle(color: Color(0xFFF0F7F8)),
                  onChanged: (_) {
                    if (errorText == null) {
                      return;
                    }

                    setDialogState(() {
                      errorText = null;
                    });
                  },
                  onSubmitted: onSubmitted == null
                      ? null
                      : (_) {
                          onSubmitted();
                        },
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: const Icon(Icons.password_rounded),
                  ),
                );
              }

              Future<void> submit() async {
                if (working) {
                  return;
                }

                final accountPassword = accountPasswordController.text;
                final currentVaultPassword =
                    currentVaultPasswordController.text;
                final newVaultPassword = newVaultPasswordController.text;
                final confirmation = confirmationController.text;
                String? validationError;

                if (accountPassword.isEmpty) {
                  validationError = 'Enter the current KORLIX login password.';
                } else if (isChange &&
                    (currentVaultPassword.length < 12 ||
                        currentVaultPassword.length > 128)) {
                  validationError =
                      'Enter the current 12 to 128 character BRAIN VAULT password.';
                } else if (newVaultPassword.length < 12 ||
                    newVaultPassword.length > 128) {
                  validationError =
                      'The new BRAIN VAULT password must contain 12 to 128 characters.';
                } else if (newVaultPassword != confirmation) {
                  validationError = 'The BRAIN VAULT passwords do not match.';
                } else if (newVaultPassword == accountPassword) {
                  validationError =
                      'The BRAIN VAULT password must differ from the KORLIX login password.';
                }

                if (validationError != null) {
                  setDialogState(() {
                    errorText = validationError;
                  });
                  return;
                }

                setDialogState(() {
                  working = true;
                  errorText = null;
                });

                try {
                  final path = isSet
                      ? '/api/brain-vault/password/set'
                      : isChange
                      ? '/api/brain-vault/password/change'
                      : '/api/brain-vault/password/reset';
                  final body = isSet
                      ? <String, dynamic>{
                          'accountPassword': accountPassword,
                          'vaultPassword': newVaultPassword,
                          'confirmVaultPassword': confirmation,
                        }
                      : isChange
                      ? <String, dynamic>{
                          'accountPassword': accountPassword,
                          'currentVaultPassword': currentVaultPassword,
                          'newVaultPassword': newVaultPassword,
                          'confirmVaultPassword': confirmation,
                        }
                      : <String, dynamic>{
                          'accountPassword': accountPassword,
                          'newVaultPassword': newVaultPassword,
                          'confirmVaultPassword': confirmation,
                        };

                  await _brainVaultSecurityRequest(path: path, body: body);

                  accountPasswordController.clear();
                  currentVaultPasswordController.clear();
                  newVaultPasswordController.clear();
                  confirmationController.clear();

                  if (!mounted || !statefulDialogContext.mounted) {
                    return;
                  }

                  Navigator.of(statefulDialogContext).pop(true);
                } catch (error) {
                  accountPasswordController.clear();
                  currentVaultPasswordController.clear();
                  newVaultPasswordController.clear();
                  confirmationController.clear();

                  if (!mounted || !statefulDialogContext.mounted) {
                    return;
                  }

                  setDialogState(() {
                    working = false;
                    errorText = _cleanError(error);
                  });
                }
              }

              return AlertDialog(
                backgroundColor: const Color(0xFF071722),
                title: Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Color(0xFFB794F4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFF0F7F8),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Only the authenticated Account Manager may manage this '
                          'credential. The BRAIN VAULT password is separate from '
                          'the KORLIX login password and is never stored in an '
                          'agent brain or export.',
                          style: TextStyle(
                            color: Color(0xFFD8E7EA),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        passwordField(
                          controller: accountPasswordController,
                          label: 'Current KORLIX login password',
                          textInputAction: TextInputAction.next,
                        ),
                        if (isChange) ...[
                          const SizedBox(height: 12),
                          passwordField(
                            controller: currentVaultPasswordController,
                            label: 'Current BRAIN VAULT password',
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                        const SizedBox(height: 12),
                        passwordField(
                          controller: newVaultPasswordController,
                          label: isSet
                              ? 'New BRAIN VAULT password'
                              : 'New BRAIN VAULT password',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        passwordField(
                          controller: confirmationController,
                          label: 'Confirm BRAIN VAULT password',
                          textInputAction: TextInputAction.done,
                          onSubmitted: () {
                            unawaited(submit());
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: !obscurePasswords,
                              onChanged: working
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        obscurePasswords = value != true;
                                      });
                                    },
                            ),
                            const Expanded(
                              child: Text(
                                'Show passwords',
                                style: TextStyle(color: Color(0xFFC7D7DC)),
                              ),
                            ),
                          ],
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (working) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(
                            minHeight: 3,
                            color: Color(0xFFB794F4),
                            backgroundColor: Color(0xFF243240),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(style: korlixSoundButtonStyle(null),
                    onPressed: korlixSoundAction(working
                        ? null
                        : () {
                            Navigator.of(statefulDialogContext).pop(false);
                          }),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: korlixSoundAction(working
                        ? null
                        : () {
                            unawaited(submit());
                          }),
                    style: korlixSoundButtonStyle(FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB794F4),
                      foregroundColor: const Color(0xFF160A22),
                    )),
                    icon: working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF160A22),
                            ),
                          )
                        : const Icon(Icons.verified_user_rounded),
                    label: Text(
                      actionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      return completed == true;
    } finally {
      accountPasswordController.clear();
      currentVaultPasswordController.clear();
      newVaultPasswordController.clear();
      confirmationController.clear();
      accountPasswordController.dispose();
      currentVaultPasswordController.dispose();
      newVaultPasswordController.dispose();
      confirmationController.dispose();
    }
  }

  Future<void> _openBrainVaultSecuritySettings() async {
    late final Map<String, dynamic> status;

    try {
      status = await _brainVaultSecurityRequest(
        path: '/api/brain-vault/security-status',
      );
    } catch (error) {
      await _showKorlixNotice(
        title: 'BRAIN VAULT Security unavailable',
        message: _cleanError(error),
        danger: true,
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final configured = _brainVaultSecurityBool(status['configured']);
    final canManage = _brainVaultSecurityBool(status['canManage']);
    final passwordVersion = _brainVaultSecurityInt(status['passwordVersion']);
    final failedAttemptCount = _brainVaultSecurityInt(
      status['failedAttemptCount'],
    );
    final lockedUntilRaw = status['lockedUntil']?.toString().trim() ?? '';
    final lockedUntil = DateTime.tryParse(lockedUntilRaw);
    final currentlyLocked = lockedUntil != null &&
        lockedUntil.toUtc().isAfter(DateTime.now().toUtc());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xCC02070C),
      builder: (sheetContext) {
        Future<void> runAction(String mode) async {
          final completed = await _openBrainVaultCredentialDialog(mode: mode);

          if (!mounted || !sheetContext.mounted || !completed) {
            return;
          }

          Navigator.of(sheetContext).pop();

          await _showKorlixNotice(
            title: 'BRAIN VAULT Security updated',
            message: mode == 'set'
                ? 'The separate Account Manager BRAIN VAULT password is now configured.'
                : mode == 'change'
                ? 'The BRAIN VAULT password was changed successfully.'
                : 'The BRAIN VAULT password was reset successfully.',
          );
        }

        return Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
              ),
              margin: const EdgeInsets.only(top: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF041019),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 34,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: const Color(0xFFB794F4).withValues(alpha: 0.14),
                            border: Border.all(
                              color: const Color(0xFFB794F4).withValues(alpha: 0.58),
                            ),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Color(0xFFDFC9FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BRAIN VAULT Security',
                                style: TextStyle(
                                  color: Color(0xFFF0F7F8),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Account Manager controls',
                                style: TextStyle(
                                  color: Color(0xFFB794F4),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(enableFeedback: false,
                          tooltip: 'Close BRAIN VAULT Security',
                          onPressed: korlixSoundAction(() {
                            Navigator.of(sheetContext).pop();
                          }),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFC7D7DC),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: const Color(0xFF081B25),
                        border: Border.all(color: const Color(0xFF2B5360)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                configured
                                    ? Icons.verified_user_rounded
                                    : Icons.gpp_maybe_rounded,
                                color: configured
                                    ? const Color(0xFF62D6A7)
                                    : const Color(0xFFFFC566),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  configured
                                      ? 'Separate password configured'
                                      : 'Password setup required',
                                  style: TextStyle(
                                    color: configured
                                        ? const Color(0xFF62D6A7)
                                        : const Color(0xFFFFC566),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'This credential is different from the KORLIX login '
                            'password. It is controlled by the authenticated '
                            'Account Manager and protects BRAIN VAULT access on '
                            'web, iOS, and Android.',
                            style: TextStyle(
                              color: Color(0xFFD8E7EA),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: const Color(0xFF06151E),
                        border: Border.all(color: const Color(0xFF1F3D49)),
                      ),
                      child: Column(
                        children: [
                          _brainVaultSecurityStatusRow(
                            label: 'Manager',
                            value: canManage ? 'Account Owner' : 'Unavailable',
                          ),
                          _brainVaultSecurityStatusRow(
                            label: 'Password version',
                            value: configured ? '$passwordVersion' : 'Not set',
                          ),
                          _brainVaultSecurityStatusRow(
                            label: 'Changed',
                            value: _brainVaultSecurityDate(
                              status['passwordChangedAt'],
                            ),
                          ),
                          _brainVaultSecurityStatusRow(
                            label: 'Failed attempts',
                            value: '$failedAttemptCount',
                          ),
                          _brainVaultSecurityStatusRow(
                            label: 'Lock status',
                            value: currentlyLocked
                                ? 'Locked until ${_brainVaultSecurityDate(lockedUntilRaw)}'
                                : 'Available',
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!configured)
                      FilledButton.icon(
                        onPressed: korlixSoundAction(canManage
                            ? () {
                                unawaited(runAction('set'));
                              }
                            : null),
                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: const Color(0xFFB794F4),
                          foregroundColor: const Color(0xFF160A22),
                        )),
                        icon: const Icon(Icons.add_moderator_rounded),
                        label: const Text(
                          'Set BRAIN VAULT Password',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      )
                    else ...[
                      FilledButton.icon(
                        onPressed: korlixSoundAction(canManage
                            ? () {
                                unawaited(runAction('change'));
                              }
                            : null),
                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: const Color(0xFFB794F4),
                          foregroundColor: const Color(0xFF160A22),
                        )),
                        icon: const Icon(Icons.password_rounded),
                        label: const Text(
                          'Change BRAIN VAULT Password',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: korlixSoundAction(canManage
                            ? () {
                                unawaited(runAction('reset'));
                              }
                            : null),
                        style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: const Color(0xFFFFC566),
                          side: const BorderSide(color: Color(0xFFFFC566)),
                        )),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text(
                          'Reset with KORLIX Login Password',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Security note: five incorrect BRAIN VAULT attempts lock '
                      'verification for 15 minutes. Passwords are submitted only '
                      'to the authenticated KORLIX security routes and are not '
                      'placed in Saved Settings, exports, billing, or AI GAS.',
                      style: TextStyle(
                        color: Color(0xFFA9C6CF),
                        height: 1.4,
                        fontSize: 12.5,
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
  }

  Widget _brainVaultSecurityStatusRow({
    required String label,
    required String value,
    bool last = false,
  }) {
    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 10, top: last ? 10 : 0),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF17303A)),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA9C6CF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFF0F7F8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // KORLIX_BRAIN_VAULT_SECURITY_SETTINGS_UI_BUILD131_V1_END

  Future<void> _openLegalPrivacy() async {
    if (!mounted) return;
    final revision = kKorlixAuthRevision.value;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => KorlixPrivacySettings(
          sessionChanges: kKorlixAuthRevision,
          isSessionCurrent: () => mounted &&
              revision == kKorlixAuthRevision.value &&
              (kKorlixAccessToken?.isNotEmpty ?? false),
        ),
      ),
    );
  }

  Future<void> _requestAccountDeletion() async {
    if (!mounted || _deletionRequestBusy) return;
    final revision = kKorlixAuthRevision.value;
    final token = kKorlixAccessToken;
    if (token == null || token.isEmpty) {
      await _showKorlixNotice(
        title: 'Sign in required',
        message: 'Sign in to the account you want to request deletion for.',
      );
      return;
    }
    final headers = Map<String, String>.from(_headers());
    bool current() => mounted && revision == kKorlixAuthRevision.value &&
        token == kKorlixAccessToken;
    _deletionRequestBusy = true;
    try {
      final recorded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => KorlixAccountDeletionDialog(
          sessionChanges: kKorlixAuthRevision,
          isSessionCurrent: current,
          showAppleSubscriptions: !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.iOS,
          submitRequest: () async {
            if (!current()) return;
            final response = await http.post(
              _assertValidKorlixBackendUri(
                '$kKorlixBackendBaseUrl/api/account/delete-request',
              ),
              headers: headers,
              body: jsonEncode({
                'reason': 'User requested account deletion from Korlix Account panel.',
              }),
            ).timeout(const Duration(seconds: 15));
            if (!current()) return;
            final data = jsonDecode(response.body);
            if (response.statusCode < 200 || response.statusCode >= 300 ||
                data is! Map || data['success'] != true) {
              throw StateError('Deletion request was not confirmed.');
            }
          },
        ),
      );
      if (recorded != true || !current()) return;
      await _showKorlixNotice(
        title: 'Deletion request recorded',
        message: 'Your request has been recorded for review. Your account has '
            'not been deleted yet. Account deletion does not automatically '
            'cancel recurring subscriptions.',
      );
    } finally {
      _deletionRequestBusy = false;
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

  // KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_PLANS_BEGIN
  Future<void> _handleAppleSubscriptionTierChanged(String _) async {
    if (!mounted) return;
    kKorlixBillingRevision.value++;
  }

  Future<void> _openPlansPanel({required String currentTier}) async {
    if (kIsWeb) {
      await showKorlixWebBilling(context, baseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _headers, sessionChanges: kKorlixAuthRevision,
        onTierChanged: _handleAppleSubscriptionTierChanged);
      return;
    }
    await showKorlixAppleSubscriptionSheet(
      context: context,
      backendBaseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _headers,
      sessionChanges: kKorlixAuthRevision,
      currentTier: currentTier,
      onTierChanged: _handleAppleSubscriptionTierChanged,
    );
  }
  // KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_PLANS_END

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

  String? _characterIntroAsset(String id) {
    final normalized = normalizeKorlixCharacterId(id);
    for (final character in korlixCharacters) {
      if (character.id == normalized) return character.video;
    }
    return null;
  }

  Future<bool> _selectCharacter(String characterId) async {
    final normalizedCharacterId = normalizeKorlixCharacterId(characterId);
    final authRevision = kKorlixAuthRevision.value;

    try {
      final response = await http.post(
        _assertValidKorlixBackendUri(
          '$kKorlixBackendBaseUrl/api/characters/select',
        ),
        headers: _headers(),
        body: jsonEncode({'character_id': normalizedCharacterId}),
      );

      if (!mounted || authRevision != kKorlixAuthRevision.value) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        await _showKorlixNotice(
          title: 'Character update failed',
          message: data['error']?.toString() ?? 'Could not save your character. Try again.',
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
    required List<dynamic> characters,
  }) async {
    var selectedId = kKorlixSelectedCharacterNotifier.value;
    var savingCharacter = false;

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
                        'Every available character is included on every plan. Tap Select, or spin the character orbit on your home screen.',
                        style: TextStyle(
                          color: Color(0xFFA9C6CF),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ...characters.whereType<Map>().where((c) => c['is_active'] == true && c['is_coming_soon'] != true).map((raw) {
                        final character = (raw as Map).cast<String, dynamic>();
                        final rawId = character['id']?.toString() ?? '';
                        final id = normalizeKorlixCharacterId(rawId);
                        final name =
                            character['name']?.toString() ?? 'Korlix Character';
                        final description =
                            character['description']?.toString() ?? '';
                        final isActive = character['is_active'] == true;
                        final comingSoon = character['is_coming_soon'] == true;
                        final selected =
                            normalizeKorlixCharacterId(id) ==
                            normalizeKorlixCharacterId(selectedId);
                        final available = isActive && !comingSoon;
                        final accent = korlixCharacterFor(id).color;
                        final videoAsset = _characterIntroAsset(id);

                        String status;

                        if (selected) {
                          status = 'Selected';
                        } else if (comingSoon) {
                          status = 'Coming soon';
                        } else if (available) {
                          status = 'Available';
                        } else {
                          status = 'Unavailable';
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
                                      'Included on every plan',
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
                                        onPressed: korlixSoundAction(selected || !available || savingCharacter
                                            ? null
                                            : () async {
                                                setModalState(() => savingCharacter = true);
                                                final success = await _selectCharacter(id);
                                                if (!context.mounted) return;
                                                setModalState(() {
                                                  savingCharacter = false;
                                                  if (success) selectedId = id;
                                                });
                                              }),
                                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
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
                                        )),
                                        child: Text(
                                          selected
                                              ? 'Selected'
                                              : comingSoon
                                              ? 'Coming soon'
                                              : available
                                              ? 'Select'
                                              : 'Unavailable',
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

  Future<void> _setTheme({required String theme, String? screenSkin}) async {
    final previous = kKorlixThemeNotifier.value;
    final choice = KorlixAppearanceChoice(theme, screenSkin ?? kKorlixScreenSkinNotifier.value);
    final saving = kKorlixAppearancePreferences.apply(choice);
    if (mounted) {
      setState(() {});
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('${korlixThemeLabelFor(choice.themeId)} · ${korlixScreenSkinLabel(choice.skinId)} applied')));
    }
    final saved = await saving;
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Look applied for this session. Device storage could not save it.')));
    }
    // New looks are stored on this device. Retain the existing remote sync only
    // for IDs accepted by the current backend, without changing account policy.
    const remoteThemes = {'korlix_blue', 'matrix_green', 'ultra_gold', 'dark_crimson'};
    if (previous == choice.themeId || !remoteThemes.contains(choice.themeId) || kKorlixThemeNotifier.value != choice.themeId) return;
    try {
      await http.post(_assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/theme/set'),
        headers: KorlixDeviceStore.headers(), body: jsonEncode({'theme': choice.themeId}))
        .timeout(const Duration(seconds: 10));
    } catch (_) { /* The saved local appearance remains usable while offline. */ }
  }

  Future<void> _openThemePanel({required String currentTheme, String? currentTier}) async {
    final selected = await showKorlixAppearancePicker(context);
    if (selected != null && mounted) await _setTheme(theme: selected.themeId, screenSkin: selected.skinId);
  }

  Future<void> _openAdPrivacyOptions() async {
    final revision = kKorlixAuthRevision.value;
    final shown = await KorlixAdConsent.instance.showPrivacyOptions();
    if (!shown && mounted && revision == kKorlixAuthRevision.value) {
      await _showKorlixNotice(
        title: 'Ad privacy options unavailable',
        message: 'Your ad privacy options could not open. Please try again.',
      );
    }
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
      final history = List<dynamic>.from(
        (historyData['history'] as List?) ?? const <dynamic>[],
      );
      final characters = (meData['characters'] as List?) ?? [];
      var historyDeleteBusy = false;

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
          return StatefulBuilder(
            builder: (context, setPanelState) {
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
                      onPressed: korlixSoundAction(() {
                        if (kIsWeb) Navigator.of(context).pop();
                        unawaited(_openPlansPanel(currentTier: tier));
                      }),
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text(kIsWeb ? 'Plans & Billing' : 'View plans / upgrade'),
                      style: korlixSoundButtonStyle(FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF143B4A),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      )),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: korlixSoundAction(() => _openCharactersPanel(
                        characters: characters,
                      )),
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('View characters'),
                      style: korlixSoundButtonStyle(FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0A2B3D),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      )),
                    ),

                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: korlixSoundAction(_openComingSoonPanel),
                      icon: const Icon(Icons.upcoming_rounded),
                      label: const Text('Coming Soon'),
                      style: korlixSoundButtonStyle(FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF143B4A),
                        foregroundColor: const Color(0xFFE4EBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      )),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: korlixSoundAction(() => _openThemePanel(
                        currentTier: tier,
                        currentTheme:
                            (profile['preferred_theme'] ?? 'korlix_blue')
                                .toString(),
                      )),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Themes & Screen Skins'),
                      style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
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
                      )),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: korlixSoundAction(() => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(builder: (_) => const KorlixSoundSettingsScreen()),
                      )),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Sounds & Alerts'),
                      style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF69D9E8),
                        side: const BorderSide(color: Color(0xFF69D9E8)),
                      )),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('korlix-send-app-feedback'),
                      onPressed: korlixSoundAction(() => showKorlixAppFeedbackDialog(
                        context,
                        baseUrl: kKorlixBackendBaseUrl,
                        headersBuilder: _headers,
                        sessionChanges: kKorlixAuthRevision,
                      )),
                      icon: const Icon(Icons.feedback_outlined),
                      label: const Text('Send app feedback'),
                    ),
                    const SizedBox(height: 10),
                    ListenableBuilder(
                      listenable: KorlixAdConsent.instance,
                      builder: (context, _) {
                        final consent = KorlixAdConsent.instance;
                        if (!consent.privacyOptionsRequired) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: OutlinedButton.icon(
                            key: const Key('korlix-ad-privacy-options'),
                            onPressed: korlixSoundAction(consent.privacyOptionsShowing
                                ? null : _openAdPrivacyOptions),
                            icon: const Icon(Icons.privacy_tip_outlined),
                            label: const Text('Ad privacy options'),
                            style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF69D9E8),
                              side: const BorderSide(color: Color(0xFF69D9E8)),
                            )),
                          ),
                        );
                      },
                    ),
                    // KORLIX_BRAIN_VAULT_ACCOUNT_MANAGER_SETTINGS_BUILD131_V1_BEGIN
                    OutlinedButton.icon(
                      onPressed: korlixSoundAction(_openBrainVaultSecuritySettings),
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                      label: const Text('BRAIN VAULT Security'),
                      style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDFC9FF),
                        side: BorderSide(
                          color: const Color(0xFFB794F4).withValues(alpha: 0.68),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      )),
                    ),
                    // KORLIX_BRAIN_VAULT_ACCOUNT_MANAGER_SETTINGS_BUILD131_V1_END
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('account-legal-privacy'),
                      onPressed: korlixSoundAction(_openLegalPrivacy),
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('Legal & Privacy'),
                      style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF69D9E8),
                        side: const BorderSide(color: Color(0xFF69D9E8)),
                      )),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: korlixSoundAction(_requestAccountDeletion),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('Request account deletion'),
                      style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(
                          color: Colors.redAccent.withOpacity(0.55),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      )),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Saved Settings',
                            style: TextStyle(
                              color: Color(0xFFE4EBEE),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (history.isNotEmpty)
                          TextButton.icon(
                            onPressed: korlixSoundAction(historyDeleteBusy
                                ? null
                                : () async {
                                    setPanelState(() {
                                      historyDeleteBusy = true;
                                    });

                                    try {
                                      final deletedCount =
                                          await _deleteAllSavedHistoryItems(
                                            loadedCount: history.length,
                                          );

                                      if (deletedCount == null ||
                                          !context.mounted) {
                                        return;
                                      }

                                      setPanelState(() {
                                        history.clear();
                                      });

                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              deletedCount == 1
                                                  ? '1 saved generation deleted.'
                                                  : '$deletedCount saved generations deleted.',
                                            ),
                                          ),
                                        );
                                    } finally {
                                      if (context.mounted) {
                                        setPanelState(() {
                                          historyDeleteBusy = false;
                                        });
                                      }
                                    }
                                  }),
                            icon: historyDeleteBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_sweep_rounded),
                            label: Text(
                              historyDeleteBusy ? 'Deleting…' : 'Delete All',
                            ),
                            style: korlixSoundButtonStyle(TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                            )),
                          ),
                      ],
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
                        final historyId = (row['id'] ?? '').toString().trim();
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
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: korlixSoundAction(() => _reportHistoryItem(
                                      generationId: historyId,
                                      prompt: prompt,
                                      outputSummary: response,
                                    )),
                                    icon: const Icon(
                                      Icons.flag_outlined,
                                      size: 17,
                                    ),
                                    label: const Text('Report Output'),
                                    style: korlixSoundButtonStyle(TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF69D9E8),
                                      padding: EdgeInsets.zero,
                                    )),
                                  ),
                                  const Spacer(),
                                  IconButton(enableFeedback: false,
                                    tooltip: 'Delete saved generation',
                                    onPressed:
                                        korlixSoundAction(historyDeleteBusy || historyId.isEmpty
                                        ? null
                                        : () async {
                                            setPanelState(() {
                                              historyDeleteBusy = true;
                                            });

                                            try {
                                              final deleted =
                                                  await _deleteSavedHistoryItem(
                                                    historyId: historyId,
                                                    prompt: prompt,
                                                  );

                                              if (!deleted ||
                                                  !context.mounted) {
                                                return;
                                              }

                                              setPanelState(() {
                                                history.removeWhere((candidate) {
                                                  if (candidate is! Map) {
                                                    return false;
                                                  }

                                                  return (candidate['id'] ?? '')
                                                          .toString()
                                                          .trim() ==
                                                      historyId;
                                                });
                                              });

                                              ScaffoldMessenger.of(context)
                                                ..hideCurrentSnackBar()
                                                ..showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Saved generation deleted.',
                                                    ),
                                                  ),
                                                );
                                            } finally {
                                              if (context.mounted) {
                                                setPanelState(() {
                                                  historyDeleteBusy = false;
                                                });
                                              }
                                            }
                                          }),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    color: Colors.redAccent,
                                  ),
                                ],
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
    if (MediaQuery.sizeOf(context).width < 460 &&
        MediaQuery.textScalerOf(context).scale(14) > 18) {
      return IconButton(
        tooltip: 'Settings',
        enableFeedback: false,
        onPressed: korlixSoundAction(_loading ? null : _openPanel),
        icon: _loading
            ? const SizedBox(width: 17, height: 17,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.settings_rounded, color: Color(0xFFE4EBEE)),
      );
    }
    return TextButton.icon(
      onPressed: korlixSoundAction(_loading ? null : _openPanel),
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
      style: korlixSoundButtonStyle(TextButton.styleFrom(
        foregroundColor: const Color(0xFFE4EBEE),
        backgroundColor: Colors.black.withOpacity(0.32),
      )),
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

final ValueNotifier<String> kKorlixSelectedCharacterNotifier =
    ValueNotifier<String>('jj');

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
              'Open Resume Studio to build, tailor, and export a resume.',
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
        QuickAction(label: 'Crear mi currículum', prompt: 'Open Resume Studio.'),
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
              'Open Resume Studio to build, tailor, and export a resume.',
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
  bool get _canShowReviewPrompt {
    final alerts = SocialAlertScope.maybeOf(context);
    return mounted && ModalRoute.of(context)?.isCurrent == true &&
        !_loading && !_voiceListening && !_uploadOpening &&
        !_voiceComposerOpening && !_resumePendingGenerationJobsRunning &&
        !_aiOutputReportBusy && !_socialOpening && !_contactsOpening &&
        !_toolFinderOpening && !_loadingTier &&
        _controller.text.trim().isEmpty && _savedTopicsOverlayEntry == null &&
        _wizardCuePlayer.state != PlayerState.playing &&
        alerts?.calls?.current == null &&
        alerts?.notifications.incomingCall == null;
  }
  late final ChatMemoryClient _chatMemory;
  SocialNotifications get _socialNotifications =>
      SocialAlertScope.maybeOf(context)!.notifications;
  bool _socialOpening = false;
  bool _contactsOpening = false;
  bool _toolFinderOpening = false;
  bool _aiOutputReportBusy = false;
  final _commandPanelKey = GlobalKey();
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
  late final CharacterSelectionController _characters;
  bool _featuredAnswerDismissed = false;
  bool _createVideoMode = false;
  bool _improvePictureMode = false;
  String? _portraitStudioPromptOverride;
  bool _imaginePictureMode = false;
  String _chatImageSize = '1024x1024';
  String _chatImageStyle = 'auto';
  ImagineClient? _imagineStudio;
  bool _imagineStudioOpening = false;
  bool _improvePictureStudioOpening = false;
  bool _logoStudioOpening = false;
  bool _emailEnhancerOpening = false;
  bool _textWorkspaceOpening = false;
  String _pendingChatPrompt = '';
  bool _pendingChatIsImage = false;
  String? _pendingChatTopicId;
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
  bool _uploadOpening = false;
  bool _voiceComposerOpening = false;
  fp.PlatformFile? _pickedUploadFile;
  final List<fp.PlatformFile> _pickedUploadFiles = <fp.PlatformFile>[];
  bool _loadingTier = false;
  String _currentTier = 'basic';
  String? _error;
  String _selectedLanguage = 'en';

  final List<GeneratedItem> _results = [];
  final List<ChatMessage> _chatMessages = [];
  final ScrollController _chatScrollController = ScrollController();
  late final String _localChatTopicsPrefsKey;
  final Map<String, KorlixLocalChatTopic> _chatTopicsById =
      <String, KorlixLocalChatTopic>{};
  String? _activeChatTopicId;
  late final String _pendingGenerationJobsPrefsKey;
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

  // KORLIX_ENTERPRISE_COPYALL_REWRITE_SAFE_V1_BEGIN
  String? _enterpriseBoxFirstStringValue(dynamic value, {Set<dynamic>? seen}) {
    final visited = seen ?? <dynamic>{};

    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    if (value is Map) {
      if (visited.contains(value)) {
        return null;
      }

      visited.add(value);

      const keys = <String>[
        'response',
        'content',
        'text',
        'answer',
        'message',
        'output',
        'result',
      ];

      for (final key in keys) {
        if (value.containsKey(key)) {
          final found = _enterpriseBoxFirstStringValue(
            value[key],
            seen: visited,
          );

          if (found != null && found.trim().isNotEmpty) {
            return found.trim();
          }
        }
      }

      for (final entry in value.entries) {
        final found = _enterpriseBoxFirstStringValue(
          entry.value,
          seen: visited,
        );

        if (found != null && found.trim().isNotEmpty) {
          return found.trim();
        }
      }
    }

    if (value is List) {
      if (visited.contains(value)) {
        return null;
      }

      visited.add(value);

      for (final item in value) {
        final found = _enterpriseBoxFirstStringValue(item, seen: visited);

        if (found != null && found.trim().isNotEmpty) {
          return found.trim();
        }
      }
    }

    return null;
  }

  Future<String> _rewriteEnterpriseBoxWithAi({
    required String boxLabel,
    required String text,
    String action = 'Polish',
  }) async {
    final original = text.trimRight();

    if (original.trim().isEmpty) {
      throw Exception('Add text to this box before using AI rewrite.');
    }

    final prompt = <String>[
      'Transform the following saved text. Requested action: $action.',
      'For Action items, extract only supported tasks and owners; mark unspecified owners or dates as unspecified.',
      'For Meeting notes, organize discussion, decisions and next steps without inventing any.',
      '',
      'Rules:',
      '- Keep the original meaning and important details.',
      '- Make it clearer, more professional, and easier to reuse.',
      '- Do not add fake facts.',
      '- Do not add markdown fences.',
      '- Return only the rewritten text.',
      '',
      'Box label: $boxLabel',
      '',
      'Original text:',
      original,
    ].join('\n');

    final response = await http
        .post(
          _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/generate'),
          headers: _authHeaders(),
          body: jsonEncode(<String, dynamic>{
            'prompt': prompt,
            'language': _selectedLanguage,
            'source': 'enterprise_box_ai_rewrite',
          }),
        )
        .timeout(const Duration(seconds: 360));

    final data = _decodeKorlixJsonMap(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['error']?.toString() ??
            data['details']?.toString() ??
            'AI rewrite failed.',
      );
    }

    final rewritten = _enterpriseBoxFirstStringValue(data);

    if (rewritten == null || rewritten.trim().isEmpty) {
      throw Exception('AI rewrite returned an empty response.');
    }

    return rewritten.trimRight();
  }
  // KORLIX_ENTERPRISE_COPYALL_REWRITE_SAFE_V1_END

  // KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_TIER_CALLBACK_BEGIN
  void _handleBillingRevision() {
    if (mounted) unawaited(_loadCurrentTier());
  }

  Future<void> _handleAppleSubscriptionTierChanged(String tier) async {
    final normalizedTier = tier.trim().toLowerCase();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentTier = normalizedTier.isEmpty ? 'basic' : normalizedTier;
    });

    await _loadCurrentTier();
  }
  // KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_TIER_CALLBACK_END

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _characters = CharacterSelectionController(
      baseUrl: kKorlixBackendBaseUrl, headersBuilder: _authHeaders,
      selected: kKorlixSelectedCharacterNotifier, sessionChanges: kKorlixAuthRevision,
    );
    unawaited(_characters.load());
    final chatStorageScope = chatAccountStorageKey(_authHeaders());
    _localChatTopicsPrefsKey = 'korlix_chat_topics_account_v2_$chatStorageScope';
    _pendingGenerationJobsPrefsKey = 'korlix_chat_jobs_account_v2_$chatStorageScope';
    _chatMemory = ChatMemoryClient(baseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    kKorlixBillingRevision.addListener(_handleBillingRevision);
    unawaited(_chatMemory.load());
    if (!kIsWeb) unawaited(
      KorlixAppleBillingService.instance.configure(
        backendBaseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _authHeaders,
        sessionChanges: kKorlixAuthRevision,
        currentTier: _currentTier,
        onTierChanged: _handleAppleSubscriptionTierChanged,
      ),
    );

    _loadSavedKorlixTheme();
    _loadCurrentTier();
    _loadLocalChatTopics();
    unawaited(_resumePendingGenerationJobs());
    if (kIsWeb && ['return', 'cancel', 'plans'].contains(Uri.base.queryParameters['billing'])) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(showKorlixWebBilling(context, baseUrl: kKorlixBackendBaseUrl,
          headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision,
          onTierChanged: _handleAppleSubscriptionTierChanged,
          checkoutReturn: Uri.base.queryParameters['billing']));
      });
    }
  }

  Future<void> _loadSavedKorlixTheme() => kKorlixAppearancePreferences.restore();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatMemory.dispose();
    kKorlixBillingRevision.removeListener(_handleBillingRevision);
    _characters.dispose();
    _schedulingVoice?.dispose();
    _schedulingVoiceClient?.dispose();
    _imagineStudio?.dispose();
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
    final skin = korlixSkinOf(context);
    if (files.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('${files.length} ${files.length == 1 ? 'file' : 'files'} attached', style: TextStyle(color: skin.text, fontWeight: FontWeight.w700))),
        TextButton(style: korlixSoundButtonStyle(null), onPressed: korlixSoundAction(_loading ? null : _handleUploadPressed), child: const Text('Manage')),
        IconButton(enableFeedback: false, tooltip: 'Clear all attachments', onPressed: korlixSoundAction(_loading ? null : _clearPickedUploadFiles), icon: const Icon(Icons.delete_sweep_outlined)),
      ]),
      for (var i = 0; i < files.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: KorlixUploadFileCard(file: files[i], onRemove: _loading ? null : () => _removePickedUploadFileAt(i))),
    ]);
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

  // KORLIX_CAMERA_ASK_STUDIO
  bool _cameraAskOpening = false;
  Future<void> _capturePhotoAndAskShortcut() async {
    if (_loading || _cameraAskOpening) return;
    setState(() => _cameraAskOpening = true);
    CameraAskClient? client;
    try {
      client = CameraAskClient(baseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
      client.guard();
      if (_voiceListening) {
        await _speechToText.stop();
        if (mounted) setState(() => _voiceListening = false);
      }
      await _stopAiCharacterTalkingForQuery();
      if (!mounted) return;
      client.guard();
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => CameraAskScreen(
        client: client!, initialQuestion: _controller.text.trim(), language: _selectedLanguage,
        ensureConsent: (context) => ensureKorlixThirdPartyAiConsent(
          context: context, featureName: 'Camera Ask',
          providers: {KorlixThirdPartyAiProvider.openAi},
          dataCategories: {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
      )));
    } catch (_) {
      if (mounted) setState(() => _error = 'Camera Ask could not open. Please try again.');
    } finally {
      client?.dispose();
      if (mounted) setState(() => _cameraAskOpening = false);
    }
  }


  Future<void> _handleUploadPressed() async {
    if (_loading || _uploadOpening) return;
    final email = kKorlixUserEmail;
    final topic = _activeChatTopicId;
    bool current() => email != null && email == kKorlixUserEmail && kKorlixAccessToken != null;
    if (!current()) return;
    setState(() => _uploadOpening = true);
    try {
      final draft = await Navigator.of(context).push<KorlixUploadDraft>(MaterialPageRoute(
        builder: (_) => KorlixUploadStudio(initialFiles: _activeUploadFiles,
          initialPrompt: _controller.text, sessionChanges: kKorlixAuthRevision,
          isSessionCurrent: current),
      ));
      if (!mounted || !current() || topic != _activeChatTopicId || draft == null) return;
      setState(() {
        _pickedUploadFiles..clear()..addAll(draft.files);
        _pickedUploadFile = draft.files.isEmpty ? null : draft.files.first;
        _controller.value = TextEditingValue(text: draft.prompt, selection: TextSelection.collapsed(offset: draft.prompt.length));
        _error = null;
      });
    } finally { if (mounted) setState(() => _uploadOpening = false); }
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
      unawaited(_chatMemory.load());
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
        safeTopicId != _activeChatTopicId) {
      if (!_chatTopicsById.containsKey(safeTopicId)) return;
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
      if (!_resumePendingGenerationJobsRunning) {
        unawaited(kKorlixSounds.play(KorlixSound.bell,
          eventId: 'generation:${safeTopicId}:${completedAt.microsecondsSinceEpoch}'));
      }
      return;
    }

    _results.insert(0, newItem);
    _addChatMessage(message);
    if (!_resumePendingGenerationJobsRunning) {
      unawaited(kKorlixSounds.play(KorlixSound.bell,
        eventId: 'generation:${_activeChatTopicId}:${completedAt.microsecondsSinceEpoch}'));
    }

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
          if (!mounted || !_chatMemory.available) return;
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
    if (_loading) return;
    await _stopAiCharacterTalkingForQuery();
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = KorlixChatCopy(_selectedLanguage).picturePromptRequired);
      return;
    }
    _ensureActiveChatTopicForPrompt(prompt);
    final topicId = _activeChatTopicId;
    final language = _selectedLanguage;
    final size = _chatImageSize;
    final style = _chatImageStyle;
    setState(() {
      _loading = true;
      _error = null;
      _featuredAnswerDismissed = false;
      _pendingChatPrompt = prompt;
      _pendingChatTopicId = topicId;
      _pendingChatIsImage = true;
    });
    try {
      final response = await http.post(
        _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/image/create'),
        headers: _authHeaders(),
        body: jsonEncode({'prompt': prompt, 'language': language,
          'imageSize': size, 'imageStyle': style}),
      ).timeout(const Duration(seconds: 260));
      final data = _decodeKorlixJsonMap(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['details'] ?? data['error'] ?? response.body);
      }
      final imageDataUrl = data['imageDataUrl']?.toString();
      final imageUrl = data['imageUrl']?.toString();
      if ((imageDataUrl == null || imageDataUrl.isEmpty) &&
          (imageUrl == null || imageUrl.isEmpty)) throw Exception(KorlixChatCopy(language).noImageReturned);
      if (!mounted) return;
      final item = GeneratedItem(command: prompt,
        title: data['title']?.toString() ?? KorlixChatCopy(language).yourPicture,
        content: data['content']?.toString() ?? KorlixChatCopy(language).imageGenerated,
        language: language, allowPdf: false, imageDataUrl: imageDataUrl, imageUrl: imageUrl);
      final message = ChatMessage(userText: prompt, aiText: item.content,
        language: language, isImage: true, imageDataUrl: imageDataUrl,
        imageUrl: imageUrl, generatedItem: item, createdAt: DateTime.now());
      setState(() {
        _loading = false;
        _pendingChatPrompt = '';
        if (_controller.text.trim() == prompt) _controller.clear();
        if (topicId == _activeChatTopicId) {
          _results.insert(0, item);
          _addChatMessage(message);
        } else if (_chatTopicsById.containsKey(topicId)) {
          final topic = _chatTopicsById[topicId]!;
          _chatTopicsById[topicId!] = topic.copyWith(
            messages: [...topic.messages, message], updatedAt: DateTime.now());
          unawaited(_persistLocalChatTopics());
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pendingChatPrompt = '';
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  Future<void> _generateImprovedPicture() async {
    if (_loading) return;
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_IMPROVE_PICTURE_BEGIN
    final korlixThirdPartyAiConsentGranted =
        await ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: 'Improve Picture',
          providers: const <KorlixThirdPartyAiProvider>{
            KorlixThirdPartyAiProvider.openAi,
          },
          dataCategories: const <KorlixThirdPartyAiDataCategory>{
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.imagesAndPhotos,
          },
        );

    if (!korlixThirdPartyAiConsentGranted || !mounted || _loading) {
      return;
    }
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_IMPROVE_PICTURE_END

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

    final prompt =
        (_portraitStudioPromptOverride != null &&
            _portraitStudioPromptOverride!.trim().isNotEmpty)
        ? _portraitStudioPromptOverride!.trim()
        : command.isEmpty
        ? 'Improve this picture and return an enhanced professional version.'
        : command;

    final language = _selectedLanguage;
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
      request.fields['language'] = language;

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          file.bytes!,
          filename: file.name,
          contentType: _mediaTypeForPickedFile(file),
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 430),
      );

      final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 430));
      if (!mounted) return;
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
        language: language,
        allowPdf: false,
        imageDataUrl: imageDataUrl,
        imageUrl: imageUrl,
      );

      setState(() {
        _loading = false;
        if (_controller.text.trim() == command) _controller.clear();
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '${_t.createError}\n\n${korlixFriendlyErrorMessage(error)}';
      });
    }
  }

  Future<void> _generateWithUpload() async {
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_GENERATE_WITH_UPLOAD_BEGIN
    final korlixThirdPartyAiConsentGranted =
        await ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: 'Analyze Uploaded Content',
          providers: const <KorlixThirdPartyAiProvider>{
            KorlixThirdPartyAiProvider.openAi,
          },
          dataCategories: const <KorlixThirdPartyAiDataCategory>{
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.imagesAndPhotos,
            KorlixThirdPartyAiDataCategory.filesAndDocuments,
          },
        );

    if (!korlixThirdPartyAiConsentGranted) {
      return;
    }
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_GENERATE_WITH_UPLOAD_END

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

  Future<void> _generate() async {
    if (_loading) return;
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_MAIN_GENERATE_BEGIN
    final korlixThirdPartyAiConsentGranted =
        await ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: 'Korlix AI Request',
          providers: const <KorlixThirdPartyAiProvider>{
            KorlixThirdPartyAiProvider.openAi,
            KorlixThirdPartyAiProvider.klingAi,
            KorlixThirdPartyAiProvider.musicApiAi,
          },
          dataCategories: const <KorlixThirdPartyAiDataCategory>{
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.imagesAndPhotos,
            KorlixThirdPartyAiDataCategory.filesAndDocuments,
            KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
          },
        );

    if (!korlixThirdPartyAiConsentGranted || _loading) {
      return;
    }
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_MAIN_GENERATE_END

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

    if (_imaginePictureMode && _activeUploadFiles.isNotEmpty) {
      if (_activeUploadFiles.length == 1 &&
          _mimeTypeForPickedFile(_activeUploadFiles.first).startsWith('image/')) {
        await _generateImprovedPicture();
      } else {
        setState(() => _error = 'Use one reference picture for an image edit, or remove attachments to create a new picture.');
      }
      return;
    }

    if (_imaginePictureMode || (_activeUploadFiles.isEmpty &&
        !_createVideoMode && !_fixCreditReportMode &&
        korlixWantsNewImage(_controller.text))) {
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

    final isMemoryRequest = RegExp(r'^(?:please\s+)?remember\s+', caseSensitive: false).hasMatch(command);
    if (_createVideoMode || (!isMemoryRequest && (
        command.toLowerCase().contains('create a video') ||
        command.toLowerCase().contains('cinematic video masterpiece')))) {
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
    _ensureActiveChatTopicForPrompt(command);
    final topicId = _activeChatTopicId;
    final selectedHistory = korlixChatHistory(_strictActiveTopicMessages().expand((m) => [
      {'role': 'user', 'content': _korlixVisibleUserText(m.userText)},
      {'role': 'assistant', 'content': m.aiText},
    ]));

    setState(() {
      _featuredAnswerDismissed = false;
      _answerMinimized = false;
      _loading = true;
      _error = null;
      _pendingChatPrompt = _korlixVisibleUserText(command);
      _pendingChatTopicId = topicId;
      _pendingChatIsImage = false;
    });

    _speakConsiderItDone();

    try {
      final data = await _runResumableJsonPost(
        localJobId: localJobId,
        kind: 'text',
        endpoint: '/api/generate',
        payload: {'command': command, 'language': _selectedLanguage,
          'history': selectedHistory, 'topicId': topicId, 'mainChatMemory': true},
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
        _pendingChatPrompt = '';
            _error = null;
            if (_controller.text.trim() == _korlixVisibleUserText(command)) _controller.clear();
          });

          _showBackgroundProcessingSnack(
            'Korlix is still processing. If your phone locks, reopen the app and this answer will resume.',
          );
        }

        return;
      }

      if (!mounted || !_chatMemory.available) return;
      unawaited(_chatMemory.load());
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
        _pendingChatPrompt = '';
        if (_controller.text.trim() == _korlixVisibleUserText(command)) _controller.clear();
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
        _pendingChatPrompt = '';
            _error = null;
          });
        }

        return;
      }

      setState(() {
        _loading = false;
        _pendingChatPrompt = '';
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
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.pop(context, false)),
              child: Text(_t.cancel),
            ),
            FilledButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.pop(context, true)),
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

  Future<bool> _submitGeneratedContentReport({
    required String contentType,
    required String prompt,
    required String outputSummary,
    required String reason,
    required String details,
    required Map<String, String> headers,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) async {
    try {
      await submitKorlixAiReport(
        endpoint: _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/report-output'),
        headers: headers,
        contentType: contentType,
        appArea: 'generated_content_report',
        prompt: prompt,
        outputSummary: outputSummary,
        reason: reason,
        details: details,
        contentId: contentId,
        imageUrl: imageUrl,
        videoId: videoId,
        language: _selectedLanguage,
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showReportGeneratedContentSheet({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
    String? imageUrl,
    String? videoId,
  }) async {
    if (!mounted || _aiOutputReportBusy) return;
    final revision = kKorlixAuthRevision.value;
    final token = kKorlixAccessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to submit a report.')),
      );
      return;
    }
    final headers = Map<String, String>.from(_authHeaders());
    bool current() => mounted && revision == kKorlixAuthRevision.value &&
        token == kKorlixAccessToken;
    _aiOutputReportBusy = true;
    var sheetSubmitted = false;
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
                          maxLength: 1000,
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
                                onPressed: korlixSoundAction(() =>
                                    Navigator.of(sheetContext).pop()),
                                style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
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
                                )),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: korlixSoundAction(() {
                                  if (sheetSubmitted) return;
                                  sheetSubmitted = true;
                                  Navigator.of(
                                    sheetContext,
                                  ).pop(<String, String>{
                                    'reason': selectedReason,
                                    'details': detailsController.text.trim(),
                                  });
                                }),
                                icon: const Icon(Icons.flag_rounded),
                                label: const Text('Submit'),
                                style: korlixSoundButtonStyle(FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                )),
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

      if (result == null || !current()) {
        return;
      }

      final reason = result['reason'] ?? 'Other';
      final details = result['details'] ?? '';

      final sent = await _submitGeneratedContentReport(
        headers: headers,
        contentType: contentType,
        prompt: prompt,
        outputSummary: outputSummary,
        reason: reason,
        details: details,
        contentId: contentId,
        imageUrl: imageUrl,
        videoId: videoId,
      );

      if (!current()) {
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
            'We could not confirm whether your report was received. It may already be saved. Contact support@korlixdeveloper.com before submitting it again.',
          ),
        ),
      );
    } finally {
      detailsController.dispose();
      _aiOutputReportBusy = false;
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
        fit: BoxFit.contain,
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      imageChild = Image.network(
        imageUrl,
        width: double.infinity,
        height: height,
        fit: BoxFit.contain,
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
      if (!mounted) return;

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
        fileNameOverrides: [_generatedImageFilename(item)],
        sharePositionOrigin: korlixShareOrigin(context),
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
              TextButton.icon(style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(() => _saveGeneratedImage(item)),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Save'),
              ),
              TextButton.icon(style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(() => _shareGeneratedImage(item)),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share'),
              ),
            ] else ...[
              TextButton(style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(() => _copyResultText(item)),
                child: Text(language.copy),
              ),
              if (item.allowPdf)
                TextButton(style: korlixSoundButtonStyle(null),
                  onPressed: korlixSoundAction(() => _exportPdf(item)),
                  child: Text(language.exportPdf),
                ),
            ],
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.pop(context)),
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
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop(false)),
              child: const Text('Close'),
            ),
            FilledButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop(true)),
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

  Widget _buildSafeUiQuickActionChip(QuickAction action, {bool tile = false}) {
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
    final isEmailAction = action.label.toLowerCase() == 'email enhancer';
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
        ? Icons.auto_awesome_mosaic_rounded
        : isCreditAction
        ? Icons.credit_score_rounded
        : isAppAction
        ? Icons.app_shortcut_rounded
        : null;

    return KorlixActionButton(
      tile: tile,
      label: label,
      subtitle: isImproveAction ? 'Restore, relight & refine' : isEmailAction ? 'Polish, draft & reply' : isImagineAction ? 'Styles, scenes & art' : null,
      leading: isImagineAction ? ClipRRect(borderRadius: BorderRadius.circular(11),
        child: const SizedBox(width: 38, height: 38, child: ImagineArtwork())) : isImproveAction ? const SizedBox(width: 38, height: 38, child: PictureArtwork()) : isEmailAction ? const SizedBox(width: 38, height: 38, child: EmailArtwork()) : null,
      icon: icon ?? korlixToolIcon(label),
      onPressed: _loading ? null : () => _useQuickAction(action),
      selected: isHighlighted ? true : null,
      accent: isHighlighted ? skin.success :
          (isVideoAction || isImproveAction || isImagineAction || isAppAction || isEmailAction)
              ? skin.secondary : skin.primary,
      size: KorlixButtonSize.compact,
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

  Future<void> _openImagineStudio() async {
    if (_loading || _imagineStudioOpening) return;
    _imagineStudioOpening = true;
    try {
      if (_voiceListening) {
        await _speechToText.stop();
        if (mounted) setState(() => _voiceListening = false);
      }
      await _stopAiCharacterTalkingForQuery();
      if (!mounted) return;
      if (_imagineStudio?.available != true) {
        _imagineStudio?.dispose();
        _imagineStudio = ImagineClient(baseUrl: kKorlixBackendBaseUrl,
          headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
        _imagineStudio!.draft = ImagineBrief(prompt: _controller.text.trim(),
          style: _chatImageStyle, size: _chatImageSize);
      }
      final studio = _imagineStudio!;
      Future<bool> consent() => ensureKorlixThirdPartyAiConsent(
        context: context, featureName: 'Imagine a Picture',
        providers: const {KorlixThirdPartyAiProvider.openAi},
        dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts});
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImagineStudioScreen(
        client: studio, language: _selectedLanguage, ensureConsent: consent, allowVoice: _hasVoiceAccess,
        onRefine: (result) async {
          if (!studio.available) return;
          final owner = PictureStudioSession(headersBuilder: _authHeaders,
            sessionChanges: kKorlixAuthRevision);
          final editor = PictureStudioClient(backendBaseUrl: kKorlixBackendBaseUrl,
            headersBuilder: _authHeaders,
            isSessionCurrent: () => studio.available && owner.isCurrent);
          try {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnimatedBuilder(
              animation: Listenable.merge([studio, owner]),
              builder: (context, _) => !studio.available || !owner.isCurrent
                ? Scaffold(appBar: AppBar(title: const Text('Picture Studio')),
                    body: const Center(child: Text('Your session changed. Sign in again.')))
                : PictureStudioScreen(
                    initialFile: fp.PlatformFile(name: 'korlix-imagined-picture.png',
                      size: result.bytes.length, bytes: result.bytes),
                    language: _selectedLanguage,
                    onImprove: (file, options) async {
                      if (!studio.available || !owner.isCurrent) throw const ImagineException('Your session changed.');
                      final edited = await editor.improve(file, options);
                      if (!studio.available || !owner.isCurrent) throw const ImagineException('Your session changed.');
                      return edited;
                    },
                    ensureConsent: () => ensureKorlixThirdPartyAiConsent(
                      context: context, featureName: 'Refine Picture',
                      providers: const {KorlixThirdPartyAiProvider.openAi},
                      dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
                        KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
                    onOpenTemplates: () => unawaited(_openPortraitTemplateGallery()),
                  ))));
          } finally { editor.dispose(); owner.dispose(); }
        },
      )));
    } finally { _imagineStudioOpening = false; }
  }

  Future<void> _openLogoStudio() async {
    if (_loading || _logoStudioOpening) return;
    _logoStudioOpening = true;
    LogoClient? client;
    try {
      if (_voiceListening) {
        await _speechToText.stop();
        if (mounted) setState(() => _voiceListening = false);
      }
      await _stopAiCharacterTalkingForQuery();
      if (!mounted) return;
      client = LogoClient(headers: _authHeaders(), images: ImagineClient(
        baseUrl: kKorlixBackendBaseUrl, headersBuilder: _authHeaders,
        sessionChanges: kKorlixAuthRevision));
      final studio = client;
      final route = MaterialPageRoute<void>(builder: (_) => LogoStudioScreen(
        client: studio, language: _selectedLanguage, allowVoice: _hasVoiceAccess,
        ensureConsent: () => ensureKorlixThirdPartyAiConsent(
          context: context, featureName: 'Logo Studio AI concepts',
          providers: const {KorlixThirdPartyAiProvider.openAi},
          dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
      ));
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } finally { client?.dispose(); _logoStudioOpening = false; }
  }

  Future<void> _openEmailEnhancer() async {
    if (_loading || _emailEnhancerOpening) return;
    _emailEnhancerOpening = true;
    EmailEnhancerClient? client;
    try {
      if (_voiceListening) {
        await _speechToText.stop();
        if (mounted) setState(() => _voiceListening = false);
      }
      await _stopAiCharacterTalkingForQuery();
      if (!mounted) return;
      client = EmailEnhancerClient(baseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
      final studio = client;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmailEnhancerScreen(
        client: studio, language: _selectedLanguage, allowVoice: _hasVoiceAccess,
        ensureConsent: () => ensureKorlixThirdPartyAiConsent(
          context: context, featureName: 'Email Enhancer',
          providers: const {KorlixThirdPartyAiProvider.openAi},
          dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
      )));
    } finally { client?.dispose(); _emailEnhancerOpening = false; }
  }

  Future<void> _openImprovePictureStudio() async {
    if (_loading || _improvePictureStudioOpening) return;
    _improvePictureStudioOpening = true;
    final owner = PictureStudioSession(headersBuilder: _authHeaders,
      sessionChanges: kKorlixAuthRevision);
    PictureStudioClient? client;
    try {
      await _stopAiCharacterTalkingForQuery();
      if (!mounted) return;
      final editor = PictureStudioClient(backendBaseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _authHeaders, isSessionCurrent: () => owner.isCurrent);
      client = editor;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnimatedBuilder(
        animation: owner,
        builder: (context, _) => !owner.isCurrent
          ? Scaffold(appBar: AppBar(title: const Text('Picture Studio')),
              body: const Center(child: Text('Sign in again to open Picture Studio.')))
          : PictureStudioScreen(
              initialFile: _activeUploadFiles.length == 1 ? _activeUploadFiles.first : null,
              initialPrompt: _controller.text.trim(), language: _selectedLanguage,
              onImprove: editor.improve,
              ensureConsent: () => ensureKorlixThirdPartyAiConsent(
                context: context, featureName: 'Improve My Picture',
                providers: const {KorlixThirdPartyAiProvider.openAi},
                dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
                  KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
              onOpenTemplates: () => unawaited(_openPortraitTemplateGallery()),
            ),
      )));
    } finally {
      client?.dispose();
      owner.dispose();
      _improvePictureStudioOpening = false;
    }
  }

  Future<void> _openPortraitTemplateGallery() async {
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
    if (action.label.toLowerCase() == 'email enhancer') { unawaited(_openEmailEnhancer()); return; }
    if (const {'Write my Resume', 'Rédiger mon CV', 'Crear mi currículum'}.contains(action.label)) { unawaited(_openResumeStudio()); return; }
    if (action.label == 'Tax Prep') { unawaited(_openTaxPrep()); return; }
    if (action.label == 'BabyBlend') { unawaited(_openBabyBlend()); return; }
    if (action.label == 'FieldProof') { unawaited(_openFieldProof()); return; }
    if (action.label == 'AI Visibility') {
      unawaited(_openAiVisibility());
      return;
    }
    if (action.label == 'Live Studio') { unawaited(_openLiveStudio()); return; }
    if (action.label == 'The Pod and You') { unawaited(_openPod()); return; }
    if (action.label == 'SEO Agent') {
      unawaited(_openSeoAgent());
      return;
    }
    if (action.label == 'Contract Radar') {
      unawaited(_openContractRadar());
      return;
    }
    if (action.label == 'Virtual Closet') {
      unawaited(_openVirtualCloset());
      return;
    }
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

    if (const {'Study / learn', 'Estudiar', 'Étudier'}.contains(action.label)) {
      unawaited(_openStudyStudio());
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
      unawaited(_openImagineStudio());
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

  Future<void> _openResumeStudio() async {
    final client=ResumeClient(baseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision,language:_selectedLanguage);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ResumeScreen(client:client,
      ensureConsent:(context)=>KorlixThirdPartyAiConsent.ensure(context:context,featureName:'Resume Studio and Rici',providers:{KorlixThirdPartyAiProvider.openAi},dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.filesAndDocuments}),
    )));
  }

  Future<void> _openKorlixSocial({SocialUnreadConversation? conversation}) async {
    if (_socialOpening) return;
    _socialOpening = true;
    final revision = kKorlixAuthRevision.value;
    try {
      await _stopAiCharacterTalkingForQuery();
      if (!mounted || revision != kKorlixAuthRevision.value) return;
      final client = SocialClient(baseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>SocialScreen(
        client:client,
        initialConversation: conversation?.card,
        initialGroupChat: conversation?.group ?? false,
      )));
    } finally {
      _socialOpening = false;
      if (mounted) unawaited(_socialNotifications.refresh());
    }
  }

  Future<void> _openInventoryStudio() async {
    if (_currentTier.trim().toLowerCase() != 'enterprise') {
      await _showPremiumFeaturePrompt(
        title: 'Inventory Studio requires Enterprise',
        availability: 'Enterprise',
        description: 'Manage stock, products and business locations with Enterprise. Your saved records are retained.',
      );
      return;
    }
    final client=InventoryClient(backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    Future<bool> consent(BuildContext context)=>KorlixThirdPartyAiConsent.ensure(context:context,featureName:'Inventory Studio and Rici',providers:{KorlixThirdPartyAiProvider.openAi},dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.imagesAndPhotos,KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,KorlixThirdPartyAiDataCategory.inventoryRecords});
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>InventoryScreen(client:client,ensureConsent:consent,openVoice:(search,results)async{
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>KorlixLiveConvoTestScreen(
        sessionChanges:kKorlixAuthRevision,backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,
        characterId:normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),language:_t.label,
        inventorySearch:search,inventoryResultsBuilder:results,
      )));
    })));
  }

  Future<void> _openCyberDefender() async {
    final client=DefenderClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>DefenderScreen(
      client:client,ensureConsent:(context)=>KorlixThirdPartyAiConsent.ensure(context:context,
        featureName:'Cybersecurity Defender',providers:{KorlixThirdPartyAiProvider.openAi},
        dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  Future<void> _openStudyStudio() async {
    final client=StudyClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>StudyScreen(
      client:client,ensureConsent:(context)=>KorlixThirdPartyAiConsent.ensure(context:context,
        featureName:'Study Studio',providers:{KorlixThirdPartyAiProvider.openAi},
        dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  Future<void> _showAppCreationDialog() async {
    final client=AppStudioClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>AppStudioScreen(
      client:client,ensureConsent:(context)=>KorlixThirdPartyAiConsent.ensure(context:context,
        featureName:'App Studio',providers:{KorlixThirdPartyAiProvider.openAi},
        dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  @override
  Widget build(BuildContext context) {
    // K135Z_B4B_V11_SYNC_SHARED_ENTERPRISE_STATE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncKorlixMeetingCopilotEnterpriseAccessFromTier(_currentTier);
    });

    final t = _t;

    return Scaffold(
      body: ValueListenableBuilder<String>(valueListenable: kKorlixScreenSkinNotifier,
        builder: (context, screenSkin, _) => KorlixScreenBackdrop(
        palette: korlixSkinPaletteFor(kKorlixThemeNotifier.value), skinId: screenSkin,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(MediaQuery.sizeOf(context).width < 430 ? 12 : 24, 28, MediaQuery.sizeOf(context).width < 430 ? 12 : 24, 40),
                child: Column(
                  children: [
                    _buildMockupHomeHeader(),
                    if (kIsWeb) const KorlixLaunchCountdown(),
                    HomeQuickAccess(
                      onFindTool: _openHomeToolFinder,
                    ),
                    SocialNotificationBanner(
                      notifications: _socialNotifications,
                      onOpen: (conversation) => _openKorlixSocial(conversation: conversation),
                    ),
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
                    KorlixSkinFrame(key: _commandPanelKey, palette: korlixSkinPaletteFor(kKorlixThemeNotifier.value), skinId: screenSkin, child: _buildCommandPanel()),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
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
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
              child: const Text(
                'Not now',
                style: TextStyle(color: Color(0xFFA9C6CF)),
              ),
            ),
            FilledButton(
              onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
              style: korlixSoundButtonStyle(FilledButton.styleFrom(
                backgroundColor: const Color(0xFF143B4A),
                foregroundColor: const Color(0xFFE4EBEE),
              )),
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
      onPressed: korlixSoundAction(() => _showPremiumFeaturePrompt(
        title: title,
        availability: availability,
        description: description,
      )),
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
        onPressed: korlixSoundAction(_loading
            ? null
            : () => _showPremiumFeaturePrompt(
                title: title,
                availability: availability,
                description: description,
              )),
        style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: accent,
          backgroundColor: Colors.black.withOpacity(0.18),
          side: BorderSide(color: accent.withOpacity(0.42)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        )),
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

  Future<void> _openReceiptWiz() => openReceiptWiz(context, backendBaseUrl:kKorlixBackendBaseUrl, headersBuilder:_authHeaders, sessionChanges:kKorlixAuthRevision);

  Future<void> _openBookkeeping() async {
    if (_currentTier.trim().toLowerCase() != 'enterprise') {
      await _showPremiumFeaturePrompt(
        title: 'Bookkeeping requires Enterprise',
        availability: 'Enterprise',
        description: 'Manage business records, income, expenses and reports with Enterprise. Your saved records are retained.',
      );
      return;
    }
    final client = BookkeepingClient(backendBaseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      BookkeepingScreen(client: client, disposeClient: true,
        openVoice: (businessId, businessName, month) async {
          final revision = kKorlixAuthRevision.value;
          final consent = await ensureKorlixThirdPartyAiConsent(
            context: context,
            featureName: 'Bookkeeping and Rici',
            providers: const {KorlixThirdPartyAiProvider.openAi},
            dataCategories: const {
              KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
              KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
              KorlixThirdPartyAiDataCategory.bookkeepingRecords,
            },
          );
          if (!consent || !mounted || client.sessionChanged ||
              revision != kKorlixAuthRevision.value) return null;
          final voice = BookkeepingVoiceController(client: client,
            businessId: businessId, businessName: businessName, month: month);
          try {
            return await Navigator.of(context).push<Map<String, dynamic>>(
              MaterialPageRoute<Map<String, dynamic>>(
                builder: (_) => KorlixLiveConvoTestScreen(
                  bookkeepingVoice: voice,
                  sessionChanges: kKorlixAuthRevision,
                  backendBaseUrl: kKorlixBackendBaseUrl,
                  headersBuilder: _authHeaders,
                  characterId: normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),
                  language: _t.label,
                ),
              ),
            );
          } finally {
            voice.dispose();
          }
        },
      )));
  }

  Future<void> _openVirtualCloset() async {
    final client = ClosetClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>VirtualClosetScreen(
      client:client,
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,
        featureName:'Virtual Closet',providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
    )));
  }

  Future<void> _openContractRadar() async {
    final client = RadarClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ContractRadarScreen(
      client:client,
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,
        featureName:'Contract Radar',providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  Future<void> _openTaxPrep() async {
    final client=BookkeepingClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>TaxPrepScreen(
      client:client,disposeClient:true,openBookkeeping:_openBookkeeping,
    )));
  }

  Future<void> _openBabyBlend() async {
    final client=BabyBlendClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>BabyBlendScreen(
      client:client,
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,
        featureName:'BabyBlend portrait creation',providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
    )));
  }

  Future<void> _openFieldProof() async {
    if (_currentTier.trim().toLowerCase() != 'enterprise') {
      await _showPremiumFeaturePrompt(
        title: 'FieldProof requires Enterprise',
        availability: 'Enterprise',
        description: 'Document jobs, review evidence and prepare customer reports with Enterprise. Your saved records are retained.',
      );
      return;
    }
    final client=FieldProofClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FieldProofScreen(
      client:client,
      openVoice:(snapshot) async {
        final revision=kKorlixAuthRevision.value;
        final consent=await ensureKorlixThirdPartyAiConsent(context:context,
          featureName:'FieldProof and Rici',providers:const {KorlixThirdPartyAiProvider.openAi},
          dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
            KorlixThirdPartyAiDataCategory.fieldProofRecords});
        if(!consent||!mounted||client.sessionChanged||revision!=kKorlixAuthRevision.value)return null;
        final voice=FieldProofVoiceController(client:client,snapshot:snapshot);
        try {
          final route=MaterialPageRoute<Map<String,dynamic>>(builder:(_)=>KorlixLiveConvoTestScreen(
            fieldProofVoice:voice,sessionChanges:kKorlixAuthRevision,backendBaseUrl:kKorlixBackendBaseUrl,
            headersBuilder:_authHeaders,characterId:normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),language:_t.label));
          final result=await Navigator.of(context).push<Map<String,dynamic>>(route);
          await route.completed;
          return result;
        }finally{voice.dispose();}
      },
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,
        featureName:'FieldProof photo review',providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.imagesAndPhotos}),
    )));
  }

  Future<void> _openAiVisibility() async {
    final client = VisibilityClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>AiVisibilityScreen(
      client:client,
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,
        featureName:'AI Visibility',providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  Future<void> _openLiveStudio() async {
    final client=LiveStudioClient(backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>LiveStudioScreen(client:client,
      ensureConsent:()=>ensureKorlixThirdPartyAiConsent(context:context,featureName:'KORLIX Live Studio',
        providers:const {KorlixThirdPartyAiProvider.openAi},
        dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts})),));
  }

  Future<void> _openPod() async {
    final client = PodClient(backendBaseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PodScreen(
      client: client,
      ensureConsent: () => ensureKorlixThirdPartyAiConsent(context: context,
        featureName: 'The Pod and You', providers: const {KorlixThirdPartyAiProvider.openAi},
        dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
          KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts}),
    )));
  }

  Future<void> _openSeoAgent() async {
    final client = SeoClient(backendBaseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SeoAgentScreen(
      client: client, openVisibility: _openAiVisibility,
      ensureConsent: () => ensureKorlixThirdPartyAiConsent(context: context,
        featureName: 'KORLIX AI SEO Agent', providers: const {KorlixThirdPartyAiProvider.openAi},
        dataCategories: const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
    )));
  }

  Future<void> _openFunnelStudio() async {
    if (_currentTier.trim().toLowerCase() != 'enterprise') return;
    final client = FunnelClient(
      backendBaseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders,
      sessionChanges: kKorlixAuthRevision,
    );
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      FunnelScreen(client: client, disposeClient: true, onOpenContacts: _openContactsCrm)));
  }

  Future<void> _openContactsCrm() async {
    if (_contactsOpening) return;
    _contactsOpening = true;
    stopKorlixCharacterSpeechGlobally();
    // Always open the real CRM. Its authenticated API verifies account access.
    try {
      final route = MaterialPageRoute<void>(builder: (_) => ContactsScreen(
        characterId: normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),
        language: _t.label,
        client: ContactsClient(backendBaseUrl: kKorlixBackendBaseUrl,
          headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision),
      ));
      await Navigator.of(context).push(route);
      await route.completed;
    } finally { _contactsOpening = false; }
  }

  List<QuickAction> get _homeQuickActions {
    final actions = _t.quickActions.where((a) => !_isCreditReportActionSafeUi(a)).toList();
    if (!actions.any((a) => a.label.toLowerCase() == 'email enhancer')) {
      actions.add(const QuickAction(label: 'Email enhancer', prompt: ''));
    }
    return actions;
  }

  Future<void> _openHomeToolFinder() async {
    if (_toolFinderOpening) return;
    _toolFinderOpening = true;
    stopKorlixCharacterSpeechGlobally();
    HomeToolEntry? selected;
    try {
      final route = MaterialPageRoute<HomeToolEntry>(builder: (_) => HomeToolFinder(
        tools: searchableHomeTools(
          quickActionLabels: _homeQuickActions.map((action) => action.label),
          enterprise: _currentTier.trim().toLowerCase() == 'enterprise',
        ),
      ));
      selected = await Navigator.of(context).push(route);
      await route.completed;
    } finally { _toolFinderOpening = false; }
    if (!mounted || selected == null) return;
    final tool = selected.label;
    switch (tool) {
      case 'Contacts CRM': await _openContactsCrm(); return;
      case 'KORLIX Social': await _openKorlixSocial(); return;
    }
    if (_loading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Wait for your current answer, then open this tool.'),
      ));
      return;
    }
    switch (tool) {
      case 'Live Convo': await _openLiveConvoAudioTest(); return;
      case 'Upload': await _handleUploadPressed(); return;
      case 'Voice': await _handleVoiceInput(); return;
      case 'Camera Ask': await _capturePhotoAndAskShortcut(); return;
      case 'Locator': await _showLocatorOptions(); return;
    }
    final actions = _homeQuickActions.where((a) => homeToolIdentity(a.label) == selected!.identity);
    if (actions.isNotEmpty) {
      _useQuickAction(actions.first);
    } else {
      _selectUtilityTool(tool);
    }
    // A few tools prepare the home composer instead of opening another route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panel = _commandPanelKey.currentContext;
      if (!mounted || panel == null || ModalRoute.of(context)?.isCurrent != true) return;
      unawaited(Scrollable.ensureVisible(panel,
        duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero : const Duration(milliseconds: 250)));
    });
  }

  Future<void> _openScheduling() async {
    final client = SchedulingClient(baseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    final enterprise = _currentTier.trim().toLowerCase() == 'enterprise';
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      SchedulingScreen(client: client, openFunnels: enterprise ? _openFunnelStudio : null,
        openContacts: enterprise ? _openContactsCrm : null,
        openVoice: () => _openLiveConvoAudioTest(schedulingMode: true))));
  }

  Future<void> _openPayroll() async {
    if (_currentTier.trim().toLowerCase() != 'enterprise') return;
    final client = PayrollClient(baseUrl: kKorlixBackendBaseUrl,
      headersBuilder: _authHeaders, sessionChanges: kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      PayrollScreen(client: client, openBookkeeping: _openBookkeeping, openWorkforce: _openWorkforce)));
  }

  Future<void> _openBusinessDirectory({bool receptionistMode=false,bool passportMode=false}) async {
    final client = DirectoryClient(backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    try {
      final route = MaterialPageRoute<void>(builder: (_) => DirectoryScreen(client:client,receptionistMode:receptionistMode,passportMode:passportMode,openScheduling:_openScheduling));
      await Navigator.of(context).push(route);
      await route.completed;
    } finally { client.dispose(); }
  }

  Future<void> _openWorkforce() async {
    final client=WorkforceClient(backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>WorkforceScreen(client:client,openVoice:(snapshot)async{
      final revision=kKorlixAuthRevision.value;
      final consent=await ensureKorlixThirdPartyAiConsent(context:context,featureName:'Workforce and Rici',providers:const {KorlixThirdPartyAiProvider.openAi},dataCategories:const {KorlixThirdPartyAiDataCategory.typedTextAndPrompts,KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,KorlixThirdPartyAiDataCategory.workforceRecords});
      if(!consent||!mounted||client.sessionChanged||revision!=kKorlixAuthRevision.value)return null;
      final voice=WorkforceVoiceController(client:client,organizationId:snapshot['organization']['id'] as String,memberId:snapshot['member']['user_id'] as String,memberVersion:snapshot['member']['version'] as int);
      try{
        final route=MaterialPageRoute<Map<String,dynamic>>(builder:(_)=>KorlixLiveConvoTestScreen(workforceVoice:voice,sessionChanges:kKorlixAuthRevision,backendBaseUrl:kKorlixBackendBaseUrl,headersBuilder:_authHeaders,characterId:normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),language:_t.label));
        final result=await Navigator.of(context).push<Map<String,dynamic>>(route);await route.completed;return result;
      }finally{voice.dispose();}
    })));
  }

  void _selectUtilityTool(String tool) {
    if (tool == 'THE RECEIPT WIZ') { unawaited(_openReceiptWiz()); return; }
    if (tool == 'Inventory Studio') { unawaited(_openInventoryStudio()); return; }
    if (tool == 'Logo Studio') { unawaited(_openLogoStudio()); return; }
    if (tool == 'Cybersecurity Defender') { unawaited(_openCyberDefender()); return; }
    if (tool == 'Study Studio') { unawaited(_openStudyStudio()); return; }
    if (tool == 'App Studio') { unawaited(_showAppCreationDialog()); return; }
    if (tool == 'Music Studio') { unawaited(_showMusicStudio()); return; }
    if (tool == 'Tax Prep') { unawaited(_openTaxPrep()); return; }
    if (tool == 'BabyBlend') { unawaited(_openBabyBlend()); return; }
    if (tool == 'FieldProof') { unawaited(_openFieldProof()); return; }
    if (tool == 'AI Visibility') {
      unawaited(_openAiVisibility());
      return;
    }
    if (tool == 'Live Studio') { unawaited(_openLiveStudio()); return; }
    if (tool == 'The Pod and You') { unawaited(_openPod()); return; }
    if (tool == 'SEO Agent') {
      unawaited(_openSeoAgent());
      return;
    }
    if (tool == 'Contract Radar') {
      unawaited(_openContractRadar());
      return;
    }
    if (tool == 'Virtual Closet') {
      unawaited(_openVirtualCloset());
      return;
    }
    if (tool == 'Bookkeeping 2027') {
      unawaited(_openBookkeeping());
      return;
    }

    if (tool == 'Funnel Studio') {
      unawaited(_openFunnelStudio());
      return;
    }

    if (tool == 'Payroll') { unawaited(_openPayroll()); return; }
    if (tool == 'KORLIX 2MEETU' || tool == 'Scheduling') { unawaited(_openScheduling()); return; }

    if (tool == 'Business Directory') { unawaited(_openBusinessDirectory()); return; }
    if (tool == 'Business Passport') { unawaited(_openBusinessDirectory(passportMode:true)); return; }
    if (tool == 'AI Receptionist') { unawaited(_openBusinessDirectory(receptionistMode:true)); return; }
    if (tool == 'Workforce') {
      unawaited(_openWorkforce());
      return;
    }

    if (tool == 'Contacts CRM') {
      unawaited(_openContactsCrm());
      return;
    }

    // KORLIX_BUILD109_HIDE_INACTIVE_UTILITY_GUARD
    if (_hiddenInactiveUtilityTools.contains(tool)) {
      setState(() {
        _clearUtilitySelection();
      });
      return;
    }

    if (tool == 'Voice-scribe' || tool == 'Copy Box') {
      unawaited(_openUtilityWorkspace(
        tool == 'Voice-scribe' ? 'voice_scribe' : 'copybox',
      ));
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
    return KorlixActionButton(
      icon: showStopIconWhenActive && active ? Icons.stop_circle_outlined : icon,
      label: label,
      onPressed: onPressed,
      locked: locked,
      selected: active || success ? true : null,
      accent: active || success ? skin.success : accentColor,
    );
  }

  bool _isIncludedTextWorkspace(String featureKey) => const {
    'voicescribe', 'copybox',
  }.contains(featureKey.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), ''));

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
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop()),
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
            TextButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() => Navigator.of(dialogContext).pop()),
              child: const Text('Cancel'),
            ),
            FilledButton(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() =>
                  Navigator.of(dialogContext).pop(controller.text.trim())),
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

  Future<void> _openSavedTextWorkspace(bool voice) async {
    if (!mounted || _textWorkspaceOpening) return;
    String? scope({bool session = false}) {
      try {
        final token = _authHeaders().entries.firstWhere((e) => e.key.toLowerCase() == 'authorization').value.split(' ').last;
        final data = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
        final parts = [data['iss'], data['sub'], if (session) data['session_id']];
        if (parts.any((v) => v is! String || v.isEmpty)) return null;
        return jsonEncode(parts);
      } catch (_) { return null; }
    }
    final account = scope(), session = scope(session: true);
    if (account == null || session == null) {
      await _showKorlixNotice(title: 'Sign in required', message: 'Sign in to open your saved text workspace.');
      return;
    }
    _textWorkspaceOpening = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || scope(session: true) != session) return;
      final route = MaterialPageRoute<void>(builder: (workspaceContext) => BoxWorkspace(
      store: BoxStore(preferences, account, voice),
      sessionChanges: kKorlixAuthRevision,
      sessionValid: () => scope(session: true) == session,
      rewrite: (action, text) async {
        if (scope(session: true) != session) throw StateError('Session changed');
        final consent = await ensureKorlixThirdPartyAiConsent(
          context: workspaceContext,
          featureName: voice ? 'VoiceScribe AI edits' : 'Copy Box AI edits',
          providers: {KorlixThirdPartyAiProvider.openAi},
          dataCategories: {KorlixThirdPartyAiDataCategory.typedTextAndPrompts, if (voice) KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts},
        );
        if (!consent || scope(session: true) != session) throw StateError('AI edit cancelled');
        final result = await _rewriteEnterpriseBoxWithAi(boxLabel: voice ? 'VoiceScribe' : 'Copy Box', text: text, action: action);
        if (scope(session: true) != session) throw StateError('Session changed');
        return result;
      },
      ));
      await Navigator.of(context).push(route);
      await route.completed;
    } catch (_) {
      if (mounted && scope(session: true) == session) {
        await _showKorlixNotice(
          title: '${voice ? 'VoiceScribe' : 'Copy Box'} could not open',
          message: 'Please try opening the workspace again. Your saved entries have not been removed.',
        );
      }
    } finally {
      _textWorkspaceOpening = false;
    }
  }

  Future<void> _openCustomAccessFeature(String featureKey) async {
    switch (featureKey.trim().toLowerCase()) {
      case 'copybox':
        await _openSavedTextWorkspace(false);
        return;
      case 'voice_scribe':
      case 'voice-scribe':
      case 'voicescribe':
        await _openSavedTextWorkspace(true);
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
    final includedTextWorkspace = _isIncludedTextWorkspace(featureKey);
    final unlocked = includedTextWorkspace || _customAccessHasFeature(featureKey);

    final statusLabel = includedTextWorkspace
        ? 'Included · No code needed'
        : unlocked
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
          FilledButton(style: korlixSoundButtonStyle(null),
            onPressed: korlixSoundAction(unlocked
                ? () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_openCustomAccessFeature(featureKey));
                  }
                : null),
            child: Text(unlocked ? 'Open' : 'Locked'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomAccessSheet({bool refresh = true}) async {
    if (refresh) {
      await _refreshCustomAccess();
    }

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
                  (item) => _isIncludedTextWorkspace(_customAccessFeatureKey(item)) || _customAccessItemBool(
                    item,
                    'includedInTrial',
                    'included_in_trial',
                  ),
                )
                .toList(growable: false);
            final paidAddons = catalog
                .where(
                  (item) => !_isIncludedTextWorkspace(_customAccessFeatureKey(item)) && !_customAccessItemBool(
                    item,
                    'includedInTrial',
                    'included_in_trial',
                  ),
                )
                .toList(growable: false);

            final hasIncludedAccess = included.any((item) =>
              _isIncludedTextWorkspace(_customAccessFeatureKey(item)) ||
              _customAccessHasFeature(_customAccessFeatureKey(item)));
            final hasCodeFeatures = included.any((item) =>
              !_isIncludedTextWorkspace(_customAccessFeatureKey(item)));

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
                            IconButton(enableFeedback: false,
                              tooltip: 'Close',
                              onPressed: korlixSoundAction(() => Navigator.of(sheetContext).pop()),
                              icon: const Icon(Icons.close_rounded),
                              color: skin.text,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'VoiceScribe and Copy Box are included with your KORLIX account. No access code is needed. Paid add-ons become available when their payment or entitlement is active.',
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
                            if (hasCodeFeatures) ...[
                              Expanded(
                                child: FilledButton.icon(style: korlixSoundButtonStyle(null),
                                  onPressed: korlixSoundAction(_customAccessLoading
                                      ? null
                                      : () => unawaited(
                                          _requestCustomAccessCode(setSheetState),
                                        )),
                                  icon: const Icon(Icons.mail_outline_rounded),
                                  label: const Text('Request a Code'),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(style: korlixSoundButtonStyle(null),
                                onPressed: korlixSoundAction(_customAccessLoading
                                    ? null
                                    : () => unawaited(
                                        _promptAndRedeemCustomAccessCode(
                                          setSheetState,
                                        ),
                                      )),
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
                          'Included tools',
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

  Future<void> _openUtilityWorkspace(String featureKey) async {
    if (_isIncludedTextWorkspace(featureKey)) {
      await _openSavedTextWorkspace(
        featureKey.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '') == 'voicescribe',
      );
      return;
    }
    if (_loading) return;
    if (_customAccessLoading) {
      return;
    }

    await _refreshCustomAccess(showErrors: true);
    if (!mounted || _customAccessMessage != null) {
      return;
    }

    if (_customAccessHasFeature(featureKey)) {
      await _openCustomAccessFeature(featureKey);
    } else {
      await _showCustomAccessSheet(refresh: false);
    }
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
          TextButton(style: korlixSoundButtonStyle(null),
            onPressed: korlixSoundAction(() => Navigator.pop(context)),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMusicStudio() async {
    final client = MusicClient(backendBaseUrl:kKorlixBackendBaseUrl,
      headersBuilder:_authHeaders,sessionChanges:kKorlixAuthRevision);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>MusicStudioScreen(
      client:client,
      ensureConsent:(context)=>KorlixThirdPartyAiConsent.ensure(context:context,
        featureName:'Music Studio',providers:{KorlixThirdPartyAiProvider.musicApiAi},
        dataCategories:{KorlixThirdPartyAiDataCategory.typedTextAndPrompts}),
      openVoice:(workingDraft) async {
        final revision = kKorlixAuthRevision.value;
        final consent = await ensureKorlixThirdPartyAiConsent(
          context: context, featureName: 'Music Studio and Rici',
          providers: const {KorlixThirdPartyAiProvider.openAi},
          dataCategories: const {
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
            KorlixThirdPartyAiDataCategory.musicDraftsAndLibrary,
          },
        );
        if (!consent || !mounted || client.sessionChanged ||
            revision != kKorlixAuthRevision.value) return null;
        final voice = MusicVoiceController(client: client, workingDraft: workingDraft);
        try {
          final route = MaterialPageRoute<Map<String, dynamic>>(builder: (_) =>
            KorlixLiveConvoTestScreen(musicVoice: voice,
              sessionChanges: kKorlixAuthRevision,
              backendBaseUrl: kKorlixBackendBaseUrl,
              headersBuilder: _authHeaders,
              characterId: normalizeKorlixCharacterId(kKorlixSelectedCharacterNotifier.value),
              language: _t.label,
            ));
          final result = await Navigator.of(context).push<Map<String, dynamic>>(route);
          await route.completed;
          return result;
        } finally {
          voice.dispose();
        }
      },
      onReport:(job,track)=>_showReportGeneratedContentSheet(contentType:'music',
        prompt:(job['settings']?['idea']??job['settings']?['lyrics']??'').toString(),
        outputSummary:'Generated music: ${track['title']??'Track'}',contentId:track['id']?.toString()),
    )));
  }


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
      if (tool == 'Inventory Studio') return 'Enterprise: find, scan and manage stock across every location with Rici';
      if (tool == 'Logo Studio') return 'Create editable logos, explore AI concepts, and download your brand kit';
      if (tool == 'Cybersecurity Defender') return 'Check suspicious messages, strengthen habits and get incident help';
      if (tool == 'Study Studio') return 'Learn with lessons, flashcards and practice quizzes';
      if (tool == 'App Studio') return 'Build, preview and export your own app';
      if (tool == 'Music Studio') return 'Create songs, save drafts and play your music library';
      if (tool == 'THE RECEIPT WIZ') return 'Free receipt scanner, smart categories and connected finance inboxes';
      if (tool == 'Tax Prep') return 'Personal tax organizer, linked Bookkeeping records and preparer packets';
      if (tool == 'BabyBlend') return 'Imagine a fictional child portrait from two adult photos with KORLIX';
      if (tool == 'FieldProof') return 'Enterprise: job photos, evidence checklists and customer handoffs with KORLIX';
      if (tool == 'AI Visibility') return 'See sampled AI answers, improve your website content and track progress';
      if (tool == 'Live Studio') return 'Create an AI-hosted show with private rehearsals and broadcast controls';
      if (tool == 'The Pod and You') return 'A podcast that listens back. Private AI conversations, up to 15 minutes';
      if (tool == 'SEO Agent') return 'Audit your website, prepare SEO drafts and monitor improvements weekly';
      if (tool == 'Virtual Closet') return 'Your private wardrobe, AI try-on, saved looks and KORLIX styling';
      if (tool == 'Contract Radar') return 'Find source-linked contracts, save opportunities and prepare bids with KORLIX';
      if (tool == 'Bookkeeping 2027') return 'Enterprise: business records, income, expenses and CSV export';
      if (tool == 'Funnel Studio') return 'Enterprise pages, lead capture and campaign links';
      if (tool == 'Payroll') return 'Enterprise US payroll, employee onboarding and payroll tax workflows';
      if (tool == 'KORLIX 2MEETU' || tool == 'Scheduling') return 'Free scheduling, booking pages, group sessions and appointments';
      if (tool == 'Business Passport') return 'Your free business page: services, photos, booking link and shareable QR';
      if (tool == 'Business Directory') return 'Find businesses and explore their public Business Passports';
      if (tool == 'AI Receptionist') return 'K-Nova answers your business calls and books appointments · Enterprise';
      if (tool == 'Workforce') return 'Your business, team tasks, shifts and Rici voice assistance';
      if (tool == 'Contacts CRM') return 'Enterprise contacts, imports and KORLIX connections';
      if (tool == 'Voice-scribe') {
        return 'Transcribe speech into saved voice boxes';
      }

      if (tool == 'Copy Box') {
        return 'Open your saved text boxes';
      }

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
                  'More tools',
                  style: TextStyle(
                    color: _korlixReadableForeground(skin),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(enableFeedback: false,
                tooltip: 'Close utilities',
                onPressed: korlixSoundAction(_loading
                    ? null
                    : () {
                        setState(() {
                          _clearUtilitySelection();
                        });
                      }),
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
              'Extra tools for writing, transcription and quick edits.',
              style: TextStyle(
                color: _korlixReadableForeground(skin, muted: true),
                fontSize: 12.4,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          KorlixActionGrid(
            children: moreHomeTools(quickActionLabels: _t.quickActions.where((a) => !_isCreditReportActionSafeUi(a)).map((a) => a.label), enterprise: _currentTier.trim().toLowerCase() == 'enterprise').map((tool) {
              final selected = selectedTool == tool;
              final status = statusFor(tool);
              final statusColor = statusColorFor(tool);

              return Tooltip(
                message: status,
                child: KorlixActionButton(
                  tile: true,
                  label: tool,
                  icon: korlixToolIcon(tool),
                  selected: selected,
                  accent: selected ? skin.success : statusColor,
                  size: KorlixButtonSize.compact,
                  onPressed: (_loading || _customAccessLoading) && !_isIncludedTextWorkspace(tool)
                      ? null
                      : () => _selectUtilityTool(tool),
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
    if (_loading || _voiceComposerOpening) return;
    final email = kKorlixUserEmail;
    final topic = _activeChatTopicId;
    bool current() => email != null && email == kKorlixUserEmail && kKorlixAccessToken != null;
    if (!current()) return;
    setState(() => _voiceComposerOpening = true);
    try {
      await _stopAiCharacterTalkingForQuery();
      if (!mounted || !current()) return;
      final draft = await Navigator.of(context).push<KorlixVoiceDraft>(MaterialPageRoute(
        builder: (_) => KorlixVoiceComposer(initialText: _controller.text,
          language: _selectedLanguage, sessionChanges: kKorlixAuthRevision, isSessionCurrent: current),
      ));
      if (!mounted || !current() || topic != _activeChatTopicId || draft == null) return;
      setState(() => _controller.value = TextEditingValue(text: draft.text, selection: TextSelection.collapsed(offset: draft.text.length)));
      if (draft.openLiveConvo) await _openLiveConvoAudioTest();
    } finally { if (mounted) setState(() => _voiceComposerOpening = false); }
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
                color: skin.glow.withOpacity(skin.isLight ? 0.04 : 0.10),
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

  Widget _buildMockupLanguageTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final language in const {'en': 'English', 'es': 'Español', 'fr': 'Français'}.entries)
          KorlixActionButton(
            label: language.value,
            selected: _selectedLanguage == language.key,
            size: KorlixButtonSize.compact,
            onPressed: _loading ? null : () => setState(() => _selectedLanguage = language.key),
          ),
      ],
    ),
  );

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
    await Share.share(
      _featuredResultShareText(item),
      subject: item.title.trim().isNotEmpty
          ? item.title.trim()
          : 'Korlix AI result',
      sharePositionOrigin: korlixShareOrigin(context),
    );
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
                  child: IconButton(enableFeedback: false,
                    onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
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
                    onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
                    style: korlixSoundButtonStyle(FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF143B4A),
                      foregroundColor: const Color(0xFFE4EBEE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )),
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
                        IconButton(enableFeedback: false,
                          onPressed: korlixSoundAction(() => Navigator.of(context).pop()),
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
                              onPressed: korlixSoundAction(() => _downloadGeneratedVideo(videoId)),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download Video'),
                              style: korlixSoundButtonStyle(FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF143B4A),
                                foregroundColor: const Color(0xFFE4EBEE),
                              )),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: korlixSoundAction(() {
                                Share.share(
                                  'I created a video with Korlix AI. Video ID: $videoId',
                                  subject: 'Korlix AI video',
                                  sharePositionOrigin: korlixShareOrigin(context),
                                );
                              }),
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Share'),
                              style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF69D9E8),
                              )),
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

  bool _locatorOpening = false;

  Future<void> _showLocatorOptions() async {
    if (_loading || _locatorOpening) return;
    final email = kKorlixUserEmail;
    bool current() => email != null && email == kKorlixUserEmail && kKorlixAccessToken != null;
    if (!current()) return;
    setState(() => _locatorOpening = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => KorlixLocatorScreen(sessionChanges: kKorlixAuthRevision, isSessionCurrent: current),
      ));
    } finally {
      if (mounted) setState(() => _locatorOpening = false);
    }
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
              style: korlixSoundButtonStyle(ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              )),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: const Text(
                'Download PDF',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: korlixSoundAction(() =>
                  _saveCreditDocFile(pdfBase64, 'credit_dispute_letter.pdf')),
            ),
          if (pdfBase64.isNotEmpty) const SizedBox(height: 8),
          if (docxBase64.isNotEmpty)
            ElevatedButton.icon(
              style: korlixSoundButtonStyle(ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              )),
              icon: const Icon(Icons.article_rounded, size: 20),
              label: const Text(
                'Download Word Doc',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: korlixSoundAction(() =>
                  _saveCreditDocFile(docxBase64, 'credit_dispute_letter.docx')),
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
      ], text: 'Credit Dispute Letter', fileNameOverrides: [fileName],
        sharePositionOrigin: korlixShareOrigin(context));
    } catch (e) {
      debugPrint('[CreditDocs] Save error: ' + e.toString());
    }
  }

  Widget _buildMockupFeaturedCharacterCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: AnimatedBuilder(
        animation: _characters,
        builder: (context, _) => Column(children: [
          KorlixCharacterOrbit(
            selectedId: kKorlixSelectedCharacterNotifier.value,
            availableIds: _characters.availableIds,
            loading: _characters.loading,
            saving: _characters.saving,
            error: _characters.error,
            onRetry: _characters.load,
            onSelected: (id) async {
              stopKorlixCharacterSpeechGlobally();
              await _characters.select(id);
            },
            previewBuilder: (character) => KorlixCharacterIntroPreview(
              key: ValueKey(character.video),
              assetPath: character.video,
              muted: true,
              showSoundButton: true,
              autoplay: !MediaQuery.disableAnimationsOf(context),
              loop: true,
              fillParent: true,
              dragSurface: true,
            ),
          ),
          if (_loading) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${korlixCharacterFor(kKorlixSelectedCharacterNotifier.value).name} is preparing your answer…'),
          ),
        ]),
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
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(false)),
                        style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE4EBEE),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        )),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(true)),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        )),
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
                      child: OutlinedButton(style: korlixSoundButtonStyle(null),
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(false)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(true)),
                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        )),
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

  Color _korlixReadableForeground(KorlixSkinPalette skin, {bool muted = false, bool hint = false}) {
    return hint ? skin.hintText : muted ? skin.mutedText : skin.text;
  }

  Color _korlixReadableToolForeground(KorlixSkinPalette skin) {
    return skin.text;
  }

  Color _korlixDefinitionBorder(KorlixSkinPalette skin, {bool secondary = false}) =>
    secondary ? skin.border : skin.primary;

  Color _korlixDefinitionShadow(KorlixSkinPalette skin) =>
    Colors.black.withValues(alpha: skin.isLight ? .07 : .22);



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

  void _setChatMode(bool imageMode, {String? starter}) {
    if (_loading) return;
    setState(() {
      _imaginePictureMode = imageMode;
      _createVideoMode = false;
      _improvePictureMode = false;
      _fixCreditReportMode = false;
      _createAppMode = false;
      _error = null;
      if (starter != null) {
        _controller.text = starter;
        _controller.selection = TextSelection.collapsed(offset: starter.length);
      }
    });
  }

  Widget _buildAnswerReadyConversationView(
    GeneratedItem? item, {required bool compact}) {
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final turns = <KorlixChatTurn>[];
    void addTurn(String id, String question, String answer, GeneratedItem? result,
        {VoidCallback? deleteQuestion, VoidCallback? deleteAnswer}) {
      final hasImage = result?.hasImageResult == true;
      turns.add(KorlixChatTurn(id: id,
        question: _korlixVisibleUserText(question), answer: _cleanDisplayText(answer),
        image: hasImage ? _buildGeneratedImagePreview(result!, height: compact ? 260 : 360) : null,
        onOpenImage: hasImage ? () => _showResult(result!) : null,
        onSaveImage: hasImage ? () => _saveGeneratedImage(result!) : null,
        onDeleteQuestion: deleteQuestion, onDeleteAnswer: deleteAnswer));
    }
    for (var index = 0; index < _chatMessages.length; index++) {
      final message = _chatMessages[index];
      if (!_answerChatMessageHasVisibleTurn(message)) continue;
      final messageIndex = index;
      addTurn('chat-$index', message.userText, message.aiText, message.generatedItem,
        deleteQuestion: () => _confirmDeleteAnswerBoxTurn(messageIndex: messageIndex, deleteUser: true),
        deleteAnswer: () => _confirmDeleteAnswerBoxTurn(messageIndex: messageIndex, deleteUser: false));
    }
    if (turns.isEmpty && item != null) {
      addTurn('result', item.command, item.content, item,
        deleteQuestion: () => _confirmDeleteLooseAnswerResultTurn(deleteUser: true),
        deleteAnswer: () => _confirmDeleteLooseAnswerResultTurn(deleteUser: false));
    }
    final busy = _loading && (_pendingChatTopicId == null || _pendingChatTopicId == _activeChatTopicId);
    return KorlixChatTimeline(key: ValueKey('chat-topic-$_activeChatTopicId'),
      languageCode: _selectedLanguage,
      turns: turns, foreground: _korlixReadableForeground(skin),
      accent: skin.primary, surface: skin.panelDeep, busy: busy,
      pendingQuestion: busy ? _pendingChatPrompt : '',
      status: _pendingChatIsImage ? KorlixChatCopy(_selectedLanguage).creatingImageStatus : KorlixChatCopy(_selectedLanguage).thinkingStatus,
      onStarter: (prompt, imageMode) => _setChatMode(imageMode, starter: prompt));
  }

  // KORLIX_LIVE_CONVO_PHASE2B_OPEN_BEGIN
  bool _liveConvoOpening = false;
  SchedulingClient? _schedulingVoiceClient;
  SchedulingVoiceController? _schedulingVoice;

  Future<void> _openLiveConvoAudioTest({bool schedulingMode = false}) async {
    if (_liveConvoOpening) return;
    _liveConvoOpening = true;
    try {
      await _openLiveConvoSession(schedulingMode: schedulingMode);
    } finally {
      _liveConvoOpening = false;
    }
  }

  Future<void> _openLiveConvoSession({required bool schedulingMode}) async {
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_LIVE_CONVO_BEGIN
    final korlixThirdPartyAiConsentGranted =
        await ensureKorlixThirdPartyAiConsent(
          context: context,
          featureName: schedulingMode ? 'KORLIX 2MEETU and Rici' : 'LIVE CONVO',
          providers: const <KorlixThirdPartyAiProvider>{
            KorlixThirdPartyAiProvider.openAi,
          },
          dataCategories: const <KorlixThirdPartyAiDataCategory>{
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
            KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
            KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
          },
        );

    if (!korlixThirdPartyAiConsentGranted) {
      return;
    }
    // KORLIX_AI_CONSENT_GATE_BUILD131_V1_LIVE_CONVO_END

    final token = kKorlixAccessToken?.trim() ?? '';

    if (token.isEmpty) {
      await _showKorlixNotice(
        title: 'Sign in required',
        message: 'Please sign in before starting LIVE CONVO.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    // Retain an unresolved approved-write receipt across voice routes for the
    // same account. Client account changes erase it; home disposal releases it.
    if (_schedulingVoice?.available != true) {
      _schedulingVoice?.dispose();
      _schedulingVoiceClient?.dispose();
      _schedulingVoiceClient = SchedulingClient(
        baseUrl: kKorlixBackendBaseUrl,
        headersBuilder: _authHeaders,
        sessionChanges: kKorlixAuthRevision,
      );
      _schedulingVoice = SchedulingVoiceController(_schedulingVoiceClient!);
    }
    final schedulingVoice = _schedulingVoice!;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => KorlixLiveConvoTestScreen(
            schedulingVoice: schedulingVoice,
            schedulingMode: schedulingMode,
            sessionChanges: kKorlixAuthRevision,
            backendBaseUrl: kKorlixBackendBaseUrl,
            headersBuilder: _authHeaders,
            characterId: normalizeKorlixCharacterId(
              kKorlixSelectedCharacterNotifier.value,
            ),
            language: _t.label,
            meetingCopilotEnterpriseEnabled:
                korlixMeetingCopilotEnterpriseEnabled(_currentTier),
          ),
        ),
      );
    } finally {
      schedulingVoice.clearPending();
    }
  }
  // KORLIX_LIVE_CONVO_PHASE2B_OPEN_END

  Widget _buildCommandPanel() {
    // K135Z_B4B_V11_GENERAL_COMMAND_ENTRY_REMOVED
    final t = _t;
    final skin = korlixSkinPaletteFor(kKorlixThemeNotifier.value);
    final hasText = _controller.text.trim().isNotEmpty;

    final canSubmit = _fixCreditReportMode
        ? (hasText && _activeUploadFiles.isNotEmpty)
        : hasText;

    final chatCopy = KorlixChatCopy(_selectedLanguage);
    final hintText = _imaginePictureMode ? chatCopy.imageHint : chatCopy.textHint;

    final GeneratedItem? activeResult =
        (_results.isNotEmpty && !_featuredAnswerDismissed)
        ? _results.first
        : null;

    Widget tile(String label, IconData icon, VoidCallback? onPressed, {String? subtitle, bool? selected, bool locked = false}) => KorlixActionButton(
      label: label, icon: icon, onPressed: onPressed, subtitle: subtitle,
      tile: true, selected: selected, locked: locked,
    );
    Widget toolTile(String label) => label == 'Contacts CRM'
      ? KorlixActionButton(
          key: const ValueKey('home-crm'), label: 'CRM',
          colorIdentity: 'Contacts CRM', icon: Icons.contact_page_outlined,
          subtitle: 'Contacts & follow-ups', tile: true,
          onPressed: _openContactsCrm,
        )
      : tile(label, korlixToolIcon(label),
          (_loading || _customAccessLoading) && label != 'THE RECEIPT WIZ' && !_isIncludedTextWorkspace(label)
            ? null : () => _selectUtilityTool(label));
    bool businessAction(QuickAction action) => const {
      'create an app', 'email enhancer', 'negocios', 'crear plan', 'ideas de contenido', 'idées contenu',
    }.contains(action.label.toLowerCase());
    final quickActions = _homeQuickActions;

    Widget answerReadyBody() => _buildAnswerReadyConversationView(
      activeResult, compact: MediaQuery.sizeOf(context).width < 430);

    Widget answerReadyPanel() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: null,
        onLongPress: null,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(31),
            border: Border.all(
              color: _korlixDefinitionBorder(
                skin,
              ).withValues(alpha: skin.isLight ? 0.72 : 0.96),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _korlixDefinitionShadow(skin),
                blurRadius: 16,
                spreadRadius: 0,
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
              width: 1.3,
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
                color: Colors.black.withOpacity(skin.isLight ? .06 : .32),
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
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: inputHintColor.withOpacity(0.96),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w400,
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
              KorlixActionButton(
                label: _loading ? chatCopy.sending : chatCopy.send,
                colorIdentity: 'Send',
                icon: Icons.arrow_upward_rounded,
                iconOnly: true,
                busy: _loading,
                onPressed: (_loading || !canSubmit) ? null : _generate,
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
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(skin.isLight ? .06 : .20),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KorlixChatModeBar(imageMode: _imaginePictureMode, busy: _loading,
                  languageCode: _selectedLanguage,
                  size: _chatImageSize, style: _chatImageStyle,
                  onModeChanged: _setChatMode,
                  onSizeChanged: (value) => setState(() => _chatImageSize = value),
                  onStyleChanged: (value) => setState(() => _chatImageStyle = value)),
                const SizedBox(height: 12),
                singleInputBoard(),
                if (_imaginePictureMode) ...[
                  const SizedBox(height: 10),
                  KorlixActionButton(label: chatCopy.openImagineStudio,
                    colorIdentity: 'Open Imagine Studio',
                    subtitle: chatCopy.imagineStudioSubtitle,
                    icon: Icons.auto_awesome_mosaic_rounded, expand: true,
                    onPressed: _loading ? null : _openImagineStudio),
                ],
                if (!_imaginePictureMode) ...[
                  const SizedBox(height: 10),
                  ChatMemoryButton(client: _chatMemory, onPressed: _loading ? null : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ChatMemoryScreen(client: _chatMemory)));
                    if (mounted) unawaited(_chatMemory.load());
                  }),
                ],

                SizedBox(height: 12),

                // KORLIX_LIVE_CONVO_HERO_HOME_SLOT_BUILD131_BEGIN
                KorlixLiveConvoButton(
                  onPressed: _loading ? null : _openLiveConvoAudioTest,
                ),
                const SizedBox(height: 14),
                // KORLIX_LIVE_CONVO_HERO_HOME_SLOT_BUILD131_END
                KorlixActionSection(
                  title: 'Start here', description: 'Choose how you want to work with Rici.',
                  icon: Icons.tune_rounded,
                  children: [
                    tile('Upload', Icons.upload_file_rounded,
                      _loading || _uploadOpening ? null : _handleUploadPressed,
                      subtitle: _activeUploadFiles.isEmpty ? 'Files & photos' : '${_activeUploadFiles.length} files attached',
                      selected: _activeUploadFiles.isEmpty ? null : true,
                      locked: !_hasDocumentUploadAccess),
                    tile('Voice', Icons.mic_rounded,
                      _loading || _voiceComposerOpening ? null : _handleVoiceInput,
                      subtitle: 'Speak or type', locked: !_hasVoiceAccess),
                    tile('Camera Ask', Icons.center_focus_strong_rounded,
                      _loading || _cameraAskOpening ? null : _capturePhotoAndAskShortcut,
                      subtitle: 'See it. Ask it.'),
                    tile('More tools', Icons.apps_rounded, _loading ? null : _toggleUtilityPanel,
                      subtitle: 'Open the toolbox', selected: _utilityPanelOpen),
                  ],
                ),
                if (_activeUploadFiles.isNotEmpty) ...[
                  const SizedBox(height: 16), _buildSelectedUploadFilesPanel(),
                ],
                if (_utilityPanelOpen) ...[
                  const SizedBox(height: 16), _buildUtilityPanel(),
                ],
                const SizedBox(height: 30),
                KorlixActionSection(
                  title: 'For business', description: 'Manage operations, grow your reach, and get work done.',
                  icon: Icons.business_center_outlined,
                  children: [
                    for (final tool in homeBusinessTools) toolTile(tool),
                    if (_currentTier.trim().toLowerCase() == 'enterprise') ...[
                      for (final tool in homeEnterpriseTools) toolTile(tool),
                    ],
                    for (final action in quickActions.where(businessAction)) _buildSafeUiQuickActionChip(action, tile: true),
                  ],
                ),
                const SizedBox(height: 30),
                KorlixActionSection(
                  title: 'For personal use', description: 'Create, learn, organize, and explore your everyday life.',
                  icon: Icons.person_outline_rounded,
                  children: [
                    AnimatedBuilder(
                      animation: _socialNotifications,
                      builder: (context, _) => tile('KORLIX Social',
                        _socialNotifications.totalUnread > 0
                          ? Icons.mark_chat_unread_rounded : Icons.people_outline_rounded,
                        () => _openKorlixSocial(),
                        subtitle: _socialNotifications.totalUnread > 0
                          ? '${_socialNotifications.countLabel} unread messages'
                          : 'People, messages & forums'),
                    ),
                    for (final tool in homePersonalTools) toolTile(tool),
                    for (final action in quickActions.where((a) => !businessAction(a))) _buildSafeUiQuickActionChip(action, tile: true),
                    tile('Music Studio', Icons.library_music_rounded, _loading ? null : _showMusicStudio),
                    tile('Locator', Icons.location_on_outlined, _loading ? null : _showLocatorOptions),
                    if (kKorlixMusicDistributionPrelaunchVisible) tile('Music Distribution', Icons.public_rounded, _loading ? null : _showMusicDistribution),
                  ],
                ),
                if (_currentTier == 'basic' && !kKorlixHideTipDeveloperOnIos) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(style: korlixSoundButtonStyle(null), icon: const Icon(Icons.favorite_outline_rounded), label: const Text('Tip the developer'), onPressed: korlixSoundAction(_loading ? null : _openDonateCashApp)),
                ],

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
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
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
                      child: OutlinedButton(style: korlixSoundButtonStyle(null),
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(false)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: korlixSoundAction(() => Navigator.of(context).pop(true)),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: korlixSoundButtonStyle(FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        )),
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

  Widget _buildSavedTopicsMenuButton() => CompositedTransformTarget(
    link: _savedTopicsMenuLayerLink,
    child: KorlixActionButton(
      label: 'Saved conversations',
      icon: Icons.menu_rounded,
      iconOnly: true,
      selected: _showSavedTopicsPanel,
      onPressed: _toggleSavedTopicsPanel,
    ),
  );

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
        fileNameOverrides: [filename],
        sharePositionOrigin: korlixShareOrigin(context),
      );
    } catch (_) {
      await Share.share(
        exportText,
        subject: 'Korlix AI chat export: ${topic.title}',
        sharePositionOrigin: korlixShareOrigin(context),
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
                    onPressed: korlixSoundAction(() => Navigator.of(sheetContext).pop()),
                    style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF69D9E8),
                      side: BorderSide(
                        color: const Color(0xFF69D9E8).withValues(alpha: 0.42),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )),
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
              IconButton(enableFeedback: false,
                onPressed: korlixSoundAction(() => _submitRenameSavedTopic(topic.id)),
                icon: Icon(Icons.check_rounded, color: skin.primary),
              ),
              IconButton(enableFeedback: false,
                onPressed: korlixSoundAction(_cancelRenameSavedTopic),
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

  Future<void> _applyThemeShortcut({required String theme, String? screenSkin}) async {
    final previous = kKorlixThemeNotifier.value;
    final choice = KorlixAppearanceChoice(theme, screenSkin ?? kKorlixScreenSkinNotifier.value);
    final saving = kKorlixAppearancePreferences.apply(choice);
    if (mounted) {
      setState(() {});
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('${korlixThemeLabelFor(choice.themeId)} · ${korlixScreenSkinLabel(choice.skinId)} applied')));
    }
    final saved = await saving;
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Look applied for this session. Device storage could not save it.')));
    }
    // New looks are stored on this device. Retain the existing remote sync only
    // for IDs accepted by the current backend, without changing account policy.
    const remoteThemes = {'korlix_blue', 'matrix_green', 'ultra_gold', 'dark_crimson'};
    if (previous == choice.themeId || !remoteThemes.contains(choice.themeId) || kKorlixThemeNotifier.value != choice.themeId) return;
    try {
      await http.post(_assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/theme/set'),
        headers: KorlixDeviceStore.headers(), body: jsonEncode({'theme': choice.themeId}))
        .timeout(const Duration(seconds: 10));
    } catch (_) { /* The saved local appearance remains usable while offline. */ }
  }

  Widget _buildThemeShortcutCircles() {
    Future<void> openAppearance(int tab) async {
      final selected = await showKorlixAppearancePicker(context, initialTab: tab);
      if (selected != null && mounted) await _applyThemeShortcut(theme: selected.themeId, screenSkin: selected.skinId);
    }
    return ValueListenableBuilder<String>(valueListenable: kKorlixThemeNotifier,
      builder: (context, theme, _) => Padding(padding: const EdgeInsets.fromLTRB(22, 10, 22, 2),
        child: KorlixThemeShortcuts(selectedId: theme,
          onSelect: (id) => unawaited(_applyThemeShortcut(theme: id)),
          onPreview: () => openAppearance(0), onSkins: () => openAppearance(1))));
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
    required Map<String, String> headers,
    String? contentId,
  }) async {
    try {
      await submitKorlixAiReport(
        endpoint: _assertValidKorlixBackendUri('$kKorlixBackendBaseUrl/api/report-output'),
        headers: headers,
        contentType: contentType,
        appArea: 'google_play_ai_generated_content_report',
        prompt: prompt,
        outputSummary: outputSummary,
        reason: reason,
        details: details,
        contentId: contentId,
        language: _selectedLanguage,
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showGooglePlayAiReportSheet({
    required String contentType,
    required String prompt,
    required String outputSummary,
    String? contentId,
  }) async {
    if (!mounted || _aiOutputReportBusy) return;
    final revision = kKorlixAuthRevision.value;
    final token = kKorlixAccessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to submit a report.')),
      );
      return;
    }
    final headers = Map<String, String>.from(_authHeaders());
    bool current() => mounted && revision == kKorlixAuthRevision.value &&
        token == kKorlixAccessToken;
    _aiOutputReportBusy = true;
    var sheetSubmitted = false;
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
                          maxLength: 1000,
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
                                onPressed: korlixSoundAction(() =>
                                    Navigator.of(sheetContext).pop()),
                                style: korlixSoundButtonStyle(OutlinedButton.styleFrom(
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
                                )),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: korlixSoundAction(() {
                                  if (sheetSubmitted) return;
                                  sheetSubmitted = true;
                                  Navigator.of(
                                    sheetContext,
                                  ).pop(<String, String>{
                                    'reason': selectedReason,
                                    'details': detailsController.text.trim(),
                                  });
                                }),
                                icon: const Icon(Icons.flag_rounded),
                                label: const Text('Submit'),
                                style: korlixSoundButtonStyle(FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                )),
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

      if (result == null || !current()) {
        return;
      }

      final sent = await _submitGooglePlayAiReport(
        headers: headers,
        contentType: contentType,
        prompt: prompt,
        outputSummary: outputSummary,
        reason: result['reason'] ?? 'Other',
        details: result['details'] ?? '',
        contentId: contentId,
      );

      if (!current()) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Report submitted. Thank you for helping improve Korlix AI safety.'
                : 'We could not confirm whether your report was received. It may already be saved. Contact support@korlixdeveloper.com before submitting it again.',
          ),
        ),
      );
    } finally {
      detailsController.dispose();
      _aiOutputReportBusy = false;
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
        onPressed: korlixSoundAction(() => _showGooglePlayAiReportSheet(
          contentType: contentType,
          prompt: prompt,
          outputSummary: outputSummary,
          contentId: contentId,
        )),
        icon: const Icon(Icons.flag_outlined, size: 17),
        label: const Text('Report AI Output'),
        style: korlixSoundButtonStyle(TextButton.styleFrom(
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
        )),
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
            IconButton(enableFeedback: false,
              onPressed: korlixSoundAction(() => setState(() => _chatMinimized = !_chatMinimized)),
              tooltip: _chatMinimized ? 'Maximize chat' : 'Minimize chat',
              icon: Icon(
                _chatMinimized
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                color: const Color(0xFF2EC7DF),
                size: 22,
              ),
            ),
            TextButton.icon(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(() async {
                await _clearAllResults();
                setState(() {
                  _chatMessages.clear();
                });
              }),
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
                  child: IconButton(enableFeedback: false,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: isMinimized
                        ? 'Maximize message'
                        : 'Minimize message',
                    onPressed: korlixSoundAction(() => setState(() {
                      if (isMinimized) {
                        _minimizedMessages.remove(index);
                      } else {
                        _minimizedMessages.add(index);
                      }
                    })),
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
                  child: IconButton(enableFeedback: false,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove message',
                    onPressed: korlixSoundAction(() =>
                        setState(() => _deletedMessages.add(index))),
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
                        onTap: () => Share.share(msg.aiText,
                          sharePositionOrigin: korlixShareOrigin(context)),
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
                                  TextButton(style: korlixSoundButtonStyle(null),
                                    onPressed: korlixSoundAction(() => Navigator.pop(ctx)),
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
  }) => KorlixActionButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: KorlixButtonSize.compact,
  );

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
              FilledButton(style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(() => _showResult(item)),
                child: Text(language.open),
              ),
              if (isImage) ...[
                OutlinedButton.icon(style: korlixSoundButtonStyle(null),
                  onPressed: korlixSoundAction(() => _saveGeneratedImage(item)),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Save'),
                ),
                OutlinedButton.icon(style: korlixSoundButtonStyle(null),
                  onPressed: korlixSoundAction(() => _shareGeneratedImage(item)),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ] else ...[
                OutlinedButton(style: korlixSoundButtonStyle(null),
                  onPressed: korlixSoundAction(() => _copyResultText(item)),
                  child: Text(language.copy),
                ),
                if (item.allowPdf)
                  OutlinedButton(style: korlixSoundButtonStyle(null),
                    onPressed: korlixSoundAction(() => _exportPdf(item)),
                    child: Text(language.pdf),
                  ),
              ],
              TextButton(style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(() => _deleteResult(item)),
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
        height: MediaQuery.sizeOf(context).width < 430 ? 410 : 500,
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
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
    if (skin.isPureWhite) {
      canvas.drawPath(outer, Paint()..color = Colors.white);
      _strokeSolid(canvas, outer, skin.border, 1.2, .7);
      _strokeSolid(canvas, middle, skin.border, .8, .3);
      return;
    }


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
                              FilledButton.icon(style: korlixSoundButtonStyle(null),
                                onPressed: korlixSoundAction(_playWizard),
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
                            FilledButton(style: korlixSoundButtonStyle(null),
                              onPressed: korlixSoundAction(_loadWizardVideo),
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
            FilledButton.icon(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(controller == null ? null : _replayWizard),
              icon: const Icon(Icons.replay),
              label: Text(current.replayGreeting),
            ),
            OutlinedButton.icon(style: korlixSoundButtonStyle(null),
              onPressed: korlixSoundAction(_loadWizardVideo),
              icon: const Icon(Icons.refresh),
              label: Text(current.reloadWizard),
            ),
          ],
        ),
      ],
    );
  }
}

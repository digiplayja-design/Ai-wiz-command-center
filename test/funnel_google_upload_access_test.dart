import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_upload_access.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'funnel_conversion_intake_test.dart' as intake;
import 'funnel_google_destination_test.dart' as dest;

const aid = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> authorization() {
  final u = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': 'fixture-google-client.apps.googleusercontent.com',
    'redirect_uri':
        'https://example.com/api/funnels/google-upload-access/callback',
    'response_type': 'code',
    'scope':
        'https://www.googleapis.com/auth/adwords https://www.googleapis.com/auth/datamanager',
    'access_type': 'offline',
    'prompt': 'consent select_account',
    'state': '$aid.${'a' * 43}',
    'code_challenge': 'b' * 43,
    'code_challenge_method': 'S256',
  });
  return {
    'source': 'google_upload_authorization',
    'id': aid,
    'proof': 'p' * 43,
    'authorization_url': u.toString(),
    'expires_in': 600,
  };
}

Map<String, dynamic> state({
  bool connected = false,
  bool ready = true,
  bool configured = true,
  String? phase,
  bool pendingCurrent = true,
}) => {
  'source': 'google_upload_access',
  'funnel_id': intake.fid,
  'campaign_id': intake.cid,
  'campaign_name': 'Autumn campaign',
  'configured': configured,
  'destination_current': ready,
  'can_authorize': ready && configured,
  'version': connected ? 1 : 0,
  'fingerprint': 'c' * 64,
  'authorization': connected
      ? {
          'account': dest.context()['account'],
          'root_id': '1234567890',
          'login_customer_id': null,
          'connected_at': '2026-09-24T12:00:00Z',
          'checked_at': '2026-09-24T12:00:01Z',
          'needs_reconnect': false,
          'current': ready && configured,
        }
      : null,
  'pending': phase == null
      ? null
      : {
          'id': aid,
          'phase': phase,
          'expires_at': '2026-09-24T12:10:00Z',
          'current': pendingCurrent && ready && configured,
        },
  'scope_set': 'ads_datamanager_v1',
  'delivery_state': 'not_implemented',
  'send_ready': false,
  'provider_verified': false,
};
Future<void> app(
  WidgetTester t,
  FunnelClient c, {
  ValueNotifier<int>? scope,
  Future<bool> Function(Uri)? openUrl,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: FunnelGoogleUploadAccess(
            client: c,
            funnelId: intake.fid,
            campaignId: intake.cid,
            scope: scope,
            openUrl: openUrl,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) => intake.tap(t, label);
const consent =
    'I want to authorize Google Ads and Data Manager access for future inquiry conversion uploads.';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      final f = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (f.existsSync()) {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(await f.readAsBytes())),
            ))
            .load();
      }
    }
  });
  test(
    'K191 strict access contract rejects cross-scope, unknown states and upload-readiness claims',
    () {
      for (final d in [
        state(),
        state(connected: true),
        state(connected: true, ready: false),
        state(configured: false),
        state(phase: 'ready'),
      ]) {
        validateGoogleUploadAccess(d, intake.fid, intake.cid);
      }
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['campaign_id'] = 'other',
        (d) => d['send_ready'] = true,
        (d) => d['provider_verified'] = true,
        (d) => d['scope_set'] = 'ads_only',
        (d) => d['delivery_state'] = 'accepted',
        (d) => d['version'] = 0,
        (d) => d['authorization']['account']['test_account'] = true,
        (d) => d['authorization']['login_customer_id'] = '9999999999',
        (d) => d['authorization']['needs_reconnect'] = true,
        (d) => d['can_authorize'] = false,
      ]) {
        final d = state(connected: true);
        change(d);
        expect(
          () => validateGoogleUploadAccess(d, intake.fid, intake.cid),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final patch in <void Function(Map<String, dynamic>)>[
        (d) => d['pending']['phase'] = 'connected',
        (d) => d['pending']['id'] = 'bad',
        (d) => d['pending']['expires_at'] = 'infinity',
      ]) {
        final d = state(phase: 'ready');
        patch(d);
        expect(
          () => validateGoogleUploadAccess(d, intake.fid, intake.cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  test(
    'K191 authorization URL rejects wrong host, callback, scopes, state, duplicate keys and missing PKCE',
    () {
      validateGoogleUploadAuthorization(authorization());
      for (final q in [
        {'scope': 'https://www.googleapis.com/auth/adwords'},
        {'redirect_uri': 'https://example.com/api/funnels/google-ads/callback'},
        {'code_challenge_method': 'plain'},
        {'state': '$aid.bad'},
        {'response_type': 'token'},
        {'client_secret': 'private'},
      ]) {
        final a = authorization(), u = Uri.parse(a['authorization_url']);
        a['authorization_url'] = u
            .replace(queryParameters: {...u.queryParameters, ...q})
            .toString();
        expect(
          () => validateGoogleUploadAuthorization(a),
          throwsA(isA<FunnelException>()),
        );
      }
      for (final value in [
        'https://evil.example/o/oauth2/v2/auth',
        '${authorization()['authorization_url']}&scope=extra',
        '${authorization()['authorization_url']}#fragment',
      ]) {
        final a = authorization()..['authorization_url'] = value;
        expect(
          () => validateGoogleUploadAuthorization(a),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  testWidgets(
    'K191 initial view reads only and disabled setup cannot authorize',
    (t) async {
      final seen = <http.Request>[];
      await app(
        t,
        intake.client((r) async {
          seen.add(r);
          return intake.reply(state(configured: false));
        }),
      );
      expect(seen.single.method, 'GET');
      expect(find.text(googleUploadBoundary), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start upload authorization'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Continue to Google'), findsNothing);
      expect(
        find.text('Google upload authorization is awaiting platform setup.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K191 sign-in is explicit, stays in memory, launches on tap and finishes with original proof',
    (t) async {
      final seen = <http.Request>[], opened = <Uri>[];
      String? phase;
      var connected = false;
      await app(
        t,
        intake.client((r) async {
          seen.add(r);
          if (r.url.path.endsWith('/begin')) {
            phase = 'waiting';
            return intake.reply(authorization());
          }
          if (r.url.path.endsWith('/finish')) {
            phase = null;
            connected = true;
          }
          return intake.reply(state(phase: phase, connected: connected));
        }),
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      );
      await tap(t, consent);
      await tap(t, 'Start upload authorization');
      expect(opened, isEmpty);
      expect(jsonDecode(seen.firstWhere((r) => r.method == 'POST').body), {
        'version': 0,
        'fingerprint': 'c' * 64,
        'confirmed': true,
      });
      await tap(t, 'Continue to Google');
      expect(opened.length, 1);
      expect(opened.single.host, 'accounts.google.com');
      await tap(t, 'Finish upload authorization');
      expect(jsonDecode(seen.last.body), {
        'id': aid,
        'proof': 'p' * 43,
        'confirmed': true,
      });
      expect(
        find.text(
          'Google upload permission saved. Inquiry uploads remain off.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue to Google'), findsNothing);
      expect(find.text('Finish upload authorization'), findsNothing);
      expect(
        seen.every((r) => r.url.path.contains('google-upload-access')),
        isTrue,
      );
    },
  );
  testWidgets(
    'K191 early Finish preserves proof only while a fresh read says the same attempt is unclaimed',
    (t) async {
      String? phase;
      var ready = false, connected = false, finishes = 0;
      await app(
        t,
        intake.client((r) async {
          if (r.url.path.endsWith('/begin')) {
            phase = 'waiting';
            return intake.reply(authorization());
          }
          if (r.url.path.endsWith('/finish')) {
            finishes++;
            if (!ready) {
              return intake.reply({
                'error': 'Complete Google sign-in first.',
              }, 409);
            }
            connected = true;
            phase = null;
          }
          return intake.reply(state(phase: phase, connected: connected));
        }),
      );
      await tap(t, consent);
      await tap(t, 'Start upload authorization');
      await tap(t, 'Finish upload authorization');
      expect(finishes, 1);
      expect(find.text('Finish upload authorization'), findsOneWidget);
      ready = true;
      await tap(t, 'Finish upload authorization');
      expect(finishes, 2);
      expect(
        find.text(
          'Google upload permission saved. Inquiry uploads remain off.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K191 uncertain claimed finish cannot be retried and fresh state is visible',
    (t) async {
      String? phase;
      var finishes = 0;
      await app(
        t,
        intake.client((r) async {
          if (r.url.path.endsWith('/begin')) {
            phase = 'waiting';
            return intake.reply(authorization());
          }
          if (r.url.path.endsWith('/finish')) {
            finishes++;
            phase = 'verifying';
            return intake.reply({'error': 'Connection interrupted.'}, 503);
          }
          return intake.reply(state(phase: phase));
        }),
      );
      await tap(t, consent);
      await tap(t, 'Start upload authorization');
      await tap(t, 'Finish upload authorization');
      expect(finishes, 1);
      expect(find.text('Finish upload authorization'), findsNothing);
      expect(find.text('Continue to Google'), findsNothing);
      expect(
        find.text(
          'Account checks are in progress. Refresh to see the result; do not start another sign-in yet.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K191 removed or stale pending attempt erases the original-window proof',
    (t) async {
      String? phase;
      var current = true;
      await app(
        t,
        intake.client((r) async {
          if (r.url.path.endsWith('/begin')) {
            phase = 'waiting';
            return intake.reply(authorization());
          }
          return intake.reply(state(phase: phase, pendingCurrent: current));
        }),
      );
      await tap(t, consent);
      await tap(t, 'Start upload authorization');
      current = false;
      await tap(t, 'Refresh upload access');
      expect(find.text('Finish upload authorization'), findsNothing);
      expect(find.text('Continue to Google'), findsNothing);
    },
  );
  testWidgets(
    'K191 stale access can be removed locally with explicit all-campaign confirmation',
    (t) async {
      final seen = <http.Request>[];
      await app(
        t,
        intake.client((r) async {
          seen.add(r);
          return intake.reply(
            state(
              connected: r.method != 'POST',
              ready: false,
              configured: false,
            ),
          );
        }),
      );
      expect(find.text('Saved upload permission needs review'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove upload access'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Remove Google upload access for all my campaigns.');
      await tap(t, 'Remove upload access');
      expect(seen.length, 2);
      expect(seen.last.url.path.endsWith('/disconnect'), isTrue);
      expect(jsonDecode(seen.last.body), {
        'version': 1,
        'fingerprint': 'c' * 64,
        'confirmed': true,
      });
      expect(
        find.text('Google upload access removed from KORLIX.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K191 workspace loss suppresses a delayed OAuth result and no window opens',
    (t) async {
      final wait = Completer<http.Response>(), scope = ValueNotifier(0);
      addTearDown(scope.dispose);
      var opened = 0;
      await app(
        t,
        intake.client(
          (r) async => r.method == 'POST' ? wait.future : intake.reply(state()),
        ),
        scope: scope,
        openUrl: (_) async {
          opened++;
          return true;
        },
      );
      await tap(t, consent);
      await t.ensureVisible(find.text('Start upload authorization'));
      await t.tap(find.text('Start upload authorization'));
      await t.pump();
      scope.value++;
      await t.pumpAndSettle();
      wait.complete(intake.reply(authorization()));
      await t.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Continue to Google'), findsNothing);
      expect(find.text('Autumn campaign'), findsNothing);
      expect(
        find.text(
          'Your workspace changed. Close upload access and open it again.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('K191 denial clears access details and pending actions', (
    t,
  ) async {
    var deny = false;
    await app(
      t,
      intake.client(
        (_) async => deny
            ? intake.reply({'error': 'Denied'}, 403)
            : intake.reply(state(connected: true)),
      ),
    );
    deny = true;
    await tap(t, 'Refresh upload access');
    expect(
      find.text('Sign in with Enterprise access to view Google upload access.'),
      findsOneWidget,
    );
    expect(find.text('Autumn campaign'), findsNothing);
    expect(find.text('Remove upload access'), findsNothing);
  });
  testWidgets('K191 destination screen opens upload access with a local read', (
    t,
  ) async {
    final seen = <http.Request>[];
    await dest.app(
      t,
      intake.client((r) async {
        seen.add(r);
        return intake.reply(
          r.url.path.endsWith('/google-upload-access')
              ? state()
              : dest.state(saved: true),
        );
      }),
    );
    await tap(t, 'Google upload access');
    expect(seen.length, 2);
    expect(seen.every((r) => r.method == 'GET'), isTrue);
    expect(find.text(googleUploadBoundary), findsOneWidget);
  });
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('K191 upload access real-font layout at $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await app(
        t,
        intake.client(
          (_) async => intake.reply(state(connected: true, phase: 'ready')),
        ),
        scale: width == 320 ? 1.3 : 1,
      );
      await t.ensureVisible(find.text('Start upload authorization'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Remove upload access'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}

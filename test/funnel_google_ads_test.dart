import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_ads.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const root = '1234567890', account = '9876543210';
const attempt = '12345678-1234-4123-8123-123456789012';
final proof = 'a' * 43;
Map<String, dynamic> connected({
  bool loaded = true,
  bool reconnect = false,
  int version = 3,
}) => {
  'configured': true,
  'connection': {
    'version': version,
    'needs_reconnect': reconnect,
    'roots': [root],
    'root_id': loaded ? root : null,
    'root_name': loaded ? 'KORLIX Manager' : null,
    'login_customer_id': loaded ? root : null,
    'selected_account': null,
    'accounts': loaded
        ? [
            {
              'id': account,
              'name': 'KORLIX Growth',
              'currency': 'USD',
              'timezone': 'America/New_York',
              'status': 'ENABLED',
              'manager': false,
              'test_account': false,
            },
          ]
        : [],
  },
};
http.Response response(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<FunnelClient> mount(
  WidgetTester t,
  Future<http.Response> Function(http.Request) handler, {
  Future<bool> Function(Uri)? open,
  GlobalKey? capture,
  bool settle = true,
}) async {
  final client = FunnelClient(
    backendBaseUrl: 'https://example.com',
    headersBuilder: () => {},
    client: MockClient(handler),
  );
  addTearDown(client.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: WfStyle.theme,
      home: Scaffold(
        body: RepaintBoundary(
          key: capture,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FunnelGoogleAdsConnection(client: client, openUrl: open),
          ),
        ),
      ),
    ),
  );
  if (settle) await t.pumpAndSettle();
  return client;
}

Map<String, dynamic> beginBody([
  String url = 'https://accounts.google.com/o/oauth2/v2/auth?state=opaque',
]) => {'id': attempt, 'proof': proof, 'authorization_url': url};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (sdk != null) {
      for (final f in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$sdk/bin/cache/artifacts/material_fonts/$f');
        if (file.existsSync()) {
          await (FontLoader(
                f.startsWith('Material') ? 'MaterialIcons' : 'Roboto',
              )..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Google OAuth, manager browsing, selection and confirmed disconnect fit $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final calls = <http.Request>[], opened = <Uri>[];
        final capture = GlobalKey();
        var state = <String, dynamic>{'configured': true, 'connection': null};
        await mount(
          t,
          (r) async {
            calls.add(r);
            if (r.url.path.endsWith('/begin')) return response(beginBody());
            if (r.url.path.endsWith('/finish')) {
              state = connected(loaded: false, version: 1);
            }
            if (r.url.path.endsWith('/roots')) {
              state = connected(loaded: false, version: 2);
            }
            if (r.url.path.endsWith('/accounts')) state = connected();
            if (r.url.path.endsWith('/select')) {
              state = connected(version: 4);
              state['connection']['selected_account'] = account;
            }
            if (r.url.path.endsWith('/disconnect')) {
              state = {'configured': true, 'connection': null};
            }
            return response(state);
          },
          open: (u) async {
            opened.add(u);
            return true;
          },
          capture: capture,
        );
        await tap(t, 'Connect Google Ads');
        expect(opened, isEmpty);
        await tap(t, 'Continue to Google');
        expect(opened.single.host, 'accounts.google.com');
        await tap(t, 'Finish Google connection');
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/finish')).body,
          ),
          {'id': attempt, 'proof': proof},
        );
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/roots')).body,
          ),
          {'version': 1},
        );
        await tap(t, 'Load Google accounts');
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/accounts')).body,
          ),
          {'root_id': root, 'version': 2},
        );
        expect(find.text('KORLIX Growth'), findsOneWidget);
        await tap(t, 'Use Google account');
        expect(find.text('Selected Google account'), findsOneWidget);
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/select')).body,
          ),
          {'root_id': root, 'account_id': account, 'version': 3},
        );
        expect(t.takeException(), isNull);
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          await t.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1.5);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '/tmp/k158-google-${width.toInt()}.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tap(t, 'Disconnect Google');
        await tap(t, 'Keep Google connection');
        expect(calls.where((r) => r.url.path.endsWith('/disconnect')), isEmpty);
        await tap(t, 'Disconnect Google');
        await tap(t, 'Disconnect Google Ads');
        expect(jsonDecode(calls.last.body), {'confirmed': true, 'version': 4});
        expect(find.text('Ready to connect'), findsOneWidget);
        expect(find.text('KORLIX Growth'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Platform setup pending disables authorization without hiding campaign workspace',
    (t) async {
      var calls = 0;
      await mount(t, (r) async {
        calls++;
        return response({'configured': false, 'connection': null});
      });
      expect(find.text('Setup pending'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Connect Google Ads'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('view and manage Ads data'), findsOneWidget);
      expect(calls, 1);
    },
  );
  testWidgets(
    'Reconnect can open Google even while the old connection is expired',
    (t) async {
      var opens = 0;
      await mount(
        t,
        (r) async => response(
          r.url.path.endsWith('/begin')
              ? beginBody()
              : connected(reconnect: true),
        ),
        open: (u) async {
          opens++;
          return true;
        },
      );
      expect(find.text('Reconnect needed'), findsOneWidget);
      expect(find.text('Use Google account'), findsNothing);
      await tap(t, 'Reconnect Google Ads');
      await tap(t, 'Continue to Google');
      expect(opens, 1);
    },
  );
  testWidgets(
    'Pending sign-in after a page reload explains original-window proof recovery',
    (t) async {
      await mount(
        t,
        (r) async => response({
          'configured': true,
          'pending': {'phase': 'ready'},
        }),
      );
      expect(find.textContaining('original window'), findsOneWidget);
      expect(find.text('Finish Google connection'), findsNothing);
    },
  );
  testWidgets(
    'Wrong Google host, path, port and user info cannot be launched',
    (t) async {
      for (final url in [
        'https://evil.example/signin',
        'https://accounts.google.com/other',
        'https://accounts.google.com:444/o/oauth2/v2/auth',
        'https://user@accounts.google.com/o/oauth2/v2/auth',
      ]) {
        await mount(
          t,
          (r) async => response(
            r.url.path.endsWith('/begin')
                ? beginBody(url)
                : {'configured': true},
          ),
          open: (u) async => throw StateError('must not launch'),
        );
        await tap(t, 'Connect Google Ads');
        expect(find.textContaining('could not be prepared'), findsOneWidget);
        expect(find.text('Continue to Google'), findsNothing);
      }
    },
  );
  testWidgets(
    'Blocked popup and incomplete authorization retain the initiating proof for retry',
    (t) async {
      await mount(t, (r) async {
        if (r.url.path.endsWith('/begin')) return response(beginBody());
        if (r.url.path.endsWith('/finish')) {
          return response({'error': 'Complete Google sign-in first.'}, 409);
        }
        return response({'configured': true});
      }, open: (u) async => false);
      await tap(t, 'Connect Google Ads');
      await tap(t, 'Continue to Google');
      expect(find.textContaining('did not open'), findsOneWidget);
      await tap(t, 'Finish Google connection');
      expect(find.text('Complete Google sign-in first.'), findsOneWidget);
      expect(find.text('Finish Google connection'), findsOneWidget);
    },
  );
  testWidgets('A newer client ignores a late result from the old client', (
    t,
  ) async {
    final late = Completer<http.Response>();
    await mount(t, (r) => late.future, settle: false);
    await mount(t, (r) async => response({'configured': false}));
    late.complete(response(connected()));
    await t.pumpAndSettle();
    expect(find.text('Setup pending'), findsOneWidget);
    expect(find.text('KORLIX Growth'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Access denial elsewhere clears account details and ignores a late Google response',
    (t) async {
      final late = Completer<http.Response>();
      final client = await mount(
        t,
        (r) async => r.url.path.endsWith('/connection')
            ? late.future
            : response({'error': 'Enterprise required'}, 403),
        settle: false,
      );
      await expectLater(
        client.request('GET', '/other'),
        throwsA(isA<FunnelException>()),
      );
      late.complete(response(connected()));
      await t.pumpAndSettle();
      expect(find.text('Access unavailable'), findsOneWidget);
      expect(find.text('KORLIX Growth'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Connect Google Ads'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'Changing access root disables selection until the new root is loaded',
    (t) async {
      final state = connected();
      state['connection']['roots'] = [root, '5555555555'];
      await mount(t, (r) async => response(state));
      await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('5555555555').last);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Load the new access account'),
        findsOneWidget,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Use Google account'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'Local search filters without requesting tokens or provider data',
    (t) async {
      final state = connected();
      final sample = Map<String, dynamic>.from(
        state['connection']['accounts'][0],
      );
      state['connection']['accounts'] = List.generate(
        5,
        (i) => {...sample, 'id': '${1000000000 + i}', 'name': 'Account $i'},
      );
      var calls = 0;
      await mount(t, (r) async {
        calls++;
        return response(state);
      });
      await t.enterText(find.byType(TextField), 'Account 3');
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Account 3'),
        findsOneWidget,
      );
      expect(find.text('Account 2'), findsNothing);
      expect(calls, 1);
    },
  );
  testWidgets(
    'An empty loaded manager explains that no active advertising accounts were found',
    (t) async {
      final state = connected();
      state['connection']['accounts'] = [];
      await mount(t, (r) async => response(state));
      expect(
        find.textContaining('No active advertising accounts'),
        findsOneWidget,
      );
    },
  );
  test(
    'Malformed roots, account identities, manager flags and stale selections fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (c) => c['version'] = 0,
        (c) => c['roots'] = [root, root],
        (c) => c['root_id'] = '5555555555',
        (c) => c['accounts'][0]['manager'] = true,
        (c) => c['accounts'][0]['status'] = 'SUSPENDED',
        (c) => c['selected_account'] = '5555555555',
        (c) => c['login_customer_id'] = '5555555555',
      ]) {
        final state = connected();
        mutate(state['connection']);
        expect(() => googleAdsState(state), throwsA(isA<FunnelException>()));
      }
    },
  );
}

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
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> connected({bool reconnect = false}) => {
  'configured': true,
  'connection': {
    'version': 7,
    'needs_reconnect': reconnect,
    'expires_at': '2026-11-20T12:00:00Z',
    'refreshed_at': '2026-09-22T12:00:00Z',
    'accounts': [
      {
        'id': 'act_123',
        'name': 'KORLIX Growth',
        'currency': 'USD',
        'timezone': 'America/New_York',
        'status': 1,
      },
    ],
  },
};
Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  Future<http.Response> Function(http.Request) handler, {
  Future<bool> Function(Uri)? open,
  GlobalKey? capture,
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
            child: FunnelMetaConnection(client: client, openUrl: open),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

http.Response response(Map<String, dynamic> body, [int code = 200]) =>
    http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final f in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$f');
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
      'Meta connection flow fits $width and binds finish to original attempt',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final calls = <http.Request>[];
        final opened = <Uri>[];
        var state = <String, dynamic>{'configured': true, 'connection': null};
        final capture = GlobalKey();
        await mount(
          t,
          (r) async {
            calls.add(r);
            if (r.url.path.endsWith('/begin')) {
              return response({
                'id': 'attempt-id',
                'proof': 'private-proof',
                'authorization_url':
                    'https://www.facebook.com/v26.0/dialog/oauth?state=opaque',
              });
            }
            if (r.url.path.endsWith('/finish')) state = connected();
            if (r.url.path.endsWith('/select')) {
              state = {
                'configured': true,
                'connection': {
                  ...state['connection'],
                  'version': 8,
                  'selected_account': 'act_123',
                },
              };
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
        await tap(t, 'Connect Meta');
        expect(opened, isEmpty);
        await tap(t, 'Continue to Meta');
        expect(opened.single.host, 'www.facebook.com');
        await tap(t, 'Finish connection');
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/finish')).body,
          ),
          {'id': 'attempt-id', 'proof': 'private-proof'},
        );
        expect(find.text('KORLIX Growth'), findsOneWidget);
        await tap(t, 'Use this account');
        expect(
          jsonDecode(
            calls.firstWhere((r) => r.url.path.endsWith('/select')).body,
          ),
          {'account_id': 'act_123', 'version': 7},
        );
        expect(find.text('Selected account'), findsOneWidget);
        expect(t.takeException(), isNull);
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          await t.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1.5);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '/tmp/k144-meta-${width.toInt()}.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tap(t, 'Disconnect');
        await tap(t, 'Keep connection');
        expect(calls.where((r) => r.url.path.endsWith('/disconnect')), isEmpty);
        await tap(t, 'Disconnect');
        await tap(t, 'Disconnect Meta');
        expect(jsonDecode(calls.last.body), {'confirmed': true, 'version': 8});
        expect(find.text('Ready to connect'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('Missing platform setup cannot start authorization', (t) async {
    final calls = <http.Request>[];
    await mount(t, (r) async {
      calls.add(r);
      return response({'configured': false});
    });
    expect(find.text('Setup pending'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Connect Meta'),
          )
          .onPressed,
      isNull,
    );
    expect(calls, hasLength(1));
  });
  testWidgets(
    'Reconnect state disables account selection and pending reload explains recovery',
    (t) async {
      await mount(
        t,
        (r) async => response({
          ...connected(reconnect: true),
          'pending': {'phase': 'ready'},
        }),
      );
      expect(find.text('Reconnect needed'), findsOneWidget);
      expect(find.textContaining('original window'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Use this account'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Refresh ad accounts'), findsNothing);
    },
  );
  testWidgets(
    'Untrusted login URL is rejected and provider error retains finish action',
    (t) async {
      var invalid = true;
      await mount(t, (r) async {
        if (r.url.path.endsWith('/begin')) {
          return response({
            'id': 'id',
            'proof': 'proof',
            'authorization_url': invalid
                ? 'https://evil.example/signin'
                : 'https://www.facebook.com/v26.0/dialog/oauth',
          });
        }
        if (r.url.path.endsWith('/finish')) {
          return response({'error': 'Complete the Meta sign-in first.'}, 409);
        }
        return response({'configured': true});
      }, open: (u) async => false);
      await tap(t, 'Connect Meta');
      expect(find.textContaining('could not be prepared'), findsOneWidget);
      expect(find.text('Continue to Meta'), findsNothing);
      invalid = false;
      await tap(t, 'Connect Meta');
      await tap(t, 'Continue to Meta');
      expect(find.textContaining('did not open'), findsOneWidget);
      await tap(t, 'Finish connection');
      expect(find.text('Complete the Meta sign-in first.'), findsOneWidget);
      expect(find.text('Finish connection'), findsOneWidget);
    },
  );
  testWidgets(
    'Search filters accounts locally without requesting credentials',
    (t) async {
      final state = connected();
      state['connection']['accounts'] = List.generate(
        5,
        (i) => {
          'id': 'act_$i',
          'name': 'Account $i',
          'currency': 'USD',
          'timezone': 'UTC',
          'status': 1,
        },
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
}

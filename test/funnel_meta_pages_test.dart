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
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_pages.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_meta_test.dart' as old;

Map<String, dynamic> state({
  int version = 7,
  int count = 2,
  String? selected,
  bool denied = false,
}) => {
  ...old.connected(),
  'connection': {
    ...old.connected()['connection'],
    'version': version,
    'selected_account': 'act_123',
    'pages': List.generate(
      count,
      (i) => <String, dynamic>{
        'id': '${9000 + i}',
        'name': 'KORLIX Community ${i + 1}',
        'category': 'Education',
      },
    ),
    'selected_page': selected,
    'pages_access_denied': denied,
    'pages_refreshed_at': count > 0 ? '2026-09-23T00:00:00Z' : null,
  },
};
FunnelClient client(Future<http.Response> Function(http.Request) handler) {
  final c = FunnelClient(
    backendBaseUrl: 'https://example.com',
    headersBuilder: () => {},
    client: MockClient(handler),
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> mount(
  WidgetTester t,
  FunnelClient c, {
  GlobalKey? capture,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: WfStyle.theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: RepaintBoundary(
            key: capture,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: FunnelMetaConnection(client: c),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> screenshot(WidgetTester t, GlobalKey key, String name) async {
  if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
  await t.runAsync(() async {
    final im =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/k161-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    im.dispose();
  });
}

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
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Page refresh, select and clear fit $width', (t) async {
      await t.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var current = state();
      final calls = <http.Request>[];
      final key = GlobalKey();
      await mount(
        t,
        client((r) async {
          calls.add(r);
          if (r.url.path.endsWith('/pages')) current = state(version: 8);
          if (r.url.path.endsWith('/select-page')) {
            current = state(version: 9, selected: '9000');
          }
          if (r.url.path.endsWith('/clear-page')) current = state(version: 10);
          return old.response(current);
        }),
        capture: key,
        scale: width == 320 ? 1.3 : 1,
      );
      expect(calls.length, 1);
      await old.tap(t, 'Refresh Facebook Pages');
      expect(jsonDecode(calls.last.body), {
        'version': 7,
        'account_id': 'act_123',
      });
      final select = find.widgetWithText(OutlinedButton, 'Use this Page').first;
      await t.ensureVisible(select);
      await t.tap(select);
      await t.pumpAndSettle();
      expect(jsonDecode(calls.last.body), {
        'version': 8,
        'account_id': 'act_123',
        'page_id': '9000',
      });
      expect(find.text('Selected Page: KORLIX Community 1'), findsOneWidget);
      await t.ensureVisible(find.text('Facebook Page'));
      await t.pumpAndSettle();
      await screenshot(t, key, 'pages-${width.toInt()}');
      expect(t.takeException(), isNull);
      await old.tap(t, 'Clear Page selection');
      expect(jsonDecode(calls.last.body), {
        'version': 9,
        'account_id': 'act_123',
      });
      expect(find.text('Selected Page'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Page search and pagination are local and reset when connection version changes',
    (t) async {
      var current = state(count: 45);
      var calls = 0;
      await mount(
        t,
        client((r) async {
          calls++;
          return old.response(current);
        }),
      );
      expect(find.text('KORLIX Community 21'), findsNothing);
      await old.tap(t, 'Next Pages');
      expect(find.text('KORLIX Community 21'), findsOneWidget);
      expect(calls, 1);
      final search = find.widgetWithText(TextField, 'Find a Facebook Page');
      await t.ensureVisible(search);
      await t.enterText(search, '9004');
      await t.pumpAndSettle();
      expect(find.text('KORLIX Community 5'), findsOneWidget);
      expect(find.text('KORLIX Community 21'), findsNothing);
      expect(calls, 1);
      current = state(version: 8, count: 45);
      await old.tap(t, 'Refresh Facebook Pages');
      expect(t.widget<TextField>(search).controller?.text ?? '', isEmpty);
      expect(find.text('KORLIX Community 1'), findsOneWidget);
      expect(calls, 2);
    },
  );
  testWidgets(
    'Missing selection, reconnect, and setup pending disable Page requests',
    (t) async {
      for (final mode in ['unselected', 'reconnect', 'unconfigured']) {
        final current = state(count: 0);
        if (mode == 'unselected') {
          current['connection']['selected_account'] = null;
        }
        if (mode == 'reconnect') {
          current['connection']['needs_reconnect'] = true;
        }
        if (mode == 'unconfigured') current['configured'] = false;
        var calls = 0;
        await mount(
          t,
          client((r) async {
            calls++;
            return old.response(current);
          }),
        );
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Refresh Facebook Pages'),
              )
              .onPressed,
          isNull,
        );
        expect(calls, 1);
      }
    },
  );
  testWidgets(
    'Page permission failure reloads safe state and keeps ad reporting available',
    (t) async {
      var current = state(selected: '9000');
      await mount(
        t,
        client((r) async {
          if (r.url.path.endsWith('/pages')) {
            current = state(version: 8, count: 0, denied: true);
            return old.response({'error': 'Page access is unavailable.'}, 409);
          }
          return old.response(current);
        }),
      );
      await old.tap(t, 'Refresh Facebook Pages');
      expect(find.text('KORLIX Community 1'), findsNothing);
      expect(find.text('Selected Page: KORLIX Community 1'), findsNothing);
      expect(
        find.textContaining('Your ad account reports remain available'),
        findsOneWidget,
      );
      expect(find.text('KORLIX Growth'), findsOneWidget);
      expect(find.text('Reconnect needed'), findsNothing);
    },
  );
  testWidgets(
    'Access denial clears Page identities and suppresses late discovery',
    (t) async {
      final pending = Completer<http.Response>();
      final c = client((r) async {
        if (r.url.path.endsWith('/pages')) return pending.future;
        if (r.url.path.endsWith('/denied')) {
          return old.response({'error': 'Sign in'}, 403);
        }
        return old.response(state());
      });
      await mount(t, c);
      await t.ensureVisible(find.text('Refresh Facebook Pages'));
      await t.tap(find.text('Refresh Facebook Pages'));
      await t.pump();
      try {
        await c.request('GET', '/denied');
      } catch (_) {}
      await t.pump();
      expect(find.text('KORLIX Community 1'), findsNothing);
      pending.complete(old.response(state(version: 8, selected: '9000')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Sign in with Enterprise access'),
        findsOneWidget,
      );
      expect(find.text('Selected Page'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Replacing the client invalidates a late Page result from the prior owner',
    (t) async {
      final pending = Completer<http.Response>();
      final c = client(
        (r) async => r.url.path.endsWith('/pages')
            ? pending.future
            : old.response(state()),
      );
      await mount(t, c);
      await t.ensureVisible(find.text('Refresh Facebook Pages'));
      await t.tap(find.text('Refresh Facebook Pages'));
      await t.pump();
      await mount(
        t,
        client(
          (r) async => old.response({'configured': true, 'connection': null}),
        ),
      );
      pending.complete(old.response(state(version: 8, selected: '9000')));
      await t.pumpAndSettle();
      expect(find.text('KORLIX Community 1'), findsNothing);
      expect(find.text('Connect Meta'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('A malformed Page response hides the previous snapshot', (
    t,
  ) async {
    var current = state();
    await mount(t, client((r) async => old.response(current)));
    current = state(version: 8, selected: '99999');
    await old.tap(t, 'Refresh Facebook Pages');
    expect(find.text('KORLIX Community 1'), findsNothing);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test(
    'Page response validation enforces identity, membership, bounds and no token fields',
    () {
      validateMetaPages(state(count: 500));
      validateMetaPages(old.connected());
      final variants = <Map<String, dynamic>>[
        state(count: 501),
        state(selected: 'not-shared'),
        state(denied: true),
      ];
      for (final edit in [
        <String, dynamic>{'id': 1},
        {'name': ''},
        {'name': 'x' * 201},
        {'category': null},
        {'access_token': 'must-not-render'},
      ]) {
        final x = state();
        x['connection']['pages'][0].addAll(edit);
        variants.add(x);
      }
      final repeated = state();
      repeated['connection']['pages'][1]['id'] = '9000';
      variants.add(repeated);
      for (final x in variants) {
        expect(() => validateMetaPages(x), throwsA(isA<FunnelException>()));
      }
    },
  );
}

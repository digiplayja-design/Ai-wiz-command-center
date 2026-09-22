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
import 'package:ai_wiz_command_center/funnel_studio/funnel_inbox.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const snapshot = '2026-09-22T12:00:00.123456Z';
Map<String, dynamic> page({
  bool next = false,
  String name = 'Avery Morgan',
  int total = 137,
}) => {
  'total': total,
  'filtered_total': total,
  'snapshot': snapshot,
  'next_cursor': next ? 'opaque-next' : null,
  'campaigns': [
    {'source': 'facebook', 'campaign': 'autumn-consultation', 'leads': total},
  ],
  'leads': total == 0
      ? []
      : [
          {
            'id': 'lead-1',
            'contact_id': 'contact-1',
            'name': name,
            'email': 'avery@example.com',
            'phone': '+1 202 555 0110',
            'message': 'I would like to explore a growth plan for our team.',
            'created_at': '2026-09-22T09:15:00Z',
            'utm': {'utm_source': 'facebook'},
          },
        ],
};
http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final e in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/${e.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double scale = 1,
    Future<void> Function(String, String)? export,
    Future<void> Function(String)? queue,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FunnelInbox(
                client: FunnelClient(
                  backendBaseUrl: 'https://example.com',
                  headersBuilder: () => {'Authorization': 'owner-token'},
                  client: MockClient(handler),
                ),
                funnelId: 'funnel-one',
                onQueue: queue ?? (_) => Future.value(),
                onExport: export,
                onOpenContacts: () => Future.value(),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).first);
    await t.tap(find.text(label).first);
    await t.pumpAndSettle();
  }

  testWidgets(
    'Search applies on the server, resets paging and exports the same filtered snapshot',
    (t) async {
      final calls = <http.Request>[];
      var exported = '';
      await mount(
        t,
        (r) async {
          calls.add(r);
          expect(r.headers['Authorization'], 'owner-token');
          if (r.url.path.endsWith('/export')) {
            return response({
              'csv': 'CSV result',
              'filename': 'leads.csv',
              'count': 3,
            });
          }
          return response(
            page(
              next: r.url.queryParameters['cursor'] == null,
              name: r.url.queryParameters['cursor'] == null
                  ? 'Avery Morgan'
                  : 'Older inquiry',
            ),
          );
        },
        export: (csv, name) async {
          exported = csv;
          expect(name, 'leads.csv');
        },
      );
      await tap(t, 'Next');
      expect(calls.last.url.queryParameters, {
        'cursor': 'opaque-next',
        'snapshot': snapshot,
      });
      expect(find.text('Older inquiry'), findsOneWidget);
      await tap(t, 'Previous');
      expect(calls.last.url.queryParameters, {'snapshot': snapshot});
      await t.enterText(find.byKey(const ValueKey('inbox-search')), 'Avery');
      await t.enterText(find.byKey(const ValueKey('inbox-source')), 'facebook');
      await t.pump();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export filtered CSV'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Apply filters');
      expect(calls.last.url.queryParameters, {
        'search': 'Avery',
        'source': 'facebook',
      });
      await tap(t, 'Export filtered CSV');
      expect(calls.last.url.queryParameters, {
        'search': 'Avery',
        'source': 'facebook',
        'snapshot': snapshot,
      });
      expect(exported, 'CSV result');
      await tap(t, 'Clear');
      expect(calls.last.url.queryParameters, isEmpty);
    },
  );
  testWidgets(
    'Failed export produces no file and access loss clears visible leads',
    (t) async {
      var deny = false, exported = false;
      await mount(t, (r) async {
        if (deny) return response({'error': 'Enterprise required'}, 403);
        if (r.url.path.endsWith('/export')) {
          return response({'error': 'Narrow filters below 5,000.'}, 400);
        }
        return response(page());
      }, export: (_, _) async => exported = true);
      await tap(t, 'Export filtered CSV');
      expect(exported, false);
      expect(find.text('Narrow filters below 5,000.'), findsOneWidget);
      deny = true;
      await tap(t, 'Refresh leads');
      expect(find.text('Avery Morgan'), findsNothing);
      expect(
        find.text('Sign in with an Enterprise account to view this inbox.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('Empty results and queue follow-up use the selected inquiry', (
    t,
  ) async {
    var empty = false, queued = '';
    await mount(
      t,
      (_) async => response(page(total: empty ? 0 : 1)),
      queue: (id) async => queued = id,
    );
    await tap(t, 'Queue follow-up');
    expect(queued, 'lead-1');
    empty = true;
    await tap(t, 'Refresh leads');
    expect(
      find.text(
        'Your next lead will appear here. Share a published page to get started.',
      ),
      findsOneWidget,
    );
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Export filtered CSV'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'A response completing after leaving the inbox cannot expose or export data',
    (t) async {
      final pending = Completer<http.Response>();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FunnelInbox(
                client: FunnelClient(
                  backendBaseUrl: 'https://example.com',
                  headersBuilder: () => {},
                  client: MockClient((_) => pending.future),
                ),
                funnelId: 'one',
                onQueue: (_) async {},
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(const MaterialApp(home: Text('Another screen')));
      pending.complete(response(page()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Avery Morgan'), findsNothing);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Responsive inbox fits $width with readable controls', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await mount(
        t,
        (_) async => response(page()),
        scale: width == 320 ? 1.3 : 1,
      );
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k146-inbox-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(find.text('Queue follow-up'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}

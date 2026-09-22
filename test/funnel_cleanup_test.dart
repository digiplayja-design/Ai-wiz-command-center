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
import 'package:ai_wiz_command_center/funnel_studio/funnel_inbox.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> lead({
  int version = 3,
  String status = 'new',
  String note = 'Discuss the consultation.',
}) => {
  'id': 'lead-1',
  'name': 'Avery Morgan',
  'email': 'avery@example.com',
  'message': 'I would like to explore a growth plan for our team.',
  'created_at': '2026-09-22T09:15:00Z',
  'utm': {'utm_source': 'facebook'},
  'contact_id': 'contact-1',
  'inbox_status': status,
  'private_note': note,
  'inbox_version': version,
  'inbox_updated_at': '2026-09-22T09:30:00Z',
};
Map<String, dynamic> details({
  int version = 4,
  String status = 'new',
  String note = 'Discuss the consultation.',
}) => {
  'lead': lead(version: version, status: status, note: note),
  'scheduled_followups': 2,
  'delivery_review': 0,
};
Map<String, dynamic> page({bool empty = false}) => {
  'total': 3,
  'filtered_total': empty ? 0 : 3,
  'snapshot': '2026-09-22T12:00:00.123456Z',
  'next_cursor': null,
  'status_totals': {
    'new': 1,
    'in_review': 1,
    'qualified': 1,
    'won': 0,
    'lost': 0,
  },
  'campaigns': [],
  'lead_management': true,
  'leads': empty ? [] : [lead()],
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
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
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
    double width = 1440,
    double scale = 1,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: WfStyle.theme,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: FunnelInbox(
                client: FunnelClient(
                  backendBaseUrl: 'https://example.com',
                  headersBuilder: () => {'Authorization': 'session'},
                  client: MockClient(handler),
                ),
                funnelId: 'funnel-1',
                onQueue: (_) async =>
                    throw StateError('Unexpected queue action'),
                onExport: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Map<String, dynamic> review({bool protected = false}) => {
    'matched': 1,
    'eligible': protected ? 0 : 1,
    'blocked': protected ? 1 : 0,
    'blocked_examples': protected
        ? [
            {
              'name': 'Avery Morgan',
              'reason': 'Resolve open follow-ups before deleting.',
            },
          ]
        : [],
    'selected': protected
        ? []
        : [
            {
              'id': 'lead-1',
              'name': 'Avery Morgan',
              'email': 'avery@example.com',
              'status': 'won',
              'created_at': '2026-01-01T12:00:00Z',
              'followups': 2,
              'sequences': 1,
            },
          ],
    'review_token': protected ? null : 'signed-review',
    'expires_at': '2026-09-22T12:10:00Z',
  };
  Future<void> confirm(WidgetTester t) async {
    final field = find.byKey(const ValueKey('cleanup-confirmation'));
    await t.ensureVisible(field);
    await t.enterText(field, 'DELETE');
    await t.pumpAndSettle();
  }

  testWidgets(
    'Single inquiry preview cannot delete until exact confirmation; success refreshes applied inbox filters',
    (t) async {
      final calls = <http.Request>[];
      var removed = false;
      await mount(t, (r) async {
        calls.add(r);
        if (r.url.path.endsWith('/preview')) {
          expect(jsonDecode(r.body), {'mode': 'single', 'lead_id': 'lead-1'});
          return response(review());
        }
        if (r.url.path.endsWith('/delete')) {
          expect(jsonDecode(r.body), {
            'review_token': 'signed-review',
            'confirmation': 'DELETE',
          });
          removed = true;
          return response({'deleted_count': 1, 'replayed': false});
        }
        return response(page(empty: removed));
      });
      await t.enterText(find.byKey(const ValueKey('inbox-source')), 'facebook');
      await tap(t, 'Apply filters');
      await t.enterText(
        find.byKey(const ValueKey('inbox-search')),
        'Unapplied',
      );
      await t.pump();
      await tap(t, 'Delete inquiry');
      expect(calls.where((r) => r.url.path.endsWith('/delete')), isEmpty);
      final button = find.widgetWithText(FilledButton, 'Delete 1 inquiry');
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      await t.ensureVisible(find.byKey(const ValueKey('cleanup-confirmation')));
      await t.enterText(
        find.byKey(const ValueKey('cleanup-confirmation')),
        'delete',
      );
      await t.pump();
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      await confirm(t);
      await tap(t, 'Delete 1 inquiry');
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls.last.url.queryParameters, {'source': 'facebook'});
      expect(find.textContaining('1 inquiry deleted.'), findsOneWidget);
      expect(find.text('Avery Morgan'), findsNothing);
    },
  );
  testWidgets(
    'Age-based cleanup is preview-only until confirmation; changed criteria invalidate the selection',
    (t) async {
      var previews = 0, deletes = 0;
      await mount(t, (r) async {
        if (r.url.path.endsWith('/preview')) {
          previews++;
          final b = jsonDecode(r.body);
          expect(b['mode'], 'retention');
          expect(b['statuses'], previews == 1 ? ['won', 'lost'] : ['lost']);
          expect(b.keys.toSet(), {'mode', 'before', 'statuses'});
          return response(review());
        }
        if (r.url.path.endsWith('/delete')) deletes++;
        return response(page());
      });
      await tap(t, 'Clean up old inquiries');
      expect(previews, 0);
      await tap(t, 'Preview cleanup');
      expect(previews, 1);
      await confirm(t);
      await t.ensureVisible(find.byKey(const ValueKey('cleanup-stages')));
      await t.tap(find.byKey(const ValueKey('cleanup-stages')));
      await t.pumpAndSettle();
      await t.tap(find.text('Lost only').last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cleanup-confirmation')), findsNothing);
      expect(find.text('Delete 1 inquiry'), findsNothing);
      await tap(t, 'Preview cleanup');
      expect(previews, 2);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Delete 1 inquiry'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Close');
      expect(deletes, 0);
    },
  );
  testWidgets(
    'Protected records explain the hold and expose no delete confirmation',
    (t) async {
      await mount(
        t,
        (r) async => response(
          r.url.path.endsWith('/preview') ? review(protected: true) : page(),
        ),
      );
      await tap(t, 'Delete inquiry');
      expect(find.text('Protected inquiries are excluded'), findsOneWidget);
      expect(find.textContaining('Resolve open follow-ups'), findsOneWidget);
      expect(find.byKey(const ValueKey('cleanup-confirmation')), findsNothing);
      expect(find.text('Delete 1 inquiry'), findsNothing);
      await tap(t, 'Close');
      expect(find.text('Avery Morgan'), findsOneWidget);
    },
  );
  testWidgets(
    'A pending deletion cannot repeat or close and only a confirmed result reports success',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      await mount(t, (r) async {
        if (r.url.path.endsWith('/preview')) return response(review());
        if (r.url.path.endsWith('/delete')) {
          writes++;
          return pending.future;
        }
        return response(page());
      });
      await tap(t, 'Delete inquiry');
      await confirm(t);
      await t.tap(find.text('Delete 1 inquiry'));
      await t.pump();
      expect(writes, 1);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Deleting…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      pending.complete(response({'deleted_count': 1, 'replayed': true}));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(find.textContaining('1 inquiry deleted.'), findsOneWidget);
    },
  );
  for (final status in [409, 503, 200]) {
    testWidgets(
      'Unconfirmed deletion ($status) clears approval and refreshes on close without a success claim',
      (t) async {
        var gets = 0;
        await mount(t, (r) async {
          if (r.url.path.endsWith('/preview')) return response(review());
          if (r.url.path.endsWith('/delete'))
            return response(
              status == 200
                  ? {'deleted_count': 2, 'replayed': false}
                  : {'error': 'Review cleanup again.'},
              status,
            );
          gets++;
          return response(page(empty: gets > 1));
        });
        await tap(t, 'Delete inquiry');
        await confirm(t);
        await tap(t, 'Delete 1 inquiry');
        expect(
          find.byKey(const ValueKey('cleanup-confirmation')),
          findsNothing,
        );
        expect(
          find.textContaining('deletion result was not confirmed'),
          findsOneWidget,
        );
        await tap(t, 'Close');
        expect(gets, 2);
        expect(find.textContaining('inquiry deleted.'), findsNothing);
        expect(find.text('Avery Morgan'), findsNothing);
      },
    );
  }
  testWidgets('Lost access clears both the cleanup review and inbox identity', (
    t,
  ) async {
    await mount(t, (r) async {
      if (r.url.path.endsWith('/preview')) return response(review());
      if (r.url.path.endsWith('/delete'))
        return response({'error': 'Enterprise required'}, 403);
      return response(page());
    });
    await tap(t, 'Delete inquiry');
    await confirm(t);
    await tap(t, 'Delete 1 inquiry');
    expect(find.text('Avery Morgan'), findsNothing);
    expect(find.text('avery@example.com'), findsNothing);
    await tap(t, 'Close');
    expect(
      find.text('Sign in with an Enterprise account to view this inbox.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'Malformed protected examples cannot expose a destructive control',
    (t) async {
      await mount(
        t,
        (r) async => response(
          r.url.path.endsWith('/preview')
              ? {
                  ...review(),
                  'blocked_examples': ['bad'],
                }
              : page(),
        ),
      );
      await tap(t, 'Delete inquiry');
      expect(find.textContaining('complete review'), findsOneWidget);
      expect(find.text('Delete 1 inquiry'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Cleanup review and confirmation fit $width', (t) async {
      await mount(
        t,
        (r) async =>
            response(r.url.path.endsWith('/preview') ? review() : page()),
        width: width,
        scale: width == 320 ? 1.3 : 1,
      );
      await tap(t, 'Clean up old inquiries');
      await tap(t, 'Preview cleanup');
      expect(t.takeException(), isNull);
      await confirm(t);
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1')
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              )
              .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k149-cleanup-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await tap(t, 'Close');
      expect(t.takeException(), isNull);
    });
  }
}

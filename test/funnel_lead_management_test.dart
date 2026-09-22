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

  Future<void> choose(WidgetTester t, String label) async {
    final dropdown = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await t.ensureVisible(dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'Status filter controls server queries and exports; clear removes it',
    (t) async {
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        return response(
          r.url.path.endsWith('/export')
              ? {'csv': 'csv', 'filename': 'leads.csv', 'count': 3}
              : page(),
        );
      });
      await t.ensureVisible(find.byKey(const ValueKey('inbox-status-')));
      await t.tap(find.byKey(const ValueKey('inbox-status-')));
      await t.pumpAndSettle();
      await t.tap(find.text('Qualified').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export filtered CSV'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Apply filters');
      expect(calls.last.url.queryParameters, {'status': 'qualified'});
      await tap(t, 'Export filtered CSV');
      expect(calls.last.url.queryParameters['status'], 'qualified');
      expect(calls.last.url.queryParameters.containsKey('snapshot'), true);
      await tap(t, 'Clear');
      expect(calls.last.url.queryParameters, isEmpty);
      expect(find.text('All statuses'), findsOneWidget);
    },
  );
  testWidgets(
    'Editor loads fresh details, saves the displayed version, then refreshes the applied filters',
    (t) async {
      final calls = <http.Request>[];
      var saved = false;
      await mount(t, (r) async {
        calls.add(r);
        if (r.method == 'PATCH') {
          saved = true;
          expect(jsonDecode(r.body), {
            'version': 4,
            'status': 'qualified',
            'private_note': 'Send the requested proposal.',
          });
          return response(
            details(
              version: 5,
              status: 'qualified',
              note: 'Send the requested proposal.',
            ),
          );
        }
        if (r.url.path.endsWith('/lead-1')) return response(details());
        return response(page(empty: saved));
      });
      await t.enterText(find.byKey(const ValueKey('inbox-source')), 'facebook');
      await tap(t, 'Apply filters');
      await t.enterText(
        find.byKey(const ValueKey('inbox-search')),
        'Unsaved search',
      );
      await t.pump();
      await tap(t, 'Manage lead');
      expect(find.textContaining('Scheduled follow-ups: 2'), findsOneWidget);
      await choose(t, 'Qualified');
      await t.enterText(
        find.byKey(const ValueKey('lead-private-note')),
        'Send the requested proposal.',
      );
      await t.pump();
      await tap(t, 'Save status & note');
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls.where((r) => r.method == 'PATCH').length, 1);
      expect(calls.last.url.queryParameters, {'source': 'facebook'});
      expect(find.text('Lead details saved.'), findsOneWidget);
      expect(find.textContaining('No inquiries match'), findsOneWidget);
    },
  );
  testWidgets('Discard requires confirmation and never saves', (t) async {
    var writes = 0;
    await mount(t, (r) async {
      if (r.method != 'GET') writes++;
      return response(r.url.path.endsWith('/lead-1') ? details() : page());
    });
    await tap(t, 'Manage lead');
    await t.enterText(
      find.byKey(const ValueKey('lead-private-note')),
      'Unsaved note',
    );
    await t.pump();
    await tap(t, 'Discard changes');
    expect(find.text('Discard these edits?'), findsOneWidget);
    await tap(t, 'Keep editing');
    expect(find.text('Unsaved note'), findsOneWidget);
    await tap(t, 'Discard changes');
    await tap(t, 'Discard edits');
    expect(find.byType(AlertDialog), findsNothing);
    expect(writes, 0);
  });
  testWidgets(
    'A stale update preserves edits and requires an explicit reload before another save',
    (t) async {
      var gets = 0, writes = 0;
      await mount(t, (r) async {
        if (r.method == 'PATCH') {
          writes++;
          return response({
            'error':
                'This inquiry changed. Reload its saved details before saving again.',
          }, 409);
        }
        if (r.url.path.endsWith('/lead-1')) {
          return response(
            details(
              version: ++gets == 1 ? 4 : 5,
              note: gets == 1 ? 'Original note' : 'Newer saved note',
            ),
          );
        }
        return response(page());
      });
      await tap(t, 'Manage lead');
      await t.enterText(
        find.byKey(const ValueKey('lead-private-note')),
        'My unsaved note',
      );
      await t.pump();
      await tap(t, 'Save status & note');
      expect(find.text('My unsaved note'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save status & note'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Reload saved details');
      await tap(t, 'Keep editing');
      expect(gets, 1);
      await tap(t, 'Reload saved details');
      await tap(t, 'Discard edits');
      expect(gets, 2);
      expect(find.text('Newer saved note'), findsOneWidget);
      expect(writes, 1);
    },
  );
  testWidgets(
    'Access denial hides the note, identity and inbox behind the dialog',
    (t) async {
      await mount(t, (r) async {
        if (r.method == 'PATCH') {
          return response({'error': 'Enterprise required'}, 403);
        }
        return response(r.url.path.endsWith('/lead-1') ? details() : page());
      });
      await tap(t, 'Manage lead');
      await t.enterText(
        find.byKey(const ValueKey('lead-private-note')),
        'Sensitive note',
      );
      await t.pump();
      await tap(t, 'Save status & note');
      expect(find.text('Avery Morgan'), findsNothing);
      expect(find.text('avery@example.com'), findsNothing);
      expect(find.text('Sensitive note'), findsNothing);
      expect(find.text('Sign in required'), findsOneWidget);
      await tap(t, 'Close');
      expect(
        find.text('Sign in with an Enterprise account to view this inbox.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'A pending save cannot be repeated and closing cannot claim success',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      await mount(t, (r) async {
        if (r.method == 'PATCH') {
          writes++;
          return pending.future;
        }
        return response(r.url.path.endsWith('/lead-1') ? details() : page());
      });
      await tap(t, 'Manage lead');
      await choose(t, 'Won');
      expect(
        find.textContaining('does not record or verify revenue'),
        findsOneWidget,
      );
      await t.tap(find.text('Save status & note'));
      await t.pump();
      expect(writes, 1);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Discard changes'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(response(details(version: 5, status: 'won')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 1);
    },
  );
  testWidgets('Leaving during a read discards late results', (t) async {
    final pending = Completer<http.Response>();
    await mount(
      t,
      (r) async =>
          r.url.path.endsWith('/lead-1') ? pending.future : response(page()),
    );
    await t.ensureVisible(find.text('Manage lead'));
    await t.tap(find.text('Manage lead'));
    await t.pump();
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Elsewhere'))),
    );
    pending.complete(response(details()));
    await t.pumpAndSettle();
    expect(find.text('Avery Morgan'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'An inconsistent save response requires reload and cannot show success',
    (t) async {
      await mount(t, (r) async {
        if (r.method == 'PATCH') {
          return response(details(version: 5, status: 'new'));
        }
        return response(r.url.path.endsWith('/lead-1') ? details() : page());
      });
      await tap(t, 'Manage lead');
      await choose(t, 'Won');
      await tap(t, 'Save status & note');
      expect(find.text('Lead details saved.'), findsNothing);
      expect(
        find.text(
          'Could not confirm the saved lead details. Reload before trying again.',
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save status & note'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Lead editor and stage filters fit $width', (t) async {
      await mount(
        t,
        (r) async =>
            response(r.url.path.endsWith('/lead-1') ? details() : page()),
        width: width,
        scale: width == 320 ? 1.3 : 1,
      );
      expect(t.takeException(), isNull);
      await tap(t, 'Manage lead');
      await choose(t, 'Lost');
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              )
              .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k148-lead-editor-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tap(t, 'Discard changes');
      expect(t.takeException(), isNull);
      await tap(t, 'Discard edits');
      expect(t.takeException(), isNull);
    });
  }
}

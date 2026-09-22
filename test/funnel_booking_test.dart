import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_booking.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_form_preview.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_questions_test.dart' show tap, enter, keyed, reply;
import 'funnel_branching_test.dart' show questions;
import 'funnel_studio_test.dart' show fixture;

List<Map<String, dynamic>> routes() => [
  {
    'id': 'route-1',
    'name': 'Home consultation',
    'question_id': 'q-2',
    'equals': 'Home',
    'url': 'https://example.com/home',
    'button_label': 'Book a home visit',
  },
  {
    'id': 'route-2',
    'name': 'Installation team',
    'question_id': 'q-1',
    'equals': 'Install',
    'url': 'https://example.com/install',
    'button_label': 'Talk to the install team',
  },
];
Map<String, dynamic> document() => {
  ...funnelTemplate('consultation'),
  'questions': questions(),
  'booking_routes': routes(),
  'booking_url': 'https://example.com/default',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
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
    }
  });
  test(
    'Routes survive generated copy and duplication independently; missing questions cannot silently reconnect',
    () {
      final d = document();
      expect(funnelBookingRoutesComplete(d), true);
      for (final next in [
        generatedCopy(d, funnelTemplate('event')),
        copyFunnel(d),
      ]) {
        expect(next['booking_routes'], routes());
        next['booking_routes'][0]['url'] = 'Changed';
        expect(d['booking_routes'][0]['url'], 'https://example.com/home');
      }
      final remaining = questions()..removeAt(1);
      final invalid = bookingRoutesAfterQuestions(d, remaining);
      expect(invalid[0]['question_id'], '');
      expect(invalid[0]['equals'], '');
      expect(
        funnelBookingRoutesComplete({
          ...d,
          'questions': questions(),
          'booking_routes': invalid,
        }),
        false,
      );
      for (final patch in [
        {'equals': 'Removed'},
        {'url': 'http://example.com'},
        {'url': 'https://user@example.com'},
        {'name': ''},
        {'button_label': ''},
      ]) {
        expect(
          funnelBookingRoutesComplete({
            ...d,
            'booking_routes': [
              {...routes().first, ...patch},
            ],
          }),
          false,
        );
      }
      expect(
        funnelBookingRoutesComplete({
          ...d,
          'booking_routes': [
            routes().first,
            {...routes().first, 'id': 'route-2'},
          ],
        }),
        false,
      );
    },
  );
  test(
    'Preview uses first active route and falls back after hidden answers are discarded',
    () {
      final d = document(), answers = {'q-1': 'Install', 'q-2': 'Home'};
      expect(funnelBookingOutcome(d, answers)['route_id'], 'route-1');
      expect(
        funnelBookingOutcome({
          ...d,
          'booking_routes': routes().reversed.toList(),
        }, answers)['route_id'],
        'route-2',
      );
      expect(
        funnelBookingOutcome(d, {
          'q-1': 'Advice',
          'q-2': 'Home',
        })['booking_url'],
        'https://example.com/default',
      );
      expect(
        funnelBookingOutcome({...d, 'booking_url': ''}, {})['booking_url'],
        '',
      );
    },
  );
  testWidgets(
    'Studio saves route changes only to the draft and reload restores the saved routes',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var f = fixture();
      f['draft'].addAll({'questions': questions(), 'booking_routes': routes()});
      final calls = <http.Request>[];
      await t.pumpWidget(
        MaterialApp(
          home: FunnelScreen(
            client: FunnelClient(
              backendBaseUrl: 'https://example.com',
              headersBuilder: () => {},
              client: MockClient((r) async {
                calls.add(r);
                if (r.method == 'PUT') {
                  f = {
                    ...f,
                    'draft': jsonDecode(r.body)['document'],
                    'version': 2,
                  };
                  return reply({'funnel': f});
                }
                return reply({
                  'funnels': [f],
                });
              }),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Open studio'));
      await tap(t, find.text('Booking routes'));
      await enter(t, 'booking-name-route-1', 'Home team');
      await tap(t, keyed('booking-up-route-2'));
      expect(
        t.widget<TextFormField>(keyed('booking-name-route-1')).initialValue,
        'Home team',
      );
      await tap(t, find.text('Save draft'));
      expect(f['draft']['booking_routes'][0]['id'], 'route-2');
      expect(f['draft']['booking_routes'][1]['name'], 'Home team');
      expect(calls.where((r) => r.method != 'GET').map((r) => r.method), [
        'PUT',
      ]);
      await tap(t, find.text('Booking routes'));
      await tap(t, keyed('booking-remove-route-1'));
      await tap(t, find.text('Reload saved'));
      await tap(t, find.text('Discard edits'));
      await tap(t, find.text('Booking routes'));
      expect(keyed('booking-name-route-1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Route editor selects conditions, clears old answers, limits four routes and preserves IDs after removal',
    (t) async {
      var d = {...document(), 'booking_routes': <Map<String, dynamic>>[]};
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, set) => FunnelBookingEditor(
                  document: d,
                  onChanged: (v) => set(() => d = {...d, 'booking_routes': v}),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(t, find.text('Booking routes'));
      await tap(t, keyed('booking-add'));
      await tap(t, keyed('booking-question-route-1-'));
      await tap(t, find.text('Property type').last);
      await tap(t, keyed('booking-answer-route-1-'));
      await tap(t, find.text('Home').last);
      expect(d['booking_routes'][0]['equals'], 'Home');
      await tap(t, keyed('booking-question-route-1-q-2'));
      await tap(t, find.text('Which service?').last);
      expect(d['booking_routes'][0]['equals'], '');
      for (var i = 1; i < 4; i++) {
        await tap(t, keyed('booking-add'));
      }
      expect(t.widget<OutlinedButton>(keyed('booking-add')).onPressed, isNull);
      await tap(t, keyed('booking-remove-route-2'));
      await tap(t, keyed('booking-add'));
      expect(d['booking_routes'].last['id'], 'route-2');
      expect(d['booking_routes'].last['name'], '');
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'Booking editor, interactive receipt preview and saved outcome fit $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var d = document();
        Future<void> mount(Widget child) async {
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('booking-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: WfStyle.theme,
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
        }

        Future<void> screenshot(String label) async {
          if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
          await t.runAsync(() async {
            final image = await t
                .renderObject<RenderRepaintBoundary>(keyed('booking-capture'))
                .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/k155-$label-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await mount(
          StatefulBuilder(
            builder: (c, set) => FunnelBookingEditor(
              document: d,
              onChanged: (v) => set(() => d = {...d, 'booking_routes': v}),
            ),
          ),
        );
        await tap(t, find.text('Booking routes'));
        await t.ensureVisible(keyed('booking-question-route-1-q-2'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot('editor');
        await mount(
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: FunnelFormPreview(
              mode: 'single',
              brand: 'Studio',
              cta: 'Send inquiry',
              accent: Colors.cyan,
              questions: questions(),
              document: d,
            ),
          ),
        );
        await tap(t, keyed('branch-preview-q-1-'));
        await tap(t, find.text('Install').last);
        await tap(t, keyed('branch-preview-q-2-'));
        await tap(t, find.text('Home').last);
        expect(find.text('Home consultation'), findsOneWidget);
        expect(find.text('https://example.com/home'), findsOneWidget);
        await t.ensureVisible(keyed('booking-outcome-preview'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot('receipt');
        await tap(t, keyed('branch-preview-q-1-Install'));
        await tap(t, find.text('Advice').last);
        expect(find.text('Home consultation'), findsNothing);
        expect(find.text('https://example.com/default'), findsOneWidget);
        await mount(
          FunnelOutcomeSummary(
            outcome: {
              'route_name': 'Saved home team',
              'booking_url':
                  'https://example.com/a-long-booking-path?ref=example&selection=home',
              'button_label': 'Book a home visit',
            },
          ),
        );
        expect(find.text('Next step offered'), findsOneWidget);
        expect(
          find.text(
            'Saved when submitted. This is not a confirmed appointment.',
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await screenshot('lead');
      },
    );
  }
}

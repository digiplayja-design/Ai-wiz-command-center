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
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_questions.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_inbox.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_inbox_test.dart' as inbox show page;
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'funnel_studio_test.dart' show fixture;

http.Response reply(Map data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Finder keyed(String key) => find.byKey(ValueKey(key));
Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String key, String value) async {
  await t.ensureVisible(keyed(key));
  await t.enterText(keyed(key), value);
  await t.pumpAndSettle();
}

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
  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double width = 1440,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
            child: child!,
          ),
          home: FunnelScreen(
            client: FunnelClient(
              backendBaseUrl: 'https://example.com',
              headersBuilder: () => {},
              client: MockClient(handler),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, find.text('Open studio'));
  }

  Future<void> screenshot(WidgetTester t, String name) async {
    if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(keyed('capture'))
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/k153-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final sampleQuestions = <Map<String, dynamic>>[
    {
      'id': 'q-1',
      'type': 'text',
      'label': 'What would you like to achieve?',
      'required': true,
      'options': <String>[],
    },
    {
      'id': 'q-2',
      'type': 'choice',
      'label': 'When would you like to begin?',
      'required': false,
      'options': ['This month', 'Next quarter'],
    },
  ];
  test(
    'Question defaults, generated copy, duplication and completeness preserve independent options',
    () {
      final current = funnelTemplate('consultation');
      expect(funnelQuestions(current), isEmpty);
      current['questions'] = sampleQuestions;
      expect(funnelQuestionsComplete(current), true);
      final generated = generatedCopy(current, funnelTemplate('event'));
      expect(generated['questions'], sampleQuestions);
      generated['questions'][1]['options'][0] = 'Changed';
      expect(sampleQuestions[1]['options'][0], 'This month');
      final cloned = copyFunnel(current);
      cloned['questions'][0]['label'] = 'Changed';
      expect(sampleQuestions[0]['label'], 'What would you like to achieve?');
      for (final options in [
        ['One'],
        ['Same', ' Same '],
        ['', 'Valid'],
        ['x' * 81, 'Valid'],
      ]) {
        expect(
          funnelQuestionsComplete({
            'questions': [
              {...sampleQuestions[1], 'options': options},
            ],
          }),
          false,
        );
      }
    },
  );
  testWidgets(
    'Question edits reorder without losing text, save only draft and reload discards later changes',
    (t) async {
      var f = fixture();
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        if (r.method == 'PUT') {
          final b = jsonDecode(r.body);
          f = {...f, 'draft': b['document'], 'version': 2};
          return reply({'funnel': f});
        }
        return reply({
          'funnels': [f],
        });
      });
      await tap(t, find.text('Inquiry questions'));
      await tap(t, find.text('Add question (0/4)'));
      await enter(t, 'question-label-q-1', 'What is your goal?');
      await tap(t, keyed('question-required-q-1'));
      await tap(t, find.text('Add question (1/4)'));
      await enter(t, 'question-label-q-2', 'When?');
      await tap(t, keyed('question-type-q-2'));
      await tap(t, find.text('Multiple choice').last);
      await enter(t, 'question-options-q-2', 'Soon\nLater');
      await tap(t, keyed('question-up-q-2'));
      await enter(t, 'question-label-q-2', 'Preferred timing');
      final text = t.widget<EditableText>(
        find.descendant(
          of: keyed('question-label-q-1'),
          matching: find.byType(EditableText),
        ),
      );
      expect(text.controller.text, 'What is your goal?');
      await tap(t, find.text('Save draft'));
      final questions = funnelQuestions(f['draft']);
      expect(questions.map((q) => q['id']), ['q-2', 'q-1']);
      expect(questions[0]['options'], ['Soon', 'Later']);
      expect(questions[1]['required'], true);
      expect(calls.where((r) => r.method != 'GET').map((r) => r.method), [
        'PUT',
      ]);
      await tap(t, find.text('Inquiry questions'));
      await tap(t, keyed('question-remove-q-1'));
      await tap(t, find.text('Reload saved'));
      await tap(t, find.text('Discard edits'));
      await tap(t, find.text('Inquiry questions'));
      expect(keyed('question-label-q-1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Four-question limit, removal and reused IDs keep the remaining definitions intact',
    (t) async {
      var d = funnelTemplate('consultation');
      await t.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, set) => FunnelQuestionEditor(
                  document: d,
                  onChanged: (q) => set(() => d = {...d, 'questions': q}),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(t, find.text('Inquiry questions'));
      for (var n = 1; n <= 4; n++) {
        await tap(t, find.text('Add question (${n - 1}/4)'));
        await enter(t, 'question-label-q-$n', 'Question $n');
      }
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add question (4/4)'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, keyed('question-remove-q-2'));
      await tap(t, find.text('Add question (3/4)'));
      expect(
        t.widget<TextFormField>(keyed('question-label-q-2')).initialValue,
        '',
      );
      expect(
        funnelQuestions(d).firstWhere((q) => q['id'] == 'q-3')['label'],
        'Question 3',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'Custom-question editor, guided preview and saved answers fit $width',
      (t) async {
        final f = fixture();
        f['draft']['questions'] = sampleQuestions;
        f['draft']['form_mode'] = 'guided';
        await mount(
          t,
          (r) async => reply({
            'funnels': [f],
          }),
          width: width,
        );
        await tap(t, find.text('Inquiry questions'));
        await t.ensureVisible(keyed('question-label-q-2'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot(t, 'questions-editor-${width.toInt()}');
        await tap(t, find.text('Preview').first);
        await tap(t, keyed('form-preview-step-1'));
        await t.ensureVisible(keyed('question-preview-q-1'));
        await t.pumpAndSettle();
        expect(find.textContaining('Choose one: This month'), findsOneWidget);
        expect(t.takeException(), isNull);
        await screenshot(t, 'questions-preview-${width.toInt()}');
        await tap(t, keyed('form-preview-step-2'));
        expect(find.text('Sample response'), findsOneWidget);
        final data = inbox.page(total: 1);
        data['leads'][0]['answers'] = [
          {
            'id': 'q-1',
            'label': 'Original submitted question',
            'type': 'text',
            'value': '<b>Plain text</b>\nA considered response.',
          },
          {'id': 'q-2', 'label': 'Timing', 'type': 'choice', 'value': ''},
        ];
        await t.pumpWidget(
          MaterialApp(
            theme: WfStyle.theme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FunnelInbox(
                  client: FunnelClient(
                    backendBaseUrl: 'https://example.com',
                    headersBuilder: () => {},
                    client: MockClient((r) async => reply(data)),
                  ),
                  funnelId: 'funnel-1',
                  onQueue: (_) async {},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, find.text('Question answers (2)'));
        expect(find.text('Original submitted question'), findsOneWidget);
        expect(
          find.text('<b>Plain text</b>\nA considered response.'),
          findsOneWidget,
        );
        expect(find.text('Not provided'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}

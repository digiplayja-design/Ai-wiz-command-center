import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_questions.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_form_preview.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_questions_test.dart' show tap, enter, keyed;

List<Map<String, dynamic>> questions() => [
  {
    'id': 'q-1',
    'type': 'choice',
    'label': 'Which service?',
    'required': true,
    'options': ['Install', 'Advice'],
  },
  {
    'id': 'q-2',
    'type': 'choice',
    'label': 'Property type',
    'required': true,
    'options': ['Home', 'Office'],
    'show_when': {'question_id': 'q-1', 'equals': 'Install'},
  },
  {
    'id': 'q-3',
    'type': 'text',
    'label': 'How many rooms?',
    'required': true,
    'options': <String>[],
    'show_when': {'question_id': 'q-2', 'equals': 'Home'},
  },
  {
    'id': 'q-4',
    'type': 'text',
    'label': 'What advice?',
    'required': false,
    'options': <String>[],
    'show_when': {'question_id': 'q-1', 'equals': 'Advice'},
  },
];
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
    'Rules survive generated copy and clone independently; broken definitions cannot publish',
    () {
      final current = {
        ...funnelTemplate('consultation'),
        'questions': questions(),
      };
      expect(funnelQuestionsComplete(current), true);
      for (final clone in [
        generatedCopy(current, funnelTemplate('event')),
        copyFunnel(current),
      ]) {
        expect(clone['questions'], current['questions']);
        clone['questions'][1]['show_when']['equals'] = 'Changed';
        expect(current['questions'][1]['show_when']['equals'], 'Install');
      }
      for (final qs in [
        questions()..removeAt(0),
        questions()..[0]['type'] = 'text',
        questions()..[0]['options'] = ['New', 'Other'],
        questions().reversed.toList(),
      ]) {
        expect(funnelQuestionsComplete({'questions': qs}), false);
      }
      expect(
        visibleFunnelQuestions(questions(), {
          'q-1': 'Advice',
          'q-2': 'Home',
        }).map((q) => q['id']),
        ['q-1', 'q-4'],
      );
      expect(
        visibleFunnelQuestions(questions(), {
          'q-1': 'Install',
          'q-2': 'Home',
        }).map((q) => q['id']),
        ['q-1', 'q-2', 'q-3'],
      );
    },
  );
  testWidgets(
    'Condition editing, reordering, parent removal and reused IDs require deliberate repair',
    (t) async {
      var d = {...funnelTemplate('consultation'), 'questions': questions()};
      await t.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
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
      await tap(t, keyed('question-condition-value-q-2-Install'));
      await tap(t, find.text('Advice').last);
      expect(d['questions'][1]['show_when']['equals'], 'Advice');
      await tap(t, keyed('question-up-q-2'));
      expect(funnelQuestionsComplete(d), false);
      expect(find.text('Unavailable question — choose again'), findsOneWidget);
      await tap(t, keyed('question-down-q-2'));
      expect(funnelQuestionsComplete(d), true);
      await tap(t, keyed('question-remove-q-1'));
      expect(funnelQuestionsComplete(d), false);
      expect(d['questions'][0]['show_when']['equals'], '');
      await tap(t, find.text('Add question (3/4)'));
      await enter(t, 'question-label-q-1', 'Replacement');
      expect(funnelQuestionsComplete(d), false);
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'Branch editor and interactive guided preview fit $width and clear discarded paths',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var d = {...funnelTemplate('consultation'), 'questions': questions()};
        Future<void> mount(Widget child) => t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('branch-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: WfStyle.theme,
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: w!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> screenshot(String name) async {
          if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
          await t.runAsync(() async {
            final image = await t
                .renderObject<RenderRepaintBoundary>(keyed('branch-capture'))
                .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/k154-$name-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await mount(
          StatefulBuilder(
            builder: (c, set) => FunnelQuestionEditor(
              document: d,
              onChanged: (q) => set(() => d = {...d, 'questions': q}),
            ),
          ),
        );
        await tap(t, find.text('Inquiry questions'));
        await t.ensureVisible(keyed('question-condition-value-q-2-Install'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot('editor');
        await mount(
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: FunnelFormPreview(
              mode: 'guided',
              brand: 'Studio',
              cta: 'Send inquiry',
              accent: Colors.cyan,
              questions: questions(),
            ),
          ),
        );
        await tap(t, keyed('form-preview-step-1'));
        expect(keyed('question-preview-q-2'), findsNothing);
        await tap(t, keyed('branch-preview-q-1-'));
        await tap(t, find.text('Install').last);
        expect(keyed('question-preview-q-2'), findsOneWidget);
        await tap(t, keyed('branch-preview-q-2-'));
        await tap(t, find.text('Home').last);
        expect(keyed('question-preview-q-3'), findsOneWidget);
        await t.ensureVisible(keyed('question-preview-q-3'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot('preview');
        await tap(t, keyed('form-preview-step-2'));
        expect(find.text('How many rooms?'), findsOneWidget);
        expect(find.text('What advice?'), findsNothing);
        await tap(t, keyed('form-preview-step-1'));
        await tap(t, keyed('branch-preview-q-1-Install'));
        await tap(t, find.text('Advice').last);
        expect(keyed('question-preview-q-2'), findsNothing);
        expect(keyed('question-preview-q-3'), findsNothing);
        expect(keyed('question-preview-q-4'), findsOneWidget);
        await tap(t, keyed('branch-preview-q-1-Advice'));
        await tap(t, find.text('Install').last);
        expect(keyed('question-preview-q-3'), findsNothing);
        expect(keyed('branch-preview-q-2-'), findsOneWidget);
        expect(d['questions'], questions());
        expect(t.takeException(), isNull);
      },
    );
  }
}

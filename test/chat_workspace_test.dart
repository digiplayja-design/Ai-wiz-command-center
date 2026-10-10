import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/chat/chat_workspace.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_button.dart';

Widget app(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, height: 500, child: child)),
  ),
);
KorlixChatTimeline timeline(
  List<KorlixChatTurn> turns, {
  bool busy = false,
  String pending = '',
}) => KorlixChatTimeline(
  turns: turns,
  foreground: Colors.white,
  accent: Colors.cyan,
  surface: Colors.black,
  busy: busy,
  pendingQuestion: pending,
);

void main() {
  testWidgets(
    'question appears above its answer, with selectable readable text and copy',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          timeline([
            const KorlixChatTurn(
              id: 'one',
              question: 'My question',
              answer: 'A helpful answer',
            ),
          ]),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('question-one'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('answer-one'))).dy,
        ),
      );
      expect(find.byType(SelectableText), findsNWidgets(2));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, 'A helpful answer');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'older than four turns stay reachable and pending input stays visible',
    (tester) async {
      final turns = List.generate(
        9,
        (i) => KorlixChatTurn(
          id: '$i',
          question: 'Question $i',
          answer: 'Answer $i',
        ),
      );
      await tester.pumpWidget(
        app(timeline(turns, busy: true, pending: 'Next question')),
      );
      expect(find.text('Next question'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('chat-conversation')),
        const Offset(0, 4000),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.text('Question 0'),
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Question 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty chat offers a picture starter without sending a request', (
    tester,
  ) async {
    bool? image;
    String? prompt;
    await tester.pumpWidget(
      app(
        KorlixChatTimeline(
          turns: const [],
          foreground: Colors.white,
          accent: Colors.cyan,
          surface: Colors.black,
          onStarter: (p, i) {
            prompt = p;
            image = i;
          },
        ),
      ),
    );
    await tester.tap(find.text('Create a picture'));
    expect(image, isTrue);
    expect(prompt, '');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'picture controls fit narrow screens and preserve user selections',
    (tester) async {
      String size = '1024x1024', style = 'auto';
      bool mode = true;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: KorlixChatModeBar(
                imageMode: mode,
                busy: false,
                size: size,
                style: style,
                onModeChanged: (v) => setState(() => mode = v),
                onSizeChanged: (v) => setState(() => size = v),
                onStyleChanged: (v) => setState(() => style = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Square'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Portrait').last);
      await tester.pumpAndSettle();
      expect(size, '1024x1536');
      await tester.tap(find.text('Follow my prompt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Graphic design').last);
      await tester.pumpAndSettle();
      expect(style, 'design');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('image result exposes open and save controls', (tester) async {
    var opened = false, saved = false;
    await tester.pumpWidget(
      app(
        timeline([
          KorlixChatTurn(
            id: 'image',
            question: 'A garden',
            answer: 'Image generated.',
            image: const SizedBox(height: 100),
            onOpenImage: () => opened = true,
            onSaveImage: () => saved = true,
          ),
        ]),
      ),
    );
    await tester.tap(find.text('Open image'));
    await tester.tap(find.text('Save image'));
    expect(opened, isTrue);
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'creation starters follow live language changes and seed localized prompts',
    (tester) async {
      final language = ValueNotifier('en');
      addTearDown(language.dispose);
      final starts = <(String, bool)>[];
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<String>(
            valueListenable: language,
            builder: (_, code, _) => KorlixChatTimeline(
              languageCode: code,
              turns: const [],
              foreground: Colors.white,
              accent: Colors.cyan,
              surface: Colors.black,
              onStarter: (prompt, image) => starts.add((prompt, image)),
            ),
          ),
        ),
      );
      expect(find.text('What would you like to create?'), findsOneWidget);
      List<List<Color>> buttonFaces() => tester
          .widgetList<KorlixActionButton>(find.byType(KorlixActionButton))
          .map((button) {
            final face = tester
                .widgetList<AnimatedContainer>(
                  find.descendant(
                    of: find.byWidget(button),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .firstWhere(
                  (container) =>
                      container.decoration is BoxDecoration &&
                      (container.decoration! as BoxDecoration).gradient != null,
                );
            return ((face.decoration! as BoxDecoration).gradient!
                    as LinearGradient)
                .colors;
          })
          .toList();
      final englishFaces = buttonFaces();
      language.value = 'es';
      await tester.pumpAndSettle();
      expect(find.text('What would you like to create?'), findsNothing);
      expect(find.text('¿Qué te gustaría crear?'), findsOneWidget);
      expect(buttonFaces(), englishFaces);
      expect(
        find.text('Haz una pregunta, desarrolla una idea o crea una imagen.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ayúdame a escribir'));
      await tester.tap(find.text('Explorar una idea'));
      await tester.tap(find.text('Crear una imagen'));
      expect(starts, [
        ('Ayúdame a escribir ', false),
        ('Ayúdame a desarrollar ', false),
        ('', true),
      ]);
      starts.clear();
      language.value = 'fr';
      await tester.pumpAndSettle();
      expect(find.text('¿Qué te gustaría crear?'), findsNothing);
      expect(find.text('Que souhaitez-vous créer ?'), findsOneWidget);
      expect(
        find.text('Posez une question, explorez une idée ou créez une image.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Aidez-moi à écrire'));
      await tester.tap(find.text('Explorer une idée'));
      await tester.tap(find.text('Créer une image'));
      expect(starts, [
        ('Aidez-moi à écrire ', false),
        ('Aidez-moi à réfléchir à ', false),
        ('', true),
      ]);
      expect(buttonFaces(), englishFaces);
      language.value = 'en';
      await tester.pumpAndSettle();
      expect(find.text('What would you like to create?'), findsOneWidget);
      expect(find.text('Que souhaitez-vous créer ?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'translated picture controls preserve API values and selections when language changes',
    (tester) async {
      final language = ValueNotifier('es');
      addTearDown(language.dispose);
      String size = '1024x1024', style = 'auto';
      bool mode = true;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => ValueListenableBuilder<String>(
              valueListenable: language,
              builder: (_, code, _) => SingleChildScrollView(
                child: KorlixChatModeBar(
                  languageCode: code,
                  imageMode: mode,
                  busy: false,
                  size: size,
                  style: style,
                  onModeChanged: (value) => setState(() => mode = value),
                  onSizeChanged: (value) => setState(() => size = value),
                  onStyleChanged: (value) => setState(() => style = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Calidad de imagen extra alta'), findsOneWidget);
      await tester.tap(find.text('Cuadrado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vertical').last);
      await tester.pumpAndSettle();
      expect(size, '1024x1536');
      await tester.tap(find.text('Seguir mis indicaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diseño gráfico').last);
      await tester.pumpAndSettle();
      expect(style, 'design');
      language.value = 'fr';
      await tester.pumpAndSettle();
      expect(find.text('Portrait'), findsOneWidget);
      expect(find.text('Graphisme'), findsOneWidget);
      expect(find.text('Qualité d’image très élevée'), findsOneWidget);
      expect(
        find.text(
          'Décrivez le sujet, le décor, l’éclairage et les mots exacts à inclure.',
        ),
        findsOneWidget,
      );
      expect(size, '1024x1536');
      expect(style, 'design');
      await tester.tap(find.text('Discuter'));
      await tester.pumpAndSettle();
      expect(mode, isFalse);
      expect(find.text('Astra · Maximum'), findsOneWidget);
      language.value = 'en';
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create image'));
      await tester.pumpAndSettle();
      expect(find.text('Portrait'), findsOneWidget);
      expect(find.text('Graphic design'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'translated result controls preserve user content and image actions',
    (tester) async {
      final language = ValueNotifier('es');
      addTearDown(language.dispose);
      String? copied;
      var opened = 0, saved = 0, deleted = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<String>(
            valueListenable: language,
            builder: (_, code, _) => KorlixChatTimeline(
              languageCode: code,
              foreground: Colors.white,
              accent: Colors.cyan,
              surface: Colors.black,
              turns: [
                KorlixChatTurn(
                  id: 'saved',
                  question: 'My original question',
                  answer: 'My original answer',
                  image: const SizedBox(height: 30),
                  onOpenImage: () => opened++,
                  onSaveImage: () => saved++,
                  onDeleteAnswer: () => deleted++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Copiar'));
      await tester.pump();
      expect(copied, 'My original answer');
      expect(find.text('Respuesta copiada'), findsOneWidget);
      await tester.tap(find.text('Abrir imagen'));
      await tester.tap(find.text('Guardar imagen'));
      language.value = 'fr';
      await tester.pumpAndSettle();
      expect(find.text('KORLIX AI'), findsOneWidget);
      expect(find.text('My original question'), findsOneWidget);
      expect(find.text('My original answer'), findsOneWidget);
      await tester.tap(find.text('Ouvrir l’image'));
      await tester.tap(find.text('Enregistrer l’image'));
      await tester.tap(find.byTooltip('Supprimer cette réponse'));
      expect(opened, 2);
      expect(saved, 2);
      expect(deleted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending status changes language without removing the pending question',
    (tester) async {
      final language = ValueNotifier('es');
      addTearDown(language.dispose);
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<String>(
            valueListenable: language,
            builder: (_, code, _) => KorlixChatTimeline(
              languageCode: code,
              turns: const [],
              busy: true,
              pendingQuestion: 'My pending question',
              foreground: Colors.white,
              accent: Colors.cyan,
              surface: Colors.black,
            ),
          ),
        ),
      );
      expect(find.text('Analizando tu solicitud…'), findsOneWidget);
      language.value = 'fr';
      await tester.pump();
      expect(find.text('Analyse de votre demande…'), findsOneWidget);
      expect(find.text('My pending question'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long French creation labels fit a small screen with enlarged text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 560),
                textScaler: TextScaler.linear(1.5),
              ),
              child: SizedBox(
                width: 320,
                height: 560,
                child: KorlixChatTimeline(
                  languageCode: 'fr-FR',
                  turns: const [],
                  foreground: Colors.white,
                  accent: Colors.cyan,
                  surface: Colors.black,
                  onStarter: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Que souhaitez-vous créer ?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

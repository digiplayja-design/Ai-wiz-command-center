import 'dart:async';

import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_screen.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_template_gallery.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_templates.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'picture_studio_test.dart' as fixtures;

const browse = Key('picture-browse-templates');
const change = Key('picture-change-template');
const submit = Key('improve-picture-submit');

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String id) async {
  await tap(tester, find.byKey(change));
  await tap(tester, find.byKey(ValueKey('picture-template-$id')));
}

Future<void> mount(
  WidgetTester tester, {
  bool withPhoto = true,
  String prompt = '',
  PictureEditCallback? edit,
  Future<bool> Function()? consent,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final file = await fixtures.photo();
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: PictureStudioScreen(
        initialFile: withPhoto ? file : null,
        initialPrompt: prompt,
        pickPhoto: () async => file,
        ensureConsent: consent ?? () async => true,
        onOpenTemplates: () =>
            fail('Integrated templates must keep the editor open.'),
        onImprove:
            edit ?? (_, _) async => PictureEditResult(bytes: file.bytes!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('every template fits the existing image editing API contract', () {
    expect(
      pictureTemplates.map((t) => t.id).toSet().length,
      pictureTemplates.length,
    );
    for (final template in pictureTemplates) {
      expect(
        ['enhance', 'restore', 'headshot', 'product', 'cutout', 'custom'],
        contains(template.preset),
        reason: template.id,
      );
      expect(['subtle', 'balanced', 'creative'], contains(template.strength));
      expect([
        'original',
        'warm',
        'cool',
        'vivid',
        'cinematic',
        'mono',
      ], contains(template.look));
      expect([
        'original',
        'brighten',
        'soft',
        'golden',
        'studio',
      ], contains(template.lighting));
      expect([
        'auto',
        '1024x1024',
        '1024x1536',
        '1536x1024',
      ], contains(template.size));
      expect(pictureTemplateCategories, contains(template.category));
      expect(template.promptWith('Keep my glasses.').length, lessThan(12000));
      expect(
        template.promptWith('Keep my glasses.'),
        endsWith('Keep my glasses.'),
      );
    }
  });

  testWidgets(
    'choose a template before a photo, customize it, then explicitly submit',
    (tester) async {
      var calls = 0, consents = 0;
      PictureEditOptions? options;
      await mount(
        tester,
        withPhoto: false,
        prompt: 'Keep my red jacket.',
        consent: () async {
          consents++;
          return true;
        },
        edit: (file, selected) async {
          calls++;
          options = selected;
          expect(file.name, 'source.png');
          return PictureEditResult(bytes: file.bytes!);
        },
      );
      await tap(tester, find.byKey(browse));
      await tester.enterText(
        find.byKey(const Key('picture-template-search')),
        'watercolor',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picture-template-cartoon')), findsNothing);
      await tap(tester, find.byKey(const Key('picture-template-watercolor')));
      expect(calls, 0);
      expect(consents, 0);
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep my red jacket.',
      );
      await tap(tester, find.text('Choose photo'));
      await tap(tester, find.byKey(submit));
      expect(calls, 1);
      expect(consents, 1);
      expect(options!.preset, 'custom');
      expect(options!.strength, 'creative');
      expect(options!.preserveIdentity, isTrue);
      expect(options!.prompt, contains('translucent pigment'));
      expect(options!.prompt, contains('take priority over the template'));
      expect(options!.prompt, endsWith('Keep my red jacket.'));
      expect(find.text('Save PNG'), findsOneWidget);
    },
  );

  testWidgets(
    'switch, dismiss and clear templates without losing personal instructions',
    (tester) async {
      final options = <PictureEditOptions>[];
      await mount(
        tester,
        prompt: 'Keep my glasses.',
        edit: (file, value) async {
          options.add(value);
          return PictureEditResult(bytes: file.bytes!);
        },
      );
      await tap(tester, find.byKey(const Key('picture-preset-restore')));
      await select(tester, 'clean-headshot');
      await select(tester, 'golden-hour');
      await tap(tester, find.byKey(change));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('picture-selected-template')))
            .data,
        'Golden hour',
      );
      await tap(tester, find.byKey(submit));
      expect(options.last.preset, 'enhance');
      expect(options.last.look, 'warm');
      expect(options.last.lighting, 'golden');
      expect(options.last.size, 'auto');
      expect(options.last.prompt, isNot(contains('professional headshot')));
      expect(options.last.prompt, endsWith('Keep my glasses.'));
      await tap(tester, find.byKey(const Key('picture-clear-template')));
      await tap(tester, find.byKey(submit));
      expect(options.last.preset, 'restore');
      expect(options.last.look, 'original');
      expect(options.last.lighting, 'original');
      expect(options.last.prompt, 'Keep my glasses.');
      await select(tester, 'white-studio');
      await tap(tester, find.byKey(const Key('picture-preset-cutout')));
      await tap(tester, find.byKey(submit));
      expect(options.last.preset, 'cutout');
      expect(options.last.prompt, 'Keep my glasses.');
      expect(options.last.size, 'auto');
      expect(find.byKey(const Key('picture-clear-template')), findsNothing);
    },
  );

  testWidgets(
    'version recall retains its template without nesting template prompts',
    (tester) async {
      final options = <PictureEditOptions>[];
      await mount(
        tester,
        prompt: 'Keep my scarf.',
        edit: (file, value) async {
          options.add(value);
          return PictureEditResult(bytes: file.bytes!);
        },
      );
      await select(tester, 'cartoon');
      await tap(tester, find.byKey(submit));
      final firstPrompt = options.single.prompt;
      await tap(tester, find.text('Refine this image'));
      expect(find.byKey(const Key('picture-clear-template')), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        'Make the background softer.',
      );
      await tap(tester, find.byKey(submit));
      expect(options.last.prompt, 'Make the background softer.');
      await tap(tester, find.byKey(const Key('picture-version-1')));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('picture-selected-template')))
            .data,
        'Cartoon portrait',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep my scarf.',
      );
      await tap(tester, find.byKey(submit));
      expect(options.last.prompt, firstPrompt);
      await tap(tester, find.text('Refine this image'));
      await tap(tester, find.text('Start from original'));
      expect(find.byKey(const Key('picture-clear-template')), findsNothing);
    },
  );

  testWidgets(
    'template-only edits require consent and cannot change while submitting',
    (tester) async {
      final consent = Completer<bool>();
      var calls = 0;
      await mount(
        tester,
        consent: () => consent.future,
        edit: (_, _) async {
          calls++;
          throw StateError('Consent denied');
        },
      );
      await select(tester, 'neon-night');
      await tester.ensureVisible(find.byKey(submit));
      await tester.tap(find.byKey(submit));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(browse)).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.byKey(change)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('picture-clear-template')))
            .onPressed,
        isNull,
      );
      expect(calls, 0);
      consent.complete(false);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('picture-selected-template')))
            .data,
        'Neon night',
      );
      expect(
        tester.widget<FilledButton>(find.byKey(submit)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'combined instructions over the server limit are blocked without truncating the draft',
    (tester) async {
      final draft = 'x' * 11999;
      await mount(
        tester,
        prompt: draft,
        edit: (_, _) async => throw StateError('Must not upload'),
      );
      await select(tester, 'clean-headshot');
      await tap(tester, find.byKey(submit));
      expect(
        find.text(
          'Shorten your instructions to leave room for the template directions.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );
    },
  );

  testWidgets(
    'gallery categories, search and empty-state reset work together',
    (tester) async {
      await mount(tester);
      await tap(tester, find.byKey(browse));
      await tap(
        tester,
        find.byKey(const Key('picture-template-category-Products')),
      );
      expect(
        find.byKey(const Key('picture-template-white-studio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('picture-template-clean-headshot')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('picture-template-search')),
        'restorationdoesnotmatch',
      );
      await tester.pumpAndSettle();
      expect(find.text('No templates match your search.'), findsOneWidget);
      await tap(tester, find.text('Show all templates'));
      expect(
        find.byKey(const Key('picture-template-clean-headshot')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('picture-template-restore-memory')),
        findsOneWidget,
      );
    },
  );

  for (final (width, scale) in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets(
      'template gallery supports ${width.toInt()}px and ${scale}x text',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme('pure_white'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const PictureTemplateGallery(selectedId: 'clean-headshot'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Selected'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('picture-template-low-light-rescue')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

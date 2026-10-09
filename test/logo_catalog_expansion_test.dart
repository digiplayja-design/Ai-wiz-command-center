import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_export.dart';
import 'logo_studio_test.dart' as logos;
import 'agent_studio_test.dart' as fixtures;
import 'social_invites_test.dart' as actions;
import 'social_test.dart' as social;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Future.wait(logoTypefaces.map(ensureLogoFonts));
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  test(
    'thousands of examples are varied, reproducible, and retain the brand brief',
    () {
      final seen = <LogoDesign>{};
      final typefaces = <String>{}, marks = <String>{}, palettes = <String>{};
      for (var page = 0; page < 250; page++) {
        final ideas = logoDirections(
          logos.sample,
          round: page,
          keepColors: false,
        );
        expect(ideas.length, 12);
        expect(
          ideas,
          logoDirections(logos.sample, round: page, keepColors: false),
        );
        for (final idea in ideas) {
          expect(
            seen.add(idea),
            isTrue,
            reason: 'Repeated example on page $page',
          );
          expect(idea.name, logos.sample.name);
          expect(idea.tagline, logos.sample.tagline);
          expect(idea.error, isNull);
          expect(LogoDesign.fromJson(idea.json), idea);
          typefaces.add(idea.typeface);
          marks.add(idea.mark);
          palettes.add(idea.primary);
        }
      }
      expect(typefaces.length, 32);
      expect(marks.length, 48);
      expect(palettes.length, 24);
      expect(logoDirections(logos.sample, round: 100000), hasLength(12));
    },
  );

  test(
    'back navigation is exact and browsing keeps only one page of previews',
    () async {
      final f = logos.LogoFixture();
      addTearDown(f.c.dispose);
      f.c.generate(logos.sample);
      final firstPage = List<LogoDesign>.of(f.c.concepts);
      final selected = f.c.design;
      f.c.toggleShortlist(selected);
      await f.c.save();
      final id = f.c.currentProjectId;
      for (var i = 0; i < 100; i++) {
        f.c.nextIdeas();
        expect(f.c.concepts, hasLength(12));
      }
      for (var i = 0; i < 100; i++) {
        f.c.previousIdeas();
      }
      expect(f.c.ideaPage, 0);
      expect(f.c.concepts, firstPage);
      expect(f.c.design, selected);
      expect(f.c.currentProjectId, id);
      expect(f.c.hasUnsavedChanges, isFalse);
      expect(f.c.shortlist, [selected]);
      f.c.configureIdeas(layout: 'Wordmark', keepColors: false);
      expect(f.c.concepts.every((d) => d.layout == 'Wordmark'), isTrue);
      expect(f.c.design, selected);
      f.c.configureIdeas(keepColors: true);
      expect(
        f.c.concepts.every(
          (d) =>
              d.primary == logos.sample.primary &&
              d.secondary == logos.sample.secondary,
        ),
        isTrue,
      );
      expect(f.studio.requests, isEmpty);
    },
  );

  testWidgets(
    'every new family produces distinct lettering and embeds its original font',
    (t) async {
      await t.runAsync(() async {
        final images = <String>{};
        for (final font in logoFontCatalog) {
          final design = logos.sample.copy(
            name: 'Poppy & Pine',
            tagline: '',
            typeface: font.name,
            layout: 'Wordmark',
          );
          final png = await logoPng(design, width: 420, height: 240);
          expect(
            images.add(base64Encode(png)),
            isTrue,
            reason: '${font.name} used identical lettering',
          );
          final svg = await logoSvg(design);
          expect(
            svg,
            contains('font-family="${font.family},${font.name},Arial,sans-serif"'),
          );
          final embedded = RegExp(
            r'data:font/ttf;base64,([A-Za-z0-9+/=]+)',
          ).allMatches(svg).last.group(1)!;
          final source = await rootBundle.load(font.asset);
          expect(embedded == base64Encode(source.buffer.asUint8List()), isTrue);
          expect(
            await rootBundle.loadString(font.license),
            contains('SIL OPEN FONT LICENSE'),
          );
        }
      });
    },
  );

  testWidgets(
    'selected script font survives project and complete brand kit exports',
    (t) async {
      await t.runAsync(() async {
        final design = logos.sample.copy(
          typeface: 'Pacifico',
          mark: 'Butterfly',
        );
        final progress = <int>[];
        final zip = ZipDecoder().decodeBytes(
          await logoBrandKit(
            design,
            onProgress: (done, total, _) {
              expect(total, 28);
              progress.add(done);
            },
          ),
        );
        expect(progress, List.generate(29, (i) => i));
        expect(zip.findFile('fonts/Pacifico.ttf'), isNotNull);
        expect(
          utf8.decode(zip.findFile('fonts/pacifico-OFL.txt')!.content),
          contains('SIL OPEN FONT LICENSE'),
        );
        expect(
          utf8.decode(zip.findFile('logos/primary.svg')!.content),
          contains('Korlix_pacifico'),
        );
        expect(
          utf8.decode(zip.findFile('layouts/monogram.svg')!.content),
          contains('font-family="Korlix_pacifico'),
        );
        expect(
          LogoDesign.fromJson(
            jsonDecode(
              utf8.decode(zip.findFile('project.korlix-logo.json')!.content),
            ),
          ),
          design,
        );
      });
    },
  );

  testWidgets('phone can browse back, filter fonts, and select a real family', (
    t,
  ) async {
    final f = logos.LogoFixture();
    await social.mount(t, f.screen(), width: 390, height: 844);
    await logos.begin(t, f);
    final initial = List<LogoDesign>.of(f.c.concepts);
    await actions.tap(t, find.byKey(const Key('logo-ideas-next')));
    expect(f.c.ideaPage, 1);
    await actions.tap(t, find.byKey(const Key('logo-ideas-previous')));
    expect(f.c.concepts, initial);
    await actions.tap(t, find.byKey(const Key('logo-concept-0')));
    await actions.tap(t, find.byKey(const Key('logo-inspector-2')));
    final search = find.byKey(const Key('logo-font-search'));
    await actions.reveal(t, search);
    await t.enterText(search, 'Pacifico');
    await t.pumpAndSettle();
    await actions.tap(t, find.byKey(const Key('logo-font-Pacifico')));
    expect(f.c.design.typeface, 'Pacifico');
    await fixtures.capture(t, 'logo-expanded-fonts-phone');
    f.c.undo();
    expect(f.c.design.typeface, initial.first.typeface);
    expect(t.takeException(), isNull);
  });
}

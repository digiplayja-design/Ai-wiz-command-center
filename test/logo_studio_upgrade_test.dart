import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';

import 'agent_studio_test.dart' as fixtures;
import 'logo_studio_test.dart' as logos;
import 'picture_studio_test.dart' as pictures;
import 'social_invites_test.dart' as actions;
import 'social_test.dart' as social;

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> enter(WidgetTester t, Finder finder, String text) async {
  await actions.reveal(t, finder);
  await t.enterText(finder, text);
  await t.pumpAndSettle();
}

Future<void> download(WidgetTester t, logos.LogoFixture f, String label) async {
  final before = f.io.files.length;
  final button = find.text(label);
  await actions.reveal(t, button);
  await t.tap(button);
  // Native raster encoding needs real event-loop time in a widget test.
  await t.runAsync(() async {
    for (var i = 0; i < 250 && f.io.files.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await t.pumpAndSettle();
  expect(f.io.files.length, before + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureLogoFonts();
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

  testWidgets('brand preview follows the brief before spending any AI credit', (
    t,
  ) async {
    final f = logos.LogoFixture();
    await social.mount(t, f.screen());
    await enter(t, find.byKey(const Key('logo-brand-name')), 'Poppy & Pine');
    await enter(t, field('Tagline (optional)'), 'Good things grow here');
    await actions.tap(t, find.byKey(const Key('logo-preset-cafe')));
    await actions.reveal(t, find.byKey(const Key('logo-live-preview')));
    final preview = t.widget<LogoCanvas>(
      find.byKey(const Key('logo-live-preview')),
    );
    expect(preview.design.name, 'Poppy & Pine');
    expect(preview.design.tagline, 'Good things grow here');
    expect(preview.design.industry, 'Food & drink');
    expect(f.studio.requests, isEmpty);
    expect(f.consents, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'mobile inspector edits the identity while keeping the canvas visible',
    (t) async {
      final f = logos.LogoFixture();
      await social.mount(t, f.screen());
      await logos.begin(t, f);
      await actions.tap(t, find.byKey(const Key('logo-concept-0')));
      final before = t.getRect(find.byKey(const Key('logo-editor-stage')));
      await actions.tap(t, find.byKey(const Key('logo-inspector-3')));
      await enter(t, field('Accent hex'), 'E38D5A');
      expect(f.c.design.secondary, 'E38D5A');
      expect(t.getRect(find.byKey(const Key('logo-editor-stage'))), before);
      await actions.tap(t, find.byKey(const Key('logo-inspector-1')));
      await actions.tap(t, find.text('Petal'));
      expect(f.c.design.mark, 'Petal');
      await actions.tap(t, find.byKey(const Key('logo-inspector-2')));
      await actions.tap(t, find.text('Wide'));
      expect(f.c.design.typeface, 'Wide');
      expect(t.takeException(), isNull);
      expect(f.studio.requests, isEmpty);
    },
  );

  testWidgets(
    'shortlisted directions survive exploring without replacing edits',
    (t) async {
      final f = logos.LogoFixture();
      await social.mount(t, f.screen());
      await logos.begin(t, f);
      final favorite = f.c.concepts.first;
      await actions.tap(t, find.byKey(const Key('logo-shortlist-0')));
      await actions.tap(t, find.byKey(const Key('logo-shortlist-2')));
      await actions.tap(t, find.byKey(const Key('logo-concept-0')));
      await enter(
        t,
        find.byKey(const Key('logo-edit-name')),
        'My chosen design',
      );
      final edited = f.c.design.json;
      await actions.tap(t, find.byTooltip('Logo directions'));
      await actions.tap(t, find.text('More directions'));
      expect(f.c.design.json, edited);
      expect(f.c.shortlist.length, 2);
      expect(f.c.shortlist.first.json, favorite.json);
      await actions.tap(t, find.byKey(const Key('logo-compare-0')));
      expect(f.c.design.json, favorite.json);
      expect(f.studio.requests, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('custom colors survive returning to the brief and regenerating', (
    t,
  ) async {
    final f = logos.LogoFixture();
    await social.mount(t, f.screen());
    await logos.begin(t, f);
    await actions.tap(t, find.byKey(const Key('logo-concept-0')));
    await actions.tap(t, find.byKey(const Key('logo-inspector-3')));
    await enter(t, field('Primary hex'), '654321');
    await enter(t, field('Accent hex'), 'A1B2C3');
    final paper = f.c.design.paper;
    await actions.tap(t, find.byTooltip('Brand brief'));
    await actions.tap(t, find.byKey(const Key('logo-generate')));
    expect(f.c.design.primary, '654321');
    expect(f.c.design.secondary, 'A1B2C3');
    expect(f.c.design.paper, paper);
    expect(f.studio.requests, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'save updates the open project while Save a copy creates another',
    (t) async {
      final f = logos.LogoFixture();
      await social.mount(t, f.screen());
      await logos.begin(t, f);
      await actions.tap(t, find.byKey(const Key('logo-concept-0')));
      await actions.tap(t, find.byTooltip('Save logo project'));
      final originalId = f.c.projects.single['id'];
      await enter(
        t,
        find.byKey(const Key('logo-edit-name')),
        'Updated original',
      );
      await actions.tap(t, find.text('Save changes'));
      expect(f.c.projects.length, 1);
      expect(f.c.projects.single['id'], originalId);
      expect(f.c.projects.single['design']['name'], 'Updated original');
      await enter(t, find.byKey(const Key('logo-edit-name')), 'Separate copy');
      await actions.tap(t, find.text('Save a copy'));
      expect(f.c.projects.length, 2);
      expect(
        f.c.projects.singleWhere(
          (p) => p['id'] == originalId,
        )['design']['name'],
        'Updated original',
      );
      await actions.tap(t, find.byTooltip('Saved projects'));
      await actions.tap(t, find.text('Open project').first);
      await enter(t, find.byKey(const Key('logo-edit-name')), 'Reopened copy');
      await actions.tap(t, find.text('Save changes'));
      expect(f.c.projects.length, 2);
      expect(f.c.projects.first['design']['name'], 'Reopened copy');
      expect(f.studio.requests, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'download controls apply profile size, white ink and transparency',
    (t) async {
      final f = logos.LogoFixture();
      await social.mount(t, f.screen());
      await logos.begin(t, f);
      await actions.tap(t, find.byTooltip('Brand kit'));
      await actions.tap(t, find.byKey(const Key('logo-export-preset')));
      await t.tap(find.text('Profile icon').last);
      await t.pumpAndSettle();
      await actions.tap(t, find.text('White'));
      await actions.tap(t, find.text('Transparent'));
      await download(t, f, 'Download PNG');
      final file = f.io.files.single;
      expect(file.$1, 'da-final-stop-profile-transparent-white.png');
      expect(file.$2, 'image/png');
      final header = ByteData.sublistView(file.$3);
      expect(header.getUint32(16), 1024);
      expect(header.getUint32(20), 1024);
      await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(file.$3);
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(pixels[3], 0, reason: 'Transparent export has actual alpha.');
        var painted = 0, nonWhite = 0;
        for (var i = 0; i < pixels.length; i += 4) {
          if (pixels[i + 3] != 255) continue;
          painted++;
          if (pixels[i] != 255 ||
              pixels[i + 1] != 255 ||
              pixels[i + 2] != 255) {
            nonWhite++;
          }
        }
        expect(painted, greaterThan(100));
        expect(nonWhite, 0, reason: 'White ink reaches the actual saved PNG.');
        frame.image.dispose();
        codec.dispose();
      });
      expect(f.studio.requests, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('SVG download applies the same chosen size, background and ink', (
    t,
  ) async {
    final f = logos.LogoFixture();
    await social.mount(t, f.screen());
    await logos.begin(t, f);
    await actions.tap(t, find.byTooltip('Edit logo'));
    await actions.tap(t, find.text('Dark'));
    await actions.tap(t, find.byTooltip('Brand kit'));
    await actions.tap(t, find.byKey(const Key('logo-export-preset')));
    await t.tap(find.text('Square').last);
    await t.pumpAndSettle();
    await actions.tap(t, find.text('Black'));
    await actions.tap(t, find.text('Light'));
    await download(t, f, 'Download SVG');
    final file = f.io.files.single;
    final svg = utf8.decode(file.$3);
    expect(file.$1, 'da-final-stop-square-light-black.svg');
    expect(file.$2, 'image/svg+xml');
    expect(svg, contains('width="1600"'));
    expect(svg, contains('height="1600"'));
    expect(svg, contains('viewBox="0 0 1600 1600"'));
    expect(svg, contains('#${f.c.design.paper}'));
    expect(svg, isNot(contains('#${f.c.design.primary}')));
    expect(svg, isNot(contains('#${f.c.design.secondary}')));
    expect(svg, contains('DA FINAL STOP'));
    expect(f.studio.requests, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'AI history downloads the selected artwork with its original brand',
    (t) async {
      final f = logos.LogoFixture();
      final earlier = ImagineResult(
        bytes: await pictures.png(Colors.green),
        brief: logos.sample.copy(name: 'EARLIER BRAND').aiBrief,
        id: 'earlier',
        width: 8,
        height: 8,
      );
      f.c.images.results.addAll([
        ImagineResult(
          bytes: await pictures.png(Colors.blue),
          brief: logos.sample.copy(name: 'LATEST BRAND').aiBrief,
          id: 'latest',
          width: 8,
          height: 8,
        ),
        earlier,
      ]);
      await social.mount(t, f.screen());
      await logos.begin(t, f);
      await actions.tap(t, find.byKey(const Key('logo-ai-result-1')));
      await download(t, f, 'Download AI concept');
      final file = f.io.files.single;
      expect(file.$1, 'earlier-brand.ai-concept.png');
      expect(file.$3, earlier.bytes);
      expect(f.studio.requests, isEmpty);
      await actions.tap(t, find.byTooltip('Saved projects'));
      await actions.tap(t, find.text('New brand'));
      expect(f.c.design.name, isEmpty);
      expect(f.c.concepts, isEmpty);
      expect(f.c.shortlist, isEmpty);
      expect(f.c.images.results, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  for (final size in [
    (320.0, 1.4, 'pure_black'),
    (1024.0, 1.0, 'pure_white'),
  ]) {
    testWidgets('upgraded studio fits ${size.$1}px at ${size.$2}x text', (
      t,
    ) async {
      final f = logos.LogoFixture();
      await social.mount(
        t,
        f.screen(),
        width: size.$1,
        scale: size.$2,
        theme: size.$3,
      );
      await enter(t, find.byKey(const Key('logo-brand-name')), 'Poppy & Pine');
      await actions.reveal(t, find.byKey(const Key('logo-live-preview')));
      await fixtures.capture(t, 'logo-upgrade-start-${size.$1}-${size.$3}');
      expect(t.takeException(), isNull);
      await actions.tap(t, find.byKey(const Key('logo-generate')));
      await actions.tap(t, find.byKey(const Key('logo-shortlist-0')));
      await actions.tap(t, find.byKey(const Key('logo-shortlist-1')));
      await actions.reveal(t, find.byKey(const Key('logo-shortlist')));
      await fixtures.capture(t, 'logo-upgrade-compare-${size.$1}-${size.$3}');
      expect(t.takeException(), isNull);
      await actions.tap(t, find.byKey(const Key('logo-compare-0')));
      await enter(
        t,
        find.byKey(const Key('logo-edit-name')),
        'Poppy & Pine Studio',
      );
      await actions.reveal(t, find.text('Undo'));
      for (final label in ['Undo', 'Redo']) {
        final text = find.text(label);
        final button = find.ancestor(
          of: text,
          matching: find.byType(TextButton),
        );
        final textRect = t.getRect(text),
            buttonRect = t.getRect(button).inflate(.1);
        expect(buttonRect.contains(textRect.topLeft), true);
        expect(buttonRect.contains(textRect.bottomRight), true);
      }
      await fixtures.capture(t, 'logo-upgrade-edit-${size.$1}-${size.$3}');
      expect(t.takeException(), isNull);
      await actions.tap(t, find.byKey(const Key('logo-preview-mode')));
      await actions.reveal(t, find.byKey(const Key('logo-in-use')));
      await fixtures.capture(t, 'logo-upgrade-in-use-${size.$1}-${size.$3}');
      expect(t.takeException(), isNull);
      if (size.$1 < 1000) {
        await actions.tap(t, find.byTooltip('Close brand previews'));
      }
      await actions.tap(t, find.byTooltip('Brand kit'));
      await actions.reveal(t, find.byKey(const Key('logo-export-preview')));
      await fixtures.capture(t, 'logo-upgrade-kit-${size.$1}-${size.$3}');
      await actions.reveal(t, find.text('Download PNG'));
      expect(t.takeException(), isNull);
      expect(f.studio.requests, isEmpty);
    });
  }
}

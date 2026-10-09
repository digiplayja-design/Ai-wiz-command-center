import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_client.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_export.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_screen.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_io.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'imagine_studio_test.dart' as imagine;
import 'social_test.dart' as social;
import 'social_invites_test.dart' as actions;
import 'agent_studio_test.dart' as fixtures;

class LogoFiles extends LogoIo {
  final files = <(String, String, Uint8List)>[];
  String? imported;
  @override
  Future<void> save(
    Uint8List bytes,
    String filename,
    String mime,
    Rect origin,
  ) async {
    files.add((filename, mime, bytes));
  }

  @override
  Future<String?> importProject() async => imported;
}

class PendingStore extends imagine.Briefs {
  final pending = Completer<List<String>>();
  @override
  Future<List<String>> read(String key) => pending.future;
}

class LogoFixture {
  LogoFixture({imagine.Briefs? storage})
    : studio = imagine.Studio(storage: storage);
  final imagine.Studio studio;
  late final c = LogoClient(
    images: studio.client,
    headers: {'Authorization': studio.token},
    store: studio.storage,
  );
  final io = LogoFiles();
  bool consent = true;
  int consents = 0;
  Widget screen() => LogoStudioScreen(
    client: c,
    io: io,
    ensureConsent: () async {
      consents++;
      return consent;
    },
  );
}

const sample = LogoDesign(
  name: 'DA FINAL STOP',
  tagline: 'GOOD FOOD. GREAT COMPANY.',
  industry: 'Food & drink',
  style: 'Organic',
  mark: 'Leaf',
  primary: '16604B',
  secondary: 'CB825B',
  paper: 'F5F3EA',
);

Future<void> begin(WidgetTester t, LogoFixture f) async {
  await actions.reveal(t, find.byKey(const Key('logo-brand-name')));
  await t.enterText(find.byKey(const Key('logo-brand-name')), 'DA FINAL STOP');
  await actions.tap(t, find.byKey(const Key('logo-generate')));
}

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
    'twelve editable directions adapt to the brief and safely restore settings',
    () {
      final options = logoDirections(sample);
      expect(options.length, 12);
      expect(
        options.map((d) => '${d.mark}/${d.layout}').toSet().length,
        greaterThanOrEqualTo(8),
      );
      expect(options.first.mark, 'Leaf');
      expect(options.first.typeface, 'Manrope');
      expect(
        options.every(
          (d) => d.name == sample.name && d.tagline == sample.tagline,
        ),
        true,
      );
      final bad = LogoDesign.fromJson({
        ...sample.json,
        'primary': '<script>',
        'tracking': double.infinity,
        'symbolScale': 999,
        'mark': 'evil.svg',
        'name': 'X' * 200,
      });
      expect(bad.primary, '2563EB');
      expect(bad.tracking, 1);
      expect(bad.symbolScale, 1.25);
      expect(bad.mark, 'Orbit');
      expect(bad.name.length, 50);
      expect(sample.aiBrief.compiledPrompt, contains('DA FINAL STOP'));
      expect(sample.aiBrief.compiledPrompt, contains('#16604B'));
      expect(
        () => LogoDesign.fromJson({'version': 7, 'name': 'Brand'}),
        throwsFormatException,
      );
    },
  );
  test(
    'editing supports undo/redo and saved projects round-trip independently',
    () async {
      final f = LogoFixture();
      f.c.generate(sample);
      final original = f.c.design;
      f.c.update(original.copy(name: 'Updated brand', primary: '112233'));
      f.c.undo();
      expect(f.c.design.name, original.name);
      f.c.redo();
      expect(f.c.design.primary, '112233');
      await f.c.save();
      expect(f.c.projects.length, 1);
      final key = f.studio.storage.values.keys.single;
      expect(key, startsWith('korlix_logo_projects_v1_'));
      f.c.import(jsonEncode(sample.json));
      expect(f.c.design.name, sample.name);
      expect(f.c.projects.first['design']['name'], 'Updated brand');
      await f.c.delete(f.c.projects.first['id']);
      expect(f.c.projects, isEmpty);
      expect(
        f.studio.requests,
        isEmpty,
        reason: 'Editable logos are generated locally',
      );
      f.c.dispose();
    },
  );
  test(
    'failed saved-project reads cannot overwrite existing projects',
    () async {
      final store = imagine.Briefs()..failRead = true;
      final f = LogoFixture(storage: store);
      f.c.generate(sample);
      await expectLater(f.c.save(), throwsStateError);
      expect(store.values, isEmpty);
      expect(f.c.saving, false);
      expect(f.c.loaded, false);
      f.c.dispose();
    },
  );
  test(
    'account changes discard late project loads and clear private state',
    () async {
      final store = PendingStore(), f = LogoFixture(storage: store);
      f.c.generate(sample);
      final pending = f.c.load();
      final check = expectLater(pending, throwsA(isA<ImagineException>()));
      f.studio.change();
      store.pending.complete([
        jsonEncode({'id': 'old', 'design': sample.json}),
      ]);
      await check;
      expect(f.c.available, false);
      expect(f.c.design.name, isEmpty);
      expect(f.c.concepts, isEmpty);
      expect(f.c.projects, isEmpty);
      f.c.dispose();
    },
  );
  testWidgets(
    'exports contain vector shapes, transparent pixels, brand assets and a restorable project',
    (t) async {
      await t.runAsync(() async {
        final escaped = await logoSvg(
          sample.copy(name: 'Café & <script>alert(1)</script>'),
        );
        expect(escaped, contains('&amp;'));
        expect(escaped, contains('&lt;script&gt;'));
        expect(escaped, isNot(contains('<script>')));
        expect(escaped, contains('<path '));
        expect(escaped, isNot(contains('<image ')));
        final mono = sample.copy(layout: 'Monogram');
        expect(
          await logoSvg(mono, ink: LogoInk.white),
          contains('mask="url(#initials)"'),
        );
        final png = await logoPng(sample, width: 600, height: 400);
        expect(ByteData.sublistView(png).getUint32(16), 600);
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final rgba = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(
          rgba!.getUint8(3),
          0,
          reason: 'Transparent means alpha, not a checkerboard',
        );
        expect(
          rgba.buffer.asUint8List().where((v) => v != 0).length,
          greaterThan(1000),
        );
        frame.image.dispose();
        codec.dispose();
        final kit = await logoBrandKit(sample);
        final archive = ZipDecoder().decodeBytes(kit);
        final names = archive.files.map((f) => f.name).toSet();
        expect(
          names,
          containsAll([
            'logos/primary.svg',
            'logos/black.svg',
            'logos/white.svg',
            'logos/transparent-2400.png',
            'social/avatar-1024.png',
            'social/cover-1500x500.png',
            'brand-guide.pdf',
            'project.korlix-logo.json',
            'fonts/LICENSE.txt',
          ]),
        );
        final restored = LogoDesign.fromJson(
          jsonDecode(
            utf8.decode(archive.findFile('project.korlix-logo.json')!.content),
          ),
        );
        expect(restored.json, sample.json);
        expect(
          ascii.decode(
            archive.findFile('brand-guide.pdf')!.content.take(5).toList(),
          ),
          '%PDF-',
        );
        final dir = Platform.environment['AGENT_STUDIO_SCREENSHOTS'];
        if (dir != null) {
          await Directory(dir).create(recursive: true);
          await File(
            '$dir/sample-logo.png',
          ).writeAsBytes(await logoPng(sample, surface: LogoSurface.light));
          await File(
            '$dir/sample-logo.svg',
          ).writeAsString(await logoSvg(sample));
          await File(
            '$dir/brand-guide.pdf',
          ).writeAsBytes(archive.findFile('brand-guide.pdf')!.content);
          await File('$dir/brand-kit.zip').writeAsBytes(kit);
        }
      });
    },
  );
  testWidgets(
    'brand flow generates locally, edits, undoes and exports project through explicit action',
    (t) async {
      final f = LogoFixture();
      await social.mount(t, f.screen());
      await begin(t, f);
      expect(f.c.concepts.length, 12);
      expect(f.studio.requests, isEmpty);
      await actions.tap(t, find.byKey(const ValueKey('logo-concept-0')));
      await actions.reveal(t, find.byKey(const Key('logo-edit-name')));
      await t.enterText(find.byKey(const Key('logo-edit-name')), 'FINAL STOP');
      expect(f.c.design.name, 'FINAL STOP');
      await actions.tap(t, find.text('Undo'));
      expect(f.c.design.name, 'DA FINAL STOP');
      await actions.tap(t, find.byTooltip('Save logo project'));
      expect(f.c.projects.length, 1);
      await actions.tap(t, find.byTooltip('Brand kit'));
      await actions.tap(t, find.text('Project backup'));
      expect(f.io.files.single.$1, 'da-final-stop.korlix-logo.json');
      expect(
        jsonDecode(utf8.decode(f.io.files.single.$3))['name'],
        'DA FINAL STOP',
      );
      expect(f.studio.requests, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'AI concepts need explicit consent and reuse authenticated credit-controlled generation',
    (t) async {
      final f = LogoFixture()..consent = false;
      f.studio.invalidBody = jsonEncode({
        ...jsonDecode((await f.studio.response()).body) as Map<String, dynamic>,
        'logoDirection': {
          'conceptName': 'A welcoming table',
          'summary':
              'A warm organic mark—“Café” lettering, balanced and clear.',
          'planningModel': 'gpt-6-astra',
          'reasoningEffort': 'max',
        },
      });
      await social.mount(t, f.screen());
      await begin(t, f);
      await actions.tap(t, find.text('Explore with AI'));
      expect(f.consents, 1);
      expect(f.studio.requests, isEmpty);
      f.consent = true;
      await actions.tap(t, find.text('Explore with AI'));
      expect(f.studio.requests.length, 1);
      expect(f.studio.requests.single['prompt'], contains('DA FINAL STOP'));
      expect(f.studio.requests.single['imageStyle'], 'design');
      expect(f.studio.requests.single['logoBrief']['name'], 'DA FINAL STOP');
      expect(
        f.studio.requests.single['logoBrief']['typeface'],
        f.c.design.typeface,
      );
      expect(
        f.studio.requests.single['logoBrief']['primary'],
        f.c.design.primary,
      );
      expect(f.c.images.results.length, 1);
      expect(find.text('A welcoming table'), findsOneWidget);
      expect(
        find.text('A warm organic mark—“Café” lettering, balanced and clear.'),
        findsOneWidget,
      );
      await actions.reveal(t, find.text('Download AI concept'));
      await t.tap(find.text('Download AI concept'));
      await t.runAsync(() async {
        // PNG decoding uses the native event loop outside the widget-test clock.
        for (var i = 0; i < 250 && f.io.files.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await t.pumpAndSettle();
      expect(f.io.files.single.$2, 'image/png');
      expect(f.io.files.single.$3, f.c.images.results.single.bytes);
      expect(f.studio.requests.length, 1);
      expect(find.textContaining('Invalid argument'), findsNothing);
      expect(find.textContaining('data:image/png;base64,'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'imported project opens editor; account switch clears it and disables exports',
    (t) async {
      final f = LogoFixture();
      f.io.imported = jsonEncode(sample.json);
      await social.mount(t, f.screen());
      await actions.tap(t, find.byTooltip('Saved projects'));
      await actions.tap(t, find.text('Import project'));
      expect(f.c.design.name, sample.name);
      f.studio.change();
      await t.pumpAndSettle();
      expect(find.textContaining('Your session changed.'), findsOneWidget);
      expect(find.byType(LogoCanvas), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(f.io.files, isEmpty);
    },
  );
  for (final v in [
    (320.0, 1.4, 'pure_black'),
    (390.0, 1.0, 'korlix_blue'),
    (390.0, 1.0, 'pure_white'),
    (1280.0, 1.0, 'korlix_blue'),
  ]) {
    testWidgets('logo layouts fit ${v.$1}px ${v.$2}x ${v.$3}', (t) async {
      final f = LogoFixture();
      await social.mount(t, f.screen(), width: v.$1, scale: v.$2, theme: v.$3);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'logo-start-${v.$1}-${v.$3}');
      await begin(t, f);
      await fixtures.capture(t, 'logo-ideas-${v.$1}-${v.$3}');
      await actions.tap(t, find.byKey(const ValueKey('logo-concept-0')));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'logo-edit-${v.$1}-${v.$3}');
      await actions.tap(t, find.text('Transparent'));
      expect(t.takeException(), isNull);
      await actions.tap(t, find.byTooltip('Brand kit'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'logo-kit-${v.$1}-${v.$3}');
      await actions.tap(t, find.byTooltip('Saved projects'));
      expect(t.takeException(), isNull);
    });
  }
}

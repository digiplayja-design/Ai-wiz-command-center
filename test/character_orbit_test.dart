import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/characters/character_catalog.dart';
import 'package:ai_wiz_command_center/characters/character_orbit.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

final allIds = korlixCharacters.map((c) => c.id).toSet();
void main() {
  testWidgets('dragging, taps and arrows select and save a character', (
    tester,
  ) async {
    String selected = 'jj';
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('korlix_blue'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: KorlixCharacterOrbit(
                selectedId: selected,
                availableIds: allIds,
                onSelected: (id) async {
                  saved.add(id);
                  setState(() => selected = id);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orbit-next')));
    await tester.pumpAndSettle();
    expect(selected, 'phil');
    await tester.tap(find.byKey(const ValueKey('orbit-previous')));
    await tester.pumpAndSettle();
    expect(selected, 'jj');
    final drag = find.byKey(const ValueKey('character-orbit-drag'));
    await tester.drag(drag, const Offset(-235, 0));
    await tester.pumpAndSettle();
    expect(selected, isNot('jj'));
    await tester.tap(find.byTooltip('Yuna'));
    await tester.pumpAndSettle();
    expect(selected, 'yuna');
    expect(saved.length, 4);
    Focus.of(tester.element(drag)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected, 'ji_a');
    expect(saved.length, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saving disables duplicate choices and external selection updates the orbit',
    (tester) async {
      var calls = 0;
      Widget app(String id, bool busy) => MaterialApp(
        home: Scaffold(
          body: KorlixCharacterOrbit(
            selectedId: id,
            availableIds: allIds,
            saving: busy,
            onSelected: (_) async {
              calls++;
            },
          ),
        ),
      );
      await tester.pumpWidget(app('jj', true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('orbit-next')));
      expect(calls, 0);
      await tester.pumpWidget(app('yuna', false));
      await tester.pumpAndSettle();
      final yuna = tester.getCenter(
        find.byKey(const ValueKey('orbit-position-yuna')),
      );
      final jj = tester.getCenter(
        find.byKey(const ValueKey('orbit-position-jj')),
      );
      expect(yuna.dy, greaterThan(jj.dy));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone, enlarged text and tablet layouts render without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['KORLIX_ORBIT_REVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        for (final font in [
          ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
          (
            'MaterialIcons',
            '/workspace/scratch/554afba260c4/tooling/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          await (FontLoader(font.$1)..addFont(
                File(font.$2).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        }
      });
    }
    for (final theme in ['korlix_blue', 'pure_white'])
      for (final size in [(390.0, 1.0), (320.0, 2.0), (1024.0, 1.0)]) {
        tester.view.physicalSize = Size(size.$1, size.$2 == 2 ? 1500 : 1000);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme(theme),
            home: MediaQuery(
              data: MediaQueryData(
                size: tester.view.physicalSize,
                textScaler: TextScaler.linear(size.$2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: boundary,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: KorlixCharacterOrbit(
                        selectedId: 'jj',
                        availableIds: allIds,
                        onSelected: (_) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$theme $size');
        if (output != null) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '$output/$theme-${size.$1.toInt()}-${size.$2}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
  });
}

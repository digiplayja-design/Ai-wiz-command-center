import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_projection_presentation.dart';

Finder control(String action) => find.byKey(ValueKey('projection-native-$action'));

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand(
    child: ColoredBox(color: Colors.black),
  );
}

void main() {
  test('native viewport follows the window, including keyboard and narrow landscape', () {
    expect(projectionNativeViewport(window: const Size(700, 1100),
        viewport: const Size(700, 280), preference: 'auto')['landscape'], isFalse,
        reason: 'A portrait window does not rotate its layout because a keyboard opens');
    expect(projectionNativeViewport(window: const Size(568, 320),
        viewport: const Size(568, 260), preference: 'auto')['landscape'], isTrue,
        reason: 'The actual native landscape view can be narrower than 600 px');
    expect(projectionNativeViewport(window: const Size(390, 844),
        viewport: const Size(844, 330), preference: 'landscape')['landscape'], isTrue);
    expect(projectionNativeViewport(window: const Size(700, 320),
        viewport: const Size(479, 260), preference: 'landscape')['landscape'], isFalse);
    expect(projectionNativeViewport(window: const Size(700, 320),
        viewport: const Size(480, 260), preference: 'landscape')['landscape'], isTrue);
  });

  test('orientation requests are deduplicated and restore the OS default', () async {
    final calls = <List<DeviceOrientation>>[];
    final orientation = BrainProjectionOrientation(setOrientations: (value) async {
      calls.add(List.of(value));
    });
    await orientation.update('landscape');
    await orientation.update('landscape');
    await orientation.update('auto');
    await orientation.update('portrait');
    await orientation.restore();
    expect(calls, [
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      <DeviceOrientation>[],
      [DeviceOrientation.portraitUp],
      <DeviceOrientation>[],
    ]);
  });

  test('late closing orientation cannot restore over a newly opened view', () async {
    final calls = <List<DeviceOrientation>>[];
    final pending = Completer<void>();
    final previous = BrainProjectionOrientation(setOrientations: (value) async {
      calls.add(List.of(value));
      await pending.future;
    });
    final first = previous.update('landscape');
    await Future<void>.delayed(Duration.zero);
    final closing = previous.restore();
    final current = BrainProjectionOrientation(setOrientations: (value) async {
      calls.add(List.of(value));
    });
    final next = current.update('portrait');
    pending.complete();
    await Future.wait([first, closing, next]);
    expect(calls, [
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      [DeviceOrientation.portraitUp],
    ]);
    await current.restore();
  });

  testWidgets('native actions keep positions and 44 px targets in every phase', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final actions = <String>[];
    for (final size in [const Size(390, 844), const Size(667, 340), const Size(568, 320)]) {
      tester.view.physicalSize = size;
      Map<String, Rect>? firstPositions;
      for (final phase in ['connecting', 'listening', 'paused', 'complete', 'error']) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(
          child: BrainProjectionPresentation(
            voice: {'phase': phase, 'active': phase == 'listening', 'paused': phase == 'paused'},
            layoutPreference: 'auto',
            onClose: () => actions.add('back'),
            onVoiceAction: actions.add,
            onLayout: actions.add,
            child: const Center(child: Text('Loading or unavailable web content')),
          ),
        ))));
        final positions = <String, Rect>{};
        for (final action in ['back', 'pause', 'resume', 'stop']) {
          final rect = tester.getRect(control(action));
          positions[action] = rect;
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
        if (firstPositions != null) expect(positions, firstPositions);
        firstPositions ??= positions;
        final pause = tester.widget<OutlinedButton>(control('pause'));
        final resume = tester.widget<OutlinedButton>(control('resume'));
        final stop = tester.widget<OutlinedButton>(control('stop'));
        expect(pause.onPressed != null, phase == 'listening' || phase == 'connecting');
        expect(resume.onPressed != null, phase == 'paused');
        expect(stop.onPressed != null, !['complete', 'error'].contains(phase));
        if (phase == 'paused') {
          await tester.tap(control('resume'));
          expect(actions.last, 'resume');
        }
        if (phase == 'listening') {
          await tester.tap(control('stop'));
          expect(actions.last, 'stop');
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('explicit format retains the child while native controls rotate', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final probe = GlobalKey<_ProbeState>();
    Future<void> show(String layout) => tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SafeArea(child: BrainProjectionPresentation(
        voice: const {'active': true, 'phase': 'listening'},
        layoutPreference: layout,
        onClose: () {}, onVoiceAction: (_) {}, onLayout: (_) {},
        child: _Probe(key: probe),
      )),
    )));
    await show('auto');
    final original = probe.currentState;
    await show('landscape');
    expect(probe.currentState, same(original));
    expect(tester.widget<RotatedBox>(find.byKey(const ValueKey('projection-presentation'))).quarterTurns, 1);
    expect(tester.getSize(find.byKey(probe)).width,
        greaterThan(tester.getSize(find.byKey(probe)).height));
    await show('auto');
    expect(probe.currentState, same(original));
    expect(tester.widget<RotatedBox>(find.byKey(const ValueKey('projection-presentation'))).quarterTurns, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard keeps native Stop and Back above the obscured area', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(
      child: BrainProjectionPresentation(
        voice: const {'active': true, 'phase': 'listening'},
        layoutPreference: 'auto',
        onClose: () => actions.add('back'), onVoiceAction: actions.add, onLayout: (_) {},
        child: const SizedBox.expand(),
      ),
    ))));
    for (final action in ['back', 'pause', 'resume', 'stop']) {
      expect(tester.getRect(control(action)).bottom, lessThanOrEqualTo(444));
    }
    await tester.tap(control('stop'));
    await tester.tap(control('back'));
    expect(actions, ['stop', 'back']);
    expect(tester.takeException(), isNull);
  });
}

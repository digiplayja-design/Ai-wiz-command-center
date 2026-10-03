import 'dart:async';

import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SoundService extends KorlixSoundService {
  KorlixSoundSettings value = const KorlixSoundSettings();
  bool activated = false;
  bool activationFails = false;
  bool persistenceFails = false;
  Completer<bool>? activationGate;
  String? failure;
  int restores = 0;
  final events = <String>[];
  final saved = <KorlixSoundSettings>[];

  @override
  KorlixSoundSettings get settings => value;
  @override
  bool get ready => activated;
  @override
  bool get blocked => activationFails;
  @override
  String? get storageError => failure;

  @override
  Future<void> restore() async => restores++;

  @override
  Future<bool> activate() async {
    events.add('activate');
    activated = activationGate == null
        ? !activationFails
        : await activationGate!.future;
    notifyListeners();
    return activated;
  }

  @override
  Future<void> preview(KorlixSound sound) async {
    events.add('preview:${sound.name}');
  }

  @override
  Future<bool> update(KorlixSoundSettings settings) async {
    value = settings;
    saved.add(settings);
    failure = persistenceFails
        ? 'Could not save your sound preferences.'
        : null;
    notifyListeners();
    return !persistenceFails;
  }

  void outsideUpdate(KorlixSoundSettings settings) {
    value = settings;
    notifyListeners();
  }
}

Future<void> _show(
  WidgetTester tester,
  _SoundService service, {
  double width = 1000,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: KorlixSoundSettingsScreen(service: service),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('activation precedes preview and a browser block is visible', (
    tester,
  ) async {
    final service = _SoundService();
    await _show(tester, service);
    expect(service.restores, 1);
    await _tap(tester, 'sound-enable');
    expect(service.events, ['activate', 'preview:bell']);
    expect(find.text('Audio is ready for this session.'), findsOneWidget);

    service.activationFails = true;
    await _tap(tester, 'sound-preview-messages');
    expect(service.events, ['activate', 'preview:bell', 'activate']);
    expect(find.textContaining('Audio could not start.'), findsOneWidget);
  });

  testWidgets('pack, categories and master mute save independently', (
    tester,
  ) async {
    final service = _SoundService();
    await _show(tester, service);
    await _tap(tester, 'sound-pack-soft');
    await _tap(tester, 'sound-switch-messages');
    expect(service.settings.pack, KorlixSoundPack.soft);
    expect(service.settings.messages, false);
    expect(service.settings.calls, true);
    await _tap(tester, 'sound-preview-messages');
    expect(service.events.last, 'preview:message');

    await _tap(tester, 'sound-switch-enabled');
    expect(service.settings.enabled, false);
    expect(service.settings.calls, true);
    final callToggle = tester.widget<Switch>(
      find.byKey(const ValueKey('sound-switch-calls')),
    );
    final messagePreview = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('sound-preview-messages')),
    );
    expect(callToggle.onChanged, isNull);
    expect(messagePreview.onPressed, isNull);
    expect(find.text('All app sound effects are muted.'), findsOneWidget);
  });

  testWidgets('leaving settings during activation does not start a preview', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final service = _SoundService()..activationGate = gate;
    await _show(tester, service);
    await _tap(tester, 'sound-enable');
    expect(service.events, ['activate']);
    await tester.pumpWidget(const SizedBox());
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(service.events, ['activate']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed preference storage is visible and retryable', (
    tester,
  ) async {
    final service = _SoundService()..persistenceFails = true;
    await _show(tester, service);
    await _tap(tester, 'sound-pack-classic');
    expect(service.settings.pack, KorlixSoundPack.classic);
    expect(find.byKey(const ValueKey('sound-storage-error')), findsOneWidget);
    service.persistenceFails = false;
    await _tap(tester, 'sound-retry-save');
    expect(service.saved.length, 2);
    expect(service.saved.last.pack, KorlixSoundPack.classic);
    expect(find.byKey(const ValueKey('sound-storage-error')), findsNothing);
  });

  testWidgets('external preference changes and volume edits stay in sync', (
    tester,
  ) async {
    final service = _SoundService();
    await _show(tester, service);
    service.outsideUpdate(service.settings.copyWith(volume: .2, clicks: false));
    await tester.pumpAndSettle();
    expect(find.text('Volume · 20%'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('sound-switch-clicks')))
          .value,
      false,
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('sound-volume')),
    );
    slider.onChanged!(.8);
    await tester.pump();
    expect(find.text('Volume · 80%'), findsOneWidget);
    expect(service.saved, isEmpty);
    slider.onChangeEnd!(.8);
    await tester.pumpAndSettle();
    expect(service.saved.single.volume, .8);
    expect(service.settings.clicks, false);
  });

  testWidgets('quiet hours explain overnight and all-day rules', (
    tester,
  ) async {
    final service = _SoundService();
    await _show(tester, service);
    expect(find.byKey(const ValueKey('sound-quiet-start')), findsNothing);
    await _tap(tester, 'sound-switch-quiet');
    expect(service.settings.quietHours, true);
    expect(find.textContaining('continues into the next day'), findsOneWidget);
    await _tap(tester, 'sound-quiet-start');
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9');
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(service.settings.quietStartMinute, 1290);
    expect(service.settings.quietEndMinute, 420);
    service.outsideUpdate(
      service.settings.copyWith(quietStartMinute: 420, quietEndMinute: 420),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('mute sounds all day'), findsOneWidget);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('320px and 2x text has no overflow in ${brightness.name}', (
      tester,
    ) async {
      final service = _SoundService()
        ..value = const KorlixSoundSettings(quietHours: true);
      await _show(
        tester,
        service,
        width: 320,
        scale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, 'sound-pack-classic');
      await _tap(tester, 'sound-preview-calls');
      await tester.ensureVisible(
        find.byKey(const ValueKey('sound-device-note')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sound effects use no AI GAS.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

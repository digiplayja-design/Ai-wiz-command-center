import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/input_tools/upload_studio.dart';
import 'package:ai_wiz_command_center/input_tools/voice_composer.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_button.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_grid.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

PlatformFile file(String name, {int size = 3, bool readable = true}) =>
    PlatformFile(
      name: name,
      size: size,
      bytes: readable ? Uint8List.fromList([1, 2, 3]) : null,
    );

class FakeDictation extends KorlixDictationEngine {
  int starts = 0, cancels = 0, initializations = 0;
  bool disposed = false, fail = false;
  String? lastLocale, finalWords;
  late ValueChanged<String> words, status, error;
  Completer<List<KorlixVoiceLocale>>? pending;
  @override
  Future<List<KorlixVoiceLocale>> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  }) async {
    initializations++;
    status = onStatus;
    error = onError;
    if (fail) throw StateError('Speech recognition is unavailable.');
    return pending?.future ??
        [
          const KorlixVoiceLocale('en_US', 'English'),
          const KorlixVoiceLocale('es_ES', 'Spanish'),
        ];
  }

  @override
  Future<void> start({
    String? locale,
    required ValueChanged<String> onWords,
    required ValueChanged<double> onLevel,
  }) async {
    starts++;
    lastLocale = locale;
    words = onWords;
    status('listening');
    onLevel(15);
  }

  @override
  Future<void> stop() async {
    if (finalWords != null) words(finalWords!);
    status('done');
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

Future<void> open(
  WidgetTester tester,
  Widget child,
  ValueChanged<Object?> onResult,
) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              onResult(
                await Navigator.of(context).push<Object>(
                  MaterialPageRoute<Object>(builder: (_) => child),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, 'Open');
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

String draft(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  test(
    'upload validation enforces count, type, byte limits and readable content',
    () {
      expect(validateKorlixUploads([file('Report.PDF')]), isNull);
      expect(
        validateKorlixUploads(List.generate(9, (i) => file('$i.pdf'))),
        contains('8 files'),
      );
      expect(
        validateKorlixUploads([file('script.exe')]),
        contains('not supported'),
      );
      expect(
        validateKorlixUploads([
          file('large.pdf', size: korlixUploadMaxBytes + 1),
        ]),
        contains('15 MB'),
      );
      expect(
        validateKorlixUploads([file('unreadable.txt', readable: false)]),
        contains('could not be read'),
      );
      expect(
        validateKorlixUploads([file('limit.pdf', size: korlixUploadMaxBytes)]),
        isNull,
      );
    },
  );

  testWidgets('two-column buttons stay equal across sections and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 390.0, 1100.0]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = Size(width, 2500);
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme('korlix_blue'),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        for (final title in [
                          'For business',
                          'For personal use',
                        ])
                          KorlixActionSection(
                            title: title,
                            description: 'Choose a tool',
                            icon: Icons.apps,
                            children: [
                              for (final label in [
                                'Inventory Studio',
                                'Cybersecurity Defender',
                                'Improve my picture',
                              ])
                                KorlixActionButton(
                                  label: label,
                                  icon: Icons.apps,
                                  tile: true,
                                  onPressed: () {},
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buttons = find.byType(KorlixActionButton);
        final size = tester.getSize(buttons.first);
        for (var i = 0; i < 6; i++) {
          expect(tester.getSize(buttons.at(i)), size);
        }
        expect(
          tester.getTopLeft(buttons.at(0)).dy,
          tester.getTopLeft(buttons.at(1)).dy,
        );
        expect(
          tester.getTopLeft(buttons.at(2)).dx,
          tester.getTopLeft(buttons.at(0)).dx,
        );
        expect(
          tester.getTopLeft(buttons.at(2)).dy,
          greaterThan(tester.getTopLeft(buttons.at(1)).dy),
        );
        expect(tester.takeException(), isNull, reason: '$width / $scale');
      }
    }
  });

  testWidgets('upload appends and deduplicates, then returns only on Attach', (
    tester,
  ) async {
    Object? result;
    final original = file('first.pdf');
    await open(
      tester,
      KorlixUploadStudio(
        initialFiles: [original],
        initialPrompt: 'My question',
        pickFiles: () async => [original, file('second.csv')],
      ),
      (v) => result = v,
    );
    await tap(tester, 'Files');
    expect(find.text('Your selection · 2/8'), findsOneWidget);
    expect(find.textContaining('duplicate file was skipped'), findsOneWidget);
    expect(result, isNull);
    await tap(tester, 'Compare');
    await tap(tester, 'Attach 2 files');
    expect((result as KorlixUploadDraft).files.map((f) => f.name), [
      'first.pdf',
      'second.csv',
    ]);
    expect(
      (result as KorlixUploadDraft).prompt,
      startsWith('Compare these files'),
    );
  });

  testWidgets('invalid upload batch keeps the previous selection and draft', (
    tester,
  ) async {
    await open(
      tester,
      KorlixUploadStudio(
        initialFiles: [file('first.pdf')],
        initialPrompt: 'Keep this',
        pickFiles: () async => [file('new.csv'), file('bad.exe')],
      ),
      (_) {},
    );
    await tap(tester, 'Files');
    expect(find.textContaining('not supported'), findsOneWidget);
    expect(find.text('Your selection · 1/8'), findsOneWidget);
    expect(draft(tester), 'Keep this');
  });

  testWidgets(
    'upload camera result stays local and cancelling discards edits',
    (tester) async {
      var returned = false;
      Object? result;
      final original = [file('original.pdf')];
      await open(
        tester,
        KorlixUploadStudio(
          initialFiles: original,
          capture: (_) async => file('capture.jpg'),
        ),
        (v) {
          returned = true;
          result = v;
        },
      );
      await tap(tester, 'Take a photo');
      expect(find.text('Your selection · 2/8'), findsOneWidget);
      expect(returned, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(returned, isTrue);
      expect(original, hasLength(1));
    },
  );

  testWidgets(
    'account change closes uploads and ignores a late picker result',
    (tester) async {
      final revision = ValueNotifier(0);
      final pending = Completer<List<PlatformFile>>();
      var valid = true;
      Object? result;
      await open(
        tester,
        KorlixUploadStudio(
          initialPrompt: 'Private draft',
          pickFiles: () => pending.future,
          sessionChanges: revision,
          isSessionCurrent: () => valid,
        ),
        (v) => result = v,
      );
      await tester.tap(find.text('Files'));
      await tester.pump();
      valid = false;
      revision.value++;
      await tester.pumpAndSettle();
      pending.complete([file('private.pdf')]);
      await tester.pumpAndSettle();
      expect(find.byType(KorlixUploadStudio), findsNothing);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
      revision.dispose();
    },
  );

  testWidgets(
    'voice starts on request, preserves typed draft, and deduplicates partial words',
    (tester) async {
      final engine = FakeDictation();
      Object? result;
      await open(
        tester,
        KorlixVoiceComposer(initialText: 'Existing question', engine: engine),
        (v) => result = v,
      );
      expect(engine.initializations, 0);
      expect(engine.starts, 0);
      await tap(tester, 'Start dictation');
      engine.words('find');
      engine.words('find inventory');
      await tester.pump();
      expect(draft(tester), 'Existing question\nfind inventory');
      expect(engine.lastLocale, 'en_US');
      expect(result, isNull);
      engine.finalWords = 'Find inventory nearby.';
      await tap(tester, 'Stop dictation');
      expect(draft(tester), 'Existing question\nFind inventory nearby.');
      await tap(tester, 'Use this text');
      expect(
        (result as KorlixVoiceDraft).text,
        'Existing question\nFind inventory nearby.',
      );
      expect((result as KorlixVoiceDraft).openLiveConvo, isFalse);
      expect(engine.disposed, isTrue);
    },
  );

  testWidgets(
    'replace and undo restore the original draft; late results are ignored',
    (tester) async {
      final engine = FakeDictation();
      await open(
        tester,
        KorlixVoiceComposer(initialText: 'Original', engine: engine),
        (_) {},
      );
      await tap(tester, 'Replace draft');
      await tap(tester, 'Start dictation');
      engine.words('Replacement');
      await tester.pump();
      expect(draft(tester), 'Replacement');
      final oldWords = engine.words;
      await tap(tester, 'Stop dictation');
      await tap(tester, 'Undo dictation');
      expect(draft(tester), 'Original');
      await tap(tester, 'Start dictation');
      oldWords('Stale words');
      engine.words('Current recording');
      await tester.pump();
      expect(draft(tester), 'Current recording');
      await tap(tester, 'Stop dictation');
    },
  );

  testWidgets('unavailable dictation keeps typing and Live Convo available', (
    tester,
  ) async {
    final engine = FakeDictation()..fail = true;
    Object? result;
    await open(tester, KorlixVoiceComposer(engine: engine), (v) => result = v);
    await tap(tester, 'Start dictation');
    expect(find.textContaining('Dictation is unavailable'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Typed fallback');
    await tester.pump();
    await tap(tester, 'Talk with K-Nova instead');
    expect((result as KorlixVoiceDraft).text, 'Typed fallback');
    expect((result as KorlixVoiceDraft).openLiveConvo, isTrue);
  });

  testWidgets('backgrounding stops dictation and preserves the draft', (
    tester,
  ) async {
    final engine = FakeDictation();
    await open(tester, KorlixVoiceComposer(engine: engine), (_) {});
    await tap(tester, 'Start dictation');
    engine.words('Keep this');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    engine.words('Late background words');
    await tester.pump();
    expect(engine.cancels, greaterThan(0));
    expect(draft(tester), 'Keep this');
    expect(find.text('Start dictation'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'account change cancels pending voice initialization and discards draft',
    (tester) async {
      final revision = ValueNotifier(0);
      final engine = FakeDictation()
        ..pending = Completer<List<KorlixVoiceLocale>>();
      var valid = true;
      Object? result;
      await open(
        tester,
        KorlixVoiceComposer(
          initialText: 'Private',
          engine: engine,
          sessionChanges: revision,
          isSessionCurrent: () => valid,
        ),
        (v) => result = v,
      );
      await tester.tap(find.text('Start dictation'));
      await tester.pump();
      valid = false;
      revision.value++;
      await tester.pumpAndSettle();
      engine.pending!.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(KorlixVoiceComposer), findsNothing);
      expect(engine.starts, 0);
      expect(engine.disposed, isTrue);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
      revision.dispose();
    },
  );
}

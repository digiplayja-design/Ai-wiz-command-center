import 'dart:async';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:ai_wiz_command_center/text_workspace/box_store.dart';
import 'package:ai_wiz_command_center/text_workspace/box_workspace.dart';

class FakeSpeech implements SpeechToText {
  @override
  SpeechErrorListener? errorListener;
  @override
  SpeechStatusListener? statusListener;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  SpeechResultListener? result;
  int cancellations = 0;
  bool listening = false, declineListen = false;
  @override
  bool get isListening => listening;
  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = const Duration(seconds: 2),
    List<SpeechConfigOption>? options,
  }) async => true;
  @override
  Future<List<LocaleName>> locales() async => [LocaleName('en_US', 'English')];
  @override
  Future cancel() async {
    cancellations++;
    listening = false;
  }

  @override
  Future listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    expect(kKorlixSounds.quiet, isTrue);
    result = onResult;
    listening = !declineListen;
  }

  void words(String value, {bool finalResult = false}) => result?.call(
    SpeechRecognitionResult([
      SpeechRecognitionWords(value, null, 1),
    ], finalResult ? ResultType.finalResult.value : ResultType.partial.value),
  );
}

final _captureKey = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['BOX_WORKSPACE_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (_captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('accounts and tool types have independent persistence', () async {
    final prefs = await SharedPreferences.getInstance();
    final a = BoxStore(prefs, 'account-a', false),
        b = BoxStore(prefs, 'account-b', false),
        voice = BoxStore(prefs, 'account-a', true);
    await a.save([SavedBox(title: 'Private', text: 'A only')]);
    expect(a.load().single.text, 'A only');
    expect(b.load(), isEmpty);
    expect(voice.load(), isEmpty);
  });
  test(
    'legacy import is explicit, non-destructive and once per account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BoxStore(prefs, 'a', false);
      await prefs.setStringList(store.legacyKey, ['old', '', 'another']);
      expect(store.load(), isEmpty);
      final boxes = <SavedBox>[];
      await store.importLegacy(boxes);
      await store.importLegacy(boxes);
      expect(boxes.length, 2);
      expect(prefs.getStringList(store.legacyKey), ['old', '', 'another']);
    },
  );
  test(
    'prepared imports are present in subsequent snapshots and retries do not duplicate',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BoxStore(prefs, 'a', false);
      await prefs.setStringList(store.legacyKey, ['legacy']);
      final boxes = [SavedBox(text: 'existing')];
      store.prepareLegacy(boxes);
      final snapshot = boxes.map((b) => SavedBox.fromJson(b.toJson())).toList();
      expect(snapshot.map((b) => b.text), ['existing', 'legacy']);
      store.prepareLegacy(boxes);
      expect(boxes.length, 2);
      await store.importLegacy(boxes);
      expect(store.load().length, 2);
    },
  );
  test('corrupt storage is surfaced instead of resetting user data', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = BoxStore(prefs, 'a', false);
    await prefs.setString(store.key, 'broken');
    expect(store.load, throwsFormatException);
    expect(prefs.getString(store.key), 'broken');
  });
  test('templates preserve original and replace repeated fields literally', () {
    const text = 'Hi {{ client }}, {{client}} owes {{amount}}';
    expect(templateFields(text), ['client', 'amount']);
    expect(
      renderTemplate(text, {'client': 'A\$1', 'amount': '20'}),
      'Hi A\$1, A\$1 owes 20',
    );
    expect(text, contains('{{client}}'));
  });
  test('versions retain originals with bounded history', () {
    final b = SavedBox(text: 'Original');
    b.replace('Draft');
    expect(b.history, ['Original']);
    for (var i = 0; i < 20; i++) {
      b.replace('$i');
    }
    expect(b.history.length, 10);
  });
  Future<(BoxStore, ValueNotifier<int>)> open(
    WidgetTester tester, {
    bool voice = false,
    FakeSpeech? speech,
    bool Function()? valid,
    Future<String> Function(String, String)? rewrite,
    List<SavedBox>? initialBoxes,
    Size size = const Size(1100, 1000),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = BoxStore(prefs, 'a', voice);
    if (initialBoxes == null || initialBoxes.isNotEmpty) {
      await store.save(
        initialBoxes ?? [SavedBox(title: 'First note', text: 'Original')],
      );
    }
    final revision = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _captureKey, child: child!),
        ),
        home: BoxWorkspace(
          store: store,
          sessionChanges: revision,
          sessionValid: valid ?? () => true,
          rewrite: rewrite ?? (a, b) async => 'Improved',
          speech: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (store, revision);
  }

  for (final voice in [false, true]) {
    final name = voice ? 'VoiceScribe' : 'Copy Box';
    testWidgets('$name opens an editable first box without another tap', (
      tester,
    ) async {
      final (store, _) = await open(
        tester,
        voice: voice,
        speech: FakeSpeech(),
        initialBoxes: [],
      );
      expect(find.widgetWithText(AppBar, name), findsOneWidget);
      final editor = find.widgetWithText(
        TextField,
        voice ? 'Transcript / notes' : 'Saved text',
      );
      expect(editor, findsNWidgets(voice ? 1 : 12));
      expect(store.load(), isEmpty);
      await tester.enterText(editor.first, 'My first saved box');
      await tester.pumpAndSettle();
      expect(store.load().length, voice ? 1 : 12);
      expect(store.load().first.text, 'My first saved box');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name can create, duplicate and open a template', (
      tester,
    ) async {
      final (store, _) = await open(tester, voice: voice, speech: FakeSpeech());
      final originalId = store.load().single.id;
      await tester.tap(
        voice
            ? find.text('New entry')
            : find.byKey(const ValueKey('copy-box-add-top')),
      );
      await tester.pumpAndSettle();
      expect(find.text(voice ? '2 entries' : '2 boxes'), findsOneWidget);
      final newId = store.load().last.id;
      final editor = voice
          ? find.widgetWithText(TextField, 'Transcript / notes')
          : find.byKey(ValueKey('copy-box-text-$newId'));
      await tester.ensureVisible(editor);
      await tester.enterText(editor, 'New content');
      await tester.pumpAndSettle();
      final duplicate = voice
          ? find.text('Duplicate')
          : find.descendant(
              of: find.byKey(ValueKey('copy-box-card-$newId')),
              matching: find.text('Duplicate'),
            );
      await tester.ensureVisible(duplicate);
      await tester.tap(duplicate);
      await tester.pumpAndSettle();
      expect(store.load().where((b) => b.text == 'New content').length, 2);
      await tester.ensureVisible(find.text('Templates'));
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(voice ? 'Meeting notes' : 'Client follow-up'));
      await tester.pumpAndSettle();
      final saved = store.load();
      expect(saved.length, 4);
      expect(saved.map((b) => b.id).toSet().length, 4);
      expect(saved.singleWhere((b) => b.id == originalId).text, 'Original');
      expect(
        (voice ? saved.first : saved.last).text,
        contains(voice ? 'Discussion:' : '{{client}}'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('corrupt saved boxes do not become an editable empty starter', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = BoxStore(prefs, 'a', false);
    await prefs.setString(store.key, 'broken');
    await tester.pumpWidget(
      MaterialApp(
        home: BoxWorkspace(
          store: store,
          sessionChanges: ValueNotifier(0),
          sessionValid: () => true,
          rewrite: (a, b) async => b,
          speech: FakeSpeech(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved data could not be read'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('copy-box-add-top')), findsNothing);
    expect(prefs.getString(store.key), 'broken');
  });

  testWidgets('edits save and search filters the stacked boxes', (
    tester,
  ) async {
    final (store, _) = await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Original'),
      'Saved edit',
    );
    await tester.pumpAndSettle();
    expect(store.load().single.text, 'Saved edit');
    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('0 boxes'), findsOneWidget);
  });
  testWidgets(
    'AI apply and version restore affect only the second Copy Box card',
    (tester) async {
      final (store, _) = await open(
        tester,
        initialBoxes: [
          SavedBox(id: 'first', title: 'First', text: 'Keep this'),
          SavedBox(id: 'second', title: 'Second', text: 'Original'),
        ],
      );
      final card = find.byKey(const ValueKey('copy-box-card-second'));
      final improve = find.descendant(
        of: card,
        matching: find.text('Improve with KORLIX ▾'),
      );
      await tester.ensureVisible(improve);
      await tester.tap(improve);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polish'));
      await tester.pumpAndSettle();
      expect(store.load().map((box) => box.text), ['Keep this', 'Original']);
      expect(find.text('Review • Polish'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(store.load().map((box) => box.text), ['Keep this', 'Improved']);
      expect(store.load().last.history, ['Original']);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('copy-box-text-second')),
            )
            .controller!
            .text,
        'Improved',
      );
      final versions = find.descendant(
        of: card,
        matching: find.text('Versions'),
      );
      await tester.ensureVisible(versions);
      await tester.tap(versions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Version 1\nOriginal'));
      await tester.pumpAndSettle();
      expect(store.load().map((box) => box.text), ['Keep this', 'Original']);
      expect(store.load().last.history, ['Improved', 'Original']);
    },
  );
  testWidgets('signout clears editor and ignores late AI result', (
    tester,
  ) async {
    bool valid = true;
    final completer = Completer<String>();
    final (store, revision) = await open(
      tester,
      valid: () => valid,
      rewrite: (a, b) => completer.future,
    );
    await tester.ensureVisible(find.text('Improve with KORLIX ▾'));
    await tester.tap(find.text('Improve with KORLIX ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polish'));
    await tester.pump();
    valid = false;
    revision.value++;
    await tester.pump();
    completer.complete('Late secret');
    await tester.pumpAndSettle();
    expect(
      find.text('Sign in again and reopen this workspace.'),
      findsOneWidget,
    );
    expect(find.text('Late secret'), findsNothing);
    expect(store.load().single.text, 'Original');
  });
  testWidgets(
    'silent dictation rejection releases quiet without closing VoiceScribe',
    (tester) async {
      final speech = FakeSpeech()..declineListen = true;
      await open(tester, voice: true, speech: speech);
      await tester.tap(find.text('Start dictation'));
      await tester.pumpAndSettle();
      expect(kKorlixSounds.quiet, isFalse);
      speech.listening = true;
      speech.statusListener?.call('listening');
      expect(kKorlixSounds.quiet, isTrue);
      await tester.tap(find.text('Stop & keep transcript'));
      await tester.pumpAndSettle();
      expect(kKorlixSounds.quiet, isFalse);
      speech.statusListener?.call('listening');
      expect(kKorlixSounds.quiet, isFalse);
    },
  );

  testWidgets('dictation appends once and rejects late results after stop', (
    tester,
  ) async {
    final speech = FakeSpeech();
    final (store, _) = await open(tester, voice: true, speech: speech);
    await tester.tap(find.text('Start dictation'));
    await tester.pumpAndSettle();
    speech.words('hello');
    await tester.pump();
    await tester.tap(find.text('Stop & keep transcript'));
    await tester.pumpAndSettle();
    speech.words('late', finalResult: true);
    await tester.pumpAndSettle();
    expect(store.load().single.text, 'Original\nhello');
    expect(speech.cancellations, greaterThan(0));
    await tester.tap(find.text('Start dictation'));
    await tester.pumpAndSettle();
    speech.words('again', finalResult: true);
    await tester.pumpAndSettle();
    expect(store.load().single.text, 'Original\nhello\nagain');
  });
  testWidgets('final words after notListening are preserved', (tester) async {
    final speech = FakeSpeech();
    final (store, _) = await open(tester, voice: true, speech: speech);
    await tester.tap(find.text('Start dictation'));
    await tester.pumpAndSettle();
    speech.words('partial');
    speech.statusListener?.call('notListening');
    speech.words('complete sentence', finalResult: true);
    await tester.pumpAndSettle();
    expect(store.load().single.text, 'Original\ncomplete sentence');
  });
  testWidgets('narrow phone layout has no overflow', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Copy Box appends editable cards, copies exact text and restores their order',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final (store, _) = await open(tester);
      final firstId = store.load().single.id;
      for (final key in ['copy-box-add-top', 'copy-box-add-bottom']) {
        final add = find.byKey(ValueKey(key));
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        final newest = find.byKey(
          ValueKey('copy-box-title-${store.load().last.id}'),
        );
        expect(newest.hitTestable(), findsOneWidget);
      }
      final ids = store.load().map((box) => box.id).toList();
      expect(ids.first, firstId);
      expect(ids.toSet().length, 3);
      expect(find.text('3 boxes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-entries-scroll')),
        findsNothing,
      );
      const values = [
        '  First\noriginal spacing  ',
        'Second 🦋\nline',
        'Third',
      ];
      for (var i = 0; i < ids.length; i++) {
        final title = find.byKey(ValueKey('copy-box-title-${ids[i]}'));
        final folder = find.byKey(ValueKey('copy-box-folder-${ids[i]}'));
        final input = find.byKey(ValueKey('copy-box-text-${ids[i]}'));
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Reusable ${i + 1}');
        await tester.ensureVisible(folder);
        await tester.enterText(folder, 'Folder ${i + 1}');
        await tester.ensureVisible(input);
        await tester.enterText(input, values[i]);
        await tester.pumpAndSettle();
        final copy = find.descendant(
          of: find.byKey(ValueKey('copy-box-card-${ids[i]}')),
          matching: find.widgetWithText(FilledButton, 'Copy Box ${i + 1}'),
        );
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(clipboard, values[i]);
      }
      final save = find.text('Save All');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy All Boxes'));
      await tester.pumpAndSettle();
      expect(clipboard, values.join('\n\n'));
      expect(store.load().map((box) => box.id), ids);
      expect(store.load().map((box) => box.text), values);
      expect(store.load().map((box) => box.title), [
        'Reusable 1',
        'Reusable 2',
        'Reusable 3',
      ]);
      expect(store.load().map((box) => box.folder), [
        'Folder 1',
        'Folder 2',
        'Folder 3',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, initialBoxes: []);
      expect(store.load().map((box) => box.id), ids);
      final positions = <double>[];
      for (var i = 0; i < ids.length; i++) {
        final input = find.byKey(ValueKey('copy-box-text-${ids[i]}'));
        expect(tester.widget<TextField>(input).controller!.text, values[i]);
        positions.add(tester.getTopLeft(input).dy);
      }
      expect(positions[0], lessThan(positions[1]));
      expect(positions[1], lessThan(positions[2]));
      await _capture(tester, 'copybox-tablet-light-stack');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Copy Box deleting and undoing a middle card preserves order', (
    tester,
  ) async {
    final boxes = List.generate(
      3,
      (i) => SavedBox(id: 'box-$i', title: 'Title $i', text: 'Text $i'),
    );
    final (store, _) = await open(tester, initialBoxes: boxes);
    final delete = find.descendant(
      of: find.byKey(const ValueKey('copy-box-card-box-1')),
      matching: find.text('Delete'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.load().map((box) => box.id), ['box-0', 'box-2']);
    expect(find.byKey(const ValueKey('copy-box-card-box-1')), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.load().map((box) => box.id), ['box-0', 'box-1', 'box-2']);
    final positions = List.generate(
      3,
      (i) => tester.getTopLeft(find.byKey(ValueKey('copy-box-text-box-$i'))).dy,
    );
    expect(positions[0], lessThan(positions[1]));
    expect(positions[1], lessThan(positions[2]));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Copy Box filters and clears search without losing edits or order',
    (tester) async {
      final (store, _) = await open(
        tester,
        initialBoxes: [
          SavedBox(id: 'alpha', title: 'Alpha', text: 'Original alpha'),
          SavedBox(
            id: 'beta',
            title: 'Beta',
            text: 'Original beta',
            favorite: true,
          ),
          SavedBox(id: 'gamma', title: 'Gamma', text: 'Original gamma'),
        ],
      );
      final input = find.byKey(const ValueKey('copy-box-text-beta'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Edited beta remains saved');
      final search = find.widgetWithText(
        TextField,
        'Search titles, folders and text',
      );
      await tester.ensureVisible(search);
      await tester.enterText(search, 'beta');
      await tester.pumpAndSettle();
      expect(find.text('1 boxes'), findsOneWidget);
      expect(find.byKey(const ValueKey('copy-box-text-alpha')), findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Edited beta remains saved',
      );
      await tester.enterText(search, 'no result');
      await tester.pumpAndSettle();
      expect(find.text('0 boxes'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('copy-box-text-alpha')), findsNothing);
      expect(find.byKey(const ValueKey('copy-box-text-beta')), findsOneWidget);
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('3 boxes'), findsOneWidget);
      expect(store.load().map((box) => box.id), ['alpha', 'beta', 'gamma']);
      expect(store.load()[1].text, 'Edited beta remains saved');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('copy-box-text-alpha'))).dy,
        lessThan(tester.getTopLeft(input).dy),
      );
      expect(
        tester.getTopLeft(input).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('copy-box-text-gamma')))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final voice in [false, true]) {
    final name = voice ? 'VoiceScribe' : 'Copy Box';
    testWidgets('$name outer mouse scrollbar moves the entire workspace', (
      tester,
    ) async {
      await open(
        tester,
        voice: voice,
        speech: FakeSpeech(),
        size: const Size(1024, 700),
      );
      final barFinder = find.byKey(const ValueKey('workspace-page-scrollbar'));
      final bar = tester.widget<Scrollbar>(barFinder);
      final page = bar.controller!;
      expect(bar.thumbVisibility, isTrue);
      expect(bar.trackVisibility, isTrue);
      expect(bar.interactive, isTrue);
      expect(page.position.maxScrollExtent, greaterThan(100));
      final header = find.text(
        voice ? 'Speak it. Shape it. Save it.' : 'Your words, ready to reuse.',
      );
      final before = tester.getTopLeft(header).dy;
      final bounds = tester.getRect(barFinder);
      expect(bounds.right, 1024);
      final gesture = await tester.startGesture(
        Offset(bounds.right - 8, bounds.top + 25),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 260));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(page.offset, greaterThan(50));
      expect(tester.getTopLeft(header).dy, lessThan(before - 50));
      if (voice) {
        expect(
          tester
              .widget<Scrollbar>(
                find.byKey(const ValueKey('workspace-entries-scrollbar')),
              )
              .controller!
              .offset,
          0,
        );
      } else {
        expect(
          find.byKey(const ValueKey('workspace-entries-scrollbar')),
          findsNothing,
        );
      }
      await tester.ensureVisible(find.text('Duplicate'));
      expect(find.text('Duplicate').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        '$name ${brightness.name} panels stay distinct on a 320px phone with large text',
        (tester) async {
          final (store, _) = await open(
            tester,
            voice: voice,
            speech: FakeSpeech(),
            size: const Size(320, 740),
            textScale: 2,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          final overview =
              tester
                      .widget<Container>(
                        find.byKey(const ValueKey('workspace-overview-panel')),
                      )
                      .decoration!
                  as BoxDecoration;
          final editor =
              tester
                      .widget<Container>(
                        find.byKey(
                          voice
                              ? const ValueKey('workspace-editor-panel')
                              : ValueKey(
                                  'copy-box-card-panel-${store.load().first.id}',
                                ),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;
          final input = find.widgetWithText(
            TextField,
            voice ? 'Transcript / notes' : 'Saved text',
          );
          final inputTheme = Theme.of(
            tester.element(input),
          ).inputDecorationTheme;
          expect(overview.color, isNot(editor.color));
          expect(inputTheme.fillColor, isNot(editor.color));
          await _capture(
            tester,
            '${voice ? 'voicescribe' : 'copybox'}-${brightness.name}-320-top',
          );
          await tester.ensureVisible(input);
          await tester.pumpAndSettle();
          await _capture(
            tester,
            '${voice ? 'voicescribe' : 'copybox'}-${brightness.name}-320-input',
          );
          await tester.enterText(input, 'Large text stays editable.');
          await tester.pumpAndSettle();
          final copy = voice
              ? find.text('Copy text')
              : find.widgetWithText(FilledButton, 'Copy Box 1');
          await tester.ensureVisible(copy);
          expect(copy.hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.text('Duplicate'));
          expect(find.text('Duplicate').hitTestable(), findsOneWidget);
          final add = voice
              ? find.text('New entry')
              : find.byKey(const ValueKey('copy-box-add-bottom'));
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(find.text(voice ? '2 entries' : '2 boxes'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    if (voice)
      testWidgets(
        '$name entries scroll independently and survive resize and empty filters',
        (tester) async {
          await open(
            tester,
            voice: voice,
            speech: FakeSpeech(),
            initialBoxes: List.generate(
              25,
              (i) => SavedBox(title: 'Entry $i', text: 'Reusable text $i'),
            ),
            size: const Size(1180, 860),
          );
          final listFinder = find.byKey(
            const ValueKey('workspace-entries-scroll'),
          );
          final list = tester.widget<ListView>(listFinder).controller!;
          final page = tester
              .widget<Scrollbar>(
                find.byKey(const ValueKey('workspace-page-scrollbar')),
              )
              .controller!;
          await tester.drag(listFinder, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(list.offset, greaterThan(100));
          expect(page.offset, 0);
          await _capture(
            tester,
            '${voice ? 'voicescribe' : 'copybox'}-tablet-light',
          );
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'no result');
          await tester.pumpAndSettle();
          expect(find.text('No entries match your search.'), findsOneWidget);
          await tester.enterText(find.byType(TextField).first, '');
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-entries-scrollbar')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
  }
}

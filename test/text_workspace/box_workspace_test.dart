import 'dart:async';
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
    result = onResult;
  }

  void words(String value, {bool finalResult = false}) => result?.call(
    SpeechRecognitionResult([
      SpeechRecognitionWords(value, null, 1),
    ], finalResult ? ResultType.finalResult.value : ResultType.partial.value),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = BoxStore(prefs, 'a', voice);
    await store.save([SavedBox(title: 'First note', text: 'Original')]);
    final revision = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
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

  testWidgets('edits save and search filters the entry list', (tester) async {
    final (store, _) = await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Original'),
      'Saved edit',
    );
    await tester.pumpAndSettle();
    expect(store.load().single.text, 'Saved edit');
    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('0 entries'), findsOneWidget);
  });
  testWidgets(
    'AI draft does not overwrite original before review and creates a version',
    (tester) async {
      final (store, _) = await open(tester);
      await tester.tap(find.text('Improve with KORLIX ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polish'));
      await tester.pumpAndSettle();
      expect(store.load().single.text, 'Original');
      expect(find.text('Review • Polish'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(store.load().single.text, 'Improved');
      expect(store.load().single.history, ['Original']);
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
}

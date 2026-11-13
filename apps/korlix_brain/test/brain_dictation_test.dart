import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_dictation.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  late _Speech speech;
  late List<BrainDictation> owners;
  late List<Map<String, dynamic>> events;
  var foreground = true;

  BrainDictation make({Future<void> Function()? prepare,
      List<Map<String, dynamic>>? output}) {
    final owner = BrainDictation(
      speech: speech,
      canListen: () => foreground,
      prepare: prepare ?? () async {},
      emit: (output ?? events).add,
    );
    owners.add(owner);
    return owner;
  }

  setUp(() {
    speech = _Speech();
    owners = [];
    events = [];
    foreground = true;
  });
  tearDown(() async {
    for (final owner in owners.reversed) {
      await owner.dispose().catchError((Object _) {});
    }
  });

  test('background during permission initialization never starts listening', () async {
    final permission = Completer<bool>();
    speech.initializeResult = permission.future;
    final owner = make();
    final starting = owner.toggle('memory');
    await Future<void>.delayed(Duration.zero);
    expect(speech.calls, ['initialize']);
    foreground = false;
    final stopping = owner.stop(cancel: true);
    permission.complete(true);
    await Future.wait([starting, stopping]);
    expect(speech.calls, isNot(contains('listen')));
    expect(owner.active, isFalse);
    foreground = true;
    await Future<void>.delayed(Duration.zero);
    expect(speech.calls, isNot(contains('listen')));
    expect(events, isEmpty);
  });

  test('background while native listen is pending releases it before a new owner', () async {
    final listening = Completer<void>();
    speech.listenResult = listening.future;
    final first = make();
    final starting = first.toggle('memory');
    await Future<void>.delayed(Duration.zero);
    expect(speech.calls.last, 'listen');
    foreground = false;
    final stopping = first.stop(cancel: true);
    final disposing = first.dispose();
    listening.complete();
    await Future.wait([starting, stopping, disposing]);
    expect(first.active, isFalse);
    expect(events.where((event) => event['active'] == true), isEmpty);
    final firstListen = speech.calls.indexOf('listen');
    expect(speech.calls.skip(firstListen + 1), contains('cancel'));
    foreground = true;
    speech.listenResult = null;
    final next = make();
    await next.toggle('training');
    expect(next.active, isTrue);
    expect(speech.calls.last, 'listen');
  });

  test('a new workspace replaces callbacks retained by the speech singleton', () async {
    final first = make();
    await first.toggle('memory');
    final oldStatus = speech.statusListener!;
    final newEvents = <Map<String, dynamic>>[];
    final next = make(output: newEvents);
    await next.toggle('training');
    final cancelsBeforeOldDispose = speech.calls.where((call) => call == 'cancel').length;
    await first.dispose();
    expect(speech.calls.where((call) => call == 'cancel').length, cancelsBeforeOldDispose);
    events.clear();
    newEvents.clear();
    oldStatus('done');
    expect(events, isEmpty);
    expect(next.active, isTrue);
    speech.statusListener!('notListening');
    expect(next.active, isFalse);
    expect(newEvents.single['active'], isFalse);
  });

  test('disposing during preparation cancels the pending capture request', () async {
    final preparation = Completer<void>();
    final owner = make(prepare: () => preparation.future);
    final starting = owner.toggle('memory');
    await owner.dispose();
    preparation.complete();
    await starting;
    expect(speech.calls, isEmpty);
    expect(events, isEmpty);
  });

  test('a failed release is retried before another workspace captures', () async {
    final first = make();
    await first.toggle('memory');
    speech.failNextCancel = true;
    await expectLater(first.dispose(), throwsA(isA<StateError>()));
    final next = make();
    await next.toggle('training');
    expect(speech.calls.where((call) => call == 'cancel').length, 2);
    expect(speech.calls.last, 'listen');
    expect(next.active, isTrue);
  });
}

// Reproduce the plugin's important ownership behavior: successful initialize
// keeps its first listeners. All unrelated API surface uses noSuchMethod.
class _Speech implements SpeechToText {
  final calls = <String>[];
  bool initialized = false, failNextCancel = false;
  Future<bool>? initializeResult;
  Future<void>? listenResult;
  @override
  SpeechErrorListener? errorListener;
  @override
  SpeechStatusListener? statusListener;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    calls.add('initialize');
    if (initialized) return true;
    errorListener = onError;
    statusListener = onStatus;
    initialized = await (initializeResult ?? Future.value(true));
    return initialized;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (failNextCancel) {
      failNextCancel = false;
      throw StateError('Native cancellation failed');
    }
  }

  @override
  Future<void> stop() async { calls.add('stop'); }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listen) {
      calls.add('listen');
      return listenResult ?? Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

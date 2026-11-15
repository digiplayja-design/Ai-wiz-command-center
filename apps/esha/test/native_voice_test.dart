import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/voice.dart';
import 'package:esha_by_korlix/services/voice_audio.dart';
import 'package:esha_by_korlix/ui/brand.dart';
import 'package:esha_by_korlix/ui/voice.dart';
import 'package:esha_by_korlix/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

const requestA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

VoiceUsage voiceUsage({
  int used = 0,
  int reserved = 0,
  int limit = 300,
  int deepLimit = 2,
}) => VoiceUsage(
  limitSeconds: limit,
  usedSeconds: used,
  reservedSeconds: reserved,
  remainingSeconds: limit - used - reserved,
  deepLimit: deepLimit,
  deepUsed: 0,
  deepReserved: 0,
  deepRemaining: deepLimit,
);

Json usageJson({int limit = 300, int deepLimit = 2}) => {
  'voice': {
    'limitSeconds': limit,
    'usedSeconds': 0,
    'reservedSeconds': 0,
    'remainingSeconds': limit,
  },
  'deep': {
    'limit': deepLimit,
    'used': 0,
    'reserved': 0,
    'remaining': deepLimit,
  },
};

Json readyJson() => {
  'voiceEnabled': true,
  'model': eshaVoiceModel,
  'usage': usageJson(),
  'membership': {
    'active': true,
    'verificationFresh': true,
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(days: 3))
        .toIso8601String(),
  },
};

class VoiceTestPurchases extends EshaPurchases {
  VoiceTestPurchases(super.api) : super(store: NoNativeStore());
  bool access = true;
  @override
  bool get hasAppAccess => access && api.session != null;
  void expire() {
    access = false;
    notifyListeners();
  }
}

class VoiceTestStore extends MemoryStore {
  Completer<void>? beforeIntentWrite;
  bool failIntentWrite = false;
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('esha.voice.pending.')) {
      if (failIntentWrite) throw StateError('secure storage unavailable');
      if (beforeIntentWrite != null) await beforeIntentWrite!.future;
    }
    await super.write(key, value);
  }
}

class FakeVoiceGateway implements VoiceGateway {
  bool enabled = true, stopFinalized = true;
  String? unavailabilityReason;
  Object? createFailure, statusFailure;
  Completer<VoiceSessionStatus>? pendingCreate;
  VoiceUsage allowance = voiceUsage();
  VoiceUsage? historicalAllowance;
  String? lastId;
  String state = 'active';
  bool finalized = false;
  int creates = 0, checks = 0;
  final List<String> stops = [];
  final List<bool> deepChoices = [];
  final List<String> requestIds = [];
  final List<String> checkedIds = [];
  List<VoiceDeepResult> results = [];
  @override
  Future<VoiceAvailability> availability() async => VoiceAvailability(
    enabled: enabled,
    usage: allowance,
    unavailabilityReason: unavailabilityReason,
  );
  VoiceSessionStatus result(String id, {bool created = false}) =>
      VoiceSessionStatus(
        requestId: id,
        state: state,
        finalizationConfirmed: finalized,
        usage: created ? allowance : historicalAllowance ?? allowance,
        deepResults: results,
        sessionId: 'live_test',
        sdpAnswer: created ? 'v=0\r\nanswer' : null,
      );
  @override
  Future<VoiceSessionStatus> create({
    required String requestId,
    required String sdpOffer,
    required bool deepThinkingConsent,
  }) async {
    creates++;
    requestIds.add(requestId);
    deepChoices.add(deepThinkingConsent);
    lastId = requestId;
    if (createFailure != null) throw createFailure!;
    if (pendingCreate != null) return pendingCreate!.future;
    state = 'active';
    finalized = false;
    return result(requestId, created: true);
  }

  @override
  Future<VoiceSessionStatus> status(String requestId) async {
    checks++;
    checkedIds.add(requestId);
    if (statusFailure != null) throw statusFailure!;
    return result(requestId);
  }

  @override
  Future<VoiceSessionStatus> stop(String requestId, String reason) async {
    stops.add(reason);
    state = stopFinalized ? 'closed' : 'closing';
    finalized = stopFinalized;
    return result(requestId);
  }
}

class FakeVoiceAudio implements VoiceAudioTransport {
  final channel = StreamController<VoiceAudioEvent>.broadcast();
  bool closed = false, autoStarted = true;
  int enabled = 0, answers = 0;
  Object? offerFailure;
  Completer<String>? pendingOffer;
  String startedId = 'live_test';
  @override
  bool get requestingMicrophone => pendingOffer != null && !closed;
  @override
  Stream<VoiceAudioEvent> get events => channel.stream;
  @override
  Future<String> createOffer() async {
    if (offerFailure != null) throw offerFailure!;
    return pendingOffer?.future ?? 'v=0\r\noffer';
  }

  @override
  Future<void> acceptAnswer(String sdp) async {
    answers++;
    if (autoStarted) {
      channel.add(
        VoiceAudioEvent(VoiceAudioEventType.started, sessionId: startedId),
      );
    }
  }

  void event(VoiceAudioEventType type, {String? id}) =>
      channel.add(VoiceAudioEvent(type, sessionId: id));
  @override
  Future<void> enableMicrophone() async {
    if (closed) throw StateError('closed');
    enabled++;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await channel.close();
  }
}

class VoiceFixture {
  String account = accountA;
  final secure = VoiceTestStore(), local = MemoryStore();
  final gateway = FakeVoiceGateway();
  final audios = <FakeVoiceAudio>[];
  FakeVoiceAudio Function()? makeAudio;
  late KorlixApi api;
  late VoiceTestPurchases purchases;
  late EshaVoiceController voice;
  Future<void> initialize() async {
    api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: secure,
      localStorage: local,
      platform: 'ios',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return http.Response(jsonEncode(authPayload(account)), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    await api.signIn('member@example.test', 'not-a-real-password');
    purchases = VoiceTestPurchases(api);
    voice = EshaVoiceController(
      api: api,
      purchases: purchases,
      gateway: gateway,
      transportFactory: () {
        final value = makeAudio?.call() ?? FakeVoiceAudio();
        audios.add(value);
        return value;
      },
    );
    await voice.refresh();
  }

  Future<void> begin({bool deep = false}) async {
    voice.setAudioConsent(true);
    voice.setDeepThinkingConsent(deep);
    await voice.start();
    await flush();
  }

  Future<void> close() async {
    voice.dispose();
    purchases.dispose();
    await flush();
    api.dispose();
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<VoiceFixture> fixture() async {
    final f = VoiceFixture();
    await f.initialize();
    addTearDown(f.close);
    return f;
  }

  test('absent consent, unavailable voice and lost membership never open microphone or create a session', () async {
    final f = await fixture();
    await f.voice.start();
    expect(f.audios, isEmpty);
    expect(f.gateway.creates, 0);
    f.voice.setAudioConsent(true);
    f.gateway.enabled = false;
    await f.voice.start();
    expect(f.audios, isEmpty);
    expect(f.gateway.creates, 0);
    f.gateway.enabled = true;
    f.purchases.access = false;
    await f.voice.start();
    expect(f.audios, isEmpty);
    expect(f.gateway.creates, 0);
  });

  test('microphone permission failure and secure intent failure occur before paid creation', () async {
    final f = await fixture();
    f.makeAudio = () => FakeVoiceAudio()
      ..offerFailure = const EshaException(
        'VOICE_MICROPHONE',
        'Permission denied',
      );
    await f.begin();
    expect(f.gateway.creates, 0);
    expect(f.audios.single.closed, isTrue);
    f.makeAudio = FakeVoiceAudio.new;
    f.secure.failIntentWrite = true;
    await f.begin();
    expect(f.gateway.creates, 0);
    expect(f.audios.last.closed, isTrue);
  });

  test('audio waits for both an authorized SDP and session.started; deep consent defaults off', () async {
    final f = await fixture();
    f.makeAudio = () => FakeVoiceAudio()..autoStarted = false;
    await f.begin();
    expect(f.voice.phase, EshaVoicePhase.connecting);
    expect(f.audios.single.answers, 1);
    expect(f.audios.single.enabled, 0);
    expect(f.gateway.deepChoices, [false]);
    expect(f.secure.values['esha.voice.pending.$accountA'], f.gateway.lastId);
    f.audios.single.event(VoiceAudioEventType.started, id: 'live_test');
    await flush();
    expect(f.voice.active, isTrue);
    expect(f.audios.single.enabled, 1);
  });

  test('a mismatched provider session closes audio without transmitting microphone input', () async {
    final f = await fixture();
    f.makeAudio = () => FakeVoiceAudio()..startedId = 'live_other';
    await f.begin();
    expect(f.audios.single.enabled, 0);
    expect(f.audios.single.closed, isTrue);
    expect(f.gateway.stops, isNotEmpty);
    expect(f.gateway.creates, 1);
  });

  test('pause ends audio, clears both consents and resume requires a new choice and UUID', () async {
    final f = await fixture();
    await f.begin(deep: true);
    final first = f.gateway.lastId;
    expect(f.voice.active, isTrue);
    expect(f.gateway.deepChoices, [true]);
    await f.voice.pause();
    expect(f.audios.single.closed, isTrue);
    expect(f.voice.phase, EshaVoicePhase.paused);
    expect(f.voice.audioConsent, isFalse);
    expect(f.voice.deepThinkingConsent, isFalse);
    await f.voice.resume();
    expect(f.gateway.creates, 1);
    f.voice.setAudioConsent(true);
    await f.voice.resume();
    await flush();
    expect(f.gateway.creates, 2);
    expect(f.gateway.lastId, isNot(first));
    expect(f.gateway.deepChoices, [true, false]);
  });

  test('background stops the current call and returning never reconnects automatically', () async {
    final f = await fixture();
    await f.begin();
    f.voice.setForeground(false);
    await flush();
    expect(f.audios.single.closed, isTrue);
    expect(f.gateway.stops, contains('background'));
    f.voice.setForeground(true);
    await flush();
    expect(f.gateway.creates, 1);
    expect(f.voice.audioConsent, isFalse);
  });

  test('disconnect, consent withdrawal and membership loss close audio and require fresh consent', () async {
    final f = await fixture();
    await f.begin();
    f.audios.last.event(VoiceAudioEventType.disconnected);
    await flush();
    expect(f.audios.last.closed, isTrue);
    expect(f.voice.audioConsent, isFalse);
    await f.begin();
    f.voice.setAudioConsent(false);
    await flush();
    expect(f.audios.last.closed, isTrue);
    await f.begin();
    f.purchases.expire();
    await flush();
    expect(f.audios.last.closed, isTrue);
    expect(f.voice.canStart, isFalse);
  });

  test('Restart stops first and requires fresh confirmation instead of making another paid create', () async {
    final f = await fixture();
    await f.begin(deep: true);
    await f.voice.restart();
    expect(f.gateway.creates, 1);
    expect(f.audios.single.closed, isTrue);
    expect(f.voice.audioConsent, isFalse);
    expect(f.voice.deepThinkingConsent, isFalse);
    expect(f.voice.error, contains('Confirm audio sharing'));
  });

  test('ambiguous create is never replayed and closing is not treated as finalized', () async {
    final f = await fixture();
    f.gateway.createFailure = const EshaException('NETWORK_ERROR', 'Timed out');
    f.gateway.stopFinalized = false;
    await f.begin();
    expect(f.gateway.creates, 1);
    expect(f.audios.single.closed, isTrue);
    expect(f.voice.hasPendingSession, isTrue);
    expect(f.secure.values['esha.voice.pending.$accountA'], f.gateway.lastId);
    await f.voice.restart();
    await f.begin();
    expect(f.gateway.creates, 1);
    f.gateway.state = 'closed';
    f.gateway.finalized = true;
    await f.voice.reconcile();
    expect(f.voice.hasPendingSession, isFalse);
    expect(
      f.secure.values.containsKey('esha.voice.pending.$accountA'),
      isFalse,
    );
  });

  test('unknown 404 cannot discard a possibly billable intent but known not-configured can', () async {
    final f = await fixture();
    f.gateway.createFailure = const EshaException(
      'voice_not_configured',
      'Not configured',
    );
    await f.begin();
    expect(f.voice.hasPendingSession, isFalse);
    expect(f.gateway.stops, isEmpty);
    f.gateway.createFailure = const EshaException('NETWORK_ERROR', 'Timed out');
    f.gateway.stopFinalized = false;
    await f.begin();
    f.gateway.statusFailure = const EshaException(
      'not_found',
      'Not found',
      404,
    );
    await f.voice.reconcile();
    expect(f.voice.hasPendingSession, isTrue);
    expect(f.gateway.creates, 2);
  });

  test('explicit absent-reservation rejection clears only that UUID and requires fresh consent without retry', () async {
    final f = await fixture();
    f.gateway.createFailure = const EshaException(
      'voice_start_not_created',
      'The voice connection limit has been reached.',
      429,
    );
    await f.begin(deep: true);
    expect(f.gateway.creates, 1);
    expect(f.gateway.stops, isEmpty);
    expect(f.voice.hasPendingSession, isFalse);
    expect(
      f.secure.values.containsKey('esha.voice.pending.$accountA'),
      isFalse,
    );
    expect(f.audios.single.closed, isTrue);
    expect(f.audios.single.enabled, 0);
    expect(f.voice.audioConsent, isFalse);
    expect(f.voice.deepThinkingConsent, isFalse);
    await f.voice.start();
    expect(f.gateway.creates, 1);
  });

  test('generic start-budget and storage failures retain the intent until terminal evidence', () async {
    for (final code in [
      'voice_start_attempts_exhausted',
      'storage_unavailable',
      'voice_request_pending',
    ]) {
      final f = await fixture();
      f.gateway.createFailure = EshaException(
        code,
        'Start could not be confirmed.',
        503,
      );
      f.gateway.stopFinalized = false;
      await f.begin(deep: true);
      expect(f.gateway.creates, 1, reason: code);
      expect(f.voice.hasPendingSession, isTrue, reason: code);
      expect(f.secure.values['esha.voice.pending.$accountA'], f.gateway.lastId);
      expect(f.voice.audioConsent, isFalse);
      expect(f.voice.deepThinkingConsent, isFalse);
      await f.voice.start();
      expect(f.gateway.creates, 1);
      f.gateway.state = 'closed';
      f.gateway.finalized = true;
      await f.voice.reconcile();
      expect(f.voice.hasPendingSession, isFalse);
    }
  });

  test('an exhausted connection budget is explained without microphone access, pending ID or lost membership', () async {
    final f = await fixture();
    f.gateway.enabled = false;
    f.gateway.unavailabilityReason = 'voice_start_attempts_exhausted';
    await f.voice.refresh();
    expect(f.voice.error, EshaVoiceController.connectionLimitMessage);
    await f.begin(deep: true);
    expect(f.voice.error, EshaVoiceController.connectionLimitMessage);
    expect(f.audios, isEmpty);
    expect(f.gateway.creates, 0);
    expect(f.voice.hasPendingSession, isFalse);
    expect(f.purchases.hasAppAccess, isTrue);
    expect(f.voice.audioConsent, isFalse);
    final parsed = VoiceAvailability.fromJson({
      ...readyJson(),
      'unavailabilityReason': 'voice_start_attempts_exhausted',
      'usage': {
        ...usageJson(),
        'voiceStarts': {
          'configured': true,
          'limit': 5,
          'used': 5,
          'remaining': 0,
        },
      },
    }, DateTime.now());
    expect(parsed.enabled, isFalse);
    expect(parsed.connectionLimitReached, isTrue);
    expect(parsed.usage!.limitSeconds, 300);
  });

  test('closing and uncertain recovery reattaches the server watcher with stop without another create', () async {
    final f = await fixture();
    f.gateway.stopFinalized = false;
    await f.begin();
    await f.voice.pause();
    for (final state in ['closing', 'uncertain']) {
      f.gateway.state = state;
      final stopsBefore = f.gateway.stops.length;
      await f.voice.reconcile();
      expect(f.gateway.stops.length, stopsBefore + 1);
      expect(f.voice.hasPendingSession, isTrue);
    }
    expect(f.gateway.creates, 1);
    expect(f.voice.audioConsent, isFalse);
  });

  test(
    'cancel during microphone preparation never creates a paid session',
    () async {
      final f = await fixture();
      final offer = Completer<String>();
      f.makeAudio = () => FakeVoiceAudio()..pendingOffer = offer;
      f.voice.setAudioConsent(true);
      final start = f.voice.start();
      await flush();
      await f.voice.pause();
      expect(f.audios.single.closed, isTrue);
      offer.complete('v=0\r\noffer');
      await start;
      expect(f.gateway.creates, 0);
      expect(f.voice.hasPendingSession, isFalse);
    },
  );

  test(
    'cancel during paid creation prevents a late answer from enabling audio',
    () async {
      final f = await fixture();
      final create = Completer<VoiceSessionStatus>();
      f.gateway.pendingCreate = create;
      f.gateway.stopFinalized = false;
      f.voice.setAudioConsent(true);
      final start = f.voice.start();
      await flush();
      await f.voice.pause();
      create.complete(
        VoiceSessionStatus(
          requestId: f.gateway.lastId!,
          state: 'active',
          finalizationConfirmed: false,
          usage: voiceUsage(),
          sessionId: 'live_test',
          sdpAnswer: 'v=0\r\nanswer',
        ),
      );
      await start;
      await flush();
      expect(f.gateway.creates, 1);
      expect(f.audios.single.enabled, 0);
      expect(f.audios.single.closed, isTrue);
      expect(f.voice.hasPendingSession, isTrue);
    },
  );

  test('account loss during secure persistence cannot attach the old request to the new account state', () async {
    final f = await fixture();
    final write = Completer<void>();
    f.secure.beforeIntentWrite = write;
    f.voice.setAudioConsent(true);
    final start = f.voice.start();
    await flush();
    await f.api.signOut();
    await f.voice.attachAccount();
    write.complete();
    await start;
    expect(f.gateway.creates, 0);
    expect(f.voice.hasPendingSession, isFalse);
    expect(
      f.secure.values.containsKey('esha.voice.pending.$accountA'),
      isFalse,
    );
    expect(f.audios.single.closed, isTrue);
  });

  test('reopening recovers only the secure UUID and finalizes before another creation', () async {
    final f = await fixture();
    f.voice.dispose();
    await f.secure.write('esha.voice.pending.$accountA', requestA);
    f.gateway.state = 'active';
    f.gateway.finalized = false;
    f.voice = EshaVoiceController(
      api: f.api,
      purchases: f.purchases,
      gateway: f.gateway,
      transportFactory: () => throw StateError('recovery must not open audio'),
    );
    await f.voice.refresh();
    expect(f.gateway.creates, 0);
    expect(f.gateway.checks, greaterThanOrEqualTo(1));
    expect(f.gateway.stops, ['transport_error']);
    expect(f.voice.hasPendingSession, isFalse);
    expect(f.voice.audioConsent, isFalse);
  });

  test(
    'availability rejects stale entitlement, wrong model and malformed usage',
    () {
      final now = DateTime.now().toUtc();
      expect(VoiceAvailability.fromJson(readyJson(), now).enabled, isTrue);
      for (final status in [
        {...readyJson(), 'model': 'gpt-6.1-sol'},
        {...readyJson(), 'voiceEnabled': false},
        {
          ...readyJson(),
          'membership': {'active': true, 'verificationFresh': false},
        },
        {
          ...readyJson(),
          'membership': {
            'active': true,
            'verificationFresh': true,
            'expiresAt': now.toIso8601String(),
          },
        },
      ]) {
        expect(VoiceAvailability.fromJson(status, now).enabled, isFalse);
      }
      expect(
        () => VoiceUsage.fromJson({
          'voice': {'limitSeconds': '300'},
        }),
        throwsA(isA<EshaException>()),
      );
    },
  );

  test('signing in again as the same user resets call choices and closes the prior audio transport', () async {
    final f = await fixture();
    await f.begin(deep: true);
    await f.api.signIn('member@example.test', 'not-a-real-password');
    await f.voice.attachAccount();
    expect(f.audios.single.closed, isTrue);
    expect(f.voice.audioConsent, isFalse);
    expect(f.voice.deepThinkingConsent, isFalse);
    expect(f.voice.hasPendingSession, isTrue);
    await f.voice.refresh();
    expect(f.gateway.creates, 1);
    expect(f.voice.hasPendingSession, isFalse);
  });

  test('fractional provider seconds are preserved exactly while the display rounds down', () {
    final value = usageJson();
    value['voice'] = {
      'limitSeconds': 300,
      'usedSeconds': 5.8,
      'reservedSeconds': 0,
      'remainingSeconds': 294.2,
    };
    final usage = VoiceUsage.fromJson(value);
    expect(usage.usedSeconds, 5.8);
    expect(usage.remainingSeconds, 294.2);
    expect(voiceTime(usage.remainingSeconds), '4:54');
    for (final invalid in [double.nan, double.infinity, -0.1, '5.8']) {
      final bad = {
        ...value,
        'voice': {...object(value['voice']), 'usedSeconds': invalid},
      };
      expect(() => VoiceUsage.fromJson(bad), throwsA(isA<EshaException>()));
    }
  });

  test('unconfigured membership with no grant stays unavailable without inventing an allowance', () {
    final value = {
      ...readyJson(),
      'voiceEnabled': false,
      'membership': {
        'active': false,
        'verificationFresh': true,
        'expiresAt': null,
      },
      'usage': {
        'voice': {
          'configured': false,
          'limitSeconds': null,
          'usedSeconds': 0,
          'reservedSeconds': 0,
          'remainingSeconds': 0,
        },
        'deep': {
          'configured': false,
          'limit': null,
          'used': 0,
          'reserved': 0,
          'remaining': 0,
        },
      },
    };
    final result = VoiceAvailability.fromJson(value, DateTime.now());
    expect(result.enabled, isFalse);
    expect(result.usage, isNull);
    expect(
      VoiceSessionStatus.fromJson({
        'requestId': requestA,
        'state': 'closed',
        'finalizationConfirmed': true,
        'usage': value['usage'],
      }, requestA).finalized,
      isTrue,
    );
  });

  test('late deep answers survive finalization and restart through UUID-only history, never another paid create', () async {
    final f = await fixture();
    await f.begin(deep: true);
    await f.voice.stop();
    final sessionId = f.gateway.lastId!;
    const answer = 'Use the satin finish you already own.';
    f.gateway.results = [
      const VoiceDeepResult(
        requestId: 'bbbbbbbb-bbbb-5bbb-8bbb-bbbbbbbbbbbb',
        answer: answer,
        productIds: ['existing-product-id'],
      ),
    ];
    await f.voice.refreshResults();
    expect(f.voice.deepResults.single.answer, answer);
    await f.voice.refreshResults();
    expect(f.voice.deepResults, hasLength(1));
    expect(f.gateway.creates, 1);
    final saved = f.secure.values['esha.voice.recent.$accountA']!;
    expect(jsonDecode(saved), [sessionId]);
    expect(saved.contains(answer), isFalse);
    expect(saved.contains('v=0'), isFalse);
    f.voice.dispose();
    f.voice = EshaVoiceController(
      api: f.api,
      purchases: f.purchases,
      gateway: f.gateway,
      transportFactory: () => throw StateError('history must never open audio'),
    );
    await f.voice.refresh();
    await flush();
    expect(f.voice.deepResults.single.answer, answer);
    expect(f.gateway.creates, 1);
    f.account = accountB;
    await f.api.signIn('another@example.test', 'not-a-real-password');
    await f.voice.attachAccount();
    final previousReads = f.gateway.checkedIds.length;
    await f.voice.refreshResults();
    expect(f.voice.deepResults, isEmpty);
    expect(f.voice.hasSavedAnswerSessions, isFalse);
    expect(f.gateway.checkedIds.length, previousReads);
    expect(f.secure.values['esha.voice.recent.$accountA'], saved);
  });

  test('historical call usage cannot overwrite the renewed current-period allowance', () async {
    final f = await fixture();
    await f.begin(deep: true);
    await f.voice.stop();
    f.gateway.historicalAllowance = voiceUsage(used: 300);
    f.gateway.allowance = voiceUsage(limit: 1800, deepLimit: 10);
    await f.voice.refresh();
    await flush();
    expect(f.voice.usage!.limitSeconds, 1800);
    expect(f.voice.usage!.remainingSeconds, 1800);
    expect(f.voice.usage!.deepRemaining, 10);
    f.voice.setAudioConsent(true);
    expect(f.voice.canStart, isTrue);
    expect(f.gateway.creates, 1);
  });

  test(
    'deep results require bounded verified fields and remain plain data',
    () {
      final result = {
        'requestId': 'bbbbbbbb-bbbb-5bbb-8bbb-bbbbbbbbbbbb',
        'answer': '<b>Plain answer text</b>',
        'productIds': ['catalog-id'],
      };
      expect(VoiceDeepResult.parse([result]).single.answer, result['answer']);
      for (final bad in [
        [result, result],
        [
          {...result, 'requestId': '../another-account'},
        ],
        [
          {...result, 'answer': 'a' * 24001},
        ],
        [
          {...result, 'productIds': List.filled(13, 'catalog-id')},
        ],
        List.filled(11, result),
      ]) {
        expect(() => VoiceDeepResult.parse(bad), throwsA(isA<EshaException>()));
      }
    },
  );

  test('session readback requires exact request binding and confirmed terminal state', () {
    final base = {
      'requestId': requestA,
      'state': 'closed',
      'finalizationConfirmed': true,
      'usage': usageJson(),
    };
    expect(VoiceSessionStatus.fromJson(base, requestA).finalized, isTrue);
    for (final bad in [
      {...base, 'requestId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
      {...base, 'state': 'active'},
      {...base, 'finalizationConfirmed': 'true'},
    ]) {
      expect(
        () => VoiceSessionStatus.fromJson(bad, requestA),
        throwsA(isA<EshaException>()),
      );
    }
  });

  test('create accepts a bound starting session while SDP is applied, but never a closing session or another model', () {
    final base = {
      'requestId': requestA,
      'state': 'starting',
      'finalizationConfirmed': false,
      'usage': usageJson(),
      'sessionId': 'live_test',
      'model': eshaVoiceModel,
      'sdpAnswer': 'v=0\r\nanswer',
    };
    expect(
      VoiceSessionStatus.fromJson(base, requestA, created: true).state,
      'starting',
    );
    expect(
      VoiceSessionStatus.fromJson(
        {...base, 'state': 'active'},
        requestA,
        created: true,
      ).state,
      'active',
    );
    for (final bad in [
      {...base, 'state': 'closing'},
      {...base, 'model': 'gpt-6.1-sol'},
      {...base, 'sdpAnswer': null},
      {...base, 'sessionId': ''},
    ]) {
      expect(
        () => VoiceSessionStatus.fromJson(bad, requestA, created: true),
        throwsA(isA<EshaException>()),
      );
    }
  });

  test('authenticated gateway sends only agreed consent and SDP fields and never retries a failed create', () async {
    final calls = <http.Request>[];
    final api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: MemoryStore(),
      localStorage: MemoryStore(),
      platform: 'ios',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return http.Response(jsonEncode(authPayload(accountA)), 200);
        }
        calls.add(request);
        if (request.url.path == '/api/esha/voice/status') {
          return http.Response(jsonEncode(readyJson()), 200);
        }
        return http.Response(
          jsonEncode({'code': 'authentication_required', 'error': 'Sign in'}),
          401,
        );
      }),
    );
    addTearDown(api.dispose);
    await api.signIn('member@example.test', 'not-a-real-password');
    final gateway = KorlixVoiceGateway(api);
    expect((await gateway.availability()).enabled, isTrue);
    await expectLater(
      gateway.create(
        requestId: requestA,
        sdpOffer: 'v=0\r\noffer',
        deepThinkingConsent: false,
      ),
      throwsA(isA<EshaException>()),
    );
    expect(calls.map((value) => value.url.path), [
      '/api/esha/voice/status',
      '/api/esha/voice/sessions',
    ]);
    expect(calls.first.url.queryParameters, {'provider': 'apple'});
    expect(jsonDecode(calls.last.body), {
      'requestId': requestA,
      'sdpOffer': 'v=0\r\noffer',
      'audioSharingConsent': true,
      'deepThinkingConsent': false,
    });
    expect(calls.last.url.host, 'chee-chai-chee-backend.onrender.com');
    expect(calls.last.headers['authorization'], 'Bearer test-token-$accountA');
  });

  test('real WebRTC permission request is audio-only and permission failure is sanitized', () async {
    const channel = MethodChannel('FlutterWebRTC.Method');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return null;
          if (call.method == 'getUserMedia') {
            throw PlatformException(
              code: 'NotAllowedError',
              message: 'permission denied',
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final audio = WebRtcVoiceAudio();
    await expectLater(audio.createOffer(), throwsA(isA<EshaException>()));
    final request = calls.singleWhere((call) => call.method == 'getUserMedia');
    expect(object(request.arguments)['constraints'], {
      'audio': true,
      'video': false,
    });
    expect(calls.any((call) => call.method == 'createPeerConnection'), isFalse);
    await audio.close();
  });

  testWidgets(
    'voice panel displays server trial and monthly amounts and separate unchecked consents',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await fixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: eshaTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: EshaVoicePanel(controller: f.voice),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5:00 of 5:00 voice time remaining'), findsOneWidget);
      expect(
        find.text('2 of 2 deep-thinking consultations remaining'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('esha-voice-audio-consent')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('esha-voice-deep-consent')),
            )
            .value,
        isFalse,
      );
      f.gateway.allowance = voiceUsage(limit: 1800, deepLimit: 10);
      await f.voice.refresh();
      await tester.pumpAndSettle();
      expect(find.text('30:00 of 30:00 voice time remaining'), findsOneWidget);
      expect(
        find.text('10 of 10 deep-thinking consultations remaining'),
        findsOneWidget,
      );
      expect(f.gateway.creates, 0);
      expect(f.audios, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

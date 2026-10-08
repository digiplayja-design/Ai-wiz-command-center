import 'dart:convert';

import 'package:ai_wiz_command_center/reviews/korlix_review_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Duration clock;
  late KorlixReviewActivityTracker tracker;

  setUp(() {
    clock = Duration.zero;
    tracker = KorlixReviewActivityTracker(
      userId: 'member-a',
      initialProgress: ReviewActivityProgress(),
      monotonicNow: () => clock,
    );
    SharedPreferences.setMockInitialValues({});
  });

  void advance(Duration time, {bool interact = false}) {
    clock += time;
    if (interact) {
      tracker.recordInteraction();
    } else {
      tracker.tick();
    }
  }

  void activeSeconds(int seconds) {
    for (var i = 0; i < seconds; i++) {
      advance(const Duration(seconds: 1), interact: i % 30 == 0);
    }
  }

  test('three active hours required: 10799 seconds is not 10800', () {
    tracker.setAvailable(true);
    tracker.recordInteraction();
    activeSeconds(10799);
    expect(tracker.progress.activeMilliseconds, 10799000);
    expect(tracker.eligible, false);
    advance(const Duration(seconds: 1));
    expect(tracker.progress.activeMilliseconds, 10800000);
    expect(tracker.eligible, true);
    activeSeconds(100);
    expect(tracker.progress.activeMilliseconds, 10800000);
  });

  test('foreground without input, background and screensaver earn no time', () {
    tracker.setAvailable(true);
    for (var i = 0; i < 12; i++) {
      advance(const Duration(seconds: 5));
    }
    expect(tracker.progress.activeMilliseconds, 0);
    tracker.recordInteraction();
    advance(const Duration(seconds: 10));
    tracker.setAvailable(false);
    activeSeconds(90);
    expect(tracker.progress.activeMilliseconds, 10000);
    tracker.setAvailable(true);
    advance(const Duration(seconds: 10));
    expect(tracker.progress.activeMilliseconds, 10000);
    tracker.recordInteraction();
    advance(const Duration(seconds: 7));
    expect(tracker.progress.activeMilliseconds, 17000);
  });

  test('frequent pointer input preserves fractions of active milliseconds', () {
    tracker.setAvailable(true);
    tracker.recordInteraction();
    for (var i = 0; i < 10; i++) {
      advance(const Duration(microseconds: 500), interact: true);
    }
    expect(tracker.progress.activeMilliseconds, 5);
  });

  test('idle cutoff credits only the observed part up to two minutes', () {
    tracker.setAvailable(true);
    tracker.recordInteraction();
    for (var i = 0; i < 11; i++) {
      advance(const Duration(seconds: 11));
    }
    expect(tracker.progress.activeMilliseconds, 120000);
    for (var i = 0; i < 20; i++) {
      advance(const Duration(seconds: 5));
    }
    expect(tracker.progress.activeMilliseconds, 120000);
    tracker.recordInteraction();
    advance(const Duration(seconds: 10));
    expect(tracker.progress.activeMilliseconds, 130000);
  });

  test('suspended heartbeat gaps and backwards clocks never add time', () {
    tracker.setAvailable(true);
    tracker.recordInteraction();
    advance(const Duration(seconds: 10));
    advance(const Duration(seconds: 40));
    expect(tracker.progress.activeMilliseconds, 10000);
    advance(const Duration(seconds: 5));
    expect(tracker.progress.activeMilliseconds, 10000);
    tracker.recordInteraction();
    advance(const Duration(seconds: 2));
    clock = Duration.zero;
    tracker.tick();
    advance(const Duration(seconds: 5));
    expect(tracker.progress.activeMilliseconds, 12000);
    tracker.recordInteraction();
    advance(const Duration(days: 2));
    expect(tracker.progress.activeMilliseconds, 12000);
  });

  test('restored eligibility still requires foreground input', () {
    tracker = KorlixReviewActivityTracker(
      userId: 'member-a',
      initialProgress: ReviewActivityProgress(activeMilliseconds: 10800000),
      monotonicNow: () => clock,
    );
    expect(tracker.eligible, false);
    tracker.setAvailable(true);
    expect(tracker.eligible, false);
    tracker.recordInteraction();
    expect(tracker.eligible, true);
    tracker.setAvailable(false);
    expect(tracker.eligible, false);
  });

  test('handled and suppressed prompts cannot become eligible again', () {
    for (final state in [
      ReviewActivityProgress(
        activeMilliseconds: 10800000,
        automaticPromptHandled: true,
      ),
      ReviewActivityProgress(activeMilliseconds: 10800000, suppressed: true),
    ]) {
      tracker = KorlixReviewActivityTracker(
        userId: 'member-a',
        initialProgress: state,
        monotonicNow: () => clock,
      );
      tracker.setAvailable(true);
      tracker.recordInteraction();
      expect(tracker.eligible, false);
      tracker.mergeProgress(ReviewActivityProgress());
      expect(tracker.eligible, false);
    }
  });

  test('serialization validates corruption without inventing eligibility', () {
    for (final raw in [
      null,
      '',
      '{',
      '[]',
      '42',
      '{"version":2}',
      jsonEncode({'version': 1, 'active_ms': -10}),
      jsonEncode({'version': 1, 'active_ms': 10800001}),
      jsonEncode({'version': 1, 'active_ms': 10800000.0}),
      jsonEncode({'version': 1, 'active_ms': '10800000'}),
    ]) {
      expect(ReviewActivityProgress.decode(raw).activeMilliseconds, 0);
      expect(ReviewActivityProgress.decode(raw).eligible, false);
    }
    final saved = ReviewActivityProgress(
      activeMilliseconds: 9876,
      automaticPromptHandled: true,
      suppressed: true,
    );
    final restored = ReviewActivityProgress.decode(jsonEncode(saved.toJson()));
    expect(restored.toJson(), saved.toJson());
    expect(
      ReviewActivityProgress(activeMilliseconds: -1).activeMilliseconds,
      0,
    );
    expect(
      ReviewActivityProgress(activeMilliseconds: 999999999999)
          .activeMilliseconds,
      10800000,
    );
    final corrupt = ReviewActivityProgress.fromJson({
      'version': 1,
      'active_ms': -99,
      'automatic_prompt_handled': true,
    });
    expect(corrupt.automaticPromptHandled, true);
  });

  test(
    'storage isolates accounts and survives repository recreation',
    () async {
      final repository = SharedPreferencesReviewActivityRepository();
      await repository.save(
        'member-a',
        ReviewActivityProgress(activeMilliseconds: 123456),
      );
      await repository.save(
        'member-b',
        ReviewActivityProgress(activeMilliseconds: 42),
      );
      final reopened = SharedPreferencesReviewActivityRepository();
      expect((await reopened.load('member-a')).activeMilliseconds, 123456);
      expect((await reopened.load('member-b')).activeMilliseconds, 42);
      expect((await reopened.load('member-c')).activeMilliseconds, 0);
      expect(
        SharedPreferencesReviewActivityRepository.storageKey('a/b'),
        isNot(SharedPreferencesReviewActivityRepository.storageKey('a_b')),
      );
      expect(
        () => SharedPreferencesReviewActivityRepository.storageKey(''),
        throwsArgumentError,
      );
    },
  );

  test(
    'only one persisted automatic claim wins and stale writes cannot clear it',
    () async {
      final first = SharedPreferencesReviewActivityRepository();
      final second = SharedPreferencesReviewActivityRepository();
      final due = ReviewActivityProgress(activeMilliseconds: 10800000);
      expect(
        await first.claimAutomaticPrompt(
          'member-a',
          ReviewActivityProgress(activeMilliseconds: 10799000),
        ),
        false,
      );
      expect(
        await Future.wait([
          first.claimAutomaticPrompt('member-a', due),
          second.claimAutomaticPrompt('member-a', due),
        ]),
        [true, false],
      );
      await second.save(
        'member-a',
        ReviewActivityProgress(activeMilliseconds: 20),
      );
      final persisted = await first.load('member-a');
      expect(persisted.activeMilliseconds, 10800000);
      expect(persisted.automaticPromptHandled, true);
      expect(await first.claimAutomaticPrompt('member-a', due), false);
      expect(await first.claimAutomaticPrompt('member-b', due), true);
      expect(persisted.toJson().keys, isNot(contains('rating')));
    },
  );

  test(
    'suppression persists and blocks the automatic prompt before threshold',
    () async {
      final repository = SharedPreferencesReviewActivityRepository();
      await repository.suppress(
        'member-a',
        ReviewActivityProgress(activeMilliseconds: 500),
      );
      final due = ReviewActivityProgress(activeMilliseconds: 10800000);
      expect(await repository.claimAutomaticPrompt('member-a', due), false);
      expect((await repository.load('member-a')).suppressed, true);
    },
  );

  test(
    'invalid stored types reset safely and unavailable storage fails closed',
    () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesReviewActivityRepository.storageKey('member-a'): 123,
      });
      final repository = SharedPreferencesReviewActivityRepository();
      expect((await repository.load('member-a')).activeMilliseconds, 0);
      final failing = SharedPreferencesReviewActivityRepository(
        loadPreferences: () => Future.error(StateError('Unavailable storage')),
      );
      await expectLater(
        failing.claimAutomaticPrompt(
          'member-a',
          ReviewActivityProgress(activeMilliseconds: 10800000),
        ),
        throwsStateError,
      );
    },
  );
}

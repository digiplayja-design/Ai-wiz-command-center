import 'dart:async';

import 'package:ai_wiz_command_center/reviews/korlix_review_activity.dart';
import 'package:ai_wiz_command_center/reviews/korlix_review_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepository extends SharedPreferencesReviewActivityRepository {
  final values = <String, ReviewActivityProgress>{};
  final loads = <String, Completer<ReviewActivityProgress>>{};
  Completer<bool>? claimGate;
  bool failWrites = false;
  int claims = 0;
  int saves = 0;

  @override
  Future<ReviewActivityProgress> load(String userId) async =>
      loads[userId]?.future ?? values[userId] ?? ReviewActivityProgress();

  @override
  Future<ReviewActivityProgress> save(
    String userId,
    ReviewActivityProgress progress,
  ) async {
    saves++;
    if (failWrites) throw StateError('Device storage unavailable');
    return values[userId] = (values[userId] ?? ReviewActivityProgress()).merge(
      progress,
    );
  }

  @override
  Future<bool> claimAutomaticPrompt(
    String userId,
    ReviewActivityProgress progress,
  ) async {
    claims++;
    if (failWrites) throw StateError('Device storage unavailable');
    if (claimGate != null) await claimGate!.future;
    final merged = (values[userId] ?? ReviewActivityProgress()).merge(progress);
    if (!merged.eligible) return false;
    values[userId] = merged.copyWith(automaticPromptHandled: true);
    return true;
  }
}

class _Harness {
  final repository = _MemoryRepository();
  final revision = ValueNotifier(0);
  final navigatorKey = GlobalKey<NavigatorState>();
  Duration clock = Duration.zero;
  String? account = 'member-a';
  bool available = true;
  bool safe = true;
  int prompts = 0;
  int cancellations = 0;
  Completer<void>? visiblePrompt;

  void notify() => revision.value++;

  Widget build() => MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => KorlixReviewHost(
      sessionChanges: revision,
      accountScope: () => account,
      isAvailable: () => available,
      canPrompt: () => safe,
      navigatorKey: navigatorKey,
      repository: repository,
      monotonicNow: () => clock,
      onPrompt: (_) async {
        prompts++;
        await visiblePrompt?.future;
      },
      onPromptCancelled: () async {
        cancellations++;
        visiblePrompt?.complete();
        visiblePrompt = null;
      },
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const ValueKey('activity'),
            onPressed: () {},
            child: const Text('Activity'),
          ),
          const TextField(key: ValueKey('editor')),
        ],
      ),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
  }

  Future<void> input(WidgetTester tester) =>
      tester.tap(find.byKey(const ValueKey('activity')));

  Future<void> advance(WidgetTester tester, [int seconds = 5]) async {
    clock += Duration(seconds: seconds);
    await tester.pump(Duration(seconds: seconds));
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    revision.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'threshold uses active time and claims once before presentation',
    (tester) async {
      final h = _Harness();
      h.repository.values['member-a'] = ReviewActivityProgress(
        activeMilliseconds:
            ReviewActivityProgress.thresholdMilliseconds - 10000,
      );
      await h.mount(tester);
      await h.input(tester);
      await h.advance(tester);
      expect(h.prompts, 0);
      await h.advance(tester);
      expect(h.prompts, 1);
      expect(h.repository.values['member-a']!.automaticPromptHandled, true);
      h.notify();
      await h.input(tester);
      await h.advance(tester);
      await h.advance(tester);
      expect(h.prompts, 1);
      expect(h.repository.claims, 1);
      await h.close(tester);

      // Reconstructing the host with persisted state never repeats the prompt.
      final reopened = _Harness();
      reopened.repository.values.addAll(h.repository.values);
      await reopened.mount(tester);
      await reopened.input(tester);
      await reopened.advance(tester);
      expect(reopened.prompts, 0);
      await reopened.close(tester);
    },
  );

  testWidgets('background and screensaver stop activity until new input', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds - 10000,
    );
    await h.mount(tester);
    await h.input(tester);
    await h.advance(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 4; i++) {
      await h.advance(tester);
    }
    expect(h.prompts, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.advance(tester);
    expect(h.prompts, 0);
    h.available = false;
    h.notify();
    await h.input(tester);
    await h.advance(tester);
    h.available = true;
    h.notify();
    await h.advance(tester);
    expect(h.prompts, 0);
    await h.input(tester);
    await h.advance(tester);
    expect(h.prompts, 1);
    await h.close(tester);
  });

  testWidgets('eligible members wait for a safe screen and a pause in input', (
    tester,
  ) async {
    final h = _Harness()..safe = false;
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
    );
    await h.mount(tester);
    await h.input(tester);
    await h.advance(tester);
    expect(h.repository.claims, 0);
    h.safe = true;
    h.notify();
    await h.advance(tester, 4);
    await h.input(tester);
    await h.advance(tester, 1);
    expect(h.prompts, 0);
    await h.advance(tester);
    expect(h.prompts, 1);
    await h.close(tester);
  });

  testWidgets('keyboard and focused mobile editor postpone automatic prompt', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
    );
    await h.mount(tester);
    await tester.tap(find.byKey(const ValueKey('editor')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'private contents');
    await h.advance(tester);
    expect(h.prompts, 0);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await h.advance(tester);
    expect(h.prompts, 1);
    await h.close(tester);
  });

  testWidgets('hardware keyboard activity counts without consuming the key', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds - 5000,
    );
    await h.mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.advance(tester);
    expect(h.prompts, 1);
    await h.close(tester);
  });

  testWidgets('software keyboard edits resume active time after idle', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.tap(find.byKey(const ValueKey('editor')));
    await tester.pump();
    for (var i = 0; i < 25; i++) {
      await h.advance(tester);
    }
    expect(h.repository.values['member-a']!.activeMilliseconds, 120000);
    // No further pointer or hardware-key events: editing through the platform
    // input connection must still count as real activity without reading text.
    await tester.enterText(find.byType(TextField), 'mobile typing');
    await h.advance(tester);
    h.available = false;
    h.notify();
    await tester.pump();
    expect(h.repository.values['member-a']!.activeMilliseconds, 125000);
    expect(h.prompts, 0);
    await h.close(tester);
  });

  testWidgets('late account load cannot transfer another account eligibility', (
    tester,
  ) async {
    final h = _Harness();
    final oldLoad = Completer<ReviewActivityProgress>();
    h.repository.loads['member-a'] = oldLoad;
    await h.mount(tester);
    h.account = 'member-b';
    h.notify();
    await tester.pump();
    oldLoad.complete(
      ReviewActivityProgress(
        activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
      ),
    );
    await tester.pump();
    await h.input(tester);
    for (var i = 0; i < 6; i++) {
      await h.advance(tester);
    }
    expect(h.prompts, 0);
    expect(h.repository.values['member-b']!.activeMilliseconds, 30000);
    expect(h.repository.values['member-a'], isNull);
    await h.close(tester);
  });

  testWidgets('logout during claim never presents to another member', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
    );
    h.repository.claimGate = Completer<bool>();
    await h.mount(tester);
    await h.input(tester);
    await h.advance(tester);
    expect(h.repository.claims, 1);
    h.account = null;
    h.notify();
    h.repository.claimGate!.complete(true);
    await tester.pump();
    expect(h.prompts, 0);
    h.account = 'member-b';
    h.notify();
    await tester.pump();
    await h.input(tester);
    await h.advance(tester);
    expect(h.prompts, 0);
    await h.close(tester);
  });

  testWidgets('storage failure suppresses presentation and repeated attempts', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
    );
    h.repository.failWrites = true;
    await h.mount(tester);
    await h.input(tester);
    await h.advance(tester);
    await h.input(tester);
    await h.advance(tester);
    expect(h.prompts, 0);
    expect(h.repository.claims, 1);
    await h.close(tester);
  });

  testWidgets('unsafe navigation cancels an in-flight request once', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.values['member-a'] = ReviewActivityProgress(
      activeMilliseconds: ReviewActivityProgress.thresholdMilliseconds,
    );
    h.visiblePrompt = Completer<void>();
    await h.mount(tester);
    await h.input(tester);
    await h.advance(tester);
    expect(h.prompts, 1);
    h.safe = false;
    h.notify();
    h.notify();
    await tester.pump();
    expect(h.cancellations, 1);
    h.safe = true;
    h.notify();
    await h.input(tester);
    await h.advance(tester);
    expect(h.prompts, 1);
    await h.close(tester);
  });

  testWidgets('input events do not write storage on each pointer movement', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    for (var i = 0; i < 10; i++) {
      await h.input(tester);
    }
    expect(h.repository.saves, 0);
    for (var i = 0; i < 6; i++) {
      await h.advance(tester);
    }
    expect(h.repository.saves, 1);
    expect(h.repository.values['member-a']!.activeMilliseconds, 30000);
    await h.close(tester);
  });
}

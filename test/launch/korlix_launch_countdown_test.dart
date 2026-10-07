import 'package:ai_wiz_command_center/launch/korlix_launch_countdown.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  required DateTime Function() now,
  String theme = 'korlix_blue',
  double scale = 1,
  bool visible = true,
}) => tester.pumpWidget(
  MaterialApp(
    theme: korlixBuildTheme(theme),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: TickerMode(
            enabled: visible,
            child: KorlixLaunchCountdown(now: now),
          ),
        ),
      ),
    ),
  ),
);

Finder unit(String name) => find.byKey(ValueKey('launch-$name'));
Finder digit(String name, String value) =>
    find.descendant(of: unit(name), matching: find.text(value));

void main() {
  test('deadline is one instant for Eastern and other time zones', () {
    for (final instant in [
      '2026-10-15T09:00:00-04:00',
      '2026-10-15T13:00:00Z',
      '2026-10-15T22:00:00+09:00',
      '2026-10-15T06:00:00-07:00',
    ]) {
      final parsed = DateTime.parse(instant);
      expect(parsed.isAtSameMomentAs(korlixWebLaunchAt), isTrue);
      expect(KorlixLaunchRemaining.at(parsed).complete, isTrue);
    }
    final before = KorlixLaunchRemaining.at(
      DateTime.parse('2026-10-13T07:56:55-04:00'),
    );
    expect(
      (before.days, before.hours, before.minutes, before.seconds),
      (2, 1, 3, 5),
    );
  });

  test(
    'last partial second stays positive; deadline and later clamp to zero',
    () {
      expect(
        KorlixLaunchRemaining.at(
          korlixWebLaunchAt.subtract(const Duration(microseconds: 1)),
        ).totalSeconds,
        1,
      );
      expect(KorlixLaunchRemaining.at(korlixWebLaunchAt).totalSeconds, 0);
      expect(
        KorlixLaunchRemaining.at(
          korlixWebLaunchAt.add(const Duration(days: 30)),
        ).totalSeconds,
        0,
      );
    },
  );

  testWidgets(
    'delayed ticks recompute actual time, without accumulated drift',
    (tester) async {
      var now = korlixWebLaunchAt.subtract(const Duration(hours: 2));
      await mount(tester, now: () => now);
      expect(digit('hours', '02'), findsOneWidget);
      now = now.add(const Duration(minutes: 37, seconds: 16));
      await tester.pump(const Duration(seconds: 1));
      expect(digit('hours', '01'), findsOneWidget);
      expect(digit('minutes', '22'), findsOneWidget);
      expect(digit('seconds', '44'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('background stops polling and resume catches up immediately', (
    tester,
  ) async {
    var now = korlixWebLaunchAt.subtract(const Duration(days: 2));
    var reads = 0;
    await mount(
      tester,
      now: () {
        reads++;
        return now;
      },
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final pausedReads = reads;
    now = now.add(const Duration(days: 1, hours: 3));
    await tester.pump(const Duration(minutes: 15));
    expect(reads, pausedReads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(digit('days', '00'), findsOneWidget);
    expect(digit('hours', '21'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('covered route stops polling and removal cancels its timer', (
    tester,
  ) async {
    var now = korlixWebLaunchAt.subtract(const Duration(minutes: 4));
    var reads = 0;
    DateTime clock() {
      reads++;
      return now;
    }

    await mount(tester, now: clock);
    await mount(tester, now: clock, visible: false);
    final coveredReads = reads;
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(minutes: 3));
    expect(reads, coveredReads);
    await mount(tester, now: clock);
    expect(digit('minutes', '01'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final removedReads = reads;
    await tester.pump(const Duration(minutes: 2));
    expect(reads, removedReads);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expiry removes digits, stops timer and makes no readiness claim',
    (tester) async {
      var now = korlixWebLaunchAt.subtract(const Duration(milliseconds: 100));
      var reads = 0;
      await mount(
        tester,
        now: () {
          reads++;
          return now;
        },
      );
      expect(digit('seconds', '01'), findsOneWidget);
      now = korlixWebLaunchAt;
      await tester.pump(const Duration(seconds: 1));
      expect(unit('seconds'), findsNothing);
      expect(find.text('Launch countdown complete'), findsOneWidget);
      final completedReads = reads;
      now = now.add(const Duration(days: 1));
      await tester.pump(const Duration(days: 1));
      expect(reads, completedReads);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final theme in ['korlix_blue', 'pure_white']) {
    for (final layout in [(320.0, 1.0), (320.0, 2.0), (1024.0, 1.0)]) {
      testWidgets('readable $theme at width ${layout.$1}, scale ${layout.$2}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(layout.$1, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await mount(
          tester,
          theme: theme,
          scale: layout.$2,
          now: () => korlixWebLaunchAt.subtract(
            const Duration(days: 7, hours: 23, minutes: 59, seconds: 59),
          ),
        );
        for (final name in ['days', 'hours', 'minutes', 'seconds']) {
          final box = tester.getRect(unit(name));
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.right, lessThanOrEqualTo(layout.$1));
        }
        final dayTop = tester.getTopLeft(unit('days')).dy;
        final minuteTop = tester.getTopLeft(unit('minutes')).dy;
        if (layout.$2 == 2) {
          expect(minuteTop, greaterThan(dayTop));
        } else {
          expect(minuteTop, dayTop);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('one accessible summary without per-second live announcements', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(
      tester,
      now: () => korlixWebLaunchAt.subtract(const Duration(days: 1)),
    );
    final summary = find.bySemanticsLabel(
      'Web launch, $korlixWebLaunchDateLabel. '
      '1 days, 0 hours, 0 minutes, 0 seconds remaining.',
    );
    expect(summary, findsOneWidget);
    final node = tester.getSemantics(summary);
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/social/domino/domino_screen.dart';
import 'package:ai_wiz_command_center/social/domino/domino_solo.dart';
import 'package:ai_wiz_command_center/social/domino/domino_tiles.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';

import 'agent_studio_test.dart' as fixtures;
import 'domino_test.dart' as domino;
import 'social_test.dart' as social;

const thinkingDelay = Duration(seconds: 3);

DominoSoloController controller(domino.Store store, {int seed = 17}) =>
    DominoSoloController(
      client: store.client,
      playerName: 'Alex',
      random: Random(seed),
      thinkDelay: thinkingDelay,
    );

Future<void> humanMove(DominoSoloController c) async {
  final legal = socialItems(c.table['legal']);
  if (legal.isEmpty) {
    await c.move('pass');
  } else {
    await c.move(
      'play',
      tile: '${legal.first['tile']}',
      side: '${legal.first['side']}',
    );
  }
}

Future<void> waitForHuman(WidgetTester t, DominoSoloController c) async {
  for (var step = 0; step < 3 && !c.myTurn; step++) {
    await t.pump(thinkingDelay + const Duration(milliseconds: 1));
  }
  expect(c.myTurn, isTrue);
}

Future<void> finishRound(WidgetTester t, DominoSoloController c) async {
  for (var turn = 0; turn < 60 && c.table['phase'] == 'playing'; turn++) {
    if (c.myTurn) await humanMove(c);
    await t.pump(thinkingDelay + const Duration(milliseconds: 1));
  }
  expect(c.table['phase'], 'finished');
}

int pips(String value) =>
    value.split('-').fold(0, (sum, pip) => sum + int.parse(pip));

Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
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

  testWidgets(
    'lobby starts the chosen computer level without creating a server table',
    (t) async {
      final store = domino.Store();
      await social.mount(
        t,
        DominoLobby(client: store.client, profile: social.me),
      );
      await fixtures.capture(t, 'domino-solo-lobby');
      await t.ensureVisible(find.byKey(const Key('domino-play-computer')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('domino-play-computer')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('domino-difficulty-easy')), findsOneWidget);
      expect(
        find.byKey(const Key('domino-difficulty-standard')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('domino-difficulty-hard')));
      await t.pump();
      await fixtures.capture(t, 'domino-solo-difficulty');
      await t.tap(find.byKey(const Key('domino-start-solo')));
      await t.pumpAndSettle();
      final screen = t.widget<DominoTableScreen>(
        find.byType(DominoTableScreen),
      );
      final c = screen.controller! as DominoSoloController;
      expect(c.difficulty, DominoDifficulty.hard);
      expect(c.table['capacity'], 2);
      expect(c.table['phase'], 'playing');
      expect(find.byKey(const Key('domino-ready')), findsNothing);
      expect(find.byKey(const Key('domino-join-video')), findsNothing);
      expect(find.byTooltip('Refresh table'), findsNothing);
      expect(store.calls.every((call) => call['action'] == 'list'), isTrue);
      expect(c.media, isNull);

      await t.tap(find.byTooltip('Leave table'));
      await t.pumpAndSettle();
      expect(find.text('Leave this practice game?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Leave table'));
      await t.pumpAndSettle();
      expect(find.byType(DominoTableScreen), findsNothing);
      expect(c.closed, isTrue);
      expect(store.calls.every((call) => call['action'] == 'list'), isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      store.dispose();
    },
  );

  testWidgets(
    'hints select a legal tile, sorting keeps the deal, and the computer replies locally',
    (t) async {
      final store = domino.Store(), c = controller(store);
      await social.mount(
        t,
        DominoTableScreen(
          client: store.client,
          initial: c.table,
          controller: c,
        ),
      );
      await waitForHuman(t, c);
      final dealt = List<String>.from(c.table['hand'] as List);
      final revision = c.table['revision'];
      await t.tap(find.byKey(const Key('domino-sort')));
      await t.pump();
      final sortedTiles = t
          .widgetList<DominoTile>(find.byType(DominoTile))
          .where((tile) => tile.key is ValueKey<String>)
          .map((tile) => (tile.key! as ValueKey<String>).value)
          .where((key) => key.startsWith('domino-tile-'))
          .map((key) => key.substring('domino-tile-'.length))
          .toList();
      final totals = sortedTiles.map(pips).toList();
      expect(totals, orderedEquals([...totals]..sort((a, b) => b - a)));
      expect(sortedTiles, unorderedEquals(dealt));
      expect(c.table['hand'], dealt);
      expect(c.table['revision'], revision);

      await t.tap(find.byKey(const Key('domino-hint')));
      await t.pump();
      expect(find.byKey(const Key('domino-hint-text')), findsOneWidget);
      final selected = t
          .widgetList<DominoTile>(find.byType(DominoTile))
          .singleWhere((tile) => tile.selected);
      final tile = '${selected.a}-${selected.b}';
      final legal = socialItems(c.table['legal']);
      final choice = legal.firstWhere((move) => move['tile'] == tile);
      await t.tap(find.byKey(Key('domino-${choice['side']}')));
      await t.pump();
      expect(c.table['hand'], hasLength(dealt.length - 1));
      expect(c.table['turn'], 'computer');
      expect(c.thinking, isTrue);
      expect(find.byKey(const Key('domino-hint-text')), findsNothing);
      final playedRevision = c.table['revision'] as int;
      await t.pump(thinkingDelay + const Duration(milliseconds: 1));
      expect(c.table['revision'] as int, greaterThan(playedRevision));
      expect(c.myTurn, isTrue);
      expect(store.calls, isEmpty);
      expect(c.media, isNull);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'domino-solo-gameplay');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      store.dispose();
    },
  );

  testWidgets(
    'a completed solo round can be replayed while keeping the score',
    (t) async {
      final store = domino.Store(), c = controller(store, seed: 29);
      await social.mount(
        t,
        DominoTableScreen(
          client: store.client,
          initial: c.table,
          controller: c,
        ),
      );
      await finishRound(t, c);
      final points = Map<String, dynamic>.from(socialMap(c.table['points']));
      final wins = Map<String, dynamic>.from(socialMap(c.table['wins']));
      expect(find.byKey(const Key('domino-next-round')), findsOneWidget);
      expect(find.byKey(const Key('domino-ready')), findsNothing);
      await fixtures.capture(t, 'domino-solo-round-complete');
      await t.tap(find.byKey(const Key('domino-next-round')));
      await t.pump();
      expect(c.table['round'], 2);
      expect(c.table['phase'], 'playing');
      expect(c.table['hand'], hasLength(7));
      expect(c.table['points'], points);
      expect(c.table['wins'], wins);
      expect(store.calls, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      store.dispose();
    },
  );

  for (final config in [
    (320.0, 640.0, 1.0),
    (390.0, 844.0, 1.0),
    (360.0, 640.0, 2.0),
    (1200.0, 850.0, 1.0),
    (844.0, 390.0, 1.0),
  ]) {
    testWidgets(
      'solo table fits ${config.$1}×${config.$2} at text scale ${config.$3}',
      (t) async {
        final store = domino.Store(), c = controller(store);
        await social.mount(
          t,
          DominoTableScreen(
            client: store.client,
            initial: c.table,
            controller: c,
          ),
          width: config.$1,
          height: config.$2,
          scale: config.$3,
        );
        await waitForHuman(t, c);
        expect(
          find.byKey(const Key('domino-board')).hitTestable(),
          findsOneWidget,
          reason: 'The active board must be visible before scrolling.',
        );
        await fixtures.capture(
          t,
          'domino-solo-${config.$1.toInt()}-${config.$3.toInt()}x',
        );
        await reveal(t, find.textContaining('Left end:'));
        await reveal(t, find.textContaining('Right end:'));
        await reveal(t, find.byKey(const Key('domino-hint')));
        await t.tap(find.byKey(const Key('domino-hint')));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('domino-hint-text')), findsOneWidget);
        expect(find.byKey(const Key('domino-join-video')), findsNothing);
        await reveal(t, find.byKey(const Key('domino-left')));
        await reveal(t, find.byKey(const Key('domino-right')));
        await fixtures.capture(
          t,
          'domino-solo-${config.$1.toInt()}-${config.$3.toInt()}x-hand',
        );
        await t.pumpWidget(const SizedBox());
        await t.pump();
        store.dispose();
      },
    );
  }

  for (final config in [(320.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'solo setup fits width ${config.$1} at text scale ${config.$2}',
      (t) async {
        final store = domino.Store();
        await social.mount(
          t,
          DominoLobby(client: store.client, profile: social.me),
          width: config.$1,
          height: 640,
          scale: config.$2,
        );
        expect(t.takeException(), isNull);
        await fixtures.capture(
          t,
          'domino-lobby-${config.$1.toInt()}-${config.$2.toInt()}x',
        );
        await t.ensureVisible(find.byKey(const Key('domino-play-computer')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('domino-play-computer')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('domino-start-solo')), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('domino-difficulty-hard')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('domino-difficulty-hard')));
        await t.pump();
        await fixtures.capture(
          t,
          'domino-difficulty-${config.$1.toInt()}-${config.$2.toInt()}x',
        );
        await t.pumpWidget(const SizedBox());
        await t.pump();
        store.dispose();
      },
    );
  }

  testWidgets('background pauses the computer and resume schedules one reply', (
    t,
  ) async {
    final store = domino.Store(), c = controller(store);
    await c.initialize();
    if (c.myTurn) await humanMove(c);
    expect(c.table['turn'], 'computer');
    expect(c.thinking, isTrue);
    c.background();
    final revision = c.table['revision'];
    await t.pump(const Duration(seconds: 20));
    expect(c.table['revision'], revision);
    expect(c.myTurn, isFalse);
    c.resume();
    await t.pump(thinkingDelay + const Duration(milliseconds: 1));
    expect(c.table['revision'], (revision as int) + 1);
    expect(c.myTurn, isTrue);
    expect(store.calls, isEmpty);
    c.dispose();
    await t.pump(const Duration(seconds: 20));
    expect(t.takeException(), isNull);
    store.dispose();
  });

  testWidgets(
    'signing out clears the practice game and cancels a pending computer move',
    (t) async {
      final store = domino.Store(), c = controller(store);
      await c.initialize();
      if (c.myTurn) await humanMove(c);
      expect(c.thinking, isTrue);
      store.token = 'Bearer different-account';
      store.session.value++;
      expect(c.available, isFalse);
      expect(c.table, isEmpty);
      await t.pump(const Duration(seconds: 20));
      expect(c.table, isEmpty);
      expect(c.thinking, isFalse);
      expect(store.calls, isEmpty);
      c.dispose();
      expect(t.takeException(), isNull);
      store.dispose();
    },
  );

  testWidgets(
    'leaving cancels the pending computer move without an HTTP request',
    (t) async {
      final store = domino.Store(), c = controller(store);
      await c.initialize();
      if (c.myTurn) await humanMove(c);
      expect(c.thinking, isTrue);
      await c.leave();
      final afterLeave = Map<String, dynamic>.from(c.table);
      await t.pump(const Duration(seconds: 20));
      expect(c.table, afterLeave);
      expect(c.thinking, isFalse);
      expect(store.calls, isEmpty);
      c.dispose();
      expect(t.takeException(), isNull);
      store.dispose();
    },
  );

  testWidgets(
    'disposing during computer thinking stops delayed notifications',
    (t) async {
      final store = domino.Store(), c = controller(store);
      await c.initialize();
      if (c.myTurn) await humanMove(c);
      expect(c.thinking, isTrue);
      var notifications = 0;
      c.addListener(() => notifications++);
      c.dispose();
      final count = notifications;
      await t.pump(const Duration(seconds: 20));
      expect(notifications, count);
      expect(c.closed, isTrue);
      expect(c.table, isEmpty);
      expect(store.calls, isEmpty);
      expect(t.takeException(), isNull);
      store.dispose();
    },
  );
}

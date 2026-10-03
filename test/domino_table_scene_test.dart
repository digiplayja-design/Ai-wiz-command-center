import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/social/domino/domino_controller.dart';
import 'package:ai_wiz_command_center/social/domino/domino_screen.dart';
import 'package:ai_wiz_command_center/social/domino/domino_table_scene.dart';
import 'package:ai_wiz_command_center/social/domino/domino_tiles.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';

import 'agent_studio_test.dart' as fixtures;
import 'domino_test.dart' as domino;
import 'social_test.dart' as social;

const positions = ['bottom', 'right', 'top', 'left'];
const playerNames = ['Alex', 'Jordan', 'Sam', 'Morgan'];

List<SocialMap> players() => List.generate(
  4,
  (seat) => {
    'id': 'player-$seat',
    'name': playerNames[seat],
    'seat': seat,
    'state': 'joined',
    'count': 7 - seat,
  },
);

/// An Euler circuit uses the complete double-six set exactly once while
/// keeping neighbouring pips joined, including every double.
List<SocialMap> completeChain() {
  final edges = <(int, int)>[
    for (var a = 0; a <= 6; a++)
      for (var b = a; b <= 6; b++) (a, b),
  ];
  final used = <int>{}, stack = [6], circuit = <int>[];
  while (stack.isNotEmpty) {
    final value = stack.last;
    var next = -1;
    for (var i = 0; i < edges.length; i++) {
      if (!used.contains(i) && (edges[i].$1 == value || edges[i].$2 == value)) {
        next = i;
        break;
      }
    }
    if (next == -1) {
      circuit.add(stack.removeLast());
    } else {
      used.add(next);
      final edge = edges[next];
      stack.add(edge.$1 == value ? edge.$2 : edge.$1);
    }
  }
  final path = circuit.reversed.toList();
  return [
    for (var i = 0; i < path.length - 1; i++)
      {
        'id':
            '${path[i] < path[i + 1] ? path[i] : path[i + 1]}-'
            '${path[i] > path[i + 1] ? path[i] : path[i + 1]}',
        'a': path[i],
        'b': path[i + 1],
        'by': 'player-${i % 4}',
      },
  ];
}

Finder seat(String position) => find.byKey(Key('domino-seat-$position'));
Finder seatText(String position, String value) =>
    find.descendant(of: seat(position), matching: find.text(value));

Future<void> mountScene(
  WidgetTester tester, {
  List<SocialMap>? tablePlayers,
  List<SocialMap>? tiles,
  String me = 'player-0',
  String? turn,
  int capacity = 4,
  bool playing = false,
  double width = 760,
  double height = 900,
  double scale = 1,
}) => fixtures.mount(
  tester,
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: DominoTableScene(
        tiles: tiles ?? [],
        players: tablePlayers ?? players(),
        me: me,
        turn: turn,
        capacity: capacity,
        playing: playing,
      ),
    ),
  ),
  width: width,
  height: height,
  scale: scale,
);

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

  for (var localSeat = 0; localSeat < 4; localSeat++) {
    testWidgets(
      'seat $localSeat sees their name at the bottom and the seat order around the table',
      (tester) async {
        // API array order must not move a player out of their assigned seat.
        final tablePlayers = players().reversed.toList();
        await mountScene(
          tester,
          tablePlayers: tablePlayers,
          me: 'player-$localSeat',
        );
        for (var index = 0; index < 4; index++) {
          final position = positions[index];
          expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
          expect(
            seatText(position, playerNames[(localSeat + index) % 4]),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: seat('bottom'),
            matching: find.textContaining('You'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all four chairs are physically arranged around the board', (
    tester,
  ) async {
    await mountScene(tester);
    final board = tester.getCenter(find.byType(DominoBoard));
    final chairCenters = {
      for (final position in positions)
        position: tester.getCenter(find.byKey(Key('domino-chair-$position'))),
    };
    expect(chairCenters['bottom']!.dy, greaterThan(board.dy));
    expect(chairCenters['top']!.dy, lessThan(board.dy));
    expect(chairCenters['right']!.dx, greaterThan(board.dx));
    expect(chairCenters['left']!.dx, lessThan(board.dx));
    await fixtures.capture(tester, 'jamaican-domino-four-chairs');
  });

  for (var localSeat = 0; localSeat < 2; localSeat++) {
    testWidgets(
      'two-player seat $localSeat keeps the opponent opposite and side chairs unused',
      (tester) async {
        await mountScene(
          tester,
          tablePlayers: players().take(2).toList(),
          me: 'player-$localSeat',
          capacity: 2,
        );
        expect(seatText('bottom', playerNames[localSeat]), findsOneWidget);
        expect(seatText('top', playerNames[1 - localSeat]), findsOneWidget);
        expect(seatText('right', 'Not in use'), findsOneWidget);
        expect(seatText('left', 'Not in use'), findsOneWidget);
        expect(find.text('Open seat'), findsNothing);
        for (final position in positions) {
          expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (localSeat == 0) {
          await fixtures.capture(tester, 'jamaican-domino-two-players');
        }
      },
    );
  }

  testWidgets('invitations and departed players leave visible open chairs', (
    tester,
  ) async {
    final tablePlayers = players();
    tablePlayers[1]['state'] = 'invited';
    tablePlayers[2]['state'] = 'left';
    tablePlayers.removeLast();
    await mountScene(tester, tablePlayers: tablePlayers);
    expect(seatText('bottom', 'Alex'), findsOneWidget);
    for (final position in ['right', 'top', 'left']) {
      expect(seatText(position, 'Open seat'), findsOneWidget);
      expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
    }
    expect(find.text('Jordan'), findsNothing);
    expect(find.text('Sam'), findsNothing);
    expect(find.text('Morgan'), findsNothing);
    expect(tester.takeException(), isNull);
    await fixtures.capture(tester, 'jamaican-domino-open-chairs');
  });

  testWidgets('an empty table still displays four available chairs', (
    tester,
  ) async {
    await mountScene(tester, tablePlayers: []);
    for (final position in positions) {
      expect(seatText(position, 'Open seat'), findsOneWidget);
      expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
    }
    expect(find.textContaining('You'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible seats identify the player, partner and public count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final tablePlayers = players();
      // Even if an unexpected private field appears in a payload, a seat may
      // disclose only its public name/count, never the opponent's hand contents.
      tablePlayers[1]['hand'] = ['private-hand-must-not-be-displayed'];
      await mountScene(tester, tablePlayers: tablePlayers);
      expect(
        find.bySemanticsLabel('bottom chair, seat 1, Alex, you, 7 tiles'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('top chair, seat 3, Sam, your partner, 5 tiles'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('right chair, seat 2, Jordan, 6 tiles'),
        findsOneWidget,
      );
      expect(find.textContaining('private-hand'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('private-hand')), findsNothing);
      for (final position in positions) {
        expect(
          find.descendant(
            of: seat(position),
            matching: find.byType(DominoTile),
          ),
          findsNothing,
        );
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'only the active player is announced as taking the current turn',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await mountScene(tester, playing: true, turn: 'player-1');
        expect(
          find.bySemanticsLabel(
            'right chair, seat 2, Jordan, 6 tiles, current turn',
          ),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('current turn')), findsOneWidget);
        expect(
          find.descendant(
            of: seat('right'),
            matching: find.textContaining('Playing'),
          ),
          findsOneWidget,
        );

        await mountScene(tester, playing: false, turn: 'player-1');
        expect(find.bySemanticsLabel(RegExp('current turn')), findsNothing);
        expect(find.textContaining('Playing'), findsNothing);
      } finally {
        handle.dispose();
      }
    },
  );

  for (final config in [
    (320.0, 780.0, 1.0),
    (320.0, 900.0, 2.0),
    (760.0, 900.0, 1.0),
    (1200.0, 900.0, 1.0),
  ]) {
    testWidgets(
      'all 28 tiles fit the table at ${config.$1} wide and ${config.$3} text scale',
      (tester) async {
        final chain = completeChain();
        expect(chain, hasLength(28));
        expect(chain.map((tile) => tile['id']).toSet(), hasLength(28));
        await mountScene(
          tester,
          tiles: chain,
          playing: true,
          turn: 'player-1',
          width: config.$1,
          height: config.$2,
          scale: config.$3,
        );
        expect(
          tester.widget<DominoBoard>(find.byType(DominoBoard)).tiles,
          hasLength(28),
        );
        for (final position in positions) {
          expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await fixtures.capture(
          tester,
          'jamaican-domino-full-set-${config.$1.toInt()}-${config.$3.toInt()}x',
        );
      },
    );
  }

  testWidgets(
    'the real game screen uses the four-seat table with a full chain',
    (tester) async {
      final table = domino.room();
      table['board'] = completeChain();
      final store = domino.Store(initial: table);
      final controller = DominoController(
        client: store.client,
        initial: table,
        polling: false,
      );
      await social.mount(
        tester,
        DominoTableScreen(
          client: store.client,
          initial: table,
          controller: controller,
        ),
        width: 320,
        height: 900,
        scale: 2,
      );
      expect(find.byType(DominoTableScene), findsOneWidget);
      for (final position in positions) {
        expect(find.byKey(Key('domino-chair-$position')), findsOneWidget);
      }
      await tester.ensureVisible(find.byType(DominoBoard));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await fixtures.capture(tester, 'jamaican-domino-full-screen-320-2x');
      await tester.scrollUntilVisible(
        find.byKey(const Key('domino-left')),
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('domino-game-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('domino-left')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('domino-right')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('domino-right')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      store.dispose();
    },
  );
}

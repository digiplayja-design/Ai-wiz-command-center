import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/social/domino/domino_solo.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';

int pips(String tile) => tile.split('-').map(int.parse).reduce((a, b) => a + b);

void playRound(DominoSoloGame game, Random choices) {
  for (var step = 0; game.phase == 'playing' && step < 60; step++) {
    final actor = game.turn!;
    final legal = game.legalFor(actor);
    final move = actor == DominoSoloGame.computer
        ? game.computerMove()
        : legal.isEmpty
        ? null
        : legal[choices.nextInt(legal.length)];
    game.apply(
      actor,
      action: move == null ? 'pass' : 'play',
      tile: move?.tile,
      side: move?.side,
    );
  }
  expect(game.phase, 'finished');
}

void main() {
  test('double-six deck has all 28 distinct canonical tiles', () {
    final deck = dominoSoloDeck();
    expect(deck.length, 28);
    expect(deck.toSet().length, 28);
    for (final tile in deck) {
      final ends = tile.split('-').map(int.parse).toList();
      expect(ends[0], inInclusiveRange(0, 6));
      expect(ends[1], inInclusiveRange(ends[0], 6));
    }
  });

  test(
    'seven each, highest dealt double or high tile opens, and no hidden hand leaks',
    () {
      var noDoubleDeals = 0;
      for (var seed = 0; seed < 1000; seed++) {
        final deck = dominoSoloDeck()..shuffle(Random(seed));
        final dealt = deck.take(14).toList();
        final doubles = dealt
            .where((tile) => tile.split('-').toSet().length == 1)
            .toList();
        if (doubles.isEmpty) noDoubleDeals++;
        final candidates = doubles.isEmpty ? dealt : doubles;
        candidates.sort((a, b) {
          final total = pips(b).compareTo(pips(a));
          return total != 0
              ? total
              : int.parse(
                  b.split('-')[1],
                ).compareTo(int.parse(a.split('-')[1]));
        });
        final game = DominoSoloGame(random: Random(seed))..startRound();
        final view = game.view();
        expect(view['hand'], deck.take(7).toList());
        expect(socialItems(view['players']).map((p) => p['count']), [7, 7]);
        expect(game.opener, candidates.first);
        expect(
          game.turn,
          deck.take(7).contains(game.opener) ? 'you' : 'computer',
        );
        expect(game.legalFor(game.turn!).map((m) => m.toMap()), [
          {'tile': game.opener, 'side': 'right'},
        ]);
        expect(view.containsKey('hands'), isFalse);
        expect(view.containsKey('state'), isFalse);
        expect(view.containsKey('boneyard'), isFalse);
        expect(
          socialItems(view['players']).every((p) => !p.containsKey('hand')),
          isTrue,
        );
      }
      expect(noDoubleDeals, greaterThan(0));
    },
  );

  test(
    'turn, opener, ownership, side and forced pass rules reject without mutation',
    () {
      final game = DominoSoloGame(random: Random(9))..startRound();
      final actor = game.turn!, other = actor == 'you' ? 'computer' : 'you';
      final initial = game.view();
      for (final attempt in <void Function()>[
        () => game.startRound(),
        () =>
            game.apply(other, action: 'play', tile: game.opener, side: 'right'),
        () => game.apply(actor, action: 'pass'),
        () =>
            game.apply(actor, action: 'play', tile: game.opener, side: 'left'),
        () => game.apply(actor, action: 'play', tile: 'missing', side: 'right'),
        () => game.apply(actor, action: 'draw'),
      ]) {
        expect(attempt, throwsA(isA<DominoRuleException>()));
        expect(game.view(), initial);
      }
      game.apply(actor, action: 'play', tile: game.opener, side: 'right');
      final after = game.view();
      expect(
        () =>
            game.apply(actor, action: 'play', tile: game.opener, side: 'right'),
        throwsA(isA<DominoRuleException>()),
      );
      expect(game.view(), after);
      expect(game.turn, other);
    },
  );

  test(
    '300 full rounds conserve every dealt tile, orient ends, pass and score correctly',
    () {
      final reasons = <String>{};
      var ties = 0, passCount = 0;
      for (final difficulty in DominoDifficulty.values) {
        for (var seed = 0; seed < 100; seed++) {
          final game = DominoSoloGame(
            random: Random(seed),
            difficulty: difficulty,
          )..startRound();
          final deck = dominoSoloDeck()..shuffle(Random(seed));
          final remaining = {
            'you': deck.take(7).toList(),
            'computer': deck.skip(7).take(7).toList(),
          };
          final choices = Random(seed + 99);
          var consecutivePasses = 0;
          for (var step = 0; game.phase == 'playing' && step < 60; step++) {
            final actor = game.turn!;
            final legal = game.legalFor(actor);
            final move = actor == 'computer'
                ? game.computerMove()
                : legal.isEmpty
                ? null
                : legal[choices.nextInt(legal.length)];
            if (move == null) {
              expect(legal, isEmpty);
              passCount++;
              consecutivePasses++;
            } else {
              expect(
                legal.any((m) => m.tile == move.tile && m.side == move.side),
                isTrue,
              );
              expect(remaining[actor]!.remove(move.tile), isTrue);
              consecutivePasses = 0;
            }
            game.apply(
              actor,
              action: move == null ? 'pass' : 'play',
              tile: move?.tile,
              side: move?.side,
            );
            final view = game.view(), board = socialItems(view['board']);
            final all = [
              ...remaining.values.expand((hand) => hand),
              ...board.map((tile) => tile['id']),
            ];
            expect(all.length, 14);
            expect(all.toSet(), deck.take(14).toSet());
            expect(view['hand'], remaining['you']);
            expect(socialItems(view['players']).map((p) => p['count']), [
              remaining['you']!.length,
              remaining['computer']!.length,
            ]);
            for (var i = 1; i < board.length; i++) {
              expect(board[i - 1]['b'], board[i]['a']);
            }
            if (consecutivePasses < 2 && remaining[actor]!.isNotEmpty) {
              expect(game.phase, 'playing');
            }
          }
          expect(game.phase, 'finished');
          final view = game.view(), result = socialMap(view['result']);
          final totals = {
            for (final entry in remaining.entries)
              entry.key: entry.value.fold(0, (sum, tile) => sum + pips(tile)),
          };
          expect(result['totals'], totals);
          reasons.add(result['reason']);
          final String? expectedWinner = remaining['you']!.isEmpty
              ? 'you'
              : remaining['computer']!.isEmpty
              ? 'computer'
              : totals['you'] == totals['computer']
              ? null
              : totals['you']! < totals['computer']!
              ? 'you'
              : 'computer';
          expect(result['winner'], expectedWinner);
          final points = expectedWinner == null
              ? 0
              : totals[expectedWinner == 'you' ? 'computer' : 'you'];
          expect(result['points'], points);
          if (expectedWinner == null) {
            ties++;
            expect(socialMap(view['wins']).values, everyElement(0));
            expect(socialMap(view['points']).values, everyElement(0));
          } else {
            expect(socialMap(view['wins'])[expectedWinner], 1);
            expect(socialMap(view['points'])[expectedWinner], points);
          }
          expect(game.turn, isNull);
          expect(game.legalFor('you'), isEmpty);
          expect(game.legalFor('computer'), isEmpty);
          expect(
            () => game.apply('you', action: 'pass'),
            throwsA(isA<DominoRuleException>()),
          );
        }
      }
      expect(reasons, {'out', 'blocked'});
      expect(ties, greaterThan(0));
      expect(passCount, greaterThan(0));
    },
  );

  test(
    'next rounds keep session points and reset board, passes and history',
    () {
      final game = DominoSoloGame(random: Random(23));
      final expectedWins = {'you': 0, 'computer': 0};
      final expectedPoints = {'you': 0, 'computer': 0};
      for (var round = 1; round <= 12; round++) {
        game.startRound();
        final start = game.view();
        expect(start['round'], round);
        expect(start['board'], isEmpty);
        expect(start['hand'], hasLength(7));
        expect(start['history'], hasLength(1));
        expect(start['result'], isNull);
        playRound(game, Random(round));
        final result = socialMap(game.view()['result']);
        final winner = result['winner'] as String?;
        if (winner != null) {
          expectedWins[winner] = expectedWins[winner]! + 1;
          expectedPoints[winner] =
              expectedPoints[winner]! + (result['points'] as int);
        }
        expect(game.view()['wins'], expectedWins);
        expect(game.view()['points'], expectedPoints);
      }
    },
  );

  test(
    'view mutations cannot change private state, legal tiles or final totals',
    () {
      final game = DominoSoloGame(random: Random(2))..startRound();
      final expected = game.view(), view = game.view();
      (view['hand'] as List).clear();
      (view['players'] as List).first['count'] = 99;
      (view['legal'] as List).clear();
      (view['wins'] as Map)['you'] = 99;
      (view['history'] as List).clear();
      expect(game.view(), expected);
      playRound(game, Random(18));
      final finished = game.view(), modified = game.view();
      (modified['board'] as List).first['a'] = 99;
      modified['result']['totals']['you'] = 99;
      expect(game.view(), finished);
    },
  );

  test(
    'computer choices use legal moves and public passes, without any hidden-hand input',
    () {
      final hand = ['0-6', '1-6', '6-6'];
      final board = <SocialMap>[
        {'a': 6, 'b': 6},
      ];
      const legal = [
        DominoMove('0-6', 'left'),
        DominoMove('1-6', 'right'),
        DominoMove('6-6', 'right'),
      ];
      for (final difficulty in DominoDifficulty.values) {
        final selected = <String>{};
        for (var seed = 0; seed < 20; seed++) {
          final first = chooseDominoMove(
            hand: hand,
            board: board,
            legal: legal,
            difficulty: difficulty,
            random: Random(seed),
          );
          final second = chooseDominoMove(
            hand: hand,
            board: board,
            legal: legal,
            difficulty: difficulty,
            random: Random(seed),
          );
          expect(first!.toMap(), second!.toMap());
          expect(legal.contains(first), isTrue);
          selected.add(first.tile);
        }
        if (difficulty == DominoDifficulty.easy) {
          expect(selected.length, greaterThan(1));
        }
        if (difficulty == DominoDifficulty.standard) expect(selected, {'6-6'});
        expect(
          chooseDominoMove(
            hand: hand,
            board: board,
            legal: [],
            difficulty: difficulty,
            random: Random(0),
          ),
          isNull,
        );
      }
      expect(hand, ['0-6', '1-6', '6-6']);
      expect(board, [
        {'a': 6, 'b': 6},
      ]);
      final withPass = chooseDominoMove(
        hand: hand,
        board: board,
        legal: legal,
        difficulty: DominoDifficulty.hard,
        random: Random(0),
        opponentPassedPips: {0, 6},
      );
      expect(withPass!.tile, anyOf('0-6', '6-6'));
    },
  );

  test(
    'hard mode values future playable tiles and learns only from public passes',
    () {
      final board = <SocialMap>[
        {'a': 6, 'b': 0},
      ];
      const legal = [DominoMove('6-6', 'left'), DominoMove('4-6', 'left')];
      final hand = ['6-6', '4-6', '4-4', '3-4', '2-4', '1-4'];
      DominoMove? choose(DominoDifficulty difficulty) => chooseDominoMove(
        hand: hand,
        board: board,
        legal: legal,
        difficulty: difficulty,
        random: Random(1),
      );
      expect(choose(DominoDifficulty.standard)!.tile, '6-6');
      expect(choose(DominoDifficulty.hard)!.tile, '4-6');
      DominoMove? withPass(Set<int> passed) => chooseDominoMove(
        hand: ['0-6', '1-6'],
        board: [
          {'a': 6, 'b': 6},
        ],
        legal: const [DominoMove('0-6', 'left'), DominoMove('1-6', 'right')],
        difficulty: DominoDifficulty.hard,
        random: Random(1),
        opponentPassedPips: passed,
      );
      expect(withPass({})!.tile, '1-6');
      expect(withPass({0})!.tile, '0-6');
    },
  );
}

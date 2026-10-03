import 'dart:async';
import 'dart:math';

import '../social_client.dart';
import 'domino_controller.dart';

enum DominoDifficulty {
  easy,
  standard,
  hard;

  String get label => switch (this) {
    easy => 'Easy',
    standard => 'Standard',
    hard => 'Hard',
  };

  String get description => switch (this) {
    easy => 'Relaxed, with varied legal moves.',
    standard => 'Balances useful tiles and remaining pips.',
    hard => 'Plans around open ends and visible passes.',
  };
}

class DominoRuleException implements Exception {
  const DominoRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DominoMove {
  const DominoMove(this.tile, this.side);
  final String tile, side;
  SocialMap toMap() => {'tile': tile, 'side': side};
}

List<int> _pips(String tile) => tile.split('-').map(int.parse).toList();
int _total(String tile) => _pips(tile).reduce((a, b) => a + b);

List<String> dominoSoloDeck() => [
  for (var a = 0; a <= 6; a++)
    for (var b = a; b <= 6; b++) '$a-$b',
];

/// This decision boundary deliberately accepts only the current player's hand
/// and public facts. The computer never receives the human's hand or boneyard.
DominoMove? chooseDominoMove({
  required List<String> hand,
  required List<SocialMap> board,
  required List<DominoMove> legal,
  required DominoDifficulty difficulty,
  required Random random,
  Set<int> opponentPassedPips = const {},
}) {
  if (legal.isEmpty) return null;
  if (difficulty == DominoDifficulty.easy) {
    return legal[random.nextInt(legal.length)];
  }
  double score(DominoMove move) {
    final pips = _pips(move.tile);
    var value = _total(move.tile).toDouble();
    if (pips[0] == pips[1]) value += 1.5;
    if (difficulty == DominoDifficulty.standard || board.isEmpty) {
      return value;
    }
    final oldLeft = (board.first['a'] as num).toInt();
    final oldRight = (board.last['b'] as num).toInt();
    final matching = move.side == 'left' ? oldLeft : oldRight;
    final exposed = pips[0] == matching ? pips[1] : pips[0];
    final left = move.side == 'left' ? exposed : oldLeft;
    final right = move.side == 'right' ? exposed : oldRight;
    final remaining = hand.where((tile) => tile != move.tile).toList();
    final mobility = remaining.where((tile) {
      final ends = _pips(tile);
      return ends.contains(left) || ends.contains(right);
    }).length;
    value += mobility * 2.25;
    if (remaining.isNotEmpty && mobility == 0) value -= 5;
    if (opponentPassedPips.contains(left)) value += 3;
    if (opponentPassedPips.contains(right)) value += 3;
    if (opponentPassedPips.contains(left) &&
        opponentPassedPips.contains(right)) {
      value += 6;
    }
    return value;
  }

  var best = double.negativeInfinity;
  final candidates = <DominoMove>[];
  for (final move in legal) {
    final value = score(move);
    if (value > best) {
      best = value;
      candidates
        ..clear()
        ..add(move);
    } else if (value == best) {
      candidates.add(move);
    }
  }
  return candidates[random.nextInt(candidates.length)];
}

/// Local two-player block dominoes, using the multiplayer table's rules and
/// view format. Scores last for this practice session only.
class DominoSoloGame {
  DominoSoloGame({
    this.playerName = 'You',
    this.difficulty = DominoDifficulty.standard,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const human = 'you', computer = 'computer';
  final String playerName;
  final DominoDifficulty difficulty;
  final Random _random;
  final _hands = <String, List<String>>{human: [], computer: []};
  final _board = <SocialMap>[];
  final _passedPips = <String, Set<int>>{human: {}, computer: {}};
  final _wins = <String, int>{human: 0, computer: 0};
  final _points = <String, int>{human: 0, computer: 0};
  final _history = <String>[];
  String phase = 'waiting';
  String? turn, opener;
  String last = 'Your computer opponent is ready.';
  int round = 0, revision = 0, _passes = 0;
  SocialMap? _result;

  String _name(String actor) => actor == human ? playerName : 'Computer';

  void startRound() {
    if (phase == 'playing') {
      throw const DominoRuleException(
        'Finish this round before dealing again.',
      );
    }
    final deck = dominoSoloDeck()..shuffle(_random);
    _hands[human] = deck.take(7).toList();
    _hands[computer] = deck.skip(7).take(7).toList();
    final dealt = _hands.values.expand((hand) => hand).toList();
    final doubles = dealt.where((tile) {
      final values = _pips(tile);
      return values[0] == values[1];
    }).toList();
    final candidates = doubles.isEmpty ? dealt : doubles;
    candidates.sort((a, b) {
      final total = _total(b).compareTo(_total(a));
      return total != 0 ? total : _pips(b)[1].compareTo(_pips(a)[1]);
    });
    opener = candidates.first;
    turn = _hands[human]!.contains(opener) ? human : computer;
    _board.clear();
    for (final pips in _passedPips.values) {
      pips.clear();
    }
    _history.clear();
    _passes = 0;
    _result = null;
    round++;
    revision++;
    phase = 'playing';
    last =
        '${_name(turn!)} opens with $opener. '
        '${doubles.isEmpty ? 'Highest dealt tile' : 'Highest dealt double'} opens.';
    _history.add(last);
  }

  List<DominoMove> legalFor(String actor) {
    if (phase != 'playing' || turn != actor) return [];
    final hand = _hands[actor] ?? const <String>[];
    if (_board.isEmpty) {
      return [
        for (final tile in hand)
          if (tile == opener) DominoMove(tile, 'right'),
      ];
    }
    final left = _board.first['a'], right = _board.last['b'];
    return [
      for (final tile in hand)
        for (final side in ['left', 'right'])
          if (_pips(tile).contains(side == 'left' ? left : right))
            DominoMove(tile, side),
    ];
  }

  DominoMove? computerMove() => chooseDominoMove(
    hand: List.unmodifiable(_hands[computer]!),
    board: _board
        .map((tile) => Map<String, dynamic>.unmodifiable(tile))
        .toList(),
    legal: legalFor(computer),
    difficulty: difficulty,
    random: _random,
    opponentPassedPips: Set.unmodifiable(_passedPips[human]!),
  );

  void apply(
    String actor, {
    required String action,
    String? tile,
    String? side,
  }) {
    if (phase != 'playing' || turn != actor) {
      throw const DominoRuleException('Wait for your turn.');
    }
    final legal = legalFor(actor);
    if (action == 'pass') {
      if (legal.isNotEmpty) {
        throw const DominoRuleException(
          'Choose a highlighted tile before passing.',
        );
      }
      if (_board.isNotEmpty) {
        _passedPips[actor]!.addAll([
          (_board.first['a'] as num).toInt(),
          (_board.last['b'] as num).toInt(),
        ]);
      }
      _passes++;
      last = '${_name(actor)} passed.';
    } else if (action == 'play') {
      if (!legal.any((move) => move.tile == tile && move.side == side)) {
        throw const DominoRuleException(
          'Choose a highlighted tile and a matching end.',
        );
      }
      var [a, b] = _pips(tile!);
      final left = side == 'left';
      if (_board.isNotEmpty) {
        final end = left ? _board.first['a'] : _board.last['b'];
        if (left ? a == end : b == end) (a, b) = (b, a);
      }
      final piece = {'id': tile, 'a': a, 'b': b, 'by': actor};
      if (left) {
        _board.insert(0, piece);
      } else {
        _board.add(piece);
      }
      _hands[actor]!.remove(tile);
      _passes = 0;
      last = '${_name(actor)} played $tile.';
    } else {
      throw const DominoRuleException('Choose an available domino action.');
    }
    _history.add(last);
    if (_history.length > 8) _history.removeAt(0);
    revision++;
    if (_hands[actor]!.isEmpty || _passes >= 2) {
      _finish(actor);
    } else {
      turn = actor == human ? computer : human;
    }
  }

  void _finish(String actor) {
    final totals = <String, int>{
      for (final entry in _hands.entries)
        entry.key: entry.value.fold(0, (sum, tile) => sum + _total(tile)),
    };
    final out = _hands[actor]!.isEmpty;
    final String? winner = out
        ? actor
        : totals[human] == totals[computer]
        ? null
        : totals[human]! < totals[computer]!
        ? human
        : computer;
    final points = winner == null
        ? 0
        : totals[winner == human ? computer : human]!;
    if (winner != null) {
      _wins[winner] = _wins[winner]! + 1;
      _points[winner] = _points[winner]! + points;
    }
    _result = {
      'winner': winner,
      'points': points,
      'totals': totals,
      'reason': out ? 'out' : 'blocked',
    };
    phase = 'finished';
    turn = null;
  }

  SocialMap view() => {
    'id': 'local-domino-practice',
    'me': human,
    'host': human,
    'name': 'You vs Computer',
    'capacity': 2,
    'revision': revision,
    'phase': phase,
    'round': round,
    'turn': turn,
    'opener': _board.isEmpty ? opener : null,
    'last': last,
    'history': List<String>.of(_history),
    'wins': Map<String, int>.of(_wins),
    'points': Map<String, int>.of(_points),
    'result': _result == null
        ? null
        : {..._result!, 'totals': Map<String, int>.of(_result!['totals'])},
    'board': _board.map((tile) => Map<String, dynamic>.of(tile)).toList(),
    'hand': List<String>.of(_hands[human]!),
    'legal': legalFor(human).map((move) => move.toMap()).toList(),
    'players': [
      for (final actor in [human, computer])
        {
          'id': actor,
          'name': _name(actor),
          'color': actor == human ? 'cyan' : 'violet',
          'seat': actor == human ? 0 : 1,
          'state': 'joined',
          'online': true,
          'ready': true,
          'count': _hands[actor]!.length,
          'camera': false,
          'microphone': false,
        },
    ],
    'signals': <SocialMap>[],
  };
}

class DominoSoloController extends DominoController {
  DominoSoloController({
    required super.client,
    String playerName = 'You',
    this.difficulty = DominoDifficulty.standard,
    Random? random,
    this.thinkDelay = const Duration(milliseconds: 800),
  }) : _game = DominoSoloGame(
         playerName: playerName,
         difficulty: difficulty,
         random: random,
       ),
       super(initial: const {}, polling: false) {
    table = _game!.view();
    client.addListener(_sessionChanged);
  }

  final DominoDifficulty difficulty;
  final Duration thinkDelay;
  DominoSoloGame? _game;
  Timer? _computerTimer;
  bool _thinking = false;
  bool get thinking => _thinking;

  @override
  bool get fresh => available && foreground && _game != null;

  void _notifySolo() {
    if (!closed) notifyListeners();
  }

  void _cancelComputer() {
    _computerTimer?.cancel();
    _computerTimer = null;
    _thinking = false;
  }

  void _sessionChanged() {
    if (!client.available) {
      _cancelComputer();
      _game = null;
      table = {};
      _notifySolo();
    }
  }

  bool get _canPlay => available && foreground && _game != null;

  void _publish() {
    if (!available || _game == null) return;
    table = _game!.view();
    updated = DateTime.now();
    _notifySolo();
  }

  void _scheduleComputer() {
    if (!_canPlay ||
        _computerTimer != null ||
        _game!.phase != 'playing' ||
        _game!.turn != DominoSoloGame.computer) {
      return;
    }
    _thinking = true;
    _notifySolo();
    _computerTimer = Timer(thinkDelay, () {
      _computerTimer = null;
      _thinking = false;
      if (!_canPlay) return;
      final game = _game!;
      if (game.turn != DominoSoloGame.computer || game.phase != 'playing') {
        _notifySolo();
        return;
      }
      final move = game.computerMove();
      game.apply(
        DominoSoloGame.computer,
        action: move == null ? 'pass' : 'play',
        tile: move?.tile,
        side: move?.side,
      );
      _publish();
    });
  }

  @override
  Future<void> initialize() async {
    if (!_canPlay) return;
    if (_game!.phase == 'waiting') _game!.startRound();
    _publish();
    _scheduleComputer();
  }

  @override
  Future<void> sync() async {
    if (!_canPlay) return;
    _publish();
    _scheduleComputer();
  }

  @override
  Future<void> move(
    String action, {
    String? tile,
    String? side,
    bool? ready,
  }) async {
    if (!_canPlay || thinking) return;
    error = null;
    try {
      if (action == 'start') {
        _game!.startRound();
      } else if (action != 'ready') {
        _game!.apply(
          DominoSoloGame.human,
          action: action,
          tile: tile,
          side: side,
        );
      }
      _publish();
      _scheduleComputer();
    } on DominoRuleException catch (e) {
      error = e.message;
      _notifySolo();
    }
  }

  @override
  void background() {
    foreground = false;
    _cancelComputer();
    _notifySolo();
  }

  @override
  void resume() {
    if (!available || _game == null) return;
    foreground = true;
    _publish();
    _scheduleComputer();
  }

  // Practice never creates a server table or captures media, even if a caller
  // accidentally invokes controls shared with the multiplayer screen.
  @override
  Future<void> startVideo() async {}
  @override
  Future<void> stopVideo() async {}
  @override
  Future<void> reconnectVideo() async {}
  @override
  Future<void> mediaControl(String kind) async {}

  @override
  Future<void> leave() async {
    _cancelComputer();
    _game = null;
    foreground = false;
    table = {};
    _notifySolo();
  }

  @override
  void dispose() {
    _cancelComputer();
    _game = null;
    client.removeListener(_sessionChanged);
    super.dispose();
  }
}

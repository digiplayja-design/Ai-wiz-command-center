import 'dart:math' as math;
import 'dart:ui';

/// Values are already ordered from the game's left end to its right end.
class DominoLayoutValue {
  const DominoLayoutValue(this.a, this.b);
  final int a, b;
  bool get isDouble => a == b;
}

class DominoPlacement {
  const DominoPlacement({
    required this.value,
    required this.rect,
    required this.flow,
  });
  final DominoLayoutValue value;
  final Rect rect;

  /// Direction in which the logical a-to-b chain travels through this tile.
  final Offset flow;

  int get quarterTurns => value.isDouble
      ? (flow.dy == 0 ? 1 : 0)
      : flow.dx > 0
      ? 0
      : flow.dy > 0
      ? 1
      : 2;
  Offset get entry => rect.center - flow * _extent(rect, flow);
  Offset get exit => rect.center + flow * _extent(rect, flow);
}

class DominoJoin {
  const DominoJoin(this.point, this.fromIndex, this.toIndex);
  final Offset point;
  final int fromIndex, toIndex;
}

class DominoChainLayout {
  const DominoChainLayout(this.tiles, this.joins, this.bounds, this.unit);
  final List<DominoPlacement> tiles;
  final List<DominoJoin> joins;
  final Rect bounds;

  /// The fitted width of one half of a domino.
  final double unit;
}

double _extent(Rect rect, Offset direction) =>
    direction.dx == 0 ? rect.height / 2 : rect.width / 2;

Rect _tileRect(DominoLayoutValue tile, Offset center, Offset flow) {
  final along = tile.isDouble ? 1.0 : 2.0;
  final across = tile.isDouble ? 2.0 : 1.0;
  return Rect.fromCenter(
    center: center,
    width: flow.dx == 0 ? across : along,
    height: flow.dx == 0 ? along : across,
  );
}

/// Joins rectangles at the matching half. At a bend the new tile meets the
/// side of the preceding b half, as it would on a physical domino table.
(DominoPlacement, Offset) _nextTile(
  DominoPlacement previous,
  DominoLayoutValue value,
  Offset flow,
) {
  final turning = flow != previous.flow;
  final matchingHalf =
      previous.rect.center +
      (turning && !previous.value.isDouble ? previous.flow * .5 : Offset.zero);
  final newExtent = value.isDouble ? .5 : 1.0;
  final contact = matchingHalf + flow * _extent(previous.rect, flow);
  return (
    DominoPlacement(
      value: value,
      rect: _tileRect(value, contact + flow * newExtent, flow),
      flow: flow,
    ),
    contact,
  );
}

bool _overlaps(DominoPlacement tile, List<DominoPlacement> placed) =>
    placed.any((other) {
      final intersection = tile.rect.intersect(other.rect);
      return intersection.width > .00001 && intersection.height > .00001;
    });

DominoChainLayout _snake(List<DominoLayoutValue> values, double rowWidth) {
  const east = Offset(1, 0), south = Offset(0, 1);
  var horizontal = east;
  var rowY = 0.0;
  final first = values.first;
  final firstCenter = Offset(-rowWidth / 2 + (first.isDouble ? .5 : 1), 0);
  final placed = <DominoPlacement>[
    DominoPlacement(
      value: first,
      rect: _tileRect(first, firstCenter, east),
      flow: east,
    ),
  ];
  final joins = <DominoJoin>[];
  var bounds = placed.first.rect;
  for (var i = 1; i < values.length; i++) {
    final previous = placed.last;
    var direction = previous.flow;
    var candidate = _nextTile(previous, values[i], direction);
    if (direction.dy == 0) {
      final atEdge = direction.dx > 0
          ? candidate.$1.rect.right > rowWidth / 2
          : candidate.$1.rect.left < -rowWidth / 2;
      if (atEdge) {
        final bend = _nextTile(previous, values[i], south);
        if (!_overlaps(bend.$1, placed)) {
          candidate = bend;
          horizontal = -horizontal;
        }
      }
    } else if (previous.rect.center.dy - rowY >= 3.5) {
      // Enough separation for crosswise doubles on both neighboring rows.
      final bend = _nextTile(previous, values[i], horizontal);
      if (!_overlaps(bend.$1, placed)) {
        candidate = bend;
        rowY = bend.$1.rect.center.dy;
      }
    }
    placed.add(candidate.$1);
    joins.add(DominoJoin(candidate.$2, i - 1, i));
    bounds = bounds.expandToInclude(candidate.$1.rect);
  }
  return DominoChainLayout(placed, joins, bounds, 1);
}

/// Fits a real, unbranched domino chain to the table. Every adjacent pair
/// touches, doubles sit crosswise, and rows never overlap. Trying a few row
/// widths makes the same layout work on phones and wide tables.
DominoChainLayout layoutDominoChain(
  List<DominoLayoutValue> values,
  Size viewport, {
  double padding = 22,
  double maxUnit = 30,
}) {
  if (values.isEmpty) {
    return const DominoChainLayout([], [], Rect.zero, 0);
  }
  final availableWidth = math.max(1.0, viewport.width - padding * 2);
  final availableHeight = math.max(1.0, viewport.height - padding * 2);
  DominoChainLayout? best;
  var bestScale = 0.0;
  for (var width = 6.0; width <= 60; width += 2) {
    final candidate = _snake(values, width);
    final scale = math.min(
      availableWidth / candidate.bounds.width,
      availableHeight / candidate.bounds.height,
    );
    if (scale > bestScale) {
      best = candidate;
      bestScale = scale;
    }
  }
  final raw = best!;
  final unit = math.min(maxUnit, bestScale);
  final translation = viewport.center(Offset.zero) - raw.bounds.center * unit;
  Rect fit(Rect rect) => Rect.fromLTRB(
    rect.left * unit + translation.dx,
    rect.top * unit + translation.dy,
    rect.right * unit + translation.dx,
    rect.bottom * unit + translation.dy,
  );
  return DominoChainLayout(
    raw.tiles
        .map(
          (tile) => DominoPlacement(
            value: tile.value,
            rect: fit(tile.rect),
            flow: tile.flow,
          ),
        )
        .toList(growable: false),
    raw.joins
        .map(
          (join) => DominoJoin(
            join.point * unit + translation,
            join.fromIndex,
            join.toIndex,
          ),
        )
        .toList(growable: false),
    fit(raw.bounds),
    unit,
  );
}

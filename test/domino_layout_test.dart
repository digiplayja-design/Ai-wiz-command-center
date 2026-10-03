import 'dart:math' as math;
import 'dart:ui';

import 'package:ai_wiz_command_center/social/domino/domino_layout.dart';
import 'package:flutter_test/flutter_test.dart';

bool boundaryContains(Rect rect, Offset point) =>
    rect.inflate(.00001).contains(point) &&
    ((point.dx - rect.left).abs() < .00001 ||
        (point.dx - rect.right).abs() < .00001 ||
        (point.dy - rect.top).abs() < .00001 ||
        (point.dy - rect.bottom).abs() < .00001);

void checkChain(DominoChainLayout layout, Size size) {
  expect(layout.bounds.left, greaterThanOrEqualTo(21.999));
  expect(layout.bounds.top, greaterThanOrEqualTo(21.999));
  expect(layout.bounds.right, lessThanOrEqualTo(size.width - 21.999));
  expect(layout.bounds.bottom, lessThanOrEqualTo(size.height - 21.999));
  expect(layout.bounds.center.dx, closeTo(size.width / 2, .00001));
  expect(layout.bounds.center.dy, closeTo(size.height / 2, .00001));
  expect(layout.joins.length, layout.tiles.length - 1);
  for (final join in layout.joins) {
    final before = layout.tiles[join.fromIndex];
    final after = layout.tiles[join.toIndex];
    expect(before.value.b, after.value.a);
    expect(boundaryContains(before.rect, join.point), isTrue);
    expect(boundaryContains(after.rect, join.point), isTrue);
    // At a bend the join is on the b half of the preceding tile.
    if (!before.value.isDouble) {
      final offset = join.point - before.rect.center;
      expect(
        offset.dx * before.flow.dx + offset.dy * before.flow.dy,
        greaterThan(0),
      );
    }
    expect(after.entry.dx, closeTo(join.point.dx, .00001));
    expect(after.entry.dy, closeTo(join.point.dy, .00001));
  }
  for (var i = 0; i < layout.tiles.length; i++) {
    final tile = layout.tiles[i];
    final along = tile.flow.dx == 0 ? tile.rect.height : tile.rect.width;
    final across = tile.flow.dx == 0 ? tile.rect.width : tile.rect.height;
    expect(along / across, closeTo(tile.value.isDouble ? .5 : 2, .00001));
    for (var j = i + 1; j < layout.tiles.length; j++) {
      final intersection = tile.rect.intersect(layout.tiles[j].rect);
      expect(
        intersection.width > .00001 && intersection.height > .00001,
        isFalse,
        reason: 'Tiles $i and $j overlap',
      );
    }
  }
}

void main() {
  test('single double is centered, crosswise, and has two distinct ends', () {
    const size = Size(320, 220);
    final layout = layoutDominoChain([const DominoLayoutValue(6, 6)], size);
    checkChain(layout, size);
    final tile = layout.tiles.single;
    expect(tile.rect.height, tile.rect.width * 2);
    expect(tile.entry, Offset(tile.rect.left, tile.rect.center.dy));
    expect(tile.exit, Offset(tile.rect.right, tile.rect.center.dy));
    expect(tile.quarterTurns, 1);
  });

  test('short chain joins normal tiles and crosswise doubles edge to edge', () {
    const size = Size(500, 220);
    final layout = layoutDominoChain([
      const DominoLayoutValue(1, 6),
      const DominoLayoutValue(6, 6),
      const DominoLayoutValue(6, 3),
      const DominoLayoutValue(3, 3),
      const DominoLayoutValue(3, 0),
    ], size);
    checkChain(layout, size);
    expect(
      layout.tiles.every((tile) => tile.flow == const Offset(1, 0)),
      isTrue,
    );
  });

  test(
    '28-tile table uses physical bends with matching halves and no overlaps',
    () {
      const size = Size(400, 220);
      final values = List.generate(
        28,
        (i) => DominoLayoutValue(i % 7, (i + 1) % 7),
      );
      final layout = layoutDominoChain(values, size);
      checkChain(layout, size);
      expect(layout.tiles.any((tile) => tile.flow.dy > 0), isTrue);
      expect(layout.tiles.any((tile) => tile.flow.dx < 0), isTrue);
      expect(layout.unit, greaterThan(10));
    },
  );

  test('synthetic double-only chain also fits without overlaps', () {
    for (final size in [const Size(220, 190), const Size(800, 240)]) {
      final layout = layoutDominoChain(
        List.filled(28, const DominoLayoutValue(6, 6)),
        size,
      );
      checkChain(layout, size);
    }
  });

  test(
    'mixed matching chains fit narrow and wide tables for every hand length',
    () {
      final random = math.Random(126);
      for (final size in [
        const Size(100, 190),
        const Size(196, 190),
        const Size(320, 220),
        const Size(800, 240),
      ]) {
        for (var count = 1; count <= 28; count++) {
          for (var variant = 0; variant < 8; variant++) {
            var end = random.nextInt(7);
            final values = List.generate(count, (_) {
              final start = end;
              if (random.nextBool()) end = random.nextInt(7);
              return DominoLayoutValue(start, end);
            });
            checkChain(layoutDominoChain(values, size), size);
          }
        }
      }
    },
  );

  test('empty table returns no placements', () {
    final layout = layoutDominoChain([], const Size(320, 220));
    expect(layout.tiles, isEmpty);
    expect(layout.joins, isEmpty);
  });
}

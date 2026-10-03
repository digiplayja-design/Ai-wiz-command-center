import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../social_client.dart';
import 'domino_layout.dart';

class DominoTile extends StatelessWidget {
  const DominoTile({
    super.key,
    required this.a,
    required this.b,
    this.selected = false,
    this.playable = false,
    this.onTap,
    this.width = 44,
    this.horizontal = false,
  });
  final int a, b;
  final bool selected, playable, horizontal;
  final double width;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    label: 'Domino $a and $b${playable ? ', playable' : ''}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: horizontal ? width * 1.85 : width,
          height: horizontal ? width : width * 1.85,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFD988)
                  : playable
                  ? const Color(0xFF65E7C6)
                  : const Color(0xFF586777),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .35),
                offset: const Offset(0, 4),
                blurRadius: 6,
              ),
            ],
          ),
          child: CustomPaint(
            painter: DominoPainter(a, b, horizontal: horizontal),
          ),
        ),
      ),
    ),
  );
}

class DominoPainter extends CustomPainter {
  DominoPainter(this.a, this.b, {this.horizontal = false});
  final int a, b;
  final bool horizontal;
  static const patterns = <int, List<Offset>>{
    0: [],
    1: [Offset(.5, .5)],
    2: [Offset(.25, .25), Offset(.75, .75)],
    3: [Offset(.25, .25), Offset(.5, .5), Offset(.75, .75)],
    4: [Offset(.25, .25), Offset(.75, .25), Offset(.25, .75), Offset(.75, .75)],
    5: [
      Offset(.25, .25),
      Offset(.75, .25),
      Offset(.5, .5),
      Offset(.25, .75),
      Offset(.75, .75),
    ],
    6: [
      Offset(.25, .2),
      Offset(.75, .2),
      Offset(.25, .5),
      Offset(.75, .5),
      Offset(.25, .8),
      Offset(.75, .8),
    ],
  };
  @override
  void paint(Canvas c, Size size) {
    final box = Offset.zero & size,
        r = RRect.fromRectAndRadius(box, const Radius.circular(7));
    c.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFE2E9E7), Color(0xFFB8C6C4)],
        ).createShader(box),
    );
    c.drawRRect(
      r.deflate(.7),
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final mid = horizontal
        ? Offset(size.width / 2, 0)
        : Offset(0, size.height / 2);
    c.drawLine(
      mid + (horizontal ? const Offset(0, 5) : const Offset(5, 0)),
      horizontal
          ? Offset(size.width / 2, size.height - 5)
          : Offset(size.width - 5, size.height / 2),
      Paint()
        ..color = const Color(0xFF83938E)
        ..strokeWidth = 1,
    );
    for (var i = 0; i < 2; i++) {
      final rect = horizontal
          ? Rect.fromLTWH(i * size.width / 2, 0, size.width / 2, size.height)
          : Rect.fromLTWH(0, i * size.height / 2, size.width, size.height / 2);
      for (final dot in patterns[i == 0 ? a : b] ?? <Offset>[]) {
        final point = Offset(
          rect.left + dot.dx * rect.width,
          rect.top + dot.dy * rect.height,
        );
        final radius = math.min(rect.width, rect.height) * .079;
        c.drawCircle(
          point + const Offset(0, .6),
          radius + .3,
          Paint()..color = const Color(0x66FFFFFF),
        );
        c.drawCircle(point, radius, Paint()..color = const Color(0xFF183C38));
      }
    }
  }

  @override
  bool shouldRepaint(DominoPainter old) =>
      old.a != a || old.b != b || old.horizontal != horizontal;
}

class DominoBoard extends StatelessWidget {
  const DominoBoard({super.key, required this.tiles});
  final List<SocialMap> tiles;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final height = box.maxWidth < 360 ? 210.0 : 240.0;
      return Semantics(
        label: tiles.isEmpty
            ? 'The domino table is empty.'
            : 'Left open end ${tiles.first['a']}. Right open end ${tiles.last['b']}. Domino chain: ${tiles.map((t) => '${t['a']}-${t['b']}').join(', ')}',
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const RadialGradient(
              center: Alignment.topLeft,
              radius: 1.8,
              colors: [Color(0xFF194D45), Color(0xFF0B282A), Color(0xFF071B23)],
            ),
            border: Border.all(color: const Color(0xFF4F8975), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: tiles.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.rotate(
                          angle: -.18,
                          child: const DominoTile(a: 6, b: 6, width: 37),
                        ),
                        const SizedBox(width: 12),
                        Transform.rotate(
                          angle: .12,
                          child: const DominoTile(a: 3, b: 5, width: 37),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'KORLIX  /  DOMINOES',
                      style: TextStyle(
                        color: Color(0xFF92B8AF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                )
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: SizedBox.expand(
                    child: CustomPaint(painter: _BoardPainter(tiles)),
                  ),
                ),
        ),
      );
    },
  );
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.tiles);
  final List<SocialMap> tiles;

  @override
  void paint(Canvas c, Size size) {
    final layout = layoutDominoChain(
      tiles
          .map(
            (t) => DominoLayoutValue(
              (t['a'] as num).toInt(),
              (t['b'] as num).toInt(),
            ),
          )
          .toList(growable: false),
      size,
    );
    for (var i = 0; i < layout.tiles.length; i++) {
      final tile = layout.tiles[i];
      c.drawRRect(
        RRect.fromRectAndRadius(
          tile.rect.shift(const Offset(0, 2)),
          Radius.circular(layout.unit * .16),
        ),
        Paint()..color = const Color(0x66000000),
      );
      c.save();
      c.translate(tile.rect.center.dx, tile.rect.center.dy);
      c.rotate(tile.quarterTurns * math.pi / 2);
      c.translate(-layout.unit, -layout.unit / 2);
      DominoPainter(
        tile.value.a,
        tile.value.b,
        horizontal: true,
      ).paint(c, Size(layout.unit * 2, layout.unit));
      c.restore();
    }
    if (layout.tiles.isEmpty) return;
    void endpoint(String label, Offset point, Offset outward, Color color) {
      final at = point + outward * 11;
      c.drawCircle(at, 8, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF112630),
            fontFamily: 'Roboto',
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(c, at - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }

    final first = layout.tiles.first, last = layout.tiles.last;
    endpoint('L', first.entry, -first.flow, const Color(0xFF65E7C6));
    endpoint('R', last.exit, last.flow, const Color(0xFFC3A1FF));
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.tiles != tiles;
}

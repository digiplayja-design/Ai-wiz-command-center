import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../social_client.dart';
import 'domino_tiles.dart';

/// Public seats only. Private hands stay in the player's hand controls.
class DominoTableScene extends StatelessWidget {
  const DominoTableScene({
    super.key,
    required this.tiles,
    required this.players,
    required this.me,
    this.turn,
    this.capacity = 4,
    this.playing = false,
  });

  final List<SocialMap> tiles, players;
  final String me;
  final String? turn;
  final int capacity;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final joined = players.where((p) => p['state'] == 'joined').toList();
    final own = joined.where((p) => p['id'] == me).firstOrNull;
    final anchor = (own?['seat'] as num?)?.toInt() ?? 0;
    final four = capacity == 4;
    SocialMap? player(int? seat) => seat == null
        ? null
        : joined.where((p) => p['seat'] == seat).firstOrNull;
    // Bottom -> right -> top -> left follows anti-clockwise turns and puts
    // partners opposite each other, whichever numbered seat the viewer holds.
    final seats = <String, int?>{
      'bottom': anchor,
      'right': four ? (anchor + 1) % 4 : null,
      'top': (anchor + (four ? 2 : 1)) % (four ? 4 : 2),
      'left': four ? (anchor + 3) % 4 : null,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final sideWidth = compact ? 54.0 : 100.0;
        final gap = compact ? 3.0 : 12.0;
        Widget seat(String position) {
          final index = seats[position], p = player(index);
          return _TableSeat(
            key: ValueKey('domino-seat-$position'),
            position: position,
            seat: index,
            player: p,
            own: p != null && p['id'] == me,
            active: playing && p != null && p['id'] == turn,
            partner: four && own != null && position == 'top',
            compact: compact,
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF102623),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF36534A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: math.min(240, constraints.maxWidth - 32),
                  child: seat('top'),
                ),
              ),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: sideWidth, child: seat('left')),
                  SizedBox(width: gap),
                  Expanded(
                    child: Container(
                      key: const ValueKey('domino-wooden-table'),
                      padding: EdgeInsets.all(compact ? 5 : 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFAD7643),
                            Color(0xFF5F371F),
                            Color(0xFF8E5E31),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFD6AC69),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 12,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                      child: DominoBoard(tiles: tiles),
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(width: sideWidth, child: seat('right')),
                ],
              ),
              SizedBox(height: gap),
              Center(
                child: SizedBox(
                  width: math.min(240, constraints.maxWidth - 32),
                  child: seat('bottom'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'JAMAICAN-STYLE TABLE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD6AC69),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              if (tiles.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'Pinch the tiles to zoom',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB1C3BC), fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TableSeat extends StatelessWidget {
  const _TableSeat({
    super.key,
    required this.position,
    required this.seat,
    required this.player,
    required this.own,
    required this.active,
    required this.partner,
    required this.compact,
  });
  final String position;
  final int? seat;
  final SocialMap? player;
  final bool own, active, partner, compact;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final name = p == null
        ? (seat == null ? 'Not in use' : 'Open seat')
        : '${p['name'] ?? 'Player'}';
    final count = p?['count'] as num?;
    final details = p == null
        ? (seat == null ? '' : 'Seat ${seat! + 1}')
        : [
            if (own) 'You' else if (partner) 'Partner',
            if (count != null) '${count.toInt()} tiles',
            if (active) own ? 'Your turn' : 'Playing',
          ].join(' · ');
    final label =
        '$position chair, ${seat == null ? 'not in use' : 'seat ${seat! + 1}, $name'}${p == null ? '' : '${own ? ', you' : ''}${partner ? ', your partner' : ''}${count == null ? '' : ', ${count.toInt()} tiles'}${active ? ', current turn' : ''}'}';
    final color = active
        ? const Color(0xFFFFD67B)
        : own || partner
        ? const Color(0xFF70E6C1)
        : const Color(0xFFD5BCF4);
    final horizontalSeat = position == 'top' || position == 'bottom';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: '$name${details.isEmpty ? '' : ' — $details'}',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalSeat ? 8 : 2,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF423A24) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: active ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                key: ValueKey('domino-chair-$position'),
                size: Size(compact ? 32 : 43, compact ? 32 : 43),
                painter: _ChairPainter(
                  position: position,
                  occupied: p != null,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: horizontalSeat ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p == null ? const Color(0xFFB1C3BC) : Colors.white,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  details,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: compact ? 10 : 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-down wooden chair; its back faces away from the playing surface.
class _ChairPainter extends CustomPainter {
  const _ChairPainter({
    required this.position,
    required this.occupied,
    required this.color,
  });
  final String position;
  final bool occupied;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(switch (position) {
      'top' => math.pi,
      'left' => math.pi / 2,
      'right' => -math.pi / 2,
      _ => 0.0,
    });
    canvas.scale(size.width / 44, size.height / 44);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-17, -16, 34, 36),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0x66000000),
    );
    final wood = Paint()..color = const Color(0xFFBA8450);
    for (final x in [-18.0, 13.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, -14, 5, 33),
          const Radius.circular(2),
        ),
        wood,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-13, -15, 26, 28),
        const Radius.circular(6),
      ),
      Paint()
        ..color = occupied
            ? color.withValues(alpha: .72)
            : const Color(0xFF536660),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-20, 10, 40, 9),
        const Radius.circular(3),
      ),
      wood,
    );
    canvas.drawLine(
      const Offset(-16, 12),
      const Offset(16, 12),
      Paint()
        ..color = const Color(0xFFE5BC85)
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChairPainter old) =>
      old.position != position ||
      old.occupied != occupied ||
      old.color != color;
}

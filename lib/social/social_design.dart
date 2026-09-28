import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';

Color socialColor(String? id) => switch (id) {
  'violet' => const Color(0xFFA994FF),
  'coral' => const Color(0xFFFFA18E),
  'mint' => const Color(0xFF67E2BE),
  'gold' => const Color(0xFFF2CE83),
  'blue' => const Color(0xFF8BB8FF),
  _ => const Color(0xFF64DCE9),
};
IconData socialIcon(String? id) => switch (id) {
  'sports' => Icons.sports_basketball_outlined,
  'entertainment' => Icons.movie_outlined,
  'politics' => Icons.account_balance_outlined,
  'religion' => Icons.auto_awesome_outlined,
  'stock-market' => Icons.show_chart_rounded,
  'technology' => Icons.memory_rounded,
  'business' => Icons.business_center_outlined,
  _ => Icons.forum_outlined,
};
String socialTime(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${date.month}/${date.day}/${date.year}';
}

class SocialPanel extends StatelessWidget {
  const SocialPanel({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context), color = accent ?? s.primary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              color.withValues(alpha: s.isLight ? .07 : .1),
              s.panelSoft,
            ),
            s.panelDeep,
          ],
        ),
        border: Border.all(color: s.border.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: s.isLight ? .05 : .22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SocialAvatar extends StatelessWidget {
  const SocialAvatar({
    super.key,
    required this.member,
    this.size = 52,
    this.showStatus = true,
  });
  final SocialMap member;
  final double size;
  final bool showStatus;
  @override
  Widget build(BuildContext context) {
    final name = '${member['name'] ?? '?'}'.trim(),
        color = socialColor(member['color']);
    return Semantics(
      label: showStatus && member['online'] == true
          ? '$name, online in Social'
          : name,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-.55, -.7),
                  colors: [Colors.white, color, color.withValues(alpha: .5)],
                  stops: const [0, .25, 1],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .45)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .17),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: const Color(0xFF112233),
                  fontWeight: FontWeight.w900,
                  fontSize: size * .38,
                ),
              ),
            ),
            if (showStatus && member['online'] == true)
              Positioned(
                right: 0,
                bottom: 1,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF58D7AA),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: korlixSkinOf(context).panelDeep,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SocialEmpty extends StatelessWidget {
  const SocialEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SocialPanel(
    child: Column(
      children: [
        const SizedBox(height: 12),
        Icon(icon, size: 40, color: korlixSkinOf(context).primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: korlixSkinOf(context).mutedText),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// Decorative dimensional network. Nodes are abstract shapes, never fake members.
class SocialOrbit extends StatelessWidget {
  const SocialOrbit({super.key, this.size = 150});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrbitPainter(korlixSkinOf(context).primary)),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.accent);
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width * .32;
    canvas.drawCircle(
      c,
      r * 1.4,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: .18), accent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.4)),
    );
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 3 - .2);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2.5, height: r * .8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: .45),
      );
      canvas.restore();
    }
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - .5,
          pos =
              c + Offset(math.cos(angle) * r * 1.14, math.sin(angle) * r * .94);
      final color = i.isEven ? accent : socialColor('violet');
      canvas.drawLine(c, pos, Paint()..color = color.withValues(alpha: .18));
      canvas.drawCircle(
        pos,
        6,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.4, -.6),
            colors: [Colors.white, color, color.withValues(alpha: .25)],
          ).createShader(Rect.fromCircle(center: pos, radius: 6)),
      );
    }
    canvas.drawCircle(
      c,
      r * .46,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.45, -.6),
          colors: [const Color(0xFFE9FFFF), accent, const Color(0xFF265C97)],
        ).createShader(Rect.fromCircle(center: c, radius: r * .46)),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.accent != accent;
}

Future<bool> socialConfirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void socialNotice(BuildContext context, Object message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$message')));
}

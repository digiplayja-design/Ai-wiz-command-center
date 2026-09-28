import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'korlix_theme.dart';

/// Equal dimensions across sections. Two columns, including an unfinished row.
/// Extent grows with accessibility text size rather than clipping labels.
class KorlixActionGrid extends StatelessWidget {
  const KorlixActionGrid({
    super.key,
    required this.children,
    this.compact = false,
    this.minimumHeight = 0,
  });
  final List<Widget> children;
  final bool compact;
  final double minimumHeight;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final width = (box.maxWidth - gap) / 2;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final extraLines = width < 180
          ? (compact ? 24.0 : 112.0) * math.max(0, scale - 1)
          : 0.0;
      final height =
          math.max(minimumHeight, compact ? 80.0 : 136.0) * math.max(1, scale) +
          extraLines +
          (width < 125 ? 16 : 0);
      return Column(
        children: [
          for (var index = 0; index < children.length; index += 2) ...[
            if (index > 0) const SizedBox(height: gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: width, height: height, child: children[index]),
                const SizedBox(width: gap),
                if (index + 1 < children.length)
                  SizedBox(
                    width: width,
                    height: height,
                    child: children[index + 1],
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

class KorlixActionSection extends StatelessWidget {
  const KorlixActionSection({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.children,
  });
  final String title, description;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: skin.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: skin.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${children.length}',
              style: TextStyle(color: skin.mutedText, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 14),
        KorlixActionGrid(children: children),
      ],
    );
  }
}

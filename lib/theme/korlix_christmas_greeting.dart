import 'package:flutter/material.dart';
import 'korlix_theme.dart';

class KorlixChristmasGreeting extends StatelessWidget {
  const KorlixChristmasGreeting({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    if (skin.id != 'christmas_red') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.ac_unit_rounded, color: skin.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Create a little Christmas magic',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: skin.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: Icon(Icons.ac_unit_rounded, color: skin.primary, size: 20),
          ),
        ],
      ),
    );
  }
}

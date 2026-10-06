import 'package:flutter/material.dart';
import 'korlix_theme.dart';
import 'korlix_screen_skin.dart';

/// A scaled, decorative sample. Labels outside the preview remain accessible.
class KorlixAppearancePreview extends StatelessWidget {
  const KorlixAppearancePreview({
    super.key,
    required this.palette,
    required this.skinId,
    this.compact = false,
    this.chat = false,
  });
  final KorlixSkinPalette palette;
  final String skinId;
  final bool compact, chat;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 14 : 22),
      child: SizedBox(
        height: compact ? 128 : 240,
        child: KorlixScreenBackdrop(
          palette: palette,
          skinId: skinId,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 20),
            child: FittedBox(
              fit: BoxFit.contain,
              child: MediaQuery.withNoTextScaling(
                child: SizedBox(
                  width: 320,
                  height: 205,
                  child: KorlixSkinFrame(
                    palette: palette,
                    skinId: skinId,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: palette.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: palette.border.withValues(alpha: .24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.blur_on_rounded,
                                color: palette.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'KORLIX AI',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.tune_rounded,
                                color: palette.mutedText,
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Expanded(child: chat ? _chat() : _home()),
                          const SizedBox(height: 9),
                          Container(
                            height: 29,
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            decoration: BoxDecoration(
                              color: palette.inputFill,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: palette.border.withValues(alpha: .5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Ask Korlix anything…',
                                    style: TextStyle(
                                      color: palette.hintText,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: palette.primary,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(
                                    Icons.arrow_upward,
                                    color: palette.textOnAccent,
                                    size: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _home() => Column(
    children: [
      Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [palette.primary, palette.secondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.glow.withValues(alpha: .2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 23,
              color: palette.textOnAccent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your AI, your way.',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'A little inspiration. Endless possibilities.',
                  style: TextStyle(color: palette.mutedText, fontSize: 8),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: Row(
          children: [
            Expanded(
              child: _tool('Create', Icons.auto_fix_high, palette.primary),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _tool('Business', Icons.work_outline, palette.secondary),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tool(String title, IconData icon, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      color: palette.panelSoft,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: accent.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: accent),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: palette.text,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _chat() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: palette.panelSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Help me plan my next big idea.',
            style: TextStyle(color: palette.text, fontSize: 10),
          ),
        ),
      ),
      const SizedBox(height: 9),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, size: 15, color: palette.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Let’s make room for something great.\nWhat would you like to create?',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

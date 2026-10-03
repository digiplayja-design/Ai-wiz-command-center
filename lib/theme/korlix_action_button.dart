import 'package:flutter/material.dart';

import 'korlix_button_colors.dart';
import 'korlix_theme.dart';

enum KorlixButtonSize { compact, regular, hero }

/// A sculpted surface around a native button: keyboard, focus and disabled
/// behavior stay with Flutter. Decoration never covers the label or hit target.
class KorlixActionButton extends StatelessWidget {
  const KorlixActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.eyebrow,
    this.accent,
    this.selected,
    this.locked = false,
    this.expand = false,
    this.iconOnly = false,
    this.busy = false,
    this.size = KorlixButtonSize.regular,
    this.leading,
    this.focusNode,
    this.tile = false,
  });

  final String label;
  final String? subtitle, eyebrow;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? accent;
  final bool? selected;
  final bool locked, expand, iconOnly, busy;
  final KorlixButtonSize size;
  final Widget? leading;
  final FocusNode? focusNode;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final enabled = onPressed != null && !busy;
    final active = selected == true;
    final hero = size == KorlixButtonSize.hero;
    final compact = size == KorlixButtonSize.compact;
    final light = skin.isLight;
    final palette = korlixButtonColorsFor(
      label,
      icon: icon,
      destructive: accent == skin.danger,
    );
    final tint = palette.start;
    final ink = enabled
        ? palette.foreground
        : skin.mutedText.withValues(alpha: .65);
    final color = ink;
    final radius = BorderRadius.circular(
      hero
          ? 24
          : compact
          ? 15
          : 18,
    );
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final faceColors = enabled
        ? palette.gradientColors
        : [
            Color.lerp(skin.panel, skin.mutedText, .08)!,
            Color.lerp(skin.panelDeep, skin.mutedText, .10)!,
          ];
    final iconSize = hero
        ? 52.0
        : compact
        ? 28.0
        : 32.0;

    final Widget emblem = leading != null
        ? Opacity(opacity: enabled ? 1 : .45, child: leading)
        : Container(
            width: iconSize,
            height: iconSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(hero ? 18 : 10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: enabled ? .12 : .06),
                  color.withValues(alpha: enabled ? .04 : .02),
                ],
              ),
              border: Border.all(
                color: color.withValues(alpha: enabled ? .32 : .12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: enabled ? .14 : .04),
                  offset: const Offset(-.5, -.5),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? .12 : .28),
                  offset: const Offset(0, 2),
                  blurRadius: 3,
                ),
              ],
            ),
            child: busy
                ? Padding(
                    padding: EdgeInsets.all(hero ? 13 : 7),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    icon,
                    size: hero
                        ? 28
                        : compact
                        ? 16
                        : 19,
                    color: color,
                  ),
          );

    final content = tile
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null || leading != null)
                    ExcludeSemantics(child: emblem),
                  if (locked || active) ...[
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        locked
                            ? Icons.lock_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 15,
                        color: color,
                      ),
                    ),
                  ],
                  if (locked && active) ...[
                    const SizedBox(width: 4),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ink, fontSize: 11, height: 1.3),
                ),
              ],
            ],
          )
        : iconOnly
        ? SizedBox(
            width: 24,
            height: 24,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: color)
                : Icon(icon, size: 22, color: color),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (icon != null || leading != null) ...[
                ExcludeSemantics(child: emblem),
                SizedBox(width: hero ? 14 : 9),
              ],
              Flexible(
                fit: expand ? FlexFit.tight : FlexFit.loose,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: ink,
                        fontSize: hero
                            ? 22
                            : compact
                            ? 12.5
                            : 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .1,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: ink,
                          fontSize: hero ? 12 : 10.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (locked || active || hero) ...[
                SizedBox(width: hero ? 12 : 7),
                ExcludeSemantics(
                  child: Icon(
                    locked
                        ? Icons.lock_outline_rounded
                        : active
                        ? Icons.check_circle_rounded
                        : Icons.arrow_outward_rounded,
                    size: hero ? 21 : 15,
                    color: color,
                  ),
                ),
              ],
              if (locked && active) ...[
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: hero ? 21 : 15,
                    color: color,
                  ),
                ),
              ],
            ],
          );

    final button = Semantics(
      selected: selected,
      label: iconOnly ? label : null,
      value: busy ? 'Working' : null,
      hint: locked ? 'Opens access options' : null,
      child: Padding(
        // Space for the solid bottom edge. Neighboring buttons keep clear.
        padding: const EdgeInsets.only(bottom: 4),
        child: TextButton(
          onPressed: enabled ? onPressed : null,
          focusNode: focusNode,
          clipBehavior: Clip.none,
          style:
              TextButton.styleFrom(
                foregroundColor: ink,
                disabledForegroundColor: ink,
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                minimumSize: Size(
                  48,
                  hero
                      ? 96
                      : compact
                      ? 48
                      : 54,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: iconOnly
                      ? 12
                      : hero
                      ? 18
                      : 12,
                  vertical: hero ? 17 : 10,
                ),
                shape: RoundedRectangleBorder(borderRadius: radius),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ).copyWith(
                animationDuration: duration,
                overlayColor: WidgetStateProperty.resolveWith(
                  // Darken white-letter faces and lighten dark-letter faces;
                  // interaction overlays always increase text contrast.
                  (states) =>
                      (palette.foreground == Colors.white
                              ? Colors.black
                              : Colors.white)
                          .withValues(
                            alpha: states.contains(WidgetState.pressed)
                                ? .10
                                : states.contains(WidgetState.hovered)
                                ? .04
                                : 0,
                          ),
                ),
                backgroundBuilder: (context, states, child) {
                  final pressed =
                      enabled && states.contains(WidgetState.pressed);
                  final hovered =
                      enabled && states.contains(WidgetState.hovered);
                  final focused =
                      enabled && states.contains(WidgetState.focused);
                  final raised = hovered || focused;
                  return AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(
                      0,
                      reduceMotion
                          ? 0
                          : pressed
                          ? 2
                          : raised
                          ? -1
                          : 0,
                      0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: faceColors,
                      ),
                      border: Border.all(
                        color: focused || active
                            ? ink
                            : color.withValues(alpha: enabled ? .24 : .18),
                        width: focused || active ? 2 : 1,
                      ),
                      boxShadow: [
                        // A contrasting outer ring remains visible on both
                        // the colorful face and the surrounding light/dark page.
                        if (focused)
                          BoxShadow(
                            color: light ? Colors.black : Colors.white,
                            spreadRadius: 3,
                          ),
                        // The hard lower edge provides physical depth without blur.
                        BoxShadow(
                          color: enabled
                              ? Color.lerp(palette.end, Colors.black, .22)!
                              : skin.panelDeep,
                          offset: Offset(0, pressed ? 1 : 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: light ? .10 : .32,
                          ),
                          blurRadius: pressed
                              ? 4
                              : raised
                              ? 16
                              : 10,
                          offset: Offset(0, pressed ? 3 : 7),
                        ),
                        if (enabled && (raised || active || hero))
                          BoxShadow(
                            color: tint.withValues(alpha: light ? .17 : .22),
                            blurRadius: hero ? 26 : 18,
                            spreadRadius: focused ? 1 : 0,
                          ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: _ButtonReflection(
                        radius.topLeft.x,
                        ink,
                        enabled,
                      ),
                      child: child,
                    ),
                  );
                },
              ),
          child: content,
        ),
      ),
    );
    return iconOnly ? Tooltip(message: label, child: button) : button;
  }
}

class _ButtonReflection extends CustomPainter {
  const _ButtonReflection(this.radius, this.accent, this.enabled);
  final double radius;
  final Color accent;
  final bool enabled;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path()
      ..moveTo(2, radius)
      ..quadraticBezierTo(2, 2, radius, 2)
      ..lineTo(size.width - radius, 2);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: enabled ? .30 : .08),
            accent.withValues(alpha: .06),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ButtonReflection old) =>
      old.radius != radius || old.accent != accent || old.enabled != enabled;
}

class KorlixLiveConvoButton extends StatelessWidget {
  const KorlixLiveConvoButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final voiceColors = korlixButtonColorsFor('Voice');
    return KorlixActionButton(
      label: 'Live Convo',
      eyebrow: 'K-Nova · LIVE VOICE',
      subtitle: 'Tap to start a conversation',
      onPressed: onPressed,
      size: KorlixButtonSize.hero,
      expand: true,
      leading: Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: voiceColors.gradientColors,
          ),
          border: Border.all(
            color: voiceColors.foreground.withValues(alpha: .4),
          ),
          boxShadow: [
            BoxShadow(
              color: voiceColors.start.withValues(
                alpha: onPressed == null ? .04 : .2,
              ),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: skin.panelDeep.withValues(alpha: .2),
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Opacity(
          opacity: onPressed == null ? .4 : 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final height in [9.0, 18.0, 26.0, 16.0, 10.0])
                Container(
                  width: 3,
                  height: height,
                  decoration: BoxDecoration(
                    color: voiceColors.foreground,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData korlixToolIcon(String label) => switch (label.toLowerCase()) {
  'email enhancer' => Icons.mark_email_read_outlined,
  'logo studio' => Icons.polyline_outlined,
  'tax prep' => Icons.receipt_long_outlined,
  'babyblend' => Icons.child_care_rounded,
  'fieldproof' => Icons.fact_check_outlined,
  'ai visibility' => Icons.insights_rounded,
  'seo agent' => Icons.travel_explore_rounded,
  'the pod and you' => Icons.podcasts_rounded,
  'contract radar' => Icons.radar_rounded,
  'virtual closet' => Icons.checkroom_rounded,
  'inventory studio' => Icons.inventory_2_outlined,
  'cybersecurity defender' => Icons.shield_outlined,
  'study studio' || 'study help' || 'étudier' => Icons.school_outlined,
  'app studio' || 'create an app' => Icons.code_rounded,
  'music studio' => Icons.music_note_rounded,
  'bookkeeping 2027' => Icons.account_balance_wallet_outlined,
  'workforce' => Icons.groups_outlined,
  'payroll' => Icons.payments_outlined,
  'korlix 2meetu' || 'scheduling' => Icons.event_available_outlined,
  'contacts crm' => Icons.contacts_outlined,
  'funnel studio' => Icons.filter_alt_outlined,
  'voice-scribe' || 'voice recorder' => Icons.graphic_eq_rounded,
  'copy box' => Icons.content_copy_rounded,
  'ask' || 'preguntar' || 'demander' => Icons.chat_bubble_outline_rounded,
  'write' => Icons.edit_note_rounded,
  _ => Icons.auto_awesome_rounded,
};

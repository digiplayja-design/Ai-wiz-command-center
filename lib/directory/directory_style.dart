import 'package:flutter/material.dart';

class DirectoryVisuals {
  static const violet = Color(0xff7355d8), cyan = Color(0xff0985ac);
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color ink(BuildContext context) =>
      dark(context) ? const Color(0xfff2f4ff) : const Color(0xff1c2946);
  static Color muted(BuildContext context) =>
      dark(context) ? const Color(0xffb5bfd5) : const Color(0xff586782);
  static (Color, Color, IconData) category(String category) {
    if (RegExp('Food|Travel|Hospitality').hasMatch(category)) {
      return (
        const Color(0xffc16b25),
        const Color(0xffe998b1),
        Icons.local_cafe_outlined,
      );
    }
    if (RegExp('Beauty|Arts').hasMatch(category)) {
      return (
        const Color(0xffbf4382),
        const Color(0xffb292e7),
        Icons.auto_awesome_outlined,
      );
    }
    if (RegExp('Health|Agriculture|Community').hasMatch(category)) {
      return (
        const Color(0xff23856c),
        const Color(0xff97bf59),
        Icons.spa_outlined,
      );
    }
    if (RegExp('Technology|Professional|Education').hasMatch(category)) {
      return (violet, const Color(0xff78a9eb), Icons.auto_awesome_outlined);
    }
    return (cyan, const Color(0xff8772d8), Icons.storefront_outlined);
  }

  static BoxDecoration panel(BuildContext context, {bool colorful = false}) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark(context)
              ? [
                  const Color(0xff172942),
                  colorful ? const Color(0xff2c2148) : const Color(0xff172038),
                ]
              : [
                  colorful ? const Color(0xffe5f8ff) : Colors.white,
                  colorful ? const Color(0xfff1eaff) : const Color(0xfffafaff),
                ],
        ),
        border: Border.all(
          color: dark(context)
              ? const Color(0xff465275)
              : const Color(0xffe1e4f2),
        ),
        boxShadow: [
          BoxShadow(
            color: violet.withValues(alpha: .07),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      );
}

class DirectoryHero extends StatelessWidget {
  const DirectoryHero({super.key, required this.actions});
  final Widget actions;
  @override
  Widget build(BuildContext context) => Container(
    decoration: DirectoryVisuals.panel(context, colorful: true),
    padding: const EdgeInsets.all(24),
    child: LayoutBuilder(
      builder: (context, box) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.4;
        final spacious =
            box.maxWidth > 740 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.4;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR BUSINESS. YOUR NEXT CHAPTER.',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: DirectoryVisuals.dark(context)
                          ? const Color(0xffb9a6ff)
                          : DirectoryVisuals.violet,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    'Your business deserves to be found.',
                    style: TextStyle(
                      fontSize: spacious ? 36 : 25,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: DirectoryVisuals.ink(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (largeText) ...[actions, const SizedBox(height: 20)],
                  Text(
                    'Create a free public storefront. Share your services, company photos and contact details. No paid KORLIX plan required.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: DirectoryVisuals.muted(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!largeText) actions,
                ],
              ),
            ),
            if (spacious) ...[
              const SizedBox(width: 35),
              SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: -.22,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(42),
                          border: Border.all(
                            color: DirectoryVisuals.violet.withValues(
                              alpha: .25,
                            ),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              DirectoryVisuals.cyan.withValues(alpha: .09),
                              DirectoryVisuals.violet.withValues(alpha: .2),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Image.asset(
                      'assets/branding/korlix_mini_mark.png',
                      width: 112,
                      height: 112,
                      excludeFromSemantics: true,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 25,
                        color: DirectoryVisuals.violet,
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: DirectoryVisuals.violet.withValues(
                                alpha: .12,
                              ),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: Text(
                          'READY TO BE DISCOVERED',
                          style: TextStyle(
                            fontSize: 8,
                            letterSpacing: .8,
                            color: DirectoryVisuals.muted(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class DirectoryListingCard extends StatelessWidget {
  const DirectoryListingCard({
    super.key,
    required this.name,
    required this.category,
    required this.location,
    required this.status,
    required this.selected,
    required this.onTap,
  });
  final String name, category, location, status;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (accent, second, icon) = DirectoryVisuals.category(category);
    final isDark = DirectoryVisuals.dark(context);
    return Semantics(
      selected: selected,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: DirectoryVisuals.panel(context).copyWith(
          border: Border.all(
            color: selected
                ? accent
                : isDark
                ? const Color(0xff465275)
                : const Color(0xffe1e4f2),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, second, second.withValues(alpha: .2)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: isDark ? .4 : .15),
                              second.withValues(alpha: .15),
                            ],
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: .17),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 27,
                          color: isDark
                              ? Color.lerp(accent, Colors.white, .5)
                              : accent,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.isNotEmpty)
                              Text(
                                category.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: isDark
                                      ? Color.lerp(accent, Colors.white, .45)
                                      : accent,
                                ),
                              ),
                            const SizedBox(height: 5),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3,
                                color: DirectoryVisuals.ink(context),
                              ),
                            ),
                            if (location.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  location,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DirectoryVisuals.muted(context),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.7,
                                color: DirectoryVisuals.muted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: isDark ? const Color(0xffb9a6ff) : accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

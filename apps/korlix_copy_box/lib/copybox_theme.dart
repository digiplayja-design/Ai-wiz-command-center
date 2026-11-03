import 'package:flutter/material.dart';

const copyboxInk = Color(0xFF161616);
const copyboxPaper = Color(0xFFF5F5F2);
const boxColorNames = ['Sage', 'Lavender', 'Butter', 'Sky', 'Peach', 'Stone'];
const boxColors = [
  Color(0xFFE3EEDC),
  Color(0xFFEDE5F6),
  Color(0xFFF6EDC6),
  Color(0xFFDDEAF3),
  Color(0xFFF4E2D6),
  Color(0xFFE7E7E3),
];
const darkBoxColors = [
  Color(0xFF28352A),
  Color(0xFF332B3E),
  Color(0xFF3D3724),
  Color(0xFF26343F),
  Color(0xFF3D2D28),
  Color(0xFF30302D),
];

ThemeData copyboxTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? Colors.white : copyboxInk;
  final surface = dark ? const Color(0xFF171717) : Colors.white;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: dark ? const Color(0xFF101010) : copyboxPaper,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: copyboxInk,
          brightness: brightness,
        ).copyWith(
          primary: ink,
          onPrimary: dark ? copyboxInk : Colors.white,
          surface: surface,
          surfaceTint: Colors.transparent,
          secondary: dark ? const Color(0xFFCBE1B9) : const Color(0xFF425B36),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF101010) : copyboxPaper,
      foregroundColor: ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: ink.withValues(alpha: .13)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: ink, width: 1.5),
      ),
      errorMaxLines: 4,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: dark ? copyboxInk : Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: .22)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ink,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(ink.withValues(alpha: .45)),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}

class CopyBoxBrand extends StatelessWidget {
  const CopyBoxBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/copybox_mark.png',
          width: compact ? 38 : 48,
          height: compact ? 38 : 48,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 11),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'KORLIX',
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'COPY Box',
            style: TextStyle(
              fontSize: compact ? 17 : 21,
              letterSpacing: -.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ],
  );
}

class CopyBoxEmpty extends StatelessWidget {
  const CopyBoxEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
    child: Column(
      children: [
        Icon(
          icon,
          size: 40,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .45),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.5),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

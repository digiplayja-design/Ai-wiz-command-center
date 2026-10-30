import 'package:flutter/material.dart';

const magicNavy = Color(0xFF07111F),
    magicPanel = Color(0xFF101E32),
    magicOrange = Color(0xFFFF982F),
    magicBlue = Color(0xFF399CFF),
    magicMuted = Color(0xFFA7B8CD);
ThemeData magicTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: magicBlue,
    brightness: Brightness.dark,
    primary: magicOrange,
    secondary: magicBlue,
    surface: magicNavy,
  ),
  scaffoldBackgroundColor: magicNavy,
  appBarTheme: const AppBarTheme(
    backgroundColor: magicNavy,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: magicPanel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    contentPadding: const EdgeInsets.all(18),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 56),
      backgroundColor: magicOrange,
      foregroundColor: magicNavy,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
);

class MagicMark extends StatelessWidget {
  const MagicMark({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/korlix_magic.png',
      package: 'korlix_magic_core',
      width: size,
      height: size,
      semanticLabel: 'Korlix Magic Camera orange and blue emblem',
    ),
  );
}

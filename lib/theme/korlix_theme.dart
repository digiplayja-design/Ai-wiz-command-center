import 'package:flutter/material.dart';
import 'korlix_button_colors.dart';

const korlixThemeIds = [
  'pure_white',
  'pure_black',
  'lavender_mist',
  'ocean_blue',
  'sunset_copper',
  'mint_cloud',
  'korlix_blue',
  'matrix_green',
  'ultra_gold',
  'pink_white',
  'dark_crimson',
  'white_gray',
];

String korlixThemeDescription(String id) => switch (korlixNormalizeSkinId(id)) {
  'pure_white' => 'True white backgrounds and panels. Crisp black text.',
  'pure_black' => 'Deep black with bright silver accents.',
  'lavender_mist' => 'Airy lavender with deep violet details.',
  'ocean_blue' => 'Deep ocean with fresh sky-blue highlights.',
  'sunset_copper' => 'Espresso surfaces and warm copper light.',
  'mint_cloud' => 'Soft mint with rich evergreen accents.',
  'matrix_green' => 'Deep forest, fresh mint and soft violet.',
  'ultra_gold' => 'Warm charcoal with understated gold.',
  'pink_white' => 'Soft rose surfaces with rich berry accents.',
  'dark_crimson' => 'Plum and crimson balanced with icy blue.',
  'white_gray' => 'Bright pearl, slate text and a deep teal accent.',
  _ => 'Signature navy with crisp cyan and soft lavender.',
};

class KorlixThemeScope extends StatelessWidget {
  const KorlixThemeScope({super.key, required this.builder, this.selection});
  final Widget Function(BuildContext, ThemeData) builder;
  final ValueNotifier<String>? selection;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: selection ?? kKorlixThemeNotifier,
    builder: (context, id, _) => builder(context, korlixBuildTheme(id)),
  );
}

class KorlixPaletteExtension extends ThemeExtension<KorlixPaletteExtension> {
  const KorlixPaletteExtension(this.palette);
  final KorlixSkinPalette palette;
  @override
  KorlixPaletteExtension copyWith({KorlixSkinPalette? palette}) =>
      KorlixPaletteExtension(palette ?? this.palette);
  @override
  KorlixPaletteExtension lerp(
    covariant KorlixPaletteExtension? other,
    double t,
  ) => other == null || t < .5 ? this : other;
}

KorlixSkinPalette korlixSkinOf(BuildContext context) =>
    Theme.of(context).extension<KorlixPaletteExtension>()?.palette ??
    korlixSkinPaletteFor(kKorlixThemeNotifier.value);

ThemeData korlixBuildTheme(String id) {
  final skin = korlixSkinPaletteFor(id);
  final brightness = skin.isLight ? Brightness.light : Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: skin.primary,
        brightness: brightness,
      ).copyWith(
        primary: skin.primary,
        onPrimary: skin.textOnAccent,
        secondary: skin.secondary,
        onSecondary: skin.isLight ? Colors.white : skin.panelDeep,
        tertiary: skin.tertiary,
        surface: skin.panel,
        onSurface: skin.text,
        onSurfaceVariant: skin.mutedText,
        surfaceContainerLowest: skin.backgroundBottom,
        surfaceContainerLow: skin.panelDeep,
        surfaceContainer: skin.panel,
        surfaceContainerHigh: skin.panelSoft,
        surfaceContainerHighest: skin.panelSoft,
        primaryContainer: skin.panelSoft,
        onPrimaryContainer: skin.text,
        secondaryContainer: skin.panelSoft,
        onSecondaryContainer: skin.text,
        outline: skin.border,
        outlineVariant: skin.border.withValues(alpha: .35),
        error: skin.danger,
        onError: skin.isLight ? Colors.white : skin.panelDeep,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  final primaryButton = korlixButtonColorsFor('Continue');
  final elevatedButton = korlixButtonColorsFor('Save');
  final actionInk = skin.isLight
      ? const Color(0xFF254EAC)
      : const Color(0xFF92C6FF);
  ButtonStyle filledStyle(KorlixButtonColors colors) =>
      FilledButton.styleFrom(
        backgroundColor: colors.start,
        foregroundColor: colors.foreground,
        disabledBackgroundColor: skin.panelSoft,
        disabledForegroundColor: skin.mutedText,
        minimumSize: const Size(48, 48),
        shape: rounded,
      ).copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? skin.text
                : Colors.transparent,
            width: states.contains(WidgetState.focused) ? 3 : 1,
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Colors.transparent
              : (colors.foreground.computeLuminance() > .5
                        ? Colors.black
                        : Colors.white)
                    .withValues(
                      alpha: states.contains(WidgetState.pressed) ? .08 : .04,
                    ),
        ),
      );
  return base.copyWith(
    extensions: [KorlixPaletteExtension(skin)],
    scaffoldBackgroundColor: skin.backgroundMid,
    textTheme: base.textTheme.apply(
      bodyColor: skin.text,
      displayColor: skin.text,
    ),
    iconTheme: IconThemeData(color: skin.primary),
    dividerTheme: DividerThemeData(
      color: skin.border.withValues(alpha: .3),
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: skin.backgroundMid,
      foregroundColor: skin.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: skin.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rounded,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: skin.panel,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: skin.panel,
      modalBackgroundColor: skin.panel,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: skin.panel,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: skin.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: skin.inputFill,
      hintStyle: TextStyle(color: skin.hintText),
      labelStyle: TextStyle(color: skin.mutedText),
      floatingLabelStyle: TextStyle(color: skin.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: skin.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: skin.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: skin.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledStyle(primaryButton)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: filledStyle(elevatedButton),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: actionInk,
            disabledForegroundColor: skin.mutedText,
            side: BorderSide(color: actionInk.withValues(alpha: .7)),
            minimumSize: const Size(48, 48),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? skin.border.withValues(alpha: .35)
                    : actionInk.withValues(alpha: .7),
                width: states.contains(WidgetState.focused) ? 2 : 1,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: actionInk,
        disabledForegroundColor: skin.mutedText,
        minimumSize: const Size(48, 48),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: skin.buttonFill,
      selectedColor: skin.panelSoft,
      labelStyle: base.textTheme.labelLarge!.copyWith(color: skin.text),
      secondaryLabelStyle: base.textTheme.labelLarge!.copyWith(
        color: skin.text,
      ),
      checkmarkColor: skin.primary,
      side: BorderSide(color: skin.border.withValues(alpha: .6)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: skin.primary,
      selectionColor: skin.primary.withValues(alpha: skin.isLight ? .20 : .25),
      selectionHandleColor: skin.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: skin.panelDeep,
      contentTextStyle: TextStyle(color: skin.text),
      actionTextColor: skin.primary,
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: skin.text,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: skin.panel),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: skin.primary),
  );
}

class KorlixSkinPalette {
  final String id;
  final String label;
  final bool isLight;

  final Color backgroundTop;
  final Color backgroundMid;
  final Color backgroundBottom;

  final Color panel;
  final Color panelSoft;
  final Color panelDeep;
  final Color inputFill;
  final Color buttonFill;

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color border;
  final Color glow;

  final Color text;
  final Color mutedText;
  final Color hintText;
  final Color textOnAccent;

  final Color success;
  final Color danger;
  final Color premium;

  bool get isPureWhite => id == 'pure_white';

  const KorlixSkinPalette({
    required this.id,
    required this.label,
    required this.isLight,
    required this.backgroundTop,
    required this.backgroundMid,
    required this.backgroundBottom,
    required this.panel,
    required this.panelSoft,
    required this.panelDeep,
    required this.inputFill,
    required this.buttonFill,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.border,
    required this.glow,
    required this.text,
    required this.mutedText,
    required this.hintText,
    required this.textOnAccent,
    required this.success,
    required this.danger,
    required this.premium,
  });
}

String korlixNormalizeSkinId(String theme) {
  final id = theme.trim().toLowerCase();

  if (korlixThemeIds.contains(id)) return id;

  switch (id) {
    case 'blue':
    case 'korlix':
    case 'korlix_blue_neon':
    case 'korlix_blue':
      return 'korlix_blue';

    case 'green':
    case 'matrix':
    case 'purple_green':
    case 'cyber_purple':
    case 'matrix_green':
      return 'matrix_green';

    case 'gold':
    case 'black_gold':
    case 'gold_black':
    case 'ultra_gold':
      return 'ultra_gold';

    case 'pink':
    case 'pink_luxe':
    case 'pink_white':
      return 'pink_white';

    case 'crimson':
    case 'red_ice':
    case 'dark_crimson':
      return 'dark_crimson';

    case 'white':
    case 'gray':
    case 'silver':
    case 'black_white':
    case 'white_gray':
      return 'white_gray';

    default:
      return 'korlix_blue';
  }
}

KorlixSkinPalette korlixSkinPaletteFor(String theme) {
  switch (korlixNormalizeSkinId(theme)) {
    case 'pure_white':
      return const KorlixSkinPalette(
        id: 'pure_white',
        label: 'Pure White',
        isLight: true,
        backgroundTop: Color(0xFFFFFFFF),
        backgroundMid: Color(0xFFFFFFFF),
        backgroundBottom: Color(0xFFFFFFFF),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFFFFFFF),
        panelDeep: Color(0xFFFFFFFF),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFFFFFFF),
        primary: Color(0xFF17202B),
        secondary: Color(0xFF374151),
        tertiary: Color(0xFF344357),
        border: Color(0xFF78828F),
        glow: Color(0xFF17202B),
        text: Color(0xFF111827),
        mutedText: Color(0xFF46505E),
        hintText: Color(0xFF536070),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFF236745),
        danger: Color(0xFFAA2537),
        premium: Color(0xFF76552B),
      );
    case 'pure_black':
      return const KorlixSkinPalette(
        id: 'pure_black',
        label: 'Pure Black',
        isLight: false,
        backgroundTop: Color(0xFF000000),
        backgroundMid: Color(0xFF000000),
        backgroundBottom: Color(0xFF000000),
        panel: Color(0xFF080808),
        panelSoft: Color(0xFF171717),
        panelDeep: Color(0xFF000000),
        inputFill: Color(0xFF080808),
        buttonFill: Color(0xFF151515),
        primary: Color(0xFFE8EDF3),
        secondary: Color(0xFFC6CDDA),
        tertiary: Color(0xFFA8C5E5),
        border: Color(0xFF818894),
        glow: Color(0xFFC6CDDA),
        text: Color(0xFFFFFFFF),
        mutedText: Color(0xFFC9CDD4),
        hintText: Color(0xFFB6BEC9),
        textOnAccent: Color(0xFF101820),
        success: Color(0xFFA7E6BC),
        danger: Color(0xFFFFADB1),
        premium: Color(0xFFE9D6A2),
      );
    case 'lavender_mist':
      return const KorlixSkinPalette(
        id: 'lavender_mist',
        label: 'Lavender Mist',
        isLight: true,
        backgroundTop: Color(0xFFFBFAFF),
        backgroundMid: Color(0xFFF6F2FD),
        backgroundBottom: Color(0xFFF0EAF8),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFF5EFFA),
        panelDeep: Color(0xFFECE4F4),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFF7F3FA),
        primary: Color(0xFF624096),
        secondary: Color(0xFF6B477D),
        tertiary: Color(0xFF4C547E),
        border: Color(0xFF8F7AA8),
        glow: Color(0xFF8D68BA),
        text: Color(0xFF2D233A),
        mutedText: Color(0xFF5D486F),
        hintText: Color(0xFF655274),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFF236745),
        danger: Color(0xFFA32540),
        premium: Color(0xFF76552B),
      );
    case 'ocean_blue':
      return const KorlixSkinPalette(
        id: 'ocean_blue',
        label: 'Ocean Blue',
        isLight: false,
        backgroundTop: Color(0xFF04111E),
        backgroundMid: Color(0xFF082033),
        backgroundBottom: Color(0xFF0D263A),
        panel: Color(0xFF102B40),
        panelSoft: Color(0xFF193B53),
        panelDeep: Color(0xFF061C2D),
        inputFill: Color(0xFF0A2032),
        buttonFill: Color(0xFF17374B),
        primary: Color(0xFF83D5FF),
        secondary: Color(0xFFA3DBD2),
        tertiary: Color(0xFFC0C8FF),
        border: Color(0xFF7495AE),
        glow: Color(0xFF83D5FF),
        text: Color(0xFFF0F8FF),
        mutedText: Color(0xFFC3D6E7),
        hintText: Color(0xFFB6CDD9),
        textOnAccent: Color(0xFF062238),
        success: Color(0xFF9ADFC4),
        danger: Color(0xFFFFACB2),
        premium: Color(0xFFEBD393),
      );
    case 'sunset_copper':
      return const KorlixSkinPalette(
        id: 'sunset_copper',
        label: 'Sunset Copper',
        isLight: false,
        backgroundTop: Color(0xFF170F0D),
        backgroundMid: Color(0xFF241813),
        backgroundBottom: Color(0xFF2B1E18),
        panel: Color(0xFF2E211B),
        panelSoft: Color(0xFF3C2D24),
        panelDeep: Color(0xFF1C120D),
        inputFill: Color(0xFF241811),
        buttonFill: Color(0xFF36261D),
        primary: Color(0xFFF1B78E),
        secondary: Color(0xFFE1C4A3),
        tertiary: Color(0xFFEBAFAA),
        border: Color(0xFFA78A73),
        glow: Color(0xFFEAB28C),
        text: Color(0xFFFBF3EC),
        mutedText: Color(0xFFDCC9BA),
        hintText: Color(0xFFD1BBAA),
        textOnAccent: Color(0xFF321A0C),
        success: Color(0xFFB0DABC),
        danger: Color(0xFFFFADB0),
        premium: Color(0xFFE9CD9B),
      );
    case 'mint_cloud':
      return const KorlixSkinPalette(
        id: 'mint_cloud',
        label: 'Mint Cloud',
        isLight: true,
        backgroundTop: Color(0xFFFAFEFC),
        backgroundMid: Color(0xFFF0F8F3),
        backgroundBottom: Color(0xFFE6F2EB),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFEFF8F2),
        panelDeep: Color(0xFFE2EFE7),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFF0F7F3),
        primary: Color(0xFF1E6049),
        secondary: Color(0xFF3C5B68),
        tertiary: Color(0xFF426044),
        border: Color(0xFF6E9580),
        glow: Color(0xFF61A188),
        text: Color(0xFF183429),
        mutedText: Color(0xFF425E50),
        hintText: Color(0xFF4D6658),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFF236745),
        danger: Color(0xFFA32540),
        premium: Color(0xFF76552B),
      );
    case 'matrix_green':
      return const KorlixSkinPalette(
        id: 'matrix_green',
        label: 'Matrix Forest',
        isLight: false,
        backgroundTop: Color(0xFF081410),
        backgroundMid: Color(0xFF101E19),
        backgroundBottom: Color(0xFF161A2A),
        panel: Color(0xFF13251F),
        panelSoft: Color(0xFF20372C),
        panelDeep: Color(0xFF0C1A14),
        inputFill: Color(0xFF0B1B15),
        buttonFill: Color(0xFF1B3025),
        primary: Color(0xFF85E3B5),
        secondary: Color(0xFFC1B3F7),
        tertiary: Color(0xFF8BD3BE),
        border: Color(0xFF6B8D7D),
        glow: Color(0xFF85E3B5),
        text: Color(0xFFF0F7F3),
        mutedText: Color(0xFFC0D2C8),
        hintText: Color(0xFFB5CBBF),
        textOnAccent: Color(0xFF07281B),
        success: Color(0xFF85E3B5),
        danger: Color(0xFFFFAAAB),
        premium: Color(0xFFDBCEA5),
      );

    case 'ultra_gold':
      return const KorlixSkinPalette(
        id: 'ultra_gold',
        label: 'Obsidian Gold',
        isLight: false,
        backgroundTop: Color(0xFF100E0B),
        backgroundMid: Color(0xFF1A1712),
        backgroundBottom: Color(0xFF211C15),
        panel: Color(0xFF211D16),
        panelSoft: Color(0xFF312A20),
        panelDeep: Color(0xFF14110D),
        inputFill: Color(0xFF15120E),
        buttonFill: Color(0xFF2A241B),
        primary: Color(0xFFECCA7C),
        secondary: Color(0xFFDFBB90),
        tertiary: Color(0xFFF0D9B0),
        border: Color(0xFF9A8564),
        glow: Color(0xFFECCA7C),
        text: Color(0xFFFCF6E9),
        mutedText: Color(0xFFD2C5AE),
        hintText: Color(0xFFCABC9F),
        textOnAccent: Color(0xFF2B200A),
        success: Color(0xFFA7D6AE),
        danger: Color(0xFFFFAAA0),
        premium: Color(0xFFECCA7C),
      );

    case 'pink_white':
      return const KorlixSkinPalette(
        id: 'pink_white',
        label: 'Rose Quartz',
        isLight: true,
        backgroundTop: Color(0xFFFCF8FA),
        backgroundMid: Color(0xFFF8F0F4),
        backgroundBottom: Color(0xFFF3E8EF),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFF9EEF4),
        panelDeep: Color(0xFFF2E4ED),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFFAF2F6),
        primary: Color(0xFFA9235F),
        secondary: Color(0xFF72508F),
        tertiary: Color(0xFF934265),
        border: Color(0xFF9F7188),
        glow: Color(0xFFC45587),
        text: Color(0xFF38212F),
        mutedText: Color(0xFF674759),
        hintText: Color(0xFF704D61),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFF246449),
        danger: Color(0xFFA92036),
        premium: Color(0xFF814483),
      );

    case 'dark_crimson':
      return const KorlixSkinPalette(
        id: 'dark_crimson',
        label: 'Crimson Ice',
        isLight: false,
        backgroundTop: Color(0xFF160D16),
        backgroundMid: Color(0xFF20111E),
        backgroundBottom: Color(0xFF261523),
        panel: Color(0xFF271927),
        panelSoft: Color(0xFF382331),
        panelDeep: Color(0xFF180D18),
        inputFill: Color(0xFF1B101C),
        buttonFill: Color(0xFF301E2D),
        primary: Color(0xFFB2E5F0),
        secondary: Color(0xFFFFA6BD),
        tertiary: Color(0xFFD1B9EC),
        border: Color(0xFF9A718E),
        glow: Color(0xFFE89AAA),
        text: Color(0xFFFAF0F7),
        mutedText: Color(0xFFD5BECC),
        hintText: Color(0xFFCDB4C5),
        textOnAccent: Color(0xFF152B34),
        success: Color(0xFF9BDDCE),
        danger: Color(0xFFFFA8AD),
        premium: Color(0xFFE7C39D),
      );

    case 'white_gray':
      return const KorlixSkinPalette(
        id: 'white_gray',
        label: 'Pearl Slate',
        isLight: true,
        backgroundTop: Color(0xFFF8FAFC),
        backgroundMid: Color(0xFFF1F5F9),
        backgroundBottom: Color(0xFFEAF0F5),
        panel: Color(0xFFFFFFFF),
        panelSoft: Color(0xFFF4F7FA),
        panelDeep: Color(0xFFE6EDF4),
        inputFill: Color(0xFFFFFFFF),
        buttonFill: Color(0xFFF1F5F9),
        primary: Color(0xFF00627B),
        secondary: Color(0xFF475F7D),
        tertiary: Color(0xFF395C8A),
        border: Color(0xFF738498),
        glow: Color(0xFF529CB0),
        text: Color(0xFF172A3C),
        mutedText: Color(0xFF465A70),
        hintText: Color(0xFF516277),
        textOnAccent: Color(0xFFFFFFFF),
        success: Color(0xFF236745),
        danger: Color(0xFFAA2537),
        premium: Color(0xFF76552B),
      );

    case 'korlix_blue':
    default:
      return const KorlixSkinPalette(
        id: 'korlix_blue',
        label: 'KORLIX Midnight',
        isLight: false,
        backgroundTop: Color(0xFF07101C),
        backgroundMid: Color(0xFF0C1828),
        backgroundBottom: Color(0xFF111B30),
        panel: Color(0xFF111F31),
        panelSoft: Color(0xFF1B2D43),
        panelDeep: Color(0xFF0A1626),
        inputFill: Color(0xFF0B1829),
        buttonFill: Color(0xFF182A40),
        primary: Color(0xFF74D8EE),
        secondary: Color(0xFFB0AEF5),
        tertiary: Color(0xFF83ADF3),
        border: Color(0xFF67849E),
        glow: Color(0xFF74D8EE),
        text: Color(0xFFF0F5FB),
        mutedText: Color(0xFFB9C8DA),
        hintText: Color(0xFFB2C3D6),
        textOnAccent: Color(0xFF06222D),
        success: Color(0xFF79D9B0),
        danger: Color(0xFFFFA4AA),
        premium: Color(0xFFF0CF89),
      );
  }
}

String korlixThemeLabelFor(String theme) {
  return korlixSkinPaletteFor(theme).label;
}

bool korlixThemeIsLight(String theme) {
  return korlixSkinPaletteFor(theme).isLight;
}

Color korlixThemeAccentFor(String theme) {
  return korlixSkinPaletteFor(theme).primary;
}

Color korlixThemePanelFor(String theme) {
  return korlixSkinPaletteFor(theme).panel;
}

Color korlixThemeSecondaryFor(String theme) {
  return korlixSkinPaletteFor(theme).secondary;
}

Color korlixThemeBorderFor(String theme) {
  return korlixSkinPaletteFor(theme).border;
}

Color korlixThemeTextFor(String theme) {
  return korlixSkinPaletteFor(theme).text;
}

Color korlixThemeMutedTextFor(String theme) {
  return korlixSkinPaletteFor(theme).mutedText;
}

List<Color> korlixThemeBackgroundFor(String theme) {
  final skin = korlixSkinPaletteFor(theme);

  return <Color>[skin.backgroundTop, skin.backgroundMid, skin.backgroundBottom];
}

SnackBar korlixThemeAppliedSnackBar(String theme) {
  final normalizedTheme = korlixNormalizeSkinId(theme);
  final skin = korlixSkinPaletteFor(normalizedTheme);

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1600),
    elevation: 0,
    backgroundColor: Colors.transparent,
    margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
    padding: EdgeInsets.zero,
    content: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.panelDeep.withValues(alpha: skin.isLight ? 0.94 : 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: skin.border.withValues(alpha: skin.isLight ? 0.54 : 0.62),
          width: 1.05,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.glow.withValues(alpha: skin.isLight ? 0.04 : 0.08),
            blurRadius: 18,
            spreadRadius: 0.5,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [skin.primary, skin.secondary, skin.panelDeep],
              ),
              border: Border.all(
                color: skin.text.withValues(alpha: skin.isLight ? 0.42 : 0.34),
              ),
            ),
            child: Icon(
              Icons.palette_rounded,
              color: skin.textOnAccent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Theme applied: ${korlixThemeLabelFor(normalizedTheme)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.text,
                fontSize: 13.2,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final ValueNotifier<String> kKorlixThemeNotifier = ValueNotifier<String>(
  'korlix_blue',
);

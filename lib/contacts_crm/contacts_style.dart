import 'package:flutter/material.dart';
import 'contacts_client.dart';

abstract final class CrmStyle {
  static const background = Color(0xFF090E1A);
  static const sidebar = Color(0xFF0D1322);
  static const surface = Color(0xFF111A2B);
  static const raised = Color(0xFF172238);
  static const line = Color(0xFF243149);
  static const text = Color(0xFFF2F5FC);
  static const muted = Color(0xFFA0AEC5);
  static const cyan = Color(0xFF80EFE1);
  static const violet = Color(0xFFB8A6FF);
  static const gold = Color(0xFFF1C578);
  static const pink = Color(0xFFF3A7CD);
  static const danger = Color(0xFFFFACAC);
  static Color category(String c) => switch (c) {
    'customer' => cyan,
    'family' => pink,
    'friend' => const Color(0xFF98B9FF),
    'lead' => gold,
    'partner' => violet,
    'vendor' => const Color(0xFF99DCCB),
    _ => muted,
  };
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: cyan,
      onPrimary: Color(0xFF082823),
      secondary: violet,
      surface: surface,
      onSurface: text,
      error: danger,
    ),
    dividerColor: line,
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
    visualDensity: VisualDensity.standard,
    textTheme: ThemeData.dark().textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: text,
      displayColor: text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: cyan, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cyan,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: raised,
      surfaceTintColor: Colors.transparent,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: muted, width: 1.2),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

class CrmBadge extends StatelessWidget {
  const CrmBadge(
    this.label, {
    super.key,
    this.color = CrmStyle.cyan,
    this.dot = false,
  });
  final String label;
  final Color color;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: .17)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({super.key, required this.contact, this.size = 38});
  final Map<String, dynamic> contact;
  final double size;
  @override
  Widget build(BuildContext context) {
    final name = (contact['name'] ?? '?').toString().trim().split(
      RegExp(r'\s+'),
    );
    final initials = name
        .take(2)
        .map((e) => e.isEmpty ? '' : e.characters.first)
        .join()
        .toUpperCase();
    final color = CrmStyle.category(contact['category'] ?? 'unknown');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: .25), color.withValues(alpha: .08)],
        ),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontSize: size * .31,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class CrmSectionLabel extends StatelessWidget {
  const CrmSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: CrmStyle.muted,
      letterSpacing: 1.6,
    ),
  );
}

class RelationshipBadge extends StatelessWidget {
  const RelationshipBadge(this.category, {super.key});
  final String category;
  @override
  Widget build(BuildContext context) => CrmBadge(
    contactLabel(category),
    color: CrmStyle.category(category),
    dot: true,
  );
}

String contactDate(String? value) {
  final date = DateTime.tryParse(value ?? '');
  if (date == null) return 'Not scheduled';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

bool contactDue(Map<String, dynamic> c) =>
    c['follow_up_on'] != null &&
    c['follow_up_on'].toString().compareTo(
          DateTime.now().toIso8601String().substring(0, 10),
        ) <=
        0;

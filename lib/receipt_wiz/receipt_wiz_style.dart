import 'package:flutter/material.dart';

const wizInk = Color(0xFF102B3E),
    wizTeal = Color(0xFF007F89),
    wizMint = Color(0xFFADFAE6),
    wizPaper = Color(0xFFF5F8FA),
    wizMuted = Color(0xFF607686);
const wizCategories = [
  'Uncategorized',
  'Groceries',
  'Meals & dining',
  'Fuel & transport',
  'Office supplies',
  'Equipment',
  'Travel & lodging',
  'Utilities',
  'Software & subscriptions',
  'Repairs & maintenance',
  'Health & medical',
  'Education',
  'Shopping',
  'Professional services',
  'Other',
];
Map<String, dynamic> wizMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> wizRows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
String wizAmount(Map<String, dynamic> d) =>
    '${d['currency'] ?? ''} ${d['total']?.toString().isNotEmpty == true ? d['total'] : 'Amount needed'}'
        .trim();
ThemeData wizTheme(BuildContext context) => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: wizTeal,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: wizPaper,
  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
  appBarTheme: const AppBarTheme(
    backgroundColor: wizPaper,
    foregroundColor: wizInk,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD8E4E8)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
);
Widget wizChip(String text, {IconData? icon, Color? color}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  decoration: BoxDecoration(
    color: (color ?? wizTeal).withValues(alpha: .09),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 15, color: color ?? wizTeal),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            color: color ?? wizTeal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);
Widget wizPanel(Widget child) => Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE0E9ED)),
  ),
  child: child,
);

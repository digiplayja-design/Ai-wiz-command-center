import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:korlix_pos_core/korlix_pos_core.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the practice app accessible to assistive technology and keyboard users.
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KORLIX POS',
      theme: posTheme(),
      home: const PosScreen(),
    ),
  );
}

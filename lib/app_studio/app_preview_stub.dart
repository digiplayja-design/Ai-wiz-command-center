import 'package:flutter/material.dart';

class AppPreview extends StatelessWidget {
  const AppPreview({super.key, required this.html});
  final String html;
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Interactive preview is available in KORLIX on the web. You can review the plan here and export your app to try it in a browser.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

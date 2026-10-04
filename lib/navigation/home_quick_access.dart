import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';

/// Tool search stays near the header, independently of account or generation loading.
class HomeQuickAccess extends StatelessWidget {
  const HomeQuickAccess({super.key, required this.onFindTool});
  final VoidCallback onFindTool;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: KorlixActionButton(
      key: const ValueKey('home-find-tool'),
      label: 'Find a tool',
      subtitle: 'Search KORLIX by name or task',
      icon: Icons.search_rounded,
      expand: true,
      onPressed: onFindTool,
    ),
  );
}

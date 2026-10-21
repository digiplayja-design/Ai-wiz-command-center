import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';

/// Lives outside the home's scroll view and reserves its own layout space.
class KorlixFixedPlanBar extends StatelessWidget {
  const KorlixFixedPlanBar({
    super.key,
    this.actions = const [],
    this.tier,
    this.developer = false,
    this.busy = false,
    required this.onOpenPlans,
  });

  final List<Widget> actions;
  final String? tier;
  final bool developer, busy;
  final VoidCallback onOpenPlans;

  String get label => developer ||
          const ['ultra', 'ultra_premium', 'ultra premium', 'enterprise']
              .contains(tier?.toLowerCase())
      ? 'My Plan'
      : const ['basic', 'pro'].contains(tier?.toLowerCase())
      ? 'Upgrade'
      : 'View Plans';

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final button = FilledButton.icon(
      key: const Key('fixed-plan-button'),
      onPressed: busy ? null : onOpenPlans,
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, 48),
        backgroundColor: skin.primary,
        foregroundColor: skin.textOnAccent,
      ),
      icon: const Icon(Icons.workspace_premium_outlined, size: 20),
      label: Text(busy ? 'Opening…' : label),
    );
    return Material(
      key: const Key('fixed-plan-bar'),
      color: skin.panel,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: LayoutBuilder(builder: (context, constraints) {
            final tools = Wrap(children: actions);
            if (actions.isNotEmpty &&
                (constraints.maxWidth < 400 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [tools, button],
              );
            }
            return Row(children: [Expanded(child: tools), button]);
          }),
        ),
      ),
    );
  }
}

/// A public overview. Purchases and account pricing remain in existing billing.
Future<bool> showKorlixPublicPlans(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose your Korlix plan'),
        content: const SingleChildScrollView(
          child: Text(
            'Ultra\nHigher usage, LIVE CONVO and an ad-free experience.\n\n'
            'Pro\nMore room for daily creation, documents and exports.\n\n'
            'Basic · Free\nMost features are extremely limited.\n\n'
            'Enterprise\nOrganization-managed access for teams.\n\n'
            'Create your free account or sign in to see current pricing and '
            'full plan details. AI GAS and Music Studio purchases are separate.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create free account')),
        ],
      ),
    ) ?? false;

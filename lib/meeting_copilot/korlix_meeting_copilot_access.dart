import 'package:flutter/material.dart';

const String kKorlixMeetingCopilotRoutePath = '/meeting-copilot';

final ValueNotifier<bool> kKorlixMeetingCopilotEnterpriseAccess =
    ValueNotifier<bool>(false);

bool korlixMeetingCopilotEnterpriseEnabled(Object? tier) {
  final normalized = (tier ?? '').toString().trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '_',
  );

  final tokens = normalized
      .split('_')
      .where((token) => token.isNotEmpty)
      .toSet();

  return tokens.contains('enterprise') &&
      !tokens.contains('non') &&
      !tokens.contains('not');
}

void setKorlixMeetingCopilotEnterpriseAccess(bool enabled) {
  if (kKorlixMeetingCopilotEnterpriseAccess.value != enabled) {
    kKorlixMeetingCopilotEnterpriseAccess.value = enabled;
  }
}

void syncKorlixMeetingCopilotEnterpriseAccessFromTier(Object? tier) {
  setKorlixMeetingCopilotEnterpriseAccess(
    korlixMeetingCopilotEnterpriseEnabled(tier),
  );
}

class KorlixMeetingCopilotLockedPanel extends StatelessWidget {
  const KorlixMeetingCopilotLockedPanel({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: Color(0xFF69D9E8)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enterprise upgrade required',
                  style: TextStyle(
                    color: Color(0xFFF0F7F8),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Nova Meeting Copilot is an '
            'Enterprise-only tool. Your '
            'current plan cannot join, '
            'listen to, or process meetings.',
            style: TextStyle(color: Color(0xFFA9C6CF), height: 1.45),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF081F2C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2B5360)),
            ),
            child: const Text(
              'ENTERPRISE ONLY • Upgrade '
              'access is required before any '
              'Zoom connection or meeting '
              'activity.',
              style: TextStyle(
                color: Color(0xFF69D9E8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Return to Agent Hub'),
            ),
          ),
        ],
      ),
    ),
  );
}

class KorlixMeetingCopilotLockedPage extends StatelessWidget {
  const KorlixMeetingCopilotLockedPage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: kKorlixMeetingCopilotEnterpriseAccess,
    builder: (context, enabled, _) {
      if (enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(
              context,
            ).pushReplacementNamed(kKorlixMeetingCopilotRoutePath);
          }
        });

        return const Scaffold(
          backgroundColor: Color(0xFF03131E),
          body: Center(child: CircularProgressIndicator()),
        );
      }

      return Scaffold(
        backgroundColor: Color(0xFF03131E),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: Card(
              color: Color(0xFF071722),
              margin: EdgeInsets.all(24),
              child: KorlixMeetingCopilotLockedPanel(),
            ),
          ),
        ),
      );
    },
  );
}

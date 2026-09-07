import 'package:flutter/material.dart';

import 'korlix_meeting_copilot.dart';
import 'korlix_meeting_copilot_access.dart';

abstract final class KorlixMeetingCopilotAssets {
  static const String korlixLogo = 'assets/meeting_copilot/korlix_logo.jpeg';
  static const String novaPortrait =
      'assets/meeting_copilot/nova_canonical.webp';
}

class KorlixMeetingCopilotRoute extends StatefulWidget {
  const KorlixMeetingCopilotRoute({super.key});

  static const String routeName = '/meeting-copilot';
  static const Key screenKey = Key('korlix-meeting-copilot-route');
  static const String accessibilityLabel =
      'Nova Meeting Copilot. Nova is still muted by default until the host invites her.';

  @override
  State<KorlixMeetingCopilotRoute> createState() =>
      _KorlixMeetingCopilotRouteState();
}

class _KorlixMeetingCopilotRouteState extends State<KorlixMeetingCopilotRoute> {
  late final NovaMeetingCopilotController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NovaMeetingCopilotController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // K135Z_B4B_V11_DIRECT_ROUTE_ENTERPRISE_GATE
    if (!kKorlixMeetingCopilotEnterpriseAccess.value) {
      return const KorlixMeetingCopilotLockedPage();
    }

    return Semantics(
      label: KorlixMeetingCopilotRoute.accessibilityLabel,
      child: KeyedSubtree(
        key: KorlixMeetingCopilotRoute.screenKey,
        child: KorlixMeetingCopilotScreen(
          controller: _controller,
          korlixLogo: const AssetImage(
            'assets/meeting_copilot/korlix_logo.jpeg',
          ),
          novaPortrait: const AssetImage(
            'assets/meeting_copilot/nova_canonical.webp',
          ),
        ),
      ),
    );
  }
}

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_email_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Korlix Agent Email UI contract', () {
    test('registers 17 client routes and 2 server-only routes', () {
      expect(
        KorlixAgentEmailApiContract.authenticatedClientRoutes,
        hasLength(17),
      );

      expect(KorlixAgentEmailApiContract.serverOnlyRoutes, hasLength(2));

      final clientRoutes = KorlixAgentEmailApiContract.authenticatedClientRoutes
          .map((route) => '${route.method} ${route.template}')
          .toSet();

      final serverRoutes = KorlixAgentEmailApiContract.serverOnlyRoutes
          .map((route) => '${route.method} ${route.template}')
          .toSet();

      expect(clientRoutes.intersection(serverRoutes), isEmpty);
    });

    test('resolves all route IDs safely', () {
      for (final route
          in KorlixAgentEmailApiContract.authenticatedClientRoutes) {
        final resolved = KorlixAgentEmailApiContract.resolve(
          route.template,
          agentId: 'nova agent',
          recipientId: 'recipient/one',
          messageId: 'message/one',
          ruleId: 'rule/one',
        );

        expect(resolved, startsWith('/'));

        expect(resolved, isNot(contains(':agentId')));

        expect(resolved, isNot(contains(':recipientId')));

        expect(resolved, isNot(contains(':messageId')));

        expect(resolved, isNot(contains(':ruleId')));
      }
    });

    test('allows Agent Email only for an authorized custom Agent', () {
      const authorized = KorlixLiveConvoAgent(
        id: 'nova',
        name: 'Nova',
        description: 'Authorized KORLIX custom Agent.',
        iconName: 'smart_toy',
        accentHex: '21D4F4',
        mission: 'Assist approved KORLIX contacts.',
        toolIds: <String>[
          'general_chat',
          'memory',
          'agent_training',
          'agent_email',
        ],
        isCustom: true,
      );

      const missingTool = KorlixLiveConvoAgent(
        id: 'nova_without_email',
        name: 'Nova',
        description: 'Custom Agent without email permission.',
        iconName: 'smart_toy',
        accentHex: '21D4F4',
        mission: 'Assist approved KORLIX contacts.',
        toolIds: <String>['general_chat', 'memory', 'agent_training'],
        isCustom: true,
      );

      const builtIn = KorlixLiveConvoAgent(
        id: 'general',
        name: 'General Korlix',
        description: 'Built-in KORLIX Agent.',
        iconName: 'auto_awesome',
        accentHex: '21D4F4',
        mission: 'General assistance.',
        toolIds: <String>['general_chat', 'agent_email'],
      );

      expect(KorlixAgentEmailAccess.canOpen(authorized), isTrue);

      expect(KorlixAgentEmailAccess.canOpen(missingTool), isFalse);

      expect(KorlixAgentEmailAccess.canOpen(builtIn), isFalse);
    });

    test('preserves nonce and server-only boundaries', () {
      expect(KorlixAgentEmailApiContract.requiresSharedApprovalNonce, isTrue);

      expect(
        KorlixAgentEmailApiContract.approvalNonceReturnedByServer,
        isFalse,
      );

      expect(KorlixAgentEmailApiContract.clientCanCallResendWebhook, isFalse);

      expect(KorlixAgentEmailApiContract.clientCanRunAutopilot, isFalse);

      final clientTemplates = KorlixAgentEmailApiContract
          .authenticatedClientRoutes
          .map((route) => route.template);

      expect(
        clientTemplates,
        isNot(contains(KorlixAgentEmailApiContract.resendWebhookTemplate)),
      );

      expect(
        clientTemplates,
        isNot(contains(KorlixAgentEmailApiContract.autopilotRunTemplate)),
      );
    });
  });
}

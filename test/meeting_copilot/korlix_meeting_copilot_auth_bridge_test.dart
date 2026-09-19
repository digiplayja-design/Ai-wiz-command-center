import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/korlix_meeting_copilot_auth_bridge.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';

void main() {
  group('K135Z B4A Meeting Copilot protected route', () {
    test('recognizes the exact hash route', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse('https://example.test/#/meeting-copilot'),
      );

      expect(route, KorlixMeetingCopilotRoute.routeName);
    });

    test('recognizes the hash route with query data', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse(
          'https://example.test/#/meeting-copilot?source=investor-demo',
        ),
      );

      expect(route, KorlixMeetingCopilotRoute.routeName);
    });

    test('recognizes the exact path route', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse('https://example.test/meeting-copilot'),
      );

      expect(route, KorlixMeetingCopilotRoute.routeName);
    });

    test('recognizes a trailing slash path route', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse('https://example.test/meeting-copilot/'),
      );

      expect(route, KorlixMeetingCopilotRoute.routeName);
    });

    test('recognizes the route below a hosted base path', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse('https://example.test/app/meeting-copilot'),
      );

      expect(route, KorlixMeetingCopilotRoute.routeName);
    });

    test('ignores unrelated application routes', () {
      final route = korlixMeetingCopilotRouteFromUri(
        Uri.parse('https://example.test/#/command-center'),
      );

      expect(route, isNull);
    });

    test('accepts only the approved pending route', () {
      expect(korlixIsAllowedPendingMeetingRoute('/meeting-copilot'), isTrue);
    });

    test('rejects arbitrary pending navigation values', () {
      expect(korlixIsAllowedPendingMeetingRoute('/admin'), isFalse);
    });
  });
}

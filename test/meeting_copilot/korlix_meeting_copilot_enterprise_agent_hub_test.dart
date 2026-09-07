import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String r(String p) => File(p).readAsStringSync();

String c(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String allMeeting() => Directory('lib/meeting_copilot')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n')
    .toLowerCase();

void main() {
  const m = 'lib/main.dart',
      l = 'lib/live_convo/korlix_live_convo_test_screen.dart',
      a = 'lib/live_convo/korlix_live_convo_agent_sheet.dart',
      q = 'lib/meeting_copilot/korlix_meeting_copilot_route.dart',
      x = 'lib/meeting_copilot/korlix_meeting_copilot_access.dart';

  test('enterprise access starts fail closed', () {
    final s = r(x);
    expect(s, contains('ValueNotifier<bool>(false)'));
    expect(s, contains("tokens.contains('enterprise')"));
    expect(s, isNot(contains("tokens.contains('pro')")));
    expect(s, isNot(contains("tokens.contains('ultra')")));
  });

  test('general command entry is removed', () {
    final s = r(m);
    expect(s, contains('K135Z_B4B_V11_GENERAL_COMMAND_ENTRY_REMOVED'));
    expect(s, isNot(contains("label: 'Meeting Copilot'")));
    expect(s, isNot(contains("label: 'Nova Meeting Copilot'")));
  });

  test('tier synchronizes shared access', () {
    final s = c(r(m));
    expect(s, contains('K135Z_B4B_V11_SYNC_SHARED_ENTERPRISE_STATE'));
    expect(s, contains('syncKorlixMeetingCopilotEnterpriseAccessFromTier'));
    expect(s, contains('_currentTier'));
  });

  test('tier passes into live convo', () {
    final s = c(r(m));
    expect(s, contains('meetingCopilotEnterpriseEnabled:'));
    expect(s, contains('korlixMeetingCopilotEnterpriseEnabled'));
    expect(s, contains('_currentTier'));
  });

  test('live convo passes into hub opener', () {
    final s = r(l);
    expect(c(s), contains('final bool meetingCopilotEnterpriseEnabled;'));
    expect(
      RegExp(r'widget\s*\.\s*meetingCopilotEnterpriseEnabled').hasMatch(s),
      isTrue,
    );
  });

  test('hub opener and sheet receive access', () {
    final s = c(r(a));
    expect(s, contains('bool meetingCopilotEnterpriseEnabled = false'));
    expect(s, contains('final bool meetingCopilotEnterpriseEnabled;'));
    expect(
      s,
      contains(
        'meetingCopilotEnterpriseEnabled: '
        'meetingCopilotEnterpriseEnabled',
      ),
    );
  });

  test('Nova card is in Agent Hub', () {
    final s = r(a);
    expect(
      s,
      contains(
        'K135Z_B4B_V11_'
        'AGENT_HUB_ENTERPRISE_CARD_BEGIN',
      ),
    );
    expect(s, contains('K135Z_B4B_V11_AGENT_HUB_CARD_SLOT'));
    expect(s, contains('NOVA MEETING COPILOT'));
    expect(
      s,
      contains(
        'assets/meeting_copilot/'
        'nova_canonical.webp',
      ),
    );
  });

  test('non enterprise state is visibly locked', () {
    final s = r(a);
    expect(s, contains('ENTERPRISE ONLY'));
    expect(s, contains('Locked — upgrade to '));
    expect(s, contains('Enterprise for Nova'));
    expect(s, contains('Icons.lock_outline_rounded'));
    expect(s, contains('KorlixMeetingCopilotLockedPanel'));
  });

  test('direct route is independently gated', () {
    final s = r(q);
    expect(
      s,
      contains(
        'K135Z_B4B_V11_'
        'DIRECT_ROUTE_ENTERPRISE_GATE',
      ),
    );
    expect(
      RegExp(
        r'!\s*kKorlixMeetingCopilotEnterpriseAccess'
        r'\s*\.\s*value',
      ).hasMatch(s),
      isTrue,
    );
    expect(s, contains('KorlixMeetingCopilotLockedPage'));
  });

  test('deep link and host mute contracts remain', () {
    final s = r(m);
    final z = allMeeting();

    expect(s, contains('K135Z_B4A'));
    expect(s, contains('KorlixMeetingCopilotRoute.routeName'));
    expect(z, contains('muted'));
    expect(z, contains('host'));
  });
}

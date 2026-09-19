import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/live_convo/korlix_live_convo_test_screen.dart';
import '../../lib/meeting_copilot/korlix_meeting_copilot_access.dart';
Map<String, String> _headers() => const <String, String>{};
String _read(String p) => File(p).readAsStringSync();
void main() {
  test('Gate5 Live Convo keeps K136S IO and defaults Copilot closed', () {
    const screen = KorlixLiveConvoTestScreen(backendBaseUrl: 'https://example.test',
      headersBuilder: _headers, characterId: 'nova', language: 'English');
    expect(screen.meetingCopilotEnterpriseEnabled, isFalse);
    expect(screen.k136sIo, isA<K136sLiveConvoIo>());
  });
  test('Gate5 forwards Enterprise without replacing K136S lifecycle', () {
    const screen = KorlixLiveConvoTestScreen(backendBaseUrl: 'https://example.test',
      headersBuilder: _headers, characterId: 'nova', language: 'English',
      meetingCopilotEnterpriseEnabled: true);
    expect(screen.meetingCopilotEnterpriseEnabled, isTrue);
    final source = _read('lib/live_convo/korlix_live_convo_test_screen.dart');
    for (final retained in <String>['meetingCopilotEnterpriseEnabled: widget.meetingCopilotEnterpriseEnabled',
      'K136sLearningOverlay', '_k136sCurrentAttempt', '_k136sRouteTranscript', '_k136sControlsLocked',
      'captureForLiveDocs: !handledAsVoiceApproval && !handledAsLearning']) {
      expect(source, contains(retained), reason: retained);
    }
  });
  test('Gate5 main has one protected route and synchronizes access', () {
    final source = _read('lib/main.dart');
    expect(RegExp(r'KorlixMeetingCopilotRoute.routeName\s*:').allMatches(source).length, 1);
    expect(source, contains('kKorlixMeetingCopilotAuthObserver'));
    expect(source, contains('syncKorlixMeetingCopilotEnterpriseAccessFromTier(_currentTier)'));
    expect(source, contains('korlixMeetingCopilotEnterpriseEnabled(_currentTier)'));
    expect(source, isNot(contains("label: 'Nova Meeting Copilot'")));
  });
  test('Gate5 Agent Hub has canonical card and denied state', () {
    final source = _read('lib/live_convo/korlix_live_convo_agent_sheet.dart');
    expect(source, contains('K135Z_B4B_V11_AGENT_HUB_CARD_SLOT'));
    expect(source, contains('KorlixMeetingCopilotLockedPanel'));
    expect(source, contains('assets/meeting_copilot/nova_canonical.webp'));
  });
  test('Gate5 canonical assets are declared once and exist', () {
    final manifest = _read('pubspec.yaml');
    for (final p in <String>['assets/meeting_copilot/korlix_logo.jpeg', 'assets/meeting_copilot/nova_canonical.webp']) {
      expect(p.allMatches(manifest).length, 1); expect(File(p).existsSync(), isTrue);
    }
  });
  test('Gate5 client gate rejects non Enterprise tiers', () {
    for (final tier in <String>['basic', 'pro', 'ultra', 'not_enterprise']) {
      expect(korlixMeetingCopilotEnterpriseEnabled(tier), isFalse);
    }
    expect(korlixMeetingCopilotEnterpriseEnabled('enterprise'), isTrue);
  });
}

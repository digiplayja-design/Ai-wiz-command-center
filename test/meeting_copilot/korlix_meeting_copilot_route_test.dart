import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/main.dart' as app;
import '../../lib/meeting_copilot/korlix_meeting_copilot_route.dart';

void main() {
  test('Meeting Copilot route name is stable', () {
    expect(KorlixMeetingCopilotRoute.routeName, '/meeting-copilot');
  });

  test('KORLIX and Nova use separate canonical asset paths', () {
    expect(
      KorlixMeetingCopilotAssets.korlixLogo,
      'assets/meeting_copilot/korlix_logo.jpeg',
    );
    expect(
      KorlixMeetingCopilotAssets.novaPortrait,
      'assets/meeting_copilot/nova_canonical.webp',
    );
    expect(
      KorlixMeetingCopilotAssets.korlixLogo,
      isNot(KorlixMeetingCopilotAssets.novaPortrait),
    );
  });

  test('main MaterialApp registers the Meeting Copilot named route', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains("import 'meeting_copilot/korlix_meeting_copilot_route.dart';"),
    );
    expect(source, contains('KorlixMeetingCopilotRoute.routeName:'));
    expect(source, contains('const KorlixMeetingCopilotRoute()'));
  });

  test('pubspec declares both exact Meeting Copilot assets', () {
    final source = File('pubspec.yaml').readAsStringSync();
    expect(source, contains('assets/meeting_copilot/korlix_logo.jpeg'));
    expect(source, contains('assets/meeting_copilot/nova_canonical.webp'));
  });

  test('controller-aware route and app entrypoint compile together', () {
    const route = KorlixMeetingCopilotRoute();
    expect(route, isA<StatefulWidget>());
    expect(
      KorlixMeetingCopilotRoute.accessibilityLabel.toLowerCase(),
      contains('muted by default'),
    );
    expect(app.main, isA<Function>());
  });
}

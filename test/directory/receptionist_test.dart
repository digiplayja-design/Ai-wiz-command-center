import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/directory/directory_client.dart';
import 'package:ai_wiz_command_center/directory/receptionist_screen.dart';

Map<String, dynamic> fixture() => {
  'version': 1,
  'business_name': 'Fixture Services',
  'published': true,
  'setupStatus': 'connect_phone',
  'settings': {
    'enabled': false,
    'booking_enabled': false,
    'processing_consent': true,
    'monthly_minutes': 120,
    'max_call_minutes': 5,
    'voice': 'coral',
    'event_ids': [],
  },
  'events': [],
  'voices': [
    {'id': 'coral', 'name': 'Coral · warm'},
  ],
  'calls': [],
  'used_seconds': 0,
};
Future<void> reveal(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 35; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
  }
  throw StateError('Control was not reachable');
}

void main() {
  testWidgets(
    'Enterprise requirement is shown without signing out of the free Directory',
    (tester) async {
      var signedOut = false;
      final client = DirectoryClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (_) async => http.Response(
            '{"error":"AI Receptionist requires Enterprise."}',
            402,
          ),
        ),
      )..onSignedOut = () => signedOut = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ReceptionistScreen(client: client, businessId: 'fixture'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Available with Enterprise'), findsOneWidget);
      expect(signedOut, false);
      expect(client.sessionChanged, false);
      client.dispose();
    },
  );
  testWidgets(
    'small phone setup stays readable and a test answer uses the preview route only',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <String>[];
      final client = DirectoryClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts.add(r.url.path);
            expect(jsonDecode(r.body)['processing_consent'], true);
            return http.Response(
              '{"reply":"We offer fixture services.","preview":true}',
              200,
            );
          }
          return http.Response(jsonEncode(fixture()), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceptionistScreen(client: client, businessId: 'fixture'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Phone connection needed'), findsOneWidget);
      final question = find.widgetWithText(TextField, 'Ask as a customer');
      await reveal(tester, question);
      await tester.enterText(question, 'What services do you offer?');
      final send = find.text('Test answer');
      await reveal(tester, send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.text('We offer fixture services.'), findsOneWidget);
      expect(posts, ['/api/directory/owner/fixture/receptionist/preview']);
      expect(tester.takeException(), isNull);
      client.dispose();
    },
  );
  testWidgets(
    'unapproved processing cannot start a preview and credentials never appear in setup',
    (tester) async {
      final d = fixture();
      (d['settings'] as Map)['processing_consent'] = false;
      final client = DirectoryClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((_) async => http.Response(jsonEncode(d), 200)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceptionistScreen(client: client, businessId: 'fixture'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Test answer');
      await reveal(tester, button);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.text('API key'), findsNothing);
      client.dispose();
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/directory/directory_client.dart';
import 'package:ai_wiz_command_center/directory/directory_screen.dart';

String token(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': user, 'session_id': 'session-$user'}))).replaceAll('=', '')}.signature';
void main() {
  testWidgets(
    'Passport shortcut opens the existing business without creating a duplicate',
    (tester) async {
      final calls = <String>[];
      final business = {
        'id': 'existing-business',
        'owner_id': 'owner',
        'slug': 'existing-business',
        'draft': {'name': 'Fixture Shop', 'category': 'Other'},
        'state': 'draft',
        'verification_state': 'none',
        'version': 1,
      };
      final client = DirectoryClient(
        backendBaseUrl: 'https://backend.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/me')
                  ? {
                      'businesses': [business],
                      'categories': ['Other'],
                    }
                  : {'business': business, 'assets': []},
            ),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: DirectoryScreen(client: client, passportMode: true)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Business Passport'), findsOneWidget);
      expect(find.text('My Business Passports'), findsOneWidget);
      expect(find.text('YOUR BUSINESS PASSPORT'), findsOneWidget);
      expect(calls, [
        'GET /api/directory/me',
        'GET /api/directory/owner/existing-business',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    },
  );
  testWidgets(
    'Passport creation and receptionist selection have distinct phone-sized screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = DirectoryClient(
        backendBaseUrl: 'https://backend.test',
        headersBuilder: () => {},
        client: MockClient(
          (r) async =>
              http.Response('{"businesses":[],"categories":["Other"]}', 200),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: DirectoryScreen(client: client, passportMode: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('FREE BUSINESS PASSPORT'), findsOneWidget);
      await tester.tap(find.text('Create Business Passport — free'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Create your Business Passport — free'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryScreen(client: client, receptionistMode: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'AI Receptionist'), findsOneWidget);
      expect(find.text('ENTERPRISE AI RECEPTIONIST'), findsOneWidget);
      expect(
        find.textContaining('A connected phone line is required.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    },
  );
  test('client rejects a response arriving after account switch', () async {
    var user = 'a';
    final revision = ValueNotifier(0), pending = Completer<http.Response>();
    final client = DirectoryClient(
      backendBaseUrl: 'https://backend.test',
      headersBuilder: () => {'Authorization': 'Bearer ${token(user)}'},
      sessionChanges: revision,
      client: MockClient((r) => pending.future),
    );
    final response = client.request('GET', '/me');
    final expectation = expectLater(
      response,
      throwsA(isA<DirectoryException>()),
    );
    user = 'b';
    revision.value++;
    pending.complete(http.Response('{"businesses":[{"owner":"a"}]}', 200));
    await expectation;
    client.dispose();
    revision.dispose();
  });
  testWidgets('free directory dashboard loads without any plan entitlement', (
    tester,
  ) async {
    final client = DirectoryClient(
      backendBaseUrl: 'https://backend.test',
      headersBuilder: () => {},
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'businesses': [],
            'isAdmin': false,
            'paymentsReady': false,
            'categories': ['Other'],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DirectoryScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Add business — free'), findsOneWidget);
    expect(find.text('My Businesses'), findsOneWidget);
    expect(find.text('Directory review desk'), findsNothing);
    client.dispose();
  });
  testWidgets('owner sees listing and verification as separate states', (
    tester,
  ) async {
    final client = DirectoryClient(
      backendBaseUrl: 'https://backend.test',
      headersBuilder: () => {},
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'businesses': [
              {
                'id': 'b',
                'draft': {'name': 'Fixture Shop'},
                'state': 'published',
                'verification_state': 'pending',
              },
            ],
            'isAdmin': false,
            'categories': ['Other'],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DirectoryScreen(client: client)));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Free listing: Live in the directory\nOptional badge: Application awaiting review',
      ),
      findsOneWidget,
    );
    client.dispose();
  });
  testWidgets('phone layout and creation form render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = DirectoryClient(
      backendBaseUrl: 'https://backend.test',
      headersBuilder: () => {},
      client: MockClient(
        (r) async =>
            http.Response('{"businesses":[],"categories":["Other"]}', 200),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DirectoryScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add business — free'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add your business — free'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    client.dispose();
  });
  testWidgets('signout closes private forms and clears owner information', (
    tester,
  ) async {
    var user = 'a';
    final revision = ValueNotifier(0);
    final client = DirectoryClient(
      backendBaseUrl: 'https://backend.test',
      sessionChanges: revision,
      headersBuilder: () => {'Authorization': 'Bearer ${token(user)}'},
      client: MockClient(
        (r) async =>
            http.Response('{"businesses":[],"categories":["Other"]}', 200),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DirectoryScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add business — free'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    user = 'b';
    revision.value++;
    await tester.pumpAndSettle();
    expect(
      find.text('Sign in again to manage your businesses.'),
      findsOneWidget,
    );
    expect(find.text('Add your business — free'), findsNothing);
    client.dispose();
    revision.dispose();
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Local fixtures only; these tokens are never sent to an authentication service.
String token({
  String user = 'owner-a',
  String session = 'session-a',
  String issuer = 'https://auth.example.test',
  int revision = 1,
  Map<String, Object?> overrides = const {},
}) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': issuer, 'sub': user, 'session_id': session, 'iat': revision, ...overrides}))).replaceAll('=', '')}.signature$revision';

class Revision extends ValueNotifier<int> {
  Revision() : super(0);
  bool get observed => hasListeners;
}

class SessionFixture {
  SessionFixture() {
    owner = PictureStudioSession(
      headersBuilder: headers,
      sessionChanges: revisions,
    );
  }
  final revisions = Revision();
  String? access = token();
  late final PictureStudioSession owner;
  Map<String, String> headers() => {
    if (access != null) 'Authorization': 'Bearer $access',
  };
  void change(String? next, {bool notify = true}) {
    access = next;
    if (notify) revisions.value++;
  }

  void dispose() {
    owner.dispose();
    revisions.dispose();
  }
}

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAE0lEQVQYlWNQnPb5Pz7MMDIUAABwQapBFKvYYAAAAABJRU5ErkJggg==',
);
PlatformFile photo() =>
    PlatformFile(name: 'private.png', size: png.length, bytes: png);
http.Response photoResponse() => http.Response(
  jsonEncode({'imageDataUrl': 'data:image/png;base64,${base64Encode(png)}'}),
  200,
);

void main() {
  test('same login survives token refresh during an edit', () async {
    final f = SessionFixture();
    addTearDown(f.dispose);
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    var notifications = 0;
    f.owner.addListener(() => notifications++);
    final client = PictureStudioClient(
      backendBaseUrl: 'https://pictures.example.test',
      headersBuilder: f.headers,
      isSessionCurrent: () => f.owner.isCurrent,
      client: MockClient((request) {
        expect(request.headers['authorization'], 'Bearer ${token()}');
        sent.complete();
        return response.future;
      }),
    );
    addTearDown(client.dispose);
    final edit = client.improve(photo(), const PictureEditOptions());
    await sent.future;
    f.change(token(revision: 2, overrides: {'email': 'updated@example.test'}));
    response.complete(photoResponse());
    expect((await edit).bytes, png);
    expect(f.owner.isCurrent, isTrue);
    expect(notifications, 0);
  });

  for (final change in <String, String?>{
    'logout': null,
    'another user': token(user: 'owner-b'),
    'another login': token(session: 'session-b'),
    'another issuer': token(issuer: 'https://other.example.test'),
  }.entries) {
    test('${change.key} invalidates and never reactivates photo state', () {
      final f = SessionFixture();
      addTearDown(f.dispose);
      var notifications = 0;
      f.owner.addListener(() => notifications++);
      expect(f.revisions.observed, isTrue);
      f.change(change.value);
      expect(f.owner.isCurrent, isFalse);
      expect(notifications, 1);
      expect(f.revisions.observed, isFalse);
      f.change(token());
      expect(f.owner.isCurrent, isFalse);
      expect(notifications, 1);
    });
  }

  test(
    'an edit finishing after account switch cannot return private bytes',
    () async {
      final f = SessionFixture();
      addTearDown(f.dispose);
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final client = PictureStudioClient(
        backendBaseUrl: 'https://pictures.example.test',
        headersBuilder: f.headers,
        isSessionCurrent: () => f.owner.isCurrent,
        client: MockClient((_) {
          sent.complete();
          return response.future;
        }),
      );
      addTearDown(client.dispose);
      final edit = client.improve(photo(), const PictureEditOptions());
      final rejected = expectLater(
        edit,
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Your session changed'),
          ),
        ),
      );
      await sent.future;
      f.change(token(user: 'owner-b'));
      f.change(token());
      response.complete(photoResponse());
      await rejected;
    },
  );

  test('missing or malformed identity cannot own a photo workspace', () {
    for (final access in <String?>[
      null,
      '',
      'opaque',
      'a.%%.c',
      token(overrides: {'sub': null}),
      token(overrides: {'session_id': ''}),
      token(overrides: {'iss': <String>[]}),
    ]) {
      final revisions = Revision();
      final owner = PictureStudioSession(
        headersBuilder: () => {
          if (access != null) 'Authorization': 'Bearer $access',
        },
        sessionChanges: revisions,
      );
      expect(owner.isCurrent, isFalse);
      expect(revisions.observed, isFalse);
      owner.dispose();
      revisions.dispose();
    }
  });

  test(
    'silent change is caught and disposal removes pending notifications',
    () async {
      final f = SessionFixture();
      var notifications = 0;
      f.owner.addListener(() => notifications++);
      f.change(token(user: 'owner-b'), notify: false);
      expect(f.owner.isCurrent, isFalse);
      f.dispose();
      await Future<void>.value();
      expect(notifications, 0);
      expect(f.owner.isCurrent, isFalse);
    },
  );

  testWidgets('auth change removes private photo route content', (
    tester,
  ) async {
    final f = SessionFixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: f.owner,
          builder: (_, _) => f.owner.isCurrent
              ? Image.memory(png, key: const Key('private-photo'))
              : const Text('Your session changed. Sign in again.'),
        ),
      ),
    );
    expect(find.byKey(const Key('private-photo')), findsOneWidget);
    f.change(null);
    await tester.pump();
    expect(find.byKey(const Key('private-photo')), findsNothing);
    expect(find.text('Your session changed. Sign in again.'), findsOneWidget);
    f.change(token());
    await tester.pump();
    expect(find.byKey(const Key('private-photo')), findsNothing);
  });
}

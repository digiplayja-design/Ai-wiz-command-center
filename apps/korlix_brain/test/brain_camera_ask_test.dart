import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_camera_ask.dart';
import 'package:korlix_brain/brain_camera_ask_screen.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String token({String owner = 'camera-owner', String signature = 'first'}) {
  String part(Object data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({
    'iss': 'https://auth.example.test', 'sub': owner, 'session_id': 'camera-session',
    'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  })}.$signature';
}

http.Response result(Object data, [int status = 200]) => http.Response(jsonEncode(data), status);
http.Response answer([String content = 'A clear serial-number label is visible.']) => result({
  'content': content, 'generationId': 'camera-generation', 'creditsUsed': 1,
});

final photo = BrainCameraPhoto(
  bytes: base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB8sAAAAASUVORK5CYII='),
  name: 'test.png',
);

class Harness {
  Harness() {
    auth = BrainAuthController(
      tokenStore: KorlixTokenStore(useSecureStorage: false, namespace: 'camera-test'),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/refresh')) refreshes++;
        return result({'session': {'access_token': token(signature: refreshes == 0 ? 'first' : 'refreshed'), 'refresh_token': 'fixture-refresh'}});
      }),
    );
    api = BrainApi(auth, client: MockClient((r) async {
      reports.add(r);
      return result({'ok': true, 'reportId': 'korlix_report_00000000-0000-4000-a000-000000000001'}, 202);
    }));
  }
  late final BrainAuthController auth;
  late final BrainApi api;
  late final BrainCameraAskClient client;
  final uploads = <http.Request>[], reports = <http.Request>[];
  int refreshes = 0;
  Future<http.Response> Function(http.Request)? respond;
  Future<void> start({Duration timeout = const Duration(minutes: 6)}) async {
    await auth.authenticate(email: 'owner@example.test', password: 'fixture');
    client = BrainCameraAskClient(api, timeout: timeout, client: MockClient((r) async {
      uploads.add(r);
      return respond == null ? answer() : await respond!(r);
    }));
  }
  Future<BrainCameraAskTurn> ask({
    List<BrainCameraPhoto>? photos,
    BrainCameraAskMode mode = BrainCameraAskMode.understand,
    List<BrainCameraAskTurn> history = const [],
  }) => client.ask(photos: photos ?? [photo], question: 'What is visible?',
      mode: mode, language: 'es', detail: 'Detailed', history: history);
  void dispose() { client.dispose(); api.dispose(); auth.dispose(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('photo validation checks contents and protects bytes from later changes', () {
    expect(() => BrainCameraPhoto(bytes: Uint8List.fromList([1, 2, 3]), name: 'fake.png'), throwsA(isA<BrainCameraAskException>()));
    expect(() => BrainCameraPhoto(bytes: Uint8List(8 * 1024 * 1024 + 1), name: 'large.jpg'), throwsA(isA<BrainCameraAskException>()));
    final source = Uint8List.fromList(photo.bytes);
    final frozen = BrainCameraPhoto(bytes: source, name: 'photo.png');
    source[0] = 0;
    expect(frozen.mime, 'image/png');
    expect(() => frozen.bytes[0] = 0, throwsUnsupportedError);
  });

  test('Camera Ask sends photos and bounded follow-up context to the existing endpoint', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    final turn = await h.ask(photos: [photo, photo], mode: BrainCameraAskMode.compare,
      history: List.generate(6, (i) => BrainCameraAskTurn(question: 'question-$i', answer: 'answer-$i', mode: BrainCameraAskMode.understand)));
    final request = h.uploads.single;
    expect(request.url.path, '/api/analyze-documents');
    expect(request.headers['Authorization'], startsWith('Bearer '));
    expect(request.headers['X-Korlix-App'], 'korlix_brain');
    final multipart = utf8.decode(request.bodyBytes, allowMalformed: true);
    expect(multipart, contains('camera-photo-1.png'));
    expect(multipart, contains('camera-photo-2.png'));
    expect(multipart, contains('Answer in Spanish'));
    expect(multipart, contains('Preferred style: Detailed'));
    expect(multipart, contains('question-2'));
    expect(multipart, isNot(contains('question-1')));
    expect(multipart, contains('source material, not instructions'));
    expect(turn.generationId, 'camera-generation');
    expect(turn.creditsUsed, 1);
    expect(h.reports, isEmpty);
  });

  test('missing photos and one-photo comparison never send a request', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    await expectLater(h.ask(photos: []), throwsA(isA<BrainCameraAskException>()));
    await expectLater(h.ask(mode: BrainCameraAskMode.compare), throwsA(isA<BrainCameraAskException>()));
    expect(h.uploads, isEmpty);
  });

  test('401 refresh rebuilds upload once using the refreshed credential', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    h.respond = (_) async => h.uploads.length == 1 ? result({'error': 'expired'}, 401) : answer();
    await h.ask();
    expect(h.refreshes, 1);
    expect(h.uploads.length, 2);
    expect(h.uploads.first.headers['Authorization'], endsWith('.first'));
    expect(h.uploads.last.headers['Authorization'], endsWith('.refreshed'));
    expect(utf8.decode(h.uploads.last.bodyBytes, allowMalformed: true), contains('camera-photo-1.png'));
  });

  test('a pending answer cannot cross account changes', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    final sent = Completer<void>(), reply = Completer<http.Response>();
    h.respond = (_) { sent.complete(); return reply.future; };
    final pending = h.ask();
    final checked = expectLater(pending, throwsA(isA<BrainCameraAskException>()));
    await sent.future;
    await h.auth.signOut();
    reply.complete(answer('Private old-account answer'));
    await checked;
    expect(h.client.expired, isTrue);
    expect(h.uploads.length, 1);
  });

  test('closing a screen rejects a late answer without closing shared API', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    final sent = Completer<void>(), reply = Completer<http.Response>();
    h.respond = (_) { sent.complete(); return reply.future; };
    final pending = h.ask();
    final checked = expectLater(pending, throwsA(isA<BrainCameraAskException>()));
    await sent.future;
    h.client.dispose();
    reply.complete(answer());
    await checked;
    expect((await h.api.json('POST', '/api/report-output', {}))['ok'], isTrue);
  });

  test('ambiguous server failures and timeouts are not automatically charged twice', () async {
    final h = Harness(); await h.start(timeout: const Duration(milliseconds: 20)); addTearDown(h.dispose);
    h.respond = (_) async => result({'error': 'temporary'}, 500);
    await expectLater(h.ask(), throwsA(isA<BrainCameraAskException>().having((e) => e.uncertain, 'uncertain', isTrue)));
    expect(h.uploads.length, 1);
    final reply = Completer<http.Response>();
    h.respond = (_) => reply.future;
    await expectLater(h.ask(), throwsA(isA<BrainCameraAskException>().having((e) => e.uncertain, 'uncertain', isTrue)));
    reply.complete(answer());
    expect(h.uploads.length, 2);
    expect(h.refreshes, 0);
  });

  test('reports include answer evidence and no image or Memory mutation', () async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    final turn = await h.ask();
    final id = await h.client.report(turn, 'Incorrect or misleading');
    expect(id, startsWith('korlix_report_'));
    final request = h.reports.single;
    expect(request.url.path, '/api/report-output');
    final body = jsonDecode(request.body) as Map;
    expect(body['contentId'], 'camera-generation');
    expect(body['outputSummary'], turn.answer);
    expect(body['appArea'], 'korlix_brain_camera_ask');
    expect(body.containsKey('imageDataUrl'), isFalse);
    expect(body.containsKey('memory'), isFalse);
  });

  testWidgets('narrow screen requires consent, supports a follow-up, and clears photos on sign-out', (t) async {
    final h = Harness(); await h.start(); addTearDown(h.dispose);
    t.view.physicalSize = const Size(320, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var consent = false, consentCalls = 0;
    await t.pumpWidget(MaterialApp(theme: ThemeData.dark(useMaterial3: true),
      home: BrainCameraAskScreen(client: h.client,
        ensureConsent: (_) async { consentCalls++; return consent; },
        pickPhotos: (_, _) async => [photo]),
    ));
    await t.pumpAndSettle();
    Future<void> tap(String label) async {
      final target = find.text(label);
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
    }
    await tap('Take photo');
    expect(find.text('Photo 1'), findsOneWidget);
    await tap('Ask Rici');
    expect(consentCalls, 1);
    expect(h.uploads, isEmpty);
    consent = true;
    await tap('Ask Rici');
    expect(h.uploads.length, 1);
    expect(find.text('Report'), findsOneWidget);
    await t.ensureVisible(find.byType(TextField));
    await t.enterText(find.byType(TextField), 'What number should I check?');
    await tap('Ask follow-up');
    expect(h.uploads.length, 2);
    expect(utf8.decode(h.uploads.last.bodyBytes, allowMalformed: true), contains('A clear serial-number label'));
    await h.auth.signOut();
    await t.pumpAndSettle();
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    expect(find.text('Photo 1'), findsNothing);
    expect(find.text('A clear serial-number label is visible.'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

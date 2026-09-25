import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'funnel_studio_test.dart' as studio;
import 'funnel_campaigns_test.dart' as campaigns;

// Synthetic local tokens: no real credential or external auth request.
String token({
  String user = 'owner-a',
  String session = 'session-a',
  String issuer = 'https://example.com/auth/v1',
  int revision = 1,
  Map<String, dynamic> extra = const {},
}) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': issuer, 'sub': user, 'session_id': session, 'iat': revision, 'exp': revision + 3600, ...extra}))).replaceAll('=', '')}.signature$revision';

http.Response reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

final changed = throwsA(
  isA<FunnelException>()
      .having((e) => e.status, 'status', 401)
      .having(
        (e) => e.message,
        'message',
        'Sign in again and reopen Funnel Studio to continue.',
      ),
);

class SessionRevision extends ValueNotifier<int> {
  SessionRevision() : super(0);
  bool get observed => hasListeners;
}

class SessionHarness {
  SessionHarness({
    FutureOr<http.Response> Function(http.Request)? handler,
    String? initial,
    bool signedOut = false,
  }) {
    access = signedOut ? null : (initial ?? token());
    client = FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {
        if (access != null) 'Authorization': 'Bearer $access',
      },
      sessionChanges: revisions,
      client: MockClient((r) async {
        calls.add(r);
        return handler == null ? reply({'ok': true}) : handler(r);
      }),
    );
  }
  final revisions = SessionRevision();
  final calls = <http.Request>[];
  late final FunnelClient client;
  String? access;
  void change(String? next, {bool notify = true}) {
    access = next;
    if (notify) revisions.value++;
  }

  void dispose() {
    client.dispose();
    revisions.dispose();
  }
}

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Map<String, dynamic> saved() => {
  'funnels': [
    {...studio.fixture(), 'name': 'Private original page'},
  ],
  'ai_ready': true,
};

Future<void> mount(WidgetTester t, SessionHarness h) async {
  await t.binding.setSurfaceSize(const Size(1400, 1100));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: FunnelScreen(client: h.client)));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final e in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/${e.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test(
    'K197 same-session refresh sends fresh credentials without invalidation',
    () async {
      final h = SessionHarness();
      addTearDown(h.dispose);
      var denied = 0;
      h.client.addAccessDeniedListener(() => denied++);
      await h.client.request('GET', '');
      final fresh = token(
        revision: 2,
        extra: {
          'email': 'new@example.com',
          'user_metadata': {'tier': 'enterprise'},
        },
      );
      h.change(fresh);
      await h.client.request('PUT', '/f', body: {'version': 1});
      expect(denied, 0);
      expect(h.client.sessionChanged, isFalse);
      expect(h.calls.last.headers['authorization'], 'Bearer $fresh');
    },
  );

  for (final entry in <String, String?>{
    'sign-out': null,
    'different owner': token(user: 'owner-b'),
    'new login for same owner': token(session: 'session-b'),
    'different issuer': token(issuer: 'https://other.example/auth/v1'),
  }.entries) {
    test(
      'K197 ${entry.key} invalidates immediately and cannot reactivate the old client',
      () async {
        final h = SessionHarness();
        addTearDown(h.dispose);
        var legacy = 0, listener = 0;
        h.client.onAccessDenied = () => legacy++;
        h.client.addAccessDeniedListener(() => listener++);
        h.change(entry.value);
        expect(legacy, 1);
        expect(listener, 1);
        await expectLater(h.client.request('POST', '/f/publish'), changed);
        await expectLater(
          h.client.uploadImage('photo.png', Uint8List.fromList([1, 2])),
          changed,
        );
        h.change(token());
        await expectLater(h.client.request('GET', ''), changed);
        expect(h.calls, isEmpty);
        expect(legacy, 1);
        expect(listener, 1);
      },
    );
  }

  test(
    'K197 missing or malformed session claims block the first request',
    () async {
      for (final value in <String?>[
        null,
        '',
        'opaque',
        'a.%%.c',
        'a.W10.c',
        token(extra: {'sub': null}),
        token(extra: {'session_id': null}),
        token(extra: {'iss': []}),
        token(extra: {'session_id': ''}),
      ]) {
        final h = SessionHarness(initial: value, signedOut: value == null);
        await expectLater(h.client.request('GET', ''), changed);
        expect(h.calls, isEmpty);
        h.dispose();
      }
    },
  );

  test(
    'K197 scope is checked even when no session event is delivered',
    () async {
      final h = SessionHarness();
      addTearDown(h.dispose);
      h.change(token(user: 'other'), notify: false);
      await expectLater(
        h.client.request('POST', '/f/campaigns/create'),
        changed,
      );
      expect(h.calls, isEmpty);
    },
  );

  test(
    'K197 captured request headers cannot belong to a different session',
    () async {
      final revision = ValueNotifier<int>(0);
      var reads = 0, sends = 0;
      final c = FunnelClient(
        backendBaseUrl: 'https://example.com',
        sessionChanges: revision,
        headersBuilder: () => {
          'Authorization':
              'Bearer ${++reads == 2 ? token(user: 'other') : token()}',
        },
        client: MockClient((r) async {
          sends++;
          return reply({});
        }),
      );
      addTearDown(() {
        c.dispose();
        revision.dispose();
      });
      await expectLater(c.request('POST', '/f/publish'), changed);
      expect(sends, 0);
    },
  );

  for (final operation in ['GET', 'PUT', 'image upload']) {
    test(
      'K197 a pending $operation cannot return data after a session switch',
      () async {
        final pending = Completer<http.Response>(), started = Completer<void>();
        final h = SessionHarness(
          handler: (r) {
            started.complete();
            return pending.future;
          },
        );
        addTearDown(h.dispose);
        final future = operation == 'image upload'
            ? h.client.uploadImage('photo.png', Uint8List.fromList([1, 2]))
            : h.client.request(
                operation,
                '/f',
                body: operation == 'PUT' ? {'name': 'Private draft'} : null,
              );
        final check = expectLater(future, changed);
        await started.future;
        h.change(token(user: 'other'));
        pending.complete(reply({'private': 'old owner'}));
        await check;
        expect(h.calls.length, 1); // No automatic repeat of a committed write.
      },
    );
  }

  test(
    'K197 a pending read detects a silent scope change before returning',
    () async {
      final pending = Completer<http.Response>(), started = Completer<void>();
      final h = SessionHarness(
        handler: (r) {
          started.complete();
          return pending.future;
        },
      );
      addTearDown(h.dispose);
      final check = expectLater(h.client.request('GET', ''), changed);
      await started.future;
      h.change(null, notify: false);
      pending.complete(reply({'private': 'old owner'}));
      await check;
      expect(h.client.sessionChanged, isTrue);
    },
  );

  test(
    'K197 a stale network error cannot bypass the session boundary',
    () async {
      final pending = Completer<http.Response>(), started = Completer<void>();
      final h = SessionHarness(
        handler: (r) {
          started.complete();
          return pending.future;
        },
      );
      addTearDown(h.dispose);
      final check = expectLater(
        h.client.request('POST', '/f/publish'),
        changed,
      );
      await started.future;
      h.change(null);
      pending.completeError(http.ClientException('old network failure'));
      await check;
      expect(h.calls.length, 1);
    },
  );

  test('K197 disposed clients detach and block further requests', () async {
    final h = SessionHarness();
    var denied = 0;
    h.client.addAccessDeniedListener(() => denied++);
    expect(h.revisions.observed, isTrue);
    h.client.dispose();
    h.client.dispose();
    expect(h.revisions.observed, isFalse);
    h.change(null);
    await expectLater(
      h.client.request('GET', ''),
      throwsA(isA<FunnelException>()),
    );
    expect(denied, 0);
    expect(h.calls, isEmpty);
    h.revisions.dispose();
  });

  testWidgets('K197 token refresh preserves unsaved page edits', (t) async {
    final h = SessionHarness(handler: (_) => reply(saved()));
    addTearDown(h.dispose);
    await mount(t, h);
    await tap(t, 'Open studio');
    final name = find.byType(TextFormField).first;
    await t.enterText(name, 'Unsaved work');
    await t.pump();
    final before = h.calls.length;
    h.change(token(revision: 2));
    await t.pumpAndSettle();
    expect(find.text('Unsaved work'), findsNWidgets(2));
    expect(find.text('Session changed'), findsNothing);
    expect(h.calls.length, before);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'K197 sign-out clears a pending publish confirmation without another request',
    (t) async {
      final h = SessionHarness(handler: (_) => reply(saved()));
      addTearDown(h.dispose);
      await mount(t, h);
      await tap(t, 'Open studio');
      await tap(t, 'Review & publish');
      final before = h.calls.length;
      expect(find.text('Publish this page?'), findsOneWidget);
      h.change(null);
      await t.pumpAndSettle();
      expect(find.text('Session changed'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Private original page'), findsNothing);
      expect(h.calls.length, before);
      expect(t.takeException(), isNull);
    },
  );

  for (final action in [
    'New campaign plan',
    'Review plan',
    'Results & reporting',
  ]) {
    testWidgets('K197 account change closes the child $action dialog', (
      t,
    ) async {
      final h = SessionHarness(
        handler: (r) {
          if (r.url.path.endsWith('/connection')) {
            return reply({'configured': false, 'connection': null});
          }
          if (r.url.path.endsWith('/campaigns')) {
            return reply({
              'campaigns': [campaigns.fixture()],
              'ai_ready': true,
            });
          }
          return reply(saved());
        },
      );
      addTearDown(h.dispose);
      await mount(t, h);
      await tap(t, 'Open studio');
      await tap(t, 'Ads workspace');
      await tap(t, action);
      expect(find.byType(AlertDialog), findsOneWidget);
      final before = h.calls.length;
      h.change(token(user: 'other'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Session changed'), findsOneWidget);
      expect(find.text('Autumn growth'), findsNothing);
      expect(h.calls.length, before);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'K197 opening with no session shows access loss without a build error',
    (t) async {
      final h = SessionHarness(signedOut: true);
      addTearDown(h.dispose);
      await mount(t, h);
      expect(find.text('Session changed'), findsOneWidget);
      expect(h.calls, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
}

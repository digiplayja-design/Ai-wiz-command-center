import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_brain/brain_api.dart';
import 'package:korlix_brain/brain_auth.dart';
import 'package:korlix_brain/brain_repository.dart';
import 'package:korlix_receipt_core/auth/korlix_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String token() {
  String part(Object data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'iss': 'https://auth.example.test', 'sub': 'brain-fixture', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.fixture';
}

http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
Map<String, dynamic> session() => {
  'session': {'access_token': token(), 'refresh_token': 'fixture-refresh'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  BrainAuthController auth(
    FutureOr<http.Response> Function(http.Request) handler,
  ) {
    final controller = BrainAuthController(
      client: MockClient((r) async => handler(r)),
      tokenStore: KorlixTokenStore(
        useSecureStorage: false,
        namespace: 'brain_test',
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'existing accounts sign in through the shared KORLIX endpoint',
    () async {
      late http.Request request;
      final a = auth((r) {
        request = r;
        return response(session());
      });
      expect(
        await a.authenticate(
          email: ' USER@example.test ',
          password: 'password',
        ),
        isTrue,
      );
      expect(request.url.path, '/api/auth/signin');
      final data = jsonDecode(request.body) as Map;
      expect(data['email'], 'user@example.test');
      expect(data['client_app'], 'korlix_brain');
      expect(a.headers()['Authorization'], startsWith('Bearer '));
    },
  );

  test(
    'duplicate signup does not create or persist a second session',
    () async {
      final a = auth(
        (r) => response({
          'code': 'KORLIX_ACCOUNT_EXISTS',
          'error': 'Already registered',
        }, 409),
      );
      await expectLater(
        a.authenticate(
          email: 'existing@example.test',
          password: 'password',
          signup: true,
        ),
        throwsA(
          isA<BrainAuthException>().having(
            (e) => e.existingAccount,
            'existing account',
            isTrue,
          ),
        ),
      );
      expect(a.session, isNull);
    },
  );

  test('late sign-in response cannot resurrect a signed-out account', () async {
    final sent = Completer<void>(), reply = Completer<http.Response>();
    final a = auth((r) {
      sent.complete();
      return reply.future;
    });
    final login = a.authenticate(
      email: 'user@example.test',
      password: 'password',
    );
    final check = expectLater(login, throwsA(anything));
    await sent.future;
    await a.signOut();
    reply.complete(response(session()));
    await check;
    expect(a.session, isNull);
  });

  test(
    'API ignores old-account responses and does not replay ambiguous writes',
    () async {
      final a = auth((r) => response(session()));
      await a.authenticate(email: 'user@example.test', password: 'password');
      final sent = Completer<void>(), reply = Completer<http.Response>();
      int count = 0;
      final api = BrainApi(
        a,
        client: MockClient((r) async {
          count++;
          sent.complete();
          return reply.future;
        }),
      );
      addTearDown(api.dispose);
      final write = api.json('POST', '/api/example', {'confirmed': true});
      final check = expectLater(write, throwsA(isA<BrainApiException>()));
      await sent.future;
      await a.signOut();
      reply.complete(response({'ok': true}));
      await check;
      expect(count, 1);
    },
  );

  test(
    'saving memory requires server acknowledgement and refuses duplicates',
    () async {
      final a = auth((r) => response(session()));
      await a.authenticate(email: 'user@example.test', password: 'password');
      final memory = <String, dynamic>{
        'id': 'one',
        'content': 'Office closes at four',
        'source': 'user_confirmed',
      };
      final saved = <Map<String, dynamic>>[];
      int posts = 0;
      final api = BrainApi(
        a,
        client: MockClient((r) async {
          if (r.method == 'GET' && r.url.path.endsWith('/memories')) {
            return response({'memories': saved});
          }
          if (r.method == 'GET') {
            return response({
              'agent': {
                'trainingInstructions': '',
                'persistenceConfigured': true,
              },
            });
          }
          posts++;
          expect((jsonDecode(r.body) as Map)['confirmed'], true);
          saved.add(memory);
          return response({'memory': memory}, 201);
        }),
      );
      addTearDown(api.dispose);
      final repo = BrainRepository(api);
      await repo.saveMemory('Office closes at four', 'Typed entry');
      expect(repo.memories.length, 1);
      await expectLater(
        repo.saveMemory('office closes at four', 'Typed entry'),
        throwsA(isA<BrainApiException>()),
      );
      expect(posts, 1);
    },
  );

  test(
    'training refuses to overwrite changes made in another KORLIX app',
    () async {
      final a = auth((r) => response(session()));
      await a.authenticate(email: 'user@example.test', password: 'password');
      int writes = 0;
      final api = BrainApi(
        a,
        client: MockClient((r) async {
          if (r.method != 'GET') writes++;
          return response({
            'agent': {
              'trainingInstructions': 'New version from another device',
            },
          });
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        BrainRepository(api).saveTraining('My replacement', 'Old version'),
        throwsA(isA<BrainApiException>()),
      );
      expect(writes, 0);
    },
  );

  test('failed save never enters the local saved-memory list', () async {
    final a = auth((r) => response(session()));
    await a.authenticate(email: 'user@example.test', password: 'password');
    final api = BrainApi(
      a,
      client: MockClient((r) async {
        if (r.method == 'POST') return response({'error': 'Unavailable'}, 503);
        return response(
          r.url.path.endsWith('/memories')
              ? {'memories': []}
              : {
                  'agent': {'trainingInstructions': ''},
                },
        );
      }),
    );
    addTearDown(api.dispose);
    final repo = BrainRepository(api);
    await expectLater(
      repo.saveMemory('Never pretend saved', 'Typed entry'),
      throwsA(isA<BrainApiException>()),
    );
    expect(repo.memories, isEmpty);
  });

  test(
    'delete verifies the selected memory and undo restores only that item',
    () async {
      final a = auth((r) => response(session()));
      await a.authenticate(email: 'user@example.test', password: 'password');
      final rows = <Map<String, dynamic>>[
        {'id': 'first', 'content': 'One'},
        {'id': 'second', 'content': 'Two'},
      ];
      final api = BrainApi(
        a,
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return response(
              r.url.path.endsWith('/memories')
                  ? {'memories': rows}
                  : {
                      'agent': {'trainingInstructions': ''},
                    },
            );
          }
          if (r.method == 'DELETE') {
            expect(r.url.path.endsWith('/first'), isTrue);
            expect((jsonDecode(r.body) as Map)['confirmed'], true);
            rows.removeWhere((m) => m['id'] == 'first');
            return response({'ok': true});
          }
          final body = jsonDecode(r.body) as Map;
          final memory = <String, dynamic>{
            'id': 'restored',
            'content': body['content'],
          };
          rows.add(memory);
          return response({'memory': memory}, 201);
        }),
      );
      addTearDown(api.dispose);
      final repo = BrainRepository(api);
      await repo.deleteMemory('first', 'One');
      expect(repo.memories.map((m) => m['content']), ['Two']);
      await repo.undo();
      expect(repo.memories.map((m) => m['content']), ['Two', 'One']);
      expect(repo.snapshot['canUndo'], false);
    },
  );

  test('PDF upload rebuilds multipart after a rejected token and refreshes once', () async {
    final original = token(), refreshed = '${token()}-refreshed';
    var refreshes = 0;
    final a = auth((r) {
      final refresh = r.url.path.endsWith('/refresh');
      if (refresh) refreshes++;
      return response({'session': {
        'access_token': refresh ? refreshed : original,
        'refresh_token': 'fixture-refresh',
      }});
    });
    await a.authenticate(email: 'user@example.test', password: 'password');
    final uploads = <http.Request>[];
    final api = BrainApi(a, client: MockClient((r) async {
      uploads.add(r);
      if (uploads.length == 1) return response({'error':'Expired access token'}, 401);
      return response({'requiresApproval': true, 'autoSaved': false,
        'sourceRetention': {'storedByKorlix': false}, 'suggestions': []});
    }));
    addTearDown(api.dispose);
    await api.analyze('memory', 'office.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7\nfixture')));
    expect(uploads, hasLength(2));
    expect(refreshes, 1);
    expect(uploads.first.headers['Authorization'], 'Bearer $original');
    expect(uploads.last.headers['Authorization'], 'Bearer $refreshed');
    for (final upload in uploads) {
      expect(upload.url.path, '/api/live-convo/agents/general/memory-files/analyze');
      expect(upload.headers['Content-Type'], startsWith('multipart/form-data;'));
      expect(upload.body, contains('filename="office.pdf"'));
      expect(upload.body, contains('%PDF-1.7'));
    }
  });

  test('ambiguous PDF failures are sanitized and never automatically replayed', () async {
    for (final failure in ['html', 'timeout', 'connection', 'bad_retention']) {
      final a = auth((_) => response(session()));
      await a.authenticate(email: 'user@example.test', password: 'password');
      var uploads = 0;
      final api = BrainApi(a, client: MockClient((_) async {
        uploads++;
        if (failure == 'timeout') throw TimeoutException('fixture timeout');
        if (failure == 'connection') throw http.ClientException('private server internals');
        if (failure == 'bad_retention') return response({
          'requiresApproval': true, 'autoSaved': false, 'sourceRetention': 'malformed',
        });
        return http.Response('<html>private server internals</html>', 503);
      }));
      addTearDown(api.dispose);
      await expectLater(api.analyze('training', 'office.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7'))),
        throwsA(isA<BrainApiException>().having((e) => e.message, 'safe message', isNot(contains('private server internals')))));
      expect(uploads, 1);
    }
  });

  test('PDF upload does not refresh or replay a late 401 for a different account', () async {
    var refreshes = 0;
    final a = auth((r) {
      if (r.url.path.endsWith('/refresh')) refreshes++;
      return response(session());
    });
    await a.authenticate(email: 'user@example.test', password: 'password');
    var uploads = 0;
    final api = BrainApi(a, client: MockClient((_) async {
      uploads++;
      a.revision++;
      return response({'error':'Expired'}, 401);
    }));
    addTearDown(api.dispose);
    await expectLater(api.analyze('memory', 'office.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7'))),
      throwsA(isA<BrainApiException>()));
    expect(uploads, 1);
    expect(refreshes, 0);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_controller.dart';

void main() {
  gate6cClientTests();
  late List<Uri> requestedUris;

  late List<String> requestedMethods;

  late KorlixZoomConnectionClient client;

  setUp(() {
    requestedUris = <Uri>[];

    requestedMethods = <String>[];

    client = KorlixZoomConnectionClient(
      backendBaseUri: Uri.parse('https://api.korlix.test/'),
      agentId: 'nova',

      headersBuilder: () async => <String, String>{
        'authorization': 'Bearer test-user-token',
      },

      transport:
          ({
            required String method,
            required Uri uri,

            required Map<String, String> headers,

            Object? body,
          }) async {
            requestedMethods.add(method);

            requestedUris.add(uri);

            expect(uri.host, 'api.korlix.test');

            expect(headers['authorization'], 'Bearer test-user-token');

            switch (uri.path) {
              case KorlixZoomConnectionClient.statusPath:
                return KorlixZoomTransportResponse(
                  statusCode: 200,

                  body: jsonEncode(<String, Object?>{
                    'ok': true,

                    'status': <String, Object?>{
                      'connected': true,

                      'requiresReauthorization': false,

                      'accessTokenExpired': false,

                      'scope':
                          'meeting:read:'
                          'list_upcoming_meetings',

                      'expiresAt': '2026-09-07T01:00:00Z',
                    },
                  }),
                );

              case KorlixZoomConnectionClient.oauthStartPath:
                return KorlixZoomTransportResponse(
                  statusCode: 200,

                  body: jsonEncode(<String, Object?>{
                    'ok': true,

                    'authorization_url':
                        'https://zoom.us/'
                        'oauth/authorize'
                        '?state=opaque',

                    'expires_at': '2026-09-07T00:10:00Z',
                  }),
                );

              case KorlixZoomConnectionClient.upcomingMeetingsPath:
                return KorlixZoomTransportResponse(
                  statusCode: 200,

                  body: jsonEncode(<String, Object?>{
                    'ok': true,

                    'meetings': <Map<String, Object?>>[
                      <String, Object?>{
                        'id': '9876543210123',

                        'topic': 'Investor meeting',

                        'startTime': '2026-09-07T15:00:00Z',

                        'durationMinutes': 45,

                        'isHost': true,
                      },
                    ],
                  }),
                );

              case KorlixZoomConnectionClient.connectionPath:
                return const KorlixZoomTransportResponse(
                  statusCode: 200,
                  body: '{"ok":true}',
                );
            }

            return const KorlixZoomTransportResponse(
              statusCode: 404,

              body:
                  '{"ok":false,'
                  '"error":{'
                  '"code":"NOT_FOUND",'
                  '"message":"Not found"'
                  '}}',
            );
          },
    );
  });

  test('frontend declares backend-only K135Z endpoint contracts', () {
    expect(
      KorlixZoomConnectionClient.oauthStartPath,
      '/api/k135z/zoom/oauth/start',
    );

    expect(KorlixZoomConnectionClient.statusPath, '/api/k135z/zoom/status');

    expect(
      KorlixZoomConnectionClient.connectionPath,
      '/api/k135z/zoom/connection',
    );

    expect(
      KorlixZoomConnectionClient.upcomingMeetingsPath,
      '/api/k135z/zoom/'
      'meetings/upcoming',
    );

    final String source = File(
      'lib/meeting_copilot/'
      'korlix_zoom_connection_client.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('zoom.us/oauth/token')));

    expect(source, isNot(contains('client_secret')));

    expect(source, isNot(contains('refresh_token')));
  });

  test(
    'status parsing exposes connection metadata without token fields',
    () async {
      final KorlixZoomConnectionStatus status = await client.getStatus();

      expect(status.connected, isTrue);

      expect(status.accessTokenExpired, isFalse);

      expect(status.scope, contains('list_upcoming_meetings'));

      expect(requestedMethods.single, 'GET');
    },
  );

  test(
    'authorization starts through KORLIX backend and returns secure URL',
    () async {
      final KorlixZoomAuthorizationStart result = await client
          .beginAuthorization(
            returnTo: Uri.parse(
              'https://app.korlix.test/'
              '#/meeting-copilot',
            ),
          );

      expect(result.authorizationUri.scheme, 'https');

      expect(result.authorizationUri.host, 'zoom.us');

      expect(
        requestedUris.single.queryParameters['return_to'],
        'https://app.korlix.test/'
        '#/meeting-copilot',
      );
    },
  );

  test('upcoming meeting IDs remain strings and parse safely', () async {
    final List<KorlixZoomMeetingSummary> meetings = await client
        .listUpcomingMeetings();

    expect(meetings, hasLength(1));

    expect(meetings.single.id, '9876543210123');

    expect(meetings.single.topic, 'Investor meeting');

    expect(meetings.single.isHost, isTrue);
  });

  test('disconnect uses only the authenticated backend endpoint', () async {
    expect(await client.disconnect(), isTrue);

    expect(requestedMethods.single, 'DELETE');

    expect(
      requestedUris.single.path,
      KorlixZoomConnectionClient.connectionPath,
    );
  });

  test(
    'controller transitions from status to meetings to disconnected',
    () async {
      final KorlixZoomConnectionController controller =
          KorlixZoomConnectionController(client: client);

      await controller.refreshStatus();

      expect(controller.phase, KorlixZoomConnectionPhase.connected);

      await controller.loadUpcomingMeetings();

      expect(controller.meetings, hasLength(1));

      await controller.disconnect();

      expect(controller.phase, KorlixZoomConnectionPhase.disconnected);

      expect(controller.meetings, isEmpty);

      controller.dispose();
    },
  );

  test('backend error responses become sanitized typed exceptions', () async {
    final KorlixZoomConnectionClient failing = KorlixZoomConnectionClient(
      backendBaseUri: Uri.parse('https://api.korlix.test/'),
      agentId: 'nova',

      headersBuilder: () async => <String, String>{'authorization': 'Bearer test-user-token'},

      transport:
          ({
            required String method,
            required Uri uri,

            required Map<String, String> headers,

            Object? body,
          }) async {
            return const KorlixZoomTransportResponse(
              statusCode: 403,

              body:
                  '{"error":{'
                  '"code":'
                  '"KORLIX_ENTERPRISE_REQUIRED",'
                  '"message":'
                  '"Enterprise required"'
                  '}}',
            );
          },
    );

    await expectLater(
      failing.getStatus(),

      throwsA(
        isA<KorlixZoomApiException>()
            .having(
              (KorlixZoomApiException error) => error.statusCode,
              'status',
              403,
            )
            .having(
              (KorlixZoomApiException error) => error.code,
              'code',
              'KORLIX_ENTERPRISE_REQUIRED',
            ),
      ),
    );
  });

  test(
    'malformed meetings are protocol errors rather than empty results',
    () async {
      final KorlixZoomConnectionClient malformed = KorlixZoomConnectionClient(
        backendBaseUri: Uri.parse('https://api.korlix.test/'),
      agentId: 'nova',
        headersBuilder: () async => <String, String>{'authorization': 'Bearer test-user-token'},
        transport:
            ({
              required String method,
              required Uri uri,
              required Map<String, String> headers,
              Object? body,
            }) async => const KorlixZoomTransportResponse(
              statusCode: 200,
              body: '{"ok":true,"meetings":{"bad":true}}',
            ),
      );

      await expectLater(
        malformed.listUpcomingMeetings(),
        throwsA(
          isA<KorlixZoomApiException>().having(
            (KorlixZoomApiException error) => error.code,
            'code',
            'ZOOM_MEETINGS_RESPONSE_INVALID',
          ),
        ),
      );
    },
  );

  test(
    'false disconnect acknowledgment does not manufacture disconnected state',
    () async {
      final KorlixZoomConnectionClient falseDisconnect =
          KorlixZoomConnectionClient(
            backendBaseUri: Uri.parse('https://api.korlix.test/'),
      agentId: 'nova',
            headersBuilder: () async => <String, String>{'authorization': 'Bearer test-user-token'},
            transport:
                ({
                  required String method,
                  required Uri uri,
                  required Map<String, String> headers,
                  Object? body,
                }) async {
                  if (uri.path == KorlixZoomConnectionClient.statusPath) {
                    return const KorlixZoomTransportResponse(
                      statusCode: 200,
                      body:
                          '{"status":{"connected":true,'
                          '"requires_reauthorization":false,'
                          '"access_token_expired":false}}',
                    );
                  }
                  return const KorlixZoomTransportResponse(
                    statusCode: 200,
                    body: '{"ok":false}',
                  );
                },
          );
      final KorlixZoomConnectionController controller =
          KorlixZoomConnectionController(client: falseDisconnect);
      await controller.refreshStatus();
      expect(controller.phase, KorlixZoomConnectionPhase.connected);
      await controller.disconnect();
      expect(controller.phase, KorlixZoomConnectionPhase.error);
      expect(controller.status?.connected, isTrue);
      controller.dispose();
    },
  );

  test(
    'late status result cannot overwrite a newer status operation',
    () async {
      final Completer<KorlixZoomTransportResponse> first =
          Completer<KorlixZoomTransportResponse>();
      int calls = 0;
      final KorlixZoomConnectionClient racing = KorlixZoomConnectionClient(
        backendBaseUri: Uri.parse('https://api.korlix.test/'),
      agentId: 'nova',
        headersBuilder: () async => <String, String>{'authorization': 'Bearer test-user-token'},
        transport:
            ({
              required String method,
              required Uri uri,
              required Map<String, String> headers,
              Object? body,
            }) async {
              calls += 1;
              if (calls == 1) {
                return first.future;
              }
              return const KorlixZoomTransportResponse(
                statusCode: 200,
                body:
                    '{"status":{"connected":false,'
                    '"requires_reauthorization":false,'
                    '"access_token_expired":false}}',
              );
            },
      );
      final KorlixZoomConnectionController controller =
          KorlixZoomConnectionController(client: racing);
      final Future<void> old = controller.refreshStatus();
      final Future<void> newer = controller.refreshStatus();
      await newer;
      first.complete(
        const KorlixZoomTransportResponse(
          statusCode: 200,
          body:
              '{"status":{"connected":true,'
              '"requires_reauthorization":false,'
              '"access_token_expired":false}}',
        ),
      );
      await old;
      expect(controller.phase, KorlixZoomConnectionPhase.disconnected);
      expect(controller.status?.connected, isFalse);
      controller.dispose();
    },
  );
}

// Gate6C supplements the retained client/controller regression tests.
void gate6cClientTests() {
  KorlixZoomConnectionClient make({String? agentId = 'nova',
      Map<String, String>? headers, void Function()? onSend}) => KorlixZoomConnectionClient(
    backendBaseUri: Uri.parse('https://api.korlix.test'), agentId: agentId,
    headersBuilder: () async => headers ?? {'authorization': 'Bearer offline-user'},
    transport: ({required String method, required Uri uri,
        required Map<String, String> headers, Object? body}) async {
      onSend?.call(); expect(uri.queryParameters['agent_id'], agentId);
      return const KorlixZoomTransportResponse(statusCode: 200,
          body: '{"status":{"connected":false}}');
    });
  test('Gate6C supplies canonical selected-agent query', () async {
    int calls = 0; await make(agentId: 'custom_17', onSend: () => calls++).getStatus();
    expect(calls, 1);
  });
  test('Gate6C missing and malformed selection never reaches transport', () async {
    int calls = 0;
    for (final id in <String?>[null, '', ' nova', 'nova/other']) {
      await expectLater(make(agentId: id, onSend: () => calls++).getStatus(),
          throwsA(isA<KorlixZoomApiException>()));
    }
    expect(calls, 0);
  });
  test('Gate6C rejects conflicting selected-agent headers', () async {
    int calls = 0;
    await expectLater(make(headers: {'authorization':'Bearer offline-user',
      'x-korlix-agent-id':'other'}, onSend: () => calls++).getStatus(),
      throwsA(isA<KorlixZoomApiException>()));
    expect(calls, 0);
  });
  test('Gate6C requires authentication before transport', () async {
    int calls = 0;
    await expectLater(make(headers: {}, onSend: () => calls++).getStatus(),
      throwsA(isA<KorlixZoomApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(calls, 0);
  });
  test('Gate6C rejects case-duplicate authorization headers', () async {
    await expectLater(make(headers: {'Authorization':'Bearer one',
      'authorization':'Bearer two'}).getStatus(), throwsA(isA<KorlixZoomApiException>()));
  });
}

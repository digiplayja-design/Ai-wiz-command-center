import 'dart:convert';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_email_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);

    final response = await handler(request);

    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

const KorlixLiveConvoAgentEmailRecipient ricardoRecipient =
    KorlixLiveConvoAgentEmailRecipient(
      id: 'recipient-ricardo',
      email: 'ricardo@korlixdeveloper.com',
      displayName: 'Ricardo Bailey',
      consentStatus: 'transactional_only',
      active: true,
    );

const KorlixLiveConvoAgentEmailRecipient secondRicardoRecipient =
    KorlixLiveConvoAgentEmailRecipient(
      id: 'recipient-ricardo-two',
      email: 'ricardo.two@example.test',
      displayName: 'Ricardo Brown',
      consentStatus: 'transactional_only',
      active: true,
    );

const KorlixLiveConvoAgentEmailToolCall draftToolCall =
    KorlixLiveConvoAgentEmailToolCall(
      callId: 'voice-call-001',
      name: 'create_agent_email_draft',
      arguments: <String, dynamic>{
        'recipient': 'ricardo@korlixdeveloper.com',
        'subject': 'LIVE CONVO Draft Test',
        'body': 'This is a mocked draft-only test.',
      },
    );

void main() {
  group('Korlix LIVE CONVO Agent Email bridge', () {
    test('publishes one draft-only Realtime tool', () {
      final definition = KorlixLiveConvoAgentEmailVoiceBridge.toolDefinition;

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.toolName,
        'create_agent_email_draft',
      );

      expect(definition['type'], 'function');

      expect(definition['name'], 'create_agent_email_draft');

      final parameters = Map<String, dynamic>.from(
        definition['parameters'] as Map,
      );

      expect(parameters['required'], <String>['recipient', 'subject', 'body']);

      expect(parameters['additionalProperties'], isFalse);
    });

    test('decodes the completed Realtime function call', () {
      final calls = KorlixLiveConvoAgentEmailToolCall.fromResponseDone(
        <String, dynamic>{
          'output': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'function_call',
              'call_id': 'voice-call-decode-1',
              'name': 'create_agent_email_draft',
              'arguments': jsonEncode(<String, dynamic>{
                'recipient': 'Ricardo Bailey',
                'subject': 'Meeting Reminder',
                'body': 'Remember the meeting.',
              }),
            },
          ],
        },
      );

      expect(calls, hasLength(1));
      expect(calls.single.callId, 'voice-call-decode-1');
      expect(calls.single.recipient, 'Ricardo Bailey');
      expect(calls.single.subject, 'Meeting Reminder');
      expect(calls.single.body, 'Remember the meeting.');
    });

    test('requires an active custom Agent with agent_email', () {
      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.isAuthorized(
          isCustom: true,
          active: true,
          toolIds: const <String>['general_chat', 'agent_email'],
        ),
        isTrue,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.isAuthorized(
          isCustom: false,
          active: true,
          toolIds: const <String>['agent_email'],
        ),
        isFalse,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.isAuthorized(
          isCustom: true,
          active: false,
          toolIds: const <String>['agent_email'],
        ),
        isFalse,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.isAuthorized(
          isCustom: true,
          active: true,
          toolIds: const <String>['general_chat'],
        ),
        isFalse,
      );
    });

    test('matches only one approved recipient', () {
      final exact =
          KorlixLiveConvoAgentEmailVoiceBridge.selectApprovedRecipient(
            query: 'ricardo@korlixdeveloper.com',
            recipients: const <KorlixLiveConvoAgentEmailRecipient>[
              ricardoRecipient,
            ],
          );

      expect(exact.id, 'recipient-ricardo');

      expect(
        () => KorlixLiveConvoAgentEmailVoiceBridge.selectApprovedRecipient(
          query: 'Ricardo',
          recipients: const <KorlixLiveConvoAgentEmailRecipient>[
            ricardoRecipient,
            secondRicardoRecipient,
          ],
        ),
        throwsA(
          isA<KorlixLiveConvoAgentEmailVoiceException>().having(
            (error) => error.code,
            'code',
            'agent_email_voice_recipient_ambiguous',
          ),
        ),
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.idempotencyKeyForCall(
          'Voice / Call 123',
        ),
        'live-convo-agent-email-draft:'
        'voice_call_123',
      );
    });

    test('creates only a mocked transactional draft', () async {
      final fakeClient = _FakeClient((http.BaseRequest request) async {
        expect(request.url.host, 'example.test');

        expect(request.url.path, isNot(contains('/send')));

        expect(request.url.path, isNot(contains('/approve')));

        if (request.method == 'GET' &&
            request.url.path ==
                '/api/live-convo/agents/'
                    'custom_nova/email/recipients') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'recipients': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'recipient-ricardo',
                  'email': 'ricardo@korlixdeveloper.com',
                  'displayName': 'Ricardo Bailey',
                  'consentStatus': 'transactional_only',
                  'active': true,
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        if (request.method == 'POST' &&
            request.url.path ==
                '/api/live-convo/agents/'
                    'custom_nova/email/drafts') {
          final posted =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;

          expect(posted['confirmed'], isTrue);

          expect(posted['confirmation'], isTrue);

          expect(posted['recipientId'], 'recipient-ricardo');

          expect(posted['subject'], 'LIVE CONVO Draft Test');

          expect(
            posted['textBody'],
            'This is a mocked '
            'draft-only test.',
          );

          expect(posted['marketing'], isFalse);

          expect(posted['purpose'], 'transactional');

          expect(posted['source'], 'live_convo_voice_draft');

          expect(
            posted['idempotencyKey'],
            startsWith('live-convo-agent-email-draft:'),
          );

          return http.Response(
            jsonEncode(<String, dynamic>{
              'draft': <String, dynamic>{
                'id': 'mock-draft-1',
                'status': 'draft',
                'sent': false,
              },
              'sent': false,
              'replayed': false,
            }),
            201,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        throw StateError(
          'Unexpected mocked request: '
          '${request.method} '
          '${request.url}',
        );
      });

      final voiceClient = KorlixLiveConvoAgentEmailVoiceClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => const <String, String>{
          'Authorization': 'Bearer test-token',
        },
        client: fakeClient,
      );

      final result = await voiceClient.executeDraftToolCall(
        agentId: 'custom_nova',
        call: draftToolCall,
      );

      expect(fakeClient.requests, hasLength(2));

      expect(result['success'], isTrue);

      expect(result['code'], 'agent_email_voice_draft_created');

      expect(result['draftId'], 'mock-draft-1');

      expect(result['status'], 'draft');

      expect(result['sent'], isFalse);

      expect(result['nothingSent'], isTrue);

      expect(result['message'], contains('Nothing was sent.'));

      voiceClient.close();
    });

    test('fails closed before HTTP without authentication', () async {
      final fakeClient = _FakeClient((http.BaseRequest request) async {
        throw StateError(
          'HTTP must not run '
          'without authentication.',
        );
      });

      final voiceClient = KorlixLiveConvoAgentEmailVoiceClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => const <String, String>{},
        client: fakeClient,
      );

      final result = await voiceClient.executeDraftToolCall(
        agentId: 'custom_nova',
        call: draftToolCall,
      );

      expect(fakeClient.requests, isEmpty);

      expect(result['success'], isFalse);

      expect(result['code'], 'agent_email_voice_sign_in_required');

      expect(result['sent'], isFalse);

      expect(result['nothingSent'], isTrue);

      expect(result['message'], contains('Nothing was sent.'));

      voiceClient.close();
    });
  });
}

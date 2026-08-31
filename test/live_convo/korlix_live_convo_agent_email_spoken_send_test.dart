import 'dart:convert';

import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_email_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _MockClient extends http.BaseClient {
  _MockClient(this.handler);

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

const String _agentId = 'custom_nova';

const String _recipientId = 'recipient-ricianna';

const String _recipientEmail = 'ricianna@example.test';

const String _recipientName = 'Ricianna Bailey';

const String _draftId = 'draft-send-1';

const String _subject = 'Please call me';

const String _body =
    'Please give me a call as soon as you receive this message.';

const String _nonce = 'one-confirmation-nonce-1234567890';

Map<String, dynamic> _postedBody(http.BaseRequest request) {
  return jsonDecode((request as http.Request).body) as Map<String, dynamic>;
}

http.Response _jsonResponse(Map<String, dynamic> value, int statusCode) {
  return http.Response(
    jsonEncode(value),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

KorlixLiveConvoAgentEmailPendingSend _pending({
  String draftId = _draftId,
  String subject = _subject,
  String body = _body,
  DateTime? now,
}) {
  return KorlixLiveConvoAgentEmailPendingSend.fromDraftOutput(
    <String, dynamic>{
      'draftId': draftId,
      'recipientId': _recipientId,
      'recipientName': _recipientName,
      'recipientEmail': _recipientEmail,
      'subject': subject,
      'body': body,
    },
    agentId: _agentId,
    confirmationNonce: _nonce,
    now: now ?? DateTime.utc(2026, 8, 31, 17),
  );
}

KorlixLiveConvoAgentEmailVoiceClient _voiceClient(http.Client client) {
  return KorlixLiveConvoAgentEmailVoiceClient(
    backendBaseUrl: 'https://example.test',
    headersBuilder: () => const <String, String>{
      'Authorization': 'Bearer mocked-test-token',
    },
    client: client,
  );
}

void main() {
  group('K134A protected spoken Agent Email send', () {
    test('recognizes explicit yes no and unknown speech', () {
      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.decisionFromTranscript(
          'Yes, send it.',
        ),
        KorlixLiveConvoAgentEmailVoiceDecision.affirmative,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.decisionFromTranscript('No.'),
        KorlixLiveConvoAgentEmailVoiceDecision.negative,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.decisionFromTranscript(
          'The message looks good.',
        ),
        KorlixLiveConvoAgentEmailVoiceDecision.unknown,
      );

      expect(
        KorlixLiveConvoAgentEmailVoiceBridge.decisionFromTranscript(
          'Yes, but change the recipient first.',
        ),
        KorlixLiveConvoAgentEmailVoiceDecision.unknown,
      );
    });

    test('creates unique secure confirmation nonces', () {
      final first =
          KorlixLiveConvoAgentEmailVoiceBridge.secureConfirmationNonce();

      final second =
          KorlixLiveConvoAgentEmailVoiceBridge.secureConfirmationNonce();

      expect(first, isNot(second));

      expect(first.length, greaterThanOrEqualTo(40));

      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('pending authorization binds exact content and expires', () {
      final created = DateTime.utc(2026, 8, 31, 17);

      final pending = _pending(now: created);

      expect(
        pending.matchesDraft(<String, dynamic>{
          'id': _draftId,
          'recipientId': _recipientId,
          'toEmail': _recipientEmail,
          'subject': _subject,
          'textBody': _body,
          'status': 'draft',
        }),
        isTrue,
      );

      expect(
        pending.matchesDraft(<String, dynamic>{
          'id': _draftId,
          'recipientId': _recipientId,
          'toEmail': _recipientEmail,
          'subject': 'Changed subject',
          'textBody': _body,
          'status': 'draft',
        }),
        isFalse,
      );

      expect(
        pending.isExpired(created.add(const Duration(minutes: 4))),
        isFalse,
      );

      expect(
        pending.isExpired(created.add(const Duration(minutes: 6))),
        isTrue,
      );
    });

    test('send request first creates only an unsent draft', () async {
      final mock = _MockClient((http.BaseRequest request) async {
        expect(request.url.host, 'example.test');

        if (request.method == 'GET' &&
            request.url.path ==
                '/api/live-convo/agents/'
                    'custom_nova/email/'
                    'recipients') {
          return _jsonResponse(<String, dynamic>{
            'recipients': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': _recipientId,
                'email': _recipientEmail,
                'displayName': _recipientName,
                'consentStatus': 'transactional_only',
                'active': true,
              },
            ],
          }, 200);
        }

        if (request.method == 'POST' &&
            request.url.path ==
                '/api/live-convo/agents/'
                    'custom_nova/email/'
                    'drafts') {
          final body = _postedBody(request);

          expect(body['source'], 'live_convo_voice_draft');

          expect(body['marketing'], isFalse);

          expect(body['recipientId'], _recipientId);

          return _jsonResponse(<String, dynamic>{
            'draft': <String, dynamic>{
              'id': 'draft-prepare-send-1',
              'status': 'draft',
              'sent': false,
            },
            'sent': false,
            'replayed': false,
          }, 201);
        }

        throw StateError(
          'Unexpected mocked request: '
          '${request.method} '
          '${request.url}',
        );
      });

      final client = _voiceClient(mock);

      final result = await client.executeDraftToolCall(
        agentId: _agentId,
        call: const KorlixLiveConvoAgentEmailToolCall(
          callId: 'voice-send-prepare-1',
          name: 'create_agent_email_draft',
          arguments: <String, dynamic>{
            'recipient': _recipientEmail,
            'subject': _subject,
            'body': _body,
            'sendRequested': true,
          },
        ),
      );

      expect(mock.requests, hasLength(2));

      expect(
        mock.requests.any((request) => request.url.path.contains('/approve')),
        isFalse,
      );

      expect(
        mock.requests.any((request) => request.url.path.endsWith('/send')),
        isFalse,
      );

      expect(result['success'], isTrue);

      expect(result['code'], 'agent_email_voice_send_confirmation_required');

      expect(result['pendingConfirmation'], isTrue);

      expect(result['sendRequested'], isTrue);

      expect(result['sent'], isFalse);

      expect(result['nothingSent'], isTrue);

      expect(result['recipientId'], _recipientId);

      expect(result['body'], _body);

      client.close();
    });

    test('spoken yes uses the same nonce to approve and send', () async {
      final mock = _MockClient((http.BaseRequest request) async {
        if (request.method == 'GET' &&
            request.url.path ==
                '/api/live-convo/agents/'
                    'custom_nova/email/'
                    'drafts/draft-send-1') {
          return _jsonResponse(<String, dynamic>{
            'draft': <String, dynamic>{
              'id': _draftId,
              'recipientId': _recipientId,
              'toEmail': _recipientEmail,
              'subject': _subject,
              'textBody': _body,
              'status': 'draft',
            },
          }, 200);
        }

        if (request.method == 'POST' &&
            request.url.path.endsWith('/draft-send-1/approve')) {
          final body = _postedBody(request);

          expect(body['confirmed'], isTrue);

          expect(body['confirmationNonce'], _nonce);

          expect(body['confirmation_nonce'], _nonce);

          return _jsonResponse(<String, dynamic>{
            'approved': true,
            'draft': <String, dynamic>{'id': _draftId, 'status': 'approved'},
            'sent': false,
          }, 200);
        }

        if (request.method == 'POST' &&
            request.url.path.endsWith('/draft-send-1/send')) {
          final body = _postedBody(request);

          expect(body['confirmed'], isTrue);

          expect(body['confirmationNonce'], _nonce);

          expect(body['confirmation_nonce'], _nonce);

          return _jsonResponse(<String, dynamic>{
            'sent': true,
            'replayed': false,
            'message': <String, dynamic>{
              'id': _draftId,
              'status': 'sent',
              'providerMessageId': 'resend-mocked-1',
            },
          }, 200);
        }

        throw StateError(
          'Unexpected mocked request: '
          '${request.method} '
          '${request.url}',
        );
      });

      final client = _voiceClient(mock);

      final result = await client.approveAndSendPending(
        pending: _pending(),
        now: DateTime.utc(2026, 8, 31, 17, 1),
      );

      expect(mock.requests, hasLength(3));

      expect(result['success'], isTrue);

      expect(result['sent'], isTrue);

      expect(result['replayed'], isFalse);

      expect(result['providerMessageId'], 'resend-mocked-1');

      client.close();
    });

    test('changed draft rejects stale spoken confirmation', () async {
      final mock = _MockClient((http.BaseRequest request) async {
        expect(request.method, 'GET');

        return _jsonResponse(<String, dynamic>{
          'draft': <String, dynamic>{
            'id': _draftId,
            'recipientId': _recipientId,
            'toEmail': _recipientEmail,
            'subject': 'Changed subject',
            'textBody': _body,
            'status': 'draft',
          },
        }, 200);
      });

      final client = _voiceClient(mock);

      final result = await client.approveAndSendPending(
        pending: _pending(),
        now: DateTime.utc(2026, 8, 31, 17, 1),
      );

      expect(mock.requests, hasLength(1));

      expect(result['success'], isFalse);

      expect(result['code'], 'agent_email_voice_confirmation_stale');

      expect(result['sent'], isFalse);

      expect(result['retrySafe'], isTrue);

      client.close();
    });

    test('expired spoken confirmation performs no HTTP request', () async {
      final mock = _MockClient((http.BaseRequest request) async {
        throw StateError(
          'Expired confirmation '
          'must not call HTTP.',
        );
      });

      final client = _voiceClient(mock);

      final result = await client.approveAndSendPending(
        pending: _pending(),
        now: DateTime.utc(2026, 8, 31, 17, 6),
      );

      expect(mock.requests, isEmpty);

      expect(result['success'], isFalse);

      expect(result['code'], 'agent_email_voice_confirmation_expired');

      expect(result['sent'], isFalse);

      client.close();
    });

    test('already sent draft is replay safe', () async {
      final mock = _MockClient((http.BaseRequest request) async {
        expect(request.method, 'GET');

        return _jsonResponse(<String, dynamic>{
          'draft': <String, dynamic>{
            'id': _draftId,
            'status': 'sent',
            'providerMessageId': 'resend-existing-1',
          },
        }, 200);
      });

      final client = _voiceClient(mock);

      final result = await client.approveAndSendPending(
        pending: _pending(),
        now: DateTime.utc(2026, 8, 31, 17, 1),
      );

      expect(mock.requests, hasLength(1));

      expect(result['success'], isTrue);

      expect(result['sent'], isTrue);

      expect(result['replayed'], isTrue);

      expect(result['providerMessageId'], 'resend-existing-1');

      client.close();
    });
  });
}

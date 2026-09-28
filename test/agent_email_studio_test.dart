import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/live_convo/agent_studio_profile.dart';
import 'package:ai_wiz_command_center/live_convo/agent_studio_workflows.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_email_sheet.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_client.dart';
import 'agent_studio_test.dart' as fixtures;

void main() {
  test('capability filters reflect only enabled agent tools', () {
    final teacher = fixtures.agents.firstWhere(
      (a) => a.id == 'language_teacher',
    );
    expect(agentMatchesCapability(teacher, 'File analysis'), isTrue);
    expect(agentMatchesCapability(teacher, 'Email'), isFalse);
    expect(agentStartingTasks(teacher).first, 'Practice a conversation');
  });
  testWidgets(
    'profile prepares a brief and hands off only after an explicit action',
    (t) async {
      String? action;
      await fixtures.mount(
        t,
        AgentStudioProfile(
          agent: fixtures.agents[1],
          onAction: (s) => action = s,
        ),
        width: 390,
      );
      await fixtures.tap(t, find.text('Draft a professional report'));
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, contains('Desired outcome:'));
      expect(action, isNull);
      await fixtures.tap(t, find.text('Plan a workflow'));
      expect(action, 'workflow');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'an agent-led workflow opens an editable plan without saving or running',
    (t) async {
      final client = fixtures.FakeWorkflows();
      await fixtures.mount(
        t,
        AgentStudioWorkflows(
          client: client,
          agents: fixtures.agents,
          leadAgent: fixtures.agents[1],
        ),
        width: 390,
      );
      expect(find.text('Doc Wizard workflow'), findsOneWidget);
      await fixtures.reveal(t, find.text('Prepare the deliverable'));
      expect(find.text('Prepare the deliverable'), findsOneWidget);
      expect(client.actions, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'email queues and rule pause at $width preserve explicit approval',
      (t) async {
        final requests = <Map<String, dynamic>>[];
        var enabled = true;
        final mock = MockClient((r) async {
          if (r.method == 'PATCH') {
            requests.add({
              'path': r.url.path,
              ...jsonDecode(r.body) as Map<String, dynamic>,
            });
            enabled = false;
            return http.Response('{"rule":{"id":"r1","enabled":false}}', 200);
          }
          final path = r.url.path;
          final settings = {
            'enabled': true,
            'paused': false,
            'canSend': true,
            'providerConfigured': true,
            'mode': 'autopilot',
            'dailySendCap': 5,
          };
          final payload = path.endsWith('/rules')
              ? {
                  'rules': [
                    {
                      'id': 'r1',
                      'name': 'Weekly update',
                      'enabled': enabled,
                      'preapproved': true,
                      'sendMode': 'autopilot',
                      'subjectTemplate': 'Project update',
                      'textTemplate': 'A short progress update.',
                      'maxSendsPerDay': 1,
                    },
                  ],
                }
              : path.endsWith('/recipients')
              ? {
                  'recipients': [
                    {
                      'id': 'p1',
                      'email': 'team@example.test',
                      'status': 'transactional_only',
                      'active': true,
                    },
                  ],
                }
              : path.endsWith('/drafts')
              ? {
                  'drafts': [
                    {
                      'id': 'd1',
                      'subject': 'Invoice follow-up',
                      'status': 'draft',
                      'textBody': 'Review this invoice.',
                    },
                    {
                      'id': 'd2',
                      'subject': 'Delivery failure',
                      'status': 'failed',
                      'textBody': 'Please retry.',
                    },
                  ],
                }
              : path.endsWith('/events')
              ? {'events': []}
              : path.endsWith('/settings')
              ? {'settings': settings}
              : {'status': settings};
          return http.Response(jsonEncode(payload), 200);
        });
        final client = KorlixLiveConvoAgentClient(
          backendBaseUrl: 'https://fixture.test',
          headersBuilder: () => {},
        );
        await http.runWithClient(() async {
          await fixtures.mount(
            t,
            KorlixLiveConvoAgentEmailSheet(
              client: client,
              agent: fixtures.agents.first.copyWith(toolIds: ['agent_email']),
            ),
            width: width,
            height: 1000,
          );
          await fixtures.tap(t, find.text('Drafts'));
          await t.enterText(
            find.widgetWithText(TextField, 'Search drafts'),
            'invoice',
          );
          await t.pumpAndSettle();
          expect(find.text('Invoice follow-up'), findsOneWidget);
          expect(find.text('Delivery failure'), findsNothing);
          await fixtures.tap(t, find.text('Automation'));
          await fixtures.tap(t, find.text('Pause rule'));
          expect(requests, isEmpty);
          await fixtures.tap(
            t,
            find.widgetWithText(FilledButton, 'Pause rule'),
          );
          expect(requests.single['confirmed'], isTrue);
          expect(requests.single['enabled'], isFalse);
          expect(requests.single['path'], endsWith('/rules/r1'));
          expect(find.text('Resume rule'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }, () => mock);
      },
    );
  }
}

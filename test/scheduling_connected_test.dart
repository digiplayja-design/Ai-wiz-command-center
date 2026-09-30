import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_client.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_connected.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_forms.dart';

final profile = <String, dynamic>{
  'revision': 1,
  'display_name': 'Host',
  'timezone': 'UTC',
  'weekly': List.generate(
    7,
    (day) => {
      'day': day,
      'windows': [
        [540, 1020],
      ],
    },
  ),
  'overrides': [],
};
final data = <String, dynamic>{
  'profile': profile,
  'connections': [],
  'pending': [],
  'teams': [],
  'capabilities': {
    'ai_scheduling': true,
    'providers': {
      'google': {'configured': false},
      'microsoft': {'configured': false},
      'stripe': {'configured': false},
    },
  },
};
http.Response response(dynamic value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
SchedulingClient client(
  Future<http.Response> Function(http.Request) handle, {
  Listenable? changes,
  Map<String, String> Function()? headers,
}) => SchedulingClient(
  baseUrl: 'https://fixture.test',
  headersBuilder: headers ?? () => {'Authorization': 'Bearer first'},
  sessionChanges: changes,
  client: MockClient(handle),
);
Future<void> panel(
  WidgetTester tester,
  String mode,
  SchedulingClient c, {
  SchedulingMap? custom,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SchedulingConnectedPanel(
          mode: mode,
          data: custom ?? data,
          client: c,
          refresh: () async {},
        ),
      ),
    ),
  ),
);
void main() {
  for (final size in [const Size(390, 844), const Size(1366, 1000)])
    testWidgets('connections, teams and assistant fit ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = client((_) async => response({}));
      for (final mode in ['connections', 'teams', 'assistant']) {
        await panel(tester, mode, c);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (mode == 'connections') {
          expect(find.text('Administrator setup required'), findsNWidgets(3));
          expect(find.text('Connect account'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
      }
      c.dispose();
    });
  testWidgets(
    'joining a team previews identity and requires explicit consent',
    (tester) async {
      final calls = <String>[];
      final c = client((r) async {
        calls.add(r.url.path);
        return response({
          'id': 'team',
          'name': 'Review team',
          'owner_name': 'Owner',
        });
      });
      await panel(tester, 'teams', c);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join with invite code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a' * 64);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Join Review team?'), findsOneWidget);
      expect(calls.where((x) => x.endsWith('/join')), isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.where((x) => x.endsWith('/join')), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    },
  );
  testWidgets('AI proposal approval is a separate reviewed request', (
    tester,
  ) async {
    final sent = <http.Request>[];
    final proposal = {
      'id': 'proposal-id',
      'state': 'review',
      'expires_at': '2026-10-01T12:00:00Z',
      'plan': {
        'action': 'draft',
        'summary': 'Create a 30-minute discovery draft.',
        'data': {'description': 'A focused conversation.'},
      },
    };
    final c = client((r) async {
      sent.add(r);
      return response({
        'proposal': {
          ...proposal,
          'state': r.url.path.endsWith('/apply') ? 'applied' : 'review',
        },
      });
    });
    await panel(tester, 'assistant', c);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Create a discovery call');
    await tester.ensureVisible(find.text('Prepare proposal'));
    await tester.tap(find.text('Prepare proposal'));
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    expect(
      jsonDecode(sent.first.body)['request_id'],
      matches(RegExp(r'^[a-f0-9-]{36}$')),
    );
    await tester.ensureVisible(find.text('Review and approve change'));
    await tester.tap(find.text('Review and approve change'));
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    await tester.tap(find.text('Approve change'));
    await tester.pumpAndSettle();
    expect(sent.length, 2);
    expect(jsonDecode(sent.last.body)['confirmed'], true);
    expect(find.text('Change applied'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('account changes discard an in-flight AI proposal', (
    tester,
  ) async {
    String token = 'Bearer first';
    final changed = ValueNotifier(0), pending = Completer<http.Response>();
    final c = client(
      (_) => pending.future,
      changes: changed,
      headers: () => {'Authorization': token},
    );
    await panel(tester, 'assistant', c);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Find appointments');
    await tester.ensureVisible(find.text('Prepare proposal'));
    await tester.tap(find.text('Prepare proposal'));
    await tester.pump();
    token = 'Bearer second';
    changed.value++;
    pending.complete(
      response({
        'proposal': {
          'id': 'private',
          'plan': {'summary': 'Private guest name'},
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private guest name'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    changed.dispose();
  });
  testWidgets('event editor preserves price and selected team hosts', (
    tester,
  ) async {
    SchedulingMap? saved;
    final e = {
      'title': 'Team consultation',
      'description': 'Talk',
      'kind': 'one_to_one',
      'location_kind': 'custom',
      'location_detail': 'Host office',
      'color': '#72D6EB',
      'routing_mode': 'collective',
      'team_id': 'team-a',
      'host_ids': ['host-a'],
      'price_cents': 2550,
      'refund_policy': 'Full refund before appointment.',
      'revision': 2,
      'questions': [],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await editScheduleEvent(
                  context,
                  e,
                  [
                    {
                      'id': 'team-a',
                      'name': 'Team A',
                      'is_owner': true,
                      'members': [
                        {
                          'user_id': 'host-a',
                          'name': 'Host A',
                          'timezone': 'UTC',
                          'active': true,
                        },
                      ],
                    },
                  ],
                  [
                    {
                      'provider': 'stripe',
                      'state': 'connected',
                      'enabled': true,
                      'charges_enabled': true,
                    },
                  ],
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved?['price_cents'], 2550);
    expect(saved?['routing_mode'], 'collective');
    expect(saved?['host_ids'], ['host-a']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

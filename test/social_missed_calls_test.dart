import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_call_history.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';

import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

const snapshot = '2026-10-11T19:40:00Z';
SocialMap missed(String id, {String peer = 'friend', int count = 3}) => {
  'id': id,
  'state': 'missed',
  'incoming': true,
  'mode': 'video',
  'created_at': snapshot,
  'peer': {'id': peer, 'name': 'Jordan Rivera'},
  'can_call': true,
  'peer_missed_count': count,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
  });
  test(
    'misses group by caller across pages without merging outgoing, declined, or hidden peers',
    () {
      final first = missed('one', count: 55);
      final items = [
        first,
        {...missed('outgoing'), 'incoming': false},
        {...missed('declined'), 'state': 'declined'},
        missed('two', count: 55),
        first,
        {
          ...missed('hidden'),
          'peer': {'id': null, 'name': 'Unavailable member'},
        },
      ];
      final groups = socialCallHistoryGroups(items);
      expect(groups.length, 4);
      expect(groups.first['missed_count'], 55);
      expect(socialCallHistoryLabel(groups.first), '55 missed calls');
      expect(socialCallHistoryLabel(groups[1]), 'No answer');
      expect(socialCallHistoryLabel(groups[2]), 'Declined');
      expect(
        first.containsKey('missed_count'),
        false,
        reason: 'render grouping must not mutate stored page items',
      );
    },
  );

  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets(
      'missed-call history shows exact grouped counts and acknowledges its displayed snapshot at $width',
      (t) async {
        final revision = ValueNotifier(0), writes = <SocialMap>[];
        var token = 'Bearer first-account';
        final client = SocialClient(
          baseUrl: 'https://fixture.test',
          headersBuilder: () => {'Authorization': token},
          sessionChanges: revision,
          client: MockClient((request) async {
            final action = request.url.pathSegments.last;
            if (request.method == 'POST') {
              writes.add({
                'action': action,
                ...socialMap(jsonDecode(request.body)),
              });
              return http.Response('{"missed_count":0}', 200);
            }
            return http.Response(
              jsonEncode({
                'items': [missed('one'), missed('two'), missed('three')],
                'missed_total': 3,
                'missed_count': 3,
                'missed_as_of': snapshot,
                'has_more': false,
              }),
              200,
            );
          }),
        );
        var called = false;
        await social.mount(
          t,
          SocialCallHistory(
            client: client,
            onCall: (_, _) async {
              called = true;
            },
          ),
          width: width,
          scale: width == 320 ? 2 : 1,
        );
        await t.scrollUntilVisible(
          find.text('3 missed calls in the last 30 days'),
          200,
        );
        expect(find.text('3 missed calls in the last 30 days'), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('3 missed calls · Latest: Video'),
          250,
        );
        await t.pumpAndSettle();
        expect(find.text('Jordan Rivera'), findsOneWidget);
        expect(find.text('3 missed calls · Latest: Video'), findsOneWidget);
        expect(writes.single['action'], 'call_history_read');
        expect(writes.single['through'], snapshot);
        expect(
          called,
          false,
          reason: 'viewing misses never automatically calls anyone',
        );
        expect(t.takeException(), isNull);
        await fixtures.capture(t, 'social-missed-calls-${width.toInt()}');
        token = 'Bearer replacement-account';
        revision.value++;
        await t.pumpAndSettle();
        expect(find.text('Jordan Rivera'), findsNothing);
        expect(find.text('3 missed calls in the last 30 days'), findsNothing);
        await t.pumpWidget(const SizedBox());
        client.dispose();
        revision.dispose();
      },
    );
  }

  testWidgets(
    'Social shows the missed count before opening history and refreshes it after acknowledgment',
    (t) async {
      var count = 3;
      final actions = <String>[];
      final client = SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((request) async {
          final action = request.url.pathSegments.last;
          actions.add(action);
          SocialMap result = {'items': []};
          if (action == 'bootstrap') {
            result = {'profile': social.me, 'categories': social.categories};
          }
          if (action == 'call_inbox') {
            result = {'call': null, 'missed_count': count};
          }
          if (action == 'call_history') {
            result = {
              'items': [missed('one'), missed('two'), missed('three')],
              'missed_total': 3,
              'missed_count': count,
              'missed_as_of': snapshot,
              'has_more': false,
            };
          }
          if (action == 'call_history_read') {
            count = 0;
            result = {'missed_count': 0};
          }
          return http.Response(jsonEncode(result), 200);
        }),
      );
      await social.mount(t, SocialScreen(client: client));
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text('3 missed calls'), findsOneWidget);
      await t.tap(find.text('3 missed calls'));
      await t.pumpAndSettle();
      expect(count, 0);
      expect(
        actions.where((action) => action == 'call_history_read').length,
        1,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('3 missed calls'), findsNothing);
      expect(find.text('Call history'), findsOneWidget);
      expect(actions.contains('call_start'), false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}

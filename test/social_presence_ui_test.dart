import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_design.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/social/social_wall.dart';

import 'social_test.dart' as fixtures;
import 'social_wall_voice_test.dart' as voice;

class PresenceStore {
  final calls = <String>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer presence-one';
  bool online = true, blocked = false, fail = false;
  int replyCount = 1;
  Completer<void>? gate;
  SocialMap get member => {...fixtures.peer, 'online': online};
  SocialMap get topic => {
    ...fixtures.topic,
    'surface': 'wall',
    'author': member,
  };
  http.Response response(SocialMap value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      calls.add(action);
      await gate?.future;
      if (blocked) {
        return response({'error': 'This profile is unavailable.'}, 404);
      }
      if (fail) {
        return response({'error': 'Temporary connection problem.'}, 503);
      }
      if (action == 'member') return response({'profile': member});
      if (action == 'wall') {
        return response({
          'items': [topic],
        });
      }
      if (action == 'topic') {
        final after =
            int.tryParse(request.url.queryParameters['after'] ?? '0') ?? 0;
        return response({
          'topic': topic,
          'items': [
            for (var i = after + 1; i <= replyCount && i <= after + 41; i++)
              {
                'id': 'reply-$i',
                'seq': i,
                'body': 'Reply $i',
                'author': member,
                'created_at': '2026-10-03T16:00:00Z',
                'updated_at': '2026-10-03T16:00:00Z',
              },
          ],
        });
      }
      return response({});
    }),
  );
  void close() {
    client.dispose();
    revision.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server privacy and unavailable identities govern presence labels', () {
    expect(socialPresenceLabel({...fixtures.peer, 'online': true}), 'Online');
    expect(socialPresenceLabel({...fixtures.peer, 'online': false}), 'Offline');
    expect(
      socialPresenceLabel({
        ...fixtures.peer,
        'online': true,
        'show_online': false,
      }),
      'Offline',
    );
    expect(
      socialPresenceLabel({...fixtures.peer, 'online': null}),
      'Status unavailable',
    );
    for (final member in <SocialMap>[
      {'name': 'Unavailable member'},
      {...fixtures.peer, 'name': 'Unavailable member'},
      {...fixtures.peer, 'blocked': true},
      {...fixtures.peer, 'suspended': true},
      {...fixtures.peer, 'unavailable': true},
      {...fixtures.peer, 'deleted': true},
    ]) {
      expect(socialPresenceLabel(member), isNull);
    }
  });

  for (final theme in ['pure_black', 'pure_white']) {
    testWidgets(
      'name and readable badge wrap at 320px and double text in $theme',
      (t) async {
        await fixtures.mount(
          t,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SocialMemberName(
                member: {
                  ...fixtures.peer,
                  'name': 'A very long member name that should wrap safely',
                },
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
          width: 320,
          scale: 2,
          theme: theme,
        );
        expect(find.text('● Online'), findsOneWidget);
        expect(find.byTooltip('Recently active in KORLIX'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('status snapshot changes update text and accessible tooltip', (
    t,
  ) async {
    final member = ValueNotifier<SocialMap>(fixtures.peer);
    await fixtures.mount(
      t,
      Scaffold(
        body: ValueListenableBuilder<SocialMap>(
          valueListenable: member,
          builder: (_, value, _) => SocialMemberName(member: value),
        ),
      ),
    );
    expect(find.text('● Online'), findsOneWidget);
    member.value = {...fixtures.peer, 'online': false};
    await t.pump();
    expect(find.text('● Offline'), findsOneWidget);
    expect(find.byTooltip('Offline or status hidden'), findsOneWidget);
    member.value = {...fixtures.peer, 'online': null};
    await t.pump();
    expect(find.text('● Status unavailable'), findsOneWidget);
    member.value = {...fixtures.peer, 'name': 'Unavailable member'};
    await t.pump();
    expect(find.textContaining('● '), findsNothing);
    await t.pumpWidget(const SizedBox());
    member.dispose();
  });

  testWidgets(
    'profile polls only its member and updates existing post authors',
    (t) async {
      final s = PresenceStore();
      await fixtures.mount(
        t,
        SocialProfileWallScreen(
          client: s.client,
          me: fixtures.me,
          member: s.member,
          categories: fixtures.categories,
        ),
      );
      final wallReads = s.calls.where((c) => c == 'wall').length;
      expect(find.text('● Online'), findsWidgets);
      s.online = false;
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(s.calls.where((c) => c == 'wall').length, wallReads);
      expect(s.calls.where((c) => c == 'member').length, 2);
      expect(find.text('● Online'), findsNothing);
      expect(find.text('● Offline'), findsWidgets);
      await t.pumpWidget(const SizedBox());
      s.close();
    },
  );

  testWidgets('profile access denial clears names and presence', (t) async {
    final s = PresenceStore();
    await fixtures.mount(
      t,
      SocialProfileWallScreen(
        client: s.client,
        me: fixtures.me,
        member: s.member,
        categories: fixtures.categories,
      ),
    );
    s.blocked = true;
    await t.pump(const Duration(seconds: 16));
    await t.pumpAndSettle();
    expect(find.text('● Online'), findsNothing);
    expect(find.text(fixtures.peer['name']), findsNothing);
    expect(find.textContaining('This profile is unavailable.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    s.close();
  });

  testWidgets('failed quiet profile refresh clears stale green presence', (
    t,
  ) async {
    final s = PresenceStore();
    await fixtures.mount(
      t,
      SocialProfileWallScreen(
        client: s.client,
        me: fixtures.me,
        member: s.member,
        categories: fixtures.categories,
      ),
    );
    s.fail = true;
    await t.pump(const Duration(seconds: 16));
    await t.pumpAndSettle();
    expect(find.text('● Online'), findsNothing);
    expect(find.text('● Status unavailable'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    s.close();
  });

  testWidgets(
    'topic presence refresh preserves caption and recorded voice draft',
    (t) async {
      final s = PresenceStore();
      await fixtures.mount(
        t,
        SocialTopicScreen(
          client: s.client,
          me: fixtures.me,
          id: 'topic',
          categories: fixtures.categories,
          voiceNotePicker: () async => voice.voiceDraft(),
        ),
      );
      await voice.tapKey(t, 'wall-record-voice');
      await t.enterText(
        find.byKey(const ValueKey('wall-reply-text')),
        'Keep this caption while status changes',
      );
      s.online = false;
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('wall-voice-draft')), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('wall-reply-text')))
            .controller!
            .text,
        'Keep this caption while status changes',
      );
      expect(s.calls.where((c) => c == 'topic').length, 2);
      expect(
        s.calls.where((c) => c == 'reply' || c == 'attachment_upload'),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
      s.close();
    },
  );

  testWidgets('quiet topic refresh preserves all loaded reply pages', (
    t,
  ) async {
    final s = PresenceStore()..replyCount = 45;
    await fixtures.mount(
      t,
      SocialTopicScreen(
        client: s.client,
        me: fixtures.me,
        id: 'topic',
        categories: fixtures.categories,
      ),
    );
    await t.scrollUntilVisible(
      find.text('Load more replies'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Load more replies'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('wall-reply-text')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.enterText(
      find.byKey(const ValueKey('wall-reply-text')),
      'Draft after page two',
    );
    s.online = false;
    final reads = s.calls.where((c) => c == 'topic').length;
    await t.pump(const Duration(seconds: 16));
    await t.pumpAndSettle();
    expect(s.calls.where((c) => c == 'topic').length, reads + 2);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('wall-reply-text')))
          .controller!
          .text,
      'Draft after page two',
    );
    await t.scrollUntilVisible(
      find.text('Reply 45'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Reply 45'), findsOneWidget);
    expect(find.text('Load more replies'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.close();
  });

  testWidgets('account change invalidates an in-flight profile refresh', (
    t,
  ) async {
    final s = PresenceStore();
    await fixtures.mount(
      t,
      SocialProfileWallScreen(
        client: s.client,
        me: fixtures.me,
        member: s.member,
        categories: fixtures.categories,
      ),
    );
    s.gate = Completer<void>();
    await t.pump(const Duration(seconds: 16));
    s.token = 'Bearer presence-two';
    s.revision.value++;
    s.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('● Online'), findsNothing);
    expect(find.text(fixtures.peer['name']), findsNothing);
    await t.pumpWidget(const SizedBox());
    s.close();
  });
}

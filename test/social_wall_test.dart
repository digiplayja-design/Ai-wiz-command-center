import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_forms.dart';
import 'package:ai_wiz_command_center/social/social_profile_details.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_wall.dart';

import 'agent_studio_test.dart' as fixtures;
import 'social_invites_test.dart' as actions;
import 'social_test.dart' as social;

class WallStore {
  final calls = <SocialMap>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer wall-owner';
  bool connected = false, incoming = false, blocked = false;
  SocialMap owner = {
    ...social.me,
    'status_caption': 'Building something good today.',
    'home_country': 'Jamaica',
    'city': 'Kingston',
  };
  SocialMap member = {
    ...social.peer,
    'status_caption': 'Always finding a new perspective.',
    'home_country': 'Canada',
    'city': 'Toronto',
    'profession': 'Designer',
    'favorite_food': 'Curry goat',
  };
  final posts = <SocialMap>[
    {
      ...social.topic,
      'id': 'peer-post',
      'surface': 'wall',
      'title': 'A new perspective',
      'body': 'A public conversation for our community.',
      'reply_count': 0,
    },
    {
      ...social.topic,
      'id': 'own-post',
      'surface': 'wall',
      'title': 'My first update',
      'body': 'Sharing what I am creating this week.',
      'author': social.me,
      'reply_count': 0,
    },
  ];
  Future<http.Response?> Function(http.Request request, SocialMap data)? before;

  http.Response response(SocialMap value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.pathSegments.last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : socialMap(r.url.queryParameters);
      calls.add({'action': action, 'method': r.method, ...data});
      final intercepted = await before?.call(r, data);
      if (intercepted != null) return intercepted;
      final profile = {
        ...member,
        if (connected || incoming)
          'connection': connected ? 'accepted' : 'pending',
        if (incoming && !connected) 'incoming': true,
      };
      if (action == 'bootstrap') {
        return response({
          'profile': owner,
          'categories': social.categories,
          'moderator': false,
        });
      }
      if (action == 'wall') {
        final feed = data['feed'];
        final memberId = data['member'];
        final visible = posts.where((post) {
          final author = socialMap(post['author'])['id'];
          if (blocked && author == member['id']) return false;
          if (memberId != null) return author == memberId;
          if (feed == 'mine') return author == owner['id'];
          if (feed == 'following') return author == owner['id'] || connected;
          return true;
        });
        final offset = int.tryParse('${data['offset'] ?? 0}') ?? 0;
        return response({'items': visible.skip(offset).take(21).toList()});
      }
      if (action == 'member') {
        if (blocked && data['peer'] == member['id']) {
          return response({'error': 'This profile is unavailable.'}, 404);
        }
        return response({
          'profile': data['peer'] == owner['id'] ? owner : profile,
        });
      }
      if (action == 'members' || action == 'connections') {
        return response({
          'items': blocked ? [] : [profile],
        });
      }
      if (action == 'save_profile') {
        owner = {...owner, ...data};
        return response({'profile': owner});
      }
      if (action == 'accept') {
        connected = true;
        incoming = false;
      }
      if (action == 'block') {
        connected = false;
        blocked = true;
      }
      if (action == 'remove') connected = false;
      if (action == 'create_topic') {
        posts.insert(0, {
          ...data,
          'author': owner,
          'reply_count': 0,
          'created_at': '2026-10-03T15:00:00Z',
          'updated_at': '2026-10-03T15:00:00Z',
          'locked': false,
        });
        return response({'id': data['id']});
      }
      if (action == 'edit_topic') {
        final index = posts.indexWhere((post) => post['id'] == data['id']);
        posts[index] = {...posts[index], ...data};
        return response({'id': data['id']});
      }
      if (action == 'topic') {
        return response({
          'topic': posts.singleWhere((post) => post['id'] == data['id']),
          'items': [],
        });
      }
      return response({});
    }),
  );

  void switchAccount() {
    token = 'Bearer another-wall-account';
    revision.value++;
  }
}

Finder field(String id) => find.byKey(ValueKey('social-profile-field-$id'));
Finder audience(String id) =>
    find.byKey(ValueKey('social-profile-visibility-$id'));
Finder feed(String id) => find.byKey(ValueKey('social-wall-feed-$id'));

Future<void> enter(WidgetTester t, Finder finder, String value) async {
  await actions.reveal(t, finder);
  await t.enterText(finder, value);
  await t.pumpAndSettle();
}

Future<void> selectAudience(WidgetTester t, String id, String label) async {
  await actions.tap(t, audience(id));
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  testWidgets(
    'Wall opens on Following and keeps Explore and My wall distinct',
    (t) async {
      final s = WallStore();
      await social.mount(t, SocialScreen(client: s.client));
      expect(
        s.calls.firstWhere((c) => c['action'] == 'wall')['feed'],
        'following',
      );
      expect(find.byKey(const ValueKey('social-write-wall')), findsOneWidget);
      await actions.reveal(t, find.text('My first update'));
      expect(find.text('A new perspective'), findsNothing);
      await actions.tap(t, feed('explore'));
      await actions.reveal(t, find.text('A new perspective'));
      expect(find.text('A new perspective'), findsOneWidget);
      await actions.tap(t, feed('mine'));
      await actions.reveal(t, find.text('My first update'));
      expect(find.text('A new perspective'), findsNothing);
      expect(s.calls.lastWhere((c) => c['action'] == 'wall')['feed'], 'mine');
      expect(s.calls.where((c) => c['action'] == 'create_topic'), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets(
    'wall post supports a blank headline, explicit publish, open and edit',
    (t) async {
      final s = WallStore();
      await social.mount(t, SocialScreen(client: s.client));
      await actions.tap(t, find.byKey(const ValueKey('social-write-wall')));
      expect(s.calls.where((c) => c['action'] == 'create_topic'), isEmpty);
      await enter(
        t,
        find.byKey(const ValueKey('social-wall-body')),
        'Today we build something useful.',
      );
      await actions.tap(t, find.byKey(const ValueKey('social-wall-publish')));
      final saved = s.calls.singleWhere((c) => c['action'] == 'create_topic');
      expect(saved['title'], '');
      expect(saved['surface'], 'wall');
      expect(saved.containsKey('category'), false);
      expect(find.text('Wall thread'), findsOneWidget);
      await actions.reveal(t, find.text('Today we build something useful.'));
      await actions.tap(t, find.byTooltip('Wall post options'));
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await enter(
        t,
        find.byKey(const ValueKey('social-wall-body')),
        'An updated public thought.',
      );
      await actions.tap(t, find.text('Save changes'));
      expect(
        s.calls.singleWhere((c) => c['action'] == 'edit_topic')['surface'],
        'wall',
      );
      await actions.reveal(t, find.text('An updated public thought.'));
      expect(find.text('An updated public thought.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets(
    'profile fetch supplies fresh optional details and omits hidden fields',
    (t) async {
      final s = WallStore();
      await social.mount(t, SocialScreen(client: s.client));
      await actions.tap(t, feed('explore'));
      await actions.tap(t, find.byKey(const ValueKey('wall-author-peer-post')));
      expect(
        s.calls.where((c) => c['action'] == 'member' && c['peer'] == 'peer'),
        hasLength(1),
      );
      await actions.reveal(t, find.text('Always finding a new perspective.'));
      await actions.tap(t, find.byKey(const ValueKey('social-profile-about')));
      await actions.reveal(t, find.text('Toronto'));
      expect(find.text('Toronto'), findsOneWidget);
      await actions.reveal(t, find.text('Curry goat'));
      expect(
        find.byKey(const ValueKey('social-profile-detail-phone_number')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('social-profile-detail-income_level')),
        findsNothing,
      );
      expect(find.text('Only me'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets('optional profile fields save audiences and can all be cleared', (
    t,
  ) async {
    final s = WallStore();
    final values = <String, String>{
      'status_caption': 'A little color in every day.',
      'home_country': 'Jamaica',
      'city': 'Kingston',
      'phone_number': '+1 555 010 2000',
      'profession': 'Developer',
      'current_job': 'Building KORLIX',
      'marital_status': 'Married',
      'income_level': 'Prefer to discuss privately',
      'favorite_color': 'Cyan',
      'favorite_food': 'Ackee and saltfish',
    };
    await social.mount(t, SocialScreen(client: s.client));
    await actions.tap(t, find.byKey(const ValueKey('social-update-status')));
    for (final value in values.entries) {
      await enter(t, field(value.key), value.value);
    }
    await selectAudience(t, 'city', 'Followers');
    await selectAudience(t, 'status_caption', 'Only me');
    await actions.tap(t, find.text('Save profile'));
    var saved = s.calls.lastWhere((c) => c['action'] == 'save_profile');
    for (final value in values.entries) {
      expect(saved[value.key], value.value);
    }
    expect(socialMap(saved['profile_visibility'])['phone_number'], 'private');
    expect(socialMap(saved['profile_visibility'])['income_level'], 'private');
    expect(socialMap(saved['profile_visibility'])['city'], 'connections');
    expect(socialMap(saved['profile_visibility'])['status_caption'], 'private');
    expect(find.text(values['status_caption']!), findsOneWidget);
    await actions.tap(t, find.byKey(const ValueKey('social-update-status')));
    for (final id in values.keys) {
      await enter(t, field(id), '');
    }
    await actions.tap(t, find.text('Save profile'));
    saved = s.calls.lastWhere((c) => c['action'] == 'save_profile');
    for (final id in values.keys) {
      expect(saved[id], '');
    }
    expect(find.text(values['status_caption']!), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.revision.dispose();
  });

  testWidgets(
    'late wall response cannot repopulate an account after sign out',
    (t) async {
      final s = WallStore();
      final pending = Completer<http.Response>();
      await social.mount(t, SocialScreen(client: s.client));
      s.before = (r, data) async =>
          r.url.pathSegments.last == 'wall' && data['feed'] == 'explore'
          ? pending.future
          : null;
      await t.tap(feed('explore'));
      await t.pump();
      s.switchAccount();
      await t.pump();
      pending.complete(s.response({'items': s.posts}));
      await t.pumpAndSettle();
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.text('A new perspective'), findsNothing);
      expect(find.text('Building something good today.'), findsNothing);
      expect(find.byKey(const ValueKey('social-write-wall')), findsNothing);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets('changing feed discards a late response from the previous feed', (
    t,
  ) async {
    final s = WallStore();
    final pending = Completer<http.Response>();
    await social.mount(t, SocialScreen(client: s.client));
    s.before = (r, data) async =>
        r.url.pathSegments.last == 'wall' && data['feed'] == 'explore'
        ? pending.future
        : null;
    await t.tap(feed('explore'));
    await t.pump();
    await t.tap(feed('mine'));
    await t.pump();
    pending.complete(
      s.response({
        'items': [s.posts.first],
      }),
    );
    await t.pumpAndSettle();
    await actions.reveal(t, find.text('My first update'));
    expect(find.text('A new perspective'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.revision.dispose();
  });

  testWidgets(
    'wall pagination requests the next twenty and retains existing posts',
    (t) async {
      final s = WallStore();
      s.posts
        ..clear()
        ..addAll(
          List.generate(
            23,
            (i) => {
              ...social.topic,
              'id': 'post-$i',
              'title': 'Public update $i',
              'surface': 'wall',
              'author': social.me,
            },
          ),
        );
      await social.mount(t, SocialScreen(client: s.client), width: 1024);
      await actions.tap(t, find.text('Load more'));
      expect(s.calls.lastWhere((c) => c['action'] == 'wall')['offset'], '20');
      await actions.reveal(t, find.text('Public update 22'));
      expect(find.text('Load more'), findsNothing);
      await actions.reveal(t, find.text('Public update 0'));
      expect(find.text('Public update 0'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets(
    'accepting a profile follow adds their posts and blocking removes them',
    (t) async {
      final s = WallStore()..incoming = true;
      s.before = (r, data) async =>
          r.url.pathSegments.last == 'wall' && s.blocked
          ? s.response({'error': 'Temporary feed interruption.'}, 503)
          : null;
      await social.mount(t, SocialScreen(client: s.client));
      await actions.tap(t, feed('explore'));
      await actions.tap(t, find.byKey(const ValueKey('wall-author-peer-post')));
      await actions.tap(t, find.text('Accept follow'));
      expect(s.connected, true);
      await t.pageBack();
      await t.pumpAndSettle();
      await actions.tap(t, feed('following'));
      await actions.reveal(t, find.text('A new perspective'));
      expect(find.text('A new perspective'), findsOneWidget);
      await actions.tap(t, find.byKey(const ValueKey('wall-author-peer-post')));
      await t.tap(find.byTooltip('Member options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Block member'));
      await t.pumpAndSettle();
      await t.tap(find.text('Block member').last);
      await t.pumpAndSettle();
      expect(s.blocked, true);
      await actions.reveal(t, find.text('My first update'));
      expect(find.text('A new perspective'), findsNothing);
      expect(s.calls.where((c) => c['action'] == 'send'), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    },
  );

  testWidgets(
    'removing a connection purges follower details even when refresh fails',
    (t) async {
      final s = WallStore()..connected = true;
      s.member['phone_number'] = '+1 555 010 4444';
      await social.mount(
        t,
        SocialProfileWallScreen(
          client: s.client,
          me: s.owner,
          member: s.member,
          categories: social.categories,
        ),
      );
      await actions.tap(t, find.byKey(const ValueKey('social-profile-about')));
      await actions.reveal(t, find.text('+1 555 010 4444'));
      s.before = (r, data) async =>
          r.url.pathSegments.last == 'member' && !s.connected
          ? s.response({'error': 'Temporary profile interruption.'}, 503)
          : null;
      await t.tap(find.byTooltip('Member options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove connection'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove').last);
      await t.pumpAndSettle();
      expect(s.connected, false);
      expect(find.text('+1 555 010 4444'), findsNothing);
      expect(find.text('Jordan Rivera'), findsNothing);
      expect(find.text('Temporary profile interruption.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.client.dispose();
      s.revision.dispose();
    },
  );

  testWidgets('profile and unpublished details clear on account change', (
    t,
  ) async {
    final s = WallStore();
    await social.mount(
      t,
      SocialProfileForm(client: s.client, profile: s.owner),
    );
    await enter(t, field('phone_number'), '+1 555 010 9999');
    s.switchAccount();
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(field('phone_number')).controller!.text, '');
    for (final detail in socialProfileFields) {
      expect(t.widget<TextFormField>(field(detail.id)).controller!.text, '');
    }
    expect(s.calls.where((c) => c['action'] == 'save_profile'), isEmpty);
    await t.pumpWidget(const SizedBox());
    s.client.dispose();
    s.revision.dispose();
  });

  for (final width in [320.0, 1024.0]) {
    testWidgets('wall, profile and optional details fit $width with scaled text', (
      t,
    ) async {
      final s = WallStore()..connected = true;
      s.member.addAll({
        'profession':
            'Community development and accessible digital product design specialist working across the Caribbean',
        'current_job':
            'Creating useful technology with an international team and supporting small business owners in their community',
        'favorite_color':
            'Ocean blue, sunshine yellow and every shade in between',
        'marital_status': 'Prefer to describe this in my own words',
      });
      await social.mount(
        t,
        SocialScreen(client: s.client),
        width: width,
        height: 900,
        scale: width == 320 ? 1.4 : 1,
        theme: width == 320 ? 'pure_white' : 'korlix_blue',
      );
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-wall-${width.toInt()}');
      await actions.tap(t, find.byKey(const ValueKey('wall-author-peer-post')));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-profile-wall-${width.toInt()}');
      await actions.tap(t, find.byKey(const ValueKey('social-profile-about')));
      await actions.reveal(t, find.text('Toronto'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-profile-about-${width.toInt()}');
      await actions.reveal(
        t,
        find.byKey(const ValueKey('social-profile-detail-current_job')),
      );
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-profile-long-details-${width.toInt()}');
      await t.pageBack();
      await t.pumpAndSettle();
      await actions.tap(t, find.byKey(const ValueKey('social-update-status')));
      await actions.reveal(t, field('status_caption'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-profile-edit-${width.toInt()}');
      await actions.reveal(t, field('phone_number'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-profile-phone-${width.toInt()}');
      await t.pumpWidget(const SizedBox());
      s.revision.dispose();
    });
  }
}

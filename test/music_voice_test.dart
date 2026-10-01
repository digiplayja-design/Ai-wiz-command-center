import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_wiz_command_center/music_studio/music_client.dart';
import 'package:ai_wiz_command_center/music_studio/music_models.dart';
import 'package:ai_wiz_command_center/music_studio/music_voice.dart';
import 'package:ai_wiz_command_center/music_studio/music_voice_panel.dart';

const id = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Map<String, dynamic> recipe() => {
  ...blankMusic(),
  'idea': 'A bright reggae jingle for KORLIX',
  'title': 'Make your day',
  'style': 'reggae, warm',
  'duration': 30,
};
Map<String, dynamic> job({String jobId = id, String status = 'completed'}) => {
  'id': jobId,
  'status': status,
  'settings': recipe(),
  'favorite': false,
  'createdAt': '2026-10-01T15:00:00Z',
  'owner_id': 'private-owner',
  'task_id': 'private-provider-id',
  'tracks': [
    {
      'state': 'succeeded',
      'title': 'Make your day',
      'duration': 30,
      'audioUrl': 'https://cdn1.suno.ai/private-audio.mp3',
      'imageUrl': 'https://cdn1.suno.ai/private-cover.png',
      'lyrics': 'Private generated song lyrics',
    },
  ],
};
Map<String, dynamic> studio() => {
  'addon': {
    'active': true,
    'providerReady': true,
    'owner_email': 'private@example.test',
    'plans': [
      {'price': 'private-plan'},
    ],
    'usage': {
      'usedThisCycle': 1,
      'reservedThisCycle': 0,
      'monthlyLimit': 75,
      'remainingThisCycle': 74,
      'cycle': '2026-10',
    },
  },
  'jobs': [job()],
  'hasMore': false,
  'draft': {
    'version': 7,
    'data': {...recipe(), 'title': 'Older saved idea'},
  },
};
Map<String, dynamic> prepared(Map<String, dynamic> input) {
  final draft = checkedMusicVoiceRecipe(input);
  final description = [
    draft['idea'],
    if (draft['style'] != '') 'Style: ${draft['style']}',
  ].where((part) => part != '').join('\n');
  final ready = draft['mode'] == 'lyrics'
      ? draft['lyrics'] != ''
      : draft['idea'] != '' && description.length <= 400;
  return {
    'draft': draft,
    'saved': false,
    'review_required': true,
    'ready_for_generation': ready,
    'validation_message': ready ? null : 'Add your music idea or lyrics first.',
  };
}

String token(String sub, {String session = 'session-a', int exp = 1}) =>
    'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': sub, 'session_id': session, 'exp': exp}))).replaceAll('=', '')}.c';

class Session {
  String authorization = token('owner-a');
  final changes = ValueNotifier<int>(0);
  Map<String, String> headers() => {'Authorization': 'Bearer $authorization'};
  void change(String value) {
    authorization = value;
    changes.value++;
  }
}

class FakeMusic extends MusicClient {
  FakeMusic(this.session)
    : super(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: session.headers,
        sessionChanges: session.changes,
      );
  final Session session;
  Map<String, dynamic> data = studio();
  Map<String, dynamic>? draftResponse, statusResponse;
  Completer<Map<String, dynamic>>? loadWait, draftWait, statusWait;
  int loads = 0, drafts = 0, searches = 0, statuses = 0, writes = 0;
  String? lastQuery;
  bool? lastFavorites;
  Map<String, dynamic>? requested;
  @override
  Future<Map<String, dynamic>> load() async {
    loads++;
    if (loadWait != null) return loadWait!.future;
    return copy(data);
  }

  @override
  Future<Map<String, dynamic>> prepareVoiceDraft(
    Map<String, dynamic> body,
  ) async {
    drafts++;
    requested = copy(body);
    if (draftWait != null) return draftWait!.future;
    return copy(draftResponse ?? prepared(body));
  }

  @override
  Future<Map<String, dynamic>> jobs({
    String query = '',
    bool favorites = false,
    String? before,
  }) async {
    searches++;
    lastQuery = query;
    lastFavorites = favorites;
    return {'jobs': copy(data)['jobs'], 'hasMore': data['hasMore']};
  }

  @override
  Future<Map<String, dynamic>> status(String value) async {
    statuses++;
    if (statusWait != null) return statusWait!.future;
    return copy(
      statusResponse ??
          (data['jobs'] as List).cast<Map<String, dynamic>>().firstWhere(
            (row) => row['id'] == value,
          ),
    );
  }

  @override
  Future<Map<String, dynamic>> generate(Map<String, dynamic> body) async {
    writes++;
    throw StateError('Voice must never generate music');
  }

  @override
  Future<Map<String, dynamic>> saveDraft(Map<String, dynamic> body) async {
    writes++;
    throw StateError('Voice must never save a draft');
  }

  @override
  Future<Map<String, dynamic>> favorite(String value, bool selected) async {
    writes++;
    throw StateError('Voice must never change favorites');
  }

  @override
  Future<void> remove(String value) async {
    writes++;
    throw StateError('Voice must never remove a creation');
  }
}

void main() {
  late Session session;
  late FakeMusic client;
  late MusicVoiceController controller;
  var call = 0;
  Future<Map<String, dynamic>> invoke(
    String name, [
    dynamic args = const <String, dynamic>{},
  ]) => controller.handleToolCall(name, args, 'call-${call++}');
  setUp(() {
    session = Session();
    client = FakeMusic(session);
    controller = MusicVoiceController(client: client, workingDraft: recipe());
    call = 0;
  });
  tearDown(() {
    expect(client.writes, 0);
    controller.dispose();
    client.dispose();
    session.changes.dispose();
  });

  test(
    'tool allowlist has six non-generating operations and filters incomplete calls',
    () {
      expect(musicVoiceTools.map((row) => row['name']), [
        'get_music_context',
        'prepare_music_draft',
        'search_music_tracks',
        'load_music_idea',
        'select_music_track',
        'get_music_creation_status',
      ]);
      final output = [
        for (final name in ['get_music_context', 'generate_music'])
          {
            'type': 'function_call',
            'status': 'completed',
            'name': name,
            'call_id': 'a',
          },
      ];
      expect(
        musicVoiceCalls({'status': 'completed', 'output': output}).length,
        1,
      );
      expect(
        musicVoiceCalls({'status': 'incomplete', 'output': output}),
        isEmpty,
      );
      expect(
        musicVoiceCalls({
          'status': 'completed',
          'output': [
            {
              'type': 'function_call',
              'status': 'in_progress',
              'name': 'get_music_context',
              'call_id': 'b',
            },
          ],
        }),
        isEmpty,
      );
    },
  );

  test(
    'recipe preserves every field, trims text and distinguishes null from zero',
    () {
      final value = checkedMusicVoiceRecipe({
        ...recipe(),
        'lyrics': '  Verse\nChorus  ',
        'duration': null,
      });
      expect(value['lyrics'], 'Verse\nChorus');
      expect(value['duration'], isNull);
      expect(() => value['title'] = 'changed', throwsUnsupportedError);
      for (final invalid in [
        {...recipe(), 'duration': 0},
        {...recipe(), 'duration': 30.0},
        {...recipe(), 'duration': 361},
        {...recipe(), 'voice': 'cloned'},
        {...recipe(), 'mode': 'mastering'},
        {...recipe(), 'title': 'x' * 101},
        {...recipe(), 'lyrics': 'x' * 5001},
        {...recipe(), 'idea': '\u0000hidden'},
        {...recipe(), 'confirmed': true},
        {...recipe()}..remove('duration'),
      ]) {
        expect(
          () => checkedMusicVoiceRecipe(invalid),
          throwsA(isA<MusicException>()),
        );
      }
    },
  );

  test(
    'context uses unsaved recipe and strips owner, URL, provider and generated lyric data',
    () async {
      final result = await invoke('get_music_context');
      expect(result['success'], true);
      expect(result['working_draft']['title'], 'Make your day');
      expect(result['addon']['usage']['remainingThisCycle'], 74);
      final serialized = jsonEncode(result);
      for (final text in [
        'private-owner',
        'private-provider-id',
        'https://',
        'private@example.test',
        'private-plan',
        'Private generated song lyrics',
        'Older saved idea',
      ]) {
        expect(serialized, isNot(contains(text)));
      }
      expect(
        () => (result['addon']['usage'] as Map)['remainingThisCycle'] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => (controller.context['jobs'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'constructor snapshots caller recipe and exposes only immutable values',
    () {
      final input = recipe();
      final second = MusicVoiceController(client: client, workingDraft: input);
      input['title'] = 'Mutated outside';
      expect(second.workingDraft['title'], 'Make your day');
      expect(
        () => second.workingDraft['title'] = 'bad',
        throwsUnsupportedError,
      );
      second.dispose();
    },
  );

  test(
    'allowance counts must be genuine nonnegative integers, never silently zero',
    () async {
      for (final bad in ['74', null, -1, 74.0]) {
        client.data['addon']['usage'] = <String, dynamic>{
          ...client.data['addon']['usage'] as Map,
          'remainingThisCycle': bad,
        };
        expect((await invoke('get_music_context'))['success'], false);
        expect(controller.context, isEmpty);
      }
    },
  );

  test(
    'context limits recent results to eight and marks more results',
    () async {
      client.data['jobs'] = [
        for (var i = 1; i <= 9; i++)
          job(jobId: '0000000$i-1111-4111-8111-111111111111'),
      ];
      final result = await invoke('get_music_context');
      expect((result['jobs'] as List).length, 8);
      expect(result['has_more'], true);
      expect(
        (await invoke('get_music_creation_status', {
          'job_id': '00000009-1111-4111-8111-111111111111',
        }))['success'],
        false,
      );
      expect(client.statuses, 0);
    },
  );

  test(
    'prepared recipes stay unsaved and later context/refinement keeps new chorus',
    () async {
      await invoke('get_music_context');
      final next = {
        ...recipe(),
        'mode': 'lyrics',
        'lyrics': 'Original verse\nA memorable chorus',
      };
      final result = await invoke('prepare_music_draft', next);
      expect(result['saved'], false);
      expect(result['generated'], false);
      expect(result['review_required'], true);
      expect(result['ready_for_generation'], true);
      expect(controller.pendingDraft, next);
      expect(
        () => controller.pendingDraft!['title'] = 'bad',
        throwsUnsupportedError,
      );
      final context = await invoke('get_music_context');
      expect(context['working_draft'], next);
      expect(controller.pendingDraft, next);
      await invoke('prepare_music_draft', {
        ...context['working_draft'] as Map<String, dynamic>,
        'title': 'Better title',
      });
      expect(controller.pendingDraft!['lyrics'], next['lyrics']);
      expect(controller.pendingDraft!['title'], 'Better title');
    },
  );

  test(
    'incomplete recipe remains reviewable with authoritative validation message',
    () async {
      await invoke('get_music_context');
      final result = await invoke('prepare_music_draft', blankMusic());
      expect(result['success'], true);
      expect(result['ready_for_generation'], false);
      expect(controller.pendingDraft, blankMusic());
      expect(controller.pendingValidationMessage, contains('Add'));
      await invoke('get_music_context');
      expect(controller.pendingValidationMessage, contains('Add'));
    },
  );

  test(
    'draft rejects changed server fields, unknown fields, false readiness and writes',
    () async {
      await invoke('get_music_context');
      for (final response in [
        {
          ...prepared(recipe()),
          'draft': {...recipe(), 'duration': 60},
        },
        {
          ...prepared(recipe()),
          'draft': {...recipe(), 'secret': 'extra'},
        },
        {...prepared(recipe()), 'saved': true},
        {...prepared(recipe()), 'review_required': false},
        {...prepared(recipe()), 'ready_for_generation': false},
        {...prepared(recipe()), 'validation_message': 'Unexpected limitation'},
      ]) {
        client.draftResponse = response;
        expect(
          (await invoke('prepare_music_draft', recipe()))['success'],
          false,
        );
        expect(controller.pendingDraft, isNull);
      }
    },
  );

  test(
    'unknown tools, extra arguments, enormous args and incomplete recipe never dispatch',
    () async {
      for (final request in [
        ('generate_music', recipe()),
        ('save_music_draft', recipe()),
        ('get_music_context', {'user_id': 'other'}),
        ('prepare_music_draft', {...recipe(), 'consent': true}),
        ('search_music_tracks', {'query': 'x' * 81, 'favorites': false}),
        (
          'search_music_tracks',
          {'query': '', 'favorites': false, 'owner': 'other'},
        ),
        ('get_music_context', 'x' * 14001),
      ]) {
        expect((await invoke(request.$1, request.$2))['success'], false);
      }
      expect(client.loads + client.drafts + client.searches, 0);
    },
  );

  test(
    'search uses actual results, favorites flag and pagination marker',
    () async {
      client.data['hasMore'] = true;
      final result = await invoke('search_music_tracks', {
        'query': ' reggae ',
        'favorites': true,
      });
      expect(client.lastQuery, 'reggae');
      expect(client.lastFavorites, true);
      expect(result['has_more'], true);
      expect(result['jobs'][0]['job_id'], id);
      expect(jsonEncode(result), isNot(contains('https://')));
      expect(
        (await invoke('load_music_idea', {'job_id': id}))['success'],
        true,
      );
      expect(client.statuses, 1);
      expect(client.drafts, 1);
      expect(controller.pendingDraft, recipe());
    },
  );

  test('unknown IDs and indexes fail before status or playback', () async {
    await invoke('get_music_context');
    for (final args in [
      {'job_id': other, 'track_index': 0},
      {'job_id': id, 'track_index': -1},
      {'job_id': id, 'track_index': 0.0},
      {'job_id': id, 'track_index': 8},
      {'job_id': id, 'track_index': 0, 'audioUrl': 'https://attacker.test/a'},
    ]) {
      expect((await invoke('select_music_track', args))['success'], false);
    }
    expect(client.statuses, 0);
    expect(controller.pendingPlayback, isNull);
  });

  test(
    'owned ready track selection is metadata only and never starts playback',
    () async {
      await invoke('get_music_context');
      final result = await invoke('select_music_track', {
        'job_id': id,
        'track_index': 0,
      });
      expect(result['success'], true);
      expect(result['playing'], false);
      expect(controller.pendingPlayback, {
        'job_id': id,
        'track_index': 0,
        'title': 'Make your day',
      });
      expect(jsonEncode(result), isNot(contains('https://')));
      expect(client.statuses, 1);
      expect(
        () => controller.pendingPlayback!['track_index'] = 2,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'fresh mismatched job, missing index, unfinished and unsafe tracks cannot play',
    () async {
      await invoke('get_music_context');
      for (final response in [
        job(jobId: other),
        {...job(), 'tracks': []},
        {
          ...job(),
          'tracks': [
            {...(job()['tracks'] as List).first as Map, 'state': 'running'},
          ],
        },
        {
          ...job(),
          'tracks': [
            {
              ...(job()['tracks'] as List).first as Map,
              'audioUrl': 'http://unsafe.test/a',
            },
          ],
        },
      ]) {
        client.statusResponse = response;
        expect(
          (await invoke('select_music_track', {
            'job_id': id,
            'track_index': 0,
          }))['success'],
          false,
        );
        expect(controller.pendingPlayback, isNull);
      }
    },
  );

  test(
    'status reflects uncertain state and performs a single fresh read',
    () async {
      await invoke('get_music_context');
      client.statusResponse = {
        ...job(status: 'uncertain'),
        'error': 'Submission could not be confirmed',
      };
      final result = await invoke('get_music_creation_status', {'job_id': id});
      expect(result['job']['status'], 'uncertain');
      expect(result['job']['error'], contains('could not'));
      expect(client.statuses, 1);
      expect(client.drafts, 0);
    },
  );

  test(
    'same call ID deduplicates an inflight request and changed replay is rejected',
    () async {
      client.loadWait = Completer<Map<String, dynamic>>();
      final first = controller.handleToolCall('get_music_context', {}, 'same');
      final duplicate = controller.handleToolCall(
        'get_music_context',
        '{}',
        'same',
      );
      expect(client.loads, 1);
      expect(
        (await controller.handleToolCall('search_music_tracks', {
          'query': '',
          'favorites': false,
        }, 'same'))['success'],
        false,
      );
      client.loadWait!.complete(studio());
      expect(await first, await duplicate);
      expect(
        (await controller.handleToolCall(
          'get_music_context',
          {},
          'same',
        ))['success'],
        true,
      );
      expect(client.loads, 1);
    },
  );

  test('only one tool request is in flight', () async {
    client.loadWait = Completer<Map<String, dynamic>>();
    final first = invoke('get_music_context');
    expect(controller.busy, true);
    expect(
      (await invoke('search_music_tracks', {
        'query': '',
        'favorites': false,
      }))['success'],
      false,
    );
    expect(client.searches, 0);
    client.loadWait!.complete(studio());
    await first;
    expect(controller.busy, false);
  });

  test(
    'pause discards late draft and retired replay cannot resurrect it',
    () async {
      await invoke('get_music_context');
      client.draftWait = Completer<Map<String, dynamic>>();
      final pending = controller.handleToolCall(
        'prepare_music_draft',
        recipe(),
        'late',
      );
      controller.clearPending();
      client.draftWait!.complete(prepared(recipe()));
      expect((await pending)['discarded'], true);
      expect(controller.pendingDraft, isNull);
      expect(controller.context, isEmpty);
      expect(
        (await controller.handleToolCall(
          'prepare_music_draft',
          recipe(),
          'late',
        ))['discarded'],
        true,
      );
      expect(client.drafts, 1);
    },
  );

  test(
    'account change clears voice data and rejects late library/status results',
    () async {
      await invoke('get_music_context');
      client.statusWait = Completer<Map<String, dynamic>>();
      final pending = invoke('select_music_track', {
        'job_id': id,
        'track_index': 0,
      });
      session.change(token('owner-b'));
      expect(controller.available, false);
      expect(controller.context, isEmpty);
      client.statusWait!.complete(job());
      expect((await pending)['discarded'], true);
      expect(controller.pendingPlayback, isNull);
      expect((await invoke('get_music_context'))['discarded'], true);
    },
  );

  test('silent principal change also hides data before notification', () async {
    await invoke('get_music_context');
    session.authorization = token('owner-b');
    expect(controller.available, false);
    expect(controller.result, isEmpty);
    expect(controller.context, isEmpty);
  });

  test(
    'token rotation for same principal/session keeps the controller usable',
    () async {
      await invoke('get_music_context');
      session.change(token('owner-a', exp: 2));
      expect(controller.available, true);
      expect((await invoke('prepare_music_draft', recipe()))['success'], true);
    },
  );

  test(
    'clearPending resets conversation recipe and no job IDs survive',
    () async {
      await invoke('get_music_context');
      await invoke('prepare_music_draft', {
        ...recipe(),
        'title': 'New unsaved title',
      });
      controller.clearPending();
      expect(
        (await invoke('get_music_creation_status', {'job_id': id}))['success'],
        false,
      );
      expect(
        (await invoke('get_music_context'))['working_draft']['title'],
        'Make your day',
      );
    },
  );

  test('session call cap bounds provider status and searches', () async {
    for (var i = 0; i < 64; i++) {
      expect(
        (await invoke('search_music_tracks', {
          'query': '',
          'favorites': false,
        }))['success'],
        true,
      );
    }
    expect(
      (await invoke('search_music_tracks', {
        'query': '',
        'favorites': false,
      }))['success'],
      false,
    );
    expect(client.searches, 64);
  });

  test(
    'client fans out a 401 once without replacing the studio callback',
    () async {
      var studioNotices = 0, voiceNotices = 0;
      final real = MusicClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: session.headers,
        sessionChanges: session.changes,
        client: MockClient(
          (request) async => http.Response('{"error":"Sign in"}', 401),
        ),
      );
      void listen() {
        voiceNotices++;
        expect(real.sessionChanged, true);
      }

      real.onAccessDenied = () {
        studioNotices++;
        expect(real.sessionChanged, true);
      };
      real.addAccessDeniedListener(listen);
      await expectLater(real.load(), throwsA(isA<MusicException>()));
      await expectLater(real.load(), throwsA(isA<MusicException>()));
      expect(studioNotices, 1);
      expect(voiceNotices, 1);
      real.removeAccessDeniedListener(listen);
      real.dispose();
    },
  );

  test(
    'client voice draft transport posts only to validation endpoint',
    () async {
      final requests = <http.Request>[];
      final real = MusicClient(
        backendBaseUrl: 'https://fixture.test/',
        headersBuilder: session.headers,
        sessionChanges: session.changes,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(prepared(recipe())), 200);
        }),
      );
      final response = await real.prepareVoiceDraft(recipe());
      expect(response['saved'], false);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/music/voice/draft');
      expect(jsonDecode(requests.single.body), recipe());
      real.dispose();
    },
  );

  testWidgets(
    'panel shows reviewable unsaved recipe and explicit creation cost',
    (tester) async {
      await invoke('get_music_context');
      await invoke('prepare_music_draft', {
        ...recipe(),
        'mode': 'lyrics',
        'lyrics': 'Original lyrics\nA new chorus',
      });
      var reviewed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MusicVoicePanel(
                controller: controller,
                onReview: () async {
                  reviewed++;
                },
                onListen: null,
                onDismiss: controller.clearPending,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Unsaved idea · No music generated'), findsOneWidget);
      expect(
        find.textContaining('uses 1 Music Production creation'),
        findsOneWidget,
      );
      expect(find.text('Original lyrics\nA new chorus'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('music-voice-review')),
      );
      await tester.tap(find.byKey(const ValueKey('music-voice-review')));
      expect(reviewed, 1);
      expect(client.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'panel renders actual ready version and listen action without autoplay',
    (tester) async {
      await invoke('get_music_context');
      await invoke('select_music_track', {'job_id': id, 'track_index': 0});
      var listened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MusicVoicePanel(
                controller: controller,
                onReview: null,
                onListen: () async {
                  listened++;
                },
                onDismiss: controller.clearPending,
              ),
            ),
          ),
        ),
      );
      expect(listened, 0);
      expect(find.text('Make your day · Version 1'), findsOneWidget);
      expect(find.text('Ready to play'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('music-voice-listen')),
      );
      await tester.tap(find.byKey(const ValueKey('music-voice-listen')));
      expect(listened, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

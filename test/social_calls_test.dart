import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'package:ai_wiz_command_center/social/social_forms.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class FakeMedia extends SocialCallMedia {
  int opened = 0, closed = 0, offers = 0, answers = 0;
  bool stopped = false, deny = false;
  Completer<void>? permission;
  final descriptions = <String>[], candidates = <SocialMap>[];
  @override
  Future<void> open(bool video, List<dynamic> servers) async {
    opened++;
    if (deny) throw StateError('Permission denied');
    if (permission != null) await permission!.future;
    if (stopped) return;
    camera = video;
    ready = true;
  }

  @override
  Future<String> offer() async {
    offers++;
    return 'caller-sdp';
  }

  @override
  Future<String> answer() async {
    answers++;
    return 'callee-sdp';
  }

  @override
  Future<void> description(String kind, String sdp) async {
    descriptions.add('$kind:$sdp');
  }

  @override
  Future<void> candidate(SocialMap value) async {
    candidates.add(value);
  }

  @override
  Future<void> close() async {
    closed++;
    stopped = true;
    ready = false;
  }
}

class CallStore {
  String state = 'ringing', token = 'Bearer caller', id = 'call';
  final revision = ValueNotifier(0);
  final requests = <SocialMap>[], signals = <SocialMap>[];
  bool failPoll = false;
  SocialClient client(String who) => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {
      'Authorization': who == 'caller' ? token : 'Bearer callee',
      'Content-Type': 'application/json',
    },
    sessionChanges: revision,
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : request.url.queryParameters;
      requests.add({'who': who, 'action': action, ...data});
      SocialMap result = {};
      if (action == 'call_config') {
        result = {'enabled': true, 'relay': false, 'iceServers': []};
      }
      if (action == 'call_start') id = data['id'];
      if (action == 'call_accept') state = 'accepted';
      if (action == 'call_end') state = 'ended';
      if (action == 'call_poll' && failPoll) {
        return http.Response('{"error":"Account unavailable"}', 403);
      }
      if (action == 'call_signal') {
        signals.add({...data, 'seq': signals.length + 1, 'who': who});
      }
      if (action != 'call_config') {
        result = {
          'call': {
            'id': id,
            'state': state,
            'mode': 'video',
            'peer': social.peer,
          },
          'signals': action == 'call_poll'
              ? signals
                    .where(
                      (s) =>
                          s['who'] != who &&
                          s['seq'] > int.parse('${data['after'] ?? 0}'),
                    )
                    .toList()
              : [],
        };
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await Scrollable.ensureVisible(t.element(finder), alignment: .5);
  await t.pumpAndSettle();
}

void main() {
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
  test(
    'incoming call never opens devices until accepted, and end closes them',
    () async {
      final store = CallStore(),
          media = FakeMedia(),
          client = CallStore().client('callee');
      final controller = SocialCallController(
        client: client,
        peer: social.peer,
        video: true,
        incoming: {'id': store.id, 'state': 'ringing'},
        media: media,
      );
      await controller.initialize();
      expect(media.opened, 0);
      await controller.accept();
      expect(media.opened, 1);
      expect(controller.state, 'accepted');
      await controller.accept();
      expect(media.opened, 1);
      await controller.end('Call ended');
      expect(media.stopped, true);
      controller.dispose();
      client.dispose();
    },
  );
  test(
    'two controllers exchange offer, answer, queued candidates and mute status',
    () async {
      final store = CallStore(),
          caller = store.client('caller'),
          callee = store.client('callee');
      final aMedia = FakeMedia(), bMedia = FakeMedia();
      final a = SocialCallController(
        client: caller,
        peer: social.peer,
        video: true,
        media: aMedia,
      );
      await a.initialize();
      final b = SocialCallController(
        client: callee,
        peer: social.me,
        video: true,
        incoming: {'id': store.id, 'state': 'ringing'},
        media: bMedia,
      );
      await b.initialize();
      await b.accept();
      store.signals.add({
        'seq': 1,
        'who': 'caller',
        'kind': 'candidate',
        'payload': {
          'candidate': 'candidate:one',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });
      await a.poll();
      await b.poll();
      await a.poll();
      expect(aMedia.offers, 1);
      expect(bMedia.answers, 1);
      expect(bMedia.descriptions, ['offer:caller-sdp']);
      expect(aMedia.descriptions, ['answer:callee-sdp']);
      expect(bMedia.candidates.length, 1);
      aMedia.onState?.call('connected');
      bMedia.onState?.call('connected');
      expect(a.connected, true);
      expect(b.connected, true);
      a.toggleMicrophone();
      await Future<void>.delayed(Duration.zero);
      await b.poll();
      expect(bMedia.remoteMicrophone, false);
      await b.end('Call ended');
      await a.poll();
      expect(a.ended, true);
      expect(aMedia.stopped, true);
      a.dispose();
      b.dispose();
      caller.dispose();
      callee.dispose();
    },
  );
  test(
    'denied permissions never ring a connection and canceled permission requests never restart media',
    () async {
      final store = CallStore(),
          client = store.client('caller'),
          media = FakeMedia()..deny = true;
      final call = SocialCallController(
        client: client,
        peer: social.peer,
        video: true,
        media: media,
      );
      await call.initialize();
      expect(call.ended, true);
      expect(store.requests.where((r) => r['action'] == 'call_start'), isEmpty);
      expect(media.stopped, true);
      call.dispose();
      final lateMedia = FakeMedia()..permission = Completer<void>();
      final late = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: lateMedia,
      );
      final started = late.initialize();
      await Future<void>.delayed(Duration.zero);
      await late.end('Canceled');
      lateMedia.permission!.complete();
      await started;
      expect(lateMedia.stopped, true);
      expect(lateMedia.ready, false);
      expect(store.requests.where((r) => r['action'] == 'call_start'), isEmpty);
      late.dispose();
      client.dispose();
    },
  );
  test(
    'account changes and revoked access stop active devices immediately',
    () async {
      final store = CallStore(),
          client = store.client('caller'),
          media = FakeMedia();
      final call = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: media,
      );
      await call.initialize();
      store.token = 'Bearer changed';
      store.revision.value++;
      expect(call.ended, true);
      expect(media.stopped, true);
      call.dispose();
      client.dispose();
      final store2 = CallStore(),
          client2 = store2.client('caller'),
          media2 = FakeMedia();
      final call2 = SocialCallController(
        client: client2,
        peer: social.peer,
        video: true,
        media: media2,
      );
      await call2.initialize();
      store2.failPoll = true;
      await call2.poll();
      expect(call2.ended, true);
      expect(media2.stopped, true);
      call2.dispose();
      client2.dispose();
    },
  );
  test(
    'photo multipart filters JSON content type, uses auth and rejects late account responses',
    () async {
      final finished = Completer<http.Response>(), changed = ValueNotifier(0);
      var token = 'Bearer one';
      bool multipart = false;
      final client = SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {
          'Authorization': token,
          'Content-Type': 'application/json',
        },
        sessionChanges: changed,
        client: MockClient((r) async {
          multipart = r.headers['content-type']!.startsWith(
            'multipart/form-data; boundary=',
          );
          expect(r.headers['authorization'], 'Bearer one');
          expect(r.body, contains('name="photo"'));
          return finished.future;
        }),
      );
      final upload = client.uploadPhoto(Uint8List.fromList([1, 2, 3]));
      final check = expectLater(upload, throwsA(isA<SocialException>()));
      await Future<void>.delayed(Duration.zero);
      expect(multipart, true);
      token = 'Bearer two';
      changed.value++;
      finished.complete(http.Response('{"profile":{"name":"private"}}', 200));
      await check;
      client.dispose();
      changed.dispose();
    },
  );
  testWidgets(
    'profession section saves explicitly and profile layout fits mobile',
    (t) async {
      final store = social.Store();
      await social.mount(
        t,
        SocialProfileForm(
          client: store.client,
          profile: {...social.me, 'profession': 'Creative Director'},
        ),
        width: 390,
        theme: 'korlix_blue',
      );
      expect(find.text('Choose photo'), findsOneWidget);
      await fixtures.capture(t, 'social-profile-photo');
      final profession = find.widgetWithText(
        TextFormField,
        'Profession (optional)',
      );
      await reveal(t, profession);
      await t.enterText(profession, 'Registered Nurse');
      await fixtures.capture(t, 'social-profession');
      final save = find.text('Save profile');
      await reveal(t, save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(
        store.calls.singleWhere(
          (r) => r['action'] == 'save_profile',
        )['profession'],
        'Registered Nurse',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      store.client.dispose();
    },
  );
  testWidgets(
    'emoji picker inserts into the cursor and sends a real Unicode message',
    (t) async {
      final store = social.Store();
      await social.mount(
        t,
        SocialChatScreen(
          client: store.client,
          me: social.me,
          peer: social.peer,
          onCall: (_) async {},
        ),
        width: 390,
        theme: 'korlix_blue',
      );
      await t.enterText(find.byType(TextField), 'Hi friend');
      final field = t.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 3);
      await t.tap(find.byTooltip('Add emoji'));
      await t.pumpAndSettle();
      await fixtures.capture(t, 'social-emoji-picker');
      await t.tap(find.byTooltip('Smile'));
      await t.pumpAndSettle();
      expect(field.controller!.text, 'Hi 😀friend');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(store.messages.single['body'], 'Hi 😀friend');
      await fixtures.capture(t, 'social-chat-calling');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      store.client.dispose();
    },
  );
  testWidgets(
    'changing accounts clears the caller identity from an open call screen',
    (t) async {
      final store = CallStore(),
          client = store.client('caller'),
          media = FakeMedia();
      await social.mount(
        t,
        SocialCallScreen(
          client: client,
          peer: {...social.peer, 'profession': 'Designer'},
          video: true,
          incoming: {'id': 'incoming', 'state': 'ringing'},
          media: media,
        ),
      );
      expect(find.text('Jordan Rivera'), findsOneWidget);
      store.token = 'Bearer different-account';
      store.revision.value++;
      await t.pumpAndSettle();
      expect(find.text('Jordan Rivera'), findsNothing);
      expect(find.text('Designer'), findsNothing);
      expect(find.text('Connection'), findsOneWidget);
      expect(media.stopped, true);
      await t.pumpWidget(const SizedBox());
      client.dispose();
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'incoming call fits $width and declining never opens microphone',
      (t) async {
        final store = CallStore(),
            client = store.client('callee'),
            media = FakeMedia();
        await social.mount(
          t,
          SocialCallScreen(
            client: client,
            peer: {...social.peer, 'profession': 'Product Designer'},
            video: true,
            incoming: {'id': 'incoming', 'state': 'ringing'},
            media: media,
          ),
          width: width,
          scale: width == 320 ? 1.4 : 1,
          theme: 'korlix_blue',
        );
        expect(media.opened, 0);
        expect(t.takeException(), isNull);
        await fixtures.capture(t, 'social-call-${width.toInt()}');
        final decline = find.byTooltip('Decline');
        await reveal(t, decline);
        await t.tap(decline);
        await t.pumpAndSettle();
        expect(media.opened, 0);
        expect(media.stopped, true);
        expect(find.text('Call declined'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        client.dispose();
      },
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_media_widgets.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/social/social_voice_note.dart';

import 'agent_studio_test.dart' as fixtures;
import 'social_test.dart' as social;

class WallVoiceStore {
  final calls = <SocialMap>[];
  final uploads = <SocialMap>[];
  final replies = <SocialMap>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer first';
  String surface = 'wall';
  bool locked = false;
  bool failUpload = false, failReply = false;
  final replyFailures = <int>[];
  bool commitThenFail = false;
  Completer<void>? uploadGate, replyGate;

  SocialMap attachment(String id) => {
    'id': id,
    'scope': 'wall',
    'kind': 'voice',
    'filename': 'Voice note.wav',
    'duration_ms': 1500,
    'size_bytes': 72044,
  };

  SocialMap voiceReply({String body = 'A little encouragement for today.'}) => {
    'id': 'existing-reply',
    'seq': 1,
    'author': social.me,
    'body': body,
    'created_at': '2026-10-03T16:30:00Z',
    'updated_at': '2026-10-03T16:30:00Z',
    'attachment': attachment('existing-voice'),
  };

  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last;
      if (action == 'attachment_upload') {
        uploads.add({...r.url.queryParameters});
        expect(r.headers['content-type'], startsWith('multipart/form-data'));
        expect(r.bodyBytes, isNotEmpty);
        await uploadGate?.future;
        if (failUpload) {
          failUpload = false;
          return http.Response(
            '{"error":"Upload interrupted. Try again."}',
            503,
          );
        }
        return http.Response(
          jsonEncode({'attachment': attachment(r.url.queryParameters['id']!)}),
          200,
        );
      }
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : r.url.queryParameters;
      calls.add({'action': action, ...data});
      SocialMap result = {};
      if (action == 'topic') {
        result = {
          'topic': {
            ...social.topic,
            'id': 'wall-topic',
            'surface': surface,
            'title': '',
            'body': 'What small win made your day brighter?',
            'locked': locked,
          },
          'items': replies,
        };
      } else if (action == 'reply') {
        await replyGate?.future;
        if (replyFailures.isNotEmpty) {
          return http.Response(
            '{"error":"Publication response unavailable."}',
            replyFailures.removeAt(0),
          );
        }
        if (failReply) {
          failReply = false;
          return http.Response('{"error":"Please retry publishing."}', 503);
        }
        if (!replies.any((reply) => reply['id'] == data['reply_id'])) {
          replies.add({
            'id': data['reply_id'],
            'seq': replies.length + 1,
            'author': social.me,
            'body': data['body'],
            'created_at': '2026-10-03T16:30:00Z',
            'updated_at': '2026-10-03T16:30:00Z',
            if (data['attachment_id'] != null)
              'attachment': attachment('${data['attachment_id']}'),
          });
        }
        if (commitThenFail) {
          commitThenFail = false;
          return http.Response('{"error":"Confirmation interrupted."}', 503);
        }
        result = {'id': data['reply_id']};
      } else if (action == 'delete_reply') {
        replies.removeWhere((reply) => reply['id'] == data['id']);
      } else if (action == 'edit_reply') {
        final reply = replies.firstWhere((reply) => reply['id'] == data['id']);
        reply['body'] = data['body'];
        reply['updated_at'] = '2026-10-03T16:32:00Z';
      } else if (action == 'attachment_link') {
        result = {'url': 'https://fixture.test/authorized-note.wav'};
      }
      return http.Response(jsonEncode(result), 200);
    }),
  );

  List<SocialMap> get publishes =>
      calls.where((call) => call['action'] == 'reply').toList();

  void switchAccount() {
    token = 'Bearer second';
    revision.value++;
  }
}

class WallVoiceRecorder implements SocialRecorder {
  final stream = StreamController<Uint8List>();
  bool denied = false, disposed = false;
  int starts = 0, cancellations = 0;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    if (denied) throw const SocialException('Microphone permission denied.');
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    stream.add(Uint8List(4800));
    await stream.close();
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!stream.isClosed) unawaited(stream.close());
  }
}

SocialAttachmentDraft voiceDraft() => SocialAttachmentDraft(
  bytes: socialPcmToWav(Uint8List(72000)),
  filename: 'Voice note.wav',
  kind: 'voice',
);

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> tapKey(WidgetTester t, String value) async {
  if (key(value).evaluate().isEmpty) {
    await t.scrollUntilVisible(
      key(value),
      400,
      scrollable: find.byType(Scrollable).first,
    );
  }
  ScaffoldMessenger.of(t.element(key(value))).clearSnackBars();
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(key(value));
  await t.pumpAndSettle();
  await t.tap(key(value));
  await t.pump();
  if (find.byType(SocialVoiceNoteSheet).evaluate().isNotEmpty) {
    await t.pump(const Duration(milliseconds: 400));
  } else {
    await t.pumpAndSettle();
  }
}

Future<void> mountWall(
  WidgetTester t,
  WallVoiceStore store, {
  Future<SocialAttachmentDraft?> Function()? picker,
  SocialVoiceCapture Function()? captureFactory,
  double width = 390,
  double height = 844,
  double scale = 1,
  String theme = 'pure_black',
}) async {
  addTearDown(store.client.dispose);
  await social.mount(
    t,
    SocialTopicScreen(
      client: store.client,
      me: social.me,
      id: 'wall-topic',
      categories: social.categories,
      voiceNotePicker: picker,
      voiceCaptureFactory: captureFactory,
    ),
    width: width,
    height: height,
    scale: scale,
    theme: theme,
  );
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

  testWidgets('voice draft stays local until Publish and can be removed', (
    t,
  ) async {
    final s = WallVoiceStore();
    var picks = 0;
    await mountWall(
      t,
      s,
      picker: () async {
        picks++;
        return voiceDraft();
      },
    );
    expect(picks, 0);
    await tapKey(t, 'wall-record-voice');
    expect(picks, 1);
    expect(key('wall-voice-draft'), findsOneWidget);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(s.uploads, isEmpty);
    expect(s.publishes, isEmpty);
    await tapKey(t, 'wall-remove-voice');
    expect(key('wall-voice-draft'), findsNothing);
    expect(s.uploads, isEmpty);
    expect(t.takeException(), isNull);
  });

  for (final caption in ['', 'Cheering you on!']) {
    testWidgets(
      'publishes ${caption.isEmpty ? 'voice-only' : 'voice with caption'} to the wall topic',
      (t) async {
        final s = WallVoiceStore();
        await mountWall(t, s, picker: () async => voiceDraft());
        await tapKey(t, 'wall-record-voice');
        if (caption.isNotEmpty) {
          await t.enterText(key('wall-reply-text'), caption);
        }
        expect(s.uploads, isEmpty);
        await tapKey(t, 'wall-publish-reply');
        expect(s.uploads, hasLength(1));
        expect(s.uploads.single['topic'], 'wall-topic');
        expect(s.uploads.single['kind'], 'voice');
        expect(s.uploads.single.containsKey('peer'), false);
        expect(s.uploads.single.containsKey('group'), false);
        expect(s.publishes, hasLength(1));
        expect(s.publishes.single['body'], caption);
        expect(s.publishes.single['attachment_id'], s.uploads.single['id']);
        expect(s.replies, hasLength(1));
        expect(key('wall-voice-draft'), findsNothing);
        expect(find.byType(SocialAttachmentView), findsOneWidget);
        expect(
          s.calls.where((call) => call['action'] == 'attachment_link'),
          isEmpty,
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed upload preserves the caption and reuses attachment identity on retry',
    (t) async {
      final s = WallVoiceStore()..failUpload = true;
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await t.enterText(key('wall-reply-text'), 'Keep this caption.');
      await tapKey(t, 'wall-publish-reply');
      expect(s.uploads, hasLength(1));
      expect(s.publishes, isEmpty);
      expect(key('wall-voice-draft'), findsOneWidget);
      expect(find.text('Keep this caption.'), findsOneWidget);
      await tapKey(t, 'wall-publish-reply');
      expect(s.uploads, hasLength(2));
      expect(s.uploads.first['id'], s.uploads.last['id']);
      expect(s.publishes.single['body'], 'Keep this caption.');
      expect(s.replies, hasLength(1));
    },
  );

  testWidgets(
    'failed publication retries the same reply without uploading audio twice',
    (t) async {
      final s = WallVoiceStore()..failReply = true;
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await t.enterText(key('wall-reply-text'), 'Try this once more.');
      await tapKey(t, 'wall-publish-reply');
      expect(key('wall-voice-draft'), findsOneWidget);
      expect(s.replies, isEmpty);
      await tapKey(t, 'wall-publish-reply');
      expect(s.uploads, hasLength(1));
      expect(s.publishes, hasLength(2));
      expect(s.publishes.first['reply_id'], s.publishes.last['reply_id']);
      expect(
        s.publishes.first['attachment_id'],
        s.publishes.last['attachment_id'],
      );
      expect(s.replies, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'unconfirmed publication keeps the exact caption and audio immutable until retry',
    (t) async {
      final s = WallVoiceStore()..failReply = true;
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await t.enterText(key('wall-reply-text'), 'First caption');
      await tapKey(t, 'wall-publish-reply');
      expect(t.widget<TextField>(key('wall-reply-text')).enabled, false);
      expect(t.widget<TextButton>(key('wall-remove-voice')).onPressed, isNull);
      expect(
        t.widget<OutlinedButton>(key('wall-replace-voice')).onPressed,
        isNull,
      );
      await tapKey(t, 'wall-publish-reply');
      expect(s.uploads, hasLength(1));
      expect(s.publishes.first, s.publishes.last);
      expect(s.publishes.last['body'], 'First caption');
      expect(s.replies, hasLength(1));
    },
  );

  testWidgets(
    'pending upload blocks duplicate publishing and attachment changes',
    (t) async {
      final s = WallVoiceStore()..uploadGate = Completer<void>();
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await t.ensureVisible(key('wall-publish-reply'));
      await t.pumpAndSettle();
      await t.tap(key('wall-publish-reply'));
      await t.pump();
      await t.tap(key('wall-publish-reply'));
      await t.pump();
      expect(s.uploads, hasLength(1));
      expect(s.publishes, isEmpty);
      expect(t.widget<TextField>(key('wall-reply-text')).enabled, false);
      s.uploadGate!.complete();
      await t.pumpAndSettle();
      expect(s.publishes, hasLength(1));
      expect(s.replies, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('account change discards a pending picker result', (t) async {
    final s = WallVoiceStore();
    final picked = Completer<SocialAttachmentDraft?>();
    await mountWall(t, s, picker: () => picked.future);
    await t.ensureVisible(key('wall-record-voice'));
    await t.pumpAndSettle();
    await t.tap(key('wall-record-voice'));
    await t.pump();
    s.switchAccount();
    picked.complete(voiceDraft());
    await t.pumpAndSettle();
    expect(key('wall-voice-draft'), findsNothing);
    expect(s.uploads, isEmpty);
    expect(s.publishes, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'account change during upload prevents publishing to the next account',
    (t) async {
      final s = WallVoiceStore()..uploadGate = Completer<void>();
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await t.enterText(key('wall-reply-text'), 'Private unsent words');
      await t.ensureVisible(key('wall-publish-reply'));
      await t.pumpAndSettle();
      await t.tap(key('wall-publish-reply'));
      await t.pump();
      s.switchAccount();
      s.uploadGate!.complete();
      await t.pumpAndSettle();
      expect(key('wall-voice-draft'), findsNothing);
      expect(find.text('Private unsent words'), findsNothing);
      expect(s.publishes, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('closing the thread safely ignores a late recording result', (
    t,
  ) async {
    final s = WallVoiceStore();
    final picked = Completer<SocialAttachmentDraft?>();
    await mountWall(t, s, picker: () => picked.future);
    await t.ensureVisible(key('wall-record-voice'));
    await t.pumpAndSettle();
    await t.tap(key('wall-record-voice'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    picked.complete(voiceDraft());
    await t.pumpAndSettle();
    expect(s.uploads, isEmpty);
    expect(s.publishes, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'recording is opt-in and preview must be accepted before publishing',
    (t) async {
      final s = WallVoiceStore(), recorder = WallVoiceRecorder();
      await mountWall(
        t,
        s,
        captureFactory: () => SocialVoiceCapture(recorder: recorder),
      );
      await tapKey(t, 'wall-record-voice');
      expect(recorder.starts, 0);
      await t.tap(find.text('Start recording'));
      await t.pump();
      expect(recorder.starts, 1);
      recorder.stream.add(Uint8List(48000));
      await t.pump();
      await t.tap(find.text('Stop recording'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Use voice note'), findsOneWidget);
      expect(s.uploads, isEmpty);
      await fixtures.capture(t, 'wall-voice-recording-preview');
      await t.tap(find.text('Use voice note'));
      await t.pumpAndSettle();
      expect(key('wall-voice-draft'), findsOneWidget);
      expect(recorder.disposed, true);
      expect(recorder.cancellations, greaterThan(0));
      expect(s.uploads, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'microphone denial is recoverable and cancellation keeps the text reply',
    (t) async {
      final s = WallVoiceStore(), recorder = WallVoiceRecorder()..denied = true;
      await mountWall(
        t,
        s,
        captureFactory: () => SocialVoiceCapture(recorder: recorder),
      );
      await t.enterText(key('wall-reply-text'), 'My typed response');
      await tapKey(t, 'wall-record-voice');
      await t.tap(find.text('Start recording'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Microphone permission denied.'), findsOneWidget);
      expect(find.text('Start recording'), findsOneWidget);
      expect(find.text('Use voice note'), findsNothing);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('My typed response'), findsOneWidget);
      expect(key('wall-voice-draft'), findsNothing);
      expect(recorder.disposed, true);
      expect(s.uploads, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'account change cancels an active wall recording and removes its draft',
    (t) async {
      final s = WallVoiceStore(), recorder = WallVoiceRecorder();
      await mountWall(
        t,
        s,
        captureFactory: () => SocialVoiceCapture(recorder: recorder),
      );
      await tapKey(t, 'wall-record-voice');
      await t.tap(find.text('Start recording'));
      await t.pump();
      recorder.stream.add(Uint8List(48000));
      await t.pump();
      s.switchAccount();
      await t.pumpAndSettle();
      expect(recorder.cancellations, greaterThan(0));
      expect(find.text('Use voice note'), findsNothing);
      expect(key('wall-voice-draft'), findsNothing);
      expect(s.uploads, isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(recorder.disposed, true);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('rate-limited retry retains the exact unresolved publication', (
    t,
  ) async {
    final s = WallVoiceStore()..replyFailures.addAll([503, 429]);
    await mountWall(t, s, picker: () async => voiceDraft());
    await tapKey(t, 'wall-record-voice');
    await t.enterText(key('wall-reply-text'), 'Keep this exact reply.');
    await tapKey(t, 'wall-publish-reply');
    await tapKey(t, 'wall-publish-reply');
    expect(t.widget<TextField>(key('wall-reply-text')).enabled, false);
    expect(t.widget<TextButton>(key('wall-remove-voice')).onPressed, isNull);
    expect(
      t.widget<OutlinedButton>(key('wall-replace-voice')).onPressed,
      isNull,
    );
    await tapKey(t, 'wall-publish-reply');
    expect(s.uploads, hasLength(1));
    expect(s.publishes, hasLength(3));
    expect(
      s.publishes.every(
        (call) => jsonEncode(call) == jsonEncode(s.publishes.first),
      ),
      true,
    );
    expect(s.replies, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'refresh reconciles a published reply after its response was lost',
    (t) async {
      final s = WallVoiceStore()..commitThenFail = true;
      await mountWall(t, s, picker: () async => voiceDraft());
      await tapKey(t, 'wall-record-voice');
      await tapKey(t, 'wall-publish-reply');
      expect(key('wall-voice-draft'), findsOneWidget);
      expect(s.replies, hasLength(1));
      await t.tap(find.byTooltip('Refresh discussion'));
      await t.pumpAndSettle();
      expect(key('wall-voice-draft'), findsNothing);
      expect(find.byType(SocialAttachmentView), findsOneWidget);
      expect(s.publishes, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );

  for (final status in [403, 404]) {
    testWidgets(
      'access $status after upload clears the voice draft and thread',
      (t) async {
        final s = WallVoiceStore()..replyFailures.add(status);
        await mountWall(t, s, picker: () async => voiceDraft());
        await tapKey(t, 'wall-record-voice');
        await t.enterText(key('wall-reply-text'), 'No longer available');
        await tapKey(t, 'wall-publish-reply');
        expect(s.uploads, hasLength(1));
        expect(key('wall-voice-draft'), findsNothing);
        expect(find.text('No longer available'), findsNothing);
        expect(find.byType(SocialAttachmentView), findsNothing);
        expect(s.replies, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'voice reply is visible without autoplay and owner can remove it',
    (t) async {
      final s = WallVoiceStore();
      s.replies.add(s.voiceReply());
      await mountWall(t, s);
      expect(find.byType(SocialAttachmentView), findsOneWidget);
      expect(find.byTooltip('Play voice note'), findsOneWidget);
      expect(find.text('0:00 / 0:01'), findsOneWidget);
      expect(
        s.calls.where((call) => call['action'] == 'attachment_link'),
        isEmpty,
      );
      await t.ensureVisible(find.byTooltip('Reply options'));
      await t.tap(find.byTooltip('Reply options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(find.text('Remove this reply?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Remove'));
      await t.pumpAndSettle();
      expect(
        s.calls.where((call) => call['action'] == 'delete_reply'),
        hasLength(1),
      );
      expect(s.replies, isEmpty);
      expect(find.byType(SocialAttachmentView), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('editing a voice caption can leave a voice-only reply', (
    t,
  ) async {
    final s = WallVoiceStore();
    s.replies.add(s.voiceReply());
    await mountWall(t, s);
    await t.ensureVisible(find.byTooltip('Reply options'));
    await t.tap(find.byTooltip('Reply options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();
    final editor = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await t.enterText(editor, '');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(
      s.calls.where((call) => call['action'] == 'edit_reply').single['body'],
      '',
    );
    expect(s.replies.single['attachment'], isNotNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SocialAttachmentView), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final scenario in ['locked wall', 'forum']) {
    testWidgets('$scenario does not expose the wall voice composer', (t) async {
      final s = WallVoiceStore()
        ..locked = scenario == 'locked wall'
        ..surface = scenario == 'forum' ? 'forum' : 'wall';
      await mountWall(t, s, picker: () async => voiceDraft());
      expect(key('wall-record-voice'), findsNothing);
      expect(key('wall-voice-draft'), findsNothing);
      expect(s.uploads, isEmpty);
      expect(t.takeException(), isNull);
    });
  }

  for (final layout in [
    ('phone320', 320.0, 812.0, 1.0, 'pure_black'),
    ('phone390', 390.0, 844.0, 1.0, 'pure_black'),
    ('large-text', 390.0, 844.0, 2.0, 'pure_black'),
    ('tablet-light', 1024.0, 1366.0, 1.0, 'pure_white'),
  ]) {
    testWidgets('voice reply and draft fit ${layout.$1}', (t) async {
      final s = WallVoiceStore();
      s.replies.add(s.voiceReply());
      await mountWall(
        t,
        s,
        picker: () async => voiceDraft(),
        width: layout.$2,
        height: layout.$3,
        scale: layout.$4,
        theme: layout.$5,
      );
      await tapKey(t, 'wall-record-voice');
      await t.enterText(
        key('wall-reply-text'),
        'Sharing a little good news in my own voice.',
      );
      await t.ensureVisible(key('wall-voice-draft'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'wall-voice-${layout.$1}');
      await t.ensureVisible(key('wall-publish-reply'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(s.uploads, isEmpty);
    });
  }
}

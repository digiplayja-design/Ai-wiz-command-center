import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/social/social_media_widgets.dart';
import 'package:ai_wiz_command_center/social/social_voice_note.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class Recorder implements SocialRecorder {
  final stream = StreamController<Uint8List>();
  bool denied = false, disposed = false, failStop = false;
  int cancellations = 0;
  Completer<void>? startGate;
  @override
  Future<Stream<Uint8List>> start() async {
    if (denied) throw const SocialException('Microphone permission denied');
    await startGate?.future;
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('Interrupted recorder');
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
  }
}

class MediaStore {
  final calls = <SocialMap>[];
  final messages = <SocialMap>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer first';
  bool failSend = false;
  int uploads = 0;
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last;
      if (action == 'attachment_upload') {
        uploads++;
        expect(r.headers['content-type'], startsWith('multipart/form-data'));
        expect(r.bodyBytes, isNotEmpty);
        return http.Response(
          jsonEncode({
            'attachment': {
              'id': r.url.queryParameters['id'],
              'kind': r.url.queryParameters['kind'],
            },
          }),
          200,
        );
      }
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : r.url.queryParameters;
      calls.add({'action': action, ...data});
      SocialMap result = {};
      if (action.endsWith('messages')) {
        result = {
          'peer': social.peer,
          'group': {...social.peer, 'name': 'Design circle'},
          'items': messages,
        };
      }
      if (action.endsWith('send')) {
        if (failSend) {
          failSend = false;
          return http.Response('{"error":"Please retry"}', 503);
        }
        messages.add({
          'id': data['id'],
          'seq': messages.length + 1,
          'body': data['body'],
          'sender': 'me',
          'author': social.me,
          'created_at': '2026-09-29T00:00:00Z',
          'deleted': false,
          'attachment': {
            'id': data['attachment_id'],
            'kind': 'file',
            'filename': 'Project notes.pdf',
            'size_bytes': 1200,
          },
        });
        result = {'id': data['id']};
      }
      return http.Response(jsonEncode(result), 200);
    }),
  );
}

SocialAttachmentDraft draft(String kind) => SocialAttachmentDraft(
  bytes: kind == 'voice'
      ? socialPcmToWav(Uint8List(48000))
      : Uint8List.fromList('%PDF-fixture'.codeUnits),
  filename: kind == 'voice' ? 'Voice note.wav' : 'Project notes.pdf',
  kind: kind,
);
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
  test(
    'voice capture includes the final audio chunk and produces portable PCM WAV',
    () async {
      final recorder = Recorder();
      final c = SocialVoiceCapture(recorder: recorder);
      await c.start();
      recorder.stream.add(Uint8List(43200));
      await c.stop();
      expect(c.recording, false);
      expect(c.preview!.length, 48044);
      final data = ByteData.sublistView(c.preview!);
      expect(utf8.decode(c.preview!.sublist(0, 4)), 'RIFF');
      expect(data.getUint32(24, Endian.little), 24000);
      expect(data.getUint32(40, Endian.little), 48000);
      c.dispose();
    },
  );
  test(
    'failed stop cancels the microphone and never creates a draft',
    () async {
      final r = Recorder()..failStop = true;
      final c = SocialVoiceCapture(recorder: r);
      await c.start();
      r.stream.add(Uint8List(48000));
      await c.stop();
      expect(r.cancellations, greaterThan(0));
      expect(c.recording, false);
      expect(c.preview, isNull);
      c.dispose();
    },
  );
  test(
    'denied microphone and too-short audio stay recoverable without a draft',
    () async {
      final r = Recorder()..denied = true, c = SocialVoiceCapture(recorder: r);
      await c.start();
      expect(c.recording, false);
      expect(c.error, contains('permission'));
      expect(c.preview, isNull);
      r.denied = false;
      await c.start();
      await c.stop();
      expect(c.preview, isNull);
      expect(c.error, contains('too short'));
      c.dispose();
    },
  );
  test(
    'closing during permission request releases late microphone access',
    () async {
      final r = Recorder()..startGate = Completer<void>(),
          c = SocialVoiceCapture(recorder: r);
      final pending = c.start();
      c.dispose();
      r.startGate!.complete();
      await pending;
      expect(r.cancellations, greaterThanOrEqualTo(1));
      expect(c.preview, isNull);
    },
  );
  for (final group in [false, true]) {
    testWidgets(
      '${group ? 'group' : 'direct'} attachment requires Send; retries reuse uploaded bytes and message ID',
      (t) async {
        final s = MediaStore()..failSend = true;
        addTearDown(s.client.dispose);
        await social.mount(
          t,
          SocialChatScreen(
            client: s.client,
            me: social.me,
            peer: social.peer,
            groupChat: group,
            attachmentPicker: (kind) async => draft(kind),
          ),
        );
        await t.tap(find.text('File'));
        await t.pumpAndSettle();
        expect(s.uploads, 0);
        expect(find.text('Project notes.pdf'), findsOneWidget);
        await t.tap(find.byTooltip('Send message'));
        await t.pumpAndSettle();
        expect(s.uploads, 1);
        expect(find.text('Project notes.pdf'), findsOneWidget);
        await t.tap(find.byTooltip('Send message'));
        await t.pumpAndSettle();
        expect(s.uploads, 1);
        final sends = s.calls
            .where((x) => x['action'] == (group ? 'group_send' : 'send'))
            .toList();
        expect(sends.length, 2);
        expect(sends[0]['id'], sends[1]['id']);
        expect(sends[0]['attachment_id'], sends[1]['attachment_id']);
        expect(s.messages.length, 1);
        expect(t.takeException(), isNull);
        await fixtures.capture(
          t,
          group ? 'social-group-file-mobile' : 'social-file-mobile',
        );
      },
    );
  }
  testWidgets(
    'recorded voice draft survives phone layout at large text size and is cleared on account change',
    (t) async {
      final s = MediaStore();
      addTearDown(s.client.dispose);
      await social.mount(
        t,
        SocialChatScreen(
          client: s.client,
          me: social.me,
          peer: social.peer,
          attachmentPicker: (kind) async => draft(kind),
        ),
        width: 320,
        scale: 1.4,
      );
      await t.tap(find.text('Voice note'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Play voice note'), findsOneWidget);
      expect(s.uploads, 0);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-voice-draft-small-phone');
      s.token = 'Bearer second';
      s.revision.value++;
      await t.pumpAndSettle();
      expect(find.byTooltip('Play voice note'), findsNothing);
      expect(s.uploads, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'recording sheet previews locally and stops microphone when closed',
    (t) async {
      final s = MediaStore(), r = Recorder();
      final capture = SocialVoiceCapture(recorder: r);
      addTearDown(s.client.dispose);
      await social.mount(
        t,
        Scaffold(
          body: SocialVoiceNoteSheet(client: s.client, capture: capture),
        ),
        width: 390,
      );
      await t.tap(find.text('Start recording'));
      await t.pump();
      r.stream.add(Uint8List(48000));
      await t.pump();
      await t.tap(find.text('Stop recording'));
      await t.pumpAndSettle();
      expect(find.text('Use voice note'), findsOneWidget);
      expect(s.uploads, 0);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-voice-preview-mobile');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(r.cancellations, greaterThan(0));
      expect(r.disposed, true);
    },
  );
}

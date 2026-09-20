import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/meeting_copilot/k135z_capture_controller.dart';
import '../../lib/meeting_copilot/k135z_meeting_response.dart';
import '../../lib/meeting_copilot/k135z_response_player.dart';
import '../../lib/meeting_copilot/k135z_response_panel.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';

class Capture extends K135zCaptureController {
  Capture(KorlixZoomJsonTransport send)
    : super(
        agentId: 'agent',
        baseUri: Uri.parse('https://api.test'),
        headers: () => {'authorization': 'Bearer offline'},
        isCurrent: () => true,
        transport: send,
        cancelRequests: () {},
        watch: false,
      );
  bool active = true;
  final binding = <String, dynamic>{
    'context': {
      'tenantId': 'u',
      'userId': 'u',
      'agentId': 'agent',
      'sessionId': 's',
      'meetingUuid': 'meeting',
      'streamId': 'stream',
      'generation': 1,
    },
    'revision': 2,
    'authorityRevision': 1,
    'bindingRevision': 1,
  };
  @override
  Map<String, dynamic>? get responseBinding => active ? binding : null;
  void changed() => notifyListeners();
}

class Player implements K135zResponsePlayer {
  int plays = 0, stops = 0;
  Completer<void> completed = Completer<void>();
  @override
  bool get supported => true;
  @override
  Future<void> play(Uint8List bytes) {
    plays++;
    return completed.future;
  }

  @override
  void stop() {
    stops++;
  }
}

class Fixture {
  int now = 0, cancels = 0;
  final calls = <String>[];
  final player = Player();
  Completer<void>? hold;
  bool badAudio = false, badContext = false;
  late final Capture capture;
  late final K135zMeetingResponse response;
  Fixture() {
    capture = Capture(({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      Object? body,
    }) async {
      expect(headers['authorization'], 'Bearer offline');
      expect(headers['x-korlix-agent-id'], 'agent');
      final path = uri.path.split('/').last, b = body as Map<String, dynamic>;
      calls.add(path);
      if (hold != null) await hold!.future;
      final context = badContext
          ? {...b['context'], 'meetingUuid': 'other'}
          : b['context'];
      if (path == 'response')
        return KorlixZoomTransportResponse(
          statusCode: 200,
          body: jsonEncode({
            'ok': true,
            'draft': {
              'id': 'a' * 32,
              'text':
                  'From the recent captions, the team will review the draft.',
              'context': context,
              'coverage': 'partial',
              'validForMs': 90000,
            },
          }),
        );
      expect(path, 'response-voice');
      expect(b['approved'], true);
      expect(b.containsKey('text'), false);
      return KorlixZoomTransportResponse(
        statusCode: 200,
        body: jsonEncode({
          'ok': true,
          'voice': {
            'context': context,
            'draftId': 'a' * 32,
            'mimeType': 'audio/mpeg',
            'audio': base64Encode(
              badAudio ? [1, 2, 3] : [73, 68, 51, ...List.filled(100, 0)],
            ),
          },
        }),
      );
    });
    response = K135zMeetingResponse(
      capture: capture,
      player: player,
      cancelRequest: () {
        cancels++;
      },
      milliseconds: () => now,
    );
  }
  void dispose() {
    response.dispose();
    capture.dispose();
  }
}

void main() {
  test('draft and approval stay silent; broadcast acknowledgment plus Speak is required', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.response.draft();
    expect(f.response.text, isNotNull);
    expect(f.player.plays, 0);
    await f.response.prepare();
    await f.response.speak();
    expect(f.player.plays, 0);
    f.response.setBroadcast(true);
    final spoken = f.response.speak();
    expect(f.player.plays, 1);
    expect(f.response.playing, true);
    f.player.completed.complete();
    await spoken;
    expect(f.response.playing, false);
    expect(f.response.message, contains('Confirm with a participant'));
    expect(f.response.canSpeak, false);
    expect(f.response.canPrepare, false);
  });
  test('Stop while preparing cancels and rejects late audio', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.response.draft();
    f.hold = Completer<void>();
    final pending = f.response.prepare();
    f.response.stop();
    f.hold!.complete();
    await pending;
    expect(f.response.canSpeak, false);
    expect(f.response.text, isNull);
    expect(f.response.busy, false);
    expect(f.player.plays, 0);
    expect(f.cancels, greaterThan(0));
  });
  test('Stop during playback is immediate and late completion cannot change message', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.response.draft();
    await f.response.prepare();
    f.response.setBroadcast(true);
    final p = f.response.speak();
    final stops = f.player.stops;
    f.response.stop();
    expect(f.player.stops, stops + 1);
    expect(f.response.playing, false);
    f.player.completed.complete();
    await p;
    expect(f.response.message, startsWith('Nova stopped'));
  });
  test('permission loss, context change, revision change and expiry clear approval', () async {
    for (final change in <void Function(Fixture)>[
      (f) => f.capture.active = false,
      (f) => f.capture.binding['context']['meetingUuid'] = 'other',
      (f) => f.capture.binding['authorityRevision'] = 2,
      (f) => f.now = 80001,
    ]) {
      final f = Fixture();
      await f.response.draft();
      await f.response.prepare();
      f.response.setBroadcast(true);
      change(f);
      f.capture.changed();
      expect(f.response.text, isNull);
      expect(f.response.canSpeak, false);
      expect(f.response.broadcast, false);
      f.dispose();
    }
  });
  test('normal status updates preserve prepared response', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    await f.response.draft();
    await f.response.prepare();
    f.capture.changed();
    f.response.setBroadcast(true);
    expect(f.response.canSpeak, true);
  });
  test('changed context or invalid audio is never playable', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.badContext = true;
    await f.response.draft();
    expect(f.response.text, isNull);
    f.badContext = false;
    await f.response.draft();
    f.badAudio = true;
    await f.response.prepare();
    f.response.setBroadcast(true);
    expect(f.response.canSpeak, false);
    expect(f.player.plays, 0);
  });
  test('an older draft cannot overwrite a new one after Stop', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    final hold = Completer<void>();
    f.hold = hold;
    final old = f.response.draft();
    f.response.stop();
    f.hold = null;
    await f.response.draft();
    final text = f.response.text;
    hold.complete();
    await old;
    expect(f.response.text, text);
    expect(f.response.busy, false);
  });
  testWidgets(
    'mobile panel provides preview, explicit approval, Speak and Stop without overflow',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: K135zResponsePanel(response: f.response),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('nova-draft-update')));
      await tester.pumpAndSettle();
      expect(find.text(f.response.text!), findsOneWidget);
      expect(f.player.plays, 0);
      expect(find.byKey(const Key('nova-approve-voice')), findsOneWidget);
      expect(find.byKey(const Key('nova-stop-response')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

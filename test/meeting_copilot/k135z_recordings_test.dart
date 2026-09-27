import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_capture_controller.dart';
import '../../lib/meeting_copilot/k135z_recordings_controller.dart';
import '../../lib/meeting_copilot/k135z_recordings_panel.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';

class Capture extends K135zCaptureController {
  Capture(KorlixZoomJsonTransport send, bool Function() current)
    : super(
        agentId: 'agent',
        baseUri: Uri.parse('https://api.test'),
        headers: () => {'authorization': 'Bearer offline'},
        isCurrent: current,
        transport: send,
        cancelRequests: () {},
        watch: false,
      );
  bool active = true;
  final context = <String, dynamic>{
    'tenantId': 'u',
    'userId': 'u',
    'agentId': 'agent',
    'sessionId': 's',
    'meetingUuid': 'meeting',
    'streamId': 'stream',
    'generation': 1,
  };
  @override
  Map<String, dynamic>? get responseBinding =>
      active ? {'context': context} : null;
  void changed() => notifyListeners();
}

Map<String, dynamic> row({String? id, String status = 'ready'}) => {
  'id': id ?? 'a' * 32,
  'status': status,
  'createdAt': '2026-09-27T03:00:00Z',
  'durationMs': 123000,
  'byteSize': status == 'ready' ? 1000000 : 0,
  'meetingUuid': 'meeting',
  'endReason': null,
};
const media =
    'https://project.supabase.co/storage/v1/object/sign/korlix-meeting-recordings/owner/audio.mp3?token=offline';

class Fixture {
  bool current = true;
  final calls = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rows = [];
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? override;
  late final Capture capture;
  late final K135zRecordingsController c;
  Fixture() {
    capture = Capture(({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      Object? body,
    }) async {
      expect(method, 'POST');
      expect(uri.path, '/api/k135z/zoom/workspace/recordings');
      expect(headers['authorization'], 'Bearer offline');
      expect(headers['x-korlix-agent-id'], 'agent');
      final b = Map<String, dynamic>.from(body as Map);
      calls.add(b);
      Map<String, dynamic> data;
      if (override != null) {
        data = await override!(b);
      } else {
        data = switch (b['action']) {
          'list' => {'recordings': rows},
          'start' => {'recording': row(id: b['id'], status: 'recording')},
          'stop' => {'recording': row(id: b['id'], status: 'saving')},
          'play' => {
            'recording': row(id: b['id']),
            'url': media,
            'downloadUrl': '$media&download=audio.mp3',
          },
          'delete' => {'deleted': true},
          _ => throw StateError('unexpected action'),
        };
      }
      return KorlixZoomTransportResponse(
        statusCode: 200,
        body: jsonEncode({'ok': true, ...data}),
      );
    }, () => current);
    c = K135zRecordingsController(capture: capture, watch: false);
  }
  void dispose() {
    c.dispose();
    capture.dispose();
  }
}

void main() {
  test(
    'listening and opening controls never start recording without separate consent',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.c.start();
      await f.c.refresh();
      expect(f.calls.map((b) => b['action']), ['list']);
      f.c.setConsent(true);
      await f.c.start();
      expect(f.calls.last['consent'], true);
      expect(f.calls.last['context'], f.capture.context);
      expect(f.c.hasActive, true);
      expect(f.c.consent, false);
      await f.c.start();
      expect(f.calls.length, 2);
      await f.c.stop(f.c.recordings.single);
      expect(f.c.recordings.single.status, 'saving');
      expect(f.c.canStart, false);
    },
  );
  test('changing meeting or losing capture clears recording consent', () {
    final f = Fixture();
    addTearDown(f.dispose);
    f.c.setConsent(true);
    f.capture.context['meetingUuid'] = 'new';
    f.capture.changed();
    expect(f.c.consent, false);
    f.c.setConsent(true);
    f.capture.active = false;
    f.capture.changed();
    expect(f.c.consent, false);
    expect(f.c.canStart, false);
  });
  test('saved recordings remain accessible after listening ends', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.capture.active = false;
    f.rows = [row()];
    await f.c.refresh();
    await f.c.open(f.c.recordings.single);
    expect(f.c.playbackUrl.toString(), media);
    expect(f.c.downloadUrl, isNotNull);
    await f.c.remove(f.c.recordings.single);
    expect(f.c.recordings, isEmpty);
    expect(f.c.playbackUrl, isNull);
  });
  test(
    'sign-out discards late private results and clears playback immediately',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.rows = [row()];
      await f.c.refresh();
      await f.c.open(f.c.recordings.single);
      final gate = Completer<Map<String, dynamic>>();
      f.override = (_) => gate.future;
      final pending = f.c.refresh();
      f.current = false;
      f.capture.changed();
      expect(f.c.playbackUrl, isNull);
      expect(f.c.recordings, isEmpty);
      gate.complete({
        'recordings': [row()],
      });
      await pending;
      expect(f.c.recordings, isEmpty);
      expect(f.c.busy, false);
    },
  );
  test(
    'Stop remains available during a slow poll and late polling cannot revive recording',
    () async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.rows = [row(status: 'recording')];
      await f.c.refresh();
      final gate = Completer<Map<String, dynamic>>();
      f.override = (b) async => b['action'] == 'list'
          ? gate.future
          : {'recording': row(status: 'saving')};
      final polling = f.c.refresh(automatic: true);
      expect(f.c.busy, false);
      await f.c.stop(f.c.recordings.single);
      expect(f.calls.last['action'], 'stop');
      gate.complete({
        'recordings': [row(status: 'recording')],
      });
      await polling;
      expect(f.c.recordings.single.status, 'saving');
    },
  );
  test('invalid or unsafe playback results never become a media source', () async {
    for (final bad in [
      'http://project.test/storage/v1/object/sign/korlix-meeting-recordings/a',
      'javascript:alert(1)',
      'https://project.test/public/audio.mp3',
      'https://user:password@project.test/storage/v1/object/sign/korlix-meeting-recordings/a',
    ]) {
      final f = Fixture();
      f.rows = [row()];
      await f.c.refresh();
      f.override = (_) async => {
        'recording': row(),
        'url': bad,
        'downloadUrl': bad,
      };
      await f.c.open(f.c.recordings.single);
      expect(f.c.playbackUrl, isNull);
      f.dispose();
    }
  });
  test('playback and deletion cannot act on an active recording', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.rows = [row(status: 'recording')];
    await f.c.refresh();
    await f.c.open(f.c.recordings.single);
    await f.c.remove(f.c.recordings.single);
    expect(f.calls.length, 1);
  });
  test('refresh clears playback of an entry deleted elsewhere', () async {
    final f = Fixture();
    addTearDown(f.dispose);
    f.rows = [row()];
    await f.c.refresh();
    await f.c.open(f.c.recordings.single);
    f.rows = [];
    await f.c.refresh();
    expect(f.c.playbackUrl, isNull);
  });
  for (final width in [390.0, 1024.0]) {
    testWidgets(
      'recording controls at width $width require consent and confirm deletion',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = Fixture();
        addTearDown(f.dispose);
        f.rows = [row()];
        int paused = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: K135zRecordingsPanel(
                  controller: f.c,
                  beforePlayback: () => paused++,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Meeting audio recording'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('nova-recording-start')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('nova-recording-consent')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('nova-recording-start')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.ensureVisible(find.text('Open recording'));
        await tester.tap(find.text('Open recording'));
        await tester.pumpAndSettle();
        expect(paused, 1);
        expect(find.text('Download MP3'), findsOneWidget);
        final delete = find.byKey(Key('nova-recording-delete-${'a' * 32}'));
        await tester.ensureVisible(delete);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        expect(find.text('Delete this recording?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(f.calls.any((b) => b['action'] == 'delete'), false);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

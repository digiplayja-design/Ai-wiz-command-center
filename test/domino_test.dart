import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/domino/domino_controller.dart';
import 'package:ai_wiz_command_center/social/domino/domino_media.dart';
import 'package:ai_wiz_command_center/social/domino/domino_screen.dart';
import 'social_call_audio_test.dart' as media;
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class Peer extends media.Peer {
  final candidates = <rtc.RTCIceCandidate>[];
  rtc.RTCSessionDescription? remote;
  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription('offer', 'offer');
  @override
  Future<rtc.RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription('answer', 'answer');
  @override
  Future<void> setLocalDescription(
    rtc.RTCSessionDescription description,
  ) async {}
  @override
  Future<void> setRemoteDescription(
    rtc.RTCSessionDescription description,
  ) async {
    remote = description;
  }

  @override
  Future<void> addCandidate(rtc.RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }
}

class MeshIo extends media.Io {
  final connections = <Peer>[];
  @override
  Future<rtc.RTCPeerConnection> peer(List<dynamic> servers) async {
    final p = Peer();
    connections.add(p);
    return p;
  }
}

SocialMap room({int capacity = 4, String phase = 'playing'}) => {
  'id': 'room',
  'me': 'a',
  'host': 'a',
  'name': 'Friday domino night',
  'capacity': capacity,
  'revision': 3,
  'phase': phase,
  'round': 1,
  'turn': 'a',
  'last': 'Jordan played 3-6.',
  'wins': {},
  'points': {},
  'board': [
    {'id': '3-6', 'a': 3, 'b': 6, 'by': 'b'},
  ],
  'hand': ['0-3', '1-4', '1-6', '2-4', '2-5', '3-3', '4-6'],
  'legal': [
    {'tile': '0-3', 'side': 'left'},
    {'tile': '1-6', 'side': 'right'},
    {'tile': '3-3', 'side': 'left'},
    {'tile': '4-6', 'side': 'right'},
  ],
  'players': List.generate(
    capacity,
    (i) => {
      'id': String.fromCharCode(97 + i),
      'name': ['Alex', 'Jordan', 'Sam', 'Morgan'][i],
      'color': ['cyan', 'violet', 'mint', 'gold'][i],
      'seat': i,
      'state': 'joined',
      'online': true,
      'ready': false,
      'count': 7,
      'camera': false,
      'microphone': false,
    },
  ),
  'signals': [],
};

class Store {
  Store({SocialMap? initial}) : table = initial ?? room();
  SocialMap table;
  final calls = <SocialMap>[];
  final session = ValueNotifier(0);
  String token = 'Bearer account-one';
  bool conflict = false;
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: session,
    client: MockClient((r) async {
      final b = socialMap(jsonDecode(r.body));
      calls.add(b);
      if (b['action'] == 'list') {
        return http.Response(jsonEncode({'items': []}), 200);
      }
      if (b['action'] == 'move') {
        if (conflict) {
          return http.Response(
            '{"error":"The table changed. Refresh before playing."}',
            409,
          );
        }
        final move = socialMap(b['move']);
        table = {...table, 'revision': (table['revision'] as int) + 1};
        if (move['action'] == 'play') {
          table['hand'] = (table['hand'] as List)
              .where((t) => t != move['tile'])
              .toList();
          table['turn'] = 'b';
          table['legal'] = [];
        }
        if (move['action'] == 'ready') {
          socialItems(table['players']).first['ready'] = move['ready'];
        }
      }
      if (b['action'] == 'media') {
        final players = socialItems(table['players']);
        players.first['mediaSession'] = b['enabled'] == true
            ? b['session']
            : null;
        players.first['camera'] = b['camera'];
        players.first['microphone'] = b['microphone'];
        table = {...table, 'players': players};
      }
      return http.Response(
        jsonEncode({
          'table': table,
          'videoConfig': {'enabled': true, 'iceServers': []},
        }),
        200,
      );
    }),
  );
  void dispose() {
    client.dispose();
    session.dispose();
  }
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
  test(
    'four-person mesh captures once, sends enabled tracks and isolates audio from video',
    () async {
      final io = MeshIo(),
          outputs = List.generate(4, (_) => media.Audio()),
          signals = <SocialMap>[];
      final m = DominoMedia(io: io, outputs: outputs);
      m.onSignal = (peer, session, kind, payload) async {
        signals.add({'peer': peer, 'kind': kind});
      };
      m.activate();
      await m.open();
      final players = socialItems(room()['players']);
      for (final p in players) {
        p['mediaSession'] = 'session-${p['id']}';
      }
      await m.sync('a', players, []);
      expect(io.captureModes, [true]);
      expect(io.connections.length, 3);
      expect(signals.where((s) => s['kind'] == 'offer').length, 3);
      for (var i = 0; i < 3; i++) {
        final peer = io.connections[i];
        expect(peer.sent, [io.mic, io.camera]);
        peer.onTrack!(
          rtc.RTCTrackEvent(
            streams: [],
            track: media.Track('voice$i', 'audio'),
          ),
        );
        peer.onTrack!(
          rtc.RTCTrackEvent(
            streams: [],
            track: media.Track('video$i', 'video'),
          ),
        );
      }
      await media.settleTrack();
      for (var seat = 1; seat < 4; seat++) {
        expect(
          outputs[seat].received!.getAudioTracks().single.id,
          'voice${seat - 1}',
        );
        expect(outputs[seat].received!.getVideoTracks(), isEmpty);
      }
      expect(
        io.renderers.every((r) => r.srcObject!.getAudioTracks().isEmpty),
        isTrue,
      );
      m.toggleMicrophone();
      expect(io.mic.enabled, isFalse);
      expect(io.camera.enabled, isTrue);
      m.toggleCamera();
      expect(io.camera.enabled, isFalse);
      final closing = m.close();
      expect(io.mic.enabled, isFalse);
      await closing;
      expect(io.mic.stopped && io.camera.stopped, isTrue);
      expect(io.connections.every((p) => p.closed), isTrue);
      expect(io.projections.every((p) => p.disposed), isTrue);
      expect(outputs.every((a) => a.closed), isTrue);
      m.dispose();
    },
  );
  test(
    'ICE queues before descriptions; stale epochs cannot negotiate a current peer',
    () async {
      final io = MeshIo(),
          m = DominoMedia(
            io: MeshIo(),
            outputs: List.generate(4, (_) => media.Audio()),
          );
      m.dispose(); // An unopened room owns no microphone.
      final mesh = DominoMedia(
        io: io,
        outputs: List.generate(4, (_) => media.Audio()),
      );
      await mesh.open();
      await mesh.sync('z', [
        {
          'id': 'b',
          'state': 'joined',
          'seat': 1,
          'online': true,
          'mediaSession': 'current',
        },
      ], []);
      SocialMap signal(String kind, String epoch, SocialMap payload) => {
        'sender': 'b',
        'session': epoch,
        'targetSession': mesh.session,
        'kind': kind,
        'payload': payload,
      };
      await mesh.receive(
        signal('candidate', 'current', {
          'candidate': 'ice',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        }),
      );
      expect(io.connections.single.candidates, isEmpty);
      await mesh.receive(signal('offer', 'old', {'sdp': 'stale'}));
      expect(io.connections.single.remote, isNull);
      await mesh.receive(signal('offer', 'current', {'sdp': 'good'}));
      expect(io.connections.single.remote!.sdp, 'good');
      expect(io.connections.single.candidates.length, 1);
      await mesh.close();
      mesh.dispose();
    },
  );
  test(
    'leaving during camera permission stops every track returned later',
    () async {
      final io = MeshIo()..permission = Completer<rtc.MediaStream>();
      final m = DominoMedia(
        io: io,
        outputs: List.generate(4, (_) => media.Audio()),
      );
      final opening = m.open();
      await media.settleTrack();
      final closing = m.close();
      io.permission!.complete(media.Stream('late', [io.mic, io.camera]));
      await opening;
      await closing;
      expect(io.mic.stopped && io.camera.stopped, isTrue);
      expect(m.ready, isFalse);
      expect(io.renderers.single.disposed, isTrue);
      m.dispose();
    },
  );
  test(
    'camera is opt-in; background stops it and account changes clear private hands',
    () async {
      final s = Store(), io = MeshIo();
      final c = DominoController(
        client: s.client,
        initial: s.table,
        polling: false,
        mediaFactory: () => DominoMedia(
          io: io,
          outputs: List.generate(4, (_) => media.Audio()),
        ),
      );
      await c.initialize();
      expect(io.captureModes, isEmpty);
      await c.startVideo();
      expect(c.videoJoined, isTrue);
      c.background();
      expect(io.mic.enabled, isFalse);
      await media.settleTrack();
      expect(io.mic.stopped, isTrue);
      s.token = 'Bearer other-account';
      s.session.value++;
      expect(c.table, isEmpty);
      c.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'selecting a legal tile sends the selected end; conflicts refresh without local cheating',
    (t) async {
      final s = Store();
      final c = DominoController(
        client: s.client,
        initial: s.table,
        polling: false,
      );
      await social.mount(
        t,
        DominoTableScreen(client: s.client, initial: s.table, controller: c),
      );
      expect(s.calls.any((r) => r['action'] == 'media'), isFalse);
      await t.tap(find.byKey(const Key('domino-tile-0-3')));
      await t.pump();
      await t.tap(find.byKey(const Key('domino-left')));
      await t.pumpAndSettle();
      final move = socialMap(
        s.calls.firstWhere((r) => r['action'] == 'move')['move'],
      );
      expect(move['tile'], '0-3');
      expect(move['side'], 'left');
      expect(move['revision'], 3);
      expect(find.byKey(const Key('domino-tile-0-3')), findsNothing);
      s.conflict = true;
      await c.move('pass');
      expect(c.error, contains('table changed'));
      expect(c.table['revision'], 4);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      s.dispose();
    },
  );
  for (final config in [
    (390.0, 844.0, 1.0, 4),
    (360.0, 640.0, 2.0, 4),
    (1200.0, 850.0, 1.0, 2),
    (844.0, 390.0, 1.0, 4),
  ]) {
    testWidgets('table layout ${config.$1} at text scale ${config.$3}', (
      t,
    ) async {
      final s = Store(initial: room(capacity: config.$4));
      final c = DominoController(
        client: s.client,
        initial: s.table,
        polling: false,
      );
      await social.mount(
        t,
        DominoTableScreen(client: s.client, initial: s.table, controller: c),
        width: config.$1,
        height: config.$2,
        scale: config.$3,
      );
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'domino-table-${config.$1.toInt()}');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      s.dispose();
    });
  }
  testWidgets('lobby has private creation and explains camera consent', (
    t,
  ) async {
    final s = Store();
    await social.mount(t, DominoLobby(client: s.client, profile: social.me));
    expect(find.text('Pull up a chair.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await fixtures.capture(t, 'domino-lobby');
    await t.pumpWidget(const SizedBox());
    await t.pump();
    s.dispose();
  });
}

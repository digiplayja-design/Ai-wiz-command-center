import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/music_studio/music_client.dart';
import 'package:ai_wiz_command_center/music_studio/music_models.dart';
import 'package:ai_wiz_command_center/music_studio/music_player.dart';
import 'package:ai_wiz_command_center/music_studio/music_studio_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> copy(Map<String, dynamic> v) =>
    musicMap(jsonDecode(jsonEncode(v)));
Map<String, dynamic> recipe() => {
  ...blankMusic(),
  'idea': 'A hopeful reggae song about a fresh start',
  'style': 'reggae, warm',
  'title': 'Fresh start',
};
Map<String, dynamic> job({String status = 'completed', String jobId = id}) => {
  'id': jobId,
  'jobId': jobId,
  'status': status,
  'settings': recipe(),
  'favorite': false,
  'createdAt': '2026-09-27T21:00:00Z',
  'error': null,
  'accepted': true,
  'quotaHeld': true,
  'tracks': status == 'completed'
      ? [
          {
            'id': 'track-a',
            'title': 'Fresh Start',
            'state': 'succeeded',
            'audioUrl': 'https://cdn1.suno.ai/a.mp3',
            'imageUrl': null,
            'duration': 180,
            'lyrics': '[Verse]\nA brand new day\n[Chorus]\nWe find our way',
          },
        ]
      : [],
};

class FakeMusic extends MusicClient {
  FakeMusic()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> saved = {'version': 0, 'data': blankMusic()};
  List<Map<String, dynamic>> starts = [], saves = [];
  List<String> queries = [];
  int statuses = 0, removed = 0, favorites = 0, downloads = 0;
  bool active = true, ready = true, failSave = false, failStart = false;
  Completer<MusicDownload>? downloadWait;
  Completer<Map<String, dynamic>>? startWait;
  Map<String, dynamic> get addon => {
    'active': active,
    'providerReady': ready,
    'plans': [],
    'usage': {
      'remainingThisCycle': 74,
      'usedThisCycle': 1,
      'reservedThisCycle': 0,
      'monthlyLimit': 75,
      'cycle': '2026-09',
    },
  };
  @override
  Future<Map<String, dynamic>> load() async => {
    'addon': addon,
    'jobs': rows.map(copy).toList(),
    'draft': copy(saved),
    'hasMore': false,
  };
  @override
  Future<Map<String, dynamic>> jobs({
    String query = '',
    bool favorites = false,
    String? before,
  }) async {
    queries.add(query);
    return {
      'jobs': rows
          .where(
            (j) =>
                (!favorites || j['favorite'] == true) &&
                (query.isEmpty ||
                    jsonEncode(j).toLowerCase().contains(query.toLowerCase())),
          )
          .map(copy)
          .toList(),
      'hasMore': false,
    };
  }

  @override
  Future<Map<String, dynamic>> draft() async => copy(saved);
  @override
  Future<Map<String, dynamic>> saveDraft(Map<String, dynamic> body) async {
    saves.add(copy(body));
    if (failSave) {
      failSave = false;
      throw const MusicException('Save connection interrupted');
    }
    saved = {
      'version': (saved['version'] as int) + 1,
      'data': copy(body['data']),
    };
    return copy(saved);
  }

  @override
  Future<Map<String, dynamic>> generate(Map<String, dynamic> body) async {
    starts.add(copy(body));
    if (failStart) {
      failStart = false;
      throw const MusicException('Connection interrupted. Check this request.');
    }
    if (startWait != null) return startWait!.future;
    final j = job(status: 'submitted', jobId: body['request_key']);
    j['settings'] = copy(body);
    rows.insert(0, j);
    return {'job': copy(j), 'addon': addon};
  }

  @override
  Future<Map<String, dynamic>> status(String value) async {
    statuses++;
    return copy(rows.firstWhere((j) => j['id'] == value));
  }

  @override
  Future<Map<String, dynamic>> favorite(String value, bool selected) async {
    favorites++;
    final j = rows.firstWhere((j) => j['id'] == value);
    j['favorite'] = selected;
    return copy(j);
  }

  @override
  Future<void> remove(String value) async {
    removed++;
    rows.removeWhere((j) => j['id'] == value);
  }

  @override
  Future<MusicDownload> download(String value, int index) async {
    downloads++;
    if (downloadWait != null) return downloadWait!.future;
    return MusicDownload(Uint8List.fromList([73, 68, 51]), 'audio/mpeg', 'mp3');
  }

  void logout() => onAccessDenied?.call();
}

class FakePlayer extends MusicPlayback {
  int toggles = 0, stops = 0, seeks = 0;
  @override
  Future<void> toggle(String id, String url) async {
    toggles++;
    activeId = id;
    playing = !playing;
    duration = const Duration(minutes: 3);
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    seeks++;
    position = value;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    activeId = null;
    playing = false;
    notifyListeners();
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeMusic c, {
  FakePlayer? player,
  double width = 1100,
  double scale = 1,
  String theme = 'pure_white',
  bool consent = true,
  Future<void> Function(Uint8List, String, String, Rect)? save,
  Future<bool> Function(BuildContext)? ensure,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: MusicStudioScreen(
          client: c,
          player: player ?? FakePlayer(),
          ensureConsent: ensure ?? (_) => Future.value(consent),
          saveFile: save ?? (a, b, c, d) async {},
          pollInterval: const Duration(hours: 1),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 150));
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder.first);
  await t.pump();
  await t.tap(finder.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> enter(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pump();
}

Future<void> library(WidgetTester t) async => tap(
  t,
  find.byWidgetPredicate(
    (w) =>
        w is ChoiceChip &&
        w.label is Text &&
        ((w.label as Text).data ?? '').startsWith('My tracks'),
  ),
);
Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
  expect(t.takeException(), isNull);
}

String token(String user, String session) =>
    'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://auth.test', 'sub': user, 'session_id': session}))).replaceAll('=', '')}.b';
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
  test('request IDs, safe URLs and pending states are explicit', () {
    expect(musicRequestKey(), matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(musicUrl('javascript:alert(1)'), isNull);
    expect(musicPending(job(status: 'submitted')), true);
    expect(musicPending(job()), false);
    expect(musicTime(const Duration(seconds: 75)), '1:15');
  });
  test(
    'client pins account/session and does not expose a late old response',
    () async {
      final revision = ValueNotifier(0);
      var auth = token('owner', 'session');
      final waiting = Completer<http.Response>();
      int denied = 0;
      final c = MusicClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: revision,
        client: MockClient((_) => waiting.future),
      );
      c.onAccessDenied = () => denied++;
      final result = expectLater(c.load(), throwsA(isA<MusicException>()));
      auth = token('other', 'another');
      revision.value++;
      waiting.complete(
        http.Response(
          jsonEncode({
            'addon': {},
            'jobs': [],
            'draft': {'version': 0, 'data': {}},
          }),
          200,
        ),
      );
      await result;
      expect(denied, 1);
      c.dispose();
      revision.dispose();
    },
  );
  test('client rejects mismatched generation acknowledgements', () async {
    final c = MusicClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {},
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'job': job(jobId: 'foreign')}), 200),
      ),
    );
    await expectLater(
      c.generate({'request_key': id}),
      throwsA(isA<MusicException>()),
    );
    c.dispose();
  });
  testWidgets(
    'create screen starts simply and inactive users can save drafts',
    (t) async {
      final c = FakeMusic()..active = false;
      await show(t, c);
      expect(find.text('Your next song starts here.'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('music-generate')))
            .onPressed,
        isNull,
      );
      await enter(t, 'music-idea', 'An original song');
      await tap(t, find.text('Save draft'));
      expect(c.saves.length, 1);
      expect(c.starts, isEmpty);
      await close(t);
    },
  );
  testWidgets('no idea means no generation and clear inline guidance', (
    t,
  ) async {
    final c = FakeMusic();
    await show(t, c);
    await tap(t, find.byKey(const ValueKey('music-generate')));
    expect(c.starts, isEmpty);
    expect(
      find.text('Tell us what your music should feel like.'),
      findsOneWidget,
    );
    await close(t);
  });
  testWidgets(
    'declining AI sharing submits nothing and leaves the idea intact',
    (t) async {
      final c = FakeMusic();
      await show(t, c, consent: false);
      await enter(t, 'music-idea', 'My private idea');
      await tap(t, find.byKey(const ValueKey('music-generate')));
      expect(c.saves, isEmpty);
      expect(c.starts, isEmpty);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('music-idea')))
            .controller!
            .text,
        'My private idea',
      );
      await close(t);
    },
  );
  testWidgets(
    'instrumental generation saves the draft first and keeps one request',
    (t) async {
      final c = FakeMusic();
      await show(t, c);
      await tap(t, find.widgetWithText(ChoiceChip, 'Instrumental'));
      await enter(t, 'music-idea', 'Quiet piano and strings');
      await tap(t, find.byKey(const ValueKey('music-generate')));
      expect(c.saves.length, 1);
      expect(c.starts.single['mode'], 'instrumental');
      expect(c.starts.single['consent'], true);
      expect(find.text('Queued'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'my lyrics are carried into a generation without a hidden prompt requirement',
    (t) async {
      final c = FakeMusic();
      await show(t, c);
      await tap(t, find.widgetWithText(ChoiceChip, 'My lyrics'));
      await enter(t, 'music-lyrics', '[Verse]\nOur original words');
      await tap(t, find.byKey(const ValueKey('music-generate')));
      expect(c.starts.single['mode'], 'lyrics');
      expect(c.starts.single['lyrics'], '[Verse]\nOur original words');
      await close(t);
    },
  );
  testWidgets('save retry keeps its key and editing starts a new draft save', (
    t,
  ) async {
    final c = FakeMusic()..failSave = true;
    await show(t, c);
    await enter(t, 'music-idea', 'Keep this idea');
    await tap(t, find.text('Save draft'));
    await tap(t, find.text('Save draft'));
    expect(c.saves[0]['request_key'], c.saves[1]['request_key']);
    await enter(t, 'music-idea', 'A changed idea');
    await tap(t, find.text('Save draft'));
    expect(c.saves[2]['request_key'], isNot(c.saves[1]['request_key']));
    await close(t);
  });
  testWidgets(
    'network recovery reuses the generation body and prevents editing an unconfirmed request',
    (t) async {
      final c = FakeMusic()..failStart = true;
      await show(t, c);
      await enter(t, 'music-idea', 'A warm song');
      await tap(t, find.byKey(const ValueKey('music-generate')));
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('music-idea'))).enabled,
        false,
      );
      await tap(t, find.byKey(const ValueKey('music-generate')));
      expect(c.starts.length, 2);
      expect(c.starts[0], c.starts[1]);
      expect(c.saves.length, 1);
      await close(t);
    },
  );
  testWidgets(
    'saved library survives reopening and resumes pending status checks',
    (t) async {
      final c = FakeMusic()..rows = [job(status: 'submitted')];
      await show(t, c);
      expect(c.statuses, 1);
      await library(t);
      expect(find.text('Queued'), findsOneWidget);
      await close(t);
      final reopened = FakeMusic()..rows = c.rows;
      await show(t, reopened);
      expect(reopened.statuses, 1);
      await library(t);
      expect(find.text('Fresh start'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('favorites and search use server library filters', (t) async {
    final c = FakeMusic()..rows = [job()];
    await show(t, c);
    await library(t);
    await tap(t, find.byTooltip('Favorite creation'));
    expect(c.favorites, 1);
    await tap(t, find.text('Favorites'));
    await enter(t, 'music-search', 'missing');
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    expect(c.queries.last, 'missing');
    expect(find.text('No matching creations'), findsOneWidget);
    await close(t);
  });
  testWidgets('player supports pause resume and seeking', (t) async {
    final c = FakeMusic()..rows = [job()], p = FakePlayer();
    await show(t, c, player: p);
    await library(t);
    await tap(t, find.byTooltip('Play track'));
    expect(p.playing, true);
    await tap(t, find.byTooltip('Pause track'));
    expect(p.playing, false);
    final slider = t.widget<Slider>(find.byType(Slider));
    slider.onChanged!(45000);
    await t.pump();
    expect(p.seeks, 1);
    expect(p.position, const Duration(seconds: 45));
    await tap(t, find.byTooltip('Play track'));
    expect(p.playing, true);
    await close(t);
    expect(p.stops, greaterThan(0));
  });
  testWidgets(
    'download uses the selected owned track and explicit save action',
    (t) async {
      final c = FakeMusic()..rows = [job()];
      String? filename, mime;
      await show(
        t,
        c,
        save: (bytes, n, m, rect) async {
          filename = n;
          mime = m;
          expect(bytes.length, 3);
        },
      );
      await library(t);
      await tap(t, find.text('Download audio'));
      expect(c.downloads, 1);
      expect(filename, contains('$id-1.mp3'));
      expect(mime, 'audio/mpeg');
      await close(t);
    },
  );
  testWidgets('logout closes private lyric dialog and stops playback', (
    t,
  ) async {
    final c = FakeMusic()..rows = [job()], p = FakePlayer();
    await show(t, c, player: p);
    await library(t);
    await tap(t, find.byTooltip('Play track'));
    await tap(t, find.text('Lyrics'));
    expect(find.byType(AlertDialog), findsOneWidget);
    c.logout();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
    expect(find.text('Fresh start'), findsNothing);
    expect(p.stops, greaterThan(0));
    await close(t);
  });
  testWidgets('late download after account change never invokes save', (
    t,
  ) async {
    final c = FakeMusic()
      ..rows = [job()]
      ..downloadWait = Completer<MusicDownload>();
    int saves = 0;
    await show(
      t,
      c,
      save: (a, b, c, d) async {
        saves++;
      },
    );
    await library(t);
    await tap(t, find.text('Download audio'));
    c.logout();
    c.downloadWait!.complete(
      MusicDownload(Uint8List.fromList([1, 2]), 'audio/mpeg', 'mp3'),
    );
    await t.pump();
    expect(saves, 0);
    await close(t);
  });
  testWidgets(
    'removal is confirmed and pending creations have no remove button',
    (t) async {
      final c = FakeMusic()..rows = [job()];
      await show(t, c);
      await library(t);
      await tap(t, find.text('Remove'));
      expect(c.removed, 0);
      await tap(t, find.text('Cancel'));
      expect(c.removed, 0);
      await tap(t, find.text('Remove'));
      await tap(t, find.text('Continue'));
      expect(c.removed, 1);
      await close(t);
      final pending = FakeMusic()..rows = [job(status: 'submitted')];
      await show(t, pending);
      await library(t);
      expect(find.text('Remove'), findsNothing);
      await close(t);
    },
  );
  testWidgets(
    'reuse copies the recipe into an editable draft without charging',
    (t) async {
      final c = FakeMusic()..rows = [job()];
      await show(t, c);
      await library(t);
      await tap(t, find.text('Use this idea'));
      expect(c.starts, isEmpty);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('music-idea')))
            .controller!
            .text,
        recipe()['idea'],
      );
      await close(t);
    },
  );
  testWidgets('refresh keeps unsaved draft revision and text', (t) async {
    final c = FakeMusic()..saved = {'version': 2, 'data': recipe()};
    await show(t, c);
    await enter(t, 'music-idea', 'Unsaved idea');
    c.saved = {'version': 3, 'data': blankMusic()};
    await tap(t, find.byTooltip('Refresh Music Studio'));
    await tap(t, find.text('Save draft'));
    expect(c.saves.last['version'], 2);
    expect(c.saves.last['data']['idea'], 'Unsaved idea');
    await close(t);
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('creator library and player fit $width at 125 percent text', (
      t,
    ) async {
      final c = FakeMusic()..rows = [job()];
      await show(
        t,
        c,
        width: width,
        scale: 1.25,
        theme: width == 390 ? 'pure_black' : 'pure_white',
      );
      expect(t.takeException(), isNull);
      await tap(t, find.text('Make it yours'));
      expect(t.takeException(), isNull);
      await library(t);
      expect(t.takeException(), isNull);
      await tap(t, find.byTooltip('Play track'));
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
  testWidgets('optional actual Music Studio screenshots', (t) async {
    final dir = Platform.environment['MUSIC_CAPTURE_DIR'];
    if (dir == null) return;
    for (final width in [390.0, 1440.0]) {
      final c = FakeMusic()..rows = [job()];
      await show(
        t,
        c,
        width: width,
        theme: width == 390 ? 'pure_white' : 'korlix_blue',
      );
      await t.runAsync(() async {
        final img =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final b = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/music-create-${width.toInt()}.png',
        ).writeAsBytes(b!.buffer.asUint8List());
      });
      await library(t);
      await t.runAsync(() async {
        final img =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final b = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/music-library-${width.toInt()}.png',
        ).writeAsBytes(b!.buffer.asUint8List());
      });
      await close(t);
    }
  });
}

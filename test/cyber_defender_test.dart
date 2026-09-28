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
import 'package:ai_wiz_command_center/cyber_defender/defender_client.dart';
import 'package:ai_wiz_command_center/cyber_defender/defender_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const id = '11111111-1111-4111-8111-111111111111';
late Map<String, dynamic> fixture;
Map<String, dynamic> cp(Map<String, dynamic> x) =>
    defenderMap(jsonDecode(jsonEncode(x)));
Map<String, dynamic> report({String key = id, String state = 'ready'}) => {
  'id': key,
  'state': state,
  'mode': 'quick',
  'details': {'kind': 'message', 'mode': 'quick', 'channel': 'email'},
  'result': cp(fixture['result']),
  'review': {},
  'progress': {},
  'revision': 0,
  'created_at': '2026-09-28T00:00:00Z',
  'error': state == 'failed'
      ? 'The deeper review failed. Your credit was returned.'
      : null,
};

http.Response fixtureResponse(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

class FakeDefender extends DefenderClient {
  FakeDefender()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> rows = [], creates = [], events = [];
  Map<String, dynamic> profile = {
    'mode': 'personal',
    'habits': {},
    'revision': 0,
  };
  Map<String, dynamic>? current;
  bool failCreate = false,
      failEvent = false,
      preparing = false,
      failList = false;
  int exports = 0, deletes = 0, opens = 0;
  Completer<Map<String, dynamic>>? createWait;
  Completer<List<int>>? exportWait;
  @override
  Future<Map<String, dynamic>> list() async {
    if (failList) throw const DefenderException('Workspace unavailable');
    return {
      ...cp(fixture),
      'reports': rows.map(cp).toList(),
      'profile': cp(profile),
    };
  }

  void sync() {
    if (current != null) {
      rows = [
        {
          ...cp(current!),
          'title': defenderMap(current!['result'])['title'],
          'concern': defenderMap(current!['result'])['concern'],
          'actionCount': 3,
        },
      ];
    }
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> b) async {
    creates.add(cp(b));
    if (failCreate) {
      failCreate = false;
      throw const DefenderException('Connection interrupted');
    }
    if (createWait != null) return createWait!.future;
    current = report(
      key: b['request_key'],
      state: preparing ? 'preparing' : 'ready',
    );
    sync();
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> open(String key) async {
    opens++;
    current ??= report(key: key);
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> progress(
    String key,
    Map<String, dynamic> b,
  ) async {
    events.add(cp(b));
    if (failEvent) {
      failEvent = false;
      throw const DefenderException('Save interrupted');
    }
    current!['progress'][b['key']] = b['checked'];
    current!['revision']++;
    sync();
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> checklist(Map<String, dynamic> b) async {
    events.add(cp(b));
    if (failEvent) {
      failEvent = false;
      throw const DefenderException('Save interrupted');
    }
    if (b['key'] == 'mode') {
      profile['mode'] = b['mode'];
    } else {
      profile['habits'][b['key']] = b['checked'];
    }
    profile['revision']++;
    return cp(profile);
  }

  @override
  Future<void> remove(String key) async {
    deletes++;
    rows = [];
    current = null;
  }

  @override
  Future<List<int>> export(String key) async {
    exports++;
    return exportWait?.future ?? utf8.encode('Defender report');
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeDefender c, {
  double width = 1100,
  double scale = 1,
  String theme = 'pure_white',
  bool consent = true,
  DefenderFileSaver? save,
}) async {
  t.view.physicalSize = Size(width, 1050);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: DefenderScreen(
          client: c,
          ensureConsent: (_) async => consent,
          saveFile: save ?? (a, b, c, d) async {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, String label) =>
    tap(t, find.widgetWithText(ChoiceChip, label));
Future<void> check(WidgetTester t) async {
  await t.enterText(
    find.byKey(const Key('defender-message')),
    'Please send your verification code.',
  );
  await tap(t, find.text('Run free quick check'));
}

String token(String sub, {String session = 'session-a', int expiry = 1}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': sub, 'session_id': session, 'exp': expiry}))).replaceAll('=', '')}.signature';
void main() {
  setUpAll(() async {
    fixture = defenderMap(
      jsonDecode(File('test/fixtures/defender.json').readAsStringSync()),
    );
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
    if (mono.existsSync()) {
      await (FontLoader(
        'monospace',
      )..addFont(mono.readAsBytes().then(ByteData.sublistView))).load();
    }
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
  test('request IDs are valid unique UUIDs', () {
    final values = List.generate(200, (_) => defenderRequestKey());
    expect(values.toSet().length, 200);
    expect(
      values.every(
        (s) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(s),
      ),
      isTrue,
    );
  });
  test(
    'client creates with verified auth header and binds response ID',
    () async {
      late http.Request sent;
      final c = DefenderClient(
        backendBaseUrl: 'https://fixture.test/',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((r) async {
          sent = r;
          return fixtureResponse(jsonEncode({'report': report()}), 202);
        }),
      );
      final r = await c.create({'request_key': id, 'mode': 'quick'});
      expect(r['id'], id);
      expect(sent.url.path, '/api/cyber-defender/reports');
      expect(sent.headers['Authorization'], 'Bearer fixture');
      expect(jsonDecode(sent.body)['request_key'], id);
      c.dispose();
    },
  );
  test('client rejects mismatched reports and malformed responses', () async {
    for (final value in [
      {'report': report(key: 'wrong')},
      {
        'report': {'id': id},
      },
      'not json',
    ]) {
      final c = DefenderClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (_) async =>
              fixtureResponse(value is String ? value : jsonEncode(value), 200),
        ),
      );
      await expectLater(c.open(id), throwsA(isA<DefenderException>()));
      c.dispose();
    }
  });
  test(
    'sign-in change discards an in-flight report; token refresh preserves scope',
    () async {
      String auth = token('owner');
      final revision = ValueNotifier(0), wait = Completer<http.Response>();
      int denied = 0;
      final c = DefenderClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: revision,
        client: MockClient((_) => wait.future),
      );
      c.onAccessDenied = () => denied++;
      auth = token('owner', expiry: 2);
      revision.value++;
      expect(denied, 0);
      final pending = c.open(id);
      final expectation = expectLater(
        pending,
        throwsA(isA<DefenderException>()),
      );
      auth = token('other');
      revision.value++;
      wait.complete(fixtureResponse(jsonEncode({'report': report()}), 200));
      await expectation;
      expect(denied, 1);
      c.dispose();
      revision.dispose();
    },
  );
  test(
    '401 locks client and mutation failures are never automatically retried',
    () async {
      int calls = 0, denied = 0;
      final c = DefenderClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((_) async {
          calls++;
          return fixtureResponse('{"error":"Sign in"}', 401);
        }),
      );
      c.onAccessDenied = () => denied++;
      await expectLater(
        c.create({'request_key': id}),
        throwsA(isA<DefenderException>()),
      );
      await expectLater(c.open(id), throwsA(isA<DefenderException>()));
      expect(calls, 1);
      expect(denied, 1);
      c.dispose();
    },
  );
  test('export rejects HTML or empty bodies', () async {
    for (final r in [
      fixtureResponse(
        '<html>error</html>',
        200,
        headers: {'content-type': 'text/html'},
      ),
      fixtureResponse('', 200, headers: {'content-type': 'text/plain'}),
    ]) {
      final c = DefenderClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient((_) async => r),
      );
      await expectLater(c.export(id), throwsA(isA<DefenderException>()));
      c.dispose();
    }
  });
  testWidgets(
    'blank check disabled, sample fills form, and quick check opens result',
    (t) async {
      final c = FakeDefender();
      await show(t, c);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Run free quick check'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.text('Try a sample'));
      await tap(t, find.text('Run free quick check'));
      expect(c.creates.single['mode'], 'quick');
      expect(c.creates.single['channel'], 'invoice');
      expect(find.text('High concern'), findsOneWidget);
      expect(find.text('Your next steps'), findsOneWidget);
      expect(find.text('evil[.]test'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    },
  );
  testWidgets('AI consent refusal does not submit or charge', (t) async {
    final c = FakeDefender();
    await show(t, c, consent: false);
    await t.enterText(
      find.byKey(const Key('defender-message')),
      'Check this request',
    );
    await tap(t, find.byType(SwitchListTile));
    await tap(t, find.text('Check + KORLIX review · 1 credit'));
    expect(c.creates, isEmpty);
  });
  testWidgets('uncertain create retries exact input and request key', (
    t,
  ) async {
    final c = FakeDefender()..failCreate = true;
    await show(t, c);
    await check(t);
    expect(find.text('Retry same request'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byKey(const Key('defender-message'))).enabled,
      isFalse,
    );
    await tap(t, find.text('Retry same request'));
    expect(c.creates.length, 2);
    expect(c.creates[0], c.creates[1]);
    expect(find.text('High concern'), findsOneWidget);
  });
  testWidgets(
    'personal and business habits persist and uncertainty blocks other changes',
    (t) async {
      final c = FakeDefender();
      await show(t, c);
      await tab(t, 'Safety checklist');
      expect(find.byType(CheckboxListTile), findsNWidgets(8));
      await tap(t, find.widgetWithText(ChoiceChip, 'Business'));
      expect(find.byType(CheckboxListTile), findsNWidgets(12));
      c.failEvent = true;
      await tap(t, find.byKey(const Key('habit-mfa')));
      expect(find.text('Retry progress change'), findsOneWidget);
      expect(
        t
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Saved reports'),
            )
            .onSelected,
        isNull,
      );
      await tap(t, find.text('Retry progress change'));
      expect(c.events[1], c.events[2]);
      expect(c.profile['habits']['mfa'], true);
    },
  );
  testWidgets(
    'incident guides create free private reports without AI consent',
    (t) async {
      final c = FakeDefender();
      await show(t, c, consent: false);
      await tab(t, 'Incident help');
      expect(find.text('Open recovery guide'), findsNWidgets(4));
      await tap(t, find.text('Open recovery guide').first);
      expect(c.creates.single['kind'], 'incident');
      expect(c.creates.single['mode'], 'quick');
      expect(c.creates.single['consent'], isNull);
    },
  );
  testWidgets(
    'saved report search, progress, export, delete confirmation and cancel work',
    (t) async {
      final c = FakeDefender()..current = report();
      c.sync();
      int saved = 0;
      await show(
        t,
        c,
        save: (bytes, name, mime, rect) async {
          saved++;
          expect(name, contains(id));
          expect(mime, 'text/plain');
        },
      );
      await tab(t, 'Saved reports');
      await tap(t, find.text('Open report'));
      await tap(
        t,
        find.widgetWithText(CheckboxListTile, 'Pause before responding'),
      );
      expect(c.current!['progress']['pause'], true);
      await tap(t, find.text('Export report'));
      expect(saved, 1);
      await tap(t, find.text('Delete report'));
      await tap(t, find.text('Cancel'));
      expect(c.deletes, 0);
      await tap(t, find.text('Delete report'));
      await tap(t, find.widgetWithText(FilledButton, 'Delete report'));
      expect(c.deletes, 1);
      expect(find.text('Your first check starts here.'), findsOneWidget);
    },
  );
  testWidgets('session change immediately clears content and reports', (
    t,
  ) async {
    final c = FakeDefender();
    await show(t, c);
    await t.enterText(
      find.byKey(const Key('defender-message')),
      'sensitive fixture message',
    );
    c.onAccessDenied?.call();
    await t.pumpAndSettle();
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    expect(find.text('sensitive fixture message'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Check a message'), findsNothing);
  });
  testWidgets('an export that finishes after sign-out is never saved', (
    t,
  ) async {
    final c = FakeDefender()
      ..current = report()
      ..exportWait = Completer<List<int>>();
    c.sync();
    int saved = 0;
    await show(
      t,
      c,
      save: (a, b, c, d) async {
        saved++;
      },
    );
    await tab(t, 'Saved reports');
    await tap(t, find.text('Open report'));
    await t.ensureVisible(find.text('Export report'));
    await t.pumpAndSettle();
    await t.tap(find.text('Export report'));
    await t.pump();
    c.onAccessDenied?.call();
    c.exportWait!.complete([1, 2]);
    await t.pumpAndSettle();
    expect(saved, 0);
  });
  testWidgets(
    'AI waiting report keeps quick results and polls until complete',
    (t) async {
      final c = FakeDefender();
      await show(t, c);
      await t.enterText(
        find.byKey(const Key('defender-message')),
        'suspicious request',
      );
      await tap(t, find.byType(SwitchListTile));
      c.preparing = true;
      await t.ensureVisible(find.text('Check + KORLIX review · 1 credit'));
      await t.pumpAndSettle();
      await t.tap(find.text('Check + KORLIX review · 1 credit'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Quick findings are ready.'), findsOneWidget);
      expect(find.text('Your next steps'), findsOneWidget);
      c.current!['state'] = 'ready';
      c.current!['review'] = {
        'concern': 'unknown',
        'summary': 'No additional signs identified.',
        'observations': ['Limited context.'],
        'uncertainty': 'Sender unverified.',
      };
      c.sync();
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('KORLIX deeper review'), findsOneWidget);
      expect(find.text('High concern'), findsOneWidget);
    },
  );
  for (final size in [320.0, 390.0, 1280.0]) {
    for (final theme in ['pure_white', 'midnight']) {
      testWidgets('all views fit at $size in $theme with large text', (
        t,
      ) async {
        final c = FakeDefender()..current = report();
        c.sync();
        await show(t, c, width: size, scale: 1.25, theme: theme);
        expect(t.takeException(), isNull);
        for (final label in [
          'Safety checklist',
          'Incident help',
          'Saved reports',
        ]) {
          await tab(t, label);
          expect(t.takeException(), isNull);
        }
        await tap(t, find.text('Open report'));
        await t.ensureVisible(find.text('Export report'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('capture actual Defender interface for visual review', (t) async {
    final dir = Platform.environment['DEFENDER_CAPTURE_DIR'];
    if (dir == null) return;
    Directory(dir).createSync(recursive: true);
    for (final width in [390.0, 1280.0]) {
      final c = FakeDefender()..current = report();
      c.sync();
      await show(
        t,
        c,
        width: width,
        theme: width == 390 ? 'pure_white' : 'midnight',
      );
      Future<void> capture(String name) async {
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final img =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$dir/defender-$name-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await capture('start');
      await tab(t, 'Incident help');
      await capture('incident');
      await tab(t, 'Saved reports');
      await tap(t, find.text('Open report'));
      await capture('report');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }
  });
}

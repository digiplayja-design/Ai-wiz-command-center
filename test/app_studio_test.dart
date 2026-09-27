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
import 'package:ai_wiz_command_center/app_studio/app_studio_client.dart';
import 'package:ai_wiz_command_center/app_studio/app_studio_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> cp(Map<String, dynamic> m) =>
    appMap(jsonDecode(jsonEncode(m)));
Map<String, dynamic> spec() => {
  'name': 'Client Circle',
  'tagline': 'Make every connection count.',
  'description': 'Keep contacts and opportunities together.',
  'accent': '#176BCA',
  'theme': 'light',
  'collections': [
    {
      'id': 'contacts',
      'label': 'Contacts',
      'singular': 'Contact',
      'layout': 'list',
      'fields': [
        {
          'id': 'name',
          'label': 'Name',
          'type': 'text',
          'required': true,
          'options': [],
        },
      ],
      'records': [],
    },
  ],
  'nextSteps': ['Connect a shared database before inviting your team.'],
  'changes': ['Created the first version.'],
};
Map<String, dynamic> project({int version = 1, String projectId = id}) => {
  'id': projectId,
  'name': 'Client Circle',
  'version': version,
  'brief': {'idea': 'A CRM for my local service business'},
  'spec': version == 0 ? {} : spec(),
};

class FakeApps extends AppStudioClient {
  FakeApps()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? current, run;
  List<Map<String, dynamic>> creates = [],
      builds = [],
      styles = [],
      restores = [];
  bool failCreate = false,
      failBuild = false,
      failStyle = false,
      completedReplay = false;
  int exports = 0, deletes = 0;
  Completer<List<int>>? exportWait;
  Completer<Map<String, dynamic>>? createWait;
  @override
  Future<List<Map<String, dynamic>>> list() async => rows.map(cp).toList();
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> b) async {
    creates.add(cp(b));
    if (failCreate) {
      failCreate = false;
      throw const AppStudioException('Connection interrupted');
    }
    if (createWait != null) return createWait!.future;
    current = project(
      version: b['template'] == null ? 0 : 1,
      projectId: b['request_key'],
    );
    current!['brief'] = {'idea': b['idea']};
    rows = [cp(current!)];
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> open(String value) async {
    current ??= rows.firstWhere((p) => p['id'] == value);
    return {
      'project': cp(current!),
      'run': run == null ? null : cp(run!),
      'previewHtml': '<html>Fixture preview</html>',
      'versions': [
        {
          'id': '22222222-2222-4222-8222-222222222222',
          'version': current!['version'],
          'label': 'Latest design',
        },
        if (current!['version'] > 1)
          {'id': id, 'version': 1, 'label': 'Starter template'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> build(
    String value,
    Map<String, dynamic> b,
  ) async {
    builds.add(cp(b));
    if (failBuild) {
      failBuild = false;
      throw const AppStudioException('Build acknowledgement interrupted');
    }
    if (completedReplay) current = project(version: 2, projectId: value);
    run = {
      'id': b['request_key'],
      'projectId': value,
      'state': completedReplay ? 'completed' : 'running',
      'charged': 1,
    };
    return cp(run!);
  }

  @override
  Future<Map<String, dynamic>> style(
    String value,
    Map<String, dynamic> b,
  ) async {
    styles.add(cp(b));
    if (failStyle) {
      failStyle = false;
      throw const AppStudioException('Save interrupted');
    }
    current!['version']++;
    current!['spec'] = {
      ...appMap(current!['spec']),
      'name': b['name'],
      'accent': b['accent'],
      'theme': b['theme'],
    };
    current!['name'] = b['name'];
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> restore(
    String value,
    Map<String, dynamic> b,
  ) async {
    restores.add(cp(b));
    current!['version']++;
    return cp(current!);
  }

  @override
  Future<void> remove(String value) async {
    deletes++;
    rows.removeWhere((p) => p['id'] == value);
  }

  @override
  Future<List<int>> export(String value) async {
    exports++;
    return exportWait?.future ?? [80, 75, 3, 4, ...List.filled(24, 0)];
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeApps c, {
  double width = 1100,
  double scale = 1,
  String theme = 'pure_white',
  bool consent = true,
  AppFileSaver? save,
}) async {
  t.view.physicalSize = Size(width, 1050);
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
        child: AppStudioScreen(
          client: c,
          ensureConsent: (_) async => consent,
          saveFile: save ?? (a, b, c, d) async {},
          previewBuilder: (_) => Container(
            color: const Color(0xfff4f6fa),
            padding: const EdgeInsets.all(20),
            child: const Text(
              'Interactive app preview fixture',
              style: TextStyle(color: Color(0xff172638)),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

Future<void> open(WidgetTester t) async {
  await tap(t, find.textContaining('My projects').first);
  await tap(t, find.text('Open project').first);
}

String token(String user, String session) =>
    'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': user, 'session_id': session}))).replaceAll('=', '')}.b';
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
  test('request IDs are distinct and suitable for replay protection', () {
    expect(appRequestKey(), matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(appRequestKey(), isNot(appRequestKey()));
  });
  testWidgets('idea saves without consent or AI generation', (t) async {
    final c = FakeApps();
    await show(t, c, consent: false);
    await t.enterText(
      find.widgetWithText(TextField, 'Your app idea'),
      'A simple CRM for a local business',
    );
    await tap(t, find.text('Save idea'));
    expect(c.creates.single['idea'], 'A simple CRM for a local business');
    expect(c.builds, isEmpty);
    expect(find.text('Build first version · 1 credit'), findsOneWidget);
    await close(t);
  });
  testWidgets('consent refusal sends no project or AI request', (t) async {
    final c = FakeApps();
    await show(t, c, consent: false);
    await t.enterText(
      find.widgetWithText(TextField, 'Your app idea'),
      'A simple CRM for a local business',
    );
    await tap(t, find.text('Build my app · 1 credit'));
    expect(c.creates, isEmpty);
    expect(c.builds, isEmpty);
    await close(t);
  });
  testWidgets(
    'starter immediately opens an interactive workspace without using AI',
    (t) async {
      final c = FakeApps();
      await show(t, c);
      await tap(t, find.text('Use starter').first);
      expect(c.creates.single['template'], 'crm');
      expect(c.builds, isEmpty);
      expect(find.text('Export app'), findsOneWidget);
      expect(find.text('Client Circle'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'lost create response retries the same body and original non-AI action',
    (t) async {
      final c = FakeApps()..failCreate = true;
      await show(t, c);
      await tap(t, find.text('Use starter').first);
      expect(find.textContaining('Connection interrupted'), findsOneWidget);
      await tap(t, find.text('Retry saved request'));
      expect(c.creates.length, 2);
      expect(c.creates[0], c.creates[1]);
      expect(c.builds, isEmpty);
      await close(t);
    },
  );
  testWidgets(
    'build saves project, sends consent and shows recoverable progress',
    (t) async {
      final c = FakeApps();
      await show(t, c);
      await t.enterText(
        find.widgetWithText(TextField, 'Your app idea'),
        'A simple CRM for a local business',
      );
      await tap(t, find.text('Build my app · 1 credit'));
      expect(c.builds.single['consent'], true);
      expect(c.builds.single['version'], 0);
      expect(
        find.textContaining('KORLIX is designing your next version'),
        findsOneWidget,
      );
      await close(t);
    },
  );
  testWidgets('retrying an unconfirmed build preserves the exact request key', (
    t,
  ) async {
    final c = FakeApps()
      ..rows = [project()]
      ..failBuild = true;
    await show(t, c);
    await open(t);
    await t.enterText(
      find.widgetWithText(TextField, 'Ask for a change'),
      'Add a priority field',
    );
    await tap(t, find.text('Build new version · 1 credit'));
    await tap(t, find.text('Retry build request'));
    expect(c.builds.length, 2);
    expect(c.builds[0], c.builds[1]);
    await close(t);
  });
  testWidgets(
    'reopening an active project resumes polling and shows completed version',
    (t) async {
      final c = FakeApps()
        ..rows = [project()]
        ..run = {'id': 'build', 'state': 'running', 'projectId': id};
      await show(t, c);
      await open(t);
      expect(
        find.textContaining('KORLIX is designing your next version'),
        findsOneWidget,
      );
      c.run = {'id': 'build', 'state': 'completed', 'projectId': id};
      c.current = project(version: 2);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.textContaining('Your new version is ready'), findsOneWidget);
      expect(find.text('Version 2 · Local web prototype'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('style changes save a version without AI and preserve retries', (
    t,
  ) async {
    final c = FakeApps()
      ..rows = [project()]
      ..failStyle = true;
    await show(t, c);
    await open(t);
    await tap(t, find.text('Make it yours'));
    await t.enterText(
      find.widgetWithText(TextField, 'App name'),
      'My Client Desk',
    );
    await tap(t, find.text('Dark'));
    await tap(t, find.text('Save style'));
    await tap(t, find.text('Retry style save'));
    expect(c.styles[0], c.styles[1]);
    expect(c.styles.last['name'], 'My Client Desk');
    expect(c.styles.last['theme'], 'dark');
    expect(c.builds, isEmpty);
    await close(t);
  });
  testWidgets(
    'version restore requires confirmation and retains project history',
    (t) async {
      final c = FakeApps()..rows = [project(version: 2)];
      await show(t, c);
      await open(t);
      await tap(t, find.text('Versions'));
      await tap(t, find.text('Restore version 1'));
      expect(c.restores, isEmpty);
      await tap(t, find.text('Restore'));
      expect(c.restores.single['version_id'], id);
      expect(c.current!['version'], 3);
      await close(t);
    },
  );
  testWidgets('project search and confirmed deletion work', (t) async {
    final c = FakeApps()..rows = [project()];
    await show(t, c);
    await tap(t, find.textContaining('My projects').first);
    await t.enterText(find.byType(TextField), 'unmatched');
    await t.pump();
    expect(find.text('Open project'), findsNothing);
    await t.enterText(find.byType(TextField), 'Client');
    await t.pump();
    await tap(t, find.text('Delete'));
    expect(c.deletes, 0);
    await tap(t, find.text('Delete project'));
    expect(c.deletes, 1);
    expect(find.text('Open project'), findsNothing);
    await close(t);
  });
  testWidgets('export is explicit and carries a ZIP filename', (t) async {
    final c = FakeApps()..rows = [project()];
    String? filename;
    await show(
      t,
      c,
      save: (b, n, m, r) async {
        filename = n;
        expect(m, 'application/zip');
      },
    );
    await open(t);
    expect(c.exports, 0);
    await tap(t, find.text('Export app'));
    expect(filename, contains('-v1.zip'));
    expect(find.textContaining('Download started'), findsOneWidget);
    await close(t);
  });
  testWidgets(
    'sign-in change clears private project and blocks late download',
    (t) async {
      final c = FakeApps()
        ..rows = [project()]
        ..exportWait = Completer();
      int saved = 0;
      await show(t, c, save: (b, n, m, r) async => saved++);
      await open(t);
      await t.tap(find.text('Export app'));
      await t.pump();
      c.onAccessDenied!();
      await t.pump();
      c.exportWait!.complete([80, 75, 3, 4, ...List.filled(24, 0)]);
      await t.pumpAndSettle();
      expect(saved, 0);
      expect(find.text('Client Circle'), findsNothing);
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('sign-in change closes a private confirmation dialog', (t) async {
    final c = FakeApps()..rows = [project()];
    await show(t, c);
    await tap(t, find.textContaining('My projects').first);
    await tap(t, find.text('Delete'));
    c.onAccessDenied!();
    await t.pumpAndSettle();
    expect(find.text('Delete Client Circle?'), findsNothing);
    expect(c.deletes, 0);
    await close(t);
  });
  test('client rejects late responses after account changes', () async {
    final notifier = ValueNotifier(0);
    String auth = token('owner', 'session');
    final wait = Completer<http.Response>();
    final c = AppStudioClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': 'Bearer $auth'},
      sessionChanges: notifier,
      client: MockClient((r) => wait.future),
    );
    final pending = c.list();
    auth = token('other', 'new-session');
    notifier.value++;
    wait.complete(http.Response('{"projects":[]}', 200));
    await expectLater(pending, throwsA(isA<AppStudioException>()));
    c.dispose();
    notifier.dispose();
  });
  test(
    'client refuses mismatched build acknowledgements and invalid export files',
    () async {
      final c = AppStudioClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (r) async => r.url.path.endsWith('/export')
              ? http.Response(
                  'not a zip',
                  200,
                  headers: {'content-type': 'application/zip'},
                )
              : http.Response('{"run":{"id":"wrong","projectId":"$id"}}', 202),
        ),
      );
      await expectLater(
        c.build(id, {'request_key': 'expected'}),
        throwsA(isA<AppStudioException>()),
      );
      await expectLater(c.export(id), throwsA(isA<AppStudioException>()));
      c.dispose();
    },
  );
  test('main button and Tools route point to the dedicated workspace', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect(s, contains('AppStudioScreen('));
    expect(s, contains("if (tool == 'App Studio')"));
    expect(s, contains("featureName:'App Studio'"));
    expect(s, isNot(contains('Generate App Spec')));
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('creator and project fit $width px at 125% text', (t) async {
      final c = FakeApps()..rows = [project(version: 2)];
      await show(
        t,
        c,
        width: width,
        scale: 1.25,
        theme: width == 1440 ? 'korlix_blue' : 'pure_white',
      );
      expect(t.takeException(), isNull);
      await open(t);
      expect(t.takeException(), isNull);
      await tap(t, find.text('App plan'));
      expect(t.takeException(), isNull);
      await tap(t, find.text('Versions'));
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
  testWidgets(
    'completed build replay refreshes the finished project immediately',
    (t) async {
      final c = FakeApps()
        ..rows = [project()]
        ..completedReplay = true;
      await show(t, c);
      await open(t);
      await t.enterText(
        find.widgetWithText(TextField, 'Ask for a change'),
        'Add a status board',
      );
      await tap(t, find.text('Build new version · 1 credit'));
      expect(find.text('Version 2 · Local web prototype'), findsOneWidget);
      expect(find.textContaining('Your new version is ready'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('failed builds restore the original instructions for editing', (
    t,
  ) async {
    final c = FakeApps()
      ..rows = [project()]
      ..run = {
        'id': 'failed-build',
        'state': 'failed',
        'projectId': id,
        'message': 'Add a priority field',
        'error': 'Build interrupted. Credit returned.',
      };
    await show(t, c);
    await open(t);
    expect(find.text('Add a priority field'), findsOneWidget);
    expect(find.text('Build interrupted. Credit returned.'), findsOneWidget);
    await close(t);
  });
  testWidgets('optional App Studio screen captures', (t) async {
    final dir = Platform.environment['APP_CAPTURE_DIR'];
    if (dir == null) return;
    for (final w in [390.0, 1440.0]) {
      final c = FakeApps()..rows = [project()];
      await show(
        t,
        c,
        width: w,
        theme: w == 390 ? 'pure_white' : 'korlix_blue',
      );
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final b = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/app-create-${w.toInt()}.png',
        ).writeAsBytes(b!.buffer.asUint8List());
      });
      await open(t);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final b = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/app-project-${w.toInt()}.png',
        ).writeAsBytes(b!.buffer.asUint8List());
      });
      await close(t);
    }
  });
}

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
import 'package:ai_wiz_command_center/funnel_studio/funnel_library.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_create_dialog.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_launch_checklist.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> sourceFunnel() => {
  'id': 'original',
  'name': 'Our published offer',
  'slug': 'original-offer',
  'state': 'published',
  'version': 5,
  'page_requests': 25,
  'lead_count': 10,
  'url': 'https://example.com/f/original-offer',
  'draft': {
    ...funnelPresets.first.document(),
    'brand': 'KORLIX AI',
    'privacy_url': 'https://example.com/privacy',
    'contact_email': 'team@example.com',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final entry in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  Future<void> capture(WidgetTester t, String name) async {
    if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> openDialog(
    WidgetTester t,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) create, {
    Map<String, dynamic>? source,
    double scale = 1,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('capture'),
          child: LayoutBuilder(
            builder: (context, box) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(box.maxWidth, box.maxHeight),
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
          ),
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                barrierDismissible: false,
                builder: (_) =>
                    FunnelCreateDialog(create: create, source: source),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.runAsync(
      () => precacheImage(
        const AssetImage('assets/meeting_copilot/korlix_logo.jpeg'),
        t.element(find.byType(FunnelCreateDialog)),
      ),
    );
    await t.pump();
  }

  test(
    'Presets have independent content and duplication copies only page fields',
    () {
      final source = sourceFunnel();
      final draft = source['draft'] as Map<String, dynamic>;
      draft['workflow_id'] = 'do-not-copy';
      final payload = funnelCreatePayload(' Copy ', ' new-address ', draft);
      expect(payload.keys, unorderedEquals(['name', 'slug', 'document']));
      expect(payload['name'], 'Copy');
      expect(payload['slug'], 'new-address');
      expect((payload['document'] as Map).containsKey('workflow_id'), false);
      (payload['document']['benefits'] as List)[0] = 'Changed';
      expect(draft['benefits'][0], isNot('Changed'));
      final preset = funnelPresets.first.document();
      (preset['benefits'] as List)[0] = 'Changed';
      expect(funnelPresets.first.document()['benefits'][0], isNot('Changed'));
      expect(funnelSlugSuggestion('My New Offer!'), 'my-new-offer');
      expect(funnelSlugSuggestion('A' * 110).length, 60);
      // Export real starter documents for the backend contract check.
      if (Platform.environment['KORLIX_FUNNEL_CONTRACT'] == '1') {
        File('/tmp/k145-presets.json').writeAsStringSync(
          jsonEncode(funnelPresets.map((p) => p.document()).toList()),
        );
      }
    },
  );

  test('Setup checks reject missing and non-public addresses', () {
    for (final url in [
      '',
      'http://example.com',
      'https://user:secret@example.com',
      'https://localhost',
      'https://127.0.0.1',
      'https://169.254.1.2',
    ]) {
      expect(funnelHttpsAddress(url), false, reason: url);
    }
    expect(funnelHttpsAddress('https://example.com/privacy'), true);
    expect(funnelContactEmail('bad'), false);
    expect(funnelContactEmail('a@example.com, b@example.com'), false);
    expect(funnelContactEmail('team@example.com'), true);
  });

  for (final size in [
    const Size(1440, 1000),
    const Size(390, 844),
    const Size(320, 740),
  ]) {
    testWidgets(
      'Library filters, previews and creates the selected preset at ${size.width}',
      (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        Map<String, dynamic>? payload;
        await openDialog(t, (p) async {
          payload = p;
          return {'id': 'new'};
        }, scale: size.width == 320 ? 1.3 : 1);
        await capture(t, 'k145-library-${size.width.toInt()}');
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Events'));
        await t.tap(find.text('Events'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('preset-event')), findsOneWidget);
        expect(find.byKey(const ValueKey('preset-demo')), findsNothing);
        await t.enterText(
          find.byKey(const ValueKey('template-search')),
          'xyzdoesnotexist',
        );
        await t.pumpAndSettle();
        expect(
          find.text('No matching templates. Try another search or category.'),
          findsOneWidget,
        );
        await t.enterText(
          find.byKey(const ValueKey('template-search')),
          'workshop',
        );
        await t.pumpAndSettle();
        final preset = find.byKey(const ValueKey('preset-event'));
        await t.ensureVisible(preset);
        await t.tap(preset);
        await t.tap(find.text('Use template'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('create-name')),
          'Autumn Workshop',
        );
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('create-slug')))
              .controller!
              .text,
          'autumn-workshop',
        );
        await t.enterText(
          find.byKey(const ValueKey('create-slug')),
          'custom-workshop',
        );
        await t.enterText(
          find.byKey(const ValueKey('create-name')),
          'Our Autumn Workshop',
        );
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('create-slug')))
              .controller!
              .text,
          'custom-workshop',
        );
        t.testTextInput.hide();
        await t.pumpAndSettle();
        await capture(t, 'k145-setup-${size.width.toInt()}');
        await t.tap(find.text('Create draft'));
        await t.pumpAndSettle();
        expect(payload!['document']['layout'], 'event');
        expect(
          payload!['document']['headline'],
          funnelPresets.firstWhere((p) => p.id == 'event').headline,
        );
        expect(payload!['slug'], 'custom-workshop');
        expect(payload!.containsKey('state'), false);
        expect(find.byType(FunnelCreateDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Conflicts retain entries; pending submission cannot be repeated or dismissed',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var calls = 0;
      final pending = Completer<Map<String, dynamic>>();
      await openDialog(t, (p) async {
        calls++;
        if (calls == 1) {
          throw const FunnelException('That address is already taken.', 409);
        }
        return pending.future;
      }, source: sourceFunnel());
      await t.enterText(
        find.byKey(const ValueKey('create-name')),
        'Keep this name',
      );
      await t.tap(find.text('Create draft'));
      await t.pumpAndSettle();
      expect(find.text('That address is already taken.'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('create-name')))
            .controller!
            .text,
        'Keep this name',
      );
      await t.enterText(
        find.byKey(const ValueKey('create-slug')),
        'another-address',
      );
      await t.tap(find.text('Create draft'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Creating…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Close',
              ),
            )
            .onPressed,
        isNull,
      );
      final c = t.element(find.byType(FunnelCreateDialog));
      await Navigator.of(c).maybePop();
      await t.pump();
      expect(find.byType(FunnelCreateDialog), findsOneWidget);
      expect(calls, 2);
      pending.complete({'id': 'created'});
      await t.pumpAndSettle();
      expect(find.byType(FunnelCreateDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Published source duplicates into a private draft through the Enterprise API',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final original = sourceFunnel();
      final requests = <http.Request>[];
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'owner'},
        client: MockClient((r) async {
          requests.add(r);
          expect(r.headers['Authorization'], 'owner');
          if (r.method == 'POST') {
            expect(r.url.path, '/api/funnels');
            final p = jsonDecode(r.body);
            expect(p.keys, unorderedEquals(['name', 'slug', 'document']));
            expect(p['slug'], 'original-offer-copy');
            expect(p['document'], original['draft']);
            return http.Response(
              jsonEncode({
                'funnel': {
                  ...original,
                  'id': 'copy',
                  'name': p['name'],
                  'slug': p['slug'],
                  'state': 'draft',
                  'version': 1,
                  'lead_count': 0,
                  'page_requests': 0,
                },
              }),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'funnels': [original],
              'ai_ready': true,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await t.pumpWidget(MaterialApp(home: FunnelScreen(client: client)));
      await t.pumpAndSettle();
      await t.tap(find.text('Open studio'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('1:brand')),
        'An unsaved change',
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Duplicate draft'),
            )
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.text('Reload saved'));
      await t.tap(find.text('Reload saved'));
      await t.pumpAndSettle();
      await t.tap(find.text('Discard edits'));
      await t.pumpAndSettle();
      await t.tap(find.text('Duplicate draft'));
      await t.pumpAndSettle();
      await t.tap(find.text('Create draft'));
      await t.pumpAndSettle();
      expect(find.text('Our published offer copy'), findsNWidgets(2));
      expect(find.text('DRAFT'), findsWidgets);
      expect(find.text('Open live page'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(original['state'], 'published');
      expect(original['lead_count'], 10);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Enterprise denial closes creation and clears the source', (
    t,
  ) async {
    final client = FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(
        (r) async => r.method == 'POST'
            ? http.Response('{"error":"Enterprise access required"}', 403)
            : http.Response(
                jsonEncode({
                  'funnels': [sourceFunnel()],
                  'ai_ready': true,
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
      ),
    );
    await t.pumpWidget(MaterialApp(home: FunnelScreen(client: client)));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Open studio'));
    await t.tap(find.text('Open studio'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Duplicate draft'));
    await t.tap(find.text('Duplicate draft'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create draft'));
    await t.pumpAndSettle();
    expect(find.byType(FunnelCreateDialog), findsNothing);
    expect(find.text('Enterprise access required'), findsOneWidget);
    expect(find.text('Our published offer'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Checklist reflects unsaved state and links to editing and preview',
    (t) async {
      var edit = false, preview = false;
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: Scaffold(
            body: FunnelLaunchChecklist(
              document: funnelPresets.first.document(),
              dirty: true,
              onEdit: () => edit = true,
              onPreview: () => preview = true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('0 of 3 setup checks complete'), findsOneWidget);
      await t.tap(find.text('Edit page details'));
      await t.tap(find.text('Preview page'));
      expect(edit && preview, true);
      expect(find.textContaining('replace “Your business”'), findsOneWidget);
    },
  );
}

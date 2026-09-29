import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_catalog.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_screen.dart';
import 'social_test.dart' as social;
import 'social_replies_test.dart' as actions;
import 'picture_studio_test.dart' as pictures;
import 'agent_studio_test.dart' as fixtures;

class Briefs implements ImagineRecipeStore {
  final Map<String, List<String>> values = {};
  bool failRead = false;
  @override
  Future<List<String>> read(String key) async {
    if (failRead) throw StateError('Unavailable');
    return values[key] ?? [];
  }

  @override
  Future<void> write(String key, List<String> value) async {
    values[key] = value;
  }
}

String auth(String user) =>
    'Bearer x.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'iss': 'https://fixture.test', 'session_id': 'session-$user'}))).replaceAll('=', '')}.x';

class Studio {
  Studio({Briefs? storage}) : storage = storage ?? Briefs();
  final Briefs storage;
  final revision = ValueNotifier(0);
  final requests = <Map<String, dynamic>>[];
  String token = auth('alice');
  Completer<http.Response>? pending;
  int status = 200;
  String? invalidBody;
  late final client = ImagineClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    store: storage,
    client: MockClient((r) async {
      expect(r.url.path, '/api/image/create');
      expect(r.headers['Authorization'], token);
      requests.add(jsonDecode(r.body) as Map<String, dynamic>);
      if (pending != null) return pending!.future;
      return response();
    }),
  );
  Future<http.Response> response() async => http.Response(
    invalidBody ??
        jsonEncode(
          status == 200
              ? {
                  'imageDataUrl':
                      'data:image/png;base64,${base64Encode(await pictures.png(Colors.blue))}',
                  'generationId': 'result-${requests.length}',
                }
              : {'error': 'Daily credit limit reached'},
        ),
    status,
  );
  void change() {
    token = auth('bob');
    revision.value++;
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
  test('creative brief preserves exact words and bounded saved settings', () {
    const b = ImagineBrief(
      prompt: 'My cafe launch',
      style: 'design',
      lighting: 'golden',
      palette: 'warm',
      composition: 'left',
      lettering: 'HELLO, WORLD!\nCafé',
      avoid: 'busy backgrounds',
    );
    expect(b.compiledPrompt, contains('HELLO, WORLD!\nCafé'));
    expect(b.compiledPrompt, contains('Golden hour'));
    expect(b.compiledPrompt, contains('busy backgrounds'));
    final restored = ImagineBrief.fromJson({
      ...b.json,
      'style': 'injected',
      'prompt': 'x' * 9000,
    });
    expect(restored.style, 'auto');
    expect(restored.prompt.length, 8000);
    expect(const ImagineBrief().error, isNotNull);
  });
  test(
    'client sends chosen settings once during a pending generation and retains the result',
    () async {
      final s = Studio()..pending = Completer<http.Response>();
      final c = s.client;
      final first = c.create(
        const ImagineBrief(
          prompt: 'Floating glass sphere',
          style: '3d',
          size: '1536x1024',
          palette: 'cool',
        ),
      );
      expect(await c.create(const ImagineBrief(prompt: 'Another')), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(s.requests.length, 1);
      expect(s.requests.first['imageStyle'], '3d');
      expect(s.requests.first['imageSize'], '1536x1024');
      expect(s.requests.first['prompt'], contains('Cyan & violet'));
      s.pending!.complete(await s.response());
      final result = await first;
      expect(result!.width, 8);
      expect(c.results.single, result);
      expect(c.busy, false);
      c.dispose();
    },
  );
  test('late image responses cannot cross an account change', () async {
    final s = Studio()..pending = Completer<http.Response>();
    final pending = s.client.create(
      const ImagineBrief(prompt: 'Private image'),
    );
    final rejected = expectLater(pending, throwsA(isA<ImagineException>()));
    await Future<void>.delayed(Duration.zero);
    s.change();
    s.pending!.complete(await s.response());
    await rejected;
    expect(s.client.results, isEmpty);
    expect(s.client.draft.prompt, isEmpty);
    expect(s.client.available, false);
    s.client.dispose();
  });
  test(
    'failed generation preserves the draft without adding a gallery result',
    () async {
      for (final body in [
        '<html>error</html>',
        '{"imageDataUrl":"data:image/png;base64,bm90LXBpY3R1cmU="}',
      ]) {
        final s = Studio()..invalidBody = body;
        await expectLater(
          s.client.create(const ImagineBrief(prompt: 'A garden')),
          throwsA(isA<ImagineException>()),
        );
        expect(s.client.results, isEmpty);
        expect(s.client.draft.prompt, 'A garden');
        expect(s.client.busy, false);
        s.client.dispose();
      }
      final s = Studio()..status = 429;
      await expectLater(
        s.client.create(const ImagineBrief(prompt: 'A garden')),
        throwsA(isA<ImagineException>()),
      );
      expect(s.client.error, contains('credit limit'));
      s.client.dispose();
    },
  );
  test(
    'saved briefs load before a write, stay account scoped and survive a new studio',
    () async {
      final store = Briefs(), a = Studio(storage: Briefs());
      a.client.dispose();
      final first = Studio(storage: store);
      await first.client.saveBrief(
        'Campaign',
        const ImagineBrief(prompt: 'A cafe poster', style: 'design'),
      );
      first.client.dispose();
      final second = Studio(storage: store);
      await second.client.saveBrief(
        'Product',
        const ImagineBrief(prompt: 'A product photo'),
      );
      expect(second.client.recipes.length, 2);
      expect(
        store.values.values.single.join(),
        isNot(contains('imageDataUrl')),
      );
      final bob = Studio(storage: store)..token = auth('bob');
      await bob.client.loadBriefs();
      expect(bob.client.recipes, isEmpty);
      await second.client.deleteBrief('${second.client.recipes.first['id']}');
      expect(second.client.recipes.length, 1);
      second.client.dispose();
      bob.client.dispose();
    },
  );
  test('failed local storage reads never overwrite existing briefs', () async {
    final s = Studio(storage: Briefs()..failRead = true);
    await expectLater(
      s.client.saveBrief('Keep me', const ImagineBrief(prompt: 'A forest')),
      throwsA(isA<ImagineException>()),
    );
    expect(s.storage.values, isEmpty);
    s.client.dispose();
  });
  Future<void> mount(
    WidgetTester t,
    Studio s, {
    double width = 390,
    double scale = 1,
    String theme = 'korlix_blue',
    bool consent = true,
    Future<void> Function(ImagineResult)? refine,
    Future<void> Function(Uint8List, String)? save,
  }) async {
    await social.mount(
      t,
      ImagineStudioScreen(
        client: s.client,
        ensureConsent: () async => consent,
        allowVoice: true,
        onRefine: refine ?? (_) async {},
        saveImage: save,
      ),
      width: width,
      height: 1000,
      scale: scale,
      theme: theme,
    );
  }

  testWidgets(
    'generation requires an explicit click and consent; result actions preserve bytes',
    (t) async {
      final s = Studio();
      Uint8List? saved;
      ImagineResult? refined;
      addTearDown(s.client.dispose);
      await mount(
        t,
        s,
        refine: (r) async => refined = r,
        save: (b, _) async => saved = b,
      );
      await t.enterText(
        find.byKey(const Key('imagine-prompt')),
        'A glass sculpture',
      );
      expect(s.requests, isEmpty);
      await actions.tap(t, find.byKey(const Key('imagine-create')));
      expect(s.requests.length, 1);
      expect(find.text('Made from your imagination'), findsOneWidget);
      await actions.tap(t, find.text('Download PNG'));
      expect(saved, s.client.results.single.bytes);
      await actions.tap(t, find.text('Refine picture'));
      expect(refined, s.client.results.single);
      await actions.tap(t, find.text('Reuse settings'));
      expect(s.requests.length, 1);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('imagine-prompt')))
            .controller!
            .text,
        'A glass sculpture',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('declined consent sends no request and keeps typed text', (
    t,
  ) async {
    final s = Studio();
    addTearDown(s.client.dispose);
    await mount(t, s, consent: false);
    await t.enterText(
      find.byKey(const Key('imagine-prompt')),
      'A private idea',
    );
    await actions.tap(t, find.byKey(const Key('imagine-create')));
    expect(s.requests, isEmpty);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('imagine-prompt')))
          .controller!
          .text,
      'A private idea',
    );
  });
  testWidgets(
    'saved brief dialog, restoration and account change clear private fields',
    (t) async {
      final s = Studio();
      addTearDown(s.client.dispose);
      await mount(t, s);
      await t.enterText(
        find.byKey(const Key('imagine-prompt')),
        'A botanical illustration',
      );
      await actions.tap(t, find.text('Save brief'));
      await t.enterText(
        find.widgetWithText(TextField, 'Brief name'),
        'Botanical',
      );
      await actions.tap(t, find.text('Save brief').last);
      expect(s.client.recipes.length, 1);
      await actions.tap(t, find.text('Saved briefs'));
      expect(find.text('Botanical'), findsOneWidget);
      await actions.tap(t, find.text('Use this brief'));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('imagine-prompt')))
            .controller!
            .text,
        'A botanical illustration',
      );
      s.change();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('imagine-prompt')), findsNothing);
      expect(find.text('A botanical illustration'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'account changes dismiss private brief text inside an open dialog',
    (t) async {
      final s = Studio();
      addTearDown(s.client.dispose);
      await mount(t, s);
      await t.enterText(
        find.byKey(const Key('imagine-prompt')),
        'Private creative idea',
      );
      await actions.tap(t, find.text('Save brief'));
      await t.enterText(
        find.widgetWithText(TextField, 'Brief name'),
        'Private campaign',
      );
      s.change();
      await t.pumpAndSettle();
      expect(find.text('Private campaign'), findsNothing);
      expect(find.widgetWithText(TextField, 'Brief name'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final v in [
    (390.0, 1.0, 'korlix_blue'),
    (320.0, 1.6, 'pure_black'),
    (390.0, 1.0, 'pure_white'),
    (1280.0, 1.0, 'korlix_blue'),
  ]) {
    testWidgets('studio layout ${v.$1} ${v.$2} ${v.$3}', (t) async {
      final s = Studio();
      addTearDown(s.client.dispose);
      await mount(t, s, width: v.$1, scale: v.$2, theme: v.$3);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'imagine-create-${v.$1.toInt()}-${v.$3}');
      await actions.tap(t, find.text('Art direction'));
      expect(t.takeException(), isNull);
      await actions.tap(t, find.byKey(const Key('imagine-create')));
      expect(t.takeException(), isNull);
      expect(s.requests, isEmpty);
      await fixtures.capture(t, 'imagine-controls-${v.$1.toInt()}-${v.$3}');
    });
  }
}

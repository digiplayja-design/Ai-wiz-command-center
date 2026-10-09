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
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_catalog.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_processing_panel.dart';
import 'imagine_studio_test.dart' as imagine;
import 'logo_studio_test.dart' as logo;
import 'social_test.dart' as social;
import 'social_invites_test.dart' as actions;
import 'agent_studio_test.dart' as fixtures;

http.Response job(String status, {String stage = 'planning', dynamic result}) =>
    http.Response(
      jsonEncode({
        'jobId': 'logo_existing',
        'status': status,
        'stage': stage,
        'result': ?result,
      }),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

ImagineClient client(Future<http.Response> Function(http.Request) handler) =>
    ImagineClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': imagine.auth('alice')},
      client: MockClient(handler),
      store: imagine.Briefs(),
      logoPollInterval: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'monospace',
    )..addFont(rootBundle.load('assets/logo_fonts/spacemono.ttf'))).load();
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
    'completed logo with an em dash, smart quotes and multilingual text keeps its PNG and direction',
    () async {
      final fixture = imagine.Studio();
      final result =
          jsonDecode((await fixture.response()).body) as Map<String, dynamic>;
      const summary =
          'One destination for connected tools—not another standalone app. “KORLIX AI” • Café • 東京 ✨';
      result.addAll({
        'success': true,
        'title': 'Logo Studio concept',
        'content': 'Logo concept: Orbit Dock. $summary',
        'logoDirection': {
          'conceptName': 'Orbit Dock',
          'summary': summary,
          'planningModel': 'gpt-6-astra',
          'reasoningEffort': 'max',
        },
      });
      var posts = 0;
      final c = client((request) async {
        if (request.method == 'POST') {
          posts++;
          return job('queued');
        }
        return job('completed', result: result);
      });
      addTearDown(c.dispose);
      final image = await c.create(
        logo.sample.aiBrief,
        logoBrief: logo.sample.json,
      );
      expect(image!.logoDirection!.summary, summary);
      expect(image.logoDirection!.conceptName, 'Orbit Dock');
      expect(
        image.bytes,
        base64Decode((result['imageDataUrl'] as String).substring(22)),
      );
      expect(c.error, isNull);
      expect(c.hasPendingLogo, false);
      expect(posts, 1);
    },
  );

  test(
    'raw service payloads and unexpected exceptions never become display errors',
    () async {
      const raw = '{"imageDataUrl":"data:image/png;base64,PRIVATE_PIXELS"}';
      for (final value in [
        raw,
        'x' * 2000,
        {'imageDataUrl': raw},
      ]) {
        final c = client(
          (request) async => http.Response(
            jsonEncode({
              'jobId': 'logo_existing',
              'status': 'failed',
              'error': value,
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await expectLater(
          c.create(logo.sample.aiBrief, logoBrief: logo.sample.json),
          throwsA(isA<ImagineException>()),
        );
        expect(c.error, 'This logo could not be completed.');
        expect(c.busy, false);
        c.dispose();
      }
      final c = client((_) async => throw ArgumentError.value(raw, 'string'));
      await expectLater(
        c.create(const ImagineBrief(prompt: 'A picture')),
        throwsA(isA<ImagineException>()),
      );
      expect(c.error, isNot(contains('PRIVATE_PIXELS')));
      expect(c.error, isNot(contains('Invalid argument')));
      expect(c.error!.length, lessThan(200));
      c.dispose();
    },
  );

  test(
    'lost start reply uses the same request ID; poll failures keep one job and report actual stages',
    () async {
      final fixture = imagine.Studio();
      final result = jsonDecode((await fixture.response()).body);
      final posts = <Map<String, dynamic>>[], stages = <String>[];
      var reads = 0;
      final c = client((request) async {
        if (request.method == 'POST') {
          posts.add(jsonDecode(request.body));
          if (posts.length == 1) throw http.ClientException('Lost response');
          return job('queued', stage: 'queued');
        }
        expect(request.url.path, '/api/logo/jobs/logo_existing');
        reads++;
        if (reads == 1) throw http.ClientException('Offline');
        if (reads == 2) return job('processing');
        if (reads == 3) return job('processing', stage: 'rendering');
        return job('completed', result: result);
      });
      c.addListener(() => stages.add(c.logoStage));
      final image = await c.create(
        logo.sample.aiBrief,
        logoBrief: logo.sample.json,
      );
      expect(posts.length, 2);
      expect(posts[0]['clientRequestId'], posts[1]['clientRequestId']);
      expect(
        stages,
        containsAllInOrder(['queued', 'planning', 'rendering', 'completed']),
      );
      expect(image, isNotNull);
      expect(c.hasPendingLogo, false);
      expect(c.logoReconnecting, false);
      c.dispose();
    },
  );

  test(
    'manual reconnect reads the pending job and preserves its original brief',
    () async {
      final fixture = imagine.Studio();
      final result = jsonDecode((await fixture.response()).body);
      var posts = 0, reads = 0;
      final c = client((request) async {
        if (request.method == 'POST') {
          posts++;
          return job('queued');
        }
        if (++reads <= 5) throw http.ClientException('Offline');
        return job('completed', result: result);
      });
      await expectLater(
        c.create(logo.sample.aiBrief, logoBrief: logo.sample.json),
        throwsA(isA<ImagineException>()),
      );
      expect(c.hasPendingLogo, true);
      expect(c.busy, false);
      expect(c.error, contains('Check pending logo'));
      final image = await c.create(
        logo.sample.copy(name: 'Changed').aiBrief,
        logoBrief: logo.sample.copy(name: 'Changed').json,
      );
      expect(posts, 1);
      expect(reads, 6);
      expect(image!.brief.lettering, contains('DA FINAL STOP'));
      expect(c.results.length, 1);
      c.dispose();
    },
  );

  testWidgets(
    'Matrix displays server progress on narrow screens and with large text',
    (t) async {
      for (final width in [320.0, 390.0, 960.0]) {
        await social.mount(
          t,
          Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: 560,
                  child: LogoProcessingPanel(
                    elapsed: 207,
                    stage: width == 960 ? 'rendering' : 'planning',
                  ),
                ),
              ),
            ),
          ),
          width: width,
          scale: width == 320 ? 1.5 : 1,
        );
        expect(find.text('3:27'), findsOneWidget);
        expect(find.text('ASTRA / MAX'), findsOneWidget);
        expect(t.takeException(), isNull);
        await fixtures.capture(t, 'logo-matrix-${width.toInt()}');
        await t
            .pumpAndSettle(); // Reduced-motion setting leaves no animation running.
      }
    },
  );

  testWidgets('Matrix rain moves between frames and is disposed cleanly', (
    t,
  ) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: const LogoProcessingPanel(elapsed: 4, stage: 'planning'),
          ),
        ),
      ),
    );
    Future<List<int>> pixels() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final first = await t.runAsync(pixels);
    await t.pump(const Duration(milliseconds: 600));
    final second = await t.runAsync(pixels);
    expect(second, isNot(equals(first)));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Logo Studio scrolls the Matrix into view until its pending result arrives',
    (t) async {
      final f = logo.LogoFixture();
      final result = await f.studio.response();
      f.studio.pending = Completer<http.Response>();
      await social.mount(t, f.screen());
      await logo.begin(t, f);
      await actions.tap(t, find.text('Explore with AI'));
      expect(find.byType(LogoProcessingPanel), findsOneWidget);
      expect(
        find.text('Astra is shaping your logo').hitTestable(),
        findsOneWidget,
      );
      expect(f.studio.requests.length, 1);
      await fixtures.capture(t, 'logo-matrix-studio-390');
      f.studio.pending!.complete(result);
      await t.pumpAndSettle();
      expect(find.byType(LogoProcessingPanel), findsNothing);
      expect(f.c.images.results.length, 1);
      expect(t.takeException(), isNull);
    },
  );
}

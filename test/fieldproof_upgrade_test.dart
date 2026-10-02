import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_client.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_photos.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_report.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_screen.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_voice.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_workspace.dart';
import 'fieldproof_test.dart' as fixture;

Future<void> _show(
  WidgetTester t,
  fixture.FakeFieldProof client, {
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>?)? voice,
  Future<List<FieldProofQueuedPhoto>> Function(int)? picker,
  double width = 390,
  GlobalKey? capture,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(1.25),
        ),
        child: RepaintBoundary(
          key: capture,
          child: FieldProofScreen(
            client: client,
            ensureConsent: () async => true,
            openVoice: voice,
            pickBatch: picker,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test(
    'follow-up reset preserves site and required scope while clearing completion data',
    () {
      final original = {
        ...fixture.data(),
        'priority': 'urgent',
        'stage': 'ready',
        'dueOn': '2026-10-03',
        'readings': [
          {'id': 'r', 'value': '900'},
        ],
        'issues': [
          {'id': 'i', 'resolved': true},
        ],
        'checks': [
          {
            'id': 'required-0',
            'label': 'Work done',
            'done': true,
            'required': true,
          },
        ],
      };
      final draft = fpRepeatDraft(original);
      expect(draft['customer'], original['customer']);
      expect(draft['site'], original['site']);
      expect(draft['requiredTags'], original['requiredTags']);
      expect(draft['summary'], '');
      expect(draft['readings'], isEmpty);
      expect(draft['issues'], isEmpty);
      expect(draft['checks'][0]['done'], false);
      expect(draft['dueOn'], '');
      expect(draft['stage'], 'planned');
      expect(original['checks'][0]['done'], true);
    },
  );
  test(
    'voice new-job draft supports exact readings and preserves untouched fields',
    () async {
      final template = {
        'name': 'General',
        'requiredTags': ['after'],
        'checks': <dynamic>[],
        'requiresApproval': false,
      };
      int writes = 0;
      final calls = <String>[];
      final client = FieldProofClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add(r.url.path);
          if (r.method == 'GET')
            return http.Response(
              jsonEncode({
                'jobs': [],
                'templates': {'general': template},
              }),
              200,
            );
          if (r.url.path == '/api/fieldproof/voice/draft') {
            final body = jsonDecode(r.body);
            return http.Response(
              jsonEncode({
                ...body,
                'saved': false,
                'reviewRequired': true,
                'readyToSave': false,
              }),
              200,
            );
          }
          writes++;
          throw StateError('Unexpected write');
        }),
      );
      final voice = FieldProofVoiceController(client: client);
      await voice.handleToolCall('get_fieldproof_context', {}, 'context');
      await voice.handleToolCall('start_fieldproof_draft', {
        'template': 'general',
      }, 'start');
      await voice.handleToolCall('update_fieldproof_field', {
        'field': 'customer',
        'value': 'Fixture company',
      }, 'customer');
      final args = {
        'label': 'Meter',
        'value': '00123.40',
        'unit': 'kWh',
        'note': 'Recorded on site',
      };
      final first = await voice.handleToolCall(
        'add_fieldproof_reading',
        args,
        'reading',
      );
      final repeated = await voice.handleToolCall(
        'add_fieldproof_reading',
        args,
        'reading',
      );
      expect(first, repeated);
      expect(voice.pendingDraft?['draft']['customer'], 'Fixture company');
      expect(
        voice.pendingDraft?['draft']['readings'].single['value'],
        '00123.40',
      );
      expect(calls.where((x) => x.endsWith('/voice/draft')).length, 3);
      expect(writes, 0);
      voice.clearPending();
      expect(
        (await voice.handleToolCall(
          'get_fieldproof_context',
          {},
          'context',
        ))['discarded'],
        true,
      );
      voice.dispose();
      client.dispose();
    },
  );
  test(
    'failed new-job preparation cannot detach the existing draft from its job',
    () async {
      var rejectNew = false;
      final bodies = <Map<String, dynamic>>[];
      final saved = fixture.snapshot();
      final client = FieldProofClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          if (r.method == 'GET')
            return http.Response(
              jsonEncode(
                r.url.path.endsWith('/job-1')
                    ? saved
                    : {
                        'jobs': [saved['job']],
                        'templates': {
                          'utility': {
                            'name': 'Utility',
                            'checks': fixture.data()['checks'],
                            'requiredTags': fixture.data()['requiredTags'],
                            'requiresApproval': true,
                          },
                        },
                      },
              ),
              200,
            );
          final body = Map<String, dynamic>.from(jsonDecode(r.body));
          bodies.add(body);
          if (rejectNew && body['jobId'] == null)
            return http.Response('{"error":"Temporary interruption"}', 503);
          return http.Response(
            jsonEncode({
              ...body,
              'saved': false,
              'reviewRequired': true,
              'readyToSave': true,
            }),
            200,
          );
        }),
      );
      final voice = FieldProofVoiceController(client: client, snapshot: saved);
      await voice.handleToolCall('get_fieldproof_context', {}, 'context');
      await voice.handleToolCall('update_fieldproof_field', {
        'field': 'summary',
        'value': 'Original working draft',
      }, 'update');
      rejectNew = true;
      expect(
        (await voice.handleToolCall('start_fieldproof_draft', {
          'template': 'utility',
        }, 'new'))['success'],
        false,
      );
      await voice.handleToolCall('update_fieldproof_field', {
        'field': 'technician',
        'value': 'Named technician',
      }, 'continued');
      expect(bodies.last['jobId'], 'job-1');
      expect(bodies.last['version'], 3);
      expect(voice.pendingDraft?['draft']['summary'], 'Original working draft');
      voice.dispose();
      client.dispose();
    },
  );
  testWidgets(
    'voice handoff remains unsaved until reviewed; stale drafts are rejected',
    (t) async {
      final c = fixture.FakeFieldProof();
      bool stale = false;
      await _show(
        t,
        c,
        voice: (snapshot) async => {
          'action': 'draft',
          'jobId': 'job-1',
          'version': stale ? 1 : 3,
          'draft': {
            ...fixture.data(),
            'summary': 'Voice draft summary',
            'priority': 'high',
          },
        },
      );
      await fixture.open(t);
      await fixture.tap(t, find.byKey(const Key('fp-voice')));
      expect(c.saves, 0);
      expect(find.byKey(const Key('fp-save-job')), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('fp-field-summary')))
            .controller!
            .text,
        'Voice draft summary',
      );
      await fixture.tap(t, find.byKey(const Key('fp-save-job')));
      expect(c.saves, 1);
      expect(fpMap(c.row['job'])['data']['summary'], 'Voice draft summary');
      stale = true;
      await fixture.tap(t, find.byKey(const Key('fp-voice')));
      expect(c.saves, 1);
      expect(find.textContaining('changed during voice'), findsOneWidget);
      expect(find.byKey(const Key('fp-save-job')), findsNothing);
      await fixture.close(t);
    },
  );
  testWidgets(
    'batch retries only failed photos with stable request IDs and original bytes',
    (t) async {
      final rows = [
        for (final name in ['first.png', 'second.png'])
          FieldProofQueuedPhoto(
            name: name,
            load: () async => FieldProofPhoto(name, fixture.photo),
          ),
      ];
      final attempts = <String>[];
      bool fail = true;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => FieldProofBatchDialog(
                    remaining: 24,
                    pick: (_) async => rows,
                    upload: (row, photo) async {
                      attempts.add(row.key);
                      expectSync(photo.bytes, fixture.photo);
                      if (row == rows[1] && fail)
                        throw const FieldProofException('Fixture interruption');
                    },
                  ),
                ),
                child: const Text('Batch'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Batch'));
      await t.pumpAndSettle();
      await fixture.tap(t, find.byKey(const Key('fp-batch-pick')));
      await fixture.tap(t, find.byKey(const Key('fp-batch-upload')));
      expect(attempts, [rows[0].key, rows[1].key]);
      expect(rows[0].saved, true);
      expect(rows[1].saved, false);
      expect(rows[1].cached, isNotNull);
      fail = false;
      await fixture.tap(t, find.byKey(const Key('fp-batch-upload')));
      expect(attempts, [rows[0].key, rows[1].key, rows[1].key]);
      expect(rows.every((x) => x.saved), true);
      expect(rows.every((x) => x.cached == null), true);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'readings and punch-list entries fit phone layout and appear in reports',
    (t) async {
      final c = fixture.FakeFieldProof();
      await _show(t, c);
      await fixture.open(t);
      await fixture.tap(t, find.byKey(const Key('fp-tab-4')));
      await fixture.tap(t, find.byKey(const Key('fp-add-reading')));
      await t.enterText(find.byKey(const Key('fp-record-label')), 'Pressure');
      await t.enterText(find.byKey(const Key('fp-record-value')), '08.50');
      await t.enterText(find.byKey(const Key('fp-record-unit')), 'bar');
      await fixture.tap(t, find.byKey(const Key('fp-record-save')));
      expect(c.saves, 1);
      expect(fpReportText(c.row), contains('Pressure: 08.50 bar'));
      await fixture.tap(t, find.byKey(const Key('fp-add-issue')));
      await t.enterText(find.byKey(const Key('fp-record-label')), 'Check seal');
      await fixture.tap(t, find.text('Must resolve before closeout'));
      await fixture.tap(t, find.byKey(const Key('fp-record-save')));
      expect(c.saves, 2);
      expect(fpReportText(c.row), contains('Blocks closeout'));
      expect(t.takeException(), isNull);
      await fixture.close(t);
    },
  );
  testWidgets('optional upgrade screenshots and report render', (t) async {
    final dir = Platform.environment['FIELDPROOF_CAPTURE_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf')))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '${Platform.environment['KORLIX_FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    });
    for (final width in [390.0, 1440.0]) {
      final c = fixture.FakeFieldProof(), key = GlobalKey();
      c.row['job']['data'] = {
        ...fixture.data(),
        'priority': 'high',
        'stage': 'in_progress',
        'dueOn': '2026-10-04',
        'readings': [
          {
            'id': 'reading-1',
            'label': 'Final meter reading',
            'value': '00123.40',
            'unit': 'kWh',
            'note': 'Technician recorded',
          },
        ],
        'issues': [
          {
            'id': 'issue-1',
            'label': 'Replace cabinet seal',
            'assignee': 'Field crew',
            'dueOn': '2026-10-05',
            'priority': 'high',
            'blocking': true,
            'resolved': false,
          },
        ],
      };
      await _show(t, c, voice: (_) async => null, width: width, capture: key);
      await t.pump();
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/upgrade-home-${width.toInt()}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
      await fixture.open(t);
      await fixture.tap(t, find.byKey(const Key('fp-tab-4')));
      await fixture.tap(t, find.byKey(const Key('fp-add-reading')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      if (width == 1440)
        await t.runAsync(() async {
          await File('$dir/fieldproof-upgrade.pdf').writeAsBytes(
            await buildFieldProofPdf(c.row, {'photo-1': fixture.photo}),
          );
        });
      await fixture.close(t);
    }
  });
}

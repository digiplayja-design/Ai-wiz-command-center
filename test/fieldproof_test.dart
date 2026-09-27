import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_client.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_report.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_screen.dart';

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAIAAABd+SbeAAAAzElEQVR4nO3QQRHAIADAMEDxRKEBfVOx8liioNf57DP43rod8BdGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOjIC4/5Amrf5r6wAAAAAElFTkSuQmCC',
);
Map<String, dynamic> data() => {
  'template': 'utility',
  'title': 'Meter installation',
  'customer': 'Bright Pine Utilities',
  'site': '12 Pine Road',
  'workOrder': 'WO-1042',
  'technician': 'Alex Rivera',
  'performedOn': '2026-09-27',
  'assetId': 'MTR-2034',
  'oldAssetId': 'MTR-1012',
  'summary':
      'Replaced meter and documented the final reading. Customer requested follow-up next week.',
  'exceptions': 'Follow-up visit requested',
  'materials': 'One meter; two seals',
  'billingNotes': 'Confirm contracted rate',
  'hours': 1.5,
  'requiresApproval': true,
  'requiredTags': ['before', 'after', 'serial'],
  'checks': [
    {
      'id': 'required-work',
      'label': 'Work documented',
      'required': true,
      'done': false,
    },
  ],
};
Map<String, dynamic> snapshot() => {
  'job': {
    'id': 'job-1',
    'data': data(),
    'version': 3,
    'state': 'active',
    'createdAt': '2026-09-27T18:00:00Z',
    'updatedAt': '2026-09-27T18:00:00Z',
    'approval': null,
    'completion': null,
  },
  'evidence': [
    {
      'id': 'photo-1',
      'name': 'Completed meter',
      'tag': 'after',
      'note': 'Final work photo',
      'state': 'ready',
      'mime': 'image/png',
      'bytes': photo.length,
      'width': 1,
      'height': 1,
      'sha256': 'a' * 64,
      'uploadedAt': '2026-09-27T18:00:00Z',
      'previewUrl': null,
    },
  ],
  'reviews': <Map<String, dynamic>>[],
  'events': [
    {
      'action': 'job_created',
      'version': 1,
      'created_at': '2026-09-27T18:00:00Z',
    },
  ],
  'readiness': {
    'ready': false,
    'label': 'Evidence needs attention',
    'missing': [
      'Before work photo',
      'Customer approval recorded for this job revision',
    ],
    'limits': 'Completeness of supplied records only.',
  },
  'fingerprint': 'b' * 64,
  'snapshotAt': '2026-09-27T18:00:00Z',
};

class FakeFieldProof extends FieldProofClient {
  FakeFieldProof()
    : super(backendBaseUrl: 'https://example.test', headersBuilder: () => {});
  Map<String, dynamic> row = snapshot();
  bool empty = false, failSave = false, failUpload = false;
  int saves = 0, uploads = 0, starts = 0, gets = 0, deletes = 0;
  List<String> keys = [], uploadKeys = [];
  List<bool> downloads = [];
  @override
  Future<Map<String, dynamic>> load() async => {
    'jobs': empty ? [] : [row['job']],
    'templates': {
      'utility': {
        'name': 'Utility field work',
        'requiredTags': ['before', 'after', 'serial'],
        'requiresApproval': true,
        'checks': data()['checks'],
      },
    },
  };
  @override
  Future<Map<String, dynamic>> job(String id) async {
    gets++;
    return row;
  }

  @override
  Future<Map<String, dynamic>> create(
    String key,
    Map<String, dynamic> value,
  ) async {
    saves++;
    keys.add(key);
    if (failSave) {
      throw const FieldProofException(
        'Connection interrupted. Your entries are still here.',
      );
    }
    row['job'] = {...fpMap(row['job']), 'data': value};
    empty = false;
    return row;
  }

  @override
  Future<Map<String, dynamic>> save(
    String id,
    int version,
    Map<String, dynamic> value,
  ) async {
    saves++;
    if (failSave) {
      throw const FieldProofException('Save failed. Refresh before retrying.');
    }
    row['job'] = {...fpMap(row['job']), 'data': value, 'version': version + 1};
    return row;
  }

  @override
  Future<Map<String, dynamic>> upload(
    String jobId,
    int version,
    FieldProofPhoto p, {
    required String key,
    required String tag,
    required String name,
    required String note,
  }) async {
    uploads++;
    uploadKeys.add(key);
    if (failUpload) {
      throw const FieldProofException(
        'Interrupted upload. Keep this photo selected and retry.',
      );
    }
    return row;
  }

  @override
  Future<Map<String, dynamic>> approve(
    String id,
    int version,
    String name,
    String note,
  ) async {
    row['job'] = {
      ...fpMap(row['job']),
      'approval': {
        'name': name,
        'note': note,
        'version': version,
        'recordedBy': 'Alex Rivera',
        'recordedAt': '2026-09-27',
      },
    };
    return row;
  }

  @override
  Future<Map<String, dynamic>> complete(String id, int version) async {
    row['job'] = {...fpMap(row['job']), 'state': 'completed'};
    return row;
  }

  @override
  Future<Map<String, dynamic>> startReview(
    String id,
    int version,
    String key,
  ) async {
    starts++;
    final r = {
      'id': key,
      'state': 'running',
      'version': version,
      'createdAt': '2026-09-27',
    };
    row['reviews'] = [r];
    return r;
  }

  @override
  Future<Uint8List> photoBytes(String id, {bool preview = false}) async {
    downloads.add(preview);
    return photo;
  }

  @override
  Future<void> remove(String id, int version) async {
    deletes++;
    empty = true;
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeFieldProof c, {
  double width = 390,
  double scale = 1,
  Future<bool> Function()? consent,
  Future<void> Function(Uint8List, String, String)? saver,
  Future<Uint8List> Function(Map<String, dynamic>, Map<String, Uint8List>)?
  render,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: FieldProofScreen(
            client: c,
            ensureConsent: consent ?? () async => true,
            pickPhoto: (_) async => FieldProofPhoto('meter.png', photo),
            saveFile: saver,
            renderPdf: render,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> tap(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump(const Duration(milliseconds: 400));
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 400));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> open(WidgetTester t) async {
  await tap(t, find.text('Open job').first);
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

String jwt(String user) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': user, 'session_id': 'session'}))).replaceAll('=', '')}.sig';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'client sends authentication and rejects missing or foreign save acknowledgements',
    () async {
      for (final body in [
        {},
        {
          ...snapshot(),
          'job': {...fpMap(snapshot()['job']), 'id': 'foreign'},
        },
      ]) {
        final c = FieldProofClient(
          backendBaseUrl: 'https://example.test/',
          headersBuilder: () => {'Authorization': 'Bearer token'},
          client: MockClient((q) async {
            expect(q.headers['Authorization'], 'Bearer token');
            expect(q.url.path, '/api/fieldproof/jobs/job-1');
            return http.Response(jsonEncode(body), 200);
          }),
        );
        await expectLater(
          c.save('job-1', 3, data()),
          throwsA(isA<FieldProofException>()),
        );
        c.dispose();
      }
    },
  );
  test('in-flight response is rejected when the account changes', () async {
    final changes = ValueNotifier(0), pending = Completer<http.Response>();
    var user = 'one';
    var locked = false;
    final c = FieldProofClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': 'Bearer ${jwt(user)}'},
      sessionChanges: changes,
      client: MockClient((_) => pending.future),
    );
    c.onAccessDenied = () => locked = true;
    final request = c.job('job-1');
    final expectRequest = expectLater(
      request,
      throwsA(isA<FieldProofException>()),
    );
    user = 'two';
    changes.value++;
    pending.complete(http.Response(jsonEncode(snapshot()), 200));
    await expectRequest;
    expect(locked, true);
    c.dispose();
    changes.dispose();
  });
  test(
    'multipart upload preserves bytes and request key without caller content type',
    () async {
      final c = FieldProofClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {
          'Authorization': 'Bearer token',
          'Content-Type': 'application/json',
        },
        client: MockClient((q) async {
          expect(
            q.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(latin1.decode(q.bodyBytes), contains('photo-key'));
          expect(q.bodyBytes, containsAllInOrder(photo));
          return http.Response(jsonEncode(snapshot()), 201);
        }),
      );
      await c.upload(
        'job-1',
        3,
        FieldProofPhoto('meter.png', photo),
        key: 'photo-key',
        tag: 'after',
        name: 'Meter',
        note: '',
      );
      c.dispose();
    },
  );
  test('reports exclude stale AI drafts and label approval accurately', () {
    final s = snapshot();
    s['reviews'] = [
      {
        'state': 'completed',
        'version': 2,
        'result': {'summary': 'STALE PRIVATE DRAFT'},
      },
    ];
    s['job']['approval'] = {
      'name': 'Customer contact',
      'version': 2,
      'note': 'Reported verbally',
      'recordedBy': 'Technician',
      'recordedAt': '2026-09-27',
    };
    final r = fpReportText(s);
    expect(r, contains('earlier revision'));
    expect(r, contains('not an independently verified signature'));
    expect(r, contains('Original SHA-256'));
    expect(r, isNot(contains('STALE PRIVATE DRAFT')));
    expect(fpInvoiceText(s), contains('does not issue an invoice'));
  });
  testWidgets(
    'phone validation and failed save preserve entries and the create key',
    (t) async {
      final c = FakeFieldProof()..empty = true;
      await show(t, c);
      await tap(t, find.byKey(const Key('fp-new')));
      await tap(t, find.byKey(const Key('fp-save-job')));
      expect(c.saves, 0);
      expect(find.text('Enter job title.'), findsOneWidget);
      for (final e in {
        'title': 'Meter installation',
        'customer': 'Bright Pine',
        'site': '12 Pine Road',
      }.entries) {
        await t.ensureVisible(find.byKey(Key('fp-field-${e.key}')));
        await t.enterText(find.byKey(Key('fp-field-${e.key}')), e.value);
      }
      c.failSave = true;
      await tap(t, find.byKey(const Key('fp-save-job')));
      expect(find.byKey(const Key('fp-save-error')), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('fp-field-title')))
            .controller!
            .text,
        'Meter installation',
      );
      c.failSave = false;
      await tap(t, find.byKey(const Key('fp-save-job')));
      expect(c.keys.length, 2);
      expect(c.keys.first, c.keys.last);
      expect(find.byKey(const Key('fp-tab-1')), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets('upload retry retains selected original and nonce', (t) async {
    final c = FakeFieldProof()..failUpload = true;
    await show(t, c);
    await open(t);
    await tap(t, find.byKey(const Key('fp-tab-1')));
    await tap(t, find.byKey(const Key('fp-add-photo')));
    await tap(t, find.byKey(const Key('fp-pick-file')));
    await t.enterText(find.byKey(const Key('fp-photo-name')), 'Meter photo');
    await tap(t, find.byKey(const Key('fp-upload')));
    expect(find.byKey(const Key('fp-photo-error')), findsOneWidget);
    c.failUpload = false;
    await tap(t, find.byKey(const Key('fp-upload')));
    expect(c.uploads, 2);
    expect(c.uploadKeys.first, c.uploadKeys.last);
    expect(t.takeException(), isNull);
    await close(t);
  });
  testWidgets(
    'checklist saves only acknowledged changes and closeout is explicit',
    (t) async {
      final c = FakeFieldProof();
      await show(t, c);
      await open(t);
      await tap(t, find.byKey(const Key('fp-tab-2')));
      expect(
        t.widget<FilledButton>(find.byKey(const Key('fp-close'))).onPressed,
        isNull,
      );
      c.failSave = true;
      await tap(t, find.text('Work documented'));
      expect(c.row['job']['data']['checks'][0]['done'], false);
      c.failSave = false;
      await tap(t, find.text('Work documented'));
      expect(c.row['job']['data']['checks'][0]['done'], true);
      c.row['readiness'] = {
        'ready': true,
        'missing': [],
        'label': 'Required records present',
      };
      await tap(t, find.byTooltip('Refresh FieldProof'));
      await tap(t, find.byKey(const Key('fp-close')));
      expect(c.row['job']['state'], 'active');
      await tap(t, find.text('Confirm'));
      expect(c.row['job']['state'], 'completed');
      await close(t);
    },
  );
  testWidgets(
    'AI consent blocks dispatch and running reviews resume without duplication',
    (t) async {
      final c = FakeFieldProof();
      await show(t, c, consent: () async => false);
      await open(t);
      await tap(t, find.byKey(const Key('fp-tab-3')));
      await tap(t, find.byKey(const Key('fp-review')));
      expect(c.starts, 0);
      await close(t);
      final resumed = FakeFieldProof();
      resumed.row['reviews'] = [
        {'id': 'review-1', 'state': 'running', 'version': 3},
      ];
      await show(t, resumed);
      await open(t);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(resumed.starts, 0);
      expect(resumed.gets, greaterThan(1));
      await close(t);
    },
  );
  testWidgets('account loss closes upload dialog and clears private job', (
    t,
  ) async {
    final c = FakeFieldProof();
    await show(t, c);
    await open(t);
    await tap(t, find.byKey(const Key('fp-tab-1')));
    await tap(t, find.byKey(const Key('fp-add-photo')));
    c.onAccessDenied!();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('fp-pick-file')), findsNothing);
    expect(find.text('Meter installation'), findsNothing);
    await close(t);
  });
  testWidgets('PDF export uses fresh authenticated previews before saving', (
    t,
  ) async {
    final c = FakeFieldProof();
    var exports = 0;
    await show(
      t,
      c,
      saver: (b, n, m) async {
        expect(n, endsWith('.pdf'));
        expect(m, 'application/pdf');
        exports++;
      },
      render: (s, p) async {
        expect(s['job']['version'], 3);
        expect(p.keys, ['photo-1']);
        return Uint8List.fromList([37, 80, 68, 70]);
      },
    );
    await open(t);
    await tap(t, find.byKey(const Key('fp-tab-3')));
    await tap(t, find.byKey(const Key('fp-export')));
    expect(exports, 1);
    expect(c.downloads, [true]);
    expect(c.gets, greaterThan(1));
    await close(t);
  });
  testWidgets('delete is confirmed before removing job', (t) async {
    final c = FakeFieldProof();
    await show(t, c);
    await open(t);
    await tap(t, find.text('Delete job and photos'));
    expect(c.deletes, 0);
    await tap(t, find.text('Cancel'));
    expect(c.deletes, 0);
    await tap(t, find.text('Delete job and photos'));
    await tap(t, find.text('Confirm'));
    expect(c.deletes, 1);
    await close(t);
  });
  testWidgets('phone and desktop layouts support enlarged text', (t) async {
    for (final width in [390.0, 1440.0]) {
      final c = FakeFieldProof();
      await show(t, c, width: width, scale: 1.25);
      await open(t);
      for (final tab in [0, 1, 2, 3]) {
        await tap(t, find.byKey(Key('fp-tab-$tab')));
        expect(t.takeException(), isNull);
      }
      await close(t);
    }
  });
  test(
    'PDF export contains embedded photo previews and refuses missing evidence',
    () async {
      final s = snapshot();
      await expectLater(buildFieldProofPdf(s, {}), throwsA(isA<StateError>()));
      final bytes = await buildFieldProofPdf(s, {'photo-1': photo});
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      final out = Platform.environment['FIELDPROOF_PDF_OUTPUT'];
      if (out != null) await File(out).writeAsBytes(bytes);
    },
  );
  testWidgets('optional actual-screen captures', (t) async {
    final dir = Platform.environment['FIELDPROOF_CAPTURE_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      final regular = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'));
      await regular.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '${Platform.environment['KORLIX_FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    });
    for (final width in [390.0, 1440.0]) {
      final c = FakeFieldProof();
      await show(t, c, width: width);
      await open(t);
      await tap(t, find.byKey(const Key('fp-tab-2')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/fieldproof-${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      await close(t);
    }
  });
}

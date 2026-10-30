import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/improve_picture/picture_studio_client.dart';
import 'package:ai_wiz_command_center/improve_picture/picture_studio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'picture_studio_test.dart' as pictures;
import 'social_replies_test.dart' as actions;
import 'social_test.dart' as social;

const _receipt = 'korlix_report_20000000-0000-4000-8000-000000000002';

String _auth(String user) =>
    'Bearer x.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'iss': 'https://fixture.test', 'session_id': 'session-$user'}))).replaceAll('=', '')}.x';

class _Studio {
  String token = _auth('alice');
  final reports = <Map<String, dynamic>>[];
  int generated = 0;
  Completer<void>? reportSent;
  late final client = PictureStudioClient(
    backendBaseUrl: 'https://fixture.test',
    headersBuilder: () async => {'Authorization': token},
    client: MockClient((request) async {
      expect(request.headers['Authorization'], token);
      if (request.url.path == '/api/report-output') {
        expect(request.method, 'POST');
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        reportSent?.complete();
        return http.Response('{"ok":true,"reportId":"$_receipt"}', 202);
      }
      expect(request.url.path, '/api/image/improve');
      generated++;
      final bytes = await pictures.png(
        generated == 1 ? Colors.green : Colors.blue,
      );
      return http.Response(
        jsonEncode({
          'imageDataUrl': 'data:image/png;base64,${base64Encode(bytes)}',
          'generationId': 'edit-$generated',
          'editSummary': 'Edited version $generated',
        }),
        200,
      );
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a prior edit keeps its report payload and rejects an account change',
    () async {
      final s = _Studio();
      addTearDown(s.client.dispose);
      final source = await pictures.photo();
      final older = await s.client.improve(
        source,
        const PictureEditOptions(prompt: 'The older green garden'),
      );
      await s.client.improve(
        source,
        const PictureEditOptions(prompt: 'A newer blue sky'),
      );
      expect(
        await older.submitReport!('Privacy concern', 'Review the older edit.'),
        _receipt,
      );
      final report = s.reports.single;
      expect(report['contentId'], 'edit-1');
      expect(report['prompt'], 'The older green garden');
      expect(report['outputSummary'], contains('Edited version 1'));
      expect(report['contentType'], 'image');
      expect(report['appArea'], 'picture_studio');
      expect(report['imageDataUrl'], startsWith('data:image/png;base64,'));
      s.token = _auth('bob');
      await expectLater(
        older.submitReport!('Privacy concern', ''),
        throwsException,
      );
      expect(s.reports, hasLength(1));
      expect(older.isReportCurrent!(), isFalse);
    },
  );

  testWidgets(
    'selected older picture reports in app, cancel sends nothing, and receipt appears',
    (t) async {
      final s = _Studio();
      addTearDown(s.client.dispose);
      await social.mount(
        t,
        PictureStudioScreen(
          initialFile: await pictures.photo(),
          onImprove: s.client.improve,
          ensureConsent: () async => true,
          onOpenTemplates: () {},
        ),
        width: 390,
        height: 1000,
      );
      await t.enterText(find.byType(TextField), 'The older green garden');
      await actions.tap(t, find.byKey(const Key('improve-picture-submit')));
      await actions.tap(t, find.text('Refine this image'));
      await t.enterText(find.byType(TextField), 'A newer blue sky');
      await actions.tap(t, find.byKey(const Key('improve-picture-submit')));
      await actions.tap(t, find.byKey(const Key('picture-version-1')));
      await actions.tap(t, find.text('Before'));
      expect(find.byKey(const Key('picture-report-result')), findsNothing);
      await actions.tap(t, find.text('After'));
      final preview = t.widget<Image>(
        find.byKey(const Key('picture-preview-image')),
      );
      expect(
        ((preview.image as ResizeImage).imageProvider as MemoryImage).bytes,
        await pictures.png(Colors.green),
      );
      await actions.tap(t, find.byKey(const Key('picture-report-result')));
      expect(find.textContaining('shared with KORLIX support'), findsOneWidget);
      await actions.tap(t, find.text('Cancel'));
      expect(s.reports, isEmpty);
      await actions.tap(t, find.byKey(const Key('picture-report-result')));
      await actions.tap(t, find.byKey(const Key('saved-report-reason')));
      await actions.tap(t, find.text('Privacy concern').last);
      await t.enterText(
        find.byKey(const Key('saved-report-details')),
        'Review the older edit.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      final submit = find.byKey(const Key('saved-report-submit'));
      await t.ensureVisible(submit);
      await t.runAsync(() async {
        s.reportSent = Completer<void>();
        await t.tap(submit);
        await s.reportSent!.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
      });
      await t.pumpAndSettle();
      expect(s.reports, hasLength(1));
      expect(s.reports.single['contentId'], 'edit-1');
      expect(s.reports.single['prompt'], 'The older green garden');
      expect(s.reports.single['details'], 'Review the older edit.');
      await t.runAsync(() async {
        final encoded = s.reports.single['imageDataUrl'] as String;
        final reported = await decodeImageFromList(
          base64Decode(encoded.substring(encoded.indexOf(',') + 1)),
        );
        final expected = await decodeImageFromList(
          await pictures.png(Colors.green),
        );
        expect(
          (await reported.toByteData())!.buffer.asUint8List(),
          (await expected.toByteData())!.buffer.asUint8List(),
        );
        reported.dispose();
        expected.dispose();
      });
      expect(find.text('Report received'), findsOneWidget);
      expect(find.textContaining(_receipt), findsOneWidget);
      await actions.tap(t, find.text('Done'));
      expect(find.byKey(const Key('picture-report-result')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}

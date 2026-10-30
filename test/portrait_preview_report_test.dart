import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/auth/korlix_http.dart' as transport;
import 'package:ai_wiz_command_center/improve_picture/models/template_model.dart';
import 'package:ai_wiz_command_center/improve_picture/screens/preview_screen.dart';
import 'package:ai_wiz_command_center/privacy/korlix_third_party_ai_consent.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reportId = 'korlix_report_20000000-0000-4000-8000-000000000001';
final _original = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAE0lEQVQYlWNQnPb5Pz7MMDIUAABwQapBFKvYYAAAAABJRU5ErkJggg==',
);
final _generated = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAEklEQVQYlWPwWR/wHx9mGBkKAFgtkoF0aEUHAAAAAElFTkSuQmCC',
);

String _token(String user) =>
    'Bearer x.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'iss': 'https://fixture.test', 'session_id': 'session-$user'}))).replaceAll('=', '')}.x';

class _PreviewFixture {
  String token = _token('alice');
  bool failRefresh = false;
  bool failHeaders = false;
  bool validReceipt = true;
  final prompts = <String>[];
  final reports = <Map<String, dynamic>>[];
  Completer<void>? sent;
  Completer<void>? checked;
  Completer<void>? generationResponse;

  Future<Map<String, String>> headers() async {
    if (failHeaders) {
      throw StateError('Authentication callback failed.');
    }
    if (checked != null && !checked!.isCompleted) {
      checked!.complete();
    }
    return {'Authorization': token};
  }

  http.Client client() => MockClient((request) async {
    expect(request.headers['Authorization'], token);
    if (request.url.path == '/api/report-output') {
      reports.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (sent != null && !sent!.isCompleted) {
        sent!.complete();
      }
      return http.Response(
        validReceipt
            ? jsonEncode({'ok': true, 'reportId': _reportId})
            : '{"ok":true}',
        202,
      );
    }
    expect(request.url.path, '/api/image/improve');
    final multipart = utf8.decode(request.bodyBytes, allowMalformed: true);
    prompts.add(
      RegExp(
        r'name="prompt"\r\n\r\n([\s\S]*?)\r\n--',
      ).firstMatch(multipart)!.group(1)!,
    );
    if (generationResponse != null && !generationResponse!.isCompleted) {
      generationResponse!.complete();
    }
    return failRefresh
        ? http.Response('Temporary preview failure', 500)
        : http.Response(
            jsonEncode({
              'imageDataUrl':
                  'data:image/png;base64,${base64Encode(_generated)}',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, _PreviewFixture fixture) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  transport.configureClientFactory(fixture.client);
  await tester.runAsync(() async {
    fixture.generationResponse = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewScreen(
          gender: ImproveGender.female,
          template: kImprovePictureTemplates.first,
          variation: 'Soft Cartoon',
          hasUploadedPhoto: true,
          bestResults: true,
          identityLock: true,
          uploadedFile: PlatformFile(
            name: 'original.png',
            size: _original.length,
            bytes: _original,
          ),
          previewHeadersBuilder: fixture.headers,
        ),
      ),
    );
    await fixture.generationResponse!.future.timeout(
      const Duration(seconds: 5),
    );
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('portrait-preview-report')), findsOneWidget);
}

Future<void> _openReport(WidgetTester tester) async {
  await _tap(tester, find.byKey(const Key('portrait-preview-report')));
  await _tap(tester, find.byKey(const Key('saved-report-reason')));
  await _tap(tester, find.text('Privacy concern').last);
  await tester.enterText(
    find.byKey(const Key('saved-report-details')),
    'Please review this generated portrait.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, _PreviewFixture fixture) async {
  final submit = find.byKey(const Key('saved-report-submit'));
  await tester.ensureVisible(submit);
  // The completer must belong to the real async zone used by image encoding.
  await tester.runAsync(() async {
    fixture.sent = Completer<void>();
    await tester.tap(submit);
    await fixture.sent!.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    const account = 'portrait-preview-report-test';
    SharedPreferences.setMockInitialValues({
      KorlixThirdPartyAiConsent.accountStorageKey(account): jsonEncode({
        'version': KorlixThirdPartyAiConsent.consentNoticeVersion,
        'grants': ['openAi:imagesAndPhotos', 'openAi:typedTextAndPrompts'],
      }),
    });
    KorlixThirdPartyAiConsent.setAccountScope(account);
  });
  tearDown(() {
    transport.configureClientFactory(null);
    KorlixThirdPartyAiConsent.setAccountScope(null);
  });

  testWidgets('canceling a portrait preview report sends nothing', (
    tester,
  ) async {
    final fixture = _PreviewFixture();
    await _mount(tester, fixture);
    await _openReport(tester);
    expect(find.textContaining('shared with KORLIX support'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect(fixture.reports, isEmpty);
    expect(find.text('Template Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'portrait report retains displayed preview and its original prompt',
    (tester) async {
      final fixture = _PreviewFixture();
      await _mount(tester, fixture);
      final originalPrompt = fixture.prompts.single;
      fixture.failRefresh = true;
      await tester.ensureVisible(find.text('1:1'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        fixture.generationResponse = Completer<void>();
        await tester.tap(find.text('1:1'));
        await fixture.generationResponse!.future.timeout(
          const Duration(seconds: 5),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(fixture.prompts, hasLength(2));
      expect(fixture.prompts.last, isNot(originalPrompt));
      await _openReport(tester);
      await _submit(tester, fixture);
      final report = fixture.reports.single;
      expect(report['contentType'], 'image');
      expect(report['appArea'], 'portrait_studio_preview');
      expect(report['contentId'], startsWith('portrait-preview-'));
      expect(report['prompt'], originalPrompt);
      expect(report['reason'], 'Privacy concern');
      expect(report['details'], 'Please review this generated portrait.');
      final encoded = report['imageDataUrl'] as String;
      expect(encoded, startsWith('data:image/png;base64,'));
      // Decode the prepared report preview and compare pixels, not PNG metadata.
      await tester.runAsync(() async {
        final reported = await decodeImageFromList(
          base64Decode(encoded.substring(encoded.indexOf(',') + 1)),
        );
        final expected = await decodeImageFromList(_generated);
        final ByteData? reportedPixels = await reported.toByteData();
        final ByteData? expectedPixels = await expected.toByteData();
        expect(
          reportedPixels!.buffer.asUint8List(),
          expectedPixels!.buffer.asUint8List(),
        );
        reported.dispose();
        expected.dispose();
      });
      expect(find.text('Report received'), findsOneWidget);
      expect(find.textContaining(_reportId), findsOneWidget);
      await _tap(tester, find.text('Done'));
      expect(find.text('Template Preview'), findsOneWidget);
      expect(fixture.reports, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('portrait report rejects an account switch before transport', (
    tester,
  ) async {
    final fixture = _PreviewFixture();
    await _mount(tester, fixture);
    await _openReport(tester);
    fixture.token = _token('bob');
    final submit = find.byKey(const Key('saved-report-submit'));
    await tester.ensureVisible(submit);
    await tester.runAsync(() async {
      fixture.checked = Completer<void>();
      await tester.tap(submit);
      await fixture.checked!.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(fixture.reports, isEmpty);
    expect(find.byKey(const Key('saved-report-feedback')), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.text('Report received'), findsNothing);
    await _tap(tester, find.text('Close'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait report requires a valid server receipt', (
    tester,
  ) async {
    final fixture = _PreviewFixture()..validReceipt = false;
    await _mount(tester, fixture);
    await _openReport(tester);
    await _submit(tester, fixture);
    expect(fixture.reports, hasLength(1));
    expect(find.text('Report received'), findsNothing);
    expect(find.byKey(const Key('saved-report-feedback')), findsOneWidget);
    await _tap(tester, find.text('Close'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an auth callback failure while opening a portrait report is safe',
    (tester) async {
      final fixture = _PreviewFixture();
      await _mount(tester, fixture);
      fixture.failHeaders = true;
      await _tap(tester, find.byKey(const Key('portrait-preview-report')));
      expect(fixture.reports, isEmpty);
      expect(find.byKey(const Key('saved-report-reason')), findsNothing);
      expect(find.text('Report received'), findsNothing);
      expect(
        find.text(
          'We could not verify your sign-in. Reopen the preview after signing in.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Authentication callback failed'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('portrait-preview-report')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

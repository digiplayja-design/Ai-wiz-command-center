import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:ai_wiz_command_center/auth/korlix_http.dart' as transport;
import 'package:ai_wiz_command_center/image_to_video/image_to_video_screen.dart';
import 'picture_studio_session_test.dart' as identity;
import 'social_discover_test.dart' show FakeVideo;
import 'social_test.dart' as fixtures;

class PhotoPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([identity.photo()]);
}

class VideoFixture {
  final revision = ValueNotifier(0);
  String token = identity.token();
  int reportStatus = 202;
  String reportBody =
      '{"ok":true,"reportId":"korlix_report_23a1fa12-e789-4f38-bc1c-701df956d510"}';
  final reports = <Map<String, dynamic>>[];
  Completer<http.Response>? generation;
  static const url = 'https://cdn.example.test/generated-video.mp4';
  http.Response output() =>
      http.Response(jsonEncode({'jobId': 'video-123', 'videoUrl': url}), 200);
  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final picker = FilePicker.platform;
    final player = VideoPlayerPlatform.instance;
    FilePicker.platform = PhotoPicker();
    final fakeVideo = FakeVideo();
    VideoPlayerPlatform.instance = fakeVideo;
    transport.configureClientFactory(
      () => MockClient((request) async {
        if (request.url.path == '/api/report-output') {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(reportBody, reportStatus);
        }
        if (request.url.path == '/api/video/image-to-video')
          return generation?.future ?? output();
        throw StateError('Unexpected test request: ${request.url.path}');
      }),
    );
    await fixtures.mount(
      tester,
      KorlixImageToVideoScreen(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer $token'},
        sessionChanges: revision,
      ),
      width: 390,
      height: 844,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      transport.configureClientFactory(null);
      FilePicker.platform = picker;
      VideoPlayerPlatform.instance = player;
      revision.dispose();
    });
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(10000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate Image to Video'));
    await tester.tap(find.text('Generate Image to Video'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Allow & Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    if (generation == null) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpAndSettle();
    }
  }

  Future<void> report(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('image-to-video-report')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('image-to-video-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-to-video-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsafe or harmful').last);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() => FilePicker.platform = PhotoPicker());
  testWidgets(
    'generated video has an in-app report with exact video and prompt context',
    (tester) async {
      final f = VideoFixture();
      await f.open(tester);
      expect(find.byKey(const Key('image-to-video-report')), findsOneWidget);
      // Editing the next prompt must not alter the context of this generated clip.
      await tester.scrollUntilVisible(
        find.byKey(const Key('image-to-video-motion-prompt')),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('image-to-video-motion-prompt')),
        'A different next prompt',
      );
      await f.report(tester);
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(f.reports, hasLength(1));
      expect(f.reports.single['videoUrl'], VideoFixture.url);
      expect(f.reports.single['videoId'], 'video-123');
      expect(f.reports.single['contentType'], 'video');
      expect(f.reports.single['appArea'], 'image_to_video');
      expect(f.reports.single['prompt'], contains('Animate this still image'));
      expect(find.textContaining('Report received.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed report stays in-app and does not show false confirmation',
    (tester) async {
      final f = VideoFixture()
        ..reportStatus = 503
        ..reportBody = '{}';
      await f.open(tester);
      await f.report(tester);
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reporting is temporarily unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('Report received.'), findsNothing);
      expect(f.reports, hasLength(1));
    },
  );
  testWidgets(
    'account change invalidates report and removes private generated video',
    (tester) async {
      final f = VideoFixture();
      await f.open(tester);
      await f.report(tester);
      f.token = identity.token(user: 'other');
      f.revision.value++;
      await tester.pumpAndSettle();
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit report'),
      );
      expect(submit.onPressed, isNull);
      expect(f.reports, isEmpty);
      expect(find.byKey(const Key('image-to-video-report')), findsNothing);
    },
  );
  testWidgets(
    'late generation after account switch never displays another account video',
    (tester) async {
      final f = VideoFixture()..generation = Completer<http.Response>();
      await f.open(tester);
      f.token = identity.token(user: 'other');
      f.revision.value++;
      f.generation!.complete(f.output());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-to-video-report')), findsNothing);
      expect(find.text('Session changed.'), findsOneWidget);
    },
  );
}

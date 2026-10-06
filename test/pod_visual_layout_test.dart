import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_wiz_command_center/pod/pod_client.dart';
import 'package:ai_wiz_command_center/pod/pod_media.dart';
import 'package:ai_wiz_command_center/pod/pod_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  'trending',
  'politics',
  'sports',
  'religion',
  'culture',
  'business',
  'technology',
];

/// Only setup is exercised here. No credentials, provider calls or audio device
/// are used by the responsive checks or optional review screenshots.
class _SetupClient extends PodClient {
  _SetupClient()
    : super(backendBaseUrl: 'https://pod.invalid', headersBuilder: () => {});

  Map<String, Object>? submitted;
  final pendingCreation = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> load() async => {
    'catalog': [],
    'access': {
      'allowed': true,
      'smallTalk': true,
      'durations': [300, 600, 900],
      'maxSeconds': 900,
    },
    'episodes': [],
  };

  @override
  Future<Map<String, dynamic>> create({
    required String requestId,
    required String category,
    required String topic,
    required int durationSeconds,
    required int hostCount,
    required String style,
  }) {
    submitted = {
      'category': category,
      'topic': topic,
      'durationSeconds': durationSeconds,
      'hostCount': hostCount,
      'style': style,
    };
    return pendingCreation.future;
  }
}

class _SilentMedia extends PodMedia {
  int activations = 0;

  @override
  bool get blocked => false;
  @override
  bool get playing => false;
  @override
  bool get recording => false;
  @override
  bool get recordingAvailable => false;
  @override
  Duration get elapsed => Duration.zero;
  @override
  String? get error => null;
  @override
  Future<void> activate() async {
    activations++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancelRecording() async {}
  @override
  Future<void> play(Uint8List wav, {VoidCallback? onStarted}) async =>
      throw StateError('Setup must not play audio.');
  @override
  Future<void> startRecording() async =>
      throw StateError('Setup must not open a microphone.');
  @override
  Future<Uint8List> stopRecording() async =>
      throw StateError('Setup has no microphone recording.');
}

Future<void> _mount(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  double textScale = 1,
  GlobalKey? boundary,
  _SetupClient? client,
  _SilentMedia? media,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: boundary,
            child: PodScreen(
              client: client ?? _SetupClient(),
              media: media ?? _SilentMedia(),
              ensureConsent: () async => true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  expect(control, findsOneWidget, reason: 'Missing setup control: $key');
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget, reason: 'Unreachable: $key');
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

Future<void> _loadReviewFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (sdk == null) {
      throw StateError(
        'Set KORLIX_FLUTTER_ROOT when capturing Pod screenshots.',
      );
    }
    Future<ByteData> font(String path) async =>
        ByteData.sublistView(await File(path).readAsBytes());
    await (FontLoader('Roboto')
          ..addFont(font('assets/fieldproof/Roboto-Regular.ttf'))
          ..addFont(font('assets/fieldproof/Roboto-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          font(
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ))
        .load();
  });
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String output,
  String name,
) async {
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1.5);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  testWidgets(
    'Pod setup fits phone and iPad with large text and either theme',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final width in [375.0, 768.0, 1024.0]) {
          for (final scale in [1.0, 1.4]) {
            final description = '$brightness, width $width, text scale $scale';
            final client = _SetupClient();
            final media = _SilentMedia();
            await _mount(
              tester,
              size: Size(width, width == 375 ? 812 : 1366),
              brightness: brightness,
              textScale: scale,
              client: client,
              media: media,
            );
            expect(tester.takeException(), isNull, reason: description);
            for (final key in [
              for (final category in _categories) 'pod-category-$category',
              'pod-topic',
              for (final seconds in [300, 600, 900]) 'pod-duration-$seconds',
              for (final hosts in [2, 3]) 'pod-hosts-$hosts',
              for (final style in ['balanced', 'relaxed', 'debate'])
                'pod-style-$style',
              'pod-listen',
            ]) {
              await _reveal(tester, key);
              expect(
                tester.takeException(),
                isNull,
                reason: '$description: $key',
              );
            }
            expect(client.submitted, isNull);
            expect(media.activations, 0);
            await _unmount(tester);
          }
        }
      }
    },
  );

  testWidgets('visual setup choices still reach the episode creation request', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _SetupClient();
    final media = _SilentMedia();
    await _mount(
      tester,
      size: const Size(375, 812),
      brightness: Brightness.light,
      textScale: 1.4,
      client: client,
      media: media,
    );
    for (final category in _categories) {
      await _tap(tester, 'pod-category-$category');
    }
    await _tap(tester, 'pod-category-sports');
    for (final seconds in [300, 600, 900]) {
      await _tap(tester, 'pod-duration-$seconds');
    }
    for (final count in [2, 3]) {
      await _tap(tester, 'pod-hosts-$count');
    }
    for (final style in ['balanced', 'relaxed', 'debate']) {
      await _tap(tester, 'pod-style-$style');
    }
    await _reveal(tester, 'pod-topic');
    await tester.enterText(
      find.byKey(const Key('pod-topic')),
      'What makes a team perform well under pressure?',
    );
    // Let EditableText finish revealing its new caret before scrolling to the
    // next control; otherwise its deferred scroll overrides ensureVisible.
    await tester.pumpAndSettle();
    await _tap(tester, 'pod-listen');
    expect(client.submitted, {
      'category': 'sports',
      'topic': 'What makes a team perform well under pressure?',
      'durationSeconds': 900,
      'hostCount': 3,
      'style': 'debate',
    });
    expect(media.activations, 1);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  final output = Platform.environment['POD_CAPTURE_DIR'];
  testWidgets(
    'capture rendered Pod setup for visual review',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _loadReviewFonts(tester);
      for (final review in [
        ('ipad-dark', const Size(1024, 1366), Brightness.dark),
        ('ipad-light-parent', const Size(1024, 1366), Brightness.light),
        ('phone', const Size(375, 812), Brightness.dark),
        ('ipad-full', const Size(1024, 2500), Brightness.dark),
      ]) {
        final boundary = GlobalKey();
        await _mount(
          tester,
          size: review.$2,
          brightness: review.$3,
          boundary: boundary,
        );
        expect(tester.takeException(), isNull, reason: review.$1);
        await _capture(tester, boundary, output!, '${review.$1}-top');
        if (review.$1 != 'ipad-full') {
          await _reveal(tester, 'pod-listen');
          await _capture(tester, boundary, output, '${review.$1}-setup');
        }
        expect(tester.takeException(), isNull, reason: review.$1);
        await _unmount(tester);
      }
    },
    skip: output == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

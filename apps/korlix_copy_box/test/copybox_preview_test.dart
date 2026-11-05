// Store captures render the shipping widgets with sample content. They do not
// synthesize device hardware, an operating-system status bar, or AI responses.
// Run only with COPYBOX_PREVIEWS and KORLIX_FLUTTER_ROOT set; the output PNGs
// are converted to store-required opaque RGB by build_store_assets.py.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:korlix_auth_core/auth/korlix_token_store.dart';
import 'package:korlix_copy_box/copybox_auth.dart';
import 'package:korlix_copy_box/copybox_home.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:korlix_copy_box/copybox_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previewKey = Key('store-preview');
const _profiles = [
  (
    name: 'play-phone',
    size: Size(360, 640),
    pixelRatio: 3.0,
    platform: TargetPlatform.android,
  ),
  (
    name: 'apple-iphone',
    size: Size(420, 912),
    pixelRatio: 3.0,
    platform: TargetPlatform.iOS,
  ),
  (
    name: 'apple-ipad',
    size: Size(1032, 1376),
    pixelRatio: 2.0,
    platform: TargetPlatform.iOS,
  ),
];

List<CopyBoxEntry> _sampleBoxes() => [
  CopyBoxEntry(
    id: 'intro',
    title: 'Start a conversation',
    folder: 'Business',
    favorite: true,
    text:
        'Hi {{name}},\n\nThanks for connecting today. I’d love to hear more '
        'about your next project.\n\nWhen would be a good time to talk?',
    color: 0,
  ),
  CopyBoxEntry(
    id: 'idea',
    title: 'Keep this thought',
    folder: 'Ideas',
    text:
        'Make useful things. Keep them simple. Give people a reason to come back.',
    color: 1,
  ),
  CopyBoxEntry(
    id: 'followup',
    title: 'A thoughtful follow-up',
    folder: 'Business',
    text:
        'Thank you for your time today. Here is a quick recap of our next steps:\n\n'
        '• Confirm the project scope.\n'
        '• Share the first draft.\n'
        '• Set a time to review it together.',
    color: 2,
  ),
];

Future<void> _loadFonts(WidgetTester tester) async {
  final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
  if (sdk == null || sdk.isEmpty) {
    throw StateError('KORLIX_FLUTTER_ROOT is required for store captures.');
  }
  await tester.runAsync(() async {
    for (final entry in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('Ahem', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(
            File('$sdk/bin/cache/artifacts/material_fonts/${entry.$2}')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
  bool dark = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final prefs = await SharedPreferences.getInstance();
  await CopyBoxStore(prefs, 'local').save(_sampleBoxes());
  final client = MockClient((_) async {
    throw StateError('Store captures must not make network requests.');
  });
  final auth = CopyBoxAuthController(
    client: client,
    tokenStore: KorlixTokenStore(
      useSecureStorage: false,
      namespace: 'korlix_copybox_store_preview',
    ),
  );
  addTearDown(() {
    auth.dispose();
    client.close();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _previewKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: copyboxTheme(
          dark ? Brightness.dark : Brightness.light,
        ).copyWith(platform: platform),
        home: CopyBoxHome(
          prefs: prefs,
          auth: auth,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          onThemeChanged: (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/copybox_mark.png'),
      tester.element(find.byType(MaterialApp)),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _navigate(WidgetTester tester, String label) async {
  final mobile = find.widgetWithText(NavigationDestination, label);
  await tester.tap(
    mobile.evaluate().isNotEmpty
        ? mobile
        : find.widgetWithText(ListTile, label),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _showWritingCards(WidgetTester tester, Size size) async {
  // The first phone capture shows the saved writing itself. Tablet captures
  // have enough room to retain the workspace heading and organization tools.
  if (size.width < 1000) {
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('box-panel-intro'))),
      alignment: .06,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _capture(
  WidgetTester tester,
  String filename,
  Size size,
  double pixelRatio,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: filename);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    expect(image.width, (size.width * pixelRatio).round());
    expect(image.height, (size.height * pixelRatio).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final target = Directory(Platform.environment['COPYBOX_PREVIEWS']!);
    await target.create(recursive: true);
    await File('${target.path}/$filename.png').writeAsBytes(
      bytes!.buffer.asUint8List(),
    );
    image.dispose();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
            'appName': 'KORLIX COPY Box',
            'packageName': 'com.korlixdeveloper.copybox',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );
  });

  for (final profile in _profiles) {
    testWidgets(
      '${profile.name} store screenshots',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _loadFonts(tester);
        await _mount(tester, size: profile.size, platform: profile.platform);
        await _showWritingCards(tester, profile.size);
        await _capture(
          tester,
          'store-${profile.name}-01-workspace',
          profile.size,
          profile.pixelRatio,
        );

        await _navigate(tester, 'Templates');
        await _capture(
          tester,
          'store-${profile.name}-02-templates',
          profile.size,
          profile.pixelRatio,
        );

        await _navigate(tester, 'Workspace');
        await tester.ensureVisible(find.byTooltip('Box options').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Box options').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Focus editor'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('focus-text')), findsOneWidget);
        await _capture(
          tester,
          'store-${profile.name}-03-focus-editor',
          profile.size,
          profile.pixelRatio,
        );

        await _mount(
          tester,
          size: profile.size,
          platform: profile.platform,
          dark: true,
        );
        await _showWritingCards(tester, profile.size);
        await _capture(
          tester,
          'store-${profile.name}-04-dark-workspace',
          profile.size,
          profile.pixelRatio,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      skip: Platform.environment['COPYBOX_PREVIEWS'] == null,
    );
  }
}

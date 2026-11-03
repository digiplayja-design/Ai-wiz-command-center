import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:korlix_auth_core/auth/korlix_token_store.dart';
import 'package:korlix_copy_box/copybox_auth.dart';
import 'package:korlix_copy_box/copybox_card.dart';
import 'package:korlix_copy_box/copybox_home.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:korlix_copy_box/copybox_theme.dart';

void main() {
  String clipboard = '';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
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
  Future<SharedPreferences> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
    List<CopyBoxEntry>? seed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final prefs = await SharedPreferences.getInstance();
    if (seed != null) {
      final store = CopyBoxStore(prefs, 'local');
      store.load();
      await store.save(seed);
    }
    final client = MockClient((_) async => http.Response('{}', 200));
    final auth = CopyBoxAuthController(
      client: client,
      tokenStore: KorlixTokenStore(
        useSecureStorage: false,
        namespace: 'korlix_copybox',
      ),
    );
    addTearDown(() {
      auth.dispose();
      client.close();
    });
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (Platform.environment['COPYBOX_PREVIEWS'] != null && sdk != null) {
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
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: copyboxTheme(dark ? Brightness.dark : Brightness.light),
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
    return prefs;
  }

  Future<void> click(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    final target = Platform.environment['COPYBOX_PREVIEWS'];
    if (target == null) return;
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(target).create(recursive: true);
      await File('$target/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'independent stacked editors autosave and Copy All includes every box',
    (tester) async {
      final prefs = await mount(
        tester,
        seed: [
          CopyBoxEntry(id: 'one', title: 'First'),
          CopyBoxEntry(id: 'two', title: 'Second'),
        ],
      );
      await tester.enterText(
        find.byKey(const ValueKey('text-one')),
        'First message',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.byKey(const ValueKey('text-two')),
        'Second message',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final stored = CopyBoxStore(prefs, 'local').load();
      expect(stored.map((b) => b.text), ['First message', 'Second message']);
      await click(tester, find.byKey(const Key('copy-all')));
      expect(clipboard, 'First message\n\nSecond message');
      await tester.enterText(find.byKey(const Key('search-boxes')), 'First');
      await tester.pumpAndSettle();
      expect(find.byType(CopyBoxCard), findsOneWidget);
      await click(tester, find.byKey(const Key('copy-all')));
      expect(clipboard, 'First message\n\nSecond message');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Add Box appends and focus editor saves a recoverable version', (
    tester,
  ) async {
    final prefs = await mount(
      tester,
      seed: [CopyBoxEntry(id: 'one', title: 'First', text: 'Original')],
    );
    await click(tester, find.byKey(const Key('add-box')));
    expect(find.byType(CopyBoxCard), findsNWidgets(2));
    final boxes = CopyBoxStore(prefs, 'local').load();
    expect(boxes.first.id, 'one');
    expect(boxes.last.text, '');
    await click(tester, find.byTooltip('Box options').first);
    await tester.tap(find.text('Focus editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('focus-text')),
      'Improved original',
    );
    await click(tester, find.text('Save & close'));
    final updated = CopyBoxStore(prefs, 'local').load().first;
    expect(updated.text, 'Improved original');
    expect(updated.history.first, 'Original');
    expect(tester.takeException(), isNull);
  });
  testWidgets('trash is recoverable and template fill preserves original', (
    tester,
  ) async {
    final prefs = await mount(
      tester,
      seed: [
        CopyBoxEntry(id: 'one', title: 'Template', text: 'Hello {{name}}'),
      ],
    );
    await click(tester, find.byTooltip('Box options').first);
    await tester.tap(find.text('Fill template fields'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'name'),
      'Ricardo',
    );
    await click(tester, find.text('Copy finished text'));
    expect(clipboard, 'Hello Ricardo');
    expect(CopyBoxStore(prefs, 'local').load().first.text, 'Hello {{name}}');
    await click(tester, find.byTooltip('Box options').first);
    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();
    expect(CopyBoxStore(prefs, 'local').load().first.trashed, isTrue);
    await click(tester, find.text('Undo'));
    expect(CopyBoxStore(prefs, 'local').load().first.trashed, isFalse);
  });
  testWidgets(
    'narrow large-text layout and all navigation destinations remain usable',
    (tester) async {
      await mount(
        tester,
        size: const Size(360, 800),
        scale: 1.8,
        seed: [
          CopyBoxEntry(
            id: 'one',
            title: 'A longer title for accessibility',
            text: 'Saved thoughts',
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      for (final label in ['Templates', 'Backup', 'Settings', 'Workspace']) {
        await click(tester, find.widgetWithText(NavigationDestination, label));
        expect(tester.takeException(), isNull, reason: label);
      }
      expect(find.byKey(const Key('copybox-outer-scrollbar')), findsOneWidget);
    },
  );
  testWidgets('corrupt saved data never gets overwritten by the workspace', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = CopyBoxStore(prefs, 'local').key;
    await prefs.setString(key, '{corrupt');
    await mount(tester);
    expect(find.text('Your saved data is protected'), findsOneWidget);
    expect(find.byKey(const Key('add-box')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(prefs.getString(key), '{corrupt');
  });
  testWidgets('mobile workspace and template previews', (tester) async {
    await mount(
      tester,
      seed: [
        CopyBoxEntry(
          id: 'intro',
          title: 'A conversation worth starting',
          folder: 'Business',
          favorite: true,
          text: 'Hi {{name}},\n\nGreat ideas deserve a little momentum. Let’s find a time to explore what we can create together.',
          color: 0,
        ),
        CopyBoxEntry(
          id: 'idea',
          title: 'Keep this thought',
          folder: 'Ideas',
          text: 'Make useful things. Keep them simple. Give people a reason to come back.',
          color: 1,
        ),
        CopyBoxEntry(
          id: 'followup',
          title: 'The thoughtful follow-up',
          folder: 'Business',
          text: 'Thank you for your time today. Here’s a quick recap of our next steps…',
          color: 2,
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'copybox-workspace');
    await click(
      tester,
      find.widgetWithText(NavigationDestination, 'Templates'),
    );
    await screenshot(tester, 'copybox-templates');
  });
  testWidgets('desktop and dark appearance previews', (tester) async {
    await mount(
      tester,
      size: const Size(1280, 900),
      dark: true,
      seed: [
        CopyBoxEntry(
          id: 'one',
          title: 'Your next bright idea',
          folder: 'Ideas',
          favorite: true,
          text: 'A place to collect the words you want to keep.\nBuild on a thought, turn it into a template, and make it your own.',
          color: 1,
        ),
        CopyBoxEntry(
          id: 'two',
          title: 'Ready when you need it',
          folder: 'Business',
          text:
              'Hi {{name}}, thanks for reaching out. Here’s what happens next.',
          color: 0,
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'copybox-desktop-dark');
  });
}

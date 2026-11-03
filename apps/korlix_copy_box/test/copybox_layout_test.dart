import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:korlix_copy_box/copybox_auth.dart';
import 'package:korlix_copy_box/copybox_dialogs.dart';
import 'package:korlix_copy_box/copybox_home.dart';
import 'package:korlix_copy_box/copybox_store.dart';
import 'package:korlix_copy_box/copybox_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
  theme: copyboxTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: home,
);

Future<void> _openHome(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await CopyBoxStore(prefs, 'local').save([
    CopyBoxEntry(title: 'A saved idea', text: 'Ready to reuse.'),
  ]);
  final client = MockClient((_) async {
    throw StateError('Offline layout tests must not make network requests.');
  });
  final auth = CopyBoxAuthController(client: client);
  addTearDown(() {
    auth.dispose();
    client.close();
  });
  await tester.pumpWidget(
    _app(
      CopyBoxHome(
        prefs: prefs,
        auth: auth,
        themeMode: ThemeMode.light,
        onThemeChanged: (_) async {},
      ),
    ),
  );
  await tester.pump();
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

  testWidgets('focus editor fits a small phone with large text and keyboard', (
    tester,
  ) async {
    _viewport(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final title = List.filled(25, 'Project ').join().trim();
    await tester.pumpWidget(
      _app(
        CopyBoxFocusEditor(title: title, text: 'Original draft'),
        textScale: 2,
      ),
    );
    await tester.pump();

    expect(tester.widget<Text>(find.text(title)).maxLines, 2);
    expect(find.bySemanticsLabel(title), findsOneWidget);
    expect(find.byKey(const Key('focus-editor-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('focus-text')),
      'The keyboard leaves this draft editable.',
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(const Key('focus-text'))).controller!.text,
      'The keyboard leaves this draft editable.',
    );
    expect(find.text('Save & close').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short wide windows use navigation that fits their height', (
    tester,
  ) async {
    _viewport(tester, const Size(1024, 400));
    await _openHome(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('YOUR SPACE'), findsNothing);
    expect(find.byKey(const Key('copybox-outer-scrollbar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('wide tablet switches away from the rail when keyboard reduces height', (
    tester,
  ) async {
    _viewport(tester, const Size(1024, 800));
    await _openHome(tester);
    expect(find.text('YOUR SPACE'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    tester.view.viewInsets = const FakeViewPadding(bottom: 440);
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('YOUR SPACE'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

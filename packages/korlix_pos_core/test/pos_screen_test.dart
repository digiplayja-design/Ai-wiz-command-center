import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_pos_core/korlix_pos_core.dart';

void main() {
  for (final size in [
    const Size(1440, 960),
    const Size(1024, 768),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('register renders at ${size.width} x ${size.height}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = PosWorkspace(save: (_) async {});
      await tester.pumpWidget(
        MaterialApp(
          theme: posTheme(),
          home: PosScreen(workspace: w),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('KORLIX POS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('retail checkout creates receipt and appears in history', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = PosWorkspace(save: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: posTheme(),
        home: PosScreen(workspace: w),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyday tote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice cash checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete practice sale'));
    await tester.pumpAndSettle();
    expect(find.text('Practice sale saved'), findsOneWidget);
    expect(w.orders.single.status, 'paid');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('KX-1001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('restaurant modifiers and kitchen ticket flow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = PosWorkspace(save: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: posTheme(),
        home: PosScreen(workspace: w),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('House burger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add cheese'));
    await tester.tap(find.text('Add to order'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send to kitchen · pay later'));
    await tester.tap(find.text('Send to kitchen · pay later'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').first);
    await tester.pumpAndSettle();
    expect(find.text('1 × House burger'), findsOneWidget);
    expect(find.text('Add cheese'), findsOneWidget);
    await tester.tap(find.text('Start preparing'));
    await tester.pumpAndSettle();
    expect(find.text('Mark ready'), findsOneWidget);
    expect(w.orders.single.status, 'unpaid');
    expect(tester.takeException(), isNull);
  });
  testWidgets('embedded view closes on account session change', (tester) async {
    final session = ValueNotifier(0);
    final w = PosWorkspace(save: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: PosScreen(workspace: w, embedded: true, sessionChanges: session),
      ),
    );
    await tester.pumpAndSettle();
    session.value = 1;
    await tester.pumpAndSettle();
    expect(
      find.text('Your KORLIX session changed. Close and reopen POS.'),
      findsOneWidget,
    );
  });
  testWidgets('all workspaces remain usable on a phone with larger text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = PosWorkspace(save: (_) async {});
    await w.switchMode('restaurant');
    await w.add('f1', ['Add cheese']);
    await w.sendToKitchen();
    await tester.pumpWidget(
      MaterialApp(
        theme: posTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.25)),
          child: child!,
        ),
        home: PosScreen(workspace: w),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['Orders', 'Kitchen', 'Inventory', 'Reports']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
  });
}

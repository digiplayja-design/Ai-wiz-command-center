import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/billing/korlix_fixed_plan_bar.dart';

void main() {
  testWidgets('plan action remains visible after scrolling, including large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(body: Column(children: [
        KorlixFixedPlanBar(tier: 'basic', onOpenPlans: () => opened++, actions: [
          for (var i = 0; i < 4; i++) IconButton(onPressed: () {}, icon: const Icon(Icons.person)),
        ]),
        Expanded(child: ListView(children: const [SizedBox(height: 1800), Text('Last item')])),
      ])),
    )));
    final button = find.byKey(const Key('fixed-plan-button'));
    final before = tester.getRect(button);
    expect(before.height, greaterThanOrEqualTo(48));
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.getRect(button), before);
    await tester.tap(button);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tier loading, paid accounts and opening state have appropriate actions', (tester) async {
    for (final item in <(String?, bool, String)>[
      (null, false, 'View Plans'), ('basic', false, 'Upgrade'),
      ('pro', false, 'Upgrade'), ('ultra', false, 'My Plan'),
      ('enterprise', false, 'My Plan'), ('basic', true, 'My Plan'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: KorlixFixedPlanBar(
        tier: item.$1, developer: item.$2, onOpenPlans: () {},
      ))));
      expect(find.text(item.$3), findsOneWidget);
    }
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: KorlixFixedPlanBar(
      tier: 'basic', busy: true, onOpenPlans: () => opened++,
    ))));
    await tester.tap(find.byKey(const Key('fixed-plan-button')));
    expect(opened, 0);
    expect(find.text('Opening…'), findsOneWidget);
  });

  testWidgets('public overview leads to free registration without a purchase', (tester) async {
    bool? create;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async => create = await showKorlixPublicPlans(context),
        child: const Text('View Plans')),
    ))));
    await tester.tap(find.text('View Plans'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Basic · Free'), findsOneWidget);
    await tester.tap(find.text('Create free account'));
    await tester.pumpAndSettle();
    expect(create, true);
  });
}

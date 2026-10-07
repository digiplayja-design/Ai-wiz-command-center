import 'package:ai_wiz_command_center/sharing/korlix_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native exports always have an anchor in the current iPad view', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final logicalSize in [
      const Size(768, 1024),
      const Size(1024, 768),
      const Size(320, 768),
    ]) {
      tester.view.physicalSize = logicalSize * 2;
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final origin = korlixShareOrigin();
      expect(origin.isEmpty, isFalse);
      expect(origin.isFinite, isTrue);
      expect(origin.center, (Offset.zero & logicalSize).center);
      expect((Offset.zero & logicalSize).contains(origin.topLeft), isTrue);
      expect((Offset.zero & logicalSize).contains(origin.bottomRight), isTrue);
    }
  });

  testWidgets('share anchors to a visible control and clips outside edges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BuildContext? control;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: -20,
                top: 100,
                width: 100,
                height: 48,
                child: Builder(
                  builder: (context) {
                    control = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(korlixShareOrigin(control), const Rect.fromLTWH(0, 100, 80, 48));

    // Sharing can finish preparing a file after its originating route closes.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(control!.mounted, isFalse);
    expect(korlixShareOrigin(control), const Rect.fromLTWH(399.5, 299.5, 1, 1));
  });
}

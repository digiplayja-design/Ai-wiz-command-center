import 'package:esha_by_korlix/ui/account.dart';
import 'package:esha_by_korlix/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  testWidgets('native screens fit 320px width and 1.7 text scaling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await guestController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: eshaTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: EshaHome(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['Ask Esha', 'Try a Look', 'My Vanity', 'Discover']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label initial layout');
      final scroller = find
          .descendant(
            of: find.byType(IndexedStack),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(scroller, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label scrolled layout');
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: eshaTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: MembershipScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: eshaTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: AccountScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

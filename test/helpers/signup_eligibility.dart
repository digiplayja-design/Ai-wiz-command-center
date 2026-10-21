import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> selectSignupAge(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byKey(const Key('signup-age-range')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signup-age-range')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> acceptAdultSignup(WidgetTester tester) async {
  final plan = find.byKey(const Key('signup-plan-basic'));
  if (plan.evaluate().isNotEmpty) {
    await tester.ensureVisible(plan);
    await tester.pumpAndSettle();
    await tester.tap(plan);
    await tester.pumpAndSettle();
  }
  await selectSignupAge(tester, '18 or older');
  final checkbox = find.byKey(const Key('signup-policy-acceptance'));
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

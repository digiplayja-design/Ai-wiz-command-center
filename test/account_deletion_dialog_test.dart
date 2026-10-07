import 'dart:async';

import 'package:ai_wiz_command_center/account/korlix_account_deletion_dialog.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixture {
  final revision = ValueNotifier(0);
  final links = <Uri>[];
  int submissions = 0;
  bool? recorded;
  Completer<void>? pending;
  bool linkOpens = true;

  Future<void> open(
    WidgetTester tester, {
    bool apple = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: korlixBuildTheme('korlix_blue'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                recorded = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => KorlixAccountDeletionDialog(
                    sessionChanges: revision,
                    isSessionCurrent: () => revision.value == 0,
                    showAppleSubscriptions: apple,
                    submitRequest: () async {
                      submissions++;
                      await pending?.future;
                    },
                    openLink: (uri) async {
                      links.add(uri);
                      return linkOpens;
                    },
                  ),
                );
              },
              child: const Text('Open deletion dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open deletion dialog'));
    await tester.pumpAndSettle();
  }
}

void main() {
  late _Fixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture = _Fixture();
  });
  tearDown(() => fixture.revision.dispose());

  testWidgets('explains the request and exposes policy without submitting', (
    tester,
  ) async {
    await fixture.open(tester);
    expect(find.textContaining('does not immediately delete'), findsOneWidget);
    expect(find.textContaining('Export any records'), findsOneWidget);
    expect(
      find.textContaining('does not automatically cancel'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('account-deletion-apple-subscriptions')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('account-deletion-policy')));
    await tester.pumpAndSettle();
    expect(
      fixture.links.single.toString(),
      'https://www.korlixdeveloper.com/delete-account.html',
    );
    expect(fixture.submissions, 0);
  });

  testWidgets(
    'Apple subscription management opens directly without submitting',
    (tester) async {
      await fixture.open(tester, apple: true);
      final link = find.byKey(
        const Key('account-deletion-apple-subscriptions'),
      );
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        fixture.links.single.toString(),
        'https://apps.apple.com/account/subscriptions',
      );
      expect(fixture.submissions, 0);
    },
  );

  testWidgets('repeated activation sends one request and shows pending state', (
    tester,
  ) async {
    fixture.pending = Completer<void>();
    await fixture.open(tester);
    final submit = tester
        .widget<FilledButton>(find.byKey(const Key('account-deletion-submit')))
        .onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(fixture.submissions, 1);
    expect(find.text('Sending request…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('account-deletion-submit')),
          )
          .onPressed,
      isNull,
    );
    fixture.pending!.complete();
    await tester.pumpAndSettle();
    expect(fixture.recorded, isTrue);
  });

  testWidgets('changing accounts before confirmation disables the old dialog', (
    tester,
  ) async {
    await fixture.open(tester);
    fixture.revision.value++;
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('account-deletion-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    expect(fixture.submissions, 0);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(fixture.recorded, isFalse);
  });

  testWidgets('a late response cannot report success for a different account', (
    tester,
  ) async {
    fixture.pending = Completer<void>();
    await fixture.open(tester);
    await tester.tap(find.byKey(const Key('account-deletion-submit')));
    await tester.pump();
    fixture.revision.value++;
    fixture.pending!.complete();
    await tester.pumpAndSettle();
    expect(fixture.recorded, isNot(isTrue));
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(fixture.recorded, isFalse);
  });

  testWidgets(
    'timeout is recoverable and late success does not close the dialog',
    (tester) async {
      fixture.pending = Completer<void>();
      await fixture.open(tester);
      await tester.tap(find.byKey(const Key('account-deletion-submit')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('could not confirm whether'), findsOneWidget);
      expect(fixture.recorded, isNot(isTrue));
      fixture.pending!.complete();
      await tester.pumpAndSettle();
      expect(fixture.recorded, isNot(isTrue));
      expect(find.byType(KorlixAccountDeletionDialog), findsOneWidget);
    },
  );

  testWidgets('failed policy link leaves an accessible error and no request', (
    tester,
  ) async {
    fixture.linkOpens = false;
    await fixture.open(tester);
    await tester.tap(find.byKey(const Key('account-deletion-policy')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open this page. Please try again.'),
      findsOneWidget,
    );
    expect(fixture.submissions, 0);
  });

  testWidgets(
    'small screens with large text retain scrollable content and actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await fixture.open(tester, apple: true, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const Key('account-deletion-submit')),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.submissions, 0);
    },
  );
}

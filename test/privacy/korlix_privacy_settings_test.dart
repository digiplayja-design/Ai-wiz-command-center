import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/privacy/korlix_privacy_settings.dart';
import 'package:ai_wiz_command_center/privacy/korlix_third_party_ai_consent.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const resetKey = Key('privacy-reset-choices');
const confirmKey = Key('privacy-reset-confirm');

class _Fixture {
  final revision = ValueNotifier(0);
  final links = <Uri>[];
  bool opens = true;
  late BuildContext context;

  Future<void> mount(
    WidgetTester tester, {
    Future<void> Function()? reset,
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
          builder: (value) {
            context = value;
            return KorlixPrivacySettings(
              sessionChanges: revision,
              isSessionCurrent: () => revision.value == 0,
              resetChoices: reset,
              openLink: (uri) async {
                links.add(uri);
                return opens;
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> beginReset(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byKey(resetKey), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(resetKey));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(confirmKey));
    await tester.tap(find.byKey(confirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  late _Fixture f;
  late String account;
  var sequence = 0;
  setUp(() {
    account = 'privacy-account-${++sequence}';
    SharedPreferences.setMockInitialValues({});
    KorlixThirdPartyAiConsent.setAccountScope(account);
    f = _Fixture();
  });
  tearDown(() {
    KorlixThirdPartyAiConsent.setAccountScope(null);
    f.revision.dispose();
  });

  testWidgets(
    'public policies open canonical URLs and remain accessible after sign-out',
    (tester) async {
      await f.mount(tester);
      f.revision.value++;
      await tester.pumpAndSettle();
      for (final file in [
        'legal.html',
        'privacy-policy.html',
        'terms.html',
        'subscription-terms.html',
        'delete-account.html',
      ]) {
        final link = find.byKey(ValueKey('privacy-link-$file'));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(f.links.last, Uri.https('www.korlixdeveloper.com', '/$file'));
      }
      await tester.ensureVisible(find.byKey(resetKey));
      expect(
        tester.widget<OutlinedButton>(find.byKey(resetKey)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('failed link gives the exact address without blocking reset', (
    tester,
  ) async {
    f.opens = false;
    await f.mount(tester);
    await tester.tap(find.byKey(const ValueKey('privacy-link-legal.html')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('https://www.korlixdeveloper.com/legal.html'),
      findsOneWidget,
    );
    await f.beginReset(tester);
    expect(find.byKey(confirmKey), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'cancel preserves grants; reset affects one account and next request asks again',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final key = KorlixThirdPartyAiConsent.accountStorageKey(account);
      final otherKey = KorlixThirdPartyAiConsent.accountStorageKey(
        'other-$account',
      );
      final grant = jsonEncode({
        'version': KorlixThirdPartyAiConsent.consentNoticeVersion,
        'grants': ['openAi:typedTextAndPrompts'],
      });
      await prefs.setString(key, grant);
      await prefs.setString(otherKey, grant);
      await f.mount(tester);
      await f.beginReset(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(prefs.getString(key), grant);
      await f.beginReset(tester);
      await f.confirm(tester);
      await tester.pumpAndSettle();
      expect(prefs.getString(key), isNull);
      expect(prefs.getString(otherKey), grant);
      final next = KorlixThirdPartyAiConsent.ensure(
        context: f.context,
        featureName: 'test request',
        providers: {KorlixThirdPartyAiProvider.openAi},
        dataCategories: {KorlixThirdPartyAiDataCategory.typedTextAndPrompts},
      );
      await tester.pumpAndSettle();
      expect(find.text('Share data with AI providers?'), findsOneWidget);
      await tester.tap(find.text("Don't Allow"));
      await tester.pumpAndSettle();
      expect(await next, isFalse);
    },
  );

  testWidgets('account switch while confirming cannot reset the new account', (
    tester,
  ) async {
    var resets = 0;
    await f.mount(
      tester,
      reset: () async {
        resets++;
      },
    );
    await f.beginReset(tester);
    KorlixThirdPartyAiConsent.setAccountScope('different-$account');
    f.revision.value++;
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);
  });

  testWidgets(
    'pending reset disables duplicates and suppresses old-account success after switch',
    (tester) async {
      final pending = Completer<void>();
      var resets = 0;
      await f.mount(
        tester,
        reset: () {
          resets++;
          return pending.future;
        },
      );
      await f.beginReset(tester);
      await f.confirm(tester);
      expect(
        tester.widget<OutlinedButton>(find.byKey(resetKey)).onPressed,
        isNull,
      );
      f.revision.value++;
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(
        find.textContaining('AI-sharing choices reset for this account'),
        findsNothing,
      );
      expect(find.textContaining('Your sign-in changed.'), findsOneWidget);
    },
  );

  testWidgets('failed reset is not reported successful and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    await f.mount(
      tester,
      reset: () async {
        if (++attempts == 1) throw StateError('unavailable');
      },
    );
    await f.beginReset(tester);
    await f.confirm(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save the reset.'), findsOneWidget);
    expect(
      find.textContaining('AI-sharing choices reset for this account'),
      findsNothing,
    );
    await f.beginReset(tester);
    await f.confirm(tester);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.textContaining('AI-sharing choices reset for this account'),
      findsOneWidget,
    );
  });

  testWidgets(
    'narrow phone with enlarged text keeps reset and confirmation reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await f.mount(tester, textScale: 2);
      await f.beginReset(tester);
      await tester.ensureVisible(find.byKey(confirmKey));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

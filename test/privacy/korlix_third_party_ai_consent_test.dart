import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Exercise real preference-cache behavior when the platform write fails.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:ai_wiz_command_center/privacy/korlix_third_party_ai_consent.dart';

const openAi = KorlixThirdPartyAiProvider.openAi;
const kling = KorlixThirdPartyAiProvider.klingAi;
const textData = KorlixThirdPartyAiDataCategory.typedTextAndPrompts;
const imageData = KorlixThirdPartyAiDataCategory.imagesAndPhotos;
final dialog = find.byKey(
  const ValueKey('korlix-third-party-ai-consent-dialog'),
);

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();
  bool failWrites = false, failRemoves = false;
  Completer<void>? writeGate;
  int writes = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    await writeGate?.future;
    if (failWrites) return false;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async =>
      failRemoves ? false : super.remove(key);
}

Future<BuildContext> mount(WidgetTester tester) async {
  late BuildContext requestContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          requestContext = context;
          return const Scaffold(body: Text('AI workspace'));
        },
      ),
    ),
  );
  return requestContext;
}

Future<bool> request(
  BuildContext context, {
  Set<KorlixThirdPartyAiProvider> providers = const {openAi},
  Set<KorlixThirdPartyAiDataCategory> categories = const {textData},
}) => ensureKorlixThirdPartyAiConsent(
  context: context,
  featureName: 'AI workspace',
  providers: providers,
  dataCategories: categories,
);

Future<void> choose(WidgetTester tester, bool allowed) async {
  await tester.pumpAndSettle();
  expect(dialog, findsOneWidget);
  await tester.tap(find.text(allowed ? 'Allow & Continue' : "Don't Allow"));
  await tester.pumpAndSettle();
}

Future<void> grant(
  WidgetTester tester,
  BuildContext context, {
  Set<KorlixThirdPartyAiProvider> providers = const {openAi},
  Set<KorlixThirdPartyAiDataCategory> categories = const {textData},
}) async {
  final pending = request(
    context,
    providers: providers,
    categories: categories,
  );
  await choose(tester, true);
  expect(await pending, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var accountSequence = 0;
  late String account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    account = 'issuer/account-${++accountSequence}';
    KorlixThirdPartyAiConsent.setAccountScope(account);
  });
  tearDown(() => KorlixThirdPartyAiConsent.setAccountScope(null));

  testWidgets('declining blocks the request and does not persist consent', (
    tester,
  ) async {
    final context = await mount(tester);
    final pending = request(context, categories: {textData, imageData});
    await tester.pumpAndSettle();
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Typed text and prompts'), findsOneWidget);
    expect(find.text('Images and photos'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    await choose(tester, false);
    expect(await pending, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  testWidgets('accepting persists exact pairs for only the current account', (
    tester,
  ) async {
    final context = await mount(tester);
    await grant(tester, context, categories: {textData, imageData});
    final prefs = await SharedPreferences.getInstance();
    final record = jsonDecode(
      prefs.getString(KorlixThirdPartyAiConsent.accountStorageKey(account))!,
    );
    expect(record['version'], KorlixThirdPartyAiConsent.consentNoticeVersion);
    expect(record['grants'], [
      'openAi:imagesAndPhotos',
      'openAi:typedTextAndPrompts',
    ]);
    expect(prefs.getKeys(), {
      KorlixThirdPartyAiConsent.accountStorageKey(account),
    });
    expect(await request(context, categories: {imageData}), isTrue);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets(
    'new requests disclose their own scope without widening old grants',
    (tester) async {
      final context = await mount(tester);
      await grant(tester, context);
      final pending = request(
        context,
        providers: {kling},
        categories: {imageData},
      );
      await tester.pumpAndSettle();
      expect(find.text('Kling AI'), findsOneWidget);
      expect(find.text('Images and photos'), findsOneWidget);
      expect(find.text('OpenAI'), findsNothing);
      expect(find.text('Typed text and prompts'), findsNothing);
      await choose(tester, false);
      expect(await pending, isFalse);
      expect(await request(context), isTrue);
    },
  );

  testWidgets(
    'independent provider/category grants never form a cross product',
    (tester) async {
      final context = await mount(tester);
      await grant(tester, context);
      await grant(tester, context, providers: {kling}, categories: {imageData});
      expect(await request(context), isTrue);
      expect(
        await request(context, providers: {kling}, categories: {imageData}),
        isTrue,
      );
      for (final scope in [(openAi, imageData), (kling, textData)]) {
        final pending = request(
          context,
          providers: {scope.$1},
          categories: {scope.$2},
        );
        await choose(tester, false);
        expect(await pending, isFalse);
      }
    },
  );

  testWidgets('accounts on a shared device cannot reuse each other consent', (
    tester,
  ) async {
    final context = await mount(tester);
    await grant(tester, context);
    KorlixThirdPartyAiConsent.setAccountScope('second-account');
    final other = request(context);
    await choose(tester, false);
    expect(await other, isFalse);
    await grant(tester, context, providers: {kling}, categories: {imageData});
    KorlixThirdPartyAiConsent.setAccountScope(account);
    expect(await request(context), isTrue);
    final missing = request(
      context,
      providers: {kling},
      categories: {imageData},
    );
    await choose(tester, false);
    expect(await missing, isFalse);
  });

  testWidgets('legacy global records are not accepted or migrated', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      KorlixThirdPartyAiConsent.consentVersionKey:
          KorlixThirdPartyAiConsent.consentNoticeVersion,
      KorlixThirdPartyAiConsent.providersKey: ['openAi', 'klingAi'],
      KorlixThirdPartyAiConsent.dataCategoriesKey: [
        'typedTextAndPrompts',
        'imagesAndPhotos',
      ],
    });
    final context = await mount(tester);
    final pending = request(context);
    await choose(tester, false);
    expect(await pending, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(KorlixThirdPartyAiConsent.accountStorageKey(account)),
      isNull,
    );
  });

  testWidgets(
    'session switch dismisses pending consent and cancels its request',
    (tester) async {
      final context = await mount(tester);
      final pending = request(context);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      KorlixThirdPartyAiConsent.setAccountScope('new-account');
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(await pending, isFalse);
      expect(find.text('AI workspace'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  testWidgets(
    'revoking dismisses consent and removes only this account grants',
    (tester) async {
      final context = await mount(tester);
      await grant(tester, context);
      KorlixThirdPartyAiConsent.setAccountScope('retained-account');
      await grant(tester, context);
      KorlixThirdPartyAiConsent.setAccountScope(account);
      final pending = request(context, categories: {imageData});
      await tester.pumpAndSettle();
      final revoking = KorlixThirdPartyAiConsent.revoke();
      await tester.pumpAndSettle();
      await revoking;
      expect(await pending, isFalse);
      expect(dialog, findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(KorlixThirdPartyAiConsent.accountStorageKey(account)),
        isFalse,
      );
      KorlixThirdPartyAiConsent.setAccountScope('retained-account');
      expect(await request(context), isTrue);
    },
  );

  testWidgets(
    'simultaneous identical requests share one prompt and atomic record',
    (tester) async {
      final context = await mount(tester);
      final first = request(context), second = request(context);
      await choose(tester, true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(dialog, findsNothing);
      expect((await SharedPreferences.getInstance()).getKeys(), hasLength(1));
    },
  );

  testWidgets('unknown account consent is one request and never reusable', (
    tester,
  ) async {
    KorlixThirdPartyAiConsent.setAccountScope(null);
    final context = await mount(tester);
    await grant(tester, context);
    final again = request(context);
    await choose(tester, false);
    expect(await again, isFalse);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  testWidgets(
    'failed preference writes cannot grant from the optimistic cache',
    (tester) async {
      final store = _ControlledPreferences()..failWrites = true;
      SharedPreferencesStorePlatform.instance = store;
      final context = await mount(tester);
      final first = request(context);
      await choose(tester, true);
      expect(await first, isFalse);
      final second = request(context);
      await choose(tester, false);
      expect(await second, isFalse);
      expect(store.writes, 1);
    },
  );

  testWidgets(
    'account change during persistence cannot continue the old request',
    (tester) async {
      final store = _ControlledPreferences()..writeGate = Completer<void>();
      SharedPreferencesStorePlatform.instance = store;
      final context = await mount(tester);
      final pending = request(context);
      await choose(tester, true);
      expect(store.writes, 1);
      KorlixThirdPartyAiConsent.setAccountScope('account-after-write-start');
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
      final next = request(context);
      await choose(tester, false);
      expect(await next, isFalse);
    },
  );

  testWidgets(
    'failed revoke remains revoked after preferences reload in this session',
    (tester) async {
      final store = _ControlledPreferences();
      SharedPreferencesStorePlatform.instance = store;
      final context = await mount(tester);
      await grant(tester, context);
      store.failRemoves = true;
      await expectLater(KorlixThirdPartyAiConsent.revoke(), throwsStateError);
      await (await SharedPreferences.getInstance()).reload();
      final pending = request(context);
      await choose(tester, false);
      expect(await pending, isFalse);
    },
  );

  testWidgets('changed notices and malformed records require consent again', (
    tester,
  ) async {
    final context = await mount(tester);
    final prefs = await SharedPreferences.getInstance();
    for (final value in [
      '{invalid-json',
      jsonEncode({
        'version': 'old-notice',
        'grants': ['openAi:typedTextAndPrompts'],
      }),
      jsonEncode({
        'version': KorlixThirdPartyAiConsent.consentNoticeVersion,
        'grants': ['openAi:typedTextAndPrompts', 2],
      }),
    ]) {
      await prefs.setString(
        KorlixThirdPartyAiConsent.accountStorageKey(account),
        value,
      );
      final pending = request(context);
      await choose(tester, false);
      expect(await pending, isFalse);
    }
  });

  testWidgets(
    'disposed caller and empty scopes never continue or open consent',
    (tester) async {
      final context = await mount(tester);
      expect(await request(context, providers: {}), isFalse);
      expect(await request(context, categories: {}), isFalse);
      await grant(tester, context);
      await tester.pumpWidget(const SizedBox());
      expect(await request(context), isFalse);
      expect(dialog, findsNothing);
    },
  );
}

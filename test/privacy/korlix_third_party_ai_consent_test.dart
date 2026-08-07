import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_wiz_command_center/privacy/korlix_third_party_ai_consent.dart';

Widget _consentTestHost({
  required Future<bool> Function(BuildContext context) request,
  required ValueChanged<bool> onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () async {
                onResult(await request(context));
              },
              child: const Text('Start request'),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('declining blocks the request and does not persist consent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    bool? result;

    await tester.pumpWidget(
      _consentTestHost(
        request: (context) {
          return ensureKorlixThirdPartyAiConsent(
            context: context,
            featureName: 'Improve Picture',
            providers: const <KorlixThirdPartyAiProvider>{
              KorlixThirdPartyAiProvider.openAi,
            },
            dataCategories: const <KorlixThirdPartyAiDataCategory>{
              KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
              KorlixThirdPartyAiDataCategory.imagesAndPhotos,
            },
          );
        },
        onResult: (value) {
          result = value;
        },
      ),
    );

    await tester.tap(find.text('Start request'));

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('korlix-third-party-ai-consent-dialog'),
      ),
      findsOneWidget,
    );

    expect(find.text('OpenAI'), findsOneWidget);

    expect(find.text('Typed text and prompts'), findsOneWidget);

    expect(find.text('Images and photos'), findsOneWidget);

    expect(find.text('Privacy Policy'), findsOneWidget);

    await tester.tap(find.text("Don't Allow"));

    await tester.pumpAndSettle();

    expect(result, isFalse);

    final preferences = await SharedPreferences.getInstance();

    expect(
      preferences.getString(KorlixThirdPartyAiConsent.consentVersionKey),
      isNull,
    );
  });

  testWidgets('accepting persists the exact provider and data scope', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    bool? result;

    Future<bool> request(BuildContext context) {
      return ensureKorlixThirdPartyAiConsent(
        context: context,
        featureName: 'LIVE CONVO',
        providers: const <KorlixThirdPartyAiProvider>{
          KorlixThirdPartyAiProvider.openAi,
        },
        dataCategories: const <KorlixThirdPartyAiDataCategory>{
          KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
          KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
        },
      );
    }

    await tester.pumpWidget(
      _consentTestHost(
        request: request,
        onResult: (value) {
          result = value;
        },
      ),
    );

    await tester.tap(find.text('Start request'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Allow & Continue'));

    await tester.pumpAndSettle();

    expect(result, isTrue);

    final preferences = await SharedPreferences.getInstance();

    expect(
      preferences.getString(KorlixThirdPartyAiConsent.consentVersionKey),
      KorlixThirdPartyAiConsent.consentNoticeVersion,
    );

    expect(
      preferences.getStringList(KorlixThirdPartyAiConsent.providersKey),
      contains(KorlixThirdPartyAiProvider.openAi.name),
    );

    expect(
      preferences.getStringList(KorlixThirdPartyAiConsent.dataCategoriesKey),
      containsAll(<String>[
        KorlixThirdPartyAiDataCategory.typedTextAndPrompts.name,
        KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts.name,
      ]),
    );

    result = null;

    await tester.pumpWidget(
      _consentTestHost(
        request: request,
        onResult: (value) {
          result = value;
        },
      ),
    );

    await tester.tap(find.text('Start request'));

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('korlix-third-party-ai-consent-dialog'),
      ),
      findsNothing,
    );

    expect(result, isTrue);
  });

  testWidgets(
    'a newly requested provider or data category requires consent again',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        KorlixThirdPartyAiConsent.consentVersionKey:
            KorlixThirdPartyAiConsent.consentNoticeVersion,
        KorlixThirdPartyAiConsent.providersKey: <String>[
          KorlixThirdPartyAiProvider.openAi.name,
        ],
        KorlixThirdPartyAiConsent.dataCategoriesKey: <String>[
          KorlixThirdPartyAiDataCategory.typedTextAndPrompts.name,
        ],
      });

      bool? result;

      await tester.pumpWidget(
        _consentTestHost(
          request: (context) {
            return ensureKorlixThirdPartyAiConsent(
              context: context,
              featureName: 'Create Video',
              providers: const <KorlixThirdPartyAiProvider>{
                KorlixThirdPartyAiProvider.klingAi,
              },
              dataCategories: const <KorlixThirdPartyAiDataCategory>{
                KorlixThirdPartyAiDataCategory.imagesAndPhotos,
              },
            );
          },
          onResult: (value) {
            result = value;
          },
        ),
      );

      await tester.tap(find.text('Start request'));

      await tester.pumpAndSettle();

      expect(find.text('Kling AI'), findsOneWidget);

      expect(find.text('Images and photos'), findsOneWidget);

      await tester.tap(find.text("Don't Allow"));

      await tester.pumpAndSettle();

      expect(result, isFalse);
    },
  );
}

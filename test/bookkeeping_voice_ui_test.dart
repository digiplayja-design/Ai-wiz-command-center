import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_forms.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/privacy/korlix_third_party_ai_consent.dart';
import 'bookkeeping_test.dart' as f;

const accounts = <Map<String, dynamic>>[
  {'code': '1000', 'name': 'Operating checking'},
];
Map<String, dynamic> draft() => {
  'business_id': f.businessId,
  'kind': 'income',
  'amount': '25.50',
  'entry_date': '2027-01-23',
  'category': '4000',
  'cash_account': '1000',
  'counterparty': 'Bayside Studio',
  'purpose': 'Design consultation paid',
  'receipt_reference': 'INV-1002',
};
Map<String, dynamic> overview() => {...f.overview(), 'cash_accounts': accounts};

String value(WidgetTester t, String label) =>
    t.widget<TextField>(f.field(label)).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'existing general voice consent does not authorize bookkeeping records',
    (t) async {
      SharedPreferences.setMockInitialValues({
        KorlixThirdPartyAiConsent.consentVersionKey:
            KorlixThirdPartyAiConsent.consentNoticeVersion,
        KorlixThirdPartyAiConsent.providersKey: [
          KorlixThirdPartyAiProvider.openAi.name,
        ],
        KorlixThirdPartyAiConsent.dataCategoriesKey: [
          KorlixThirdPartyAiDataCategory.typedTextAndPrompts.name,
          KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts.name,
        ],
      });
      bool? allowed;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  allowed = await ensureKorlixThirdPartyAiConsent(
                    context: context,
                    featureName: 'Bookkeeping and K-Nova',
                    providers: const {KorlixThirdPartyAiProvider.openAi},
                    dataCategories: const {
                      KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
                      KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
                      KorlixThirdPartyAiDataCategory.bookkeepingRecords,
                    },
                  );
                },
                child: const Text('Start voice'),
              ),
            ),
          ),
        ),
      );
      await f.tap(t, 'Start voice');
      expect(
        find.text('Selected business bookkeeping records'),
        findsOneWidget,
      );
      await f.tap(t, "Don't Allow");
      expect(allowed, isFalse);
    },
  );

  testWidgets(
    'voice hands off one business and reviewed draft saves only after confirmation',
    (t) async {
      await f.size(t, const Size(390, 1100));
      final result = Completer<Map<String, dynamic>?>();
      final writes = <Map<String, dynamic>>[], months = <String>[];
      List<String>? opened;
      final client = f.client((r) {
        if (r.method == 'POST') {
          writes.add(Map<String, dynamic>.from(jsonDecode(r.body)));
          return f.reply({'entry': f.savedEntry()}, 201);
        }
        if (r.url.path.endsWith('/overview')) {
          months.add(r.url.queryParameters['month']!);
          return f.reply(overview());
        }
        return f.reply({
          'businesses': [f.business()],
        });
      });
      addTearDown(client.dispose);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: BookkeepingScreen(
            client: client,
            openVoice: (id, name, month) {
              opened = [id, name, month];
              return result.future;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final initialMonth = months.single;
      await f.tap(t, 'Talk to K-Nova');
      expect(opened, [f.businessId, 'Harbor Creative LLC', initialMonth]);
      expect(writes, isEmpty);
      expect(t.takeException(), isNull);
      result.complete(draft());
      await t.pumpAndSettle();
      expect(
        months.length,
        2,
        reason: 'Current catalogs are refreshed after voice closes.',
      );
      expect(find.byType(BookkeepingEntryDialog), findsOneWidget);
      expect(value(t, 'Amount (USD)'), '25.50');
      expect(value(t, 'Date received / paid'), '2027-01-23');
      expect(value(t, 'Business purpose'), 'Design consultation paid');
      expect(writes, isEmpty);
      await f.tap(t, 'Review entry');
      expect(writes, isEmpty);
      await f.tap(t, 'Confirm and save');
      expect(writes, hasLength(1));
      expect(writes.single, containsPair('amount', '25.50'));
      expect(writes.single, containsPair('entry_date', '2027-01-23'));
      expect(writes.single, containsPair('cash_account', '1000'));
      expect(writes.single, containsPair('confirmed', true));
      expect(months.last, '2027-01');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'missing voice fields do not silently become today or default accounts',
    (t) async {
      await f.size(t, const Size(390, 1100));
      var writes = 0;
      final client = f.client((r) {
        if (r.method == 'POST') writes++;
        return f.reply({});
      });
      addTearDown(client.dispose);
      await f.mountDialog(
        t,
        BookkeepingEntryDialog(
          client: client,
          businessId: f.businessId,
          categories: f.categories(),
          cashAccounts: accounts,
          kind: 'income',
          initialDraft: {
            'amount': '25.50',
            'purpose': 'Design consultation paid',
            'category': 'removed-category',
            'cash_account': 'removed-account',
          },
        ),
      );
      expect(value(t, 'Date received / paid'), isEmpty);
      final dropdowns = t
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(dropdowns.map((d) => d.initialValue), everyElement(isNull));
      await f.tap(t, 'Review entry');
      expect(find.text('Confirm and save'), findsNothing);
      expect(writes, 0);
      expect(t.takeException(), isNull);
    },
  );

  for (final wrongBusiness in [false, true]) {
    testWidgets(
      'voice ${wrongBusiness ? 'wrong-business draft' : 'cancel'} cannot open an entry or write',
      (t) async {
        await f.size(t, const Size(1100, 1100));
        var writes = 0;
        final client = f.client((r) {
          if (r.method == 'POST') writes++;
          return f.reply(
            r.url.path.endsWith('/overview')
                ? overview()
                : {
                    'businesses': [f.business()],
                  },
          );
        });
        addTearDown(client.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: BookkeepingScreen(
              client: client,
              openVoice: (_, __, ___) async => wrongBusiness
                  ? {...draft(), 'business_id': 'another-business'}
                  : null,
            ),
          ),
        );
        await t.pumpAndSettle();
        await f.tap(t, 'Talk to K-Nova');
        expect(find.byType(BookkeepingEntryDialog), findsNothing);
        expect(writes, 0);
        if (wrongBusiness)
          expect(
            find.textContaining('does not match the selected business'),
            findsOneWidget,
          );
      },
    );
  }

  testWidgets(
    'access denial during voice rejects the late returned financial draft',
    (t) async {
      await f.size(t, const Size(1100, 1100));
      final result = Completer<Map<String, dynamic>?>();
      var writes = 0;
      final client = f.client((r) {
        if (r.method == 'POST') writes++;
        if (r.url.path.endsWith('/denied'))
          return f.reply({'error': 'Denied'}, 403);
        return f.reply(
          r.url.path.endsWith('/overview')
              ? overview()
              : {
                  'businesses': [f.business()],
                },
        );
      });
      addTearDown(client.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookkeepingScreen(
            client: client,
            openVoice: (_, __, ___) => result.future,
          ),
        ),
      );
      await t.pumpAndSettle();
      await f.tap(t, 'Talk to K-Nova');
      await expectLater(client.request('GET', '/denied'), throwsException);
      result.complete(draft());
      await t.pumpAndSettle();
      expect(find.byType(BookkeepingEntryDialog), findsNothing);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      expect(writes, 0);
    },
  );
}

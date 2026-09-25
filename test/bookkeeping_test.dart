import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_forms.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_models.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';

const businessId = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> business() => {
  'id': businessId,
  'name': 'Harbor Creative LLC',
  'legal_structure': 'llc',
  'tax_treatment': 's_corporation',
  'contractor_income': true,
  'currency': 'USD',
  'basis': 'cash',
  'version': 1,
};
List<Map<String, dynamic>> categories() => [
  {'code': '4000', 'name': 'Services', 'kind': 'income'},
  {'code': '5010', 'name': 'Software and subscriptions', 'kind': 'expense'},
];
Map<String, dynamic> savedEntry({String kind = 'income'}) => {
  'id': '22222222-2222-4222-8222-222222222222',
  'business_id': businessId,
  'entry_date': '2027-01-15',
  'kind': kind,
  'amount_cents': '125000',
  'purpose': 'January design retainer',
  'counterparty': 'Bayside Studio',
  'receipt_reference': 'INV-1001',
  'category_name': 'Services',
  'reversal_of': null,
  'reversed_by': null,
};
Map<String, dynamic> overview({List<Map<String, dynamic>>? entries}) => {
  'business': business(),
  'entries': entries ?? [savedEntry()],
  'categories': categories(),
  'income_cents': '125000',
  'expense_cents': '999',
  'net_cents': '124001',
  'entry_count': entries?.length ?? 1,
};
http.Response reply(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
String token(String user, {int revision = 1}) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://example.com/auth/v1', 'sub': user, 'session_id': 'session-$user', 'iat': revision}))).replaceAll('=', '')}.sig$revision';
BookkeepingClient client(
  FutureOr<http.Response> Function(http.Request) handler,
) => BookkeepingClient(
  backendBaseUrl: 'https://example.com',
  headersBuilder: () => {'Authorization': 'Bearer fixture'},
  client: MockClient((r) async => handler(r)),
);
Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> fill(WidgetTester t, String label, String text) async {
  final f = field(label);
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> size(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> mountDialog(WidgetTester t, Widget dialog) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                showDialog<void>(context: c, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tap(t, 'Open');
}

Future<void> screenshot(WidgetTester t, String name, GlobalKey key) async {
  final directory = Platform.environment['KORLIX_BOOKKEEPING_PREVIEW'];
  if (directory == null) return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final e in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/${e.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test('money stays exact above JS safe integer range and validates cents', () {
    expect(bookkeepingMoney('9007199254740993'), r'$90,071,992,547,409.93');
    expect(bookkeepingMoney('-999'), r'-$9.99');
    for (final v in ['0', '-1', '1.001', '1e3', '01.00', 'NaN']) {
      expect(validateBookkeepingAmount(v), isNotNull);
    }
    for (final v in ['0.01', '0.1', '9999999999.99']) {
      expect(validateBookkeepingAmount(v), isNull);
    }
    expect(validateBookkeepingDate('2027-02-29'), isNotNull);
    expect(validateBookkeepingDate('2028-02-29'), isNull);
    expect(allowedTreatments('llc'), contains('s_corporation'));
    expect(
      allowedTreatments('corporation'),
      isNot(contains('sole_proprietor')),
    );
  });
  test(
    'session change rejects late financial responses and blocks later writes',
    () async {
      var access = token('a');
      final revisions = ValueNotifier(0), wait = Completer<http.Response>();
      int calls = 0;
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'Bearer $access'},
        sessionChanges: revisions,
        client: MockClient((_) {
          calls++;
          return wait.future;
        }),
      );
      final result = c.request('GET', '/businesses');
      final expected = expectLater(
        result,
        throwsA(
          isA<BookkeepingException>().having((e) => e.status, 'status', 401),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      access = token('b');
      revisions.value++;
      wait.complete(
        reply({
          'businesses': [business()],
        }),
      );
      await expected;
      await expectLater(
        c.request('POST', '/businesses', body: {}),
        throwsA(isA<BookkeepingException>()),
      );
      expect(calls, 1);
      c.dispose();
      revisions.dispose();
    },
  );
  test(
    'same-session token refresh retains access and sends new bearer',
    () async {
      var access = token('a');
      final revisions = ValueNotifier(0);
      String? received;
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com/',
        headersBuilder: () => {'Authorization': 'Bearer $access'},
        sessionChanges: revisions,
        client: MockClient((r) async {
          received = r.headers['Authorization'];
          expect(r.url.path, '/api/bookkeeping/businesses');
          return reply({'businesses': []});
        }),
      );
      access = token('a', revision: 2);
      revisions.value++;
      await c.request('GET', '/businesses');
      expect(received, 'Bearer $access');
      expect(c.sessionChanged, false);
      c.dispose();
      revisions.dispose();
    },
  );
  testWidgets(
    'empty recordbook offers real setup and shows current release scope',
    (t) async {
      final c = client((_) => reply({'businesses': []}));
      addTearDown(c.dispose);
      await size(t, const Size(390, 844));
      await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
      await t.pumpAndSettle();
      expect(find.text('Add your first business'), findsOneWidget);
      expect(
        find.textContaining('Coming next: expanded accounting'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await tap(t, 'Add your first business');
      expect(find.text('Add your business'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'profile setup sends separated structure/tax/1099 fields and stable retry',
    (t) async {
      final requests = <Map<String, dynamic>>[];
      final c = client((r) {
        final p = jsonDecode(r.body) as Map<String, dynamic>;
        requests.add(p);
        return requests.length == 1
            ? reply({'error': 'Temporary failure'}, 503)
            : reply({'business': business()}, 201);
      });
      addTearDown(c.dispose);
      await size(t, const Size(390, 844));
      await mountDialog(
        t,
        BookkeepingProfileDialog(client: c, business: business()),
      );
      await fill(t, 'Business name', 'Harbor Updated');
      await tap(t, 'Save business');
      await tap(t, 'Retry same save');
      expect(requests.length, 2);
      expect(requests[0], requests[1]);
      expect(requests[0]['legal_structure'], 'llc');
      expect(requests[0]['tax_treatment'], 's_corporation');
      expect(requests[0]['contractor_income'], true);
      expect(requests[0]['version'], 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'entry validates input, requires review, preserves string amounts and retries one key',
    (t) async {
      final requests = <Map<String, dynamic>>[];
      final c = client((r) {
        requests.add(jsonDecode(r.body) as Map<String, dynamic>);
        return requests.length == 1
            ? reply({'error': 'Connection interrupted'}, 503)
            : reply({'entry': savedEntry()}, 201);
      });
      addTearDown(c.dispose);
      await size(t, const Size(390, 844));
      await mountDialog(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: businessId,
          categories: categories(),
          kind: 'income',
        ),
      );
      await tap(t, 'Review entry');
      expect(requests, isEmpty);
      expect(find.text('Describe why this entry was made.'), findsOneWidget);
      await fill(t, 'Amount (USD)', '0.10');
      await fill(t, 'Date received / paid', '2027-01-15');
      await fill(t, 'Business purpose', 'Consulting');
      await tap(t, 'Review entry');
      expect(requests, isEmpty);
      expect(find.text('Review income'), findsOneWidget);
      await tap(t, 'Confirm and save');
      expect(find.text('Edit'), findsNothing);
      await tap(t, 'Retry same save');
      expect(requests.length, 2);
      expect(requests.first, requests.last);
      expect(requests.first['amount'], '0.10');
      expect(requests.first['confirmed'], true);
      expect(
        requests.first['request_key'],
        matches(RegExp(r'^[a-f0-9-]{36}$')),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'reversal explains prior-month change and requires reason and confirmation',
    (t) async {
      final requests = <http.Request>[];
      final c = client((r) {
        requests.add(r);
        return reply({'entry': savedEntry()}, 201);
      });
      addTearDown(c.dispose);
      await size(t, const Size(390, 844));
      await mountDialog(
        t,
        BookkeepingEntryDialog(
          client: c,
          businessId: businessId,
          categories: categories(),
          kind: 'income',
          original: savedEntry(),
        ),
      );
      await fill(t, 'Reason for correction', 'Duplicate entry');
      await tap(t, 'Review entry');
      expect(
        find.textContaining('equal offset is recorded on 2027-01-15'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await tap(t, 'Confirm reversal');
      expect(requests.single.url.path, endsWith('/reverse'));
      expect(jsonDecode(requests.single.body)['reason'], 'Duplicate entry');
      expect(t.takeException(), isNull);
    },
  );
  for (final viewport in [
    const Size(1440, 1000),
    const Size(390, 844),
    const Size(320, 760),
  ]) {
    testWidgets(
      'dashboard fits ${viewport.width} with real totals, export and entry actions',
      (t) async {
        final requests = <http.Request>[];
        String? exported;
        final key = GlobalKey();
        final c = client((r) {
          requests.add(r);
          return reply(
            r.url.path.endsWith('/overview')
                ? overview()
                : r.url.path.endsWith('/export')
                ? {
                    'csv': 'entry_id,amount\nfixture,1250.00',
                    'filename': 'fixture.csv',
                    'count': 1,
                  }
                : {
                    'businesses': [business()],
                  },
          );
        });
        addTearDown(c.dispose);
        await size(t, viewport);
        await t.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: BookkeepingScreen(
                client: c,
                onExport: (csv, name) async {
                  exported = csv;
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Recorded income'), findsOneWidget);
        expect(find.text(r'$1,250.00'), findsNWidgets(2));
        expect(find.text('January design retainer'), findsOneWidget);
        expect(t.takeException(), isNull);
        await screenshot(t, 'dashboard-${viewport.width.toInt()}', key);
        await tap(t, 'Export month');
        expect(exported, contains('1250.00'));
        expect(requests.last.url.queryParameters['month'], isNotNull);
        await tap(t, 'Record expense');
        expect(find.text('Business purpose'), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, 'Close');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'sign-out clears saved financial data and closes open entry dialog',
    (t) async {
      String? access = token('a');
      final revisions = ValueNotifier(0);
      int posts = 0;
      final c = BookkeepingClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {
          if (access != null) 'Authorization': 'Bearer $access',
        },
        sessionChanges: revisions,
        client: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return reply(
            r.url.path.endsWith('/overview')
                ? overview()
                : {
                    'businesses': [business()],
                  },
          );
        }),
      );
      addTearDown(() {
        c.dispose();
        revisions.dispose();
      });
      await size(t, const Size(390, 844));
      await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
      await t.pumpAndSettle();
      await tap(t, 'Record income');
      await fill(t, 'Amount (USD)', '10.00');
      access = null;
      revisions.value++;
      await t.pumpAndSettle();
      expect(find.text('January design retainer'), findsNothing);
      expect(find.text('Amount (USD)'), findsNothing);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      expect(posts, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('successful entry switches dashboard to the recorded month', (
    t,
  ) async {
    final months = <String>[];
    final c = client((r) {
      if (r.url.path.endsWith('/overview')) {
        months.add(r.url.queryParameters['month']!);
        return reply(overview());
      }
      if (r.method == 'POST') return reply({'entry': savedEntry()}, 201);
      return reply({
        'businesses': [business()],
      });
    });
    addTearDown(c.dispose);
    await size(t, const Size(390, 844));
    await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
    await t.pumpAndSettle();
    await tap(t, 'Record income');
    await fill(t, 'Amount (USD)', '15.00');
    await fill(t, 'Date received / paid', '2027-02-15');
    await fill(t, 'Business purpose', 'Services');
    await tap(t, 'Review entry');
    await tap(t, 'Confirm and save');
    expect(months.last, '2027-02');
    expect(t.takeException(), isNull);
  });
}

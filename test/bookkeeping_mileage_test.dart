import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_client.dart';
import 'package:ai_wiz_command_center/bookkeeping/bookkeeping_screen.dart';
import 'package:ai_wiz_command_center/bookkeeping/mileage_form.dart';
import 'package:ai_wiz_command_center/bookkeeping/mileage_models.dart';
import 'package:ai_wiz_command_center/bookkeeping/mileage_screen.dart';
import 'bookkeeping_test.dart' as f;

const tid = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> trip({bool excluded = false}) => {
  'id': tid,
  'trip_date': '2027-01-15',
  'vehicle': 'Blue hatchback',
  'origin': 'Studio',
  'destination': 'Client office',
  'purpose': 'Deliver completed designs',
  'method': 'miles',
  'distance_tenths': '123',
  'manual_tenths': '123',
  'start_tenths': null,
  'end_tenths': null,
  'correction_of': null,
  'void_id': excluded ? 'void' : null,
  'void_reason': excluded ? 'Duplicate trip' : null,
  'replacement_id': null,
  'included_tenths': excluded ? '0' : '123',
};
Map<String, dynamic> list({bool excluded = false}) => {
  'trips': [trip(excluded: excluded)],
  'summary': {
    'distance_tenths': excluded ? '0' : '123',
    'trip_count': excluded ? 0 : 1,
    'excluded_count': excluded ? 1 : 0,
  },
  'record_count': 1,
  'vehicles': ['Blue hatchback'],
  'period': '2027-01',
};
http.Response base(http.Request r) {
  if (r.url.path.endsWith('/businesses')) {
    return f.reply({
      'businesses': [f.business()],
    });
  }
  if (r.url.path.endsWith('/overview')) return f.reply(f.overview());
  return f.reply(list());
}

Future<void> fillTrip(WidgetTester t) async {
  await f.fill(t, 'Trip date (YYYY-MM-DD)', '2027-01-15');
  await f.fill(t, 'Vehicle nickname', 'Blue hatchback');
  await f.fill(t, 'Starting place', 'Studio');
  await f.fill(t, 'Destination', 'Client office');
  await f.fill(t, 'Business purpose', 'Deliver completed designs');
  await f.fill(t, 'Miles driven', '12.3');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
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
    }
  });
  test('mileage arithmetic preserves tenths and rejects invalid distance', () {
    expect(mileageDecimal('9007199254740993'), '900719925474099.3');
    expect(mileageTenths('0.1'), BigInt.one);
    expect(mileageTenths('0', odometer: true), BigInt.zero);
    for (final v in ['0', '1.01', '-1', '1e2', '01.2', '10000']) {
      expect(mileageTenths(v), isNull);
    }
    expect(
      mileageDecimal(
        mileageTenths('100.3', odometer: true)! -
            mileageTenths('100.1', odometer: true)!,
      ),
      '0.2',
    );
  });
  testWidgets(
    'trip validates, requires review, and preserves request key after lost response',
    (t) async {
      await f.size(t, const Size(1000, 1100));
      final sent = <Map<String, dynamic>>[];
      final c = f.client((r) {
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        return sent.length == 1
            ? f.reply({'error': 'Response interrupted'}, 503)
            : f.reply({'trip': trip()}, 201);
      });
      await f.mountDialog(t, MileageForm(client: c, businessId: f.businessId));
      await f.tap(t, 'Review trip');
      expect(sent, isEmpty);
      await fillTrip(t);
      await f.tap(t, 'Review trip');
      expect(sent, isEmpty);
      expect(find.text('12.3 miles'), findsOneWidget);
      await f.tap(t, 'Confirm and save trip');
      await f.tap(t, 'Retry same save');
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(sent[0]['miles'], '12.3');
      expect(sent[0]['confirmed'], true);
      c.dispose();
    },
  );
  testWidgets(
    'odometer workflow rejects reversed readings and reviews exact difference',
    (t) async {
      await f.size(t, const Size(1000, 1100));
      final c = f.client((_) => f.reply({'trip': trip()}));
      await f.mountDialog(t, MileageForm(client: c, businessId: f.businessId));
      await fillTrip(t);
      await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await f.tap(t, 'Odometer readings');
      await f.fill(t, 'Starting odometer (miles)', '100.3');
      await f.fill(t, 'Ending odometer (miles)', '100.1');
      await f.tap(t, 'Review trip');
      expect(
        find.textContaining('Ending odometer must be higher'),
        findsOneWidget,
      );
      await f.fill(t, 'Starting odometer (miles)', '100.1');
      await f.fill(t, 'Ending odometer (miles)', '100.3');
      await f.tap(t, 'Review trip');
      expect(find.text('0.2 miles'), findsOneWidget);
      c.dispose();
    },
  );
  testWidgets(
    'correction preserves original details and posts one reviewed replacement',
    (t) async {
      await f.size(t, const Size(1000, 1100));
      http.Request? sent;
      final c = f.client((r) {
        sent = r;
        return f.reply({
          'trip': {...trip(), 'trip_date': '2027-02-01'},
        });
      });
      await f.mountDialog(
        t,
        MileageForm(client: c, businessId: f.businessId, original: trip()),
      );
      await f.fill(t, 'Trip date (YYYY-MM-DD)', '2027-02-01');
      await f.fill(t, 'Miles driven', '14.7');
      await f.fill(t, 'Reason for correction', 'Correct date and distance');
      await f.tap(t, 'Review trip');
      expect(
        find.text('Original: 2027-01-15 · 12.3 mi · Blue hatchback'),
        findsOneWidget,
      );
      expect(sent, isNull);
      await f.tap(t, 'Confirm and save trip');
      expect(sent!.url.path, endsWith('/mileage/$tid/correct'));
      expect(jsonDecode(sent!.body)['trip_date'], '2027-02-01');
      c.dispose();
    },
  );
  testWidgets(
    'void requires a reason and separate confirmation without deleting trip',
    (t) async {
      http.Request? sent;
      final c = f.client((r) {
        sent = r;
        return f.reply({
          'void': {'id': 'fixture'},
        });
      });
      await f.mountDialog(
        t,
        MileageForm(
          client: c,
          businessId: f.businessId,
          original: trip(),
          voidOnly: true,
        ),
      );
      await f.tap(t, 'Review trip');
      expect(find.text('Enter 1–500 characters on one line.'), findsOneWidget);
      expect(sent, isNull);
      await f.fill(t, 'Reason for correction', 'Duplicate trip');
      await f.tap(t, 'Review trip');
      expect(
        find.textContaining('excluded from mileage totals'),
        findsOneWidget,
      );
      await f.tap(t, 'Confirm exclusion');
      expect(sent!.method, 'POST');
      expect(sent!.url.path, endsWith('/mileage/$tid/void'));
      expect(jsonDecode(sent!.body)['reason'], 'Duplicate trip');
      c.dispose();
    },
  );
  testWidgets('year and vehicle filters apply to totals and exported history', (
    t,
  ) async {
    await f.size(t, const Size(1100, 1100));
    final requests = <http.Request>[];
    String? exported;
    final c = f.client((r) {
      requests.add(r);
      return r.url.path.endsWith('/export')
          ? f.reply({
              'csv': 'recorded,included\r\n12.3,0.0\r\n',
              'filename': 'mileage.csv',
            })
          : f.reply(list(excluded: true));
    });
    await f.mountDialog(
      t,
      BookkeepingMileage(
        client: c,
        businessId: f.businessId,
        businessName: 'Harbor Creative LLC',
        onExport: (csv, _) async {
          exported = csv;
        },
      ),
    );
    await f.fill(t, 'Period (YYYY or YYYY-MM)', '2027');
    await f.fill(t, 'Vehicle filter (optional)', 'Blue hatchback');
    await f.tap(t, 'Apply filters');
    expect(requests.last.url.queryParameters['period'], '2027');
    expect(requests.last.url.queryParameters['vehicle'], 'Blue hatchback');
    expect(find.text('0.0 miles'), findsOneWidget);
    expect(find.text('Void trip'), findsNothing);
    await f.tap(t, 'Export mileage');
    expect(requests.last.url.queryParameters['vehicle'], 'Blue hatchback');
    expect(exported, contains('12.3,0.0'));
    c.dispose();
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('mileage workflow fits $width and opens from dashboard', (
      t,
    ) async {
      await f.size(t, Size(width, 1000));
      final c = f.client(base);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(home: BookkeepingScreen(client: c)),
        ),
      );
      await t.pumpAndSettle();
      await f.tap(t, 'Mileage log');
      expect(find.text('Business mileage'), findsOneWidget);
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'k200-mileage-${width.toInt()}', key);
      await f.tap(t, 'Record trip');
      expect(t.takeException(), isNull);
      await fillTrip(t);
      await f.tap(t, 'Review trip');
      expect(t.takeException(), isNull);
      c.dispose();
    });
  }
  testWidgets('logout clears private mileage and closes nested trip form', (
    t,
  ) async {
    await f.size(t, const Size(1100, 1000));
    final changes = ValueNotifier(0);
    String identity = f.token('owner');
    final c = BookkeepingClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {'Authorization': 'Bearer $identity'},
      sessionChanges: changes,
      client: MockClient((r) async => base(r)),
    );
    await t.pumpWidget(MaterialApp(home: BookkeepingScreen(client: c)));
    await t.pumpAndSettle();
    await f.tap(t, 'Mileage log');
    await f.tap(t, 'Correct trip');
    identity = f.token('other');
    changes.value++;
    await t.pumpAndSettle();
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(find.text('Blue hatchback'), findsNothing);
    expect(find.text('Correct trip'), findsNothing);
    expect(t.takeException(), isNull);
    c.dispose();
    changes.dispose();
  });
}

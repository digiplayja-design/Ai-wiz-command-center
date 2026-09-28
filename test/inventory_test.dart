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
import 'package:ai_wiz_command_center/inventory/inventory_client.dart';
import 'package:ai_wiz_command_center/inventory/inventory_screen.dart';
import 'package:ai_wiz_command_center/inventory/inventory_voice.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Map<String, dynamic> copy(Map<String, dynamic> value) =>
    inventoryMap(jsonDecode(jsonEncode(value)));
final product = {
  'id': 'item-1',
  'revision': 1,
  'data': {
    'name': 'Cordless drill 18V',
    'sku': 'ATL-018',
    'brand': 'Atlas',
    'category': 'Tools',
    'description': 'Compact cordless drill with rechargeable battery.',
    'unit': 'each',
    'currency': 'USD',
    'price': 89.95,
    'reorder': 4,
    'tracking': 'serial',
  },
  'available': 24,
  'quantity': 26,
  'reserved': 2,
  'locations': 3,
};

class FakeInventory extends InventoryClient {
  FakeInventory()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> searches = [], changes = [];
  bool empty = false, failChange = false;
  Completer<Map<String, dynamic>>? searchWait;
  @override
  Future<Map<String, dynamic>> workspace() async => {
    'locations': [
      {
        'id': 'location-1',
        'revision': 1,
        'data': {
          'name': 'Columbus warehouse',
          'region': 'Ohio',
          'country': 'US',
          'city': 'Columbus',
          'address': 'Unit 4',
        },
      },
      {
        'id': 'location-2',
        'revision': 1,
        'data': {
          'name': 'Kingston studio',
          'region': 'Kingston',
          'country': 'JM',
          'city': 'Kingston',
        },
      },
    ],
    'partners': [],
    'orders': [],
    'summary': {
      'products': empty ? 0 : 148,
      'units': 1208,
      'locations': 2,
      'reserved': 26,
      'value': [
        {'currency': 'USD', 'amount': 12400},
      ],
    },
  };
  @override
  Future<Map<String, dynamic>> search(Map<String, dynamic> f) async {
    searches.add(copy(f));
    if (searchWait != null) return searchWait!.future;
    return {
      'total': empty ? 0 : 1,
      'items': empty ? [] : [copy(product)],
      'scope': f['scope'],
      'country': f['country'],
      'region': f['region'],
    };
  }

  @override
  Future<Map<String, dynamic>> item(String id) async => {
    'item': copy(product),
    'stock': [
      {
        'id': 'stock-1',
        'revision': 1,
        'location_id': 'location-1',
        'serial': '000-AT-102',
        'quantity': 1,
        'reserved': 0,
        'unit_cost': 40,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> change(Map<String, dynamic> b) async {
    changes.add(copy(b));
    if (failChange) {
      failChange = false;
      throw const InventoryException('Connection interrupted');
    }
    return {'record': product};
  }

  @override
  Future<Map<String, dynamic>> events({int offset = 0, String? item}) async => {
    'events': [],
  };
}

final boundary = GlobalKey();
Future<void> mount(
  WidgetTester t,
  FakeInventory c, {
  double width = 1280,
  double scale = 1,
  String theme = 'pure_white',
  InventoryVoiceLauncher? voice,
}) async {
  t.view.physicalSize = Size(width, 1100);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: InventoryScreen(
          client: c,
          ensureConsent: (_) async => true,
          openVoice: voice ?? (_, __) async {},
          saveFile: (a, b, c, d) async {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });
  for (final theme in ['pure_white', 'pure_black']) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'Inventory $theme at $width with large text and geographic controls',
        (t) async {
          final c = FakeInventory();
          await mount(t, c, width: width, scale: 1.25, theme: theme);
          expect(find.text('KORLIX Inventory'), findsOneWidget);
          expect(find.text('K-Nova Live'), findsOneWidget);
          expect(t.takeException(), isNull);
          await tap(t, find.text('Statewide'));
          expect(c.searches.last['scope'], 'statewide');
          expect(c.searches.last['region'], 'Ohio');
          await tap(t, find.text('Nationwide'));
          expect(c.searches.last['scope'], 'nationwide');
          await tap(t, find.text('International'));
          expect(c.searches.last['scope'], 'international');
          await tap(t, find.text('Cordless drill 18V'));
          expect(find.text('Stock & traceability'), findsOneWidget);
          expect(find.textContaining('000-AT-102'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Text and voice share partial-name and geographic search without changing inventory',
    (t) async {
      final c = FakeInventory();
      InventorySearch? liveSearch;
      await mount(
        t,
        c,
        voice: (search, render) async {
          liveSearch = search;
        },
      );
      await tap(t, find.text('Statewide'));
      await t.enterText(find.byType(TextField), 'dri');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(c.searches.last['q'], 'dri');
      await tap(t, find.text('Ask K-Nova'));
      expect(liveSearch, isNotNull);
      await liveSearch!({'q': '000-AT'});
      await t.pumpAndSettle();
      expect(c.searches.last['region'], 'Ohio');
      expect(c.searches.last['scope'], 'statewide');
      expect(find.text('000-AT'), findsOneWidget);
      expect(c.changes, isEmpty);
    },
  );
  testWidgets(
    'Uncertain save retries the original request key and blocks a second change',
    (t) async {
      final c = FakeInventory()..failChange = true;
      await mount(t, c);
      await tap(t, find.text('Add item'));
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'New item');
      await t.enterText(fields.at(1), 'NEW-1');
      await tap(t, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('One change needs confirmation'), findsOneWidget);
      expect(c.changes, hasLength(1));
      await tap(t, find.text('Confirm pending change'));
      expect(c.changes, hasLength(2));
      expect(c.changes[0], c.changes[1]);
      expect(find.text('One change needs confirmation'), findsNothing);
    },
  );
  testWidgets('Account change hides stock and late search results', (t) async {
    final c = FakeInventory();
    await mount(t, c);
    final gate = Completer<Map<String, dynamic>>();
    c.searchWait = gate;
    await t.enterText(find.byType(TextField), 'private');
    await t.pump(const Duration(milliseconds: 400));
    c.onAccessDenied!();
    await t.pumpAndSettle();
    gate.complete({
      'total': 1,
      'items': [product],
    });
    await t.pumpAndSettle();
    expect(find.textContaining('sign-in changed'), findsOneWidget);
    expect(find.text('Cordless drill 18V'), findsNothing);
  });
  testWidgets(
    'Multi-item order form saves explicit lines and rejects an empty draft',
    (t) async {
      final c = FakeInventory();
      await mount(t, c, width: 390, scale: 1.25);
      await tap(t, find.text('Cordless drill 18V'));
      await tap(t, find.text('Create order'));
      await t.enterText(find.byType(TextFormField).first, 'PO-2026-01');
      await tap(t, find.text('Save draft'));
      expect(find.text('Add at least one order line.'), findsOneWidget);
      await tap(t, find.text('Add to order'));
      await tap(t, find.text('Add to order'));
      expect(find.text('Order lines · 2'), findsOneWidget);
      await tap(t, find.text('Save draft'));
      expect(c.changes.single['value']['lines'], hasLength(2));
      expect(c.changes.single['value']['type'], 'purchase');
      expect(t.takeException(), isNull);
    },
  );
  test('Client rejects a late response after sign-in identity changes', () async {
    final revision = ValueNotifier(0);
    String user = 'one';
    String token() =>
        'x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'test', 'sub': user, 'session_id': 'session'})))}.x';
    final gate = Completer<http.Response>();
    final c = InventoryClient(
      backendBaseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': 'Bearer ${token()}'},
      sessionChanges: revision,
      client: MockClient((_) => gate.future),
    );
    final pending = c.workspace();
    final assertion = expectLater(pending, throwsA(isA<InventoryException>()));
    user = 'two';
    revision.value++;
    gate.complete(http.Response('{}', 200));
    await assertion;
    c.dispose();
  });
  test(
    'Voice tool accepts completed calls only and excludes private URLs from output',
    () {
      final call = {
        'type': 'function_call',
        'status': 'completed',
        'name': 'search_inventory',
        'call_id': 'call-1',
        'arguments': '{"q":"dri","scope":"nationwide","country":"US"}',
      };
      expect(
        inventoryVoiceCalls({
          'status': 'completed',
          'output': [call],
        }),
        hasLength(1),
      );
      expect(
        inventoryVoiceCalls({
          'status': 'cancelled',
          'output': [call],
        }),
        isEmpty,
      );
      expect(inventoryVoiceArguments(call['arguments'])['q'], 'dri');
      expect(
        inventoryVoiceArguments({'q': 'x', 'action': 'delete'})['action'],
        isNull,
      );
      final summary = inventoryVoiceSummary({
        'total': 1,
        'items': [
          {...product, 'photo_url': 'private-photo', 'owner_id': 'owner'},
        ],
      });
      expect(jsonEncode(summary), isNot(contains('private-photo')));
      expect(jsonEncode(summary), isNot(contains('owner_id')));
    },
  );
  testWidgets('Inventory screenshot captures', (t) async {
    final dir = Platform.environment['INVENTORY_SCREENSHOTS_DIR'];
    if (dir == null) return;
    for (final width in [390.0, 1440.0]) {
      await mount(t, FakeInventory(), width: width);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File(
          '$dir/inventory-${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }
  });
}

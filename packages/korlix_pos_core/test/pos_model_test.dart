import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_pos_core/korlix_pos_core.dart';

void main() {
  late PosWorkspace w;
  late String saved;
  setUp(() {
    saved = '';
    w = PosWorkspace(
      save: (raw) async {
        saved = raw;
      },
      clock: () => DateTime(2026, 10, 24, 12),
    );
  });
  test(
    'decimal entry accepts cents and rejects exponent, negative and excess precision',
    () {
      expect(posParseMoney('12.5'), 1250);
      expect(posParseMoney('0.01'), 1);
      for (final invalid in [
        '-1',
        '1.001',
        '1e3',
        'NaN',
        'Infinity',
        '',
        '1000000',
      ]) {
        expect(() => posParseMoney(invalid), throwsFormatException);
      }
    },
  );
  test('line-level rounding keeps discounted taxable total in whole cents', () {
    final totals = PosTotals(
      const [PosLine(productId: 'x', name: 'X', price: 1999, quantity: 3)],
      1000,
      825,
      100,
    );
    expect(totals.subtotal, 5997);
    expect(totals.discount, 600);
    expect(totals.tax, 445);
    expect(totals.total, 5942);
  });
  test(
    'cash checkout records sale, deducts stock once and calculates change',
    () async {
      await w.add('r1');
      await w.add('r1');
      await w.configure(discount: 1000, tax: 800);
      final o = await w.checkout(cash: 4000);
      expect(o.totals.total, 3499);
      expect(o.change, 501);
      expect(w.products.first.stock, 22);
      expect(w.cart, isEmpty);
      expect(w.todayNetCash, 3499);
      expect(jsonDecode(saved)['orders'], hasLength(1));
      await expectLater(
        w.checkout(cash: 4000, orderId: o.id),
        throwsStateError,
      );
      expect(w.products.first.stock, 22);
      expect(w.orders, hasLength(1));
    },
  );
  test('underpayment rolls back order, stock, sequence and cart', () async {
    await w.add('r1');
    final before = jsonEncode(w.toJson());
    await expectLater(w.checkout(cash: 100), throwsStateError);
    expect(jsonEncode(w.toJson()), before);
    expect(w.orders, isEmpty);
    final o = await w.checkout(cash: 1800);
    expect(o.id, 'KX-1001');
  });
  test('persistence failure cannot report a completed sale', () async {
    var fail = false;
    final model = PosWorkspace(
      save: (raw) async {
        if (fail) throw StateError('disk full');
      },
    );
    await model.add('r1');
    fail = true;
    await expectLater(model.checkout(cash: 1800), throwsStateError);
    expect(model.orders, isEmpty);
    expect(model.cart, hasLength(1));
    expect(model.products.first.stock, 24);
    expect(model.busy, isFalse);
  });
  test(
    'rapid duplicate mutation is rejected while persistence is pending',
    () async {
      final done = Completer<void>();
      final model = PosWorkspace(save: (_) => done.future);
      final first = model.add('r1');
      await expectLater(model.add('r1'), throwsStateError);
      done.complete();
      await first;
      expect(model.units, 1);
    },
  );
  test('stock limits combine modifier lines and reject overselling', () async {
    await w.add('r1');
    await w.quantity(w.cart.single.key, 24);
    await expectLater(w.add('r1'), throwsStateError);
    expect(w.units, 24);
    await expectLater(w.quantity(w.cart.single.key, 25), throwsStateError);
    expect(w.units, 24);
  });
  test('mode switch cannot silently drop a cart', () async {
    await w.add('r1');
    await expectLater(w.switchMode('restaurant'), throwsStateError);
    expect(w.mode, 'retail');
    expect(w.cart, hasLength(1));
  });
  test(
    'restaurant modifiers price correctly and a table is required for dine-in',
    () async {
      await w.switchMode('restaurant');
      await w.add('f1', ['Add cheese', 'Add cheese']);
      expect(w.totals.total, 1600);
      await w.configure(service: 'Dine-in');
      await expectLater(w.sendToKitchen(), throwsStateError);
      expect(w.cart, hasLength(1));
      await w.configure(tableName: 'Table 3', orderNote: 'No onions');
      final o = await w.sendToKitchen();
      expect(o.status, 'unpaid');
      expect(o.table, 'Table 3');
      expect(o.note, 'No onions');
      expect(w.products.firstWhere((p) => p.id == 'f1').stock, 29);
      await w.advanceKitchen(o.id);
      await w.advanceKitchen(o.id);
      await w.advanceKitchen(o.id);
      expect(w.kitchenOrders, isEmpty);
      expect(w.orders.single.status, 'unpaid');
      final paid = await w.checkout(cash: 2000, tip: 200, orderId: o.id);
      expect(paid.change, 200);
      expect(paid.totals.total, 1800);
      expect(w.products.firstWhere((p) => p.id == 'f1').stock, 29);
    },
  );
  test(
    'unknown modifiers and cross-mode items fail without data changes',
    () async {
      await expectLater(w.add('f1'), throwsStateError);
      await w.switchMode('restaurant');
      await expectLater(
        w.add('f1', ['FREE PRICE OVERRIDE']),
        throwsArgumentError,
      );
      expect(w.cart, isEmpty);
    },
  );
  test('refund preserves original sale and restocks exactly once', () async {
    await w.add('r1');
    final o = await w.checkout(cash: 2000);
    await w.reverse(o.id, reason: 'Customer returned item', restock: true);
    expect(w.todayCollected, 1800);
    expect(w.todayReturned, 1800);
    expect(w.todayNetCash, 0);
    expect(w.products.first.stock, 24);
    expect(w.orders.single.lines.single.price, 1800);
    expect(w.orders.single.status, 'refunded');
    await expectLater(
      w.reverse(o.id, reason: 'Duplicate', restock: true),
      throwsStateError,
    );
    expect(w.products.first.stock, 24);
  });
  test(
    'prepared-food cancellation can avoid returning consumed stock',
    () async {
      await w.switchMode('restaurant');
      await w.add('f1');
      final o = await w.sendToKitchen();
      await w.advanceKitchen(o.id);
      await w.reverse(o.id, reason: 'Customer left', restock: false);
      expect(w.kitchenOrders, isEmpty);
      expect(w.products.firstWhere((p) => p.id == 'f1').stock, 29);
      expect(w.todayReturned, 0);
    },
  );
  test(
    'next-day refund affects refund day without rewriting prior-day cash',
    () async {
      var now = DateTime(2026, 10, 24);
      final model = PosWorkspace(save: (_) async {}, clock: () => now);
      await model.add('r1');
      final o = await model.checkout(cash: 1800);
      expect(model.todayNetCash, 1800);
      now = DateTime(2026, 10, 25);
      await model.reverse(o.id, reason: 'Return next day', restock: true);
      expect(model.todayCollected, 0);
      expect(model.todayReturned, 1800);
      expect(model.todayNetCash, -1800);
    },
  );
  test(
    'restoration preserves unpaid checks, catalog and money snapshots',
    () async {
      await w.switchMode('restaurant');
      await w.add('f4', ['Oat milk']);
      await w.sendToKitchen();
      final restored = PosWorkspace(save: (_) async {});
      restored.restore(saved);
      expect(restored.orders.single.totals.total, 625);
      expect(restored.kitchenOrders, hasLength(1));
      expect(restored.orders.single.status, 'unpaid');
      expect(restored.mode, 'restaurant');
    },
  );
  test('catalog changes cannot reprice historical sales', () async {
    await w.add('r1');
    await w.checkout(cash: 1800);
    await w.saveProduct(
      const PosProduct(
        id: 'r1',
        name: 'Renamed tote',
        category: 'Accessories',
        mode: 'retail',
        price: 9900,
        stock: 5,
        symbol: 'tote',
      ),
    );
    expect(w.orders.single.totals.total, 1800);
    expect(w.orders.single.lines.single.name, 'Everyday tote');
  });
  test('CSV quotes data and neutralizes spreadsheet formulas', () async {
    await w.add('r1');
    final o = await w.checkout(cash: 1800);
    await w.reverse(o.id, reason: '=1+1', restock: true);
    expect(w.salesCsv(), contains('"\'=1+1"'));
    expect(w.salesCsv(), contains('PRACTICE DATA ONLY'));
  });
}

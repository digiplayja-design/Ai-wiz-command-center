import 'dart:convert';
import 'package:flutter/foundation.dart';

typedef PosSave = Future<void> Function(String value);

String posMoney(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
int posRound(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

int posParseMoney(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException('Enter an amount such as 20.00.');
  }
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

class PosProduct {
  const PosProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.mode,
    required this.price,
    required this.stock,
    required this.symbol,
    this.barcode = '',
    this.modifiers = const {},
  });
  final String id, name, category, mode, symbol, barcode;
  final int price;
  final int? stock;
  final Map<String, int> modifiers;
  PosProduct stockChanged(int quantity) => PosProduct(
    id: id,
    name: name,
    category: category,
    mode: mode,
    price: price,
    stock: stock == null ? null : stock! + quantity,
    symbol: symbol,
    barcode: barcode,
    modifiers: modifiers,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'mode': mode,
    'price': price,
    'stock': stock,
    'symbol': symbol,
    'barcode': barcode,
    'modifiers': modifiers,
  };
  factory PosProduct.fromJson(Map<String, dynamic> j) => PosProduct(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    mode: j['mode'],
    price: j['price'],
    stock: j['stock'],
    symbol: j['symbol'],
    barcode: j['barcode'] ?? '',
    modifiers: Map<String, int>.from(j['modifiers'] ?? {}),
  );
}

class PosLine {
  const PosLine({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.modifiers = const [],
  });
  final String productId, name;
  final int price, quantity;
  final List<String> modifiers;
  String get key => '$productId:${modifiers.join('|')}';
  int get subtotal => price * quantity;
  PosLine withQuantity(int value) => PosLine(
    productId: productId,
    name: name,
    price: price,
    quantity: value,
    modifiers: modifiers,
  );
  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'price': price,
    'quantity': quantity,
    'modifiers': modifiers,
  };
  factory PosLine.fromJson(Map<String, dynamic> j) => PosLine(
    productId: j['productId'],
    name: j['name'],
    price: j['price'],
    quantity: j['quantity'],
    modifiers: List<String>.from(j['modifiers']),
  );
}

class PosTotals {
  PosTotals(
    List<PosLine> lines,
    this.discountBps,
    this.taxBps, [
    this.tip = 0,
  ]) {
    if (discountBps < 0 ||
        discountBps > 10000 ||
        taxBps < 0 ||
        taxBps > 2500 ||
        tip < 0) {
      throw ArgumentError('Invalid discount, tax or tip.');
    }
    subtotal = lines.fold(0, (sum, l) => sum + l.subtotal);
    discount = lines.fold(
      0,
      (sum, l) => sum + posRound(l.subtotal * discountBps, 10000),
    );
    tax = lines.fold(
      0,
      (sum, l) =>
          sum +
          posRound(
            (l.subtotal - posRound(l.subtotal * discountBps, 10000)) * taxBps,
            10000,
          ),
    );
  }
  final int discountBps, taxBps, tip;
  late final int subtotal, discount, tax;
  int get total => subtotal - discount + tax + tip;
}

class PosOrder {
  PosOrder({
    required this.id,
    required this.mode,
    required this.fulfilment,
    required this.table,
    required this.note,
    required this.lines,
    required this.discountBps,
    required this.taxBps,
    required this.createdAt,
    this.status = 'unpaid',
    this.kitchen = 'queued',
    this.tip = 0,
    this.cash = 0,
    this.paidAt,
    this.refundedAt,
    this.refundReason = '',
    this.restocked = false,
  });
  final String id, mode, fulfilment, table, note;
  final List<PosLine> lines;
  final int discountBps, taxBps;
  final DateTime createdAt;
  String status, kitchen, refundReason;
  int tip, cash;
  DateTime? paidAt, refundedAt;
  bool restocked;
  PosTotals get totals => PosTotals(lines, discountBps, taxBps, tip);
  int get change => cash - totals.total;
  Map<String, dynamic> toJson() => {
    'id': id,
    'mode': mode,
    'fulfilment': fulfilment,
    'table': table,
    'note': note,
    'lines': lines.map((l) => l.toJson()).toList(),
    'discountBps': discountBps,
    'taxBps': taxBps,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'kitchen': kitchen,
    'tip': tip,
    'cash': cash,
    'paidAt': paidAt?.toIso8601String(),
    'refundedAt': refundedAt?.toIso8601String(),
    'refundReason': refundReason,
    'restocked': restocked,
  };
  factory PosOrder.fromJson(Map<String, dynamic> j) => PosOrder(
    id: j['id'],
    mode: j['mode'],
    fulfilment: j['fulfilment'],
    table: j['table'],
    note: j['note'],
    lines: (j['lines'] as List)
        .map((l) => PosLine.fromJson(Map<String, dynamic>.from(l)))
        .toList(),
    discountBps: j['discountBps'],
    taxBps: j['taxBps'],
    createdAt: DateTime.parse(j['createdAt']),
    status: j['status'],
    kitchen: j['kitchen'],
    tip: j['tip'],
    cash: j['cash'],
    paidAt: j['paidAt'] == null ? null : DateTime.parse(j['paidAt']),
    refundedAt: j['refundedAt'] == null
        ? null
        : DateTime.parse(j['refundedAt']),
    refundReason: j['refundReason'] ?? '',
    restocked: j['restocked'] ?? false,
  );
}

class PosWorkspace extends ChangeNotifier {
  PosWorkspace({required this._save, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final PosSave _save;
  final DateTime Function() _clock;
  List<PosProduct> _products = demoProducts();
  List<PosLine> _cart = [];
  List<PosOrder> _orders = [];
  String mode = 'retail', fulfilment = 'Takeaway', table = '', note = '';
  int discountBps = 0, taxBps = 0, _sequence = 1001;
  bool busy = false;
  List<PosProduct> get products => List.unmodifiable(_products);
  List<PosLine> get cart => List.unmodifiable(_cart);
  List<PosOrder> get orders => List.unmodifiable(_orders.reversed);
  PosTotals get totals => PosTotals(_cart, discountBps, taxBps);
  List<PosOrder> get kitchenOrders => orders
      .where(
        (o) =>
            o.mode == 'restaurant' &&
            !['cancelled', 'refunded'].contains(o.status) &&
            o.kitchen != 'served',
      )
      .toList();
  int get units => _cart.fold(0, (sum, l) => sum + l.quantity);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  List<PosOrder> get todaySales => orders
      .where((o) => o.paidAt != null && _sameDay(o.paidAt!, _clock()))
      .toList();
  List<PosOrder> get todayRefunds => orders
      .where((o) => o.refundedAt != null && _sameDay(o.refundedAt!, _clock()))
      .toList();
  int get todayCollected =>
      todaySales.fold(0, (sum, o) => sum + o.totals.total);
  int get todayReturned =>
      todayRefunds.fold(0, (sum, o) => sum + o.totals.total);
  int get todayNetCash => todayCollected - todayReturned;
  int available(String id) {
    final p = _products.firstWhere((p) => p.id == id);
    return p.stock == null
        ? 999
        : (p.stock! -
              _cart
                  .where((l) => l.productId == id)
                  .fold(0, (sum, l) => sum + l.quantity));
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'products': _products.map((p) => p.toJson()).toList(),
    'cart': _cart.map((l) => l.toJson()).toList(),
    'orders': _orders.map((o) => o.toJson()).toList(),
    'mode': mode,
    'fulfilment': fulfilment,
    'table': table,
    'note': note,
    'discountBps': discountBps,
    'taxBps': taxBps,
    'sequence': _sequence,
  };
  void restore(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['schema'] != 1) {
      throw const FormatException(
        'This saved workspace uses an unsupported version.',
      );
    }
    final products = (j['products'] as List)
        .map((p) => PosProduct.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    final cart = (j['cart'] as List)
        .map((p) => PosLine.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    final orders = (j['orders'] as List)
        .map((p) => PosOrder.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    _products = products;
    _cart = cart;
    _orders = orders;
    mode = j['mode'];
    fulfilment = j['fulfilment'];
    table = j['table'];
    note = j['note'];
    discountBps = j['discountBps'];
    taxBps = j['taxBps'];
    _sequence = j['sequence'];
  }

  Future<T> _change<T>(T Function() change) async {
    if (busy) throw StateError('Wait for the current action to finish.');
    final previous = jsonEncode(toJson());
    busy = true;
    notifyListeners();
    try {
      final result = change();
      await _save(jsonEncode(toJson()));
      return result;
    } catch (_) {
      restore(previous);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> switchMode(String value) => _change(() {
    if (!['retail', 'restaurant'].contains(value)) {
      throw ArgumentError('Choose a business mode.');
    }
    if (_cart.isNotEmpty) {
      throw StateError('Complete or clear this cart before switching modes.');
    }
    mode = value;
    table = '';
    note = '';
    fulfilment = 'Takeaway';
    discountBps = 0;
  });
  Future<void> add(String id, [List<String> modifiers = const []]) =>
      _change(() {
        final p = _products.firstWhere((p) => p.id == id);
        if (p.mode != mode) throw StateError('Switch business mode first.');
        if (available(id) < 1) throw StateError('${p.name} is out of stock.');
        final selected = modifiers.toSet().toList()..sort();
        if (selected.any((m) => !p.modifiers.containsKey(m))) {
          throw ArgumentError('Unknown item option.');
        }
        final line = PosLine(
          productId: id,
          name: p.name,
          price: p.price + selected.fold(0, (sum, m) => sum + p.modifiers[m]!),
          modifiers: List.unmodifiable(selected),
        );
        final index = _cart.indexWhere((l) => l.key == line.key);
        if (index < 0) {
          _cart.add(line);
        } else {
          _cart[index] = _cart[index].withQuantity(_cart[index].quantity + 1);
        }
      });
  Future<void> quantity(String key, int value) => _change(() {
    final i = _cart.indexWhere((l) => l.key == key);
    if (i < 0) throw StateError('This item is no longer in your cart.');
    if (value < 0 || value > 999) {
      throw ArgumentError('Quantity must be between 0 and 999.');
    }
    final line = _cart[i];
    if (value > line.quantity + available(line.productId)) {
      throw StateError('There is not enough stock.');
    }
    if (value == 0) {
      _cart.removeAt(i);
    } else {
      _cart[i] = line.withQuantity(value);
    }
  });
  Future<void> clearCart() => _change(() {
    _cart = [];
    note = '';
    table = '';
    discountBps = 0;
  });
  Future<void> configure({
    int? discount,
    int? tax,
    String? service,
    String? tableName,
    String? orderNote,
  }) => _change(() {
    if (discount != null) {
      if (discount < 0 || discount > 10000) {
        throw ArgumentError('Invalid discount.');
      }
      discountBps = discount;
    }
    if (tax != null) {
      if (tax < 0 || tax > 2500) {
        throw ArgumentError('Tax must be between 0% and 25%.');
      }
      taxBps = tax;
    }
    if (service != null) {
      if (!['Takeaway', 'Dine-in'].contains(service)) {
        throw ArgumentError('Invalid service.');
      }
      fulfilment = service;
      if (service == 'Takeaway') table = '';
    }
    if (tableName != null) table = tableName.trim();
    if (orderNote != null) {
      if (orderNote.length > 300) {
        throw ArgumentError('Keep notes under 300 characters.');
      }
      note = orderNote.trim();
    }
  });
  PosOrder _createOrder() {
    if (_cart.isEmpty) throw StateError('Add an item to your cart.');
    if (mode == 'restaurant' && fulfilment == 'Dine-in' && table.isEmpty) {
      throw StateError('Choose a table for this order.');
    }
    for (final p in _products) {
      final count = _cart
          .where((l) => l.productId == p.id)
          .fold(0, (sum, l) => sum + l.quantity);
      if (p.stock != null && count > p.stock!) {
        throw StateError('Refresh stock before checkout.');
      }
    }
    final order = PosOrder(
      id: 'KX-${_sequence++}',
      mode: mode,
      fulfilment: mode == 'retail' ? 'Counter' : fulfilment,
      table: table,
      note: note,
      lines: List.unmodifiable(_cart),
      discountBps: discountBps,
      taxBps: taxBps,
      createdAt: _clock(),
      kitchen: mode == 'retail' ? 'served' : 'queued',
    );
    _products = _products
        .map(
          (p) => p.stockChanged(
            -_cart
                .where((l) => l.productId == p.id)
                .fold(0, (sum, l) => sum + l.quantity),
          ),
        )
        .toList();
    _orders.add(order);
    _cart = [];
    note = '';
    table = '';
    discountBps = 0;
    return order;
  }

  Future<PosOrder> sendToKitchen() => _change(() {
    if (mode != 'restaurant') {
      throw StateError('Kitchen tickets are for restaurant orders.');
    }
    return _createOrder();
  });
  Future<PosOrder> checkout({
    required int cash,
    int tip = 0,
    String? orderId,
  }) => _change(() {
    if (cash < 0 || tip < 0 || cash > 99999999 || tip > 99999999) {
      throw ArgumentError('Invalid cash or tip.');
    }
    final order = orderId == null
        ? _createOrder()
        : _orders.firstWhere((o) => o.id == orderId);
    if (order.status != 'unpaid') {
      throw StateError('This order has already been settled or cancelled.');
    }
    order.tip = tip;
    if (cash < order.totals.total) {
      throw StateError('Cash received is less than the amount due.');
    }
    order.cash = cash;
    order.status = 'paid';
    order.paidAt = _clock();
    return order;
  });
  Future<void> advanceKitchen(String id) => _change(() {
    final o = _orders.firstWhere((o) => o.id == id);
    if (o.mode != 'restaurant' ||
        ['cancelled', 'refunded'].contains(o.status)) {
      throw StateError('This kitchen order is closed.');
    }
    const stages = ['queued', 'preparing', 'ready', 'served'];
    final i = stages.indexOf(o.kitchen);
    if (i < 0 || i == stages.length - 1) {
      throw StateError('This order has already been served.');
    }
    o.kitchen = stages[i + 1];
  });
  Future<void> reverse(
    String id, {
    required String reason,
    required bool restock,
  }) => _change(() {
    final o = _orders.firstWhere((o) => o.id == id);
    if (!['paid', 'unpaid'].contains(o.status)) {
      throw StateError('This order has already been reversed.');
    }
    if (reason.trim().length < 3 || reason.length > 200) {
      throw ArgumentError('Enter a short reason for the audit record.');
    }
    o.status = o.status == 'paid' ? 'refunded' : 'cancelled';
    o.refundReason = reason.trim();
    if (o.status == 'refunded') o.refundedAt = _clock();
    o.restocked = restock;
    if (restock) {
      _products = _products
          .map(
            (p) => p.stockChanged(
              o.lines
                  .where((l) => l.productId == p.id)
                  .fold(0, (sum, l) => sum + l.quantity),
            ),
          )
          .toList();
    }
  });
  Future<void> saveProduct(PosProduct p) => _change(() {
    if (p.name.trim().isEmpty ||
        p.name.length > 80 ||
        p.price < 0 ||
        p.price > 99999999 ||
        (p.stock != null && (p.stock! < 0 || p.stock! > 999999)) ||
        !['retail', 'restaurant'].contains(p.mode)) {
      throw ArgumentError('Check the item name, price and stock.');
    }
    if (_cart.any((l) => l.productId == p.id)) {
      throw StateError('Clear this item from the cart before editing it.');
    }
    if (p.barcode.isNotEmpty &&
        _products.any((x) => x.id != p.id && x.barcode == p.barcode)) {
      throw StateError('That barcode is already assigned.');
    }
    final index = _products.indexWhere((x) => x.id == p.id);
    if (index < 0) {
      _products.add(p);
    } else {
      _products[index] = p;
    }
  });
  Future<void> reset() => _change(() {
    _products = demoProducts();
    _cart = [];
    _orders = [];
    mode = 'retail';
    fulfilment = 'Takeaway';
    table = '';
    note = '';
    discountBps = 0;
    taxBps = 0;
    _sequence = 1001;
  });
  String receipt(PosOrder o) => [
    'KORLIX POS · PRACTICE RECEIPT',
    'No real payment was processed.',
    o.id,
    '${o.fulfilment}${o.table.isEmpty ? '' : ' · ${o.table}'}',
    o.createdAt.toIso8601String(),
    '',
    ...o.lines.map(
      (l) =>
          '${l.quantity} × ${l.name}${l.modifiers.isEmpty ? '' : ' (${l.modifiers.join(', ')})'}  ${posMoney(l.subtotal)}',
    ),
    '',
    'Subtotal  ${posMoney(o.totals.subtotal)}',
    'Discount  -${posMoney(o.totals.discount)}',
    'Sample tax (${o.taxBps / 100}%)  ${posMoney(o.totals.tax)}',
    'Tip  ${posMoney(o.tip)}',
    'TOTAL  ${posMoney(o.totals.total)}',
    'Status  ${o.status.toUpperCase()}',
    if (o.paidAt != null) 'Practice cash received  ${posMoney(o.cash)}',
    if (o.paidAt != null) 'Change  ${posMoney(o.change)}',
    if (o.note.isNotEmpty) 'Note: ${o.note}',
    if (o.refundReason.isNotEmpty) 'Reversal reason: ${o.refundReason}',
    '',
    'Thank you for trying KORLIX POS.',
  ].join('\n');
  String salesCsv() {
    String cell(Object? v) {
      var s = '$v';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      ['PRACTICE DATA ONLY — not accounting records'],
      [
        'order',
        'created',
        'paid',
        'refunded',
        'mode',
        'service',
        'table',
        'status',
        'subtotal_cents',
        'discount_cents',
        'tax_cents',
        'tip_cents',
        'total_cents',
        'currency',
        'reason',
      ],
      ...orders.map(
        (o) => [
          o.id,
          o.createdAt.toIso8601String(),
          o.paidAt?.toIso8601String() ?? '',
          o.refundedAt?.toIso8601String() ?? '',
          o.mode,
          o.fulfilment,
          o.table,
          o.status,
          o.totals.subtotal,
          o.totals.discount,
          o.totals.tax,
          o.tip,
          o.totals.total,
          'USD',
          o.refundReason,
        ],
      ),
    ];
    return rows.map((r) => r.map(cell).join(',')).join('\r\n');
  }
}

List<PosProduct> demoProducts() => const [
  PosProduct(
    id: 'r1',
    name: 'Everyday tote',
    category: 'Accessories',
    mode: 'retail',
    price: 1800,
    stock: 24,
    symbol: 'tote',
    barcode: 'KX1001',
  ),
  PosProduct(
    id: 'r2',
    name: 'Essential tee',
    category: 'Apparel',
    mode: 'retail',
    price: 2400,
    stock: 18,
    symbol: 'shirt',
    barcode: 'KX1002',
  ),
  PosProduct(
    id: 'r3',
    name: 'Travel tumbler',
    category: 'Accessories',
    mode: 'retail',
    price: 2200,
    stock: 12,
    symbol: 'cup',
    barcode: 'KX1003',
  ),
  PosProduct(
    id: 'r4',
    name: 'Studio notebook',
    category: 'Lifestyle',
    mode: 'retail',
    price: 1250,
    stock: 32,
    symbol: 'book',
    barcode: 'KX1004',
  ),
  PosProduct(
    id: 'r5',
    name: 'Signature cap',
    category: 'Apparel',
    mode: 'retail',
    price: 2000,
    stock: 7,
    symbol: 'cap',
    barcode: 'KX1005',
  ),
  PosProduct(
    id: 'r6',
    name: 'Botanical candle',
    category: 'Lifestyle',
    mode: 'retail',
    price: 1650,
    stock: 5,
    symbol: 'candle',
    barcode: 'KX1006',
  ),
  PosProduct(
    id: 'r7',
    name: 'Consultation',
    category: 'Services',
    mode: 'retail',
    price: 4500,
    stock: null,
    symbol: 'service',
  ),
  PosProduct(
    id: 'r8',
    name: 'Gift wrapping',
    category: 'Services',
    mode: 'retail',
    price: 500,
    stock: null,
    symbol: 'gift',
  ),
  PosProduct(
    id: 'f1',
    name: 'House burger',
    category: 'Kitchen',
    mode: 'restaurant',
    price: 1450,
    stock: 30,
    symbol: 'burger',
    modifiers: {'Add cheese': 150, 'Add avocado': 250},
  ),
  PosProduct(
    id: 'f2',
    name: 'Garden bowl',
    category: 'Kitchen',
    mode: 'restaurant',
    price: 1250,
    stock: 20,
    symbol: 'salad',
    modifiers: {'Add chicken': 400, 'Extra dressing': 50},
  ),
  PosProduct(
    id: 'f3',
    name: 'Crispy fries',
    category: 'Sides',
    mode: 'restaurant',
    price: 500,
    stock: 40,
    symbol: 'fries',
    modifiers: {'Add cheese': 150},
  ),
  PosProduct(
    id: 'f4',
    name: 'Iced latte',
    category: 'Drinks',
    mode: 'restaurant',
    price: 550,
    stock: null,
    symbol: 'coffee',
    modifiers: {'Oat milk': 75, 'Extra shot': 100},
  ),
  PosProduct(
    id: 'f5',
    name: 'Mango smoothie',
    category: 'Drinks',
    mode: 'restaurant',
    price: 700,
    stock: 25,
    symbol: 'smoothie',
  ),
  PosProduct(
    id: 'f6',
    name: 'Chocolate brownie',
    category: 'Desserts',
    mode: 'restaurant',
    price: 450,
    stock: 14,
    symbol: 'cake',
  ),
  PosProduct(
    id: 'f7',
    name: 'Breakfast sandwich',
    category: 'Kitchen',
    mode: 'restaurant',
    price: 850,
    stock: 18,
    symbol: 'sandwich',
    modifiers: {'Add cheese': 150},
  ),
  PosProduct(
    id: 'f8',
    name: 'Sparkling water',
    category: 'Drinks',
    mode: 'restaurant',
    price: 300,
    stock: 36,
    symbol: 'water',
  ),
];

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pos_model.dart';

const _ink = Color(0xFF192F38),
    _teal = Color(0xFF087F75),
    _canvas = Color(0xFFF5F6F2),
    _orange = Color(0xFF9C4D20);
ThemeData posTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: _canvas,
  colorScheme: ColorScheme.fromSeed(seedColor: _teal),
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: _ink,
    displayColor: _ink,
  ),
  inputDecorationTheme: InputDecorationThemeData(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.all(15),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _teal,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

/// Shared practice UI. No live payment, authentication or production-data calls.
class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    this.workspace,
    this.embedded = false,
    this.sessionChanges,
  });
  final PosWorkspace? workspace;
  final bool embedded;
  final Listenable? sessionChanges;
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  PosWorkspace? _model;
  String? _error;
  bool _closed = false, _showCart = false;
  int _page = 0;
  String _category = 'All', _search = '';
  final _searchField = TextEditingController();
  PosWorkspace get w => _model!;
  static const _labels = [
    'Register',
    'Orders',
    'Kitchen',
    'Inventory',
    'Reports',
  ];
  static const _icons = [
    Icons.point_of_sale_rounded,
    Icons.receipt_long_rounded,
    Icons.soup_kitchen_rounded,
    Icons.inventory_2_outlined,
    Icons.bar_chart_rounded,
  ];
  @override
  void initState() {
    super.initState();
    widget.sessionChanges?.addListener(_sessionChanged);
    unawaited(_load());
  }

  void _sessionChanged() {
    if (mounted) setState(() => _closed = true);
  }

  Future<void> _load() async {
    try {
      if (widget.workspace != null) {
        _model = widget.workspace;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final key = widget.embedded
            ? 'korlix_pos_embedded_practice_v1'
            : 'korlix_pos_practice_v1';
        final model = PosWorkspace(
          save: (raw) async {
            if (!await prefs.setString(key, raw)) {
              throw StateError('Practice data could not be saved.');
            }
          },
        );
        final raw = prefs.getString(key);
        if (raw != null) model.restore(raw);
        _model = model;
      }
      _model!.addListener(_changed);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your saved practice workspace could not be opened. The saved data has been kept.',
        );
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.sessionChanges?.removeListener(_sessionChanged);
    _model?.removeListener(_changed);
    if (widget.workspace == null) _model?.dispose();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (w.busy || _closed) return;
    try {
      await action();
    } catch (e) {
      if (mounted) {
        _message(
          e is FormatException
              ? e.message
              : e.toString().replaceFirst(
                  RegExp(r'^(Bad state|Invalid argument\(s\)): '),
                  '',
                ),
        );
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void _nav(int n) => setState(() {
    _page = n;
    _showCart = false;
  });
  @override
  Widget build(BuildContext context) {
    if (_closed) {
      return const Scaffold(
        body: Center(
          child: Text('Your KORLIX session changed. Close and reopen POS.'),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!),
          ),
        ),
      );
    }
    if (_model == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Theme(
      data: posTheme(),
      child: LayoutBuilder(
        builder: (context, b) {
          final wide = b.maxWidth >= 1050 && b.maxHeight >= 650;
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  if (wide) _rail(),
                  Expanded(
                    child: Column(
                      children: [
                        _header(b.maxWidth),
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFFFF0D4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 9,
                          ),
                          child: const Text(
                            'PRACTICE WORKSPACE · Sample data, saved on this device. No real payments or cloud sync.',
                            style: TextStyle(
                              color: Color(0xFF765013),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(b.maxWidth < 650 ? 12 : 22),
                            child: LayoutBuilder(
                              builder: (context, space) {
                                final view = switch (_page) {
                                  0 => _register(space.maxWidth),
                                  1 => _orders(),
                                  2 => _kitchen(),
                                  3 => _inventory(),
                                  _ => _reports(),
                                };
                                return space.maxHeight < 400
                                    ? SingleChildScrollView(
                                        child: SizedBox(
                                          height: 650,
                                          child: view,
                                        ),
                                      )
                                    : view;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _page,
                    onDestinationSelected: _nav,
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationDestination(
                          icon: Icon(_icons[i]),
                          label: _labels[i],
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _rail() => Container(
    width: 100,
    color: _ink,
    child: Column(
      children: [
        const SizedBox(height: 26),
        const Icon(Icons.hub_rounded, color: Color(0xFF9DE5CF), size: 34),
        const SizedBox(height: 8),
        const Text(
          'KORLIX',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < _labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Material(
              color: _page == i ? const Color(0xFF31535B) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => _nav(i),
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      children: [
                        Icon(_icons[i], color: Colors.white),
                        const SizedBox(height: 6),
                        Text(
                          _labels[i],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        IconButton(
          tooltip: 'Workspace settings',
          onPressed: _settings,
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 22, top: 8),
          child: Text(
            'POS / 0.1',
            style: TextStyle(color: Color(0xFFCEDFE2), fontSize: 11),
          ),
        ),
      ],
    ),
  );
  Widget _header(double width) {
    final compact = MediaQuery.sizeOf(context).height < 500;
    final identity = Row(
      children: [
        if (widget.embedded)
          IconButton(
            tooltip: 'Back to KORLIX AI',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/korlix_logo.png',
            package: 'korlix_pos_core',
            width: 44,
            height: 44,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'KORLIX POS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
              Text(
                widget.embedded
                    ? 'Inside KORLIX AI'
                    : 'One counter. More possibilities.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF617575)),
              ),
            ],
          ),
        ),
      ],
    );
    Future<void> choose(String mode) => _run(() async {
      await w.switchMode(mode);
      setState(() {
        _category = 'All';
        _search = '';
        _searchField.clear();
        _showCart = false;
      });
    });
    final modes = SegmentedButton<String>(
      showSelectedIcon: false,
      selected: {w.mode},
      onSelectionChanged: w.busy ? null : (s) => choose(s.first),
      segments: const [
        ButtonSegment(
          value: 'retail',
          icon: Icon(Icons.storefront_rounded, size: 18),
          label: Text('Retail & services'),
        ),
        ButtonSegment(
          value: 'restaurant',
          icon: Icon(Icons.restaurant_rounded, size: 18),
          label: Text('Restaurant'),
        ),
      ],
    );
    final settings = IconButton(
      tooltip: 'Workspace settings',
      onPressed: _settings,
      icon: const Icon(Icons.settings_outlined),
    );
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: compact ? 8 : 16),
      child: compact
          ? Row(
              children: [
                Expanded(child: identity),
                PopupMenuButton<String>(
                  tooltip: 'Business mode',
                  onSelected: choose,
                  icon: Icon(
                    w.mode == 'retail' ? Icons.storefront : Icons.restaurant,
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'retail',
                      child: Text('Retail & services'),
                    ),
                    PopupMenuItem(
                      value: 'restaurant',
                      child: Text('Restaurant'),
                    ),
                  ],
                ),
                settings,
              ],
            )
          : width < 1100
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: identity),
                    settings,
                  ],
                ),
                const SizedBox(height: 12),
                modes,
              ],
            )
          : Row(
              children: [
                Expanded(child: identity),
                modes,
                const SizedBox(width: 15),
                settings,
              ],
            ),
    );
  }

  Widget _register(double width) {
    if (width < 860) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _showCart ? 'Current sale' : 'Make every sale count.',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showCart = !_showCart),
                icon: Icon(
                  _showCart ? Icons.storefront : Icons.shopping_bag_outlined,
                ),
                label: Text(_showCart ? 'Items' : 'Cart (${w.units})'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _showCart ? _cart() : _catalog()),
          if (!_showCart && w.units > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => setState(() => _showCart = true),
                  child: Text(
                    'View cart · ${w.units} items · ${posMoney(w.totals.total)}',
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Make every sale count.',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 22),
                child: Text(
                  w.mode == 'retail'
                      ? 'Your products, your service, your next happy customer.'
                      : 'From the first order to the final plate.',
                  style: const TextStyle(color: Color(0xFF627676)),
                ),
              ),
              Expanded(child: _catalog()),
            ],
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(width: width > 1150 ? 390 : 340, child: _cart()),
      ],
    );
  }

  Widget _catalog() {
    final products = w.products.where((p) => p.mode == w.mode).toList();
    final categories = ['All', ...products.map((p) => p.category).toSet()];
    final filtered = products
        .where(
          (p) =>
              (_category == 'All' || p.category == _category) &&
              '${p.name} ${p.category} ${p.barcode}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchField,
          onChanged: (v) => setState(() => _search = v),
          onSubmitted: (_) {
            final found = products.where(
              (p) =>
                  p.barcode.isNotEmpty &&
                  p.barcode.toLowerCase() == _search.trim().toLowerCase(),
            );
            if (found.length == 1) unawaited(_add(found.first));
          },
          decoration: InputDecoration(
            hintText: 'Search items or scan a barcode',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchField.clear();
                setState(() => _search = '');
              },
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    showCheckmark: false,
                    selectedColor: const Color(0xFFD5ECE4),
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? _empty(
                  Icons.search_off,
                  'No matching items',
                  'Try a different search or category.',
                )
              : LayoutBuilder(
                  builder: (context, b) => GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: b.maxWidth < 440
                          ? 2
                          : b.maxWidth < 740
                          ? 3
                          : 4,
                      mainAxisExtent: 218,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _tile(filtered[i], i),
                  ),
                ),
        ),
      ],
    );
  }

  IconData _icon(String symbol) => switch (symbol) {
    'tote' => Icons.shopping_bag_outlined,
    'shirt' => Icons.checkroom_rounded,
    'cup' => Icons.coffee_outlined,
    'book' => Icons.menu_book_rounded,
    'cap' => Icons.sports_baseball_outlined,
    'candle' => Icons.local_fire_department_outlined,
    'service' => Icons.handshake_outlined,
    'gift' => Icons.redeem_rounded,
    'burger' => Icons.lunch_dining_rounded,
    'salad' => Icons.eco_outlined,
    'fries' => Icons.fastfood_outlined,
    'coffee' => Icons.local_cafe_outlined,
    'smoothie' => Icons.local_drink_outlined,
    'cake' => Icons.cake_outlined,
    'sandwich' => Icons.breakfast_dining_rounded,
    'water' => Icons.water_drop_outlined,
    _ => Icons.category_outlined,
  };
  Widget _tile(PosProduct p, int i) {
    const colors = [
      Color(0xFFE6E0F2),
      Color(0xFFF8E6D7),
      Color(0xFFD9EAE4),
      Color(0xFFF1E9CF),
      Color(0xFFDAE7F2),
      Color(0xFFF3DFE5),
    ];
    final stock = w.available(p.id);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: w.busy ? null : () => _add(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length],
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(_icon(p.symbol), size: 52, color: _ink),
                      ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.stock == null
                                ? 'UNTRACKED'
                                : stock == 0
                                ? 'SOLD OUT'
                                : '$stock LEFT',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: stock <= 5 ? _orange : _ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                p.category,
                style: const TextStyle(fontSize: 11, color: Color(0xFF667978)),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      posMoney(p.price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(PosProduct p) async {
    List<String> modifiers = [];
    if (p.modifiers.isNotEmpty) {
      final chosen = <String>{};
      final selected = await showDialog<List<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(p.name),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Starting at ${posMoney(p.price)}'),
                  const SizedBox(height: 12),
                  for (final m in p.modifiers.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.key),
                      subtitle: Text('+${posMoney(m.value)}'),
                      value: chosen.contains(m.key),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          chosen.add(m.key);
                        } else {
                          chosen.remove(m.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, chosen.toList()),
                child: const Text('Add to order'),
              ),
            ],
          ),
        ),
      );
      if (selected == null) return;
      modifiers = selected;
    }
    await _run(() => w.add(p.id, modifiers));
  }

  Widget _cart() => _panel(
    SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current sale',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: w.cart.isEmpty || w.busy
                    ? null
                    : () => _run(w.clearCart),
                child: const Text('Clear'),
              ),
            ],
          ),
          Text(
            '${w.units} ${w.units == 1 ? 'item' : 'items'} · ${w.mode == 'retail' ? 'Counter sale' : 'Restaurant order'}',
            style: const TextStyle(color: Color(0xFF687A78), fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (w.mode == 'restaurant') ...[
            SegmentedButton<String>(
              selected: {w.fulfilment},
              onSelectionChanged: w.busy
                  ? null
                  : (s) => _run(() => w.configure(service: s.first)),
              segments: const [
                ButtonSegment(value: 'Takeaway', label: Text('Takeaway')),
                ButtonSegment(value: 'Dine-in', label: Text('Dine-in')),
              ],
            ),
            if (w.fulfilment == 'Dine-in')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('table-${w.table}'),
                  initialValue: w.table.isEmpty ? null : w.table,
                  decoration: const InputDecoration(labelText: 'Table'),
                  items: [
                    for (var i = 1; i <= 12; i++)
                      DropdownMenuItem(
                        value: 'Table $i',
                        child: Text('Table $i'),
                      ),
                  ],
                  onChanged: w.busy
                      ? null
                      : (v) => _run(() => w.configure(tableName: v)),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (w.cart.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: _empty(
                Icons.shopping_bag_outlined,
                'Ready when you are',
                'Tap an item to start this sale.',
              ),
            ),
          for (final l in w.cart)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        posMoney(l.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  if (l.modifiers.isNotEmpty)
                    Text(
                      l.modifiers.join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF667978),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '${posMoney(l.price)} each',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Decrease ${l.name}',
                        visualDensity: VisualDensity.compact,
                        onPressed: w.busy
                            ? null
                            : () =>
                                  _run(() => w.quantity(l.key, l.quantity - 1)),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      Text(
                        '${l.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        tooltip: 'Increase ${l.name}',
                        visualDensity: VisualDensity.compact,
                        onPressed: w.busy
                            ? null
                            : () =>
                                  _run(() => w.quantity(l.key, l.quantity + 1)),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (w.cart.isNotEmpty)
            TextButton.icon(
              onPressed: _note,
              icon: const Icon(Icons.edit_note),
              label: Text(
                w.note.isEmpty ? 'Add an order note' : w.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Divider(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PopupMenuButton<int>(
                tooltip: 'Order discount',
                onSelected: (v) => _run(() => w.configure(discount: v)),
                itemBuilder: (_) => [
                  for (final n in [0, 500, 1000, 1500, 2000])
                    PopupMenuItem(
                      value: n,
                      child: Text('${n ~/ 100}% discount'),
                    ),
                ],
                child: _pill(
                  'Discount ${w.discountBps ~/ 100}%',
                  Icons.local_offer_outlined,
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Sample tax rate',
                onSelected: (v) => _run(() => w.configure(tax: v)),
                itemBuilder: (_) => [
                  for (final n in [0, 500, 800, 1000])
                    PopupMenuItem(
                      value: n,
                      child: Text('${n ~/ 100}% sample tax'),
                    ),
                ],
                child: _pill('Sample tax ${w.taxBps / 100}%', Icons.percent),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _amount('Subtotal', w.totals.subtotal),
          if (w.totals.discount > 0) _amount('Discount', -w.totals.discount),
          _amount('Sample tax', w.totals.tax),
          const Divider(height: 24),
          _amount('Total due', w.totals.total, strong: true),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: w.cart.isEmpty || w.busy ? null : () => _checkout(),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Practice cash checkout'),
          ),
          if (w.mode == 'restaurant')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: w.cart.isEmpty || w.busy
                    ? null
                    : () => _run(() async {
                        final o = await w.sendToKitchen();
                        _message(
                          '${o.id} sent to the practice kitchen. Payment is still due.',
                        );
                      }),
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('Send to kitchen · pay later'),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Card payments and live receipts connect during merchant setup.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF657673)),
          ),
        ],
      ),
    ),
  );
  Widget _pill(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
    decoration: BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
  Widget _amount(String label, int amount, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: strong ? 19 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          posMoney(amount),
          style: TextStyle(
            fontSize: strong ? 27 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
  Future<void> _note() async {
    final c = TextEditingController(text: w.note);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order note'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Preparation or customer request',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    if (value != null) await _run(() => w.configure(orderNote: value));
  }

  Future<void> _checkout([PosOrder? order]) async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _CashDialog(
        total: (order?.totals ?? w.totals).total,
        restaurant: (order?.mode ?? w.mode) == 'restaurant',
      ),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      final saved = await w.checkout(
        cash: result.$1,
        tip: result.$2,
        orderId: order?.id,
      );
      if (mounted) {
        setState(() => _showCart = false);
        await _receipt(saved);
      }
    });
  }

  Future<void> _receipt(PosOrder o) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(o.status == 'paid' ? 'Practice sale saved' : o.id),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: SelectableText(
            w.receipt(o),
            style: const TextStyle(fontSize: 13, height: 1.65),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: w.receipt(o)));
            if (mounted) _message('Practice receipt copied.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy receipt'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  Widget _heading(String title, String detail, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: const TextStyle(fontSize: 12, color: Color(0xFF627676)),
        ),
        if (action != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: action,
            ),
          ),
      ],
    ),
  );
  Widget _orders() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Every order, in one place.',
        'Practice sales and open checks from both business modes.',
      ),
      Expanded(
        child: w.orders.isEmpty
            ? _empty(
                Icons.receipt_long_outlined,
                'Your first sale starts here',
                'Create a sale in Register to see its history.',
              )
            : ListView.separated(
                itemCount: w.orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final o = w.orders[i];
                  return _panel(
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o.id,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              _status(o.status),
                              const SizedBox(width: 12),
                              Text(
                                posMoney(o.totals.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${o.fulfilment}${o.table.isEmpty ? '' : ' · ${o.table}'} · ${o.lines.fold(0, (int n, l) => n + l.quantity)} items',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            o.lines
                                .map((l) => '${l.quantity} × ${l.name}')
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (o.note.isNotEmpty) Text('Note: ${o.note}'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _receipt(o),
                                icon: const Icon(
                                  Icons.receipt_outlined,
                                  size: 18,
                                ),
                                label: const Text('View receipt'),
                              ),
                              if (o.status == 'unpaid')
                                FilledButton(
                                  onPressed: w.busy ? null : () => _checkout(o),
                                  child: const Text('Collect practice cash'),
                                ),
                              if (['paid', 'unpaid'].contains(o.status))
                                TextButton(
                                  onPressed: w.busy ? null : () => _reverse(o),
                                  child: Text(
                                    o.status == 'paid'
                                        ? 'Refund'
                                        : 'Cancel order',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
  Widget _status(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: value == 'paid'
          ? const Color(0xFFDCEFE7)
          : value == 'unpaid'
          ? const Color(0xFFFFECCC)
          : const Color(0xFFE9E6F1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      value.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
  Future<void> _reverse(PosOrder o) async {
    final reason = TextEditingController();
    var restock = o.mode == 'retail';
    String? error;
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(o.status == 'paid' ? 'Refund ${o.id}' : 'Cancel ${o.id}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  o.status == 'paid'
                      ? 'Record a full practice cash refund of ${posMoney(o.totals.total)}.'
                      : 'Cancel this open check.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reason,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    errorText: error,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: restock,
                  onChanged: (v) => update(() => restock = v ?? false),
                  title: const Text('Return items to stock'),
                  subtitle: const Text(
                    'Leave off for prepared food or damaged goods.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 3) {
                  update(() => error = 'Enter a reason.');
                  return;
                }
                Navigator.pop(context, (reason.text, restock));
              },
              child: Text(
                o.status == 'paid' ? 'Record refund' : 'Cancel order',
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _run(() => w.reverse(o.id, reason: result.$1, restock: result.$2));
    }
  }

  Widget _kitchen() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Keep the kitchen moving.',
        'Queue → preparing → ready → served. Payment is tracked separately.',
      ),
      Expanded(
        child: w.kitchenOrders.isEmpty
            ? _empty(
                Icons.soup_kitchen_outlined,
                'A clear counter feels good',
                'Restaurant orders appear when sent or checked out.',
              )
            : LayoutBuilder(
                builder: (context, b) => GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: b.maxWidth < 600
                        ? 1
                        : b.maxWidth < 1000
                        ? 2
                        : 3,
                    mainAxisExtent: 340,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: w.kitchenOrders.length,
                  itemBuilder: (_, i) {
                    final o = w.kitchenOrders[i];
                    final next = switch (o.kitchen) {
                      'queued' => 'Start preparing',
                      'preparing' => 'Mark ready',
                      _ => 'Mark served',
                    };
                    return _panel(
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    o.table.isEmpty ? o.fulfilment : o.table,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                _status(o.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${o.id} · ${o.kitchen.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _orange,
                                fontSize: 12,
                              ),
                            ),
                            const Divider(height: 25),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final l in o.lines)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${l.quantity} × ${l.name}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (l.modifiers.isNotEmpty)
                                            Text(
                                              l.modifiers.join(' · '),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (o.note.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(9),
                                      color: const Color(0xFFFFF0D4),
                                      child: Text(o.note),
                                    ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: w.busy
                                  ? null
                                  : () => _run(() => w.advanceKitchen(o.id)),
                              child: Text(next),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    ],
  );
  Widget _inventory() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'A catalog that works for you.',
        'Sample products, menu items and services.',
        action: FilledButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: w.products.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = w.products[i];
            return _panel(
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: p.mode == 'retail'
                      ? const Color(0xFFE6E0F2)
                      : const Color(0xFFF8E6D7),
                  child: Icon(_icon(p.symbol), color: _ink),
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${p.mode} · ${p.category}\n${p.stock == null ? 'Stock not tracked' : '${p.stock} available'}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      posMoney(p.price),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      tooltip: 'Edit ${p.name}',
                      onPressed: () => _edit(p),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
  Future<void> _edit([PosProduct? p]) async {
    final name = TextEditingController(text: p?.name ?? ''),
        price = TextEditingController(
          text: ((p?.price ?? 0) / 100).toStringAsFixed(2),
        ),
        stock = TextEditingController(text: p?.stock?.toString() ?? ''),
        category = TextEditingController(text: p?.category ?? 'General'),
        barcode = TextEditingController(text: p?.barcode ?? '');
    var mode = p?.mode ?? w.mode;
    var tracked = p == null || p.stock != null;
    String? error;
    final result = await showDialog<PosProduct>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(p == null ? 'Add an item' : 'Edit ${p.name}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Item name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Price (USD)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: category,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: 'Business mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'retail',
                        child: Text('Retail & services'),
                      ),
                      DropdownMenuItem(
                        value: 'restaurant',
                        child: Text('Restaurant'),
                      ),
                    ],
                    onChanged: p == null
                        ? (v) => update(() => mode = v!)
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: tracked,
                    title: const Text('Track available stock'),
                    onChanged: (v) => update(() => tracked = v ?? false),
                  ),
                  if (tracked)
                    TextField(
                      controller: stock,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Available quantity',
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: barcode,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Barcode / SKU (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final qty = tracked ? int.tryParse(stock.text) : null;
                  if (name.text.trim().isEmpty ||
                      category.text.trim().isEmpty ||
                      (tracked && (qty == null || qty < 0))) {
                    throw const FormatException(
                      'Enter a name, category and valid stock quantity.',
                    );
                  }
                  Navigator.pop(
                    context,
                    PosProduct(
                      id:
                          p?.id ??
                          'custom-${DateTime.now().microsecondsSinceEpoch}',
                      name: name.text.trim(),
                      category: category.text.trim(),
                      mode: mode,
                      price: posParseMoney(price.text),
                      stock: qty,
                      symbol: p?.symbol ?? 'custom',
                      barcode: barcode.text.trim(),
                      modifiers: p?.modifiers ?? {},
                    ),
                  );
                } catch (e) {
                  update(
                    () => error = e is FormatException
                        ? e.message
                        : 'Check the values and try again.',
                  );
                }
              },
              child: const Text('Save item'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await _run(() => w.saveProduct(result));
  }

  Widget _reports() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Know how your day is going.',
          'Practice cash activity · this device’s calendar day',
          action: OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export CSV'),
          ),
        ),
        LayoutBuilder(
          builder: (context, b) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _metric(
                'Net cash today',
                posMoney(w.todayNetCash),
                Icons.account_balance_wallet_outlined,
                const Color(0xFFDCEFE7),
                b.maxWidth,
              ),
              _metric(
                'Practice sales today',
                '${w.todaySales.length}',
                Icons.receipt_long_outlined,
                const Color(0xFFE6E0F2),
                b.maxWidth,
              ),
              _metric(
                'Open checks',
                '${w.orders.where((o) => o.status == 'unpaid').length}',
                Icons.pending_actions,
                const Color(0xFFFFE8D1),
                b.maxWidth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _panel(
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cash movement',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                _amount('Collected today', w.todayCollected),
                _amount('Refunds recorded today', -w.todayReturned),
                const Divider(height: 28),
                _amount('Net cash today', w.todayNetCash, strong: true),
                const SizedBox(height: 16),
                const Text(
                  'Includes sample tax and tips. Refunds reduce cash on the refund date, even when the sale was earlier.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF627676)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _panel(
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock to watch',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                for (final p in w.products.where(
                  (p) => p.stock != null && p.stock! <= 5,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: _orange),
                        const SizedBox(width: 10),
                        Expanded(child: Text(p.name)),
                        Text(
                          '${p.stock} left',
                          style: const TextStyle(
                            color: _orange,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!w.products.any((p) => p.stock != null && p.stock! <= 5))
                  const Text('All tracked items are above five units.'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color color,
    double width,
  ) => SizedBox(
    width: width < 650 ? width : (width - 32) / 3,
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
  Future<void> _export() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Practice sales CSV'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: SelectableText(
            w.salesCsv(),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: w.salesCsv()));
            if (mounted) {
              _message('CSV copied. Paste it into a spreadsheet or .csv file.');
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy CSV'),
        ),
      ],
    ),
  );
  Future<void> _settings() async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your practice workspace'),
        content: const SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Text(
              'Try retail and restaurant workflows with sample data.\n\nPractice data stays on this device/browser. It is not a cloud backup or a multi-register store. Use one tab at a time.\n\nThe shared POS screen is prepared for the standalone app and the KORLIX AI Business section. Shared-account access, merchant payments, hardware printing, staff permissions and business-tool synchronization are the next integration stage.\n\nTax rates are examples you select; they are not calculated from a business address.\n\nReset removes this device’s practice orders and catalog edits.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset practice data'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to POS'),
          ),
        ],
      ),
    );
    if (reset == true && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset practice data?'),
          content: const Text(
            'All practice orders and catalog edits on this device will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep data'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _run(() async {
          await w.reset();
          setState(() {
            _category = 'All';
            _search = '';
            _searchField.clear();
            _showCart = false;
            _page = 0;
          });
        });
      }
    }
  }

  Widget _panel(Widget child) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDFE5DF)),
    ),
    child: child,
  );
  Widget _empty(IconData icon, String title, String detail) => Center(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 43, color: const Color(0xFF91ABA4)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF617575), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _CashDialog extends StatefulWidget {
  const _CashDialog({required this.total, required this.restaurant});
  final int total;
  final bool restaurant;
  @override
  State<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<_CashDialog> {
  late final cash = TextEditingController(
    text: (widget.total / 100).toStringAsFixed(2),
  );
  final tip = TextEditingController(text: '0.00');
  String? error;
  int get gratuity {
    try {
      return posParseMoney(tip.text);
    } catch (_) {
      return 0;
    }
  }

  int get due => widget.total + gratuity;
  @override
  void dispose() {
    cash.dispose();
    tip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Practice cash checkout'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No real payment is processed.',
              style: TextStyle(color: _orange, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Text(
              posMoney(due),
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
            ),
            const Text('Total due · USD'),
            const SizedBox(height: 22),
            if (widget.restaurant) ...[
              TextField(
                controller: tip,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Tip amount (USD)',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: cash,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Cash received (USD)',
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in <int>{
                  due,
                  ((due + 999) ~/ 1000) * 1000,
                  ((due + 1999) ~/ 2000) * 2000,
                })
                  ActionChip(
                    label: Text(amount == due ? 'Exact' : posMoney(amount)),
                    onPressed: () => setState(
                      () => cash.text = (amount / 100).toStringAsFixed(2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final received = posParseMoney(cash.text),
                extra = posParseMoney(tip.text);
            if (received < widget.total + extra) {
              throw const FormatException(
                'Cash received is less than the total due.',
              );
            }
            Navigator.pop(context, (received, extra));
          } catch (e) {
            setState(
              () => error = e is FormatException
                  ? e.message
                  : 'Enter valid amounts.',
            );
          }
        },
        child: const Text('Complete practice sale'),
      ),
    ],
  );
}

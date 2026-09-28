import 'dart:async';
import 'package:flutter/material.dart';
import 'inventory_client.dart';

Future<Map<String, dynamic>?> showInventoryOrder(
  BuildContext context, {
  required InventoryClient client,
  required List<Map<String, dynamic>> locations,
  required List<Map<String, dynamic>> partners,
  Map<String, dynamic>? initialItem,
  List<Map<String, dynamic>> initialStock = const [],
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _OrderForm(
    client: client,
    locations: locations,
    partners: partners,
    initialItem: initialItem,
    initialStock: initialStock,
  ),
);

class _OrderForm extends StatefulWidget {
  const _OrderForm({
    required this.client,
    required this.locations,
    required this.partners,
    this.initialItem,
    required this.initialStock,
  });
  final InventoryClient client;
  final List<Map<String, dynamic>> locations, partners, initialStock;
  final Map<String, dynamic>? initialItem;
  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _due = TextEditingController(),
      _notes = TextEditingController(),
      _query = TextEditingController(),
      _qty = TextEditingController(text: '1'),
      _price = TextEditingController(text: '0');
  final List<Map<String, dynamic>> _lines = [];
  List<Map<String, dynamic>> _matches = [], _stock = [];
  Map<String, dynamic> _item = {};
  String _type = 'purchase';
  String? _partner, _stockId, _error;
  bool _loading = false;
  int _epoch = 0;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _item = widget.initialItem ?? {};
    _stock = widget.initialStock;
    _stockId = _stock.isEmpty ? null : _stock.first['id'];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _due, _notes, _query, _qty, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  String _location(dynamic id) {
    for (final l in widget.locations) {
      if (l['id'] == id) return '${inventoryMap(l['data'])['name']}';
    }
    return 'Archived location';
  }

  Future<void> _search() async {
    final e = ++_epoch;
    setState(() => _loading = true);
    try {
      final r = await widget.client.search({
        'q': _query.text,
        'scope': 'international',
      });
      if (mounted && e == _epoch) {
        setState(() => _matches = inventoryItems(r['items']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && e == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _choose(Map<String, dynamic> p) async {
    final e = ++_epoch;
    setState(() => _loading = true);
    try {
      final d = await widget.client.item(p['id']);
      if (mounted && e == _epoch) {
        setState(() {
          _item = inventoryMap(d['item']);
          _stock = inventoryItems(d['stock']);
          _stockId = _stock.isEmpty ? null : _stock.first['id'];
          _matches = [];
          _query.clear();
          _price.text = '${inventoryMap(_item['data'])['price'] ?? 0}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && e == _epoch) setState(() => _loading = false);
    }
  }

  void _add() {
    final qty = double.tryParse(_qty.text),
        price = double.tryParse(_price.text);
    if (_stockId == null ||
        qty == null ||
        !qty.isFinite ||
        qty <= 0 ||
        price == null ||
        !price.isFinite ||
        price < 0) {
      setState(
        () => _error =
            'Choose a stock position, positive quantity and nonnegative price.',
      );
      return;
    }
    if (_lines.length >= 100) {
      setState(() => _error = 'An order can contain up to 100 lines.');
      return;
    }
    final d = inventoryMap(_item['data']);
    if (_lines.isNotEmpty && _lines.first['currency'] != d['currency']) {
      setState(() => _error = 'Use a separate order for each currency.');
      return;
    }
    setState(() {
      _lines.add({
        'stock_id': _stockId,
        'quantity': qty,
        'unit_price': price,
        'name': d['name'],
        'sku': d['sku'],
        'currency': d['currency'],
        'location': _location(
          _stock.firstWhere((s) => s['id'] == _stockId)['location_id'],
        ),
      });
      _error = null;
    });
  }

  Widget _input(
    TextEditingController c,
    String label, {
    bool required = false,
    bool number = false,
  }) => TextFormField(
    controller: c,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (v) =>
        required && (v ?? '').trim().isEmpty ? 'Enter $label' : null,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create a purchase or sales order'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Save a draft, then open it. Sales reserve stock. Purchases add stock when received.',
              ),
              const SizedBox(height: 18),
              _input(_name, 'Order name / number', required: true),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Order type'),
                items: const [
                  DropdownMenuItem(
                    value: 'purchase',
                    child: Text('Purchase order'),
                  ),
                  DropdownMenuItem(value: 'sale', child: Text('Sales order')),
                ],
                onChanged: (v) => setState(() {
                  _type = v!;
                  _partner = null;
                }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('partner-$_type'),
                initialValue: _partner,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _type == 'purchase' ? 'Supplier' : 'Customer',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No contact selected'),
                  ),
                  for (final p in widget.partners.where(
                    (p) =>
                        inventoryMap(p['data'])['type'] ==
                        (_type == 'purchase' ? 'supplier' : 'customer'),
                  ))
                    DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        '${inventoryMap(p['data'])['name']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _partner = v),
              ),
              const SizedBox(height: 14),
              _input(_due, 'Due date (YYYY-MM-DD)'),
              const SizedBox(height: 24),
              Text(
                'Order lines · ${_lines.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (var i = 0; i < _lines.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_lines[i]['name']}'),
                  subtitle: Text(
                    '${_lines[i]['location']} · ${inventoryQuantity(_lines[i]['quantity'])} × ${_lines[i]['currency']} ${inventoryQuantity(_lines[i]['unit_price'])}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove line ${i + 1}',
                    onPressed: () => setState(() => _lines.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (_lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Total ${_lines.first['currency']} ${_lines.fold<double>(0, (sum, l) => sum + inventoryNumber(l['quantity']) * inventoryNumber(l['unit_price'])).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              const Divider(height: 26),
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  labelText: 'Find another item by name or SKU',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _search);
                },
                onSubmitted: (_) => _search(),
              ),
              if (_loading) const LinearProgressIndicator(),
              for (final p in _matches.take(10))
                ListTile(
                  title: Text('${inventoryMap(p['data'])['name']}'),
                  subtitle: Text('${inventoryMap(p['data'])['sku']}'),
                  onTap: () => _choose(p),
                ),
              if (_item.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '${inventoryMap(_item['data'])['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_stock.isEmpty)
                  const Text(
                    'Add a stock position to this item before ordering it.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('stock-${_item['id']}'),
                    initialValue: _stockId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Stock position',
                    ),
                    items: _stock
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(
                              '${_location(s['location_id'])} · ${s['serial'] ?? ''} ${s['batch'] ?? ''} · ${inventoryQuantity(s['quantity'])} on hand',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _stockId = v),
                  ),
                  const SizedBox(height: 14),
                  _input(_qty, 'Quantity', number: true),
                  const SizedBox(height: 14),
                  _input(
                    _price,
                    'Unit price / purchase cost (${inventoryMap(_item['data'])['currency']})',
                    number: true,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add to order'),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              _input(_notes, 'Notes / reference'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading
            ? null
            : () {
                if (!_form.currentState!.validate()) return;
                if (_lines.isEmpty) {
                  setState(() => _error = 'Add at least one order line.');
                  return;
                }
                Navigator.pop(context, {
                  'name': _name.text.trim(),
                  'type': _type,
                  'partner_id': _partner,
                  'due': _due.text.trim(),
                  'notes': _notes.text.trim(),
                  'lines': _lines
                      .map(
                        (l) => {
                          'stock_id': l['stock_id'],
                          'quantity': l['quantity'],
                          'unit_price': l['unit_price'],
                        },
                      )
                      .toList(),
                });
              },
        child: const Text('Save draft'),
      ),
    ],
  );
}

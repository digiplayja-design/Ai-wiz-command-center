import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'inventory_client.dart';
import 'inventory_form.dart';
import 'inventory_art.dart';
import 'inventory_order_form.dart';
part 'inventory_views.dart';

typedef InventorySearch =
    Future<Map<String, dynamic>> Function(Map<String, dynamic>);
typedef InventoryVoiceLauncher =
    Future<void> Function(
      InventorySearch,
      Widget Function(Map<String, dynamic>, Future<bool> Function()),
    );

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    required this.openVoice,
    this.saveFile = saveBookkeepingFile,
  });
  final InventoryClient client;
  final Future<bool> Function(BuildContext) ensureConsent;
  final InventoryVoiceLauncher openVoice;
  final Future<void> Function(Uint8List, String, String, Rect) saveFile;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _query = TextEditingController();
  Map<String, dynamic> _workspace = {}, _results = {}, _detail = {}, _scan = {};
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _pending;
  String _tab = 'discover',
      _scope = 'international',
      _country = '',
      _region = '',
      _filter = 'all';
  String? _error, _notice;
  bool _busy = false, _loading = true, _locked = false, _dialog = false;
  int _searchGeneration = 0;
  Timer? _debounce, _scanTimer;
  void _update(VoidCallback action) {
    if (mounted) setState(action);
  }

  bool get blocked => _busy || _locked || _loading;
  bool get editable => !blocked && _pending == null;
  List<Map<String, dynamic>> get locations =>
      inventoryItems(_workspace['locations']);
  List<Map<String, dynamic>> get partners =>
      inventoryItems(_workspace['partners']);
  List<Map<String, dynamic>> get orders => inventoryItems(_workspace['orders']);
  Map<String, dynamic> get item => inventoryMap(_detail['item']);
  List<Map<String, dynamic>> get stock => inventoryItems(_detail['stock']);
  Map<String, dynamic> get filters => {
    'q': _query.text,
    'scope': _scope,
    'country': _country,
    'region': _region,
    'filter': _filter,
  };
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scanTimer?.cancel();
    _query.dispose();
    widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted || _locked) return;
    _debounce?.cancel();
    _scanTimer?.cancel();
    _query.clear();
    _searchGeneration++;
    if (_dialog) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _workspace = {};
      _results = {};
      _detail = {};
      _scan = {};
      _events = [];
      _pending = null;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _work(Future<void> Function() job) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (_locked) return;
    try {
      final w = await widget.client.workspace();
      if (!mounted || _locked) return;
      setState(() {
        _workspace = w;
        _country = _country.isEmpty && locations.isNotEmpty
            ? inventoryMap(locations.first['data'])['country'] ?? ''
            : _country;
      });
      await _search();
      if (_detail.isNotEmpty) {
        final d = await widget.client.item(item['id']);
        if (mounted && !_locked) setState(() => _detail = d);
      }
      if (_tab == 'activity') await _loadEvents();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _search({
    Map<String, dynamic>? voice,
    int offset = 0,
    bool append = false,
  }) async {
    final epoch = ++_searchGeneration;
    final f = voice == null
        ? {...filters, 'offset': offset}
        : {...filters, ...voice, 'offset': 0};
    final result = await widget.client.search(f);
    if (!mounted || _locked || epoch != _searchGeneration) {
      return {'items': [], 'total': 0, 'discarded': true};
    }
    setState(() {
      if (voice != null) {
        _query.text = '${f['q'] ?? ''}';
        _scope = '${f['scope']}';
        _country = '${f['country'] ?? ''}';
        _region = '${f['region'] ?? ''}';
        _filter = '${f['filter']}';
        _tab = 'discover';
        _detail = {};
      }
      _results = {
        ...result,
        'items': append
            ? [
                ...inventoryItems(_results['items']),
                ...inventoryItems(result['items']),
              ]
            : result['items'],
      };
    });
    return result;
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !_locked) {
        _search().catchError((Object e) {
          if (mounted && !_locked) setState(() => _error = e.toString());
          return <String, dynamic>{};
        });
      }
    });
  }

  Future<void> _change(Map<String, dynamic> body) async {
    _pending ??= {'request_key': inventoryRequestKey(), ...body};
    try {
      await widget.client.change(_pending!);
      if (_pending!['action'] == 'archive' && _pending!['id'] == item['id']) {
        _detail = {};
      }
      _pending = null;
      await _load();
      if (mounted && !_locked) {
        setState(() => _notice = 'Saved to your inventory.');
      }
    } on InventoryException catch (e) {
      if (e.status >= 400 && e.status < 500) _pending = null;
      rethrow;
    }
  }

  Future<Map<String, String>?> _form(
    String title,
    List<InventoryField> fields, {
    String submit = 'Save',
    String? note,
  }) async {
    if (!editable) return null;
    _dialog = true;
    try {
      return await showInventoryForm(
        context,
        title: title,
        fields: fields,
        submit: submit,
        note: note,
      );
    } finally {
      _dialog = false;
    }
  }

  Future<void> _editProduct([Map<String, dynamic>? existing]) async {
    final d = inventoryMap(existing?['data']);
    String val(String k, [String fallback = '']) => '${d[k] ?? fallback}';
    final f = await _form(
      existing == null ? 'Add an item' : 'Edit item',
      [
        InventoryField(
          'name',
          'Item name',
          initial: val('name'),
          required: true,
        ),
        InventoryField(
          'sku',
          'SKU / item code',
          initial: val('sku'),
          required: true,
        ),
        InventoryField('barcode', 'Barcode', initial: val('barcode')),
        InventoryField('brand', 'Brand', initial: val('brand')),
        InventoryField('category', 'Category', initial: val('category')),
        InventoryField(
          'aliases',
          'Other names / search words',
          initial: val('aliases'),
        ),
        InventoryField(
          'unit',
          'Unit of measure',
          initial: val('unit', 'each'),
          required: true,
        ),
        InventoryField(
          'currency',
          'Currency (USD, JMD, EUR…)',
          initial: val('currency', 'USD'),
          required: true,
        ),
        InventoryField(
          'price',
          'Selling price',
          initial: val('price', '0'),
          numeric: true,
        ),
        InventoryField(
          'reorder',
          'Low-stock threshold',
          initial: val('reorder', '0'),
          numeric: true,
        ),
        InventoryField(
          'tracking',
          'Tracking',
          initial: val('tracking', 'bulk'),
          options: const {
            'bulk': 'Quantity / bulk',
            'serial': 'Individual serial numbers',
            'batch': 'Batches / lots',
          },
          required: true,
        ),
        InventoryField(
          'description',
          'Description',
          initial: val('description'),
          lines: 3,
        ),
      ],
      note:
          'Add the item first, then choose a location and receive its opening stock.',
    );
    if (f == null || !mounted || _locked) return;
    await _work(() async {
      await _change({
        'action': 'save',
        'kind': 'product',
        'id': existing?['id'] ?? inventoryRequestKey(),
        'revision': existing?['revision'] ?? 0,
        'value': {
          ...f,
          'price': double.parse(f['price']!),
          'reorder': double.parse(f['reorder']!),
        },
      });
    });
  }

  Future<void> _editLocation([Map<String, dynamic>? existing]) async {
    final d = inventoryMap(existing?['data']);
    final f = await _form(
      existing == null ? 'Add a location' : 'Edit location',
      [
        InventoryField(
          'name',
          'Location name',
          initial: d['name'] ?? '',
          required: true,
        ),
        InventoryField('city', 'City', initial: d['city'] ?? ''),
        InventoryField(
          'region',
          'State / province',
          initial: d['region'] ?? '',
          required: true,
        ),
        InventoryField(
          'country',
          'Country code (US, JM, GB…)',
          initial: d['country'] ?? 'US',
          required: true,
        ),
        InventoryField(
          'address',
          'Address',
          initial: d['address'] ?? '',
          lines: 2,
        ),
      ],
      note:
          'Warehouses, stores, vehicles and storage rooms can each be a location.',
    );
    if (f == null || !mounted || _locked) return;
    await _work(
      () => _change({
        'action': 'save',
        'kind': 'location',
        'id': existing?['id'] ?? inventoryRequestKey(),
        'revision': existing?['revision'] ?? 0,
        'value': f,
      }),
    );
  }

  Future<void> _editPartner([Map<String, dynamic>? existing]) async {
    final d = inventoryMap(existing?['data']);
    final f = await _form(existing == null ? 'Add a contact' : 'Edit contact', [
      InventoryField(
        'name',
        'Name / company',
        initial: d['name'] ?? '',
        required: true,
      ),
      InventoryField(
        'type',
        'Contact type',
        initial: d['type'] ?? 'supplier',
        options: const {'supplier': 'Supplier', 'customer': 'Customer'},
        required: true,
      ),
      InventoryField('email', 'Email', initial: d['email'] ?? ''),
      InventoryField('phone', 'Phone', initial: d['phone'] ?? ''),
      InventoryField('notes', 'Notes', initial: d['notes'] ?? '', lines: 3),
    ]);
    if (f == null || !mounted || _locked) return;
    await _work(
      () => _change({
        'action': 'save',
        'kind': 'partner',
        'id': existing?['id'] ?? inventoryRequestKey(),
        'revision': existing?['revision'] ?? 0,
        'value': f,
      }),
    );
  }

  Future<void> _openItem(String id) async => _work(() async {
    final d = await widget.client.item(id);
    if (mounted && !_locked) {
      setState(() {
        _detail = d;
        _tab = 'discover';
      });
    }
  });
  Future<void> _addStock() async {
    if (locations.isEmpty) {
      setState(() => _notice = 'Add a location before receiving stock.');
      return;
    }
    final d = inventoryMap(item['data']);
    final f = await _form(
      'Add a stock position',
      [
        InventoryField(
          'location_id',
          'Location',
          options: {
            for (final l in locations)
              l['id']: inventoryMap(l['data'])['name'] ?? '',
          },
          required: true,
        ),
        const InventoryField('bin', 'Bin / shelf'),
        if (d['tracking'] == 'serial')
          InventoryField(
            'serial',
            'Serial number',
            initial: '${inventoryMap(_scan['result'])['serial'] ?? ''}',
            required: true,
          ),
        if (d['tracking'] == 'batch')
          const InventoryField('batch', 'Batch / lot', required: true),
        const InventoryField('expiry', 'Expiry (YYYY-MM-DD)'),
        const InventoryField(
          'unit_cost',
          'Unit cost',
          initial: '0',
          numeric: true,
        ),
      ],
      note:
          'Creates a zero-quantity position. Use Receive to add stock with an audit record.',
    );
    if (f == null || !mounted || _locked) return;
    await _work(
      () => _change({
        'action': 'stock',
        'id': inventoryRequestKey(),
        'product_id': item['id'],
        ...f,
        'unit_cost': double.parse(f['unit_cost']!),
      }),
    );
  }

  Future<void> _move(Map<String, dynamic> s) async {
    final f = await _form(
      'Update stock',
      [
        const InventoryField(
          'kind',
          'Action',
          initial: 'receive',
          options: {
            'receive': 'Receive stock',
            'issue': 'Issue / use stock',
            'transfer': 'Transfer to another location',
            'count': 'Record physical count',
            'return_in': 'Customer return',
            'return_out': 'Return to supplier',
          },
          required: true,
        ),
        InventoryField(
          'quantity',
          'Quantity / counted quantity',
          initial: '1',
          numeric: true,
        ),
        InventoryField(
          'unit_cost',
          'Cost per received unit',
          initial: '${s['unit_cost'] ?? 0}',
          numeric: true,
        ),
        InventoryField(
          'target_location_id',
          'Transfer destination',
          options: {
            '': 'Only for transfers',
            for (final l in locations)
              if (l['id'] != s['location_id'])
                l['id']: inventoryMap(l['data'])['name'] ?? '',
          },
        ),
        const InventoryField('reference', 'Reference / delivery number'),
        const InventoryField('note', 'Reason / note', required: true, lines: 2),
      ],
      note:
          'Available: ${inventoryQuantity(inventoryNumber(s['quantity']) - inventoryNumber(s['reserved']))}. Transfers conserve stock. Counts replace the on-hand quantity.',
    );
    if (f == null || !mounted || _locked) return;
    await _work(
      () => _change({
        'action': 'move',
        'id': s['id'],
        'revision': s['revision'],
        ...f,
        'quantity': double.parse(f['quantity']!),
        'unit_cost': double.parse(f['unit_cost']!),
        'target_id': inventoryRequestKey(),
      }),
    );
  }

  Future<void> _archive(Map<String, dynamic> record) async {
    if (!editable) return;
    _dialog = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive this record?'),
        content: const Text(
          'It will leave active lists. Stock and audit history are retained. Stocked items and open orders cannot be archived.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    _dialog = false;
    if (ok != true || !mounted || _locked) return;
    await _work(() async {
      await _change({
        'action': 'archive',
        'id': record['id'],
        'revision': record['revision'],
        'confirmed': true,
      });
      if (mounted && !_locked) setState(() => _detail = {});
    });
  }

  Future<({Uint8List bytes, String name})?> _picture({
    bool camera = false,
  }) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (x == null) return null;
    if (await x.length() > 8 * 1024 * 1024) {
      throw const InventoryException('Choose a picture up to 8 MB.');
    }
    return (bytes: await x.readAsBytes(), name: x.name);
  }

  Future<void> _productPhoto() async => _work(() async {
    final target = {...item};
    final file = await _picture();
    if (file == null || !mounted || _locked) return;
    await widget.client.upload(
      '/items/${target['id']}/photo',
      file.bytes,
      file.name,
      {'revision': '${target['revision']}'},
    );
    await _load();
  });
  Future<void> _recognize(String mode) async {
    if (!editable) return;
    _dialog = true;
    final source = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          mode == 'serial' ? 'Scan a serial label' : 'Find an item by picture',
        ),
        content: const Text(
          'KORLIX reads the picture with OpenAI for 1 generation credit. You can edit the detected words before searching. A failed scan returns the credit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(c, 'gallery'),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose photo'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, 'camera'),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Take photo'),
          ),
        ],
      ),
    );
    _dialog = false;
    if (source == null || !mounted || _locked) return;
    if (!await widget.ensureConsent(context) || !mounted || _locked) return;
    await _work(() async {
      final file = await _picture(camera: source == 'camera');
      if (file == null || !mounted || _locked) return;
      final id = inventoryRequestKey();
      setState(() => _scan = {'id': id, 'state': 'preparing', 'mode': mode});
      try {
        final r = await widget.client.upload('/vision', file.bytes, file.name, {
          'request_key': id,
          'mode': mode,
          'consent': 'true',
        });
        if (mounted && !_locked) {
          setState(() => _scan = inventoryMap(r['scan']));
        }
      } on InventoryException catch (e) {
        if (mounted && !_locked && e.status >= 400 && e.status < 500) {
          setState(
            () => _scan = {'id': id, 'state': 'failed', 'message': e.message},
          );
        }
        rethrow;
      } finally {
        if (mounted && !_locked) _startScanPolling();
      }
    });
  }

  void _startScanPolling() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_scan['state'] == 'preparing' && !_busy && !_locked) {
        _pollScan();
      } else if (_scan['state'] != 'preparing') {
        _scanTimer?.cancel();
      }
    });
  }

  bool _polling = false;
  Future<void> _pollScan() async {
    if (_polling) return;
    _polling = true;
    final id = _scan['id'];
    try {
      final r = await widget.client.scan(id);
      if (mounted && !_locked && _scan['id'] == id) {
        setState(() => _scan = inventoryMap(r['scan']));
      }
    } on InventoryException catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = e.toString();
          if (e.status == 404) {
            _scan = {
              'id': id,
              'state': 'failed',
              'message': 'This scan was not started. Please try again.',
            };
          }
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _voice() async {
    if (!editable) return;
    if (!await widget.ensureConsent(context) || !mounted || _locked) return;
    await widget.openVoice((args) => _search(voice: args), _voiceResults);
  }

  Future<void> _import() async => _work(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: false,
      withReadStream: true,
    );
    if (picked == null || !mounted || _locked) return;
    final file = picked.files.single;
    if (file.size > 500000) {
      throw const InventoryException('Choose a CSV up to 500 KB.');
    }
    final buffer = BytesBuilder();
    if (file.bytes != null) {
      buffer.add(file.bytes!);
    } else if (file.readStream != null) {
      await for (final b in file.readStream!) {
        buffer.add(b);
        if (buffer.length > 500000) {
          throw const InventoryException('CSV is too large.');
        }
      }
    } else {
      throw const InventoryException('This CSV could not be read.');
    }
    final products = await widget.client.importPreview(
      utf8.decode(buffer.takeBytes()),
    );
    if (!mounted || _locked) return;
    _dialog = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Import ${products.length} new items?'),
        content: SingleChildScrollView(
          child: Text(
            'Existing SKUs will be rejected. Stock stays unchanged.\n\n${products.take(8).map((p) => '${p['sku']} · ${p['name']}').join('\n')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Import items'),
          ),
        ],
      ),
    );
    _dialog = false;
    if (yes != true || !mounted || _locked) return;
    await _change({
      'action': 'import',
      'products': products
          .map((p) => {...p, 'id': inventoryRequestKey()})
          .toList(),
    });
  });
  Future<void> _export() async => _work(() async {
    final bytes = await widget.client.export();
    if (!mounted || _locked) return;
    await widget.saveFile(
      bytes,
      'KORLIX-Inventory.csv',
      'text/csv',
      const Rect.fromLTWH(0, 0, 40, 40),
    );
    if (mounted && !_locked) {
      setState(() => _notice = 'Inventory export prepared.');
    }
  });
  Future<void> _template() async => _work(() async {
    await widget.saveFile(
      Uint8List.fromList(
        utf8.encode(
          'name,sku,barcode,brand,category,unit,currency,price,reorder,tracking,aliases,description\r\n',
        ),
      ),
      'KORLIX-Inventory-Import.csv',
      'text/csv',
      const Rect.fromLTWH(0, 0, 40, 40),
    );
  });
  Future<void> _loadEvents() async {
    final r = await widget.client.events();
    if (mounted && !_locked) {
      setState(() => _events = inventoryItems(r['events']));
    }
  }

  Future<void> _newOrder() async {
    if (!editable) return;
    _dialog = true;
    Map<String, dynamic>? value;
    try {
      value = await showInventoryOrder(
        context,
        client: widget.client,
        locations: locations,
        partners: partners,
        initialItem: item.isEmpty ? null : item,
        initialStock: stock,
      );
    } finally {
      _dialog = false;
    }
    if (value == null || !mounted || _locked) return;
    await _work(
      () => _change({
        'action': 'save',
        'kind': 'order',
        'id': inventoryRequestKey(),
        'revision': 0,
        'value': value,
      }),
    );
    if (mounted && !_locked) {
      setState(() {
        _tab = 'orders';
        _detail = {};
      });
    }
  }

  Future<void> _orderAction(Map<String, dynamic> o, String action) async {
    final d = inventoryMap(o['data']);
    final lines = inventoryItems(d['lines']);
    Map<String, dynamic> extra = {};
    if (action == 'order_process') {
      final f = await _form(
        d['type'] == 'purchase' ? 'Receive an order' : 'Ship an order',
        [
          InventoryField(
            'line',
            'Order line',
            initial: '0',
            options: {
              for (var i = 0; i < lines.length; i++)
                if (inventoryNumber(lines[i]['quantity']) >
                    inventoryNumber(lines[i]['done']))
                  '$i':
                      'Line ${i + 1} · ${inventoryQuantity(inventoryNumber(lines[i]['quantity']) - inventoryNumber(lines[i]['done']))} remaining',
            },
            required: true,
          ),
          const InventoryField(
            'quantity',
            'Quantity',
            initial: '1',
            numeric: true,
          ),
        ],
      );
      if (f == null) return;
      extra = {
        'line': int.parse(f['line']!),
        'quantity': double.parse(f['quantity']!),
      };
    }
    if (!mounted || _locked) return;
    if (action == 'order_cancel') {
      _dialog = true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cancel remaining order quantities?'),
          content: const Text(
            'Completed receipts and shipments stay in the audit trail. Remaining sales reservations will be released.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cancel remainder'),
            ),
          ],
        ),
      );
      _dialog = false;
      if (ok != true) return;
    }
    if (!mounted || _locked) return;
    await _work(
      () => _change({
        'action': action,
        'id': o['id'],
        'revision': o['revision'],
        ...extra,
      }),
    );
  }

  String _locationName(dynamic id) {
    for (final l in locations) {
      if (l['id'] == id) return '${inventoryMap(l['data'])['name']}';
    }
    return 'Archived location';
  }

  Widget _voiceResults(
    Map<String, dynamic> result,
    Future<bool> Function() close,
  ) => InventoryVoiceResults(
    result: result,
    onView: () async {
      await close();
    },
    onOpen: (id) async {
      if (await close() && mounted && !_locked) await _openItem(id);
    },
  );
  @override
  Widget build(BuildContext context) => _buildWorkspace();
}

class InventoryVoiceResults extends StatelessWidget {
  const InventoryVoiceResults({
    super.key,
    required this.result,
    required this.onView,
    required this.onOpen,
  });
  final Map<String, dynamic> result;
  final VoidCallback onView;
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) {
    final list = inventoryItems(result['items']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.isEmpty
                  ? 'Rici · your inventory assistant'
                  : '${result['total'] ?? 0} inventory matches',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (result.isEmpty)
              const Text(
                'Start voice and say an item name, SKU or serial. A partial name is enough. Your selected search region is used unless you ask to change it.',
              ),
            for (final p in list.take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: p['photo_url'] == null
                    ? const Icon(Icons.inventory_2_outlined)
                    : Image.network(
                        p['photo_url'],
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, s) =>
                            const Icon(Icons.inventory_2_outlined),
                      ),
                title: Text('${inventoryMap(p['data'])['name']}'),
                subtitle: Text(
                  '${inventoryMap(p['data'])['sku']} · ${inventoryQuantity(p['available'])} available',
                ),
                onTap: () => onOpen(p['id']),
              ),
            TextButton(
              onPressed: onView,
              child: const Text('View all matches in Inventory'),
            ),
          ],
        ),
      ),
    );
  }
}

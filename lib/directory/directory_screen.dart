import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'directory_client.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key, required this.client});
  final DirectoryClient client;
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  DirJson _me = {}, _data = {};
  final Map<String, DirJson> _unsaved = {};
  List<DirJson> _businesses = [], _queue = [];
  String? _id, _error;
  String _adminQuery = '';
  bool _busy = false, _locked = false;
  bool get _admin => _me['isAdmin'] == true;
  DirJson get _business => dirMap(_data['business']);
  DirJson get _membership => dirMap(_data['membership']);
  bool get _paid =>
      _membership['livemode'] == true &&
      _membership['state'] == 'active' &&
      _membership['blocked_invoice'] == null &&
      (DateTime.tryParse(
            _membership['paid_until'] ?? '',
          )?.isAfter(DateTime.now()) ??
          false);
  bool get _mine => _businesses.any((b) => b['id'] == _id);
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
    _run(_load);
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null) Navigator.of(context).popUntil((r) => r == route);
    setState(() {
      _locked = true;
      _unsaved.clear();
      _data = {};
      _businesses = [];
      _queue = [];
      _id = null;
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final me = await widget.client.request('GET', '/me');
    if (!mounted || _locked) return;
    setState(() {
      _me = me;
      _businesses = dirRows(me['businesses']);
    });
    if (_admin) {
      final q = await widget.client.request(
        'GET',
        '/admin',
        query: {'q': _adminQuery},
      );
      if (mounted && !_locked) {
        setState(() => _queue = dirRows(q['businesses']));
      }
    }
    if (_id != null) await _select(_id!);
  }

  Future<void> _select(String id) async {
    final d = await widget.client.request('GET', '/owner/$id');
    if (mounted && !_locked) {
      setState(() {
        _id = id;
        _data = d;
      });
    }
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    if (!mounted || _locked) return null;
    final route = DialogRoute<T>(context: context, builder: builder);
    final value = await Navigator.of(context).push(route);
    await route.completed;
    return _locked ? null : value;
  }

  Future<bool> _confirm(String title, String message) async =>
      await _dialog<bool>(
        (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _open(String address) async {
    if (!await launchUrl(
      Uri.parse(address),
      mode: LaunchMode.externalApplication,
    )) {
      throw const DirectoryException('Could not open this link.');
    }
  }

  String get _publicUrl =>
      'https://www.korlixdeveloper.com/business-directory/?business=${Uri.encodeComponent(_business['slug'] ?? '')}';
  Future<void> _edit({bool create = false}) async {
    final recoveryKey = create ? 'new' : _id!;
    final recovery = _unsaved[recoveryKey];
    final current = recovery != null
        ? dirMap(recovery['details'])
        : create
        ? <String, dynamic>{}
        : dirMap(_business['draft']);
    final controls = <String, TextEditingController>{};
    const fields = {
      'name': 'Business name *',
      'owner_name': 'Owner / representative name (private) *',
      'public_contact_name': 'Public contact name (optional)',
      'specialties': 'Specialties / nature of business',
      'phone': 'Public business phone',
      'email': 'Public contact email',
      'address': 'Public street address (optional)',
      'city': 'City',
      'country': 'Country',
      'service_area': 'Service area / online service',
      'description': 'Short business description *',
      'hours': 'Opening hours',
      'website': 'Website URL (https://...)',
      'social': 'Social page URL (https://...)',
      'languages': 'Languages spoken',
      'accessibility': 'Accessibility details',
      'offer_text': 'Member offer / announcement',
      'offer_expires': 'Offer expiry (YYYY-MM-DD)',
    };
    for (final k in fields.keys) {
      controls[k] = TextEditingController(
        text: k == 'owner_name'
            ? (recovery?['owner_name'] ??
                  (create ? '' : _business['owner_name'] ?? ''))
            : k == 'offer_text'
            ? (current['offer']?['text'] ?? '')
            : k == 'offer_expires'
            ? (current['offer']?['expires'] ?? '')
            : current[k]?.toString() ?? '',
      );
    }
    String category =
        current['category'] ?? (_me['categories'] as List? ?? ['Other']).first;
    final photos = List<String>.from(current['photos'] ?? []);
    final assets = create
        ? <DirJson>[]
        : dirRows(
            _data['assets'],
          ).where((a) => a['purpose'] == 'photo').toList();
    try {
      final result = await _dialog<DirJson>(
        (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: Text(
              create ? 'Add your business — free' : 'Edit business listing',
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Only the fields marked public, your business details, and selected company photos appear in the directory after review. Owner name and verification evidence stay private. Add at least a phone or email, plus a city or service area.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Business category',
                      ),
                      items: (_me['categories'] as List? ?? ['Other'])
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.toString(),
                              child: Text(v.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => category = v ?? category,
                    ),
                    for (final e in fields.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: TextField(
                          controller: controls[e.key],
                          maxLength: e.key == 'description'
                              ? 2000
                              : e.key == 'hours'
                              ? 500
                              : e.key == 'offer_text'
                              ? 400
                              : e.key == 'owner_name' ||
                                    e.key == 'public_contact_name'
                              ? 100
                              : e.key == 'name'
                              ? 150
                              : e.key == 'phone'
                              ? 40
                              : e.key == 'email'
                              ? 254
                              : e.key == 'city' || e.key == 'country'
                              ? 100
                              : e.key == 'offer_expires'
                              ? 10
                              : 500,
                          minLines: e.key == 'description' ? 3 : 1,
                          maxLines: e.key == 'description' || e.key == 'hours'
                              ? 5
                              : 1,
                          decoration: InputDecoration(
                            labelText: e.value,
                            helperText: e.key.startsWith('offer_')
                                ? 'Shown only with an active verified membership'
                                : null,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    if (assets.isNotEmpty) ...[
                      const Text(
                        'Choose company photos (first selected is the cover)',
                      ),
                      for (final a in assets)
                        CheckboxListTile(
                          value: photos.contains(a['id']),
                          title: Text('Company photo ${assets.indexOf(a) + 1}'),
                          onChanged: (v) => update(() {
                            if (v == true && photos.length < 12) {
                              photos.add(a['id']);
                            } else {
                              photos.remove(a['id']);
                            }
                          }),
                        ),
                    ],
                    const Text(
                      'Save a draft first, upload company pictures, then submit for review. Basic listings show up to 3 photos; active verified members can show 12.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final d = <String, dynamic>{
                    for (final k in fields.keys)
                      if (![
                        'owner_name',
                        'offer_text',
                        'offer_expires',
                      ].contains(k))
                        k: controls[k]!.text.trim(),
                    'category': category,
                    'photos': photos,
                    'offer': controls['offer_text']!.text.trim().isEmpty
                        ? null
                        : {
                            'text': controls['offer_text']!.text.trim(),
                            'expires': controls['offer_expires']!.text.trim(),
                          },
                  };
                  Navigator.pop(c, {
                    'details': d,
                    'owner_name': controls['owner_name']!.text.trim(),
                  });
                },
                child: const Text('Save draft'),
              ),
            ],
          ),
        ),
      );
      if (result == null || _locked) return;
      _unsaved[recoveryKey] = result;
      final b = await widget.client.request(
        'POST',
        create ? '/owner' : '/owner/$_id/action',
        body: {
          ...result,
          if (!create) 'action': 'save',
          if (!create) 'version': _business['version'],
        },
      );
      _unsaved.remove(recoveryKey);
      _id = b['id'];
      await _load();
    } finally {
      for (final c in controls.values) {
        c.dispose();
      }
    }
  }

  Future<void> _submit() async {
    final d = dirMap(_business['draft']);
    if (!await _confirm(
      'Publish these business details?',
      '${d['name']}\n${d['description']}\n\n${d['phone']}\n${d['email']}\n${[d['address'], d['city'], d['country'], d['service_area']].where((v) => v != null && v != '').join(', ')}\n\nThe business details and selected company photos will be public after approval. I am authorized to publish this information and these photos.',
    )) {
      return;
    }
    await widget.client.request(
      'POST',
      '/owner/$_id/action',
      body: {
        'action': 'submit',
        'version': _business['version'],
        'owner_name': _business['owner_name'],
        'details': d,
        'consent': true,
      },
    );
    await _load();
  }

  Future<void> _upload(String purpose) async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: purpose == 'evidence'
          ? ['jpg', 'jpeg', 'png', 'webp', 'pdf']
          : ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (file == null || _locked) return;
    final f = file.files.single;
    if (f.size > 5242880 || f.bytes == null) {
      throw const DirectoryException('Choose a file smaller than 5 MB.');
    }
    final uploaded = await widget.client.request(
      'POST',
      '/owner/$_id/assets',
      body: {'purpose': purpose, 'base64': base64Encode(f.bytes!)},
    );
    if (purpose == 'photo' && !_locked) {
      final draft = dirClone(dirMap(_business['draft']));
      final photos = List<String>.from(draft['photos'] ?? []);
      if (photos.length < 12) {
        photos.add(uploaded['id']);
        draft['photos'] = photos;
        await widget.client.request(
          'POST',
          '/owner/$_id/action',
          body: {
            'action': 'save',
            'version': _business['version'],
            'owner_name': _business['owner_name'],
            'details': draft,
          },
        );
      }
    }
    await _select(_id!);
  }

  Future<void> _evidence() async {
    final c = TextEditingController(text: _business['evidence_note'] ?? '');
    try {
      final note = await _dialog<String>(
        (context) => AlertDialog(
          title: const Text('Apply for business verification'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Explain your role and how a reviewer can check business email, phone and ownership. Include a company website or registration reference, or an alternative for a sole proprietor. Upload supporting evidence separately. Do not include passwords or unnecessary personal identifiers.\n\nReview comes first. If approved, you can choose \$4.99/month or \$49/year USD. No payment is taken by submitting this application.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: c,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Ownership evidence and explanation',
                      border: OutlineInputBorder(),
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
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Submit application'),
            ),
          ],
        ),
      );
      if (note == null || _locked) return;
      await widget.client.request(
        'POST',
        '/owner/$_id/action',
        body: {'action': 'verification_submit', 'evidence_note': note},
      );
      await _load();
    } finally {
      c.dispose();
    }
  }

  Future<void> _review(String action) async {
    final c = TextEditingController();
    String decision = action == 'resolve_reports' ? 'resolve' : 'changes';
    final checks = <String>{};
    try {
      final result = await _dialog<DirJson>(
        (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              action == 'verification_review'
                  ? 'Review business verification'
                  : action == 'review'
                  ? 'Review public listing'
                  : 'Resolve reports',
            ),
            content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (action == 'verification_review') ...[
                      const Text(
                        'Only mark a check after completing it independently. An owner’s statement or payment alone is not verification. Document the method and outcome in your review note.',
                      ),
                      for (final k in ['email', 'phone', 'ownership'])
                        CheckboxListTile(
                          value: checks.contains(k),
                          title: Text('$k checked'),
                          onChanged: (v) => update(() {
                            v == true ? checks.add(k) : checks.remove(k);
                          }),
                        ),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: decision,
                      items:
                          (action == 'review'
                                  ? ['approve', 'changes', 'hide']
                                  : action == 'verification_review'
                                  ? ['approve', 'changes', 'revoke']
                                  : ['resolve'])
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                      onChanged: (v) => decision = v ?? decision,
                    ),
                    TextField(
                      controller: c,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Review note / methods and outcome',
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
                onPressed: () => Navigator.pop(context, {
                  'action': action,
                  'decision': decision,
                  'checks': checks.toList(),
                  'note': c.text.trim(),
                  'version': _business['version'],
                }),
                child: const Text('Record decision'),
              ),
            ],
          ),
        ),
      );
      if (result == null || _locked) return;
      await widget.client.request('POST', '/admin/$_id', body: result);
      await _load();
    } finally {
      c.dispose();
    }
  }

  Future<void> _membershipAction(String action, {String? interval}) async {
    if (action == 'checkout' &&
        !await _confirm(
          'Start recurring membership?',
          '${interval == 'year' ? '\$49 per year' : '\$4.99 per month'} USD, billed automatically until canceled. Membership includes a badge only while verification remains approved and payment is current. Cancel renewal from My Businesses. Your basic listing stays free.',
        )) {
      return;
    }
    if (action == 'cancel' &&
        !await _confirm(
          'Cancel membership renewal?',
          'Your free listing remains. Paid benefits continue through the current paid period unless verification is revoked.',
        )) {
      return;
    }
    final result = await widget.client.request(
      'POST',
      '/owner/$_id/membership',
      body: {
        'action': action,
        'interval': ?interval,
        'acceptRecurring': true,
        'confirm': true,
      },
    );
    if (_locked) return;
    if (result['url'] != null) await _open(result['url']);
    await _load();
  }

  Future<void> _removeFile() async {
    final assets = dirRows(_data['assets']);
    final selected = await _dialog<DirJson>(
      (c) => SimpleDialog(
        title: const Text('Remove an uploaded file'),
        children: [
          for (final a in assets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, a),
              child: Text('${a['purpose']} ${assets.indexOf(a) + 1}'),
            ),
        ],
      ),
    );
    if (selected == null || _locked) return;
    if (!await _confirm(
      'Delete this uploaded file?',
      'Company photos must first be removed from the draft and approved listing. Removing evidence can require another verification review.',
    )) {
      return;
    }
    await widget.client.request(
      'DELETE',
      '/owner/$_id/assets/${selected['id']}',
    );
    await _load();
  }

  Future<void> _file(DirJson a) async {
    final bytes = await widget.client.bytes('/owner/$_id/assets/${a['id']}');
    if (!mounted || _locked) return;
    if (a['mime'] == 'application/pdf') {
      await saveBookkeepingFile(
        bytes,
        'business-evidence.pdf',
        'application/pdf',
        const Rect.fromLTWH(0, 0, 1, 1),
      );
    } else {
      await _dialog<void>(
        (c) => AlertDialog(
          title: Text(
            a['purpose'] == 'evidence'
                ? 'Private verification evidence'
                : 'Company photo',
          ),
          content: Image.memory(bytes),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _button(
    String label,
    VoidCallback? action, {
    IconData icon = Icons.arrow_forward,
  }) => OutlinedButton.icon(
    onPressed: _busy ? null : action,
    icon: Icon(icon),
    label: Text(label),
  );
  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business Directory')),
        body: const Center(
          child: Text('Sign in again to manage your businesses.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('KORLIX Business Directory'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : () => _run(_load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your business deserves to be found.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a free public storefront. Share your services, company photos and contact details. No paid KORLIX plan required.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _edit(create: true)),
                        icon: const Icon(Icons.add_business),
                        label: const Text('Add business — free'),
                      ),
                      _button(
                        'Explore public directory',
                        () => _run(
                          () => _open(
                            'https://www.korlixdeveloper.com/business-directory/',
                          ),
                        ),
                        icon: Icons.public,
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _error! +
                            (_unsaved.isEmpty
                                ? ''
                                : '\nYour edits are kept here. Reopen the form to retry.'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'My Businesses',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_businesses.isEmpty && !_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Your first listing starts here. Add your business, upload company photos, then submit it for review.',
                      ),
                    ),
                  for (final b in _businesses)
                    Card(
                      child: ListTile(
                        selected: b['id'] == _id,
                        leading: const Icon(Icons.storefront),
                        title: Text(b['draft']?['name'] ?? 'Business'),
                        subtitle: Text(
                          'Listing: ${b['state']} • Verification: ${b['verification_state']}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _run(() => _select(b['id'])),
                      ),
                    ),
                  if (_admin) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Directory review desk',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Review submitted listings, verify ownership, and resolve reports. Payments never substitute for these checks.',
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Find any listing by name or share slug',
                        hintText: 'Leave blank for pending reviews',
                      ),
                      onSubmitted: (v) {
                        _adminQuery = v.trim();
                        _run(_load);
                      },
                    ),
                    if (_queue.isEmpty)
                      const Text('No pending reviews or unresolved reports.'),
                    for (final b in _queue)
                      ListTile(
                        title: Text(b['name'] ?? 'Business'),
                        subtitle: Text(
                          '${b['state']} • verification ${b['verification_state']} • ${b['reports']} reports',
                        ),
                        trailing: const Icon(Icons.fact_check_outlined),
                        onTap: () => _run(() => _select(b['id'])),
                      ),
                  ],
                  if (_id != null && _business.isNotEmpty) ...[
                    const Divider(height: 40),
                    ..._detail(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _detail() {
    final b = _business,
        d = dirMap(b['draft']),
        assets = dirRows(_data['assets']);
    return [
      Text(
        d['name'] ?? 'Business',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text('${d['category']} • ${d['city'] ?? d['service_area'] ?? ''}'),
      const SizedBox(height: 12),
      SelectableText(d['description'] ?? ''),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          for (final k in [
            'phone',
            'email',
            'address',
            'city',
            'country',
            'service_area',
            'website',
            'hours',
            'public_contact_name',
          ])
            if (d[k]?.toString().isNotEmpty == true)
              Chip(label: Text('${k.replaceAll('_', ' ')}: ${d[k]}')),
        ],
      ),
      if (b['review_note']?.toString().isNotEmpty == true)
        Text('Listing review: ${b['review_note']}'),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_mine) ...[
            _button(
              'Remove uploaded file',
              () => _run(_removeFile),
              icon: Icons.delete_outline,
            ),
            _button('Edit draft', () => _run(_edit), icon: Icons.edit),
            _button(
              'Upload company picture',
              () => _run(() => _upload('photo')),
              icon: Icons.add_photo_alternate_outlined,
            ),
            _button(
              'Submit listing for review',
              () => _run(_submit),
              icon: Icons.publish,
            ),
            _button(
              'Hide listing',
              () => _run(() async {
                if (await _confirm(
                  'Hide this listing?',
                  'It will no longer appear publicly. This does not cancel a paid membership.',
                )) {
                  await widget.client.request(
                    'POST',
                    '/owner/$_id/action',
                    body: {'action': 'hide'},
                  );
                  await _load();
                }
              }),
              icon: Icons.visibility_off_outlined,
            ),
          ],
          if (b['published'] != null) ...[
            _button(
              'View public page',
              () => _run(() => _open(_publicUrl)),
              icon: Icons.public,
            ),
            _button(
              'Copy share link',
              () => _run(() async {
                await Clipboard.setData(ClipboardData(text: _publicUrl));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Business link copied')),
                  );
                }
              }),
              icon: Icons.link,
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      if (assets.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in assets)
              _button(
                '${a['purpose'] == 'evidence' ? 'Private evidence' : 'Company photo'} ${assets.indexOf(a) + 1}',
                () => _run(() => _file(a)),
                icon: a['purpose'] == 'evidence'
                    ? Icons.lock_outline
                    : Icons.photo_outlined,
              ),
          ],
        ),
      const Divider(height: 40),
      Text(
        'KORLIX Verified Business',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Optional: \$4.99/month or \$49/year USD after review. Verification checks an owner’s connection to the business, not service quality. Basic listings stay free.',
      ),
      Text(
        'Application: ${b['verification_state']} • Membership: ${_membership['state'] ?? 'none'}',
      ),
      if (b['verification_note']?.toString().isNotEmpty == true)
        Text('Verification review: ${b['verification_note']}'),
      if (_membership['paid_until'] != null)
        Text(
          'Paid through: ${_membership['paid_until']} • Renewal ${_membership['cancel_at_period_end'] == true ? 'canceled' : 'enabled'}',
        ),
      if (_mine)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button(
              'Upload private evidence',
              () => _run(() => _upload('evidence')),
              icon: Icons.lock_outline,
            ),
            _button(
              'Apply for verification',
              () => _run(_evidence),
              icon: Icons.verified_outlined,
            ),
            if (kIsWeb &&
                b['verification_state'] == 'approved' &&
                _me['paymentsReady'] == true) ...[
              _button(
                'Subscribe monthly',
                () => _run(
                  () => _membershipAction('checkout', interval: 'month'),
                ),
              ),
              _button(
                'Subscribe yearly',
                () =>
                    _run(() => _membershipAction('checkout', interval: 'year')),
              ),
            ],
            if (_membership.isNotEmpty) ...[
              _button(
                'Refresh membership',
                () => _run(() => _membershipAction('refresh')),
              ),
              if (kIsWeb && _membership['customer_id'] != null)
                _button(
                  'Manage billing',
                  () => _run(() => _membershipAction('portal')),
                ),
              if (_membership['subscription_id'] != null)
                _button(
                  'Cancel renewal',
                  () => _run(() => _membershipAction('cancel')),
                ),
            ],
          ],
        ),
      if (_me['paymentsReady'] != true)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Paid checkout is not available yet. Free listings and verification applications are open. No payment will be taken.',
          ),
        ),
      if (_me['paymentsReady'] == true && _me['livePayments'] != true)
        const Text(
          'Membership payments are in test mode. No live badge is sold in this mode.',
        ),
      if (_paid && b['verification_state'] == 'approved') ...[
        const SizedBox(height: 16),
        Text(
          'Last 30 days • approximate activity',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${dirRows(_data['metrics']).fold<int>(0, (s, m) => s + (m['views'] as int? ?? 0))} profile views • ${dirRows(_data['metrics']).fold<int>(0, (s, m) => s + (m['contacts'] as int? ?? 0))} contact-button clicks',
        ),
        const Text(
          'Counts are rate-limited signals, not unique people or confirmed leads.',
        ),
      ],
      if (_admin) ...[
        const Divider(height: 40),
        Text(
          'Private reviewer information',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SelectableText(
          'Owner / representative: ${b['owner_name']}\nOwnership explanation: ${b['evidence_note']}',
        ),
        for (final r in dirRows(_data['reports']))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Reported: ${r['reason']}'),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button('Review listing', () => _run(() => _review('review'))),
            _button(
              'Review verification',
              () => _run(() => _review('verification_review')),
            ),
            _button(
              'Resolve reports',
              () => _run(() => _review('resolve_reports')),
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      _button(
        'Verification, billing and directory rules',
        () => _run(
          () => _open(
            'https://www.korlixdeveloper.com/business-directory/verification.html',
          ),
        ),
      ),
    ];
  }
}

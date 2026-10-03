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
  String? _id, _error, _notice;
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
      _error = _notice = null;
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
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

  void _acceptBusiness(DirJson business) {
    if (!mounted || _locked) return;
    if (business['id'] is! String || business['version'] is! num) {
      throw const DirectoryException(
        'Refresh to check whether your listing was saved before retrying.',
      );
    }
    setState(() {
      final same = _id == business['id'];
      _id = business['id'];
      _data = {...(same ? _data : <String, dynamic>{}), 'business': business};
      _businesses = [
        for (final b in _businesses)
          if (b['id'] != _id) b,
        business,
      ];
    });
  }

  void _announce(String message) {
    if (!mounted || _locked) return;
    setState(() => _notice = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshAfterWrite() async {
    try {
      await _load();
    } catch (_) {
      if (mounted && !_locked) {
        setState(
          () => _error =
              'Your change was saved, but the directory could not refresh. Tap Refresh to update the screen.',
        );
      }
    }
  }

  String _listingLabel(DirJson business) => switch (business['state']) {
    'pending' =>
      business['published'] == null
          ? 'Awaiting listing review'
          : 'Updates awaiting review',
    'published' => 'Live in the directory',
    'needs_changes' => 'Changes requested',
    'hidden' => 'Hidden from the directory',
    _ => business['published'] != null ? 'Draft updates saved' : 'Draft saved',
  };

  String _verificationLabel(dynamic state) => switch (state) {
    'pending' => 'Application awaiting review',
    'approved' => 'Ownership approved',
    'needs_changes' => 'Application needs changes',
    'revoked' => 'Approval withdrawn',
    _ => 'Not requested',
  };

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
    final form = GlobalKey<FormState>();
    bool consent = false, formFinished = false;
    String? formError;
    String? validate(String field, String? raw) {
      final value = (raw ?? '').trim();
      if (['name', 'owner_name', 'description'].contains(field) &&
          value.isEmpty) {
        return 'Please complete this field.';
      }
      const limits = {
        'specialties': 300,
        'address': 250,
        'service_area': 250,
        'languages': 200,
        'accessibility': 300,
      };
      if (limits[field] != null && value.length > limits[field]!) {
        return 'Use ${limits[field]} characters or fewer.';
      }
      if (field == 'phone') {
        if (value.isEmpty && controls['email']!.text.trim().isEmpty) {
          return 'Add a business phone or contact email.';
        }
        if (value.isNotEmpty &&
            !RegExp(
              r'^[+\d() .x-]{5,40}$',
              caseSensitive: false,
            ).hasMatch(value)) {
          return 'Enter a valid business phone number.';
        }
      }
      if (field == 'email' &&
          value.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
        return 'Enter a valid contact email.';
      }
      if (field == 'city' &&
          value.isEmpty &&
          controls['service_area']!.text.trim().isEmpty) {
        return 'Add a city or service area.';
      }
      if (['website', 'social'].contains(field) && value.isNotEmpty) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return 'Use a complete public http:// or https:// address.';
        }
      }
      if (field == 'offer_expires' &&
          controls['offer_text']!.text.trim().isNotEmpty &&
          (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
              DateTime.tryParse(value) == null)) {
        return 'Use an offer expiry date in YYYY-MM-DD format.';
      }
      return null;
    }

    try {
      final result = await _dialog<DirJson>(
        (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            title: Text(
              create ? 'Add your business — free' : 'Edit business listing',
            ),
            content: SizedBox(
              width: 650,
              child: Form(
                key: form,
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
                        child: TextFormField(
                          key: ValueKey('directory-field-${e.key}'),
                          controller: controls[e.key],
                          validator: (value) => validate(e.key, value),
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
                      'Company photos are optional. You can save a draft to upload pictures first, or submit your free listing now. Basic listings show up to 3 photos; active verified members can show 12.',
                    ),
                    const SizedBox(height: 12),
                    if (formError != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            formError!,
                            style: TextStyle(
                              color: Theme.of(c).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    CheckboxListTile(
                      key: const ValueKey('directory-public-consent'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      titleAlignment: ListTileTitleAlignment.top,
                      value: consent,
                      title: const Text(
                        'I am authorized to publish this listing.',
                      ),
                      subtitle: const Text(
                        'Free listing review does not require a verified badge or payment.',
                      ),
                      onChanged: (value) => update(() {
                        consent = value == true;
                        formError = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (formFinished) return;
                  formFinished = true;
                  Navigator.pop(c);
                },
                child: const Text('Cancel'),
              ),
              for (final submit in [false, true])
                FilledButton.tonal(
                  key: ValueKey(
                    submit ? 'directory-submit-free' : 'directory-save-draft',
                  ),
                  style: submit
                      ? FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF146C43),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                        )
                      : null,
                  onPressed: () {
                    if (formFinished) return;
                    if (form.currentState?.validate() != true) {
                      update(
                        () => formError =
                            'Check the highlighted fields. Your information is still here.',
                      );
                      return;
                    }
                    if (submit && !consent) {
                      update(
                        () => formError =
                            'Confirm permission to publish before submitting your free listing.',
                      );
                      return;
                    }
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
                    formFinished = true;
                    Navigator.pop(c, {
                      'details': d,
                      'owner_name': controls['owner_name']!.text.trim(),
                      'submit': submit,
                    });
                  },
                  child: Text(submit ? 'Submit free listing' : 'Save draft'),
                ),
            ],
          ),
        ),
      );
      if (result == null || !mounted || _locked) return;
      _unsaved[recoveryKey] = result;
      final submit = result['submit'] == true;
      final b = await widget.client.request(
        'POST',
        create ? '/owner' : '/owner/$_id/action',
        body: {
          ...result,
          if (!create) 'action': submit ? 'submit' : 'save',
          if (!create) 'version': _business['version'],
          if (!create && submit) 'consent': true,
        },
      );
      if (!mounted || _locked) return;
      _acceptBusiness(b);
      _unsaved.remove(recoveryKey);
      if (create && submit) {
        try {
          final submitted = await widget.client.request(
            'POST',
            '/owner/$_id/action',
            body: {
              'action': 'submit',
              'version': b['version'],
              'owner_name': b['owner_name'],
              'details': b['draft'],
              'consent': true,
            },
          );
          if (!mounted || _locked) return;
          _acceptBusiness(submitted);
        } catch (error) {
          if (!mounted || _locked) return;
          _unsaved[_id!] = result;
          _announce(
            'Your business draft is saved. Submission was not confirmed.',
          );
          throw DirectoryException(
            '$error Refresh this saved listing to check its status before submitting again.',
          );
        }
      }
      _announce(
        submit
            ? 'Free listing submitted for review.'
            : 'Business draft saved. Submit it when you are ready for listing review.',
      );
      await _refreshAfterWrite();
    } finally {
      for (final c in controls.values) {
        c.dispose();
      }
    }
  }

  Future<void> _submit() async {
    if (_business['state'] == 'pending') return;
    final id = _id;
    final business = _business;
    final d = dirMap(_business['draft']);
    if (!await _confirm(
      'Submit this free listing?',
      '${d['name']}\n${d['description']}\n\n${d['phone']}\n${d['email']}\n${[d['address'], d['city'], d['country'], d['service_area']].where((v) => v != null && v != '').join(', ')}\n\nThe business details and selected company photos will be public after approval. I am authorized to publish this information and these photos.',
    )) {
      return;
    }
    if (!mounted || _locked || id != _id) return;
    final submitted = await widget.client.request(
      'POST',
      '/owner/$id/action',
      body: {
        'action': 'submit',
        'version': business['version'],
        'owner_name': business['owner_name'],
        'details': d,
        'consent': true,
      },
    );
    if (!mounted || _locked) return;
    _acceptBusiness(submitted);
    _unsaved.remove(id);
    _announce('Free listing submitted for review.');
    await _refreshAfterWrite();
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
                  if (_notice != null)
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        key: const ValueKey('directory-save-confirmation'),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _notice!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                          'Free listing: ${_listingLabel(b)}\nOptional badge: ${_verificationLabel(b['verification_state'])}',
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
                          '${_listingLabel(b)} • Optional badge: ${_verificationLabel(b['verification_state'])} • ${b['reports']} reports',
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
      Card(
        key: const ValueKey('directory-listing-status'),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _listingLabel(b),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                switch (b['state']) {
                  'pending' =>
                    b['published'] == null
                        ? 'We received your free listing. It will appear in the public directory after a listing reviewer approves it. No verified badge or payment is required.'
                        : 'Your updates are awaiting listing review. Your previously approved listing stays public while these changes are reviewed.',
                  'published' =>
                    'Your approved listing is public. Saved edits appear after you submit them and a reviewer approves the changes.',
                  'needs_changes' =>
                    'Read the listing review note below, update your details, then submit your free listing again.',
                  'hidden' =>
                    'This listing is not visible publicly. You can update and submit it for a new listing review.',
                  _ =>
                    b['published'] != null
                        ? 'Your draft updates are saved. Your previously approved listing remains public. Submit the updates when they are ready for review.'
                        : 'Your details are saved privately. Add optional company photos, then submit your free listing for review.',
                },
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
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
              b['state'] == 'pending'
                  ? 'Listing submitted'
                  : 'Submit free listing',
              b['state'] == 'pending' ? null : () => _run(_submit),
              icon: b['state'] == 'pending'
                  ? Icons.hourglass_top
                  : Icons.publish,
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
      Text('Optional badge: ${_verificationLabel(b['verification_state'])}'),
      Text(
        _membership.isEmpty ||
                _membership['state'] == null ||
                _membership['state'] == 'none'
            ? 'No paid membership. Your free listing review is separate.'
            : 'Membership: ${_membership['state']}',
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

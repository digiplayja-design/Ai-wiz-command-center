import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'contacts_style.dart';

import 'contacts_client.dart';
import 'phone_contacts.dart';

class ContactImport extends StatefulWidget {
  const ContactImport({
    super.key,
    required this.client,
    this.initialSource = 'spreadsheet',
  });
  final String initialSource;
  final ContactsClient client;
  @override
  State<ContactImport> createState() => _ContactImportState();
}

class _ContactImportState extends State<ContactImport> {
  String _source = 'spreadsheet';
  String? _filename;
  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
  }

  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview;
  final Set<int> _selected = {};
  List<Map<String, dynamic>> get _rows =>
      ((_preview?['contacts'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> _run(Future<Map<String, dynamic>> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await fn();
      if (mounted) {
        setState(() {
          _preview = p;
          _selected
            ..clear()
            ..addAll(List.generate((p['contacts'] as List).length, (i) => i));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _file() async {
    // File selection stays in the user's explicit tap; no background address-book reads.
    setState(() => _error = null);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'tsv', 'xlsx', 'vcf', 'vcard', 'json'],
        withData: true,
      );
      if (picked == null || !mounted) return;
      final f = picked.files.single;
      _filename = f.name;
      if (f.size > 2 * 1024 * 1024) {
        throw const ContactsException('Choose a file smaller than 2 MB.');
      }
      if (f.bytes == null) {
        throw const ContactsException(
          'This file could not be read. Please choose it again.',
        );
      }
      await _run(
        () => widget.client.request(
          'POST',
          '/imports/preview',
          body: {
            'source': _source,
            'filename': f.name,
            'content': base64Encode(f.bytes!),
          },
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _phone() => _run(() async {
    final rows = await pickPhoneContacts();
    if (rows.isEmpty) {
      throw const ContactsException('No phone contacts were selected.');
    }
    return widget.client.request(
      'POST',
      '/imports/preview',
      body: {'source': 'phone', 'contacts': rows},
    );
  });
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final rows = _rows;
      final result = await widget.client.request(
        'POST',
        '/imports',
        body: {
          'confirmed': true,
          'contacts': _selected.map((i) => rows[i]).toList(),
        },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _chooseSource(String value) => setState(() {
    _source = value;
    _preview = null;
    _filename = null;
    _selected.clear();
    _error = null;
  });
  Widget _sources(bool small) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in const {
          'phone': 'Phone',
          'email': 'Email',
          'facebook': 'Facebook',
          'spreadsheet': 'Spreadsheet',
        }.entries)
          SizedBox(
            width: (box.maxWidth - (small ? 10 : 30)) / (small ? 2 : 4),
            child: Material(
              color: _source == e.key
                  ? CrmStyle.cyan.withValues(alpha: .075)
                  : CrmStyle.background,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _busy ? null : () => _chooseSource(e.key),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _source == e.key
                          ? CrmStyle.cyan.withValues(alpha: .7)
                          : CrmStyle.line,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            switch (e.key) {
                              'phone' => Icons.smartphone_rounded,
                              'email' => Icons.alternate_email_rounded,
                              'facebook' => Icons.facebook_outlined,
                              _ => Icons.table_chart_outlined,
                            },
                            size: 23,
                            color: _source == e.key
                                ? CrmStyle.cyan
                                : CrmStyle.muted,
                          ),
                          const Spacer(),
                          if (_source == e.key)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: CrmStyle.cyan,
                              size: 15,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _sourceStep(bool small) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CrmSectionLabel('Where are your contacts?'),
      const SizedBox(height: 16),
      _sources(small),
      const SizedBox(height: 22),
      Text(switch (_source) {
        'phone' =>
          phonePickerAvailable
              ? 'Choose contacts from this device, or upload a vCard (.vcf) export.'
              : 'Export your phone contacts as a vCard (.vcf), then choose that file here. Direct phone selection isn’t supported by this browser.',
        'email' =>
          'Use a Google or Outlook contacts export, or bring in recipients saved in Nova Email. Inbox syncing is not connected.',
        'facebook' =>
          'Choose friends.json from your Facebook information export, or a contacts CSV. Names are imported; emails and phone numbers are included only if present in the file.',
        _ =>
          'Use a CSV or Excel workbook with Name, Phone, Email, Status, Company, Notes and Tags columns. We’ll read the first worksheet and show you a preview.',
      }, style: const TextStyle(color: CrmStyle.muted, fontSize: 13, height: 1.7)),
      const SizedBox(height: 22),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 27),
        decoration: BoxDecoration(
          color: CrmStyle.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CrmStyle.line),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: CrmStyle.cyan.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.drive_folder_upload_outlined,
                size: 28,
                color: CrmStyle.cyan,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Bring your people together',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            const Text(
              'Up to 1,000 contacts · 2 MB per file',
              style: TextStyle(color: CrmStyle.muted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _file,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Choose file'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (_source == 'phone' && phonePickerAvailable)
            OutlinedButton.icon(
              onPressed: _busy ? null : _phone,
              icon: const Icon(Icons.contacts_outlined, size: 17),
              label: const Text('Choose phone contacts'),
            ),
          if (_source == 'email')
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.client.request(
                        'POST',
                        '/imports/email-preview',
                      ),
                    ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 17),
              label: const Text('Use Nova Email contacts'),
            ),
          if (_source == 'spreadsheet')
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await Clipboard.setData(
                        const ClipboardData(
                          text: 'Name,Phone,Email,Status,Company,Notes,Tags\n',
                        ),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('CSV column headers copied.'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Copy CSV column headers'),
            ),
        ],
      ),
    ],
  );
  Widget _reviewStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.task_alt_rounded, color: CrmStyle.cyan, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your import is ready to review',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text(
                  _filename ?? '${contactLabel(_source)} contacts',
                  style: const TextStyle(fontSize: 12, color: CrmStyle.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CrmBadge('${_rows.length} ready', color: CrmStyle.cyan),
          CrmBadge(
            '${_preview!['duplicates'] ?? 0} duplicates',
            color: CrmStyle.gold,
          ),
          CrmBadge(
            '${(_preview!['errors'] as List? ?? []).length} invalid',
            color: CrmStyle.muted,
          ),
        ],
      ),
      const SizedBox(height: 15),
      const Text(
        'Select the people to add. Existing contacts are kept; matching email addresses or phone numbers are skipped.',
        style: TextStyle(color: CrmStyle.muted, fontSize: 12, height: 1.7),
      ),
      const SizedBox(height: 14),
      Material(
        color: CrmStyle.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CrmStyle.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text(
                'Select all · ${_selected.length} selected',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              value: _rows.isNotEmpty && _selected.length == _rows.length,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _selected.clear();
                      if (v == true) {
                        _selected.addAll(List.generate(_rows.length, (i) => i));
                      }
                    }),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 240,
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: ContactAvatar(contact: c, size: 32),
                    title: Text(
                      c['name'],
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [c['email'], c['phone']].whereType<String>().join(' · '),
                      style: const TextStyle(
                        color: CrmStyle.muted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: _selected.contains(i),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _selected.add(i);
                            } else {
                              _selected.remove(i);
                            }
                          }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      if ((_preview!['errors'] as List? ?? []).isNotEmpty)
        ExpansionTile(
          title: const Text(
            'Rows to fix',
            style: TextStyle(fontSize: 12, color: CrmStyle.gold),
          ),
          children: [
            for (final e in (_preview!['errors'] as List).take(30))
              ListTile(
                dense: true,
                title: Text(
                  'Row ${e['row']}: ${e['message']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => setState(() {
                _preview = null;
                _selected.clear();
                _error = null;
              }),
        icon: const Icon(Icons.arrow_back_rounded, size: 16),
        label: const Text('Choose another source'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 600,
        review = _preview != null;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: EdgeInsets.all(small ? 16 : 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 740,
            maxHeight: MediaQuery.sizeOf(context).height - 80,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(small ? 20 : 28, 24, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Import contacts',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            review
                                ? 'A clean start for every connection.'
                                : 'Your network. One beautiful workspace.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CrmStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close import',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: small ? 20 : 28),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    CrmBadge(
                      '01  Source',
                      color: review ? CrmStyle.muted : CrmStyle.cyan,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: CrmStyle.muted,
                        size: 16,
                      ),
                    ),
                    CrmBadge(
                      '02  Review & import',
                      color: review ? CrmStyle.cyan : CrmStyle.muted,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(small ? 20 : 28),
                  child: review ? _reviewStep() : _sourceStep(small),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: CrmStyle.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Container(
                padding: EdgeInsets.all(small ? 16 : 22),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: CrmStyle.line)),
                ),
                child: Row(
                  children: [
                    if (!small)
                      const Expanded(
                        child: Text(
                          'Importing does not start outreach.',
                          style: TextStyle(color: CrmStyle.muted, fontSize: 11),
                        ),
                      ),
                    if (small) const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    if (review) ...[
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _busy || _selected.isEmpty ? null : _save,
                        child: Text(
                          _busy
                              ? 'Importing…'
                              : 'Import ${_selected.length} contacts',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

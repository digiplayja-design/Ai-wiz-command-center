import 'package:flutter/material.dart';
import 'contacts_client.dart';
import 'contacts_style.dart';

class ContactEditor extends StatefulWidget {
  const ContactEditor({
    super.key,
    this.contact,
    this.initialSection = 0,
    required this.onSave,
  });
  final Map<String, dynamic>? contact;
  final int initialSection;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  final _fields = <String, TextEditingController>{};
  int _section = 0;
  String _category = 'unknown',
      _emailPermission = 'none',
      _callPermission = 'none';
  bool _favorite = false, _blocked = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final c = widget.contact ?? {};
    _section = widget.initialSection.clamp(0, 2);
    for (final k in [
      'name',
      'phone',
      'email',
      'company',
      'notes',
      'follow_up_on',
      'call_brief',
      'consent_at',
    ]) {
      _fields[k] = TextEditingController(text: (c[k] ?? '').toString());
    }
    _fields['tags'] = TextEditingController(
      text: ((c['tags'] as List?) ?? []).join(', '),
    );
    _category = c['category'] ?? 'unknown';
    _emailPermission = c['email_permission'] ?? 'none';
    _callPermission = c['call_permission'] ?? 'none';
    _favorite = c['favorite'] == true;
    _blocked = c['do_not_contact'] == true;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String key,
    String label, {
    int lines = 1,
    String? hint,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextField(
      key: ValueKey('edit-$key'),
      controller: _fields[key],
      enabled: !_saving,
      maxLines: lines,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 14),
      maxLength: {
        'name': 160,
        'phone': 60,
        'email': 254,
        'company': 160,
        'notes': 4000,
        'call_brief': 2000,
        'tags': 400,
      }[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    ),
  );
  Widget _choice(
    String title,
    String value,
    Map<String, String> items,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      key: ValueKey(title),
      initialValue: value,
      isExpanded: true,
      style: const TextStyle(fontSize: 13, color: CrmStyle.text),
      decoration: InputDecoration(labelText: title),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: _saving ? null : (v) => setState(() => changed(v!)),
    ),
  );
  Future<void> _save() async {
    if (_fields['name']!.text.trim().isEmpty) {
      setState(() {
        _section = 0;
        _error = 'Enter a name';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(<String, dynamic>{
        ...widget.contact ?? {},
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'category': _category,
        'email_permission': _emailPermission,
        'call_permission': _callPermission,
        'favorite': _favorite,
        'do_not_contact': _blocked,
        'tags': _fields['tags']!.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate:
          DateTime.tryParse(_fields['follow_up_on']!.text) ?? DateTime.now(),
    );
    if (d != null && mounted) {
      _fields['follow_up_on']!.text = d.toIso8601String().substring(0, 10);
    }
  }

  Widget _details(bool small) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CrmSectionLabel('The essentials'),
      const SizedBox(height: 20),
      _field('name', 'Full name *', hint: 'Who would you like to add?'),
      if (small) ...[
        _field('email', 'Email address', keyboard: TextInputType.emailAddress),
        _field(
          'phone',
          'Telephone',
          hint: '+1 415 555 0123',
          keyboard: TextInputType.phone,
        ),
      ] else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                'email',
                'Email address',
                keyboard: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _field(
                'phone',
                'Telephone',
                hint: '+1 415 555 0123',
                keyboard: TextInputType.phone,
              ),
            ),
          ],
        ),
      _field('company', 'Company / organization'),
      const SizedBox(height: 4),
      const CrmSectionLabel('Relationship status'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in contactCategories)
            ChoiceChip(
              label: Text(contactLabel(c)),
              selected: _category == c,
              onSelected: _saving ? null : (_) => setState(() => _category = c),
              selectedColor: CrmStyle.category(c).withValues(alpha: .2),
              labelStyle: TextStyle(
                color: _category == c ? CrmStyle.category(c) : CrmStyle.muted,
                fontSize: 12,
              ),
              showCheckmark: false,
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Start with a name. Add the rest whenever you’re ready.',
        style: TextStyle(color: CrmStyle.muted, fontSize: 12, height: 1.6),
      ),
    ],
  );
  Widget _relationship() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CrmSectionLabel('Make it personal'),
      const SizedBox(height: 20),
      _field(
        'notes',
        'Relationship notes',
        lines: 4,
        hint: 'What matters to this person?',
      ),
      _field('tags', 'Tags', hint: 'VIP, referral, west coast'),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('edit-follow-up'),
              controller: _fields['follow_up_on'],
              readOnly: true,
              onTap: _saving ? null : _pickDate,
              decoration: const InputDecoration(
                labelText: 'Next follow-up',
                suffixIcon: Icon(Icons.calendar_month_outlined, size: 19),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear follow-up',
            onPressed: _saving ? null : () => _fields['follow_up_on']!.clear(),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
      const SizedBox(height: 20),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Keep in favorites',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'A shortcut to your most important people.',
          style: TextStyle(fontSize: 12, color: CrmStyle.muted),
        ),
        secondary: const Icon(Icons.star_outline_rounded, color: CrmStyle.gold),
        value: _favorite,
        onChanged: _saving ? null : (v) => setState(() => _favorite = v),
      ),
    ],
  );
  Widget _nova() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CrmStyle.violet.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CrmStyle.violet.withValues(alpha: .18)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, color: CrmStyle.violet, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Prepare Nova to reach out with context. Saving permissions does not send an email or place a call.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: CrmStyle.muted,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _choice('Email permission', _emailPermission, const {
        'none': 'Not recorded',
        'transactional': 'Transactional email allowed',
        'marketing': 'Marketing opt-in recorded',
        'blocked': 'Email blocked',
      }, (v) => _emailPermission = v),
      if (_emailPermission == 'marketing')
        _field('consent_at', 'Marketing permission date', hint: 'YYYY-MM-DD'),
      _choice('Call permission', _callPermission, const {
        'none': 'Not recorded',
        'allowed': 'Outbound calls allowed',
        'blocked': 'Calls blocked',
      }, (v) => _callPermission = v),
      _field(
        'call_brief',
        'Nova call brief',
        lines: 3,
        hint: 'Purpose, useful context and desired outcome.',
      ),
      const Text(
        'Call briefs are available. Live outbound calling requires activation.',
        style: TextStyle(fontSize: 12, color: CrmStyle.muted, height: 1.6),
      ),
      const SizedBox(height: 18),
      const Divider(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Do not contact',
          style: TextStyle(
            color: CrmStyle.danger,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: const Text(
          'Block Nova outreach for this contact.',
          style: TextStyle(fontSize: 12, color: CrmStyle.muted),
        ),
        value: _blocked,
        onChanged: _saving ? null : (v) => setState(() => _blocked = v),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 600;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.all(small ? 16 : 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CrmStyle.cyan.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.contact == null
                            ? Icons.person_add_alt_rounded
                            : Icons.edit_outlined,
                        color: CrmStyle.cyan,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.contact == null
                                ? 'New contact'
                                : 'Edit contact',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Build a better connection.',
                            style: TextStyle(
                              color: CrmStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close editor',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: small ? 20 : 28),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: CrmStyle.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: TextButton(
                            key: ValueKey('editor-tab-$i'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                              backgroundColor: _section == i
                                  ? CrmStyle.raised
                                  : Colors.transparent,
                              foregroundColor: _section == i
                                  ? CrmStyle.text
                                  : CrmStyle.muted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            onPressed: _saving
                                ? null
                                : () => setState(() => _section = i),
                            child: Text(
                              ['Details', 'Relationship', 'Nova'][i],
                              style: TextStyle(fontSize: small ? 11 : 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(small ? 20 : 28),
                  child: switch (_section) {
                    0 => _details(small),
                    1 => _relationship(),
                    _ => _nova(),
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: CrmStyle.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(small ? 16 : 22),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: CrmStyle.line)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: Text(_saving ? 'Saving…' : 'Save contact'),
                    ),
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

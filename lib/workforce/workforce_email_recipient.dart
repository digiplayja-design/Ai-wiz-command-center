import 'package:flutter/material.dart';
import 'workforce_client.dart';
import 'workforce_style.dart';

class WorkforceEmailRecipientDialog extends StatefulWidget {
  const WorkforceEmailRecipientDialog({
    super.key,
    required this.client,
    required this.path,
  });
  final WorkforceClient client;
  final String path;
  @override
  State<WorkforceEmailRecipientDialog> createState() =>
      _WorkforceEmailRecipientDialogState();
}

class _WorkforceEmailRecipientDialogState
    extends State<WorkforceEmailRecipientDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _id = wfId();
  bool _approved = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_approved || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        widget.path,
        body: {
          'id': _id,
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'confirmed': true,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Approve email recipient'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add someone authorized to receive the work records you select. You will choose their scope in each rule.',
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Recipient name',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  maxLength: 254,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : 'Enter one email address',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _approved,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _approved = v == true),
                  title: const Text(
                    'I have permission to send Workforce records to this address.',
                  ),
                ),
                const Text(
                  'Saving a recipient sends no email. Recipients can stop future workspace emails using the link in each message.',
                  style: TextStyle(fontSize: 12, color: WfStyle.muted),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: WfStyle.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !_approved ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Approve recipient'),
        ),
      ],
    ),
  );
}

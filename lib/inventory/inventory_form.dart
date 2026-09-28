import 'package:flutter/material.dart';

class InventoryField {
  const InventoryField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.required = false,
    this.numeric = false,
    this.lines = 1,
    this.options,
  });
  final String keyName, label, initial;
  final bool required, numeric;
  final int lines;
  final Map<String, String>? options;
}

Future<Map<String, String>?> showInventoryForm(
  BuildContext context, {
  required String title,
  required List<InventoryField> fields,
  String submit = 'Save',
  String? note,
}) => showDialog<Map<String, String>>(
  context: context,
  builder: (context) =>
      _Form(title: title, fields: fields, submit: submit, note: note),
);

class _Form extends StatefulWidget {
  const _Form({
    required this.title,
    required this.fields,
    required this.submit,
    this.note,
  });
  final String title, submit;
  final String? note;
  final List<InventoryField> fields;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> values;
  @override
  void initState() {
    super.initState();
    values = {
      for (final f in widget.fields)
        f.keyName: TextEditingController(text: f.initial),
    };
  }

  @override
  void dispose() {
    for (final v in values.values) {
      v.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    widget.note!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f.options == null
                      ? TextFormField(
                          controller: values[f.keyName],
                          maxLines: f.lines,
                          maxLength: f.lines > 1 ? 2000 : 160,
                          keyboardType: f.numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: f.label,
                            border: const OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (v) {
                            if (f.required && (v ?? '').trim().isEmpty) {
                              return 'Enter ${f.label.toLowerCase()}';
                            }
                            if (f.numeric &&
                                (double.tryParse(v ?? '') == null ||
                                    double.parse(v!) < 0 ||
                                    !double.parse(v).isFinite)) {
                              return 'Enter a nonnegative number';
                            }
                            return null;
                          },
                        )
                      : DropdownButtonFormField<String>(
                          initialValue:
                              f.options!.containsKey(values[f.keyName]!.text)
                              ? values[f.keyName]!.text
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: f.label,
                            border: const OutlineInputBorder(),
                          ),
                          items: f.options!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => values[f.keyName]!.text = v ?? '',
                          validator: (v) => f.required && (v ?? '').isEmpty
                              ? 'Choose ${f.label.toLowerCase()}'
                              : null,
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
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              values.map((k, v) => MapEntry(k, v.text.trim())),
            );
          }
        },
        child: Text(widget.submit),
      ),
    ],
  );
}

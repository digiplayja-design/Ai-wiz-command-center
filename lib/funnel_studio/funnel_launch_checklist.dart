import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_library.dart';

class FunnelLaunchChecklist extends StatelessWidget {
  const FunnelLaunchChecklist({
    super.key,
    required this.document,
    required this.dirty,
    required this.onEdit,
    required this.onPreview,
    this.onEditField,
  });
  final Map<String, dynamic> document;
  final bool dirty;
  final VoidCallback onEdit, onPreview;
  final ValueChanged<String>? onEditField;

  @override
  Widget build(BuildContext context) {
    final checks = <(String, bool, String)>[
      (
        'Save your latest edits',
        !dirty,
        'Use Save draft above to save your changes.',
      ),
      (
        'Add a privacy-policy URL',
        funnelHttpsAddress('${document['privacy_url'] ?? ''}'),
        'Add a public HTTPS privacy-policy address in the page editor.',
      ),
      (
        'Add your business contact email',
        funnelContactEmail('${document['contact_email'] ?? ''}'),
        'Add a valid business email in the page editor.',
      ),
      if (document['sections'] is List &&
          (document['sections'] as List).any((s) => s['kind'] == 'text'))
        (
          'Complete your text sections',
          (document['sections'] as List)
              .where((s) => s['kind'] == 'text')
              .every(
                (s) =>
                    '${s['heading'] ?? ''}'.trim().isNotEmpty &&
                    '${s['body'] ?? ''}'.trim().isNotEmpty,
              ),
          'Add a heading and copy to each text section in Page sections.',
        ),
      if (document['logo'] is Map || document['hero_image'] is Map)
        (
          'Add descriptions for your images',
          ['logo', 'hero_image'].every(
            (key) =>
                document[key] is! Map ||
                '${document[key]['alt'] ?? ''}'.trim().isNotEmpty,
          ),
          'Describe each selected image in Page images before publishing.',
        ),
    ];
    final complete = checks.where((c) => c.$2).length;
    return Container(
      decoration: BoxDecoration(
        color: WfStyle.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WfStyle.line),
      ),
      child: ExpansionTile(
        initiallyExpanded: complete < checks.length,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.fact_check_outlined,
          color: complete == checks.length ? WfStyle.cyan : WfStyle.gold,
        ),
        title: const Text(
          'Launch checklist',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$complete of ${checks.length} setup checks complete',
          style: const TextStyle(color: WfStyle.muted, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    c.$2
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: c.$2 ? WfStyle.cyan : WfStyle.gold,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (!c.$2)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              c.$3,
                              style: const TextStyle(
                                color: WfStyle.muted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (!c.$2 &&
                            onEditField != null &&
                            (c.$1 == 'Add a privacy-policy URL' ||
                                c.$1 == 'Add your business contact email'))
                          TextButton.icon(
                            onPressed: () => onEditField!(
                              c.$1 == 'Add a privacy-policy URL'
                                  ? 'privacy_url'
                                  : 'contact_email',
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              c.$1 == 'Add a privacy-policy URL'
                                  ? 'Edit privacy URL'
                                  : 'Edit contact email',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (document['brand'] == 'Your business')
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Make it yours: replace “Your business” and review the starter copy.',
                style: TextStyle(color: WfStyle.gold, height: 1.4),
              ),
            ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Review your offer and page preview before publishing. These checks do not verify your privacy page or email ownership.',
              style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit page details'),
                ),
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview page'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

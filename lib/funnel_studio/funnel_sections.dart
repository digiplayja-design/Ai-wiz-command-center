import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_images.dart';
import 'funnel_form_preview.dart';
import 'funnel_questions.dart';

List<Map<String, dynamic>> defaultFunnelSections() => [
  for (final kind in ['main_image', 'benefits', 'inquiry', 'faq'])
    {'kind': kind, 'visible': true},
];
List<Map<String, dynamic>> funnelSections(Map document) =>
    document['sections'] is List
    ? (document['sections'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
    : defaultFunnelSections();
String funnelSectionKey(Map section) => section['kind'] == 'text'
    ? section['id'].toString()
    : section['kind'].toString();
String funnelSectionTitle(Map section) => switch (section['kind']) {
  'main_image' => 'Main image',
  'benefits' => 'Benefits',
  'inquiry' => 'Inquiry form',
  'faq' => 'Questions & answers',
  _ => 'Text section',
};

class FunnelSectionEditor extends StatelessWidget {
  const FunnelSectionEditor({
    super.key,
    required this.document,
    required this.onChanged,
  });
  final Map<String, dynamic> document;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  void _move(List<Map<String, dynamic>> list, int from, int to) {
    final item = list.removeAt(from);
    list.insert(to, item);
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final sections = funnelSections(document);
    final customCount = sections.where((s) => s['kind'] == 'text').length;
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        title: const Text(
          'Page sections',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Arrange content and add text below your headline.',
          style: TextStyle(fontSize: 12, color: WfStyle.muted),
        ),
        children: [
          const Text(
            'Move sections with the arrows. Your headline stays first and the inquiry form stays available. Hidden sections keep their copy. Save and publish to change the live page.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < sections.length; i++)
            Container(
              key: ValueKey('section-editor-${funnelSectionKey(sections[i])}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: WfStyle.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${funnelSectionTitle(sections[i])}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        key: ValueKey(
                          'section-up-${funnelSectionKey(sections[i])}',
                        ),
                        tooltip:
                            'Move ${funnelSectionTitle(sections[i]).toLowerCase()} up',
                        onPressed: i == 0
                            ? null
                            : () => _move(funnelSections(document), i, i - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: ValueKey(
                          'section-down-${funnelSectionKey(sections[i])}',
                        ),
                        tooltip:
                            'Move ${funnelSectionTitle(sections[i]).toLowerCase()} down',
                        onPressed: i == sections.length - 1
                            ? null
                            : () => _move(funnelSections(document), i, i + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      if ([
                        'benefits',
                        'faq',
                      ].contains(sections[i]['kind'])) ...[
                        Switch(
                          key: ValueKey(
                            'section-visible-${sections[i]['kind']}',
                          ),
                          value: sections[i]['visible'] != false,
                          onChanged: (v) {
                            final next = funnelSections(document);
                            next[i]['visible'] = v;
                            onChanged(next);
                          },
                        ),
                        Text(
                          sections[i]['visible'] == false ? 'Hidden' : 'Shown',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      if (sections[i]['kind'] == 'text')
                        TextButton.icon(
                          key: ValueKey('section-remove-${sections[i]['id']}'),
                          onPressed: () {
                            final next = funnelSections(document);
                            next.removeAt(i);
                            onChanged(next);
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Remove'),
                        ),
                    ],
                  ),
                  if (sections[i]['kind'] == 'main_image')
                    const Text(
                      'Choose or remove this image in Page images.',
                      style: TextStyle(color: WfStyle.muted, fontSize: 11),
                    ),
                  if (sections[i]['kind'] == 'inquiry')
                    const Text(
                      'Required. Uses your selected single-page or guided form.',
                      style: TextStyle(color: WfStyle.muted, fontSize: 11),
                    ),
                  if (sections[i]['kind'] == 'text') ...[
                    TextFormField(
                      key: ValueKey('section-heading-${sections[i]['id']}'),
                      initialValue: sections[i]['heading'] as String? ?? '',
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Section heading',
                      ),
                      maxLines: 2,
                      onChanged: (v) {
                        final next = funnelSections(document);
                        next[i]['heading'] = v;
                        onChanged(next);
                      },
                    ),
                    TextFormField(
                      key: ValueKey('section-copy-${sections[i]['id']}'),
                      initialValue: sections[i]['body'] as String? ?? '',
                      maxLength: 1000,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Section copy',
                      ),
                      onChanged: (v) {
                        final next = funnelSections(document);
                        next[i]['body'] = v;
                        onChanged(next);
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Plain text. Complete both fields before publishing.',
                        style: TextStyle(
                          color: WfStyle.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: customCount >= 4
                  ? null
                  : () {
                      final next = funnelSections(document);
                      final id = [
                        for (var n = 1; n <= 4; n++) 'text-$n',
                      ].firstWhere((id) => !next.any((s) => s['id'] == id));
                      final formIndex = next.indexWhere(
                        (s) => s['kind'] == 'inquiry',
                      );
                      next.insert(formIndex, {
                        'kind': 'text',
                        'id': id,
                        'visible': true,
                        'heading': '',
                        'body': '',
                      });
                      onChanged(next);
                    },
              icon: const Icon(Icons.add),
              label: Text('Add text section ($customCount/4)'),
            ),
          ),
        ],
      ),
    );
  }
}

class FunnelSectionsPreview extends StatelessWidget {
  const FunnelSectionsPreview({
    super.key,
    required this.document,
    required this.client,
    required this.accent,
  });
  final Map<String, dynamic> document;
  final FunnelClient client;
  final Color accent;
  static const ink = Color(0xFF142B38), muted = Color(0xFF526776);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final section in funnelSections(document))
        if (section['visible'] != false)
          KeyedSubtree(
            key: ValueKey('page-preview-${funnelSectionKey(section)}'),
            child: _section(section),
          ),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Text(
          'Powered by KORLIX AI',
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ),
    ],
  );
  Widget _section(Map<String, dynamic> section) {
    final kind = section['kind'];
    if (kind == 'main_image') {
      final a = document['hero_image'];
      return a is Map
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FunnelPrivateImage(
                  client: client,
                  id: a['id'].toString(),
                  description: a['alt'].toString(),
                  height: 280,
                ),
              ),
            )
          : const SizedBox.shrink();
    }
    if (kind == 'inquiry') {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: FunnelFormPreview(
          document: document,
          questions: funnelQuestions(document),
          mode: document['form_mode'] as String? ?? 'single',
          brand: '${document['brand']}',
          cta: '${document['cta']}',
          accent: accent,
        ),
      );
    }
    if (kind == 'benefits') {
      final benefits = document['benefits'] as List;
      if (benefits.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final benefit in benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF147467),
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        benefit.toString(),
                        style: const TextStyle(color: ink, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (kind == 'faq') {
      final faq = document['faq'] as List;
      if (faq.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questions, answered.',
              style: TextStyle(
                color: ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final f in faq)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f['q'].toString(),
                      style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      f['a'].toString(),
                      style: const TextStyle(color: muted, height: 1.4),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E0E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${section['heading']}'.trim().isEmpty
                ? 'Your section heading'
                : '${section['heading']}',
            style: const TextStyle(
              color: ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${section['body']}'.trim().isEmpty
                ? 'Add the copy for this section.'
                : '${section['body']}',
            style: const TextStyle(color: muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

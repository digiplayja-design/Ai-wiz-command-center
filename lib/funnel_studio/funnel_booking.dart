import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_library.dart';
import 'funnel_questions.dart';

List<Map<String, dynamic>> funnelBookingRoutes(Map document) => [
  for (final r in document['booking_routes'] as List? ?? [])
    Map<String, dynamic>.from(r as Map),
];

bool funnelBookingRoutesComplete(Map document) {
  final routes = funnelBookingRoutes(document),
      questions = funnelQuestions(document);
  final seen = <String>{};
  for (final r in routes) {
    if ('${r['name'] ?? ''}'.trim().isEmpty ||
        '${r['button_label'] ?? ''}'.trim().isEmpty ||
        !funnelHttpsAddress('${r['url'] ?? ''}') ||
        !seen.add('${r['question_id']}\u0000${r['equals']}') ||
        !questions.any(
          (q) =>
              q['id'] == r['question_id'] &&
              q['type'] == 'choice' &&
              '${r['equals'] ?? ''}'.isNotEmpty &&
              funnelChoiceOptions(q).contains(r['equals']),
        )) {
      return false;
    }
  }
  return routes.length <= 4;
}

// A reused question ID must not silently reconnect a removed question's routes.
List<Map<String, dynamic>> bookingRoutesAfterQuestions(
  Map document,
  List<Map<String, dynamic>> questions,
) {
  final ids = questions.map((q) => q['id']).toSet();
  return [
    for (final r in funnelBookingRoutes(document))
      ids.contains(r['question_id'])
          ? r
          : {...r, 'question_id': '', 'equals': ''},
  ];
}

Map<String, dynamic> funnelBookingOutcome(
  Map document,
  Map<String, String> answers,
) {
  final active = visibleFunnelQuestions(
    funnelQuestions(document),
    answers,
  ).map((q) => q['id']).toSet();
  final matches = funnelBookingRoutes(document).where(
    (r) =>
        active.contains(r['question_id']) &&
        '${r['equals'] ?? ''}'.isNotEmpty &&
        answers[r['question_id']]?.trim() == r['equals'],
  );
  final route = matches.isEmpty ? null : matches.first;
  return {
    'route_id': route?['id'] ?? 'default',
    'route_name': route?['name'] ?? 'Default next step',
    'message': document['thank_you'] ?? 'Thank you.',
    'booking_url': route?['url'] ?? document['booking_url'] ?? '',
    'button_label': route?['button_label'] ?? 'Continue →',
  };
}

class FunnelBookingEditor extends StatelessWidget {
  const FunnelBookingEditor({
    super.key,
    required this.document,
    required this.onChanged,
  });
  final Map<String, dynamic> document;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  void change(int i, String field, String value) {
    final next = funnelBookingRoutes(document);
    next[i][field] = value;
    onChanged(next);
  }

  void move(int from, int to) {
    final next = funnelBookingRoutes(document);
    final r = next.removeAt(from);
    next.insert(to, r);
    onChanged(next);
  }

  Widget field(Map r, int i, String name, String label, int max) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('booking-$name-${r['id']}'),
      initialValue: '${r[name] ?? ''}',
      maxLength: max,
      maxLines: name == 'url' ? 2 : 1,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => change(i, name, v),
    ),
  );
  Widget rule(Map r, int i) {
    final sources = funnelQuestions(
      document,
    ).where((q) => q['type'] == 'choice').toList();
    final selected = '${r['question_id'] ?? ''}',
        value = '${r['equals'] ?? ''}';
    final source = sources.where((q) => q['id'] == selected);
    final options = source.isEmpty
        ? <String>[]
        : funnelChoiceOptions(source.first);
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('booking-question-${r['id']}-$selected'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'When this question'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Choose a question')),
            for (final q in sources)
              DropdownMenuItem(
                value: '${q['id']}',
                child: Text(
                  '${q['label']}'.isEmpty
                      ? 'Untitled question'
                      : '${q['label']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (selected.isNotEmpty && source.isEmpty)
              DropdownMenuItem(
                value: selected,
                child: const Text('Unavailable question — choose again'),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            final next = funnelBookingRoutes(document);
            next[i]['question_id'] = v;
            next[i]['equals'] = '';
            onChanged(next);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('booking-answer-${r['id']}-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Has this answer'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Choose an answer')),
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(
                  option,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (value.isNotEmpty && !options.contains(value))
              DropdownMenuItem(
                value: value,
                child: const Text('Unavailable answer — choose again'),
              ),
          ],
          onChanged: (v) {
            if (v != null) change(i, 'equals', v);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = funnelBookingRoutes(document);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: const Text(
          'Booking routes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Offer a next step based on an answer.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12),
        ),
        children: [
          const Text(
            'Add up to four routes using multiple-choice answers. The first matching route wins. Otherwise, visitors see your default booking link, if set. Hidden questions never match.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (!funnelQuestions(document).any((q) => q['type'] == 'choice'))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Add a multiple-choice question in Inquiry questions to use booking routes.',
                style: TextStyle(
                  color: WfStyle.gold,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          for (var i = 0; i < routes.length; i++)
            Container(
              key: ValueKey('booking-editor-${routes[i]['id']}'),
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
                    'Route ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        key: ValueKey('booking-up-${routes[i]['id']}'),
                        tooltip: 'Move route up',
                        onPressed: i == 0 ? null : () => move(i, i - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: ValueKey('booking-down-${routes[i]['id']}'),
                        tooltip: 'Move route down',
                        onPressed: i == routes.length - 1
                            ? null
                            : () => move(i, i + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      TextButton.icon(
                        key: ValueKey('booking-remove-${routes[i]['id']}'),
                        onPressed: () {
                          final next = funnelBookingRoutes(document);
                          next.removeAt(i);
                          onChanged(next);
                        },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                  field(routes[i], i, 'name', 'Route name (for your team)', 80),
                  rule(routes[i], i),
                  field(routes[i], i, 'url', 'Booking / next-step URL', 1000),
                  field(
                    routes[i],
                    i,
                    'button_label',
                    'Next-step button text',
                    60,
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('booking-add'),
              onPressed: routes.length >= 4
                  ? null
                  : () {
                      final next = funnelBookingRoutes(document);
                      final id = [
                        for (var i = 1; i <= 4; i++) 'route-$i',
                      ].firstWhere((id) => !next.any((r) => r['id'] == id));
                      next.add({
                        'id': id,
                        'name': '',
                        'question_id': '',
                        'equals': '',
                        'url': '',
                        'button_label': 'Book a time',
                      });
                      onChanged(next);
                    },
              icon: const Icon(Icons.add),
              label: Text('Add route (${routes.length}/4)'),
            ),
          ),
          const SizedBox(height: 12),
          if (routes.isNotEmpty && !funnelBookingRoutesComplete(document))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Complete every route and use each answer condition once before publishing.',
                style: TextStyle(
                  color: WfStyle.gold,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          const Text(
            'Use public HTTPS booking pages. Links appear after a successful inquiry; they do not confirm an appointment. Save and publish to change the live page. Follow-up templates use the default booking link.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class FunnelOutcomeSummary extends StatelessWidget {
  const FunnelOutcomeSummary({super.key, required this.outcome});
  final Map outcome;
  @override
  Widget build(BuildContext context) => outcome.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Next step offered',
                style: TextStyle(
                  color: WfStyle.violet,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text('${outcome['route_name']}'),
              if ('${outcome['booking_url'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${outcome['button_label']}'),
                SelectableText(
                  '${outcome['booking_url']}',
                  style: const TextStyle(color: WfStyle.cyan, fontSize: 13),
                ),
              ] else
                const Text(
                  'No next-step link was configured.',
                  style: TextStyle(color: WfStyle.muted, fontSize: 12),
                ),
              const SizedBox(height: 6),
              const Text(
                'Saved when submitted. This is not a confirmed appointment.',
                style: TextStyle(
                  color: WfStyle.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
}

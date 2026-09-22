import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';

List<Map<String, dynamic>> funnelQuestions(Map document) => [
  for (final q in document['questions'] as List? ?? [])
    {
      ...Map<String, dynamic>.from(q as Map),
      'options': List<String>.from(q['options'] as List? ?? []),
    },
];
bool funnelQuestionsComplete(Map document) =>
    funnelQuestions(document).every((q) {
      final options = q['options'] as List;
      return '${q['label']}'.trim().isNotEmpty &&
          (q['type'] != 'choice' ||
              (options.length >= 2 &&
                  options.length <= 8 &&
                  options.every(
                    (o) => '$o'.trim().isNotEmpty && '$o'.length <= 80,
                  ) &&
                  options.map((o) => '$o'.trim()).toSet().length ==
                      options.length));
    });

class FunnelQuestionEditor extends StatelessWidget {
  const FunnelQuestionEditor({
    super.key,
    required this.document,
    required this.onChanged,
  });
  final Map<String, dynamic> document;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  void change(int index, String field, dynamic value) {
    final next = funnelQuestions(document);
    next[index][field] = value;
    onChanged(next);
  }

  void move(int from, int to) {
    final next = funnelQuestions(document);
    final q = next.removeAt(from);
    next.insert(to, q);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final questions = funnelQuestions(document);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: const Text(
          'Inquiry questions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Ask about your visitor’s needs.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12),
        ),
        children: [
          const Text(
            'Add up to four questions. Answers appear in Leads after the visitor submits. Save and publish to change the live form.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < questions.length; i++)
            Container(
              key: ValueKey('question-editor-${questions[i]['id']}'),
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
                    'Question ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        key: ValueKey('question-up-${questions[i]['id']}'),
                        tooltip: 'Move question up',
                        onPressed: i == 0 ? null : () => move(i, i - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: ValueKey('question-down-${questions[i]['id']}'),
                        tooltip: 'Move question down',
                        onPressed: i == questions.length - 1
                            ? null
                            : () => move(i, i + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      TextButton.icon(
                        key: ValueKey('question-remove-${questions[i]['id']}'),
                        onPressed: () {
                          final next = funnelQuestions(document);
                          next.removeAt(i);
                          onChanged(next);
                        },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: ValueKey('question-label-${questions[i]['id']}'),
                    initialValue: questions[i]['label'] as String? ?? '',
                    maxLength: 120,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Question'),
                    onChanged: (v) => change(i, 'label', v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('question-type-${questions[i]['id']}'),
                    initialValue: questions[i]['type'] as String,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Answer type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'text',
                        child: Text('Text answer'),
                      ),
                      DropdownMenuItem(
                        value: 'choice',
                        child: Text('Multiple choice'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final next = funnelQuestions(document);
                      next[i]['type'] = v;
                      if (v == 'choice' &&
                          (next[i]['options'] as List).isEmpty) {
                        next[i]['options'] = <String>['', ''];
                      }
                      onChanged(next);
                    },
                  ),
                  if (questions[i]['type'] == 'choice') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('question-options-${questions[i]['id']}'),
                      initialValue: (questions[i]['options'] as List).join(
                        '\n',
                      ),
                      minLines: 3,
                      maxLines: 9,
                      maxLength: 647,
                      decoration: const InputDecoration(labelText: 'Choices'),
                      onChanged: (v) => change(i, 'options', v.split('\n')),
                    ),
                    const Text(
                      'One choice per line. Use 2–8 distinct choices, up to 80 characters each.',
                      style: TextStyle(
                        color: WfStyle.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Visitors can enter up to 500 characters.',
                        style: TextStyle(color: WfStyle.muted, fontSize: 12),
                      ),
                    ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Switch(
                        key: ValueKey(
                          'question-required-${questions[i]['id']}',
                        ),
                        value: questions[i]['required'] == true,
                        onChanged: (v) => change(i, 'required', v),
                      ),
                      Text(
                        questions[i]['required'] == true
                            ? 'Required'
                            : 'Optional',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: questions.length >= 4
                  ? null
                  : () {
                      final next = funnelQuestions(document);
                      final id = [
                        for (var i = 1; i <= 4; i++) 'q-$i',
                      ].firstWhere((id) => !next.any((q) => q['id'] == id));
                      next.add({
                        'id': id,
                        'type': 'text',
                        'label': '',
                        'required': false,
                        'options': <String>[],
                      });
                      onChanged(next);
                    },
              icon: const Icon(Icons.add),
              label: Text('Add question (${questions.length}/4)'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class FunnelAnswerSummary extends StatelessWidget {
  const FunnelAnswerSummary({super.key, required this.answers});
  final List answers;
  @override
  Widget build(BuildContext context) => answers.isEmpty
      ? const SizedBox.shrink()
      : Material(
          color: Colors.transparent,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(
              'Question answers (${answers.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            children: [
              for (final a in answers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a['label']}',
                        style: const TextStyle(
                          color: WfStyle.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        '${a['value']}'.isEmpty
                            ? 'Not provided'
                            : '${a['value']}',
                        style: const TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
}

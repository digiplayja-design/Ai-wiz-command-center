import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';

List<Map<String, dynamic>> funnelQuestions(Map document) => [
  for (final q in document['questions'] as List? ?? [])
    {
      ...Map<String, dynamic>.from(q as Map),
      'options': List<String>.from(q['options'] as List? ?? []),
      if (q['show_when'] is Map)
        'show_when': Map<String, dynamic>.from(q['show_when']),
    },
];
List<String> funnelChoiceOptions(Map question) =>
    (question['options'] as List? ?? [])
        .map((o) => '$o'.trim())
        .where((o) => o.isNotEmpty && o.length <= 80)
        .toSet()
        .toList();

bool funnelQuestionConditionValid(List<Map<String, dynamic>> questions, int i) {
  final rule = questions[i]['show_when'];
  if (rule == null) return true;
  if (rule is! Map) return false;
  return questions
      .take(i)
      .any(
        (q) =>
            q['id'] == rule['question_id'] &&
            q['type'] == 'choice' &&
            '${rule['equals'] ?? ''}'.isNotEmpty &&
            funnelChoiceOptions(q).contains(rule['equals']),
      );
}

bool funnelQuestionsComplete(Map document) {
  final questions = funnelQuestions(document);
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i], options = q['options'] as List;
    if ('${q['label']}'.trim().isEmpty ||
        !funnelQuestionConditionValid(questions, i) ||
        (q['type'] == 'choice' &&
            (options.length < 2 ||
                options.length > 8 ||
                options.any((o) => '$o'.trim().isEmpty || '$o'.length > 80) ||
                options.map((o) => '$o'.trim()).toSet().length !=
                    options.length))) {
      return false;
    }
  }
  return true;
}

List<Map<String, dynamic>> visibleFunnelQuestions(
  List<Map<String, dynamic>> questions,
  Map<String, String> answers,
) {
  final shown = <Map<String, dynamic>>[];
  for (final q in questions) {
    final rule = q['show_when'];
    if (rule == null ||
        (rule is Map &&
            shown.any(
              (p) =>
                  p['id'] == rule['question_id'] &&
                  p['type'] == 'choice' &&
                  '${rule['equals'] ?? ''}'.isNotEmpty &&
                  funnelChoiceOptions(p).contains(rule['equals']) &&
                  answers[p['id']]?.trim() == rule['equals'],
            ))) {
      shown.add(q);
    }
  }
  return shown;
}

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

  Widget _condition(List<Map<String, dynamic>> questions, int i) {
    final q = questions[i], rule = q['show_when'] as Map?;
    final sources = questions
        .take(i)
        .where((p) => p['type'] == 'choice')
        .toList();
    final selected = rule?['question_id'] as String? ?? '';
    final matches = sources.where((p) => p['id'] == selected).toList();
    final options = matches.isEmpty
        ? <String>[]
        : funnelChoiceOptions(matches.first);
    final value = rule?['equals'] as String? ?? '';
    final valid = funnelQuestionConditionValid(questions, i);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('question-condition-${q['id']}-$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Show this question'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Always')),
              for (final p in sources)
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(
                    'When: ${'${p['label']}'.trim().isEmpty ? 'Question ${questions.indexOf(p) + 1}' : p['label']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (selected.isNotEmpty && matches.isEmpty)
                DropdownMenuItem(
                  value: selected,
                  child: const Text('Unavailable question — choose again'),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              change(
                i,
                'show_when',
                v.isEmpty ? null : {'question_id': v, 'equals': ''},
              );
            },
          ),
          if (rule != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('question-condition-value-${q['id']}-$value'),
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Answer equals'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Choose an answer'),
                ),
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
                    child: const Text('Unavailable choice — choose again'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  change(i, 'show_when', {
                    'question_id': selected,
                    'equals': v,
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              valid
                  ? 'Required only when this question is shown.'
                  : 'Choose an earlier multiple-choice question and one of its current choices before publishing.',
              style: TextStyle(
                color: valid ? WfStyle.muted : Colors.amber,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'To show this only for certain answers, add a multiple-choice question above it.',
                style: TextStyle(
                  color: WfStyle.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
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
                          final removed = next.removeAt(i);
                          for (final dependent in next) {
                            final rule = dependent['show_when'];
                            if (rule is Map &&
                                rule['question_id'] == removed['id']) {
                              dependent['show_when'] = {...rule, 'equals': ''};
                            }
                          }
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
                  _condition(questions, i),
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

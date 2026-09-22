import 'dart:convert';
import 'package:flutter/material.dart';
import 'funnel_questions.dart';

class FunnelFormPreview extends StatefulWidget {
  const FunnelFormPreview({
    super.key,
    required this.mode,
    required this.brand,
    required this.cta,
    required this.accent,
    this.questions = const [],
  });
  final String mode, brand, cta;
  final Color accent;
  final List<Map<String, dynamic>> questions;
  @override
  State<FunnelFormPreview> createState() => _FunnelFormPreviewState();
}

class _FunnelFormPreviewState extends State<FunnelFormPreview> {
  int _step = 0;
  final Map<String, String> _answers = {};
  late String _questionSignature;
  @override
  void initState() {
    super.initState();
    _questionSignature = jsonEncode(widget.questions);
  }

  static const _ink = Color(0xFF142B38), _muted = Color(0xFF526776);
  @override
  void didUpdateWidget(covariant FunnelFormPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _step = 0;
    final signature = jsonEncode(widget.questions);
    if (signature != _questionSignature) {
      _answers.clear();
      _questionSignature = signature;
    }
  }

  Widget _field(String label, [String? sample]) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFD8E0E3)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
        if (sample != null) ...[
          const SizedBox(height: 5),
          Text(sample, style: const TextStyle(color: _ink, height: 1.4)),
        ],
      ],
    ),
  );

  Widget _choice(Map<String, dynamic> q) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('branch-preview-${q['id']}-${_answers[q['id']] ?? ''}'),
      initialValue: _answers[q['id']] ?? '',
      isExpanded: true,
      dropdownColor: Colors.white,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _ink),
      iconEnabledColor: _muted,
      decoration: InputDecoration(
        labelText:
            '${q['label']}${q['required'] == true ? ' *' : ' (optional)'}',
        labelStyle: const TextStyle(color: _muted),
        fillColor: Colors.white,
        filled: true,
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFD8E0E3)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text('Choose a sample answer'),
        ),
        for (final o in funnelChoiceOptions(q))
          DropdownMenuItem(
            value: o,
            child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _answers[q['id']] = v;
          final active = visibleFunnelQuestions(
            widget.questions,
            _answers,
          ).map((q) => q['id']).toSet();
          _answers.removeWhere((id, _) => !active.contains(id));
        });
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final guided = widget.mode == 'guided';
    final conditional = widget.questions.any((q) => q['show_when'] != null);
    final shown = visibleFunnelQuestions(widget.questions, _answers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (guided) ...[
          const Text(
            'Explore the three form steps',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  key: ValueKey('form-preview-step-$i'),
                  label: Text(['1 · Contact', '2 · Request', '3 · Review'][i]),
                  labelStyle: const TextStyle(color: _ink, fontSize: 12),
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFB5EEE7),
                  showCheckmark: false,
                  selected: _step == i,
                  onSelected: (_) => setState(() => _step = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          guided
              ? [
                  'Your contact details',
                  'Your request',
                  'Review your inquiry',
                ][_step]
              : 'Let’s connect',
          style: const TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        if (!guided || _step == 0) ...[
          _field('Your name *'),
          _field('Email address *'),
          _field('Phone (optional)'),
        ],
        if (!guided || _step == 1) ...[
          _field('How can we help? (optional)'),
          if (conditional)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Try the choices to explore each question path. Preview answers are not saved.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
            ),
          for (final q in shown)
            KeyedSubtree(
              key: ValueKey('question-preview-${q['id']}'),
              child: conditional && q['type'] == 'choice'
                  ? _choice(q)
                  : _field(
                      '${q['label'].toString().isEmpty ? 'Your question' : q['label']}${q['required'] == true ? ' *' : ' (optional)'}',
                      q['type'] == 'choice'
                          ? 'Choose one: ${(q['options'] as List).join(' · ')}'
                          : 'Text answer · up to 500 characters',
                    ),
            ),

          Text(
            '□ I agree that ${widget.brand} may contact me about this request.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'This does not subscribe you to marketing messages.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        if (guided && _step == 2) ...[
          const Text(
            'Sample details for preview',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _field('Name', 'Taylor Morgan'),
          _field('Email', 'taylor@example.com'),
          _field(
            'Your request',
            'I would like to learn more about your services.',
          ),
          for (final q in shown)
            _field(
              '${q['label']}',
              q['type'] == 'choice' && (q['options'] as List).isNotEmpty
                  ? conditional
                        ? (_answers[q['id']]?.isNotEmpty == true
                              ? _answers[q['id']]!
                              : 'Not provided')
                        : '${q['options'][0]}'
                  : 'Sample response',
            ),
          Text(
            'Visitors review their details and consent before pressing “${widget.cta}”. They can go back to edit.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: widget.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            !guided || _step == 2
                ? widget.cta
                : _step == 0
                ? 'Continue to request →'
                : 'Review inquiry →',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
          ),
        ),
        if (guided) ...[
          const SizedBox(height: 12),
          const Text(
            'Preview only. Only the final submission creates a lead; earlier steps do not save a partial inquiry.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }
}

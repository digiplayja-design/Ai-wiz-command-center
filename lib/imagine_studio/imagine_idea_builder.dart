import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';

/// A local writing aid. It does not call a model or create an image.
class ImagineIdeaBuilder extends StatefulWidget {
  const ImagineIdeaBuilder({super.key, required this.initialText});
  final String initialText;

  @override
  State<ImagineIdeaBuilder> createState() => _ImagineIdeaBuilderState();
}

class _ImagineIdeaBuilderState extends State<ImagineIdeaBuilder> {
  late final TextEditingController subject;
  final setting = TextEditingController();
  final detail = TextEditingController();
  String mood = '';
  String get description => [
    subject.text.trim(),
    if (setting.text.trim().isNotEmpty) 'Setting: ${setting.text.trim()}',
    if (mood.isNotEmpty) 'Mood: $mood',
    if (detail.text.trim().isNotEmpty) 'Details: ${detail.text.trim()}',
  ].join('\n\n');

  @override
  void initState() {
    super.initState();
    subject = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    subject.dispose();
    setting.dispose();
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final ready = subject.text.trim().isNotEmpty && description.length <= 8000;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Build your idea'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A few details can make a picture feel entirely yours.',
              style: TextStyle(color: skin.mutedText, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('imagine-idea-subject'),
              controller: subject,
              minLines: 2,
              maxLines: 5,
              maxLength: 8000,
              decoration: const InputDecoration(
                labelText: 'Your main idea',
                hintText: 'A floating glass house, my cafe launch, a portrait…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('imagine-idea-setting'),
              controller: setting,
              maxLength: 400,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Setting',
                helperText: 'Optional',
                hintText: 'Above the clouds at sunrise',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(
              'How should it feel?',
              style: TextStyle(color: skin.text, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final choice in [
                  'Dreamlike',
                  'Luxurious',
                  'Playful',
                  'Calm',
                  'Dramatic',
                  'Futuristic',
                ])
                  ChoiceChip(
                    label: Text(choice),
                    selected: mood == choice,
                    onSelected: (selected) =>
                        setState(() => mood = selected ? choice : ''),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('imagine-idea-detail'),
              controller: detail,
              maxLength: 600,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Special detail',
                helperText: 'Optional',
                hintText: 'Reflections in the glass, a tiny garden on the roof',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: skin.inputFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skin.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR DESCRIPTION',
                    style: TextStyle(
                      color: skin.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subject.text.trim().isEmpty
                        ? 'Start with your main idea above.'
                        : description,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: skin.text, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description.length > 8000
                  ? 'Shorten your idea by ${description.length - 8000} characters to continue.'
                  : 'Add this to the editor, then choose Create when you are ready.',
              style: TextStyle(
                color: description.length > 8000 ? skin.danger : skin.mutedText,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        KorlixActionButton(
          key: const Key('imagine-use-idea'),
          label: 'Use this idea',
          icon: Icons.north_east_rounded,
          accent: skin.secondary,
          onPressed: ready ? () => Navigator.pop(context, description) : null,
        ),
      ],
    );
  }
}

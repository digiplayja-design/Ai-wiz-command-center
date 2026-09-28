import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/korlix_action_button.dart';
import '../theme/korlix_action_grid.dart';

class KorlixChatTurn {
  const KorlixChatTurn({
    required this.id,
    required this.question,
    required this.answer,
    this.image,
    this.onOpenImage,
    this.onSaveImage,
    this.onDeleteQuestion,
    this.onDeleteAnswer,
  });
  final String id, question, answer;
  final Widget? image;
  final VoidCallback? onOpenImage,
      onSaveImage,
      onDeleteQuestion,
      onDeleteAnswer;
}

class KorlixChatTimeline extends StatelessWidget {
  const KorlixChatTimeline({
    super.key,
    required this.turns,
    required this.foreground,
    required this.accent,
    required this.surface,
    this.busy = false,
    this.pendingQuestion = '',
    this.status = 'Thinking through your request…',
    this.onStarter,
  });
  final List<KorlixChatTurn> turns;
  final Color foreground, accent, surface;
  final bool busy;
  final String pendingQuestion, status;
  final void Function(String prompt, bool image)? onStarter;

  Widget _question(String text, String id) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      key: ValueKey('question-$id'),
      margin: const EdgeInsets.only(left: 28, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SelectableText(
        text,
        style: TextStyle(color: foreground, fontSize: 15, height: 1.5),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty && !busy) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 28),
              const SizedBox(height: 14),
              Text(
                'What would you like to create?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask a question, work through an idea, or make a picture.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: .75),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  KorlixActionButton(
                    label: 'Help me write',
                    icon: Icons.edit_outlined,
                    size: KorlixButtonSize.compact,
                    onPressed: onStarter == null
                        ? null
                        : () => onStarter!('Help me write ', false),
                  ),
                  KorlixActionButton(
                    label: 'Explore an idea',
                    icon: Icons.lightbulb_outline,
                    size: KorlixButtonSize.compact,
                    onPressed: onStarter == null
                        ? null
                        : () => onStarter!('Help me think through ', false),
                  ),
                  KorlixActionButton(
                    label: 'Create a picture',
                    icon: Icons.image_outlined,
                    size: KorlixButtonSize.compact,
                    onPressed: onStarter == null
                        ? null
                        : () => onStarter!('', true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('chat-conversation'),
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      itemCount: turns.length + (busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (busy && index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pendingQuestion.isNotEmpty)
                _question(pendingQuestion, 'pending'),
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
          );
        }
        final turn = turns[turns.length - 1 - index + (busy ? 1 : 0)];
        return Column(
          key: ValueKey('turn-${turn.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (turn.question.isNotEmpty) ...[
              _question(turn.question, turn.id),
              if (turn.onDeleteQuestion != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Delete your question',
                    visualDensity: VisualDensity.compact,
                    onPressed: turn.onDeleteQuestion,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: foreground.withValues(alpha: .55),
                    ),
                  ),
                ),
            ],
            if (turn.answer.isNotEmpty || turn.image != null) ...[
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 17, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'KORLIX AI',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (turn.image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(color: surface, child: turn.image!),
                ),
                const SizedBox(height: 8),
              ],
              if (turn.answer.isNotEmpty)
                SelectableText(
                  turn.answer,
                  key: ValueKey('answer-${turn.id}'),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (turn.answer.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: turn.answer),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Answer copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('Copy'),
                    ),
                  if (turn.onOpenImage != null)
                    TextButton.icon(
                      onPressed: turn.onOpenImage,
                      icon: const Icon(Icons.open_in_full, size: 16),
                      label: const Text('Open image'),
                    ),
                  if (turn.onSaveImage != null)
                    TextButton.icon(
                      onPressed: turn.onSaveImage,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('Save image'),
                    ),
                  if (turn.onDeleteAnswer != null)
                    IconButton(
                      tooltip: 'Delete this answer',
                      onPressed: turn.onDeleteAnswer,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 17,
                        color: foreground.withValues(alpha: .55),
                      ),
                    ),
                ],
              ),
            ],
            Divider(height: 30, color: foreground.withValues(alpha: .10)),
          ],
        );
      },
    );
  }
}

class KorlixChatModeBar extends StatelessWidget {
  const KorlixChatModeBar({
    super.key,
    required this.imageMode,
    required this.busy,
    required this.onModeChanged,
    required this.size,
    required this.style,
    required this.onSizeChanged,
    required this.onStyleChanged,
  });
  final bool imageMode, busy;
  final void Function(bool) onModeChanged;
  final String size, style;
  final ValueChanged<String> onSizeChanged, onStyleChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KorlixActionGrid(
        compact: true,
        children: [
          KorlixActionButton(
            label: 'Chat',
            selected: !imageMode,
            expand: true,
            onPressed: busy ? null : () => onModeChanged(false),
          ),
          KorlixActionButton(
            label: 'Create image',
            selected: imageMode,
            expand: true,
            onPressed: busy ? null : () => onModeChanged(true),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        imageMode ? 'Extra-high image quality' : 'Astra · Extra high',
        style: const TextStyle(fontSize: 12),
      ),
      if (imageMode) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: size,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Shape',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '1024x1024', child: Text('Square')),
                  DropdownMenuItem(value: '1024x1536', child: Text('Portrait')),
                  DropdownMenuItem(
                    value: '1536x1024',
                    child: Text('Landscape'),
                  ),
                  DropdownMenuItem(value: 'auto', child: Text('Automatic')),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) onSizeChanged(v);
                      },
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                initialValue: style,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Style',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text('Follow my prompt'),
                  ),
                  DropdownMenuItem(value: 'photo', child: Text('Photographic')),
                  DropdownMenuItem(
                    value: 'illustration',
                    child: Text('Illustration'),
                  ),
                  DropdownMenuItem(
                    value: 'design',
                    child: Text('Graphic design'),
                  ),
                  DropdownMenuItem(
                    value: 'cinematic',
                    child: Text('Cinematic'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) onStyleChanged(v);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Describe the subject, setting, lighting, and any exact words to include.',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
      ],
    ],
  );
}

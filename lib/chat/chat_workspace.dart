import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/korlix_action_button.dart';
import '../theme/korlix_action_grid.dart';
import 'chat_workspace_copy.dart';

export 'chat_workspace_copy.dart';

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
    this.status,
    this.languageCode = 'en',
    this.onStarter,
  });
  final List<KorlixChatTurn> turns;
  final Color foreground, accent, surface;
  final bool busy;
  final String pendingQuestion, languageCode;
  final String? status;
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
    final copy = KorlixChatCopy(languageCode);
    if (turns.isEmpty && !busy) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 28),
              const SizedBox(height: 14),
              Text(
                copy.createTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.createSubtitle,
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
                    label: copy.helpWrite,
                    colorIdentity: 'Help me write',
                    icon: Icons.edit_outlined,
                    size: KorlixButtonSize.compact,
                    onPressed: onStarter == null
                        ? null
                        : () => onStarter!(copy.helpWritePrompt, false),
                  ),
                  KorlixActionButton(
                    label: copy.exploreIdea,
                    colorIdentity: 'Explore an idea',
                    icon: Icons.lightbulb_outline,
                    size: KorlixButtonSize.compact,
                    onPressed: onStarter == null
                        ? null
                        : () => onStarter!(copy.exploreIdeaPrompt, false),
                  ),
                  KorlixActionButton(
                    label: copy.createPicture,
                    colorIdentity: 'Create a picture',
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
                        status?.isNotEmpty == true ? status! : copy.thinking,
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
                    tooltip: copy.deleteQuestion,
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
                            SnackBar(
                              content: Text(copy.answerCopied),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: Text(copy.copy),
                    ),
                  if (turn.onOpenImage != null)
                    TextButton.icon(
                      onPressed: turn.onOpenImage,
                      icon: const Icon(Icons.open_in_full, size: 16),
                      label: Text(copy.openImage),
                    ),
                  if (turn.onSaveImage != null)
                    TextButton.icon(
                      onPressed: turn.onSaveImage,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text(copy.saveImage),
                    ),
                  if (turn.onDeleteAnswer != null)
                    IconButton(
                      tooltip: copy.deleteAnswer,
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
    this.languageCode = 'en',
  });
  final bool imageMode, busy;
  final void Function(bool) onModeChanged;
  final String size, style, languageCode;
  final ValueChanged<String> onSizeChanged, onStyleChanged;
  @override
  Widget build(BuildContext context) {
    final copy = KorlixChatCopy(languageCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KorlixActionGrid(
          compact: true,
          children: [
            KorlixActionButton(
              label: copy.chat,
              colorIdentity: 'Chat',
              selected: !imageMode,
              expand: true,
              onPressed: busy ? null : () => onModeChanged(false),
            ),
            KorlixActionButton(
              label: copy.createImage,
              colorIdentity: 'Create image',
              selected: imageMode,
              expand: true,
              onPressed: busy ? null : () => onModeChanged(true),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          imageMode ? copy.imageQuality : copy.chatQuality,
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
                  decoration: InputDecoration(
                    labelText: copy.shape,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '1024x1024',
                      child: Text(copy.square),
                    ),
                    DropdownMenuItem(
                      value: '1024x1536',
                      child: Text(copy.portrait),
                    ),
                    DropdownMenuItem(
                      value: '1536x1024',
                      child: Text(copy.landscape),
                    ),
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(copy.automatic),
                    ),
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
                  decoration: InputDecoration(
                    labelText: copy.style,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(copy.followPrompt),
                    ),
                    DropdownMenuItem(
                      value: 'photo',
                      child: Text(copy.photographic),
                    ),
                    DropdownMenuItem(
                      value: 'illustration',
                      child: Text(copy.illustration),
                    ),
                    DropdownMenuItem(
                      value: 'design',
                      child: Text(copy.graphicDesign),
                    ),
                    DropdownMenuItem(
                      value: 'cinematic',
                      child: Text(copy.cinematic),
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
          Text(
            copy.imageGuidance,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }
}

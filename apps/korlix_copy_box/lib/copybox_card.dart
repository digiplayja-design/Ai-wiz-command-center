import 'package:flutter/material.dart';

import 'copybox_store.dart';
import 'copybox_theme.dart';

enum CopyBoxAction {
  focus,
  share,
  paste,
  template,
  versions,
  duplicate,
  moveUp,
  moveDown,
  color,
  delete,
}

class CopyBoxCard extends StatefulWidget {
  const CopyBoxCard({
    super.key,
    required this.box,
    required this.number,
    required this.onChanged,
    required this.onCopy,
    required this.onAction,
    required this.onAi,
    this.busy = false,
  });
  final CopyBoxEntry box;
  final int number;
  final VoidCallback onChanged, onCopy;
  final ValueChanged<CopyBoxAction> onAction;
  final ValueChanged<String> onAi;
  final bool busy;
  @override
  State<CopyBoxCard> createState() => _CopyBoxCardState();
}

class _CopyBoxCardState extends State<CopyBoxCard> {
  late final _title = TextEditingController(text: widget.box.title);
  late final _text = TextEditingController(text: widget.box.text);
  late final _folder = TextEditingController(text: widget.box.folder);
  @override
  void didUpdateWidget(covariant CopyBoxCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final pair in [
      (_title, widget.box.title),
      (_text, widget.box.text),
      (_folder, widget.box.folder),
    ]) {
      if (pair.$1.text != pair.$2) {
        pair.$1.value = TextEditingValue(
          text: pair.$2,
          selection: TextSelection.collapsed(offset: pair.$2.length),
        );
      }
    }
  }

  void _edit(VoidCallback action) {
    action();
    widget.box.updated = DateTime.now().toUtc().toIso8601String();
    setState(() {});
    widget.onChanged();
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5F5F2) : copyboxInk;
    final colorIndex = widget.box.color.clamp(0, boxColors.length - 1).toInt();
    final words = _text.text.trim().isEmpty
        ? 0
        : _text.text.trim().split(RegExp(r'\s+')).length;
    return Container(
      key: ValueKey('box-panel-${widget.box.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (dark ? darkBoxColors : boxColors)[colorIndex],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ink.withValues(alpha: .06)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  widget.number.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: ink.withValues(alpha: .5),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: ValueKey('folder-${widget.box.id}'),
                    controller: _folder,
                    maxLength: 100,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: .75),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Add a folder',
                      counterText: '',
                      isDense: true,
                    ),
                    onChanged: (v) => _edit(() => widget.box.folder = v),
                  ),
                ),
                IconButton(
                  tooltip: widget.box.favorite
                      ? 'Remove favorite'
                      : 'Add to favorites',
                  onPressed: () =>
                      _edit(() => widget.box.favorite = !widget.box.favorite),
                  icon: Icon(
                    widget.box.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 22,
                  ),
                ),
                PopupMenuButton<CopyBoxAction>(
                  tooltip: 'Box options',
                  onSelected: widget.onAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: CopyBoxAction.focus,
                      child: Text('Focus editor'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.paste,
                      child: Text('Paste from clipboard'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.share,
                      child: Text('Share text'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.template,
                      child: Text('Fill template fields'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.versions,
                      child: Text('Version history'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.duplicate,
                      child: Text('Duplicate box'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.moveUp,
                      child: Text('Move up'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.moveDown,
                      child: Text('Move down'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.color,
                      child: Text('Change color'),
                    ),
                    const PopupMenuItem(
                      value: CopyBoxAction.delete,
                      child: Text('Move to trash'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('title-${widget.box.id}'),
              controller: _title,
              maxLength: 200,
              style: TextStyle(
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
                color: ink,
              ),
              decoration: InputDecoration(
                hintText: 'Give this box a title',
                counterText: '',
                hintStyle: TextStyle(
                  color: ink.withValues(alpha: .45),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: (v) => _edit(() => widget.box.title = v),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('text-${widget.box.id}'),
              controller: _text,
              minLines: 3,
              maxLines: null,
              maxLength: 100000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15, height: 1.65, color: ink),
              decoration: InputDecoration(
                hintText: 'A bright idea. A reply worth saving.\nYour next great sentence starts here.',
                counterText: '',
                hintStyle: TextStyle(
                  color: ink.withValues(alpha: .48),
                  fontSize: 15,
                  height: 1.65,
                ),
              ),
              onChanged: (v) => _edit(() => widget.box.text = v),
            ),
            const SizedBox(height: 18),
            Divider(color: ink.withValues(alpha: .10), height: 1),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  '$words words  ·  ${_text.text.length} characters',
                  style: TextStyle(
                    fontSize: 11,
                    color: ink.withValues(alpha: .6),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Improve with AI',
                      enabled:
                          !widget.busy && widget.box.text.trim().isNotEmpty,
                      onSelected: widget.onAi,
                      itemBuilder: (_) =>
                          [
                                'Polish',
                                'Shorten',
                                'Summarize',
                                'Professional email',
                                'Action items',
                                'Meeting notes',
                              ]
                              .map(
                                (a) => PopupMenuItem(value: a, child: Text(a)),
                              )
                              .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_outlined,
                              size: 16,
                              color: widget.busy
                                  ? ink.withValues(alpha: .4)
                                  : ink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.busy ? 'Working…' : 'Refine',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      key: ValueKey('copy-${widget.box.id}'),
                      onPressed: widget.onCopy,
                      style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: dark ? copyboxInk : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.content_copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

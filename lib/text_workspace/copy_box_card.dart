import 'package:flutter/material.dart';

import 'box_store.dart';

/// An independently editable Copy Box in the account's stacked workspace.
class CopyBoxCard extends StatefulWidget {
  const CopyBoxCard({
    super.key,
    required this.box,
    required this.number,
    required this.busy,
    required this.primary,
    required this.accent,
    required this.onAccent,
    required this.panelColor,
    required this.borderColor,
    required this.selectionColor,
    required this.onChanged,
    required this.onVersions,
    required this.onDuplicate,
    required this.onDelete,
    required this.onFillTemplate,
    required this.onCopy,
    required this.onAi,
  });

  final SavedBox box;
  final int number;
  final bool busy;
  final Color primary, accent, onAccent;
  final Color panelColor, borderColor, selectionColor;
  final VoidCallback onChanged;
  final VoidCallback onVersions, onDuplicate, onDelete, onFillTemplate;
  final Future<void> Function(String) onCopy, onAi;

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
    // AI drafts and version restores can update this model externally. Ordinary
    // typing leaves the controller and its cursor untouched.
    _sync(_title, widget.box.title);
    _sync(_text, widget.box.text);
    _sync(_folder, widget.box.folder);
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _edit(VoidCallback change) {
    change();
    widget.box.updated = DateTime.now().toIso8601String();
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
    final words = _text.text.trim().isEmpty
        ? 0
        : _text.text.trim().split(RegExp(r'\s+')).length;
    return Container(
      key: ValueKey('copy-box-card-panel-${widget.box.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.panelColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Copy Box ${widget.number}',
                  style: TextStyle(
                    color: widget.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.box.favorite
                    ? 'Remove Copy Box ${widget.number} from favorites'
                    : 'Favorite Copy Box ${widget.number}',
                color: widget.primary,
                onPressed: () =>
                    _edit(() => widget.box.favorite = !widget.box.favorite),
                icon: Icon(
                  widget.box.favorite ? Icons.star : Icons.star_border,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('copy-box-title-${widget.box.id}'),
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (value) => _edit(() => widget.box.title = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('copy-box-folder-${widget.box.id}'),
            controller: _folder,
            decoration: const InputDecoration(
              labelText: 'Folder / category',
              hintText: 'e.g. Clients, Meetings, Personal',
            ),
            onChanged: (value) => _edit(() => widget.box.folder = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('copy-box-text-${widget.box.id}'),
            controller: _text,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Saved text',
              hintText:
                  'Write reusable text. Use {{client}} for template fields.',
            ),
            onChanged: (value) => _edit(() => widget.box.text = value),
          ),
          const SizedBox(height: 8),
          Text('$words words • ${_text.text.length} characters'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: widget.onAccent,
                ),
                onPressed: () => widget.onCopy(_text.text),
                icon: const Icon(Icons.copy),
                label: Text('Copy Box ${widget.number}'),
              ),
              OutlinedButton(
                onPressed: widget.busy ? null : widget.onFillTemplate,
                child: const Text('Fill template'),
              ),
              PopupMenuButton<String>(
                enabled: !widget.busy && _text.text.trim().isNotEmpty,
                onSelected: widget.onAi,
                itemBuilder: (_) => [
                  'Polish',
                  'Summarize',
                  'Action items',
                  'Meeting notes',
                  'Professional email',
                  'Shorten',
                ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.selectionColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.borderColor),
                  ),
                  child: Text(
                    widget.busy
                        ? 'Creating AI draft…'
                        : 'Improve with KORLIX ▾',
                    style: TextStyle(
                      color: widget.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.busy ? null : widget.onVersions,
                child: const Text('Versions'),
              ),
              TextButton(
                onPressed: widget.busy ? null : widget.onDuplicate,
                child: const Text('Duplicate'),
              ),
              TextButton(
                onPressed: widget.busy ? null : widget.onDelete,
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

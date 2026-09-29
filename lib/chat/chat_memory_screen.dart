import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import 'chat_memory_client.dart';

const memoryCategories = <String, String>{
  'general': 'General',
  'personal': 'About me',
  'preferences': 'Preferences',
  'work': 'Work',
  'goals': 'Goals',
};

class ChatMemoryButton extends StatelessWidget {
  const ChatMemoryButton({
    super.key,
    required this.client,
    required this.onPressed,
  });
  final ChatMemoryClient client;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: client,
    builder: (_, _) => KorlixActionButton(
      key: const Key('main-chat-memory'),
      label: !client.loaded
          ? 'Memory'
          : client.enabled
          ? 'Memory on'
          : 'Memory paused',
      subtitle: !client.loaded
          ? 'Remember across chats'
          : '${client.items.length} saved · Manage',
      icon: Icons.psychology_alt_outlined,
      selected: client.loaded && client.enabled,
      expand: true,
      onPressed: onPressed,
    ),
  );
}

class ChatMemoryScreen extends StatefulWidget {
  const ChatMemoryScreen({super.key, required this.client});
  final ChatMemoryClient client;
  @override
  State<ChatMemoryScreen> createState() => _ChatMemoryScreenState();
}

class _ChatMemoryScreenState extends State<ChatMemoryScreen> {
  String _query = '', _category = 'all';
  ChatMemoryClient get client => widget.client;
  @override
  void initState() {
    super.initState();
    client.load();
  }

  Future<bool> _confirm(String title, String message, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _edit([MemoryNote? note]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => MemoryEditor(client: client, note: note),
    );
  }

  Future<void> _forget(MemoryNote note) async {
    if (await _confirm(
          'Forget this memory?',
          '${note['body']}\n\nThis removes the saved note. Existing chat messages stay in their conversations.',
          'Forget',
        ) &&
        mounted) {
      await client.forget('${note['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Long-term memory'),
        actions: [
          IconButton(
            tooltip: 'Refresh memories',
            onPressed: client.busy ? null : client.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: client,
        builder: (context, _) {
          if (!client.available) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(client.error ?? 'Sign in to open memory.'),
              ),
            );
          }
          final notes = client.items
              .where(
                (n) =>
                    (_category == 'all' || n['category'] == _category) &&
                    '${n['body']}'.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _MemoryPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            MemoryOrb(active: client.enabled),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MAIN CHAT',
                                    style: TextStyle(
                                      color: s.primary,
                                      letterSpacing: 2,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Your context,\nremembered.',
                                    style: TextStyle(
                                      fontSize: 27,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Keep the details that make KORLIX more helpful: your preferences, work, goals and the things that matter to you.',
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Type or dictate “Remember that I prefer concise answers.” Saved notes carry into future main chats on your account, across devices.',
                          style: TextStyle(color: s.mutedText, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use long-term memory'),
                          subtitle: Text(
                            client.enabled
                                ? 'Saved notes help personalize main-chat answers.'
                                : 'Paused. Saved notes stay here and are not added to new requests.',
                          ),
                          value: client.enabled,
                          onChanged: client.busy || !client.loaded
                              ? null
                              : client.setEnabled,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You choose what is saved. Pausing does not erase the current conversation. Saved notes used in a request are shared with the chat AI provider. Avoid passwords and access codes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: s.mutedText,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${client.items.length} / 100 memories',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      KorlixActionButton(
                        label: 'Add memory',
                        icon: Icons.add_rounded,
                        onPressed:
                            !client.loaded ||
                                client.busy ||
                                client.items.length >= 100
                            ? null
                            : () => _edit(),
                      ),
                    ],
                  ),
                  if (client.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (client.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            client.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: client.busy ? null : client.load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh memories'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search your memories',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final e in {
                        'all': 'All',
                        ...memoryCategories,
                      }.entries)
                        FilterChip(
                          label: Text(e.value),
                          selected: _category == e.key,
                          onSelected: (_) => setState(() => _category = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (notes.isEmpty && client.loaded)
                    _MemoryPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.auto_awesome_outlined, color: s.primary),
                          const SizedBox(height: 12),
                          Text(
                            client.items.isEmpty
                                ? 'Start with something useful.'
                                : 'No matching memories.',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            client.items.isEmpty
                                ? 'Add a detail here, or start a main-chat message with “Remember that…”. Only details you explicitly save appear here.'
                                : 'Try another search or category.',
                          ),
                        ],
                      ),
                    ),
                  for (final note in notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MemoryPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memoryCategories['${note['category']}'] ??
                                  'General',
                              style: TextStyle(
                                color: s.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SelectableText(
                              '${note['body']}',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                TextButton.icon(
                                  key: ValueKey('edit-${note['id']}'),
                                  onPressed: client.busy
                                      ? null
                                      : () => _edit(note),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Edit'),
                                ),
                                TextButton.icon(
                                  key: ValueKey('forget-${note['id']}'),
                                  onPressed: client.busy
                                      ? null
                                      : () => _forget(note),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Forget'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (client.items.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: client.busy
                          ? null
                          : () async {
                              if (await _confirm(
                                    'Forget all saved memories?',
                                    'This permanently removes every saved main-chat note on your account. Existing chat messages and agent memories stay in their own sections.',
                                    'Forget all',
                                  ) &&
                                  mounted) {
                                await client.clear();
                              }
                            },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Forget all memories'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MemoryEditor extends StatefulWidget {
  const MemoryEditor({super.key, required this.client, this.note});
  final ChatMemoryClient client;
  final MemoryNote? note;
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.note?['body'] as String? ?? '',
  );
  late String _category = widget.note?['category'] as String? ?? 'general';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) {
      if (!widget.client.available) {
        return const AlertDialog(
          content: Text(
            'Your session changed. Close this window and sign in again.',
          ),
        );
      }
      return AlertDialog(
        title: Text(widget.note == null ? 'Add a memory' : 'Edit memory'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'One clear detail works best. You can change or forget it at any time.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('memory-note-input'),
                  controller: _text,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Memory note',
                    hintText:
                        'I prefer practical examples and concise answers.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: memoryCategories.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _category = v!),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    if (_text.text.trim().isEmpty) {
                      setState(() => _error = 'Write a detail to remember.');
                      return;
                    }
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    final saved = await widget.client.save(
                      _text.text,
                      _category,
                      previous: widget.note,
                    );
                    if (!context.mounted) return;
                    if (saved) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _saving = false;
                        _error =
                            widget.client.error ?? 'Refresh before retrying.';
                      });
                    }
                  },
            child: Text(_saving ? 'Saving…' : 'Save memory'),
          ),
        ],
      );
    },
  );
}

class _MemoryPanel extends StatelessWidget {
  const _MemoryPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(s.primary.withValues(alpha: .09), s.panelSoft),
            s.panelDeep,
          ],
        ),
        border: Border.all(color: s.border.withValues(alpha: .6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: s.isLight ? .06 : .3),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MemoryOrb extends StatelessWidget {
  const MemoryOrb({super.key, required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context), color = active ? s.primary : s.mutedText;
    return ExcludeSemantics(
      child: SizedBox(
        width: 76,
        height: 86,
        child: CustomPaint(
          painter: _MemoryOrbit(color),
          child: Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-.4, -.5),
                  colors: [
                    Color.lerp(color, Colors.white, .6)!,
                    color.withValues(alpha: .5),
                    s.panelDeep,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .24),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.psychology_alt_outlined,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryOrbit extends CustomPainter {
  _MemoryOrbit(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.translate(c.dx, c.dy);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 3);
      canvas.drawOval(
        const Rect.fromLTWH(-37, -22, 74, 44),
        Paint()
          ..color = color.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9,
      );
      canvas.drawCircle(const Offset(34, 8), 2.2, Paint()..color = color);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MemoryOrbit oldDelegate) => oldDelegate.color != color;
}

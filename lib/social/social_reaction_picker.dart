import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_media_widgets.dart';

class SocialReaction {
  const SocialReaction(this.id, this.label, this.category, this.keywords);
  final String id, label, category, keywords;
  String asset(String kind) =>
      'assets/social_reactions/$id.${kind == 'gif' ? 'gif' : 'png'}';
  bool matches(String query) {
    final text = '$label $category $keywords'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

Future<List<SocialReaction>> loadSocialReactions() async {
  final rows =
      jsonDecode(
            await rootBundle.loadString('assets/social_reactions/catalog.json'),
          )
          as List;
  return rows
      .map(
        (r) =>
            SocialReaction(r['id'], r['label'], r['category'], r['keywords']),
      )
      .toList();
}

Future<SocialAttachmentDraft?> pickSocialReactionFile(String kind) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: kind == 'gif' ? ['gif'] : ['png', 'webp', 'jpg', 'jpeg'],
    withData: false,
    withReadStream: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  const max = 20 * 1024 * 1024;
  if (file.size > max) {
    throw const SocialException('Choose a file smaller than 20 MB.');
  }
  final data = BytesBuilder(copy: false);
  if (file.bytes != null) {
    data.add(file.bytes!);
  } else if (file.readStream != null) {
    await for (final chunk in file.readStream!) {
      data.add(chunk);
      if (data.length > max) {
        throw const SocialException('Choose a file smaller than 20 MB.');
      }
    }
  }
  if (data.isEmpty || data.length > max) {
    throw const SocialException(
      'This file could not be read. Choose another one.',
    );
  }
  return SocialAttachmentDraft(
    bytes: data.takeBytes(),
    filename: file.name,
    kind: kind,
  );
}

/// Only a local draft leaves this sheet. Sending always remains a chat action.
class SocialReactionSheet extends StatefulWidget {
  const SocialReactionSheet({
    super.key,
    required this.client,
    required this.initialKind,
    this.uploadPicker,
  });
  final SocialClient client;
  final String initialKind;
  final Future<SocialAttachmentDraft?> Function(String)? uploadPicker;
  @override
  State<SocialReactionSheet> createState() => _SocialReactionSheetState();
}

class _SocialReactionSheetState extends State<SocialReactionSheet> {
  final _search = TextEditingController();
  List<SocialReaction> _catalog = [];
  late String _kind = widget.initialKind;
  String _category = 'All';
  String? _error, _label;
  bool _loading = true, _busy = false;
  SocialAttachmentDraft? _selected;
  int _request = 0;
  bool get _active => mounted && widget.client.available;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    _load();
  }

  @override
  void dispose() {
    _request++;
    widget.client.removeListener(_access);
    _search.dispose();
    super.dispose();
  }

  void _access() {
    if (!mounted || widget.client.available) return;
    _request++;
    setState(() {
      _selected = null;
      _search.clear();
      _busy = false;
      _error = 'Your session changed. Close this picker and sign in again.';
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await loadSocialReactions();
      if (_active) setState(() => _catalog = catalog);
    } catch (_) {
      if (_active) {
        setState(
          () => _error =
              'The reaction collection could not load. Try again, or upload your own.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose([SocialReaction? reaction]) async {
    if (_busy || !_active) return;
    FocusScope.of(context).unfocus();
    final request = ++_request, kind = _kind;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SocialAttachmentDraft? draft;
      if (reaction == null) {
        draft = await (widget.uploadPicker ?? pickSocialReactionFile)(kind);
      } else {
        final bytes = await rootBundle.load(reaction.asset(kind));
        draft = SocialAttachmentDraft(
          bytes: bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
          filename: '${reaction.label}.${kind == 'gif' ? 'gif' : 'png'}',
          kind: kind,
        );
      }
      if (!_active || request != _request || draft == null) return;
      if (draft.bytes.isEmpty || draft.bytes.length > 20 * 1024 * 1024) {
        throw const SocialException('Choose a file smaller than 20 MB.');
      }
      // Check the GIF signature here; the server independently decodes,
      // validates and re-encodes all frames before accepting any upload.
      if (kind == 'gif' &&
          (draft.bytes.length < 6 ||
              !['GIF87a', 'GIF89a'].contains(
                ascii.decode(draft.bytes.sublist(0, 6), allowInvalid: true),
              ))) {
        throw const SocialException(
          'Choose a GIF file. Use Stickers for still images.',
        );
      }
      if (!_active || request != _request) return;
      setState(() {
        _selected = draft;
        _label = reaction?.label ?? draft!.filename;
      });
    } catch (error) {
      if (_active && request == _request) {
        setState(
          () => _error = error is SocialException
              ? error.message
              : 'Could not open this reaction. Try again.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context), gif = _kind == 'gif';
    final items = _catalog
        .where(
          (r) =>
              (_category == 'All' || r.category == _category) &&
              r.matches(_search.text),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'GIFs & stickers',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close GIFs and stickers',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'gif',
                  label: Text('GIFs'),
                  icon: Icon(Icons.gif_box_outlined),
                ),
                ButtonSegment(
                  value: 'sticker',
                  label: Text('Stickers'),
                  icon: Icon(Icons.auto_awesome_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy || !_active
                  ? null
                  : (value) => setState(() {
                      _kind = value.single;
                      _selected = null;
                      _error = null;
                    }),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_selected != null) ...[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        _label ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 240,
                        child: SocialReactionImage(
                          provider: MemoryImage(_selected!.bytes),
                          animated: gif,
                          label: _label ?? (gif ? 'GIF' : 'Sticker'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Add it to your message, then tap Send.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: skin.mutedText),
                      ),
                    ],
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _selected = null),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Choose another'),
                  ),
                  FilledButton.icon(
                    onPressed: !_active || _busy
                        ? null
                        : () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.add),
                    label: Text(gif ? 'Use GIF' : 'Use sticker'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                enabled: _active && !_busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search reactions…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in [
                      'All',
                      'Greetings',
                      'Reactions',
                      'Love',
                      'Celebrate',
                      'Everyday',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: !_active || _busy
                              ? null
                              : (_) => setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'KORLIX Originals · ${_catalog.length}',
                        style: TextStyle(color: skin.mutedText, fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: !_active || _busy ? null : () => _choose(),
                      icon: const Icon(Icons.upload_rounded),
                      label: Text(gif ? 'Upload GIF' : 'Upload sticker'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _catalog.isEmpty
                    ? Center(
                        child: TextButton(
                          onPressed: _active ? _load : null,
                          child: const Text('Reload collection'),
                        ),
                      )
                    : items.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching reactions. Try “love”, “hello” or “thanks”.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          final columns = box.maxWidth >= 640
                              ? 4
                              : box.maxWidth >= 430
                              ? 3
                              : 2;
                          return GridView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  childAspectRatio: .94,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return Material(
                                color: skin.inputFill,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  key: ValueKey('reaction-${item.id}'),
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: !_active || _busy
                                      ? null
                                      : () {
                                          FocusScope.of(context).unfocus();
                                          _choose(item);
                                        },
                                  child: Semantics(
                                    button: true,
                                    label:
                                        '${item.label} ${gif ? 'GIF' : 'sticker'}',
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Image.asset(
                                              item.asset('sticker'),
                                              fit: BoxFit.contain,
                                              excludeFromSemantics: true,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            0,
                                            4,
                                            8,
                                          ),
                                          child: Text(
                                            gif ? 'Preview GIF' : item.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: skin.mutedText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:korlix_auth_core/privacy/korlix_third_party_ai_consent.dart';

import 'copybox_auth.dart';
import 'copybox_auth_screen.dart';
import 'copybox_card.dart';
import 'copybox_dialogs.dart';
import 'copybox_store.dart';
import 'copybox_theme.dart';

class CopyBoxHome extends StatefulWidget {
  const CopyBoxHome({
    super.key,
    required this.prefs,
    required this.auth,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final SharedPreferences prefs;
  final CopyBoxAuthController auth;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeChanged;
  @override
  State<CopyBoxHome> createState() => _CopyBoxHomeState();
}

class _CopyBoxHomeState extends State<CopyBoxHome> with WidgetsBindingObserver {
  late final _store = CopyBoxStore(
    widget.prefs,
    widget.auth.accountScope ?? 'local',
  );
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _anchors = <String, GlobalKey>{};
  List<CopyBoxEntry> _boxes = [];
  String _status = 'Saved on this device', _query = '';
  String? _folder, _busyId;
  bool _favorites = false,
      _loadFailed = false,
      _saveFailed = false,
      _working = false;
  int _section = 0;
  Timer? _saveTimer;
  late final Future<PackageInfo> _package = PackageInfo.fromPlatform();
  List<CopyBoxEntry> get _active => _boxes.where((b) => !b.trashed).toList();
  List<CopyBoxEntry> get _visible => filterEntries(
    _boxes,
    query: _query,
    folder: _folder,
    favoritesOnly: _favorites,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _load() {
    try {
      _boxes = _store.load();
      if (_boxes.isEmpty) {
        _boxes = List.generate(
          12,
          (i) => CopyBoxEntry(title: '', color: i % boxColors.length),
        );
      }
      _loadFailed = false;
    } catch (_) {
      _loadFailed = true;
      _status =
          'Saved data could not be read. Existing data has been preserved.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_save());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // The store captures a deep snapshot before queueing; an old account's
    // pending save never writes into the next account's workspace.
    if (!_loadFailed) unawaited(_store.save(_boxes).catchError((Object _) {}));
    _scroll.dispose();
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _message(String value, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(value), action: action));
  }

  void _changed() {
    if (_loadFailed) return;
    setState(() => _status = 'Saving…');
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_save()),
    );
  }

  Future<bool> _save({bool announce = false}) async {
    _saveTimer?.cancel();
    if (_loadFailed) return false;
    try {
      await _store.save(_boxes);
      if (mounted) {
        setState(() {
          _status = 'Saved on this device';
          _saveFailed = false;
        });
        if (announce) _message('All boxes saved.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'Save failed. Export a backup or retry Save All.';
          _saveFailed = true;
        });
      }
      return false;
    }
  }

  Future<void> _newBox({
    String title = '',
    String text = '',
    String folder = '',
  }) async {
    if (_loadFailed || _boxes.length >= 1000) {
      _message(
        'This workspace is full. Export a backup and clear unused boxes.',
      );
      return;
    }
    final box = CopyBoxEntry(
      title: title.length > copyBoxMaxTitleLength
          ? title.substring(0, copyBoxMaxTitleLength)
          : title,
      text: text,
      folder: folder,
      color: _active.length % boxColors.length,
    );
    setState(() {
      _boxes.add(box);
      _section = 0;
      _query = '';
      _folder = null;
      _favorites = false;
      _search.clear();
    });
    await _save();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _anchors[box.id]?.currentContext;
      if (mounted && target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: .1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
          ),
        );
      }
    });
  }

  Future<void> _copy(String text) async {
    if (text.trim().isEmpty) {
      _message('Write something in this box first.');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _message('Copied. Ready wherever you need it.');
    } catch (_) {
      _message(
        'Copy was unavailable. Select the text and use your device’s Copy action.',
      );
    }
  }

  Rect get _shareOrigin {
    final render = context.findRenderObject();
    if (render is RenderBox && render.hasSize) {
      return render.localToGlobal(Offset.zero) & Size(render.size.width, 80);
    }
    return const Rect.fromLTWH(0, 0, 100, 80);
  }

  Future<void> _shareText(String text, String title) async {
    if (text.trim().isEmpty) {
      _message('Add some text before sharing.');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          title: title,
          sharePositionOrigin: _shareOrigin,
        ),
      );
    } catch (_) {
      _message('Sharing could not open. Use Copy instead.');
    }
  }

  Future<void> _export({bool plainText = false}) async {
    if (_loadFailed || _working) return;
    setState(() => _working = true);
    try {
      final contents = plainText
          ? _active
                .where((b) => b.text.isNotEmpty)
                .map(
                  (b) =>
                      '${b.title.isEmpty ? 'Untitled box' : b.title}\n${b.text}',
                )
                .join('\n\n────────\n\n')
          : exportBackup(_boxes);
      final bytes = Uint8List.fromList(utf8.encode(contents));
      final name =
          'KORLIX_COPY_Box_${DateTime.now().toIso8601String().substring(0, 10)}.${plainText ? 'txt' : 'json'}';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save COPY Box backup',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [plainText ? 'txt' : 'json'],
        bytes: bytes,
      );
      if (mounted && path != null) {
        _message('Export saved. Keep your backup in a safe place.');
      }
    } catch (_) {
      _message(
        'Export could not be saved. Try Share backup or copy your boxes.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareBackup() async {
    if (_loadFailed || _working) return;
    setState(() => _working = true);
    try {
      const filename = 'KORLIX_COPY_Box_Backup.json';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(exportBackup(_boxes))),
              mimeType: 'application/json',
              name: filename,
            ),
          ],
          fileNameOverrides: const [filename],
          sharePositionOrigin: _shareOrigin,
        ),
      );
    } catch (_) {
      _message('Backup sharing could not open. Try Save backup.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import({bool plainText = false}) async {
    if (_loadFailed || _working) return;
    setState(() => _working = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: plainText ? ['txt', 'md'] : ['json'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > 5 * 1024 * 1024 || file.bytes == null) {
        throw const FormatException(
          'Choose a readable file smaller than 5 MB.',
        );
      }
      final imported = parseImport(
        utf8.decode(file.bytes!),
        plainText: plainText,
      );
      if (_boxes.length + imported.length > 1000) {
        throw const FormatException(
          'There is not enough room. The workspace limit is 1,000 boxes, including trash.',
        );
      }
      // Validate the complete combined snapshot before offering an import.
      exportBackup([..._boxes, ...imported]);
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(
            'Import ${imported.length} ${imported.length == 1 ? 'box' : 'boxes'}?',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These will be added as new boxes. Your current boxes will stay in place. Imported backups may contain private text and older versions. Boxes marked as trash can be restored from Backup → Open trash.',
                  ),
                  const SizedBox(height: 20),
                  for (final box in imported.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${box.title.isEmpty ? 'Untitled box' : box.title}\n${box.text.length} characters',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (imported.length > 8)
                    Text('…and ${imported.length - 8} more'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Import boxes'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
      setState(() {
        _boxes.addAll(imported);
        _section = 0;
        _query = '';
        _folder = null;
        _favorites = false;
        _search.clear();
      });
      if (await _save()) _message('${imported.length} boxes imported.');
    } catch (error) {
      _message(
        error is FormatException
            ? error.message
            : error is CopyBoxDataException
            ? error.toString()
            : 'This file could not be imported. Your existing boxes are unchanged.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _boxAction(CopyBoxEntry box, CopyBoxAction action) async {
    if (_loadFailed || !_boxes.contains(box) || box.trashed) return;
    switch (action) {
      case CopyBoxAction.focus:
        final before = box.text;
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => CopyBoxFocusEditor(title: box.title, text: before),
          ),
        );
        if (!mounted || result == null) return;
        if (box.text != before || box.trashed) {
          _message(
            'The original changed while editing. Save the new text in another box.',
          );
          return;
        }
        setState(() => box.replace(result));
        await _save();
      case CopyBoxAction.share:
        await _shareText(box.text, box.title);
      case CopyBoxAction.paste:
        try {
          final clip = await Clipboard.getData(Clipboard.kTextPlain);
          if (!mounted ||
              clip?.text?.isNotEmpty != true ||
              !_boxes.contains(box) ||
              box.trashed) {
            return;
          }
          final combined = box.text.isEmpty
              ? clip!.text!
              : '${box.text}\n${clip!.text!}';
          if (combined.length > 100000) {
            _message('The combined text is too long for one box.');
            return;
          }
          setState(() => box.replace(combined));
          await _save();
        } catch (_) {
          _message(
            'Paste could not access the clipboard. Try the text field’s Paste action.',
          );
        }
      case CopyBoxAction.template:
        final rendered = await fillCopyBoxTemplate(context, box.text);
        if (mounted && rendered != null) await _copy(rendered);
      case CopyBoxAction.versions:
        if (box.history.isEmpty) {
          _message(
            'Versions appear after a replacement, paste, AI edit, or restoration.',
          );
          return;
        }
        final before = box.text;
        final value = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Version history'),
            content: SizedBox(
              width: 520,
              height: 360,
              child: ListView(
                children: [
                  for (final entry in box.history.indexed)
                    ListTile(
                      title: Text('Version ${entry.$1 + 1}'),
                      subtitle: Text(
                        entry.$2,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.restore),
                      onTap: () => Navigator.pop(dialog, entry.$2),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Keep current'),
              ),
            ],
          ),
        );
        if (!mounted || value == null) return;
        if (box.text != before || box.trashed) {
          _message('This box changed. Open history again to restore safely.');
          return;
        }
        setState(() => box.replace(value));
        await _save();
        _message('Version restored. The previous text is also in history.');
      case CopyBoxAction.duplicate:
        await _newBox(
          title: '${box.title.isEmpty ? 'Untitled box' : box.title} (copy)',
          text: box.text,
          folder: box.folder,
        );
      case CopyBoxAction.moveUp:
      case CopyBoxAction.moveDown:
        final active = _active;
        final index = active.indexOf(box),
            next =
                active.indexOf(box) + (action == CopyBoxAction.moveUp ? -1 : 1);
        if (index < 0 || next < 0 || next >= active.length) return;
        final from = _boxes.indexOf(box), to = _boxes.indexOf(active[next]);
        setState(() {
          _boxes.removeAt(from);
          _boxes.insert(to, box);
        });
        await _save();
      case CopyBoxAction.color:
        final color = await showDialog<int>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Box color'),
            children: [
              for (var i = 0; i < boxColors.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, i),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 12, backgroundColor: boxColors[i]),
                      const SizedBox(width: 14),
                      Text(boxColorNames[i]),
                      if (box.color == i)
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Icon(Icons.check, size: 18),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (!mounted || color == null) return;
        setState(() => box.color = color);
        await _save();
      case CopyBoxAction.delete:
        setState(() => box.trashed = true);
        await _save();
        _message(
          'Box moved to trash.',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted) {
                setState(() => box.trashed = false);
                unawaited(_save());
              }
            },
          ),
        );
    }
  }

  Future<void> _connect() async {
    if (!await _save() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: copyboxTheme(Brightness.light),
          child: CopyBoxAuthScreen(auth: widget.auth),
        ),
      ),
    );
  }

  Future<void> _ai(CopyBoxEntry box, String action) async {
    if (_busyId != null || box.text.trim().isEmpty || box.trashed) return;
    if (widget.auth.session == null) {
      await _connect();
      return;
    }
    final original = box.text;
    final revision = widget.auth.revision;
    final consent = await ensureKorlixThirdPartyAiConsent(
      context: context,
      featureName: 'COPY Box text refinement',
      additionalDisclosure:
          'This sends the full text of this box and your refinement instruction '
          'to KORLIX and OpenAI. KORLIX saves the request and generated response '
          'in your account’s AI history, even if you keep the original. '
          'Deleting a local box does not remove that online history.',
      providers: const {KorlixThirdPartyAiProvider.openAi},
      dataCategories: const {
        KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
      },
    );
    if (!mounted ||
        !consent ||
        widget.auth.revision != revision ||
        box.text != original ||
        box.trashed) {
      return;
    }
    setState(() => _busyId = box.id);
    try {
      final result = await widget.auth.rewrite(action, original);
      if (!mounted || widget.auth.revision != revision) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => CopyBoxAiReview(
          original: original,
          result: result,
          action: action,
          onReport: (reason, details) => widget.auth.reportOutput(
            output: result,
            reason: reason,
            details: details,
          ),
        ),
      );
      if (!mounted || widget.auth.revision != revision || choice == null) {
        return;
      }
      if (choice == 'new') {
        await _newBox(
          title: '${box.title.isEmpty ? 'Refined text' : box.title} · $action',
          text: result,
          folder: box.folder,
        );
      } else if (_boxes.contains(box) && !box.trashed && box.text == original) {
        setState(() => box.replace(result));
        await _save();
      } else {
        _message(
          'Your original changed. Run Refine again to keep the latest edits.',
        );
      }
    } catch (error) {
      _message(
        error is CopyBoxAuthException ? error.message : 'AI could not complete this edit. Your original is safe. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openUrl(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Show copyable URL below. */
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Open this address'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete your KORLIX account?'),
        content: const Text(
          'This submits a deletion request for your shared account across KORLIX apps. Your local COPY Box data remains on this device until you clear it. Export anything you need first. Cancel subscriptions with the store where you purchased them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    try {
      await widget.auth.requestAccountDeletion();
      _message('Your account deletion request was received.');
    } catch (error) {
      _message(
        error is CopyBoxAuthException
            ? error.message
            : 'The deletion request could not be confirmed. Please try again.',
      );
    }
  }

  Future<void> _trash() async {
    final trashed = _boxes.where((b) => b.trashed).toList();
    if (trashed.isEmpty) {
      _message('Your trash is empty.');
      return;
    }
    final box = await showDialog<CopyBoxEntry>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore from trash'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView(
            children: [
              for (final b in trashed)
                ListTile(
                  title: Text(b.title.isEmpty ? 'Untitled box' : b.title),
                  subtitle: Text(
                    b.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.restore),
                  onTap: () => Navigator.pop(d, b),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (mounted && box != null) {
      setState(() => box.trashed = false);
      await _save();
      _message('Box restored.');
    }
  }

  Future<void> _emptyTrash() async {
    final count = _boxes.where((b) => b.trashed).length;
    if (count == 0) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Permanently delete $count boxes?'),
        content: const Text(
          'This removes the boxes in trash and their saved versions from this workspace. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (mounted && yes == true) {
      setState(() => _boxes.removeWhere((b) => b.trashed));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 1000 &&
        MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                MediaQuery.paddingOf(context).vertical -
                80 >=
            480 &&
        MediaQuery.textScalerOf(context).scale(16) < 24;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: const CopyBoxBrand(compact: true),
        actions: [
          Tooltip(
            message:
                widget.auth.session?.email ?? 'Connect your KORLIX account',
            child: IconButton(
              onPressed: () {
                if (widget.auth.session == null) {
                  unawaited(_connect());
                } else {
                  setState(() => _section = 3);
                }
              },
              icon: Icon(
                widget.auth.session == null
                    ? Icons.account_circle_outlined
                    : Icons.account_circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide) _rail(),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: Scrollbar(
                  key: const Key('copybox-outer-scrollbar'),
                  controller: _scroll,
                  thumbVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      wide ? 40 : 18,
                      16,
                      wide ? 40 : 24,
                      120,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_loadFailed)
                              CopyBoxEmpty(
                                icon: Icons.warning_amber_rounded,
                                title: 'Your saved data is protected',
                                message: _status,
                                action: FilledButton(
                                  onPressed: () => setState(_load),
                                  child: const Text('Retry opening'),
                                ),
                              )
                            else
                              ...switch (_section) {
                                0 => _workspace(),
                                1 => _templates(),
                                2 => _backup(),
                                _ => _settings(),
                              },
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _section == 0 && !_loadFailed
          ? FloatingActionButton.extended(
              key: const Key('add-box'),
              onPressed: _newBox,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Box',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: (i) {
                setState(() => _section = i);
                if (_scroll.hasClients) _scroll.jumpTo(0);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Workspace',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_mosaic_outlined),
                  label: 'Templates',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_copy_outlined),
                  label: 'Backup',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }

  Widget _rail() => Container(
    width: 228,
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .12),
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 0, 18),
          child: Text(
            'YOUR SPACE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final item in [
          (Icons.dashboard_outlined, 'Workspace'),
          (Icons.auto_awesome_mosaic_outlined, 'Templates'),
          (Icons.folder_copy_outlined, 'Backup & restore'),
          (Icons.tune, 'Settings'),
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              selected: _section == item.$1,
              selectedTileColor: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .07),
              leading: Icon(item.$2.$1, size: 20),
              title: Text(
                item.$2.$2,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                setState(() => _section = item.$1);
                if (_scroll.hasClients) _scroll.jumpTo(0);
              },
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.auth.session == null
                ? 'LOCAL WORKSPACE\nYour words, on this device.'
                : 'KORLIX CONNECTED\nYour personal workspace.',
            style: const TextStyle(fontSize: 11, height: 1.8),
          ),
        ),
      ],
    ),
  );
  Widget _heading(String eyebrow, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .5),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1.13,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .65),
          ),
        ),
      ],
    ),
  );
  List<Widget> _workspace() {
    final visible = _visible, active = _active;
    final folders =
        active
            .map((b) => b.folder.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [
      _heading(
        'THINK IT. SAVE IT. USE IT.',
        'Good words.\nAlways within reach.',
        'Your ideas, replies, and everyday brilliance. All in one place.',
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${active.length.toString().padLeft(2, '0')} BOXES  /  ${active.where((b) => b.favorite).length} FAVORITES',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _saveFailed
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 14,
                  color: _saveFailed
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_status, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('search-boxes'),
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Find a word, a box, an idea…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(() {
                    _query = '';
                    _search.clear();
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: !_favorites && _folder == null,
                label: const Text('All boxes'),
                onSelected: (_) => setState(() {
                  _favorites = false;
                  _folder = null;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: _favorites,
                avatar: const Icon(Icons.star_border, size: 16),
                label: const Text('Favorites'),
                onSelected: (v) => setState(() => _favorites = v),
              ),
            ),
            for (final folder in folders)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: _folder == folder,
                  label: Text(folder),
                  onSelected: (v) =>
                      setState(() => _folder = v ? folder : null),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('save-all'),
            onPressed: () => _save(announce: true),
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save All'),
          ),
          OutlinedButton.icon(
            key: const Key('copy-all'),
            onPressed: () => _copy(
              active
                  .where((b) => b.text.trim().isNotEmpty)
                  .map((b) => b.text)
                  .join('\n\n'),
            ),
            icon: const Icon(Icons.copy_all_outlined, size: 17),
            label: const Text('Copy All Boxes'),
          ),
          if (_query.isNotEmpty || _favorites || _folder != null)
            TextButton(
              onPressed: () => _copy(
                visible
                    .where((b) => b.text.trim().isNotEmpty)
                    .map((b) => b.text)
                    .join('\n\n'),
              ),
              child: Text('Copy ${visible.length} shown'),
            ),
        ],
      ),
      const SizedBox(height: 22),
      if (visible.isEmpty)
        CopyBoxEmpty(
          icon: Icons.search_off_rounded,
          title: active.isEmpty
              ? 'Make room for a new idea.'
              : 'No boxes found.',
          message: active.isEmpty
              ? 'Add a box or choose a starter from Templates.'
              : 'Try another word or clear your filters.',
        ),
      for (final box in visible)
        Padding(
          key: _anchors.putIfAbsent(box.id, () => GlobalKey()),
          padding: const EdgeInsets.only(bottom: 16),
          child: CopyBoxCard(
            key: ValueKey(box.id),
            box: box,
            number: active.indexOf(box) + 1,
            busy: _busyId == box.id,
            onChanged: _changed,
            onCopy: () => _copy(box.text),
            onAction: (a) => _boxAction(box, a),
            onAi: (a) => _ai(box, a),
          ),
        ),
      if (visible.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'A space for every thought. Add another whenever you need it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .5),
            ),
          ),
        ),
    ];
  }

  List<Widget> _templates() => [
    _heading(
      'A HEAD START FOR YOUR NEXT IDEA',
      'Skip the blank page.',
      'Thoughtful starters with fields you can fill once and reuse.',
    ),
    for (final item in copyBoxTemplates.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: (Theme.of(context).brightness == Brightness.dark
                ? darkBoxColors
                : boxColors)[item.$1 % 6],
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.$2.folder.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.$2.title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.$2.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.6),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _newBox(
                  title: item.$2.title,
                  text: item.$2.text,
                  folder: item.$2.folder,
                ),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Use template'),
              ),
            ],
          ),
        ),
      ),
  ];
  Widget _panel({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> actions,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 27),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(description, style: const TextStyle(height: 1.6, fontSize: 14)),
        const SizedBox(height: 20),
        Wrap(spacing: 10, runSpacing: 10, children: actions),
      ],
    ),
  );
  List<Widget> _backup() => [
    _heading(
      'KEEP YOUR WORDS CLOSE',
      'Take your boxes\nwith you.',
      'A backup lets you move your workspace to another device.',
    ),
    if (_working)
      const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: LinearProgressIndicator(
          semanticsLabel: 'Working with your backup',
        ),
      ),
    _panel(
      icon: Icons.save_alt_rounded,
      title: 'Save a full backup',
      description: 'Includes your text, folders, colors, favorites, trash, and version history. Backup files are readable text, so store and share them carefully.',
      actions: [
        FilledButton.icon(
          onPressed: _working ? null : _export,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Save backup'),
        ),
        OutlinedButton(
          onPressed: _working ? null : _shareBackup,
          child: const Text('Share backup'),
        ),
        TextButton(
          onPressed: _working ? null : () => _export(plainText: true),
          child: const Text('Export as text'),
        ),
      ],
    ),
    _panel(
      icon: Icons.file_open_outlined,
      title: 'Bring your words in',
      description: 'Import a COPY Box JSON backup or a text file. You will see a preview before new boxes are added. Existing boxes are preserved.',
      actions: [
        FilledButton(
          onPressed: _working ? null : _import,
          child: const Text('Import backup'),
        ),
        OutlinedButton(
          onPressed: _working ? null : () => _import(plainText: true),
          child: const Text('Import text'),
        ),
      ],
    ),
    _panel(
      icon: Icons.restore_from_trash_outlined,
      title: 'A second chance',
      description:
          '${_boxes.where((b) => b.trashed).length} boxes in trash. Restore a box, or clear the trash when you are ready.',
      actions: [
        OutlinedButton(onPressed: _trash, child: const Text('Open trash')),
        TextButton(onPressed: _emptyTrash, child: const Text('Empty trash')),
      ],
    ),
  ];
  List<Widget> _settings() => [
    _heading(
      'MAKE THIS SPACE YOURS',
      'A few thoughtful\ndetails.',
      'Your appearance, account, and help. Simply organized.',
    ),
    _panel(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      description: 'Choose what feels best. COPY Box also follows your device’s text size and accessibility settings.',
      actions: [
        for (final mode in ThemeMode.values)
          ChoiceChip(
            label: Text(switch (mode) {
              ThemeMode.system => 'Device',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }),
            selected: widget.themeMode == mode,
            onSelected: (_) async {
              try {
                await widget.onThemeChanged(mode);
              } catch (_) {
                _message('Appearance could not be saved.');
              }
            },
          ),
      ],
    ),
    _panel(
      icon: Icons.account_circle_outlined,
      title: widget.auth.session?.email ?? 'Your KORLIX account',
      description: widget.auth.session == null
          ? 'Local editing works without an account. Connect KORLIX to refine text with AI using your existing account limits. Account workspaces are separate from your local workspace.'
          : 'Signed in with your existing KORLIX account. Boxes are stored on this device and separated by account. Use a backup to transfer content between devices or workspaces.',
      actions: [
        if (widget.auth.session == null)
          FilledButton(onPressed: _connect, child: const Text('Connect KORLIX'))
        else
          OutlinedButton(
            onPressed: () async {
              if (await _save()) {
                try {
                  await widget.auth.signOut();
                } catch (_) {
                  _message('Sign-out could not finish. Please try again.');
                }
              }
            },
            child: const Text('Sign out'),
          ),
      ],
    ),
    _panel(
      icon: Icons.privacy_tip_outlined,
      title: 'Your words, your choice',
      description:
          'Editing saves boxes on this device. With your permission, AI refinement '
          'sends the selected box’s full text and instruction to KORLIX and OpenAI. '
          'KORLIX saves the request and response in your account’s AI history, '
          'even if you keep the original. Deleting a local box does not remove '
          'this online history. Sharing and export send the content you choose. '
          'Local boxes and backups are not encrypted by COPY Box.',
      actions: [
        TextButton(
          onPressed: () => _openUrl(
            Uri.https('www.korlixdeveloper.com', '/privacy-policy.html'),
          ),
          child: const Text('Privacy Policy'),
        ),
        TextButton(
          onPressed: () =>
              _openUrl(Uri.https('www.korlixdeveloper.com', '/terms.html')),
          child: const Text('Terms of Use'),
        ),
      ],
    ),
    _panel(
      icon: Icons.help_outline_rounded,
      title: 'A little help',
      description: 'Have a question or found a bug? Send the KORLIX team a message from your email app.',
      actions: [
        OutlinedButton(
          onPressed: () => _openUrl(
            Uri(
              scheme: 'mailto',
              path: 'support@korlixdeveloper.com',
              queryParameters: {'subject': 'KORLIX COPY Box support'},
            ),
          ),
          child: const Text('Contact support'),
        ),
      ],
    ),
    if (widget.auth.session != null)
      TextButton(
        onPressed: _deleteAccount,
        child: const Text('Request KORLIX account deletion'),
      ),
    TextButton(
      onPressed: () => _openUrl(
        Uri.https('www.korlixdeveloper.com', '/delete-account.html'),
      ),
      child: const Text('Account deletion information'),
    ),
    const SizedBox(height: 16),
    FutureBuilder<PackageInfo>(
      future: _package,
      builder: (_, snapshot) => Text(
        snapshot.hasData
            ? 'KORLIX COPY Box  ·  Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
            : 'KORLIX COPY Box',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  ];
}

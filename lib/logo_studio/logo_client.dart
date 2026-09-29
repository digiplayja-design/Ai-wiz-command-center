import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../imagine_studio/imagine_client.dart';
import '../chat/chat_memory_client.dart' show chatAccountStorageKey;
import '../live_convo/agent_studio_client.dart' show agentStudioKey;
import 'logo_model.dart';

class LogoClient extends ChangeNotifier {
  LogoClient({
    required this.images,
    required Map<String, String> headers,
    ImagineRecipeStore? store,
  }) : _store = store ?? ImaginePreferences(),
       _key = 'korlix_logo_projects_v1_${chatAccountStorageKey(headers)}' {
    images.addListener(_session);
  }
  final ImagineClient images;
  final ImagineRecipeStore _store;
  final String _key;
  bool _closed = false, loaded = false, saving = false;
  int round = 0;
  LogoDesign design = const LogoDesign();
  List<LogoDesign> concepts = [];
  List<Map<String, dynamic>> projects = [];
  final _undo = <LogoDesign>[], _redo = <LogoDesign>[];
  bool get available => !_closed && images.available;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _guard() {
    if (!available) {
      throw const ImagineException(
        'Your session changed. Reopen Logo Studio after signing in.',
      );
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _session() {
    if (!images.available) {
      design = const LogoDesign();
      concepts.clear();
      projects.clear();
      _undo.clear();
      _redo.clear();
    }
    _notify();
  }

  void generate(LogoDesign brief) {
    _guard();
    if (brief.error != null) throw ImagineException(brief.error!);
    concepts = logoDirections(brief, round: round++);
    choose(concepts.first);
  }

  void choose(LogoDesign value) {
    _guard();
    design = value;
    _undo.clear();
    _redo.clear();
    _notify();
  }

  void update(LogoDesign value) {
    _guard();
    if (jsonEncode(value.json) == jsonEncode(design.json)) return;
    _undo.add(design);
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    design = value;
    _notify();
  }

  void undo() {
    _guard();
    if (!canUndo) return;
    _redo.add(design);
    design = _undo.removeLast();
    _notify();
  }

  void redo() {
    _guard();
    if (!canRedo) return;
    _undo.add(design);
    design = _redo.removeLast();
    _notify();
  }

  Future<void>? _loading;
  Future<void> load() async {
    _guard();
    if (loaded) return;
    if (_loading != null) return _loading!;
    _loading = _load();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    final rows = await _store.read(_key);
    _guard();
    final next = <Map<String, dynamic>>[];
    for (final raw in rows.take(20)) {
      try {
        if (raw.length > 12000) continue;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final d = LogoDesign.fromJson(Map<String, dynamic>.from(m['design']));
        if (d.error != null || m['id'] is! String) continue;
        next.add({
          'id': m['id'],
          'design': d.json,
          'savedAt': '${m['savedAt'] ?? ''}',
        });
      } catch (_) {
        /* Ignore a damaged local entry without executing its content. */
      }
    }
    projects = next;
    loaded = true;
    _notify();
  }

  Future<void> save() async {
    _guard();
    if (saving) return;
    if (design.error != null) throw ImagineException(design.error!);
    final snapshot = design;
    saving = true;
    _notify();
    try {
      await load();
      _guard();
      if (projects.length >= 20) {
        throw const ImagineException(
          'Remove a saved project before adding another. You can also export a project file.',
        );
      }
      final next = [
        {
          'id': agentStudioKey(),
          'design': snapshot.json,
          'savedAt': DateTime.now().toIso8601String(),
        },
        ...projects,
      ];
      await _store.write(_key, next.map(jsonEncode).toList());
      _guard();
      projects = next;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> delete(String id) async {
    _guard();
    if (saving) return;
    saving = true;
    _notify();
    try {
      await load();
      _guard();
      final next = projects.where((p) => p['id'] != id).toList();
      await _store.write(_key, next.map(jsonEncode).toList());
      _guard();
      projects = next;
    } finally {
      saving = false;
      _notify();
    }
  }

  void import(String source) {
    _guard();
    if (source.length > 32000) {
      throw const FormatException(
        'Choose a Logo Studio project smaller than 32 KB.',
      );
    }
    final d = LogoDesign.fromJson(jsonDecode(source) as Map<String, dynamic>);
    if (d.error != null) throw FormatException(d.error!);
    choose(d);
  }

  @override
  void dispose() {
    _closed = true;
    images.removeListener(_session);
    images.dispose();
    projects.clear();
    concepts.clear();
    _undo.clear();
    _redo.clear();
    super.dispose();
  }
}

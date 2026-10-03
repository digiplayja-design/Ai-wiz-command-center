import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../imagine_studio/imagine_catalog.dart' show ImagineBrief;
import '../imagine_studio/imagine_client.dart';
import '../chat/chat_memory_client.dart' show chatAccountStorageKey;
import '../live_convo/agent_studio_client.dart'
    show agentAccountScope, agentStudioKey;
import 'logo_model.dart';

class LogoClient extends ChangeNotifier {
  LogoClient({
    required this.images,
    required Map<String, String> headers,
    ImagineRecipeStore? store,
  }) : _store = store ?? ImaginePreferences(),
       _scope = agentAccountScope(headers),
       _key = 'korlix_logo_projects_v1_${chatAccountStorageKey(headers)}' {
    images.addListener(_session);
  }
  final ImagineClient images;
  final ImagineRecipeStore _store;
  final String _key, _scope;
  bool _closed = false, _denied = false, loaded = false, saving = false;
  int round = 0, _documentEpoch = 0;
  String? _currentProjectId, _savedDesign;
  LogoDesign design = const LogoDesign();
  List<LogoDesign> concepts = [];
  List<Map<String, dynamic>> projects = [];
  final List<LogoDesign> shortlist = [];
  final _undo = <LogoDesign>[], _redo = <LogoDesign>[];
  bool get available =>
      !_closed &&
      !_denied &&
      images.available &&
      _scope.isNotEmpty &&
      _scope == agentAccountScope(images.headersBuilder());
  String? get currentProjectId => _currentProjectId;
  bool get hasUnsavedChanges => _savedDesign == null
      ? design.error == null
      : _savedDesign != jsonEncode(design.json);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _guard() {
    if (!available) {
      _invalidate();
      _notify();
      throw const ImagineException(
        'Your session changed. Reopen Logo Studio after signing in.',
      );
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _session() {
    if (!available) _invalidate();
    _notify();
  }

  void _invalidate() {
    _denied = true;
    design = const LogoDesign();
    concepts.clear();
    shortlist.clear();
    projects.clear();
    _undo.clear();
    _redo.clear();
    _currentProjectId = _savedDesign = null;
    _documentEpoch++;
    loaded = false;
  }

  void generate(LogoDesign brief, {bool preserveSelection = false}) {
    _guard();
    if (brief.error != null) throw ImagineException(brief.error!);
    concepts = logoDirections(brief, round: round++);
    if (!preserveSelection) {
      choose(concepts.first);
    } else {
      _notify();
    }
  }

  void choose(LogoDesign value) {
    _guard();
    design = value;
    _currentProjectId = _savedDesign = null;
    _documentEpoch++;
    _undo.clear();
    _redo.clear();
    _notify();
  }

  void openProject(String id) {
    _guard();
    final project = projects.where((p) => p['id'] == id).firstOrNull;
    if (project == null) {
      throw const ImagineException(
        'That saved project is no longer available.',
      );
    }
    design = LogoDesign.fromJson(Map<String, dynamic>.from(project['design']));
    _currentProjectId = id;
    _savedDesign = jsonEncode(design.json);
    _documentEpoch++;
    _undo.clear();
    _redo.clear();
    _notify();
  }

  void newBrand() {
    _guard();
    if (images.busy) {
      throw const ImagineException(
        'Wait for your AI concept to finish before starting a new brand.',
      );
    }
    concepts.clear();
    shortlist.clear();
    round = 0;
    choose(const LogoDesign());
    for (final result in images.results.toList()) {
      images.removeResult(result.id);
    }
    images.draft = const ImagineBrief();
    images.error = null;
    images.elapsed = 0;
    _notify();
  }

  bool isShortlisted(LogoDesign value) =>
      shortlist.any((d) => jsonEncode(d.json) == jsonEncode(value.json));

  void toggleShortlist(LogoDesign value) {
    _guard();
    if (value.error != null) throw ImagineException(value.error!);
    final key = jsonEncode(value.json);
    final index = shortlist.indexWhere((d) => jsonEncode(d.json) == key);
    if (index >= 0) {
      shortlist.removeAt(index);
    } else {
      if (shortlist.length >= 3) {
        throw const ImagineException(
          'Compare up to three favorites. Remove one before adding another.',
        );
      }
      shortlist.add(value);
    }
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
        if (d.error != null ||
            m['id'] is! String ||
            (m['id'] as String).isEmpty ||
            next.any((p) => p['id'] == m['id'])) {
          continue;
        }
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

  Future<void> save({bool asCopy = false}) async {
    _guard();
    if (saving) return;
    if (design.error != null) throw ImagineException(design.error!);
    final snapshot = design;
    final epoch = _documentEpoch;
    final originalId = asCopy ? null : _currentProjectId;
    saving = true;
    _notify();
    try {
      await load();
      _guard();
      final updating =
          originalId != null && projects.any((p) => p['id'] == originalId);
      if (!updating && projects.length >= 20) {
        throw const ImagineException(
          'Remove a saved project before adding another. You can also export a project file.',
        );
      }
      final id = updating ? originalId : agentStudioKey();
      final next = [
        {
          'id': id,
          'design': snapshot.json,
          'savedAt': DateTime.now().toIso8601String(),
        },
        ...projects.where((p) => p['id'] != id),
      ];
      await _store.write(_key, next.map(jsonEncode).toList());
      _guard();
      projects = next;
      if (_documentEpoch == epoch) {
        _currentProjectId = id;
        _savedDesign = jsonEncode(snapshot.json);
      }
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
      if (_currentProjectId == id) {
        _currentProjectId = _savedDesign = null;
      }
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
    shortlist.clear();
    _undo.clear();
    _redo.clear();
    super.dispose();
  }
}

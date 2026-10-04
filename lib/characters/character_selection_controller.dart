import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'character_catalog.dart';

/// The server owns availability; account and request revisions discard stale replies.
class CharacterSelectionController extends ChangeNotifier {
  CharacterSelectionController({
    required this.baseUrl,
    required this.headersBuilder,
    required this.selected,
    required this.sessionChanges,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    sessionChanges.addListener(_sessionChanged);
    selected.addListener(_selectedChanged);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final ValueNotifier<String> selected;
  final ValueListenable<int> sessionChanges;
  final http.Client _client;
  Set<String> availableIds = {};
  bool loading = true, saving = false, _disposed = false;
  String? error;
  int _revision = 0;
  bool _current(int revision) => !_disposed && revision == _revision;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _selectedChanged() => _changed();
  void _sessionChanged() {
    ++_revision;
    saving = false;
    availableIds = {};
    selected.value = 'jj';
    unawaited(load());
  }

  Future<void> load() async {
    if (_disposed || saving) return;
    final revision = ++_revision;
    loading = true;
    error = null;
    _changed();
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/me'), headers: headersBuilder())
          .timeout(const Duration(seconds: 20));
      if (!_current(revision)) return;
      if (response.statusCode != 200) throw StateError('load');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      availableIds = (data['characters'] as List? ?? [])
          .whereType<Map>()
          .where(
            (item) =>
                item['is_active'] == true && item['is_coming_soon'] != true,
          )
          .map((item) => normalizeKorlixCharacterId(item['id']?.toString()))
          .toSet();
      final id = normalizeKorlixCharacterId(
        (data['profile'] as Map?)?['selected_character']?.toString(),
      );
      selected.value = id;
    } catch (_) {
      if (_current(revision)) {
        error = 'Could not load your characters. Try again.';
      }
    } finally {
      if (_current(revision)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> select(String id) async {
    id = normalizeKorlixCharacterId(id);
    if (_disposed ||
        saving ||
        loading ||
        !availableIds.contains(id) ||
        id == selected.value) {
      return;
    }
    final revision = ++_revision;
    saving = true;
    error = null;
    _changed();
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/characters/select'),
            headers: {...headersBuilder(), 'Content-Type': 'application/json'},
            body: jsonEncode({'character_id': id}),
          )
          .timeout(const Duration(seconds: 20));
      if (!_current(revision)) return;
      if (response.statusCode != 200) throw StateError('save');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] != true ||
          normalizeKorlixCharacterId(
                (data['profile'] as Map?)?['selected_character']?.toString(),
              ) !=
              id) {
        throw StateError('unconfirmed');
      }
      selected.value = id;
    } catch (_) {
      if (_current(revision)) {
        error =
            'Your character could not be saved. Tap a character to try again.';
      }
    } finally {
      if (_current(revision)) {
        saving = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    selected.removeListener(_selectedChanged);
    sessionChanges.removeListener(_sessionChanged);
    _client.close();
    super.dispose();
  }
}

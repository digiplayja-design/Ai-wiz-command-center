import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../live_convo/agent_studio_client.dart'
    show agentAccountScope, agentStudioKey;
import '../chat/chat_memory_client.dart' show chatAccountStorageKey;
import 'imagine_catalog.dart';

class ImagineException implements Exception {
  const ImagineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImagineResult {
  ImagineResult({
    required this.bytes,
    required this.brief,
    required this.id,
    DateTime? createdAt,
    required this.width,
    required this.height,
  }) : createdAt = createdAt ?? DateTime.now();
  final Uint8List bytes;
  final ImagineBrief brief;
  final String id;
  final DateTime createdAt;
  final int width, height;
}

abstract class ImagineRecipeStore {
  Future<List<String>> read(String key);
  Future<void> write(String key, List<String> value);
}

class ImaginePreferences implements ImagineRecipeStore {
  @override
  Future<List<String>> read(String key) async =>
      (await SharedPreferences.getInstance()).getStringList(key) ?? [];
  @override
  Future<void> write(String key, List<String> value) async {
    if (!await (await SharedPreferences.getInstance()).setStringList(
      key,
      value,
    )) {
      throw const ImagineException(
        'This brief could not be saved on this device.',
      );
    }
  }
}

class ImagineClient extends ChangeNotifier {
  ImagineClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
    ImagineRecipeStore? store,
  }) : _http = client ?? http.Client(),
       _store = store ?? ImaginePreferences() {
    _scope = agentAccountScope(headersBuilder());
    _key =
        'korlix_imagine_briefs_v1_${chatAccountStorageKey(headersBuilder())}';
    sessionChanges?.addListener(_check);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final ImagineRecipeStore _store;
  late final String _scope, _key;
  bool _closed = false,
      _denied = false,
      busy = false,
      savingBrief = false,
      briefsLoaded = false;
  int elapsed = 0;
  Timer? _clock;
  final List<ImagineResult> results = [];
  List<Map<String, dynamic>> recipes = [];
  ImagineBrief draft = const ImagineBrief();
  String? error;
  bool get available => !_closed && !_denied;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _check() {
    if (!available) return;
    if (_scope.isEmpty || _scope != agentAccountScope(headersBuilder())) {
      _denied = true;
      _clock?.cancel();
      results.clear();
      recipes = [];
      draft = const ImagineBrief();
      busy = false;
      error = 'Your session changed. Close this studio and sign in again.';
      _notify();
    }
  }

  void _guard() {
    _check();
    if (!available) {
      throw const ImagineException(
        'Your session changed. Close this studio and sign in again.',
      );
    }
  }

  Future<void>? _loadingBriefs;
  Future<void> loadBriefs() async {
    if (_loadingBriefs != null) return _loadingBriefs!;
    final task = _readBriefs();
    _loadingBriefs = task;
    try {
      await task;
    } finally {
      _loadingBriefs = null;
    }
  }

  Future<void> _readBriefs() async {
    if (briefsLoaded || !available) return;
    try {
      final values = await _store.read(_key);
      _guard();
      recipes = values
          .take(20)
          .map((v) {
            try {
              final m = jsonDecode(v);
              if (m is! Map<String, dynamic> ||
                  m['name'] is! String ||
                  m['brief'] is! Map) {
                return null;
              }
              return <String, dynamic>{
                'id': '${m['id']}',
                'name': (m['name'] as String).substring(
                  0,
                  (m['name'] as String).length.clamp(0, 60),
                ),
                'brief': ImagineBrief.fromJson(
                  Map<String, dynamic>.from(m['brief']),
                ).json,
              };
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      briefsLoaded = true;
    } catch (_) {
      if (available) {
        error =
            'Saved briefs could not be opened. You can still create a picture.';
      }
    } finally {
      _notify();
    }
  }

  Future<void> saveBrief(String name, ImagineBrief brief) async {
    _guard();
    await loadBriefs();
    _guard();
    if (!briefsLoaded) {
      throw const ImagineException(
        'Saved briefs could not be opened. Please reopen the studio before saving.',
      );
    }
    if (savingBrief) return;
    if (brief.error != null) throw ImagineException(brief.error!);
    if (name.trim().isEmpty || name.trim().length > 60) {
      throw const ImagineException(
        'Give this brief a name, up to 60 characters.',
      );
    }
    if (recipes.length >= 20) {
      throw const ImagineException(
        'You have 20 saved briefs. Remove one before saving another.',
      );
    }
    savingBrief = true;
    _notify();
    try {
      final next = [
        {'id': agentStudioKey(), 'name': name.trim(), 'brief': brief.json},
        ...recipes,
      ];
      await _store.write(_key, next.map(jsonEncode).toList());
      _guard();
      recipes = next;
    } finally {
      savingBrief = false;
      _notify();
    }
  }

  Future<void> deleteBrief(String id) async {
    _guard();
    if (savingBrief) return;
    savingBrief = true;
    _notify();
    try {
      final next = recipes.where((x) => x['id'] != id).toList();
      await _store.write(_key, next.map(jsonEncode).toList());
      _guard();
      recipes = next;
    } finally {
      savingBrief = false;
      _notify();
    }
  }

  Future<ImagineResult?> create(
    ImagineBrief brief, {
    String language = 'en',
  }) async {
    _guard();
    if (busy) return null;
    if (brief.error != null) throw ImagineException(brief.error!);
    busy = true;
    error = null;
    elapsed = 0;
    draft = brief;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed++;
      _notify();
    });
    _notify();
    try {
      final headers = Map<String, String>.from(headersBuilder())
        ..['Content-Type'] = 'application/json';
      final response = await _http
          .post(
            Uri.parse(
              '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/image/create',
            ),
            headers: headers,
            body: jsonEncode({
              'prompt': brief.compiledPrompt,
              'language': language,
              'imageSize': brief.size,
              'imageStyle': brief.style,
            }),
          )
          .timeout(const Duration(seconds: 265));
      _guard();
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const ImagineException(
          'The picture service could not confirm a result. Please try again shortly.',
        );
      }
      if (response.statusCode == 401) {
        _denied = true;
        results.clear();
        recipes = [];
        draft = const ImagineBrief();
        throw const ImagineException('Sign in again to create pictures.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ImagineException(
          '${data['details'] ?? data['error'] ?? 'This picture could not be created.'}',
        );
      }
      final source = data['imageDataUrl'];
      if (source is! String ||
          !source.startsWith('data:image/png;base64,') ||
          source.length > 36 * 1024 * 1024) {
        throw const ImagineException('A usable PNG picture was not returned.');
      }
      Uint8List bytes;
      try {
        bytes = base64Decode(source.substring(22));
      } catch (_) {
        throw const ImagineException('The returned picture could not be read.');
      }
      if (bytes.length < 24 ||
          !listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
        throw const ImagineException(
          'The returned picture is not a valid PNG.',
        );
      }
      final info = ByteData.sublistView(bytes),
          width = info.getUint32(16),
          height = info.getUint32(20);
      if (width < 1 || height < 1 || width * height > 32000000) {
        throw const ImagineException(
          'The returned picture has unsupported dimensions.',
        );
      }
      final result = ImagineResult(
        bytes: bytes,
        brief: brief,
        id: '${data['generationId'] ?? agentStudioKey()}',
        width: width,
        height: height,
      );
      results.insert(0, result);
      while (results.length > 6 ||
          (results.length > 1 &&
              results.fold<int>(0, (sum, x) => sum + x.bytes.length) >
                  40 * 1024 * 1024)) {
        results.removeLast();
      }
      return result;
    } on TimeoutException {
      error =
          'The connection timed out before a picture was returned. A new attempt may use another credit.';
      rethrow;
    } catch (e) {
      if (available || _denied) error = '$e';
      rethrow;
    } finally {
      _clock?.cancel();
      busy = false;
      _notify();
    }
  }

  void removeResult(String id) {
    _guard();
    results.removeWhere((r) => r.id == id);
    _notify();
  }

  @override
  void dispose() {
    _closed = true;
    _clock?.cancel();
    sessionChanges?.removeListener(_check);
    _http.close();
    results.clear();
    recipes = [];
    super.dispose();
  }
}

import 'brain_api.dart';

/// Coordinates confirmed changes and session-local undo. The backend owns data.
class BrainRepository {
  BrainRepository(this.api);
  final BrainApi api;
  Map<String, dynamic> agent = {};
  List<Map<String, dynamic>> memories = [];
  Map<String, dynamic>? _undo;
  bool _writing = false;
  String get training => agent['trainingInstructions']?.toString() ?? '';

  Map<String, dynamic> get snapshot => {
    'training': training,
    'memories': memories,
    'canUndo': _undo != null,
    'agentName': agent['name'] ?? 'Rici',
  };

  Future<Map<String, dynamic>> load() async {
    final results = await Future.wait([
      api.json('GET', BrainApi.agentPath),
      api.json('GET', '${BrainApi.agentPath}/memories'),
    ]);
    final nextAgent = Map<String, dynamic>.from(results[0]['agent'] as Map);
    if (nextAgent['persistenceConfigured'] == false) {
      throw const BrainApiException(
        'Account memory storage is not available yet.',
      );
    }
    agent = nextAgent;
    memories = (results[1]['memories'] as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    return snapshot;
  }

  Future<T> _write<T>(Future<T> Function() operation) async {
    if (_writing) {
      throw const BrainApiException(
        'Please wait for the current change to finish.',
      );
    }
    _writing = true;
    try {
      return await operation();
    } finally {
      _writing = false;
    }
  }

  Future<void> _checkTraining(String expected) async {
    final data = await api.json('GET', BrainApi.agentPath);
    final fresh = Map<String, dynamic>.from(data['agent'] as Map);
    if ((fresh['trainingInstructions'] ?? '') != expected) {
      agent = fresh;
      throw const BrainApiException(
        'Your behaviors changed in another app. Refresh and review them again.',
      );
    }
  }

  static String checkedText(Object? value, int max) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty || text.length > max) {
      throw BrainApiException('Enter between 1 and $max characters.');
    }
    return text;
  }

  Future<Map<String, dynamic>> saveMemory(
    String text,
    String source,
  ) => _write(() async {
    final content = checkedText(text, 4000);
    // Check persisted content, so retries after an interrupted acknowledgement
    // do not insert an identical memory again.
    await load();
    if (memories.any(
      (m) =>
          m['content'].toString().trim().toLowerCase() == content.toLowerCase(),
    )) {
      throw const BrainApiException('That memory is already saved.');
    }
    final data = await api.json('POST', '${BrainApi.agentPath}/memories', {
      'confirmed': true,
      'content': content,
      'kind': 'preference',
      'source': source == 'voice' ? 'voice_confirmed' : 'user_confirmed',
      'importance': 3,
      'tags': <String>[],
      'sensitive': false,
    });
    memories.add(Map<String, dynamic>.from(data['memory'] as Map));
    _undo = null;
    return snapshot;
  });

  Future<Map<String, dynamic>> saveTraining(String text, String expected) =>
      _write(() async {
        final content = checkedText(text, 12000);
        await _checkTraining(expected);
        final data = await api.json('POST', '${BrainApi.agentPath}/training', {
          'confirmed': true,
          'trainingInstructions': content,
          'mode': 'replace',
          'source': 'user_confirmed',
          'changeSummary': 'Approved in KORLIX Brain',
        });
        agent = Map<String, dynamic>.from(data['agent'] as Map);
        _undo = {'kind': 'training', 'before': expected, 'after': training};
        return snapshot;
      });

  Future<Map<String, dynamic>> deleteMemory(String id, String expected) =>
      _write(() async {
        await load();
        final matches = memories.where(
          (m) => m['id'] == id && m['content'] == expected,
        );
        if (matches.isEmpty) {
          throw const BrainApiException(
            'This memory changed. Refresh and select it again.',
          );
        }
        final before = Map<String, dynamic>.from(matches.first);
        await api.json(
          'DELETE',
          '${BrainApi.agentPath}/memories/${Uri.encodeComponent(id)}',
          {'confirmed': true},
        );
        memories.removeWhere((m) => m['id'] == id);
        _undo = {'kind': 'memory', 'memory': before};
        return snapshot;
      });

  Future<Map<String, dynamic>> deleteBehavior(int index, String expected) =>
      _write(() async {
        await _checkTraining(expected);
        final lines = expected
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (index < 0 || index >= lines.length) {
          throw const BrainApiException('Select the behavior again.');
        }
        lines.removeAt(index);
        final next = lines.join('\n');
        // The profile update supports an empty string; the training endpoint does not.
        final data = await api.json('PUT', BrainApi.agentPath, {
          'trainingInstructions': next,
        });
        agent = Map<String, dynamic>.from(data['agent'] as Map);
        _undo = {'kind': 'training', 'before': expected, 'after': training};
        return snapshot;
      });

  Future<Map<String, dynamic>> undo() => _write(() async {
    final value = _undo;
    if (value == null) {
      throw const BrainApiException(
        'There is no change to undo in this session.',
      );
    }
    if (value['kind'] == 'training') {
      await _checkTraining(value['after'] as String);
      final data = await api.json('PUT', BrainApi.agentPath, {
        'trainingInstructions': value['before'],
      });
      agent = Map<String, dynamic>.from(data['agent'] as Map);
    } else {
      await load();
      final memory = Map<String, dynamic>.from(value['memory'] as Map);
      if (!memories.any((m) => m['content'] == memory['content'])) {
        final data = await api.json('POST', '${BrainApi.agentPath}/memories', {
          for (final key in [
            'content',
            'kind',
            'label',
            'tags',
            'importance',
            'sensitive',
            'source',
          ])
            if (memory[key] != null) key: memory[key],
          'confirmed': true,
        });
        memories.add(Map<String, dynamic>.from(data['memory'] as Map));
      }
    }
    _undo = null;
    return snapshot;
  });
}

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const copyBoxMaxBytes = 5 * 1024 * 1024;
const copyBoxMaxEntries = 1000;
const copyBoxMaxTitleLength = 200;
const copyBoxMaxFolderLength = 200;
const copyBoxMaxTextLength = 100000;
const copyBoxMaxHistory = 20;

/// A message safe to show to the user, without including their saved text.
class CopyBoxDataException extends FormatException {
  const CopyBoxDataException(super.message);

  @override
  String toString() => message;
}

final _random = Random.secure();
final _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$');
final _isoDate = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$',
);

String _newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return 'box_${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _now() => DateTime.now().toUtc().toIso8601String();

class CopyBoxEntry {
  CopyBoxEntry({
    String? id,
    this.title = 'Untitled',
    this.text = '',
    this.folder = '',
    this.favorite = false,
    this.color = 0,
    String? updated,
    List<String>? history,
    this.trashed = false,
  }) : id = id ?? _newId(),
       updated = updated ?? _now(),
       history = (history ?? const <String>[])
           .take(copyBoxMaxHistory)
           .toList();

  final String id;
  String title;
  String text;
  String folder;
  bool favorite;
  int color;
  String updated;
  final List<String> history;
  bool trashed;

  /// Revisions are newest first. Restoring a revision uses this same method,
  /// preserving the text that was present before restoration.
  void replace(String value) {
    _string(value, 'Text', copyBoxMaxTextLength);
    if (value == text) {
      return;
    }
    if (text.isNotEmpty) {
      history.insert(0, text);
    }
    if (history.length > copyBoxMaxHistory) {
      history.removeRange(copyBoxMaxHistory, history.length);
    }
    text = value;
    updated = _now();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'folder': folder,
    'favorite': favorite,
    'color': color,
    'updated': updated,
    'history': List<String>.of(history),
    'trashed': trashed,
  };

  factory CopyBoxEntry.fromJson(Map<String, dynamic> value) {
    final id = _string(value['id'], 'Box ID', 128);
    if (!_safeId.hasMatch(id)) {
      throw const CopyBoxDataException('A box has an invalid ID.');
    }
    final color = value['color'] ?? 0;
    if (color is! int || color < 0 || color > 5) {
      throw const CopyBoxDataException('A box has an invalid color.');
    }
    final revisions = value['history'] ?? const <String>[];
    if (revisions is! List || revisions.length > copyBoxMaxHistory) {
      throw const CopyBoxDataException(
        'A box has invalid revision history (maximum 20 revisions).',
      );
    }
    final updated = value['updated'] ?? _now();
    if (updated is! String ||
        updated.length > 64 ||
        !_isoDate.hasMatch(updated) ||
        DateTime.tryParse(updated) == null) {
      throw const CopyBoxDataException('A box has an invalid update date.');
    }
    return CopyBoxEntry(
      id: id,
      title: _string(value['title'], 'Title', copyBoxMaxTitleLength),
      text: _string(value['text'], 'Text', copyBoxMaxTextLength),
      folder: _string(
        value['folder'] ?? '',
        'Folder',
        copyBoxMaxFolderLength,
      ),
      favorite: _boolean(value['favorite'] ?? false, 'Favorite'),
      color: color,
      updated: updated,
      history: [
        for (final revision in revisions)
          _string(revision, 'Revision text', copyBoxMaxTextLength),
      ],
      trashed: _boolean(value['trashed'] ?? false, 'Trash status'),
    );
  }
}

String _string(Object? value, String label, int limit) {
  if (value is! String) {
    throw CopyBoxDataException('$label must be text.');
  }
  if (value.length > limit) {
    throw CopyBoxDataException('$label exceeds the $limit character limit.');
  }
  return value;
}

bool _boolean(Object value, String label) {
  if (value is! bool) {
    throw CopyBoxDataException('$label must be true or false.');
  }
  return value;
}

void _checkSize(String raw) {
  if (raw.length > copyBoxMaxBytes ||
      utf8.encode(raw).length > copyBoxMaxBytes) {
    throw const CopyBoxDataException(
      'The data exceeds the 5 MB limit. Use a smaller workspace or import.',
    );
  }
}

/// Backups contain all supplied boxes, including revisions and trash. They are
/// plain JSON, not encrypted; callers should disclose this before sharing one.
String exportBackup(List<CopyBoxEntry> entries) {
  if (entries.length > copyBoxMaxEntries) {
    throw const CopyBoxDataException('A workspace can contain at most 1000 boxes.');
  }
  final ids = <String>{};
  final boxes = <Map<String, dynamic>>[];
  for (final entry in entries) {
    final snapshot = entry.toJson();
    // Mutable editor state is validated before any saved data is replaced.
    CopyBoxEntry.fromJson(snapshot);
    if (!ids.add(entry.id)) {
      throw const CopyBoxDataException('The workspace contains duplicate box IDs.');
    }
    boxes.add(snapshot);
  }
  final raw = jsonEncode({
    'format': 'korlix.copybox',
    'version': 1,
    'exportedAt': _now(),
    'boxes': boxes,
  });
  _checkSize(raw);
  return raw;
}

List<CopyBoxEntry> _decode(String raw, {required bool freshIds}) {
  _checkSize(raw);
  Object? decoded;
  try {
    decoded = jsonDecode(raw.startsWith('\uFEFF') ? raw.substring(1) : raw);
  } on FormatException {
    throw const CopyBoxDataException('The file is not valid JSON.');
  }
  Object? boxes;
  if (decoded is List) {
    // Explicit import of a legacy KORLIX hub export; never automatic migration.
    boxes = decoded;
  } else if (decoded is Map) {
    if (decoded['format'] != 'korlix.copybox') {
      throw const CopyBoxDataException('This is not a KORLIX COPY BOX backup.');
    }
    if (decoded['version'] is! int || decoded['version'] != 1) {
      throw const CopyBoxDataException(
        'This backup version is unsupported. Keep the file and update the app.',
      );
    }
    boxes = decoded['boxes'];
  }
  if (boxes is! List) {
    throw const CopyBoxDataException('The backup must contain a list of boxes.');
  }
  if (boxes.length > copyBoxMaxEntries) {
    throw const CopyBoxDataException('An import can contain at most 1000 boxes.');
  }
  final entries = <CopyBoxEntry>[];
  final ids = <String>{};
  for (var index = 0; index < boxes.length; index++) {
    try {
      final value = boxes[index];
      if (value is! Map<String, dynamic>) {
        throw const CopyBoxDataException('Each box must be a JSON object.');
      }
      // Validate source IDs even though an import never adopts their identity.
      final entry = CopyBoxEntry.fromJson(value);
      if (!freshIds && !ids.add(entry.id)) {
        throw const CopyBoxDataException('The saved data has duplicate box IDs.');
      }
      entries.add(
        freshIds
            ? CopyBoxEntry.fromJson({...entry.toJson(), 'id': _newId()})
            : entry,
      );
    } on CopyBoxDataException catch (error) {
      throw CopyBoxDataException('Box ${index + 1}: ${error.message}');
    }
  }
  return entries;
}

/// Parses completely before returning; a malformed box cannot partially import.
/// JSON imports always get fresh IDs, including repeated imports of one file.
/// Plain text becomes one box and retains all whitespace and line endings.
List<CopyBoxEntry> parseImport(String raw, {bool plainText = false}) {
  _checkSize(raw);
  if (plainText) {
    if (raw.isEmpty) {
      throw const CopyBoxDataException('The text file is empty.');
    }
    return [
      CopyBoxEntry(
        title: 'Imported text',
        folder: 'Imported',
        text: _string(raw, 'Text', copyBoxMaxTextLength),
      ),
    ];
  }
  return _decode(raw, freshIds: true);
}

/// Plain local preferences, separated by the verified account scope supplied by
/// the app. This is not encrypted storage or a cloud sync service. Device/OS
/// backups are controlled by the platform's backup configuration.
class CopyBoxStore {
  CopyBoxStore(this.preferences, this.account) {
    if (account.trim().isEmpty) {
      throw ArgumentError.value(account, 'account', 'Must not be empty.');
    }
  }

  final SharedPreferences preferences;
  final String account;
  String get key => 'korlix_copy_box_v1.${Uri.encodeComponent(account)}';

  Future<void> _pendingWrite = Future<void>.value();
  bool _checked = false;
  bool _blocked = false;
  String? _validatedRaw;

  /// Unmodified saved bytes for an explicit recovery export after a read error.
  String? get rawData {
    final value = preferences.get(key);
    return value is String ? value : null;
  }

  List<CopyBoxEntry> load() {
    try {
      final value = preferences.get(key);
      final String? raw;
      if (value == null) {
        raw = null;
      } else if (value is String) {
        raw = value;
      } else {
        throw const CopyBoxDataException('The stored value is not text.');
      }
      final entries = raw == null
          ? <CopyBoxEntry>[]
          : _decode(raw, freshIds: false);
      _validatedRaw = raw;
      _checked = true;
      _blocked = false;
      return entries;
    } on CopyBoxDataException catch (error) {
      _blocked = true;
      throw CopyBoxDataException(
        'Saved data could not be read. Your existing data has been kept. '
        '${error.message}',
      );
    }
  }

  void _checkWritable() {
    if (_blocked) {
      throw const CopyBoxDataException(
        'Saving is paused because saved data could not be read. '
        'Recover the existing data and reopen the workspace before saving.',
      );
    }
    // Also protects callers that save before their first load, and catches
    // malformed data that appeared while a previous write was pending.
    if (!_checked || preferences.get(key) != _validatedRaw) {
      load();
    }
  }

  /// Captures the complete snapshot immediately, then writes in call order.
  /// A failed platform write is reported and does not poison subsequent retries.
  Future<void> save(List<CopyBoxEntry> entries) async {
    _checkWritable();
    final snapshot = exportBackup(entries);
    final write = _pendingWrite.then((_) async {
      _checkWritable();
      try {
        final saved = await preferences.setString(key, snapshot);
        if (!saved) {
          throw StateError('The platform rejected the write.');
        }
        _validatedRaw = snapshot;
      } catch (_) {
        throw const CopyBoxDataException(
          'Could not save on this device. Keep your text open, export a backup, '
          'and retry.',
        );
      }
    });
    // Consume only the queue's error; the individual caller still receives it.
    _pendingWrite = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await write;
  }
}

/// Filters without sorting or mutating the workspace. Query words can match
/// title, current text, or folder. An empty folder selects uncategorized boxes.
List<CopyBoxEntry> filterEntries(
  Iterable<CopyBoxEntry> entries, {
  String query = '',
  String? folder,
  bool favoritesOnly = false,
  bool includeTrashed = false,
  bool trashedOnly = false,
}) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
  return entries.where((entry) {
    if (trashedOnly ? !entry.trashed : (!includeTrashed && entry.trashed)) {
      return false;
    }
    if (favoritesOnly && !entry.favorite) {
      return false;
    }
    if (folder != null && entry.folder != folder) {
      return false;
    }
    final searchable = '${entry.title}\n${entry.text}\n${entry.folder}'.toLowerCase();
    return words.every(searchable.contains);
  }).toList();
}

class CopyBoxTemplate {
  const CopyBoxTemplate({
    required this.title,
    required this.folder,
    required this.text,
  });

  final String title;
  final String folder;
  final String text;
}

const copyBoxTemplates = <CopyBoxTemplate>[
  CopyBoxTemplate(
    title: 'Client follow-up',
    folder: 'Business',
    text:
        'Hi {{client}},\n\nFollowing up on {{topic}}. '
        '{{update}}\n\nNext step: {{next step}}\n\nThanks,\n{{your name}}',
  ),
  CopyBoxTemplate(
    title: 'Project update',
    folder: 'Work',
    text:
        '{{project}} — {{date}}\n\nCompleted:\n{{completed}}\n\n'
        'In progress:\n{{in progress}}\n\nBlockers:\n{{blockers}}\n\n'
        'Next steps:\n{{next steps}}',
  ),
  CopyBoxTemplate(
    title: 'Customer support',
    folder: 'Business',
    text:
        'Hi {{customer}},\n\nThanks for contacting us about {{issue}}.\n\n'
        '{{response}}\n\nNext step: {{next step}}\n\n{{your name}}',
  ),
  CopyBoxTemplate(
    title: 'Meeting recap',
    folder: 'Work',
    text:
        '{{meeting}} — {{date}}\n\nAttendees: {{attendees}}\n\n'
        'Key points:\n{{key points}}\n\nDecisions:\n{{decisions}}\n\n'
        'Actions, owners and due dates:\n{{actions}}',
  ),
  CopyBoxTemplate(
    title: 'Social caption',
    folder: 'Social',
    text: '{{opening}}\n\n{{message}}\n\n{{call to action}}\n\n{{hashtags}}',
  ),
  CopyBoxTemplate(
    title: 'Proposal brief',
    folder: 'Business',
    text:
        'Proposal for {{client}}\n\nGoal:\n{{goal}}\n\nScope:\n{{scope}}\n\n'
        'Deliverables:\n{{deliverables}}\n\nTimeline: {{timeline}}\n'
        'Budget: {{budget}}\n\nNext step: {{next step}}',
  ),
];

final _templatePattern = RegExp(r'\{\{([^{}\r\n]+)\}\}');

List<String> templateFields(String text) {
  final fields = <String>{};
  for (final match in _templatePattern.allMatches(text)) {
    final name = match[1]!.trim();
    if (name.isNotEmpty) {
      fields.add(name);
    }
  }
  return fields.toList();
}

/// Replacements are literal, non-recursive, and leave unknown fields intact.
String renderTemplate(String text, Map<String, String> values) =>
    text.replaceAllMapped(_templatePattern, (match) {
      final name = match[1]!.trim();
      return name.isEmpty ? match[0]! : values[name] ?? match[0]!;
    });

import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

String boxId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

class SavedBox {
  SavedBox({
    String? id,
    this.title = 'Untitled',
    this.text = '',
    this.folder = '',
    this.favorite = false,
    List<String>? history,
    String? updated,
  }) : id = id ?? boxId(),
       history = history ?? [],
       updated = updated ?? DateTime.now().toIso8601String();
  final String id;
  String title, text, folder, updated;
  bool favorite;
  final List<String> history;
  void replace(String value) {
    if (value == text) return;
    if (text.isNotEmpty) history.insert(0, text);
    if (history.length > 10) history.removeRange(10, history.length);
    text = value;
    updated = DateTime.now().toIso8601String();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'folder': folder,
    'favorite': favorite,
    'history': history,
    'updated': updated,
  };
  factory SavedBox.fromJson(Map<String, dynamic> v) => SavedBox(
    id: v['id'] as String,
    title: v['title'] as String,
    text: v['text'] as String,
    folder: v['folder'] as String? ?? '',
    favorite: v['favorite'] == true,
    history: List<String>.from(v['history'] as List? ?? []),
    updated: v['updated'] as String?,
  );
}

List<String> templateFields(String text) => RegExp(
  r'\{\{\s*([\w -]+?)\s*\}\}',
).allMatches(text).map((m) => m[1]!.trim()).toSet().toList();
String renderTemplate(String text, Map<String, String> values) =>
    text.replaceAllMapped(
      RegExp(r'\{\{\s*([\w -]+?)\s*\}\}'),
      (m) => values[m[1]!.trim()] ?? m[0]!,
    );

/// Local device storage, separated by verified session's issuer and account ID.
/// Legacy device-wide boxes are never silently assigned to an account.
class BoxStore {
  BoxStore(this.preferences, this.account, this.voice);
  final SharedPreferences preferences;
  final String account;
  final bool voice;
  String get key =>
      'korlix_boxes_v2.${Uri.encodeComponent(account)}.${voice ? 'voice' : 'copy'}';
  String get legacyKey => voice
      ? 'korlix_enterprise_voice_scribe_boxes_v1'
      : 'korlix_enterprise_copybox_entries_v1';
  List<SavedBox> load() {
    final raw = preferences.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => SavedBox.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> save(List<SavedBox> boxes) async {
    if (!await preferences.setString(
      key,
      jsonEncode(boxes.map((b) => b.toJson()).toList()),
    )) {
      throw StateError(
        'Could not save on this device. Copy your text and retry.',
      );
    }
  }

  List<String> get legacy =>
      preferences
          .getStringList(legacyKey)
          ?.where((e) => e.trim().isNotEmpty)
          .toList() ??
      [];
  bool get imported => preferences.getBool('$key.imported') ?? false;
  void prepareLegacy(List<SavedBox> boxes) {
    if (imported) return;
    for (final entry in legacy.indexed) {
      final id = '$legacyKey:${entry.$1}';
      if (!boxes.any((b) => b.id == id)) {
        boxes.add(
          SavedBox(
            id: id,
            title: 'Imported box ${entry.$1 + 1}',
            text: entry.$2,
          ),
        );
      }
    }
  }

  Future<void> importLegacy(List<SavedBox> boxes) async {
    if (imported) return;
    prepareLegacy(boxes);
    await save(boxes);
    await preferences.setBool('$key.imported', true);
  }
}

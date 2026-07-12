import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

// KORLIX_LIVE_CONVO_TRANSCRIPT_EXPORT_V1_BEGIN

enum KorlixLiveConvoTranscriptRole { user, assistant }

@immutable
class KorlixLiveConvoTranscriptEntry {
  const KorlixLiveConvoTranscriptEntry({
    required this.id,
    required this.role,
    required this.text,
    required this.source,
    required this.timestamp,
  });

  final String id;
  final KorlixLiveConvoTranscriptRole role;
  final String text;
  final String source;
  final DateTime timestamp;

  KorlixLiveConvoTranscriptEntry copyWith({
    String? text,
    String? source,
    DateTime? timestamp,
  }) {
    return KorlixLiveConvoTranscriptEntry(
      id: id,
      role: role,
      text: text ?? this.text,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

String korlixLiveConvoSourceLabel(String rawSource) {
  switch (rawSource.trim().toLowerCase()) {
    case 'voice':
      return 'Voice';

    case 'keyboard':
      return 'Keyboard';

    case 'camera':
      return 'Camera';

    case 'greeting':
      return 'Greeting';

    case 'realtime':
      return 'Live';

    default:
      final source = rawSource.trim();

      if (source.isEmpty) {
        return '';
      }

      return source;
  }
}

String _korlixTwoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

String _korlixTranscriptDate(DateTime value) {
  final local = value.toLocal();

  return '${local.year}-'
      '${_korlixTwoDigits(local.month)}-'
      '${_korlixTwoDigits(local.day)} '
      '${_korlixTwoDigits(local.hour)}:'
      '${_korlixTwoDigits(local.minute)}';
}

String _korlixTranscriptClock(DateTime value) {
  final local = value.toLocal();

  return '${_korlixTwoDigits(local.hour)}:'
      '${_korlixTwoDigits(local.minute)}:'
      '${_korlixTwoDigits(local.second)}';
}

String _korlixTranscriptDuration(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;

  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;

  if (hours > 0) {
    return '${_korlixTwoDigits(hours)}:'
        '${_korlixTwoDigits(minutes)}:'
        '${_korlixTwoDigits(seconds)}';
  }

  return '${_korlixTwoDigits(minutes)}:'
      '${_korlixTwoDigits(seconds)}';
}

String formatKorlixLiveConvoTranscript({
  required String characterName,
  required DateTime startedAt,
  required int durationSeconds,
  required List<KorlixLiveConvoTranscriptEntry> entries,
}) {
  final cleanCharacter = characterName.trim().isEmpty
      ? 'Korlix'
      : characterName.trim();

  final usableEntries = entries
      .where((entry) => entry.text.trim().isNotEmpty)
      .toList(growable: false);

  final buffer = StringBuffer()
    ..writeln('KORLIX LIVE CONVO')
    ..writeln('Character: $cleanCharacter')
    ..writeln('Date: ${_korlixTranscriptDate(startedAt)}')
    ..writeln(
      'Duration: '
      '${_korlixTranscriptDuration(durationSeconds)}',
    )
    ..writeln('Turns: ${usableEntries.length}')
    ..writeln();

  for (final entry in usableEntries) {
    final isUser = entry.role == KorlixLiveConvoTranscriptRole.user;

    final roleLabel = isUser ? 'YOU' : cleanCharacter.toUpperCase();

    final sourceLabel = korlixLiveConvoSourceLabel(entry.source);

    final sourceSuffix = isUser && sourceLabel.isNotEmpty
        ? ' [$sourceLabel]'
        : '';

    buffer
      ..writeln(
        '$roleLabel$sourceSuffix — '
        '${_korlixTranscriptClock(entry.timestamp)}',
      )
      ..writeln(entry.text.trim())
      ..writeln();
  }

  if (usableEntries.isEmpty) {
    buffer.writeln('No conversation turns were recorded.');
  }

  return buffer.toString().trimRight();
}

Future<void> copyKorlixLiveConvoTranscript({
  required String characterName,
  required DateTime startedAt,
  required int durationSeconds,
  required List<KorlixLiveConvoTranscriptEntry> entries,
}) async {
  final transcript = formatKorlixLiveConvoTranscript(
    characterName: characterName,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    entries: entries,
  );

  await Clipboard.setData(ClipboardData(text: transcript));
}

Rect _korlixSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();

  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      renderObject.size.width > 0 &&
      renderObject.size.height > 0) {
    final topLeft = renderObject.localToGlobal(Offset.zero);

    final rect = topLeft & renderObject.size;

    if (rect.width > 0 &&
        rect.height > 0 &&
        rect.left.isFinite &&
        rect.top.isFinite) {
      return rect;
    }
  }

  return const Rect.fromLTWH(1, 1, 1, 1);
}

String _korlixTranscriptFilename({
  required String characterName,
  required DateTime startedAt,
}) {
  final local = startedAt.toLocal();

  final character = characterName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  final safeCharacter = character.isEmpty ? 'korlix' : character;

  return 'korlix-live-convo-'
      '$safeCharacter-'
      '${local.year}'
      '${_korlixTwoDigits(local.month)}'
      '${_korlixTwoDigits(local.day)}-'
      '${_korlixTwoDigits(local.hour)}'
      '${_korlixTwoDigits(local.minute)}'
      '${_korlixTwoDigits(local.second)}.txt';
}

Future<void> shareKorlixLiveConvoTranscript({
  required BuildContext context,
  required String characterName,
  required DateTime startedAt,
  required int durationSeconds,
  required List<KorlixLiveConvoTranscriptEntry> entries,
}) async {
  final transcript = formatKorlixLiveConvoTranscript(
    characterName: characterName,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    entries: entries,
  );

  final filename = _korlixTranscriptFilename(
    characterName: characterName,
    startedAt: startedAt,
  );

  final bytes = Uint8List.fromList(utf8.encode(transcript));

  await SharePlus.instance.share(
    ShareParams(
      text:
          'Korlix LIVE CONVO transcript '
          'with $characterName.',
      subject: 'Korlix LIVE CONVO Transcript',
      files: <XFile>[
        XFile.fromData(bytes, mimeType: 'text/plain', name: filename),
      ],
      fileNameOverrides: <String>[filename],
      sharePositionOrigin: _korlixSharePositionOrigin(context),
    ),
  );
}

// KORLIX_LIVE_CONVO_TRANSCRIPT_EXPORT_V1_END

import 'dart:typed_data';

import 'package:ai_wiz_command_center/live_docs/korlix_live_docs.dart';

class KorlixLiveConvoAttachment {
  KorlixLiveConvoAttachment({
    required this.id,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required Uint8List bytes,
    required DateTime addedAt,
  }) : bytes = Uint8List.fromList(bytes),
       addedAt = addedAt.toUtc();

  final String id;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final Uint8List bytes;
  final DateTime addedAt;

  String get dedupeKey {
    return '${displayName.trim().toLowerCase()}|$sizeBytes';
  }

  bool get hasLocalBytes => bytes.isNotEmpty;

  String get sizeLabel => korlixLiveConvoFormatAttachmentSize(sizeBytes);

  KorlixLiveDocSourceFile toLiveDocSourceFile() {
    return KorlixLiveDocSourceFile(
      id: id,
      displayName: displayName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      uploadedAt: addedAt,
    );
  }
}

class KorlixLiveConvoAttachmentPolicy {
  static const int maxFiles = 6;
  static const int maxFileBytes = 15 * 1024 * 1024;
  static const int maxTotalBytes = 30 * 1024 * 1024;

  static const List<String> allowedExtensions = <String>[
    'pdf',
    'doc',
    'docx',
    'txt',
    'rtf',
    'csv',
    'xls',
    'xlsx',
    'png',
    'jpg',
    'jpeg',
    'webp',
  ];

  static String? validateCandidate({
    required int existingCount,
    required int existingBytes,
    required int candidateBytes,
  }) {
    if (existingCount >= maxFiles) {
      return 'LIVE CONVO supports up to $maxFiles files per session.';
    }

    if (candidateBytes <= 0) {
      return 'The selected file is empty.';
    }

    if (candidateBytes > maxFileBytes) {
      return 'Each LIVE CONVO file must be 15 MB or smaller.';
    }

    if (existingBytes + candidateBytes > maxTotalBytes) {
      return 'LIVE CONVO files may total no more than 30 MB.';
    }

    return null;
  }
}

String korlixLiveConvoAttachmentIdPart(String value) {
  var result = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+'), '')
      .replaceAll(RegExp(r'-+$'), '');

  if (result.isEmpty) {
    result = 'file';
  }

  if (result.length > 56) {
    result = result.substring(0, 56);
  }

  return result;
}

String korlixLiveConvoMimeTypeForName(String rawName) {
  final name = rawName.trim().toLowerCase();

  final extension = name.contains('.') ? name.split('.').last : '';

  switch (extension) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'txt':
      return 'text/plain';
    case 'rtf':
      return 'application/rtf';
    case 'csv':
      return 'text/csv';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}

String korlixLiveConvoFormatAttachmentSize(int bytes) {
  if (bytes <= 0) {
    return 'Size unavailable';
  }

  if (bytes < 1024) {
    return '$bytes B';
  }

  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

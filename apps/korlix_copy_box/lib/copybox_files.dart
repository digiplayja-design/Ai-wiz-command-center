import 'dart:typed_data';

import 'copybox_store.dart';

/// Enforces the import limit before buffering or decoding the complete file.
/// A provider's reported size can be missing or stale, so count streamed bytes
/// as well and cancel the stream as soon as it exceeds the workspace limit.
Future<Uint8List> readCopyBoxImportBytes(
  Stream<List<int>> Function() openStream, {
  int? declaredLength,
}) async {
  if (declaredLength != null &&
      (declaredLength < 0 || declaredLength > copyBoxMaxBytes)) {
    throw const CopyBoxDataException(
      'Choose a readable file no larger than 5 MB.',
    );
  }
  final bytes = BytesBuilder();
  await for (final chunk in openStream()) {
    if (chunk.length > copyBoxMaxBytes - bytes.length) {
      throw const CopyBoxDataException(
        'Choose a readable file no larger than 5 MB.',
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

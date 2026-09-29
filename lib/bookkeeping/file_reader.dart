import 'dart:typed_data';
import 'bookkeeping_client.dart';

/// Retains original bytes only after a complete, bounded read. Copying each
/// chunk is essential: camera/file streams may reuse a mutable buffer.
Future<Uint8List> readBookkeepingFile({
  required int advertisedSize,
  required int maxBytes,
  required String limitMessage,
  Uint8List? bytes,
  Stream<List<int>>? stream,
}) async {
  if (advertisedSize <= 0 || advertisedSize > maxBytes) {
    throw BookkeepingException(limitMessage);
  }
  final builder = BytesBuilder(copy: true);
  try {
    if (bytes != null) {
      if (bytes.length != advertisedSize || bytes.length > maxBytes) {
        throw const BookkeepingException(
          'The file was not read completely. Choose the original file again.',
        );
      }
      builder.add(bytes);
    } else {
      if (stream == null) throw StateError('Missing file stream');
      await for (final chunk in stream) {
        if (builder.length + chunk.length > maxBytes ||
            builder.length + chunk.length > advertisedSize) {
          throw BookkeepingException(limitMessage);
        }
        builder.add(chunk);
      }
    }
  } on BookkeepingException {
    rethrow;
  } catch (_) {
    throw const BookkeepingException(
      'This file could not be read. Choose the original file again.',
    );
  }
  if (builder.length != advertisedSize) {
    throw const BookkeepingException(
      'The file was not read completely. Choose the original file again.',
    );
  }
  return builder.takeBytes();
}

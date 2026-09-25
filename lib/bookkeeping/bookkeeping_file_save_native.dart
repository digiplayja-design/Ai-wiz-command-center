import 'dart:typed_data';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';

Future<void> saveBookkeepingFile(
  Uint8List bytes,
  String filename,
  String mime,
  Rect origin,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: filename)],
      fileNameOverrides: [filename],
      sharePositionOrigin: origin,
    ),
  );
}

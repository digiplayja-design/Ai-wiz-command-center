import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveKorlixGeneratedImage({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  await Share.shareXFiles(
    [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
    text: 'Save or share your Korlix AI improved image.',
    subject: 'Korlix AI improved image',
  );
}

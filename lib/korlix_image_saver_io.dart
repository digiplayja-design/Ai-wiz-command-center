import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'sharing/korlix_share.dart';

Future<void> saveKorlixGeneratedImage({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
      fileNameOverrides: [filename],
      text: 'Save or share your KORLIX AI image.',
      subject: 'KORLIX AI image',
      sharePositionOrigin: korlixShareOrigin(),
    ),
  );
}

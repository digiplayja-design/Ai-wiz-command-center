import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

Future<void> saveBabyBlendFile(
  Uint8List bytes,
  String name,
  String mime,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      text: 'KORLIX BabyBlend · AI imagining',
      subject: 'KORLIX BabyBlend',
    ),
  );
}

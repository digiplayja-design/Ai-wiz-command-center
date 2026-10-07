import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import '../sharing/korlix_share.dart';

Future<void> saveFieldProofFile(
  Uint8List bytes,
  String name,
  String mime,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      fileNameOverrides: [name],
      text: 'KORLIX FieldProof export',
      subject: 'KORLIX FieldProof',
      sharePositionOrigin: korlixShareOrigin(),
    ),
  );
}

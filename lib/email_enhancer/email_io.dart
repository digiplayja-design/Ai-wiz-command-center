import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../korlix_image_saver.dart';
import 'email_model.dart';

class EmailEnhancerIo {
  Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));
  Future<String?> importText() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > 48000 || file.bytes == null) {
      throw const EmailEnhancerException('Choose a text file up to 48 KB.');
    }
    final text = utf8.decode(file.bytes!);
    if (text.length > 12000 || text.contains('\u0000')) {
      throw const EmailEnhancerException(
        'Choose an email with up to 12,000 characters.',
      );
    }
    return text;
  }

  Future<void> export(String text, String extension, Rect origin) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name =
        'KORLIX-Email-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final mime = extension == 'eml' ? 'message/rfc822' : 'text/plain';
    if (kIsWeb) {
      await saveKorlixGeneratedImage(
        bytes: bytes,
        filename: name,
        mimeType: mime,
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name, mimeType: mime)],
          fileNameOverrides: [name],
          subject: 'KORLIX Email Enhancer',
          sharePositionOrigin: origin,
        ),
      );
    }
  }
}

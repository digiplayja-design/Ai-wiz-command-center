import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../korlix_image_saver.dart';

class LogoIo {
  Future<void> save(
    Uint8List bytes,
    String filename,
    String mime,
    Rect origin,
  ) async {
    if (kIsWeb) {
      await saveKorlixGeneratedImage(
        bytes: bytes,
        filename: filename,
        mimeType: mime,
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
          fileNameOverrides: [filename],
          subject: 'KORLIX Logo Studio',
          sharePositionOrigin: origin,
        ),
      );
    }
  }

  Future<String?> importProject() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > 32000 || file.bytes == null) {
      throw const FormatException(
        'Choose a KORLIX logo project smaller than 32 KB.',
      );
    }
    return utf8.decode(file.bytes!);
  }
}

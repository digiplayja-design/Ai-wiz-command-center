import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

Future<void> downloadKorlixVideo({
  required String url,
  required Map<String, String> headers,
  required String filename,
}) async {
  final response = await http.get(Uri.parse(url), headers: headers);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Video download failed. Status code: ${response.statusCode}');
  }

  await Share.shareXFiles(
    [
      XFile.fromData(
        Uint8List.fromList(response.bodyBytes),
        name: filename,
        mimeType: 'video/mp4',
      ),
    ],
    text: 'Save or share your Korlix AI video.',
    subject: 'Korlix AI video',
  );
}

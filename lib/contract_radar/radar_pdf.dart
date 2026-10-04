import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'radar_client.dart';

class RadarPdf {
  const RadarPdf(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<RadarPdf?> pickRadarPdf() async {
  const limit = 5 * 1024 * 1024;
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: false,
    withData: false,
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  if (file.size < 1 || file.size > limit) {
    throw const RadarException('Choose a PDF up to 5 MB.');
  }
  if (file.bytes != null) return RadarPdf(file.name, file.bytes!);
  if (file.readStream == null) {
    throw const RadarException('Choose this PDF again.');
  }
  final data = BytesBuilder(copy: false);
  await for (final chunk in file.readStream!) {
    if (data.length + chunk.length > limit) {
      throw const RadarException('Choose a PDF up to 5 MB.');
    }
    data.add(chunk);
  }
  return RadarPdf(file.name, data.takeBytes());
}

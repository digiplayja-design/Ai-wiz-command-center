import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'bookkeeping_client.dart';

class BookkeepingPickedReceipt {
  const BookkeepingPickedReceipt(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<BookkeepingPickedReceipt?> pickBookkeepingReceipt({
  bool camera = false,
}) async {
  const max = 8 * 1024 * 1024;
  if (camera) {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return null;
    if (await file.length() > max) {
      throw const BookkeepingException('Choose a receipt photo up to 8 MB.');
    }
    return BookkeepingPickedReceipt(file.name, await file.readAsBytes());
  }
  final selected = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    allowMultiple: false,
    withData: false,
    withReadStream: true,
  );
  if (selected == null || selected.files.isEmpty) return null;
  final file = selected.files.single;
  if (file.size > max || file.size == 0) {
    throw const BookkeepingException('Choose a receipt file up to 8 MB.');
  }
  if (file.bytes != null) {
    return BookkeepingPickedReceipt(file.name, file.bytes!);
  }
  final stream = file.readStream;
  if (stream == null) {
    throw const BookkeepingException(
      'This file could not be read. Choose it again.',
    );
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > max) {
      throw const BookkeepingException('Choose a receipt file up to 8 MB.');
    }
    builder.add(chunk);
  }
  return BookkeepingPickedReceipt(file.name, builder.takeBytes());
}

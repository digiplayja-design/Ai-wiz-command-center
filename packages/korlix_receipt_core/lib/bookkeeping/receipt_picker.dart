import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'file_reader.dart';

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
    return BookkeepingPickedReceipt(
      file.name,
      await readBookkeepingFile(
        advertisedSize: await file.length(),
        maxBytes: max,
        limitMessage: 'Choose a receipt photo up to 8 MB.',
        stream: file.openRead(),
      ),
    );
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
  return BookkeepingPickedReceipt(
    file.name,
    await readBookkeepingFile(
      advertisedSize: file.size,
      maxBytes: max,
      limitMessage: 'Choose a receipt file up to 8 MB.',
      bytes: file.bytes,
      stream: file.readStream,
    ),
  );
}

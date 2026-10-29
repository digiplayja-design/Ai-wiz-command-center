import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'file_reader.dart';

class BookkeepingPickedReceipt {
  const BookkeepingPickedReceipt(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

const receiptFileLimit = 8 * 1024 * 1024;
const receiptBatchLimit = 10;
const receiptBatchBytesLimit = 40 * 1024 * 1024;

void validateReceiptBatch(List<BookkeepingPickedReceipt> files) {
  if (files.isEmpty || files.length > receiptBatchLimit) {
    throw const FormatException('Choose between 1 and 10 receipt files.');
  }
  var total = 0;
  for (final file in files) {
    if (!RegExp(
      r'\.(jpe?g|png|webp|pdf)$',
      caseSensitive: false,
    ).hasMatch(file.name)) {
      throw const FormatException('Choose JPG, PNG, WebP or PDF receipts.');
    }
    if (file.bytes.isEmpty || file.bytes.length > receiptFileLimit) {
      throw const FormatException(
        'Each receipt must be between 1 byte and 8 MB.',
      );
    }
    total += file.bytes.length;
    if (total > receiptBatchBytesLimit) {
      throw const FormatException('Choose up to 40 MB of receipts at a time.');
    }
  }
}

/// Read bounded streams only after checking the whole selection's limits.
Future<List<BookkeepingPickedReceipt>?> pickBookkeepingReceiptBatch() async {
  final selected = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    allowMultiple: true,
    withData: false,
    withReadStream: true,
  );
  if (selected == null || selected.files.isEmpty) return null;
  if (selected.files.length > receiptBatchLimit) {
    throw const FormatException('Choose up to 10 receipt files at a time.');
  }
  var total = 0;
  for (final file in selected.files) {
    if (file.size <= 0 || file.size > receiptFileLimit) {
      throw const FormatException(
        'Each receipt must be between 1 byte and 8 MB.',
      );
    }
    total += file.size;
  }
  if (total > receiptBatchBytesLimit) {
    throw const FormatException('Choose up to 40 MB of receipts at a time.');
  }
  final files = <BookkeepingPickedReceipt>[];
  for (final file in selected.files) {
    files.add(
      BookkeepingPickedReceipt(
        file.name,
        await readBookkeepingFile(
          advertisedSize: file.size,
          maxBytes: receiptFileLimit,
          limitMessage: 'Choose a receipt file up to 8 MB.',
          bytes: file.bytes,
          stream: file.readStream,
        ),
      ),
    );
  }
  validateReceiptBatch(files);
  return files;
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

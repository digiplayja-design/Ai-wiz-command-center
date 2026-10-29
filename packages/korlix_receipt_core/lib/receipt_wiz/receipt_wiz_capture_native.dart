import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../bookkeeping/receipt_picker.dart';
import '../bookkeeping/file_reader.dart';
import 'receipt_wiz_client.dart';

Future<BookkeepingPickedReceipt?> captureReceiptWiz(
  BuildContext context,
  ReceiptWizClient client,
) async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    requestFullMetadata: false,
    imageQuality: 92,
    maxWidth: 2400,
    maxHeight: 2400,
  );
  if (photo == null || client.sessionChanged) return null;
  final bytes = await readBookkeepingFile(
    advertisedSize: await photo.length(),
    maxBytes: receiptFileLimit,
    limitMessage: 'Choose a receipt photo up to 8 MB.',
    stream: photo.openRead(),
  );
  if (client.sessionChanged) return null;
  return BookkeepingPickedReceipt(photo.name, bytes);
}

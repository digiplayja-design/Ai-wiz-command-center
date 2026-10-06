import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../bookkeeping/receipt_picker.dart';
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
  return BookkeepingPickedReceipt(photo.name, await photo.readAsBytes());
}

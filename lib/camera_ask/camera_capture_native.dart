import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_ask_client.dart';

Future<CameraPhoto?> captureCameraAskPhoto(BuildContext context) async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    requestFullMetadata: false,
    imageQuality: 90,
    maxWidth: 2048,
    maxHeight: 2048,
  );
  if (photo == null) return null;
  return CameraPhoto(bytes: await photo.readAsBytes(), name: photo.name);
}

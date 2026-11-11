import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brain_camera_ask.dart';

/// Android can recreate the app while its system camera is open. A recovered
/// image is offered only to the account that launched that picker, for review.
class BrainCameraPicker {
  BrainCameraPicker({required this.owner, required this.isCurrent, ImagePicker? picker})
      : _picker = picker ?? ImagePicker();
  final String owner;
  final bool Function() isCurrent;
  final ImagePicker _picker;
  static const _pendingOwnerKey = 'korlix_brain_camera_picker_owner_v1';

  Future<List<BrainCameraPhoto>> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    final prefs = await SharedPreferences.getInstance();
    final pendingOwner = prefs.getString(_pendingOwnerKey);
    try {
      final lost = await _picker.retrieveLostData();
      if (pendingOwner != owner || !isCurrent() || lost.isEmpty) return [];
      if (lost.exception != null) throw lost.exception!;
      return await _read(lost.files ?? []);
    } finally {
      await prefs.remove(_pendingOwnerKey);
    }
  }

  Future<List<BrainCameraPhoto>> pick(bool camera, int remaining) async {
    if (!isCurrent() || remaining < 1 || remaining > 3) return [];
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_pendingOwnerKey, owner)) {
      throw const BrainCameraAskException('The photo picker could not start. Please try again.');
    }
    try {
      if (!isCurrent()) return [];
      final List<XFile> files;
      if (camera || remaining == 1) {
        final file = await _picker.pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          preferredCameraDevice: CameraDevice.rear,
          requestFullMetadata: false,
          maxWidth: 2048, maxHeight: 2048, imageQuality: 90,
        );
        files = file == null ? [] : [file];
      } else {
        files = await _picker.pickMultiImage(
          limit: remaining, requestFullMetadata: false,
          maxWidth: 2048, maxHeight: 2048, imageQuality: 90,
        );
      }
      if (!isCurrent()) return [];
      if (files.length > remaining) {
        throw const BrainCameraAskException('Use up to three photos in one question.');
      }
      return await _read(files);
    } finally {
      await prefs.remove(_pendingOwnerKey);
    }
  }

  Future<List<BrainCameraPhoto>> _read(List<XFile> files) async {
    if (files.length > 3) {
      throw const BrainCameraAskException('Use up to three photos in one question.');
    }
    final result = <BrainCameraPhoto>[];
    var total = 0;
    for (final file in files) {
      if (!isCurrent()) return [];
      final length = await file.length();
      if (length > BrainCameraPhoto.maxPhotoBytes || total + length > 16 * 1024 * 1024) {
        throw const BrainCameraAskException('Use photos up to 8 MB each and 16 MB combined.');
      }
      final bytes = await file.readAsBytes();
      if (!isCurrent()) return [];
      total += bytes.length;
      if (total > 16 * 1024 * 1024) {
        throw const BrainCameraAskException('Use photos up to 16 MB combined.');
      }
      result.add(BrainCameraPhoto(bytes: bytes, name: file.name));
    }
    return result;
  }
}

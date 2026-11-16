import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// A local cosmetic preview. Neither image bytes nor landmarks are serializable
/// through the account/vanity models, and no network service is used here.
class SelfieException implements Exception {
  const SelfieException(this.code, this.message);
  final String code, message;
}

class FaceLandmarks {
  const FaceLandmarks({
    required this.bounds,
    required this.outerLips,
    required this.innerLips,
    required this.leftEye,
    required this.rightEye,
  });

  /// All coordinates are fractions of the upright image, with top-left origin.
  final ui.Rect bounds;
  final List<ui.Offset> outerLips, innerLips, leftEye, rightEye;

  factory FaceLandmarks.fromResponse(
    Map<Object?, Object?> result,
    ui.Size size,
  ) {
    final faces = result['faces'];
    final count = result['faceCount'] ?? (faces is List ? faces.length : null);
    if (count == 0) {
      throw const SelfieException(
        'no_face',
        'No clear face was found. Choose a well-lit selfie with your eyes and lips visible.',
      );
    }
    if (count is num && count > 1) {
      throw const SelfieException(
        'multiple_faces',
        'Choose a selfie with just one person so the look follows your face.',
      );
    }
    if (count != 1 ||
        faces is! List ||
        faces.length != 1 ||
        result['imageWidth'] != size.width ||
        result['imageHeight'] != size.height ||
        faces.single is! Map) {
      throw _alignmentFailure;
    }
    final face = faces.single as Map;
    for (final angle in [face['yaw'], face['pitch']]) {
      if (angle != null &&
          (angle is! num || !angle.isFinite || angle.abs() > 28)) {
        throw const SelfieException(
          'face_angle',
          'Choose a selfie looking straight ahead, with both eyes and your lips visible.',
        );
      }
    }
    final rawBounds = face['bounds'];
    if (rawBounds is! Map) throw _alignmentFailure;
    final bounds = ui.Rect.fromLTWH(
      _fraction(rawBounds['left']),
      _fraction(rawBounds['top']),
      _fraction(rawBounds['width']),
      _fraction(rawBounds['height']),
    );
    // A face can have complete usable landmarks in a wider portrait. Its
    // fraction of the whole photo is not a pixel-resolution requirement.
    // Keep strict geometry checks without rejecting it for its framing.
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        bounds.right > 1.002 ||
        bounds.bottom > 1.002) {
      throw _alignmentFailure;
    }
    final outer = _points(face['outerLips'], 6);
    final inner = _points(face['innerLips'], 4);
    final left = _points(face['leftEye'], 4);
    final right = _points(face['rightEye'], 4);
    final allowed = bounds.inflate(.05);
    if ([
      ...outer,
      ...inner,
      ...left,
      ...right,
    ].any((p) => !allowed.contains(p))) {
      throw _alignmentFailure;
    }
    return FaceLandmarks(
      bounds: bounds,
      outerLips: List.unmodifiable(outer),
      innerLips: List.unmodifiable(inner),
      leftEye: List.unmodifiable(left),
      rightEye: List.unmodifiable(right),
    );
  }

  static const _alignmentFailure = SelfieException(
    'landmarks_unavailable',
    'The eyes and lips could not be aligned clearly. Try a front-facing selfie without anything covering your face.',
  );

  static double _fraction(Object? value) {
    if (value is! num || !value.isFinite || value < -.002 || value > 1.002) {
      throw _alignmentFailure;
    }
    return value.toDouble().clamp(0, 1);
  }

  static List<ui.Offset> _points(Object? value, int minimum) {
    if (value is! List || value.length < minimum || value.length > 256) {
      throw _alignmentFailure;
    }
    return value.map((point) {
      if (point is! List || point.length != 2) throw _alignmentFailure;
      return ui.Offset(_fraction(point[0]), _fraction(point[1]));
    }).toList();
  }
}

class SelfiePhoto {
  SelfiePhoto({required this.image, this.face, this.alignmentIssue})
    : assert(face == null || alignmentIssue == null);
  final ui.Image image;
  final FaceLandmarks? face;
  final SelfieException? alignmentIssue;
  bool get hasMakeupAlignment => face != null;
  ui.Size get size => ui.Size(image.width.toDouble(), image.height.toDouble());
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

abstract interface class SelfiePhotoService {
  Future<void> discardInterruptedSelection();
  Future<SelfiePhoto?> choose({
    void Function(String message)? onProgress,
    void Function(SelfiePhoto photo)? onPreview,
  });
}

typedef SelfieDetector = Future<Map<Object?, Object?>> Function(Uint8List png);

/// Removes only picker copies inside the platform's app-owned picker cache.
/// Android's picker cache differs from Dart's usual `code_cache` directory.
class PickerFileCleaner {
  PickerFileCleaner({Future<String> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? _nativeTemporaryDirectory;

  final Future<String> Function() _temporaryDirectory;
  static const _channel = MethodChannel('com.korlixdeveloper.esha/selfie');

  static Future<String> _nativeTemporaryDirectory() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<String>('temporaryDirectory') ?? '';
    }
    // image_picker_ios writes into NSTemporaryDirectory, not Library/Caches.
    return Directory.systemTemp.path;
  }

  Future<void> clean(XFile selected) async {
    if (selected.path.isEmpty) return;
    try {
      final path = await _temporaryDirectory().timeout(
        const Duration(seconds: 2),
      );
      if (path.isEmpty) return;
      final temporary = await Directory(path).resolveSymbolicLinks();
      final file = File(selected.path);
      final resolved = await file.resolveSymbolicLinks();
      // Resolve both paths before checking containment, so ../ segments and
      // symlinks cannot turn cleanup into deletion of an original library file.
      if (resolved.startsWith('$temporary${Platform.pathSeparator}')) {
        await file.delete();
      }
    } catch (_) {
      // Native cache lookup or cleanup failure must not discard a prepared
      // image or block sign-in. The OS may also have removed the copy already.
    }
  }
}

class DeviceSelfiePhotoService implements SelfiePhotoService {
  DeviceSelfiePhotoService({
    ImagePicker? picker,
    SelfieDetector? detector,
    PickerFileCleaner? fileCleaner,
  }) : _picker = picker ?? ImagePicker(),
       _detector = detector ?? _detect,
       _fileCleaner = fileCleaner ?? PickerFileCleaner();

  static const maxFileBytes = 25 * 1024 * 1024;
  static const maxEncodedPreviewBytes = 12 * 1024 * 1024;
  static const maxImagePixels = 50 * 1000 * 1000;
  static const maxPreviewEdge = 1600;
  static const _channel = MethodChannel('com.korlixdeveloper.esha/selfie');
  final ImagePicker _picker;
  final SelfieDetector _detector;
  final PickerFileCleaner _fileCleaner;

  static Future<Map<Object?, Object?>> _detect(Uint8List png) async {
    final result = await _channel
        .invokeMapMethod<Object?, Object?>('detectFaces', {'bytes': png})
        .timeout(const Duration(seconds: 20));
    if (result == null) throw FaceLandmarks._alignmentFailure;
    return result;
  }

  @override
  Future<void> discardInterruptedSelection() async {
    if (!Platform.isAndroid) return;
    // A result from a previous process cannot be tied safely to this account.
    // Never silently restore or process it after an Android activity restart.
    try {
      final lost = await _picker.retrieveLostData();
      for (final file in lost.files ?? <XFile>[]) {
        await _fileCleaner.clean(file);
      }
    } on PlatformException {
      // Picking again remains available if the old result cannot be recovered.
    }
  }

  @override
  Future<SelfiePhoto?> choose({
    void Function(String message)? onProgress,
    void Function(SelfiePhoto photo)? onPreview,
  }) async {
    XFile? selected;
    ui.Image? image;
    try {
      onProgress?.call('Choose a selfie from your photos…');
      // Do not request broad library access, EXIF/GPS metadata, camera access,
      // or picker-side resizing (which could leave an extra cached original).
      selected = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (selected == null) return null;
      onProgress?.call('Opening your selected photo…');
      if (await selected.length() > maxFileBytes) {
        throw const SelfieException(
          'image_too_large',
          'Choose a photo smaller than 25 MB. A regular selfie or a smaller copy works well.',
        );
      }
      final source = await selected.readAsBytes();
      // Keep the picker copy only long enough to read it. Detection and the
      // preview use memory; finally below also covers interrupted reads.
      await _fileCleaner.clean(selected);
      if (source.length > maxFileBytes) {
        throw const SelfieException(
          'image_too_large',
          'Choose a photo smaller than 25 MB.',
        );
      }
      image = await normalizeSelfie(source);
      // Display a decoded photo immediately. The controller owns this clone,
      // so cancelling/removing it cannot dispose pixels still used here.
      if (onPreview != null) {
        onPreview(SelfiePhoto(image: image.clone()));
      }
      onProgress?.call('Aligning the look on your device…');
      FaceLandmarks? face;
      SelfieException? alignmentIssue;
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null || png.lengthInBytes > maxEncodedPreviewBytes) {
          throw const SelfieException(
            'alignment_image_too_large',
            'Your photo is displayed. Choose a smaller copy to add the makeup preview.',
          );
        }
        // The detector and painter receive the same normalized pixels.
        // Re-encoding excludes the source image's EXIF and location tags.
        final response = await _detector(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
        face = FaceLandmarks.fromResponse(
          response,
          ui.Size(image.width.toDouble(), image.height.toDouble()),
        );
      } catch (failure) {
        // Alignment controls makeup only. Keep the selected photo even when
        // a detector cannot find one suitable face or complete landmarks.
        alignmentIssue = _alignmentIssue(failure);
      }
      final result = SelfiePhoto(
        image: image,
        face: face,
        alignmentIssue: alignmentIssue,
      );
      image = null; // Ownership transfers to the session-scoped controller.
      return result;
    } finally {
      image?.dispose();
      if (selected != null) await _fileCleaner.clean(selected);
    }
  }

  static SelfieException _alignmentIssue(Object failure) => switch (failure) {
    SelfieException() => failure,
    TimeoutException() => const SelfieException(
      'alignment_timeout',
      'Your photo is ready, but makeup alignment took too long. Try another clear, front-facing selfie.',
    ),
    MissingPluginException() => const SelfieException(
      'alignment_unavailable',
      'Your photo is ready. Update Esha to use makeup try-on on iPhone or Android.',
    ),
    _ => FaceLandmarks._alignmentFailure,
  };

  static Future<ui.Image> normalizeSelfie(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const SelfieException(
        'invalid_image',
        'Choose a clear JPG, PNG, HEIC or WebP selfie.',
      );
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width, height = descriptor.height;
      if (width < 160 || height < 160) {
        throw const SelfieException(
          'small_image',
          'Choose a larger selfie, at least 160 pixels on each side.',
        );
      }
      if (width * height > maxImagePixels) {
        throw const SelfieException(
          'image_too_large',
          'Choose a smaller copy of this photo for the preview.',
        );
      }
      final scale = math.min(1.0, maxPreviewEdge / math.max(width, height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      if (codec.frameCount != 1) {
        throw const SelfieException(
          'animated_image',
          'Choose a still selfie instead of an animated image.',
        );
      }
      return (await codec.getNextFrame()).image;
    } on SelfieException {
      rethrow;
    } catch (_) {
      throw const SelfieException(
        'invalid_image',
        'This photo could not be opened. Try another JPG, PNG, HEIC or WebP selfie.',
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class SelfieStudioController extends ChangeNotifier {
  SelfieStudioController({SelfiePhotoService? service})
    : _service = service ?? DeviceSelfiePhotoService();
  final SelfiePhotoService _service;
  SelfiePhoto? _photo;
  SelfiePhoto? get photo => _photo;
  bool busy = false, showOriginal = false, _allowed = false, _disposed = false;
  String? error;
  String busyMessage = 'Choose a selfie from your photos…';
  double intensity = .55;
  String? _ownerId;
  int _accountEpoch = -1, _generation = 0;
  Future<void>? _initialization;
  bool get canChoose => !_disposed && _allowed && _ownerId != null && !busy;
  bool get canTryOn => _photo?.hasMakeupAlignment == true;

  Future<void> initialize() => _initialization ??= _initializePicker();

  Future<void> _initializePicker() async {
    try {
      await _service.discardInterruptedSelection().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // Old picker cleanup must never block account restoration or keep a
      // failed startup future from permitting a fresh, user-initiated pick.
      // A timed-out cleanup may still finish, but it never restores an image.
    }
  }

  void updateAccess({
    required String? ownerId,
    required int accountEpoch,
    required bool allowed,
  }) {
    if (_disposed) return;
    final identityChanged =
        ownerId != _ownerId || accountEpoch != _accountEpoch;
    final accessChanged = allowed != _allowed;
    _ownerId = ownerId;
    _accountEpoch = accountEpoch;
    _allowed = allowed && ownerId != null;
    if (identityChanged || (!allowed && accessChanged)) {
      _clear();
      notifyListeners();
    } else if (accessChanged) {
      notifyListeners();
    }
  }

  Future<void> choosePhoto() async {
    if (!canChoose) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    bool current() => !_disposed && generation == _generation && _allowed;
    try {
      await initialize();
      if (!current()) return;
      final selected = await _service.choose(
        onPreview: (preview) {
          if (!current()) {
            preview.dispose();
            return;
          }
          _photo?.dispose();
          _photo = preview;
          showOriginal = true;
          notifyListeners();
        },
        onProgress: (message) {
          if (current()) {
            busyMessage = message;
            notifyListeners();
          }
        },
      );
      if (!current()) {
        selected?.dispose();
        return;
      }
      if (selected != null) {
        _photo?.dispose();
        _photo = selected;
        showOriginal = !selected.hasMakeupAlignment;
      }
    } catch (failure) {
      if (current()) {
        error = switch (failure) {
          SelfieException() => failure.message,
          TimeoutException() =>
            'This photo took too long to align. Try a clearer selfie.',
          PlatformException(
            code: 'photo_access_denied' || 'photo_access_restricted',
          ) =>
            'Photo access is unavailable. Allow photo selection in Settings, then try again.',
          MissingPluginException() => 'Selfie try-on needs the latest Esha app update on iPhone or Android.',
          _ =>
            'This selfie could not be prepared. Please choose another photo.',
        };
      }
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void setShowOriginal(bool value) {
    if (_disposed ||
        _photo == null ||
        showOriginal == value ||
        (!value && !canTryOn)) {
      return;
    }
    showOriginal = value;
    notifyListeners();
  }

  void setIntensity(double value) {
    if (_disposed || !canTryOn || !value.isFinite) return;
    intensity = value.clamp(.15, .85);
    notifyListeners();
  }

  void _clear() {
    ++_generation;
    _photo?.dispose();
    _photo = null;
    busy = false;
    error = null;
    showOriginal = false;
    intensity = .55;
  }

  void removePhoto() {
    if (_disposed) return;
    _clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clear();
    super.dispose();
  }
}

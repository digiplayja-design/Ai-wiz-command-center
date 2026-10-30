// Copyright 2026 KORLIX
// Use of this source code is governed by the BSD-style license in LICENSE.

import AVFoundation
import UIKit

/// Applies the view's orientation without assuming a front camera's sensor mounting.
enum CameraConnectionOrientation {
  static func apply(
    _ orientation: UIDeviceOrientation,
    to connection: CaptureConnection,
    position: AVCaptureDevice.Position
  ) {
    // A raw angle of 90 is not universally portrait. In particular, the Center Stage
    // front sensor is mounted differently, and photo output can compensate for its
    // sensor independently of video output. Let AVFoundation translate the semantic
    // orientation for each front-camera connection. This compatibility API remains
    // available on our iOS deployment range; its deprecation is intentional here.
    if position == .front {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = videoOrientation(orientation)
      }
      return
    }

    // Preserve upstream behavior for the rear camera, which is already upright.
    if #available(iOS 17.0, *) {
      let angle = rearCameraRotationAngle(orientation)
      if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle
      }
    } else if connection.isVideoOrientationSupported {
      connection.videoOrientation = videoOrientation(orientation)
    }
  }

  private static func rearCameraRotationAngle(_ orientation: UIDeviceOrientation) -> CGFloat {
    switch orientation {
    case .landscapeLeft: return 0
    case .landscapeRight: return 180
    case .portraitUpsideDown: return 270
    default: return 90
    }
  }

  private static func videoOrientation(_ orientation: UIDeviceOrientation)
    -> AVCaptureVideoOrientation
  {
    switch orientation {
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
}

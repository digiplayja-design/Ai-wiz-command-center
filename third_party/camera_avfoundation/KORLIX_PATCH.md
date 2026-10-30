# Front-camera orientation compatibility patch

This directory vendors the runtime of Flutter's `camera_avfoundation` 0.11.1
from pub.dev. The upstream BSD license, source headers, Dart interface, Swift
package and CocoaPods support are retained. Only `DefaultCamera.swift` is
modified, and `CameraConnectionOrientation.swift` is added to production code.
The local package version is `0.11.1+korlix.1`.

Upstream applies the same raw portrait rotation (90 degrees) to every sensor
on iOS 17+. Apple documents that the iPhone 17 generation's Center Stage front
sensor is mounted in portrait and that processed photo output can independently
compensate for that mounting. A fixed angle therefore is not a universal
orientation for front-camera preview and capture.

For front cameras, the patch uses AVFoundation's semantic `videoOrientation`
setter on each video/photo connection, allowing iOS to perform the sensor/output
specific conversion. This deprecated but supported compatibility API is used
deliberately; rear-camera rotation, mirroring, recording guards and orientation
locks retain upstream behavior. No device-model checks or extra Flutter image
rotation are introduced. The root app, standalone app and shared package each
override the plugin so builds and tests resolve the same source.

The standalone RunnerTests compile the exact production orientation helper and
connection protocol. They cover different front-sensor/output rotation baselines,
portrait/landscape, repeated calls, mirroring, unsupported connections and rear
camera behavior. These tests run on an iOS simulator in GitHub Actions. Physical
device checks are still required for live preview and captured/save/share output.

Remove the override when upstream handles sensor-specific rotation. The newer
RotationCoordinator device-orientation API requires a newer SDK than the pinned
Xcode 26.6 release toolchain; do not replace this with another fixed front angle.

Sources:
- https://pub.dev/packages/camera_avfoundation/versions/0.11.1
- https://developer.apple.com/videos/play/wwdc2026/341/
- https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videoorientation
- https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle

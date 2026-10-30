import AVFoundation
import UIKit
import XCTest

// The target compiles the production helper and protocol directly from the
// vendored plugin, so the regression exercises the code shipped in the app.
final class RunnerTests: XCTestCase {
  func testFrontPortraitUsesSemanticOrientationForDifferentSensorsAndOutputs() {
    // Video and compensated photo output need not share a native rotation.
    for baseline in [CGFloat(0), CGFloat(90), CGFloat(270)] {
      let connection = OrientationConnection(initialAngle: baseline)
      CameraConnectionOrientation.apply(.portrait, to: connection, position: .front)
      XCTAssertEqual(connection.semanticWrites, [.portrait])
      XCTAssertTrue(connection.angleWrites.isEmpty, "A fixed angle bypasses sensor conversion")
    }
  }

  func testFrontLandscapeAndUpsideDownUseViewOrientation() {
    let cases: [(UIDeviceOrientation, AVCaptureVideoOrientation)] = [
      (.portrait, .portrait), (.landscapeLeft, .landscapeRight),
      (.landscapeRight, .landscapeLeft), (.portraitUpsideDown, .portraitUpsideDown),
      (.faceUp, .portrait), (.faceDown, .portrait), (.unknown, .portrait),
    ]
    for (device, expected) in cases {
      let connection = OrientationConnection(initialAngle: 0)
      CameraConnectionOrientation.apply(device, to: connection, position: .front)
      XCTAssertEqual(connection.semanticWrites, [expected])
      XCTAssertTrue(connection.angleWrites.isEmpty)
    }
  }

  func testRepeatedFrontOrientationDoesNotAccumulateRotationOrChangeMirroring() {
    let connection = OrientationConnection(initialAngle: 270)
    connection.isVideoMirrored = true
    for _ in 0..<3 {
      CameraConnectionOrientation.apply(.landscapeLeft, to: connection, position: .front)
      CameraConnectionOrientation.apply(.portrait, to: connection, position: .front)
    }
    XCTAssertEqual(connection.semanticWrites, [
      .landscapeRight, .portrait, .landscapeRight, .portrait, .landscapeRight, .portrait,
    ])
    XCTAssertTrue(connection.angleWrites.isEmpty)
    XCTAssertTrue(connection.isVideoMirrored)
  }

  func testUnsupportedFrontConnectionIsNotGivenAFixedAngle() {
    let connection = OrientationConnection(initialAngle: 0)
    connection.isVideoOrientationSupported = false
    CameraConnectionOrientation.apply(.portrait, to: connection, position: .front)
    XCTAssertTrue(connection.semanticWrites.isEmpty)
    XCTAssertTrue(connection.angleWrites.isEmpty)
  }

  func testRearCameraRetainsUpstreamRotation() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Raw rotation requires iOS 17") }
    let cases: [(UIDeviceOrientation, CGFloat)] = [
      (.portrait, 90), (.landscapeLeft, 0), (.landscapeRight, 180),
      (.portraitUpsideDown, 270), (.unknown, 90),
    ]
    for (device, expected) in cases {
      let connection = OrientationConnection(initialAngle: 90)
      CameraConnectionOrientation.apply(device, to: connection, position: .back)
      XCTAssertEqual(connection.angleWrites, [expected])
      XCTAssertTrue(connection.semanticWrites.isEmpty)
      XCTAssertFalse(connection.isVideoMirrored)
    }
  }

  func testUnsupportedRearRotationDoesNotWriteConnection() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Raw rotation requires iOS 17") }
    let connection = OrientationConnection(initialAngle: 90)
    connection.rotationSupported = false
    CameraConnectionOrientation.apply(.portrait, to: connection, position: .back)
    XCTAssertTrue(connection.angleWrites.isEmpty)
    XCTAssertTrue(connection.semanticWrites.isEmpty)
  }

  func testLensSwitchUsesEachConnectionsOwnOrientationPath() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Raw rotation requires iOS 17") }
    let front = OrientationConnection(initialAngle: 0)
    let back = OrientationConnection(initialAngle: 90)
    for _ in 0..<2 {
      CameraConnectionOrientation.apply(.portrait, to: front, position: .front)
      CameraConnectionOrientation.apply(.portrait, to: back, position: .back)
    }
    XCTAssertEqual(front.semanticWrites, [.portrait, .portrait])
    XCTAssertTrue(front.angleWrites.isEmpty)
    XCTAssertEqual(back.angleWrites, [90, 90])
    XCTAssertTrue(back.semanticWrites.isEmpty)
  }
}

private final class OrientationConnection: NSObject, CaptureConnection {
  var semanticWrites: [AVCaptureVideoOrientation] = []
  var angleWrites: [CGFloat] = []
  private var angle: CGFloat
  var isVideoMirrored = false
  var isVideoMirroringSupported = true
  var isVideoOrientationSupported = true
  var rotationSupported = true
  var inputPorts: [AVCaptureInput.Port] { [] }
  var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off

  init(initialAngle: CGFloat) {
    angle = initialAngle
    super.init()
  }

  var videoOrientation: AVCaptureVideoOrientation {
    get { semanticWrites.last ?? .portrait }
    set { semanticWrites.append(newValue) }
  }

  @available(iOS 17.0, *)
  var videoRotationAngle: CGFloat {
    get { angle }
    set { angle = newValue; angleWrites.append(newValue) }
  }

  @available(iOS 17.0, *)
  func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool {
    rotationSupported
  }
}

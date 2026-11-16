import CoreGraphics
import Flutter
import Foundation
import ImageIO
import Vision

/// Local geometry only. The caller supplies the same upright PNG it displays.
/// No image, landmarks, or file paths are persisted or sent to an API.
final class SelfieFaceDetector {
  private static let maximumEncodedBytes = 12 * 1024 * 1024
  private static let maximumImageSide = 1600
  private static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
  private let queue = DispatchQueue(label: "com.korlixdeveloper.esha.selfie", qos: .userInitiated)
  // Method calls and completion both run on the main thread.
  private var busy = false

  func detectFaces(arguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = arguments as? [String: Any],
      let typedData = arguments["bytes"] as? FlutterStandardTypedData,
      !typedData.data.isEmpty
    else {
      result(SelfieError.invalidArguments.flutterError)
      return
    }
    guard typedData.data.count <= Self.maximumEncodedBytes else {
      result(SelfieError.imageTooLarge.flutterError)
      return
    }
    guard !busy else {
      result(FlutterError(code: "selfie_busy", message: "A photo is already being processed.", details: nil))
      return
    }
    busy = true
    let bytes = typedData.data
    queue.async {
      let response: Any = autoreleasepool {
        do {
          return try Self.detect(bytes: bytes)
        } catch let error as SelfieError {
          return error.flutterError
        } catch {
          // Native exceptions may contain image details. Return only a fixed message.
          return SelfieError.detectionFailed.flutterError
        }
      }
      DispatchQueue.main.async {
        self.busy = false
        result(response)
      }
    }
  }

  private static func detect(bytes: Data) throws -> [String: Any] {
    guard bytes.prefix(8) == pngSignature,
      let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0, height > 0
    else {
      throw SelfieError.invalidImage
    }
    guard max(width, height) <= maximumImageSide else {
      throw SelfieError.imageTooLarge
    }
    // Flutter normalizes EXIF and mirroring before encoding. Do not rotate a second time.
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    guard orientation == 1,
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
      ), image.width == width, image.height == height
    else {
      throw SelfieError.invalidImage
    }

    let request = VNDetectFaceLandmarksRequest()
    // Vision locates all faces before analyzing each face's landmarks.
    try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
    let faces = request.results ?? []
    var response: [String: Any] = [
      "imageWidth": width,
      "imageHeight": height,
      "faceCount": faces.count,
      "faces": [] as [[String: Any]],
    ]
    guard faces.count == 1, let face = faces.first else {
      return response
    }
    guard let landmarks = face.landmarks else {
      throw SelfieError.invalidLandmarks
    }
    let box = face.boundingBox
    let left = try unit(Double(box.minX))
    let top = try unit(1 - Double(box.maxY))
    let right = try unit(Double(box.maxX))
    let bottom = try unit(1 - Double(box.minY))
    guard right > left, bottom > top else {
      throw SelfieError.invalidLandmarks
    }
    response["faces"] = [[
      "bounds": ["left": left, "top": top, "width": right - left, "height": bottom - top],
      "outerLips": try polygon(landmarks.outerLips, box: box),
      "innerLips": try polygon(landmarks.innerLips, box: box),
      "leftEye": try polygon(landmarks.leftEye, box: box),
      "rightEye": try polygon(landmarks.rightEye, box: box),
      "yaw": degrees(face.yaw),
      "pitch": degrees(face.pitch),
    ]]
    return response
  }

  private static func polygon(_ region: VNFaceLandmarkRegion2D?, box: CGRect) throws -> [[Double]] {
    guard let region = region, region.pointCount >= 3, region.pointCount <= 128 else {
      throw SelfieError.invalidLandmarks
    }
    // Vision points are normalized within the face box, with lower-left origin.
    // Convert exactly once into normalized full-image, upper-left coordinates.
    var points = try region.normalizedPoints.map { point in
      [
        try unit(Double(box.minX + point.x * box.width)),
        try unit(1 - Double(box.minY + point.y * box.height)),
      ]
    }
    if points.first == points.last {
      points.removeLast()
    }
    guard points.count >= 3 else {
      throw SelfieError.invalidLandmarks
    }
    // A closed polygon is implicit; the Flutter painter calls Path.close().
    // Positive signed area in this upper-left coordinate system is clockwise.
    let signedArea = points.indices.reduce(0.0) { sum, index in
      let next = points[(index + 1) % points.count]
      return sum + points[index][0] * next[1] - next[0] * points[index][1]
    }
    if signedArea < 0 {
      points.reverse()
    }
    return points
  }

  private static func unit(_ value: Double) throws -> Double {
    // Only tolerate numerical round-off, never a cropped or invalid landmark.
    guard value.isFinite, value >= -0.000001, value <= 1.000001 else {
      throw SelfieError.invalidLandmarks
    }
    return min(1, max(0, value))
  }

  private static func degrees(_ radians: NSNumber?) -> Any {
    guard let radians = radians?.doubleValue, radians.isFinite else {
      return NSNull()
    }
    return radians * 180 / .pi
  }

  private enum SelfieError: Error {
    case invalidArguments
    case invalidImage
    case imageTooLarge
    case invalidLandmarks
    case detectionFailed

    var flutterError: FlutterError {
      let code: String
      let message: String
      switch self {
      case .invalidArguments:
        code = "invalid_arguments"
        message = "Choose a photo to preview."
      case .invalidImage:
        code = "invalid_image"
        message = "This photo could not be read. Choose another photo."
      case .imageTooLarge:
        code = "image_too_large"
        message = "This photo is too large to process."
      case .invalidLandmarks:
        code = "invalid_landmarks"
        message = "Use a clear, front-facing photo with your eyes and lips visible."
      case .detectionFailed:
        code = "detection_failed"
        message = "The photo could not be analyzed. Please try another photo."
      }
      return FlutterError(code: code, message: message, details: nil)
    }
  }
}

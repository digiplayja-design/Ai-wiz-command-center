import AVFoundation
import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var soundEffects: KorlixSoundEffects?
  private var socialCalls: FlutterMethodChannel?
  private var socialCallId: String?
  private var storeReviews: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KorlixStoreReview") {
      storeReviews = FlutterMethodChannel(name: "korlix/store_review", binaryMessenger: registrar.messenger())
      storeReviews?.setMethodCallHandler { call, result in
        guard call.method == "requestReview" else { result(FlutterMethodNotImplemented); return }
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive &&
                  $0.windows.contains(where: { $0.isKeyWindow && !$0.isHidden }) }) else {
          result(false)
          return
        }
        if #available(iOS 16.0, *) {
          AppStore.requestReview(in: scene)
        } else if #available(iOS 14.0, *) {
          SKStoreReviewController.requestReview(in: scene)
        } else {
          SKStoreReviewController.requestReview()
        }
        // StoreKit deliberately provides no shown/submitted result. TestFlight
        // and store quotas can suppress this request without indicating it.
        result(true)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KorlixSoundEffects") {
      soundEffects = KorlixSoundEffects(messenger: registrar.messenger())
      socialCalls = FlutterMethodChannel(name: "korlix/social_call_background", binaryMessenger: registrar.messenger())
      socialCalls?.setMethodCallHandler { [weak self] call, result in
        guard let self = self,
              let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else { result(false); return }
        if call.method == "start" {
          let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
          // WebRTC owns activation and teardown. This lease only confirms that
          // its foreground, permissioned play-and-record session can continue.
          let session = AVAudioSession.sharedInstance()
          let ready = UIApplication.shared.applicationState == .active && modes.contains("audio") &&
            session.category == .playAndRecord && session.recordPermission == .granted &&
            (self.socialCallId == nil || self.socialCallId == id)
          if ready { self.socialCallId = id }
          result(ready)
        } else if call.method == "stop" {
          if self.socialCallId == id { self.socialCallId = nil }
          // Do not deactivate the shared audio session underneath another tool.
          result(true)
        } else { result(FlutterMethodNotImplemented) }
      }
    }
  }
}

/// Short local effects only. Never configures or deactivates the shared audio
/// session used by WebRTC, microphone recording, or other media features.
private final class KorlixSoundEffects {
  private let channel: FlutterMethodChannel
  private var owner: String?
  private var players: [String: AVAudioPlayer] = [:]
  private var deadlines: [String: DispatchWorkItem] = [:]
  private var revisions: [String: Int64] = [:]
  private var observers: [NSObjectProtocol] = []
  private var foreground = UIApplication.shared.applicationState == .active
  private let names: Set<String> = ["effect", "ring", "preview"]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "korlix/sound_effects", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      self.handle(call, result: result)
    }
    let center = NotificationCenter.default
    for event in [UIApplication.willResignActiveNotification,
                  UIApplication.didEnterBackgroundNotification,
                  UIScene.willDeactivateNotification] {
      observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
        self?.foreground = false
        self?.stopAll()
      })
    }
    for event in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
      observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
        // Returning to foreground never resumes an old ringtone.
        self?.foreground = true
      })
    }
  }

  private func stop(_ name: String) {
    deadlines.removeValue(forKey: name)?.cancel()
    players.removeValue(forKey: name)?.stop()
  }

  private func stopAll() {
    for name in names { stop(name) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let requestOwner = args["owner"] as? String else { result(false); return }
    if call.method == "activate" {
      stopAll()
      owner = requestOwner
      revisions.removeAll()
      result(foreground)
      return
    }
    guard owner == requestOwner else { result(false); return }
    switch call.method {
    case "stopAll", "dispose":
      stopAll()
      if let next = args["revisions"] as? [String: NSNumber] {
        for (name, revision) in next where names.contains(name) {
          revisions[name] = max(revisions[name] ?? 0, revision.int64Value)
        }
      }
      if call.method == "dispose" { owner = nil }
      result(true)
    case "stop", "play":
      guard let name = args["channel"] as? String, names.contains(name),
            let next = args["revision"] as? NSNumber,
            next.int64Value > (revisions[name] ?? 0) else { result(false); return }
      let revision = next.int64Value
      revisions[name] = revision
      stop(name)
      if call.method == "stop" { result(true); return }
      guard foreground,
            let bytes = args["wav"] as? FlutterStandardTypedData,
            bytes.data.count >= 44, bytes.data.count <= 200000,
            bytes.data.prefix(4) == Data("RIFF".utf8),
            let volume = args["volume"] as? NSNumber, volume.doubleValue.isFinite,
            let milliseconds = args["durationMs"] as? NSNumber,
            milliseconds.intValue > 0 else { result(false); return }
      let nowEpoch = Date().timeIntervalSince1970 * 1000
      let prepareRemaining = min(250,
        ((args["prepareDeadlineEpochMs"] as? NSNumber)?.doubleValue ?? 0) - nowEpoch)
      let ringRemaining = min(45000,
        ((args["expiresEpochMs"] as? NSNumber)?.doubleValue ?? 0) - nowEpoch)
      let looping = args["loop"] as? Bool == true
      guard prepareRemaining > 0, !looping || ringRemaining > 0 else { result(true); return }
      let requestedAt = ProcessInfo.processInfo.systemUptime
      do {
        let player = try AVAudioPlayer(data: bytes.data, fileTypeHint: "wav")
        player.volume = Float(min(1, max(0, volume.doubleValue)))
        player.numberOfLoops = looping ? -1 : 0
        guard player.prepareToPlay() else { result(false); return }
        let preparedAt = ProcessInfo.processInfo.systemUptime
        guard (preparedAt - requestedAt) * 1000 < prepareRemaining,
              !looping || (preparedAt - requestedAt) * 1000 < ringRemaining else {
          player.stop()
          result(true)
          return
        }
        guard player.play() else { result(false); return }
        players[name] = player
        let deadline = DispatchWorkItem { [weak self] in
          guard let self = self, self.owner == requestOwner,
                self.revisions[name] == revision else { return }
          self.stop(name)
        }
        deadlines[name] = deadline
        let playbackSeconds = looping
          ? max(0, requestedAt + ringRemaining / 1000 - ProcessInfo.processInfo.systemUptime)
          : Double(min(5000, milliseconds.intValue)) / 1000
        DispatchQueue.main.asyncAfter(
          deadline: .now() + playbackSeconds,
          execute: deadline)
        result(true)
      } catch { result(false) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    stopAll()
    channel.setMethodCallHandler(nil)
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
}

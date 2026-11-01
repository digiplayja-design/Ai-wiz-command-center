import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BrainWelcomePlayer") {
      BrainWelcomePlayer.register(with: registrar)
    }
  }
}

// The bundled welcome must not depend on WKWebView's autoplay/user-gesture state.
// Keep this in the existing Runner source file so every release target includes it.
final class BrainWelcomePlayer: NSObject, FlutterPlugin, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let assetKey: String
  private var player: AVAudioPlayer?
  private var token: Int?
  private var ownsSession = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.korlix.brain/welcome", binaryMessenger: registrar.messenger())
    let instance = BrainWelcomePlayer(
      channel: channel, assetKey: registrar.lookupKey(forAsset: "assets/web/welcome-v1.wav"))
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(channel: FlutterMethodChannel, assetKey: String) {
    self.channel = channel
    self.assetKey = assetKey
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(background),
      name: UIScene.willDeactivateNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let data = call.arguments as? [String: Any]
    switch call.method {
    case "play":
      guard let requestedToken = data?["token"] as? Int else {
        result(FlutterError(code: "invalid_token", message: "Invalid welcome request", details: nil))
        return
      }
      guard UIApplication.shared.applicationState == .active else {
        result(["started": false, "retry": true])
        return
      }
      finish(reason: "replaced")
      do {
        guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
          throw NSError(domain: "BrainWelcome", code: 1)
        }
        let audio = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        ownsSession = true
        player = audio
        token = requestedToken
        audio.delegate = self
        audio.volume = 0.9
        guard audio.play() else { throw NSError(domain: "BrainWelcome", code: 2) }
        result(["started": true])
      } catch {
        finish(reason: "error")
        result(FlutterError(code: "welcome_unavailable", message: "Welcome audio unavailable", details: nil))
      }
    case "stop":
      // A late stop for an older greeting cannot interrupt a newer Replay.
      if let requestedToken = data?["token"] as? Int, requestedToken == token {
        finish(reason: "stopped")
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func finish(reason: String) {
    let endedToken = token
    token = nil
    player?.stop()
    player?.delegate = nil
    player = nil
    if ownsSession {
      ownsSession = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    if let endedToken = endedToken {
      channel.invokeMethod("ended", arguments: ["token": endedToken, "reason": reason])
    }
  }

  @objc private func background() { finish(reason: "background") }

  @objc private func interrupted(_ notification: Notification) {
    if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
       type == AVAudioSession.InterruptionType.began.rawValue {
      finish(reason: "interrupted")
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player === self.player { finish(reason: flag ? "completed" : "error") }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if player === self.player { finish(reason: "error") }
  }

  deinit { NotificationCenter.default.removeObserver(self) }
}

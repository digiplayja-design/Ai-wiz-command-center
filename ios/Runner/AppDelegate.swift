import AVFoundation
import MediaPlayer
import Flutter
import StoreKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var soundEffects: KorlixSoundEffects?
  private var socialCalls: FlutterMethodChannel?
  private var socialCallId: String?
  private var riciStopTarget: Any?
  private var riciPauseTarget: Any?
  private let socialNative = KorlixSocialNative()

  private func clearRiciControls() {
    let commands = MPRemoteCommandCenter.shared()
    if let target = riciStopTarget { commands.stopCommand.removeTarget(target) }
    if let target = riciPauseTarget { commands.pauseCommand.removeTarget(target) }
    if riciStopTarget != nil || riciPauseTarget != nil {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    riciStopTarget = nil
    riciPauseTarget = nil
  }

  private func showRiciControls(_ id: String) {
    clearRiciControls()
    let commands = MPRemoteCommandCenter.shared()
    let stop: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
      guard let self = self, self.socialCallId == id else { return .commandFailed }
      self.clearRiciControls()
      self.socialCalls?.invokeMethod("stopped", arguments: ["id": id])
      return .success
    }
    commands.stopCommand.isEnabled = true
    commands.pauseCommand.isEnabled = true
    riciStopTarget = commands.stopCommand.addTarget(handler: stop)
    riciPauseTarget = commands.pauseCommand.addTarget(handler: stop)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: "Rici live voice",
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0
    ]
  }
  private var storeReviews: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    socialNative.configureCategories()
    return launched
  }

  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    socialNative.registered(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    socialNative.registrationFailed()
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      willPresent notification: UNNotification,
                                      withCompletionHandler completionHandler:
                                      @escaping (UNNotificationPresentationOptions) -> Void) {
    if socialNative.isSocial(notification.request.content.userInfo) {
      guard socialNative.accepts(notification.request.content.userInfo) else {
        completionHandler([])
        return
      }
      let silentValue = notification.request.content.userInfo["silent"]
      let silent = (silentValue as? Bool == true) || (silentValue as? String == "true")
      if #available(iOS 14.0, *) { completionHandler(silent ? [.banner] : [.banner, .sound]) }
      else { completionHandler(silent ? [.alert] : [.alert, .sound]) }
      return
    }
    super.userNotificationCenter(center, willPresent: notification,
                                 withCompletionHandler: completionHandler)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      didReceive response: UNNotificationResponse,
                                      withCompletionHandler completionHandler: @escaping () -> Void) {
    if socialNative.isSocial(response.notification.request.content.userInfo) {
      socialNative.receive(response)
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response,
                                 withCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KorlixSocialNative") {
      socialNative.attach(messenger: registrar.messenger())
    }
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
          if ready {
            self.socialCallId = id
            if args["kind"] as? String == "rici" { self.showRiciControls(id) }
          }
          result(ready)
        } else if call.method == "stop" {
          if self.socialCallId == id {
            self.socialCallId = nil
            self.clearRiciControls()
          }
          // Do not deactivate the shared audio session underneath another tool.
          result(true)
        } else { result(FlutterMethodNotImplemented) }
      }
    }
  }
}

/// APNs is opt-in and account-bound. It carries only generic alerts and routes;
/// authenticated Dart owns fetching conversations and submitting replies.
private final class KorlixSocialNative {
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let prefix = "korlix.social.native."
  private var channel: FlutterMethodChannel?
  private var owner: String?
  private var binding: String
  private let device: String
  private var enabled: Bool
  private var active = false
  private var token: String?
  private var events: [(payload: [String: Any], expires: Date)] = []
  private var registration: FlutterResult?
  private var registrationTimeout: DispatchWorkItem?
  private var registrationOwner: String?
  private var registrationBinding: String?
  private static let messageCategory = "KORLIX_SOCIAL_MESSAGE"
  private static let activityCategory = "KORLIX_SOCIAL_OPEN"
  private static let replyAction = "KORLIX_SOCIAL_REPLY"

  init() {
    let storage = UserDefaults.standard
    let key = "korlix.social.native."
    let restoredOwner = storage.string(forKey: key + "owner")
    owner = restoredOwner
    binding = storage.string(forKey: key + "binding") ?? UUID().uuidString.lowercased()
    device = storage.string(forKey: key + "device") ?? UUID().uuidString.lowercased()
    enabled = storage.bool(forKey: key + "enabled") && restoredOwner != nil
    defaults.set(device, forKey: prefix + "device")
    defaults.set(binding, forKey: prefix + "binding")
  }

  // An unset setting keeps existing signing profiles/builds working. APNs still
  // verifies the actual signed entitlement before issuing any device token.
  private var environment: String? {
    guard let configured = Bundle.main.object(forInfoDictionaryKey: "KorlixAPNsEnvironment") as? String,
          ["development", "production"].contains(configured) else { return nil }
    return configured == "development" ? "sandbox" : "production"
  }

  func configureCategories() {
    let reply = UNTextInputNotificationAction(
      identifier: Self.replyAction, title: "Reply",
      options: [.foreground, .authenticationRequired],
      textInputButtonTitle: "Send", textInputPlaceholder: "Message")
    let messages = UNNotificationCategory(identifier: Self.messageCategory,
      actions: [reply], intentIdentifiers: [], options: [])
    // Calls are alerts only: opening one never answers or starts a microphone.
    let activity = UNNotificationCategory(identifier: Self.activityCategory,
      actions: [], intentIdentifiers: [], options: [])
    center.getNotificationCategories { [weak self] existing in
      let other = existing.filter {
        ![Self.messageCategory, Self.activityCategory].contains($0.identifier)
      }
      self?.center.setNotificationCategories(Set(other).union([messages, activity]))
    }
  }

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "korlix/social_native", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.handle(call, result: result)
    }
  }

  private func validOwner(_ value: Any?) -> String? {
    guard let value = value as? String, value.utf8.count <= 2048,
          let data = value.data(using: .utf8),
          let pair = try? JSONSerialization.jsonObject(with: data) as? [String],
          pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { return nil }
    return value
  }

  private func clearNotifications() {
    center.getDeliveredNotifications { [weak self] notifications in
      guard let self = self else { return }
      let ids = notifications.filter { self.isSocial($0.request.content.userInfo) }
        .map { $0.request.identifier }
      self.center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    center.getPendingNotificationRequests { [weak self] requests in
      guard let self = self else { return }
      let ids = requests.filter { self.isSocial($0.content.userInfo) }.map { $0.identifier }
      self.center.removePendingNotificationRequests(withIdentifiers: ids)
    }
  }

  private func finishRegistration(_ value: Any?) {
    registrationTimeout?.cancel()
    registrationTimeout = nil
    let completion = registration
    registration = nil
    registrationOwner = nil
    registrationBinding = nil
    completion?(value)
  }

  private func resetDelivery() {
    finishRegistration(FlutterError(code: "account_changed",
      message: "Social notifications changed accounts. Please try again.", details: nil))
    UIApplication.shared.unregisterForRemoteNotifications()
    enabled = false
    defaults.set(false, forKey: prefix + "enabled")
    token = nil
    events.removeAll()
    binding = UUID().uuidString.lowercased()
    defaults.set(binding, forKey: prefix + "binding")
    clearNotifications()
  }

  private func subscription() -> [String: Any]? {
    guard enabled, owner != nil, let token = token, let environment = environment,
          let appID = Bundle.main.bundleIdentifier else { return nil }
    return ["device": device, "binding": binding,
            "subscription": ["provider": "apns", "token": token,
                             "app_id": appID, "environment": environment]]
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "capabilities" {
      center.getNotificationSettings { [weak self] settings in
        DispatchQueue.main.async {
          guard let self = self else { result(nil); return }
          let permission: String
          switch settings.authorizationStatus {
          case .authorized, .provisional: permission = "granted"
          case .denied: permission = "denied"
          default:
            if #available(iOS 14.0, *), settings.authorizationStatus == .ephemeral {
              permission = "granted"
            } else { permission = "default" }
          }
          result(["bubbles": false, "push": self.environment != nil,
                  "provider": "apns", "permission": permission])
        }
      }
      return
    }
    if call.method == "activate" {
      let next = validOwner(args["owner"])
      // Missing/empty owner is logout. Reject malformed nonempty identities.
      if let raw = args["owner"] as? String, !raw.isEmpty, next == nil {
        result(false)
        return
      }
      if next != owner {
        resetDelivery()
        owner = next
        defaults.set(next, forKey: prefix + "owner")
      }
      active = next != nil
      if active && enabled && environment != nil {
        // Token must be obtained anew on every app launch, never from a cache.
        UIApplication.shared.registerForRemoteNotifications()
      }
      result(true)
      return
    }
    guard let requestOwner = validOwner(args["owner"]), requestOwner == owner, active else {
      result(nil)
      return
    }
    switch call.method {
    case "current": result(subscription())
    case "unsubscribe":
      let previous = subscription()
      resetDelivery()
      result(previous)
    case "takeEvent":
      events.removeAll { $0.expires <= Date() }
      result(events.isEmpty ? nil : events.removeFirst().payload)
    case "subscribe": subscribe(requestOwner, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func subscribe(_ requestOwner: String, result: @escaping FlutterResult) {
    guard environment != nil else {
      result(FlutterError(code: "push_not_configured",
        message: "Social notifications are not enabled in this iOS build.", details: nil))
      return
    }
    guard registration == nil else {
      result(FlutterError(code: "registration_busy",
        message: "Notification permission is already being requested.", details: nil))
      return
    }
    let requestBinding = binding
    registration = result
    registrationOwner = requestOwner
    registrationBinding = requestBinding
    // Includes the OS permission prompt; a delayed grant can still deliver a
    // token event after this bounded request returns.
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishRegistration(FlutterError(code: "registration_timeout",
        message: "Notification setup is taking longer than expected. Please try again.", details: nil))
    }
    registrationTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
      DispatchQueue.main.async {
        guard let self = self, self.owner == requestOwner, self.binding == requestBinding,
              self.active else { return }
        guard error == nil, granted else {
          self.enabled = false
          self.defaults.set(false, forKey: self.prefix + "enabled")
          self.finishRegistration(FlutterError(code: "permission_denied",
            message: "Allow notifications in iOS Settings to receive Social alerts.", details: nil))
          return
        }
        self.enabled = true
        self.defaults.set(true, forKey: self.prefix + "enabled")
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  func registered(_ data: Data) {
    guard enabled, active, let owner = owner, environment != nil else { return }
    token = data.map { String(format: "%02x", $0) }.joined()
    if registrationOwner == owner && registrationBinding == binding {
      finishRegistration(subscription())
    }
    emit(["type": "token", "owner": owner, "requestId": UUID().uuidString.lowercased()])
  }

  func registrationFailed() {
    token = nil
    finishRegistration(FlutterError(code: "registration_failed",
      message: "iOS could not register Social notifications. Check this build's push signing and connection.",
      details: nil))
  }

  func isSocial(_ info: [AnyHashable: Any]) -> Bool {
    guard let type = info["type"] as? String else { return false }
    return ["message", "call", "online"].contains(type) && info["binding"] != nil && info["owner"] != nil
  }

  func accepts(_ info: [AnyHashable: Any]) -> Bool {
    guard enabled, environment != nil, let owner = owner, info["owner"] as? String == owner,
          info["binding"] as? String == binding,
          let kind = info["kind"] as? String, ["peer", "group"].contains(kind),
          let id = info["id"] as? String, !id.isEmpty, id.utf8.count <= 256,
          let eventID = info["event_id"] as? String, !eventID.isEmpty, eventID.utf8.count <= 256,
          let expires = expiry(info), expires > Date() else {
      return false
    }
    return isSocial(info)
  }

  private func expiry(_ info: [AnyHashable: Any]) -> Date? {
    guard let raw = info["expires_at"] as? String, raw.utf8.count <= 64 else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatter.date(from: raw) { return parsed }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
  }

  func receive(_ response: UNNotificationResponse) {
    let info = response.notification.request.content.userInfo
    guard accepts(info), let owner = owner, let expires = expiry(info),
          response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
    var event: [String: Any] = [
      "type": "open", "owner": owner, "kind": info["kind"] as! String,
      "id": info["id"] as! String, "requestId": UUID().uuidString.lowercased()
    ]
    if response.actionIdentifier == Self.replyAction {
      guard info["type"] as? String == "message",
            let input = response as? UNTextInputNotificationResponse else { return }
      let text = input.userText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text.utf16.count <= 2000 else { return }
      event["type"] = "reply"
      event["text"] = text
    } else if response.actionIdentifier != UNNotificationDefaultActionIdentifier { return }
    // A fresh process has not restored Dart auth yet. Keep the action in memory
    // until activate(owner) and takeEvent, never send a message in native code.
    emit(event, expires: expires)
  }

  private func emit(_ event: [String: Any], expires: Date = .distantFuture) {
    // The stream signals availability. Dart drains takeEvent after auth is
    // restored, so never discard a reply merely because the channel exists.
    if event["type"] as? String != "token" {
      if events.count >= 20 { events.removeFirst() }
      events.append((payload: event, expires: expires))
    }
    if active { channel?.invokeMethod("event", arguments: event) }
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

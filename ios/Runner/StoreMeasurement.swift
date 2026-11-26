import AppTrackingTransparency
import FirebaseAnalytics
import FirebaseCore
import Flutter
import UIKit

final class StoreMeasurement {
  private let channel: FlutterMethodChannel
  private var generation = 0
  private let ownerKey = "korlix.subscription.measurement.owner"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "korlix/store_measurement", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      self.handle(call, result)
    }
  }

  private func configure() -> Bool {
    guard Bundle.main.bundleIdentifier == "com.korlixdeveloper.korlixai" else { return false }
    if FirebaseApp.app() != nil { return true }
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
          let options = FirebaseOptions(contentsOfFile: path),
          options.bundleID == Bundle.main.bundleIdentifier else { return false }
    FirebaseApp.configure(options: options)
    return true
  }

  private func disable() {
    generation += 1
    if FirebaseApp.app() != nil || UserDefaults.standard.string(forKey: ownerKey) != nil && configure() {
      Analytics.setAnalyticsCollectionEnabled(false)
      Analytics.setConsent([.analyticsStorage: .denied, .adStorage: .denied,
                            .adUserData: .denied, .adPersonalization: .denied])
      Analytics.resetAnalyticsData()
    }
    UserDefaults.standard.removeObject(forKey: ownerKey)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let owner = args?["owner"] as? String
    if call.method == "disable" { disable(); result(nil); return }
    guard call.method == "enable" || call.method == "resume" else {
      result(FlutterMethodNotImplemented); return
    }
    guard let owner, UUID(uuidString: owner) != nil else { result(nil); return }
    if UserDefaults.standard.string(forKey: ownerKey) != owner { disable() }
    let expected = generation
    let apply: (ATTrackingManager.AuthorizationStatus) -> Void = { [weak self] status in
      DispatchQueue.main.async {
        guard let self, self.generation == expected else { result(nil); return }
        guard status == .authorized, self.configure() else { self.disable(); result(nil); return }
        Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .granted,
                              .adUserData: .granted, .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(true)
        if UserDefaults.standard.string(forKey: self.ownerKey) != owner {
          UserDefaults.standard.set(owner, forKey: self.ownerKey)
          Analytics.logEvent("subscription_measurement_opt_in", parameters: nil)
        }
        result(Analytics.appInstanceID())
      }
    }
    if call.method == "enable" && ATTrackingManager.trackingAuthorizationStatus == .notDetermined &&
        UIApplication.shared.applicationState == .active {
      ATTrackingManager.requestTrackingAuthorization(completionHandler: apply)
    } else {
      apply(ATTrackingManager.trackingAuthorizationStatus)
    }
  }
}

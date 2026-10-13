import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PocketwiseNotifications") else { return }
    let channel = FlutterMethodChannel(name: "pocketwise/notifications", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "status":
        Self.notificationStatus(result)
      case "request":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
          if let error = error {
            DispatchQueue.main.async {
              result(FlutterError(code: "permission", message: error.localizedDescription, details: nil))
            }
          } else {
            Self.notificationStatus(result)
          }
        }
      case "openSettings":
        let path: String
        if #available(iOS 16.0, *) {
          path = UIApplication.openNotificationSettingsURLString
        } else {
          path = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: path) else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func notificationStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .notDetermined: status = "notDetermined"
      case .denied: status = "blocked"
      case .authorized: status = "granted"
      case .provisional, .ephemeral: status = "provisional"
      @unknown default: status = "unknown"
      }
      DispatchQueue.main.async { result(status) }
    }
  }
}

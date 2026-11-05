import Flutter
import UIKit
import UserNotifications

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
    // "bcdcnt/badge": clear the red number on the app icon (push sets it).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BcdcntBadge") {
      let channel = FlutterMethodChannel(name: "bcdcnt/badge", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "clear" else { return result(FlutterMethodNotImplemented) }
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
          UIApplication.shared.applicationIconBadgeNumber = 0
        }
        result(nil)
      }
    }
  }
}

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
    // "bcdcnt/settings": open this app's notification settings (after the
    // listener said no to the permission prompt).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BcdcntSettings") {
      let channel = FlutterMethodChannel(name: "bcdcnt/settings", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "openNotificationSettings" else { return result(FlutterMethodNotImplemented) }
        var urlString = UIApplication.openSettingsURLString
        if #available(iOS 16.0, *) { urlString = UIApplication.openNotificationSettingsURLString }
        if let url = URL(string: urlString) { UIApplication.shared.open(url) }
        result(nil)
      }
    }
  }
}

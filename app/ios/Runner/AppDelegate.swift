import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Answers the glass capability query from
  /// `lib/core/theme/glass_capability.dart`.
  ///
  /// Flutter surfaces no "reduce transparency" flag — `MediaQueryData` carries
  /// highContrast, invertColors, disableAnimations and boldText, and nothing for
  /// transparency — so `UIAccessibility.isReduceTransparencyEnabled` has to come
  /// over a channel. iOS always supports blur, so that half is always true.
  ///
  /// The setting can be turned on while the app is running, and toggling it to
  /// see whether an app responds is exactly how someone checks that it is
  /// respected. So the value is pushed on change, not only answered on request.
  private static let glassChannelName = "deutschplan/glass"

  private var glassChannel: FlutterMethodChannel?
  private var reduceTransparencyObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: the reminder shows while the app is open,
    // and a tap reaches Flutter (#157). Written without a Mac to run it.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.glassChannelName,
      binaryMessenger: engineBridge.applicationBinaryMessenger
    )
    glassChannel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "capabilities":
        result([
          "supportsBlur": true,
          "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    reduceTransparencyObserver = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak channel] _ in
      channel?.invokeMethod(
        "capabilitiesChanged",
        arguments: ["reduceTransparency": UIAccessibility.isReduceTransparencyEnabled]
      )
    }
  }

  deinit {
    if let observer = reduceTransparencyObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}

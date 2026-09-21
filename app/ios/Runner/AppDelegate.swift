import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Answers the glass capability query from
  /// `lib/core/theme/glass_capability.dart`.
  ///
  /// Flutter surfaces no "reduce transparency" flag — `MediaQueryData` carries
  /// highContrast, invertColors, disableAnimations and boldText, and nothing for
  /// transparency — so `UIAccessibility.isReduceTransparencyEnabled` has to come
  /// over a channel. iOS always supports blur, so that half is always true.
  private static let glassChannelName = "deutschplan/glass"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.glassChannelName,
      binaryMessenger: engineBridge.applicationBinaryMessenger
    )

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
  }
}

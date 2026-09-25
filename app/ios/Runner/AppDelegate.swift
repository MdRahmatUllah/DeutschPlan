import Flutter
import UIKit
import UserNotifications
import workmanager_apple

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

  /// `lib/services/device_storage.dart`: M4's free space (#156).
  private static let storageChannelName = "deutschplan/storage"

  private var glassChannel: FlutterMethodChannel?
  private var reduceTransparencyObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: the reminder shows while the app is open,
    // and a tap reaches Flutter (#157). Written without a Mac to run it.
    UNUserNotificationCenter.current().delegate = self

    // workmanager (#158): a task's engine gets the app's plugins, and iOS
    // learns the three tasks before launch ends, as BGTaskScheduler asks.
    // The identifiers are `BackgroundTask.id`, and Info.plist's
    // BGTaskSchedulerPermittedIdentifiers. Written without a Mac to run it.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "plan_pregenerate")
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "reminder_compose")
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "widget_refresh",
      earliestBeginInSeconds: NSNumber(value: 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The space M4's card shows and a model download is checked against. The
    // capacity "for important usage" is what iOS will actually free up for a
    // download the user asked for. Written without a Mac to run it.
    FlutterMethodChannel(
      name: AppDelegate.storageChannelName,
      binaryMessenger: engineBridge.applicationBinaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "space" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let home = URL(fileURLWithPath: NSHomeDirectory())
      let values = try? home.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeTotalCapacityKey,
      ])
      result([
        "free": values?.volumeAvailableCapacityForImportantUsage ?? 0,
        "total": values?.volumeTotalCapacity ?? 0,
      ])
    }

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

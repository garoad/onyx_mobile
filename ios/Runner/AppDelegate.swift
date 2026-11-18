import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platformChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnyxPlatform") else { return }
    let channel = FlutterMethodChannel(name: "io.onyx.pocket.editor/platform", binaryMessenger: registrar.messenger())
    platformChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "openAppSettings", let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      } else { result(FlutterMethodNotImplemented) }
    }
  }
}

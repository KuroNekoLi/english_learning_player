import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let flutterEngine = FlutterEngine(name: "EnglishLearningPlayer")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Start the engine explicitly so plugin registration has a binary
    // messenger even when UIKit hasn't connected the app window yet.
    guard flutterEngine.run() else {
      return false
    }

    let controller = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    controller.setFlutterViewDidRenderCallback {
      NSLog("English Learning Player rendered its first Flutter frame.")
    }

    let appWindow = UIWindow(frame: UIScreen.main.bounds)
    appWindow.rootViewController = controller
    window = appWindow
    GeneratedPluginRegistrant.register(with: flutterEngine)
    appWindow.makeKeyAndVisible()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

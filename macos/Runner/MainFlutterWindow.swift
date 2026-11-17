import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var folderAccessPlugin: FolderAccessPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let folderAccessPlugin = FolderAccessPlugin()
    folderAccessPlugin.register(messenger: flutterViewController.engine.binaryMessenger)
    self.folderAccessPlugin = folderAccessPlugin

    super.awakeFromNib()
  }
}

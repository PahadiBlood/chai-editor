import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var clipboardChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    clipboardChannel = FlutterMethodChannel(
      name: "chai/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "getHtml":
        result(NSPasteboard.general.string(forType: .html))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    styleMask.insert(.fullSizeContentView)
    backgroundColor = NSColor(srgbRed: 11.0 / 255, green: 11.0 / 255, blue: 12.0 / 255, alpha: 1)
    flutterViewController.view.frame = contentView!.bounds
    flutterViewController.view.autoresizingMask = [.width, .height]
  }
}

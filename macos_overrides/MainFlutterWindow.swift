import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var filesChannel: FlutterMethodChannel?
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
      case "setClipboard":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              let html = args["html"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "Expected text and html", details: nil))
          return
        }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setString(html, forType: .html) else {
          result(FlutterError(code: "clipboard_write_failed", message: "Could not prepare clipboard", details: nil))
          return
        }
        NSPasteboard.general.clearContents()
        result(NSPasteboard.general.writeObjects([item]))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    filesChannel = FlutterMethodChannel(
      name: "chai/files",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    filesChannel?.setMethodCallHandler { call, result in
      guard call.method == "reveal" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Expected a path", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      if args["directory"] as? Bool == true {
        result(NSWorkspace.shared.open(url))
      } else {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        result(true)
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

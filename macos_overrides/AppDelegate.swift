import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Load the selected asset directly so the Dock does not retain the icon
    // from an earlier build at this same application bundle path.
    if let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
       let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns"),
       let icon = NSImage(contentsOf: iconURL) {
      NSApplication.shared.applicationIconImage = icon
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

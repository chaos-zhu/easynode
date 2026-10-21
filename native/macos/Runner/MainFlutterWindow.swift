import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?
  private var filesChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.contentMinSize = NSSize(width: 900, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let files = FlutterMethodChannel(
      name: "easynode/files",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    files.setMethodCallHandler { call, result in
      switch call.method {
      case "getHomeDirectory":
        result(NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    filesChannel = files

    let channel = FlutterMethodChannel(
      name: "easynode/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setTheme" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let mode = arguments["mode"] as? String,
            let background = arguments["backgroundColor"] as? NSNumber else {
        result(FlutterError(
          code: "invalid_window_theme",
          message: "Expected a theme mode and ARGB background color",
          details: nil
        ))
        return
      }
      switch mode {
      case "light":
        self?.appearance = NSAppearance(named: .aqua)
      case "dark":
        self?.appearance = NSAppearance(named: .darkAqua)
      case "system":
        // Restore inheritance so macOS keeps tracking system appearance.
        self?.appearance = nil
      default:
        result(FlutterError(
          code: "invalid_theme_mode",
          message: "Unknown theme mode",
          details: nil
        ))
        return
      }
      // Let the window's exact theme color show through the native title bar.
      // Appearance alone only selects macOS's standard light/dark gray surface.
      let argb = background.uint32Value
      self?.titlebarAppearsTransparent = true
      self?.backgroundColor = NSColor(
        srgbRed: CGFloat((argb >> 16) & 0xff) / 255,
        green: CGFloat((argb >> 8) & 0xff) / 255,
        blue: CGFloat(argb & 0xff) / 255,
        alpha: CGFloat((argb >> 24) & 0xff) / 255
      )
      result(nil)
    }
    windowChannel = channel

    super.awakeFromNib()
  }
}

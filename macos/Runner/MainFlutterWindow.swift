import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let windowChannelName = "vpet/window"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = NSColor.clear
    flutterViewController.view.wantsLayer = true
    flutterViewController.view.layer?.isOpaque = false
    flutterViewController.view.layer?.backgroundColor = NSColor.clear.cgColor

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentView?.wantsLayer = true
    self.contentView?.layer?.isOpaque = false
    self.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    configureDesktopPetWindow()
    setupWindowChannel(flutterViewController: flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func configureDesktopPetWindow() {
    isOpaque = false
    backgroundColor = NSColor.clear
    alphaValue = 1.0
    hasShadow = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    styleMask.remove(.titled)
    styleMask.remove(.resizable)
    styleMask.remove(.miniaturizable)
    styleMask.remove(.closable)
    setContentSize(NSSize(width: 280, height: 280))
    center()
  }

  private func activeScreenVisibleFrame() -> NSRect {
    if let screen = self.screen {
      return screen.visibleFrame
    }
    return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
  }

  private func clampOrigin(_ proposed: NSPoint) -> NSPoint {
    let visible = activeScreenVisibleFrame()
    let maxX = visible.maxX - frame.width
    let maxY = visible.maxY - frame.height
    return NSPoint(
      x: min(max(proposed.x, visible.minX), maxX),
      y: min(max(proposed.y, visible.minY), maxY)
    )
  }

  private func setupWindowChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: windowChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "quitApp":
        NSApp.terminate(nil)
        result(nil)
      case "moveWindowBy":
        guard
          let args = call.arguments as? [String: Any],
          let dx = args["dx"] as? Double,
          let dy = args["dy"] as? Double
        else {
          result(FlutterError(code: "bad_args", message: "dx/dy required", details: nil))
          return
        }
        let next = NSPoint(x: self.frame.origin.x + dx, y: self.frame.origin.y + dy)
        self.setFrameOrigin(self.clampOrigin(next))
        result(nil)
      case "windowMetrics":
        let frame = self.frame
        let visible = self.activeScreenVisibleFrame()
        result([
          "x": frame.origin.x,
          "y": frame.origin.y,
          "width": frame.width,
          "height": frame.height,
          "screenMinX": visible.minX,
          "screenMinY": visible.minY,
          "screenMaxX": visible.maxX,
          "screenMaxY": visible.maxY,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

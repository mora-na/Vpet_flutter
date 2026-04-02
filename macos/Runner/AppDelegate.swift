import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var secondPetWindow: MainFlutterWindow?
  private var secondWindowRetryCount = 0
  private var didSchedule = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    ensureSecondPetWindow()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc
  private func appDidBecomeActive() {
    ensureSecondPetWindow()
  }

  func ensureSecondPetWindow() {
    scheduleSecondWindowCreation()
  }

  private func scheduleSecondWindowCreation() {
    if didSchedule && secondPetWindow != nil {
      return
    }
    didSchedule = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.createSecondPetWindowIfNeeded()
    }
  }

  private func createSecondPetWindowIfNeeded() {
    if secondPetWindow != nil {
      return
    }
    guard let mainWindow = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first else {
      if secondWindowRetryCount < 20 {
        secondWindowRetryCount += 1
        scheduleSecondWindowCreation()
      }
      return
    }
    secondWindowRetryCount = 0
    var secondOrigin = NSPoint(x: mainWindow.frame.origin.x + 320, y: mainWindow.frame.origin.y - 40)
    if abs(secondOrigin.x - mainWindow.frame.origin.x) < 40 &&
      abs(secondOrigin.y - mainWindow.frame.origin.y) < 40 {
      secondOrigin = NSPoint(x: mainWindow.frame.origin.x - 320, y: mainWindow.frame.origin.y + 40)
    }
    let secondWindow = MainFlutterWindow(
      contentRect: mainWindow.frame,
      styleMask: mainWindow.styleMask,
      backing: .buffered,
      defer: false
    )
    secondWindow.bootstrapDesktopPetWindow(initialOrigin: secondOrigin)
    secondWindow.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    secondPetWindow = secondWindow
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

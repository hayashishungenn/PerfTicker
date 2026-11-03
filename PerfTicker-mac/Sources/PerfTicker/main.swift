import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Art.makeAppIcon(size: 512)
        controller = AppController()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            controller?.restoreFromTray()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.saveSettings()
    }
}

// 应用程序入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

import AppKit
import Darwin

/// 单实例保护：持有 app.lock 文件锁；第二个实例广播唤醒首实例后退出。
/// flock 随进程退出自动释放，不会留下死锁文件。
private let wakeNotification = Notification.Name("com.qiusui.perfticker.wake")
private var instanceLockFd: Int32 = -1

@discardableResult
private func acquireSingleInstance() -> Bool {
    let dir = Settings.dir
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("app.lock").path
    instanceLockFd = open(path, O_CREAT | O_RDWR, 0o644)
    guard instanceLockFd >= 0 else { return true }   // 打不开锁文件时宁可放行，不阻止启动
    if flock(instanceLockFd, LOCK_EX | LOCK_NB) == 0 { return true }
    close(instanceLockFd)
    instanceLockFd = -1
    return false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Art.makeAppIcon(size: 512)
        controller = AppController()
        setupMainMenu()
        // 另一个实例请求唤起主面板
        wakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: wakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.controller?.restoreFromTray()
        }
    }

    /// Dock 图标右键菜单（HIG：高频系统级操作露出在 Dock）
    func applicationDockMenu(_ notification: Notification) -> NSMenu? {
        guard let c = controller else { return nil }
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开主面板", action: #selector(AppController.restoreFromTray), keyEquivalent: "")
        open.target = c
        menu.addItem(open)
        let reset = NSMenuItem(title: "营收归零", action: #selector(AppController.menuResetEconomy), keyEquivalent: "")
        reset.target = c
        menu.addItem(reset)
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            controller?.restoreFromTray()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = wakeObserver { DistributedNotificationCenter.default().removeObserver(obs) }
        controller?.saveSettings()
    }

    /// 标准 macOS 菜单栏：App 菜单（关于/设置⌘,/隐藏/退出）+ 显示 + 窗口。
    /// 注意：不绑定普通字母快捷键，避免拦截进程表搜索框的输入。
    private func setupMainMenu() {
        guard let c = controller else { return }
        let main = NSMenu()

        // App 菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(menuItem("关于 PerfTicker", action: #selector(AppController.showAboutPanel), key: "", target: c))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("设置…", action: #selector(AppController.showSettingsPanel), key: ",", target: c))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("隐藏 PerfTicker", action: #selector(NSApplication.hide(_:)), key: "h", target: nil))
        appMenu.addItem(menuItem("退出 PerfTicker", action: #selector(NSApplication.terminate(_:)), key: "q", target: nil))
        appItem.submenu = appMenu

        // 显示菜单（不带快捷键，字母留给进程搜索框与既有单键快捷键）
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(menuItem("暂停 / 继续行情", action: #selector(AppController.togglePause), key: "", target: c))
        viewMenu.addItem(menuItem("窗口置顶", action: #selector(AppController.toggleTopMost), key: "", target: c))
        viewMenu.addItem(menuItem("切换红涨 / 绿涨", action: #selector(AppController.toggleColor), key: "", target: c))
        viewMenu.addItem(menuItem("营收系统开关", action: #selector(AppController.toggleEconomy), key: "", target: c))
        viewMenu.addItem(menuItem("桌面小挂件", action: #selector(AppController.toggleGadget), key: "", target: c))
        viewItem.submenu = viewMenu

        // 窗口菜单（最小化 / 缩放 / 列出全部窗口）
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, action: Selector, key: String, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}

// 应用程序入口
if !acquireSingleInstance() {
    // 已有实例在运行：广播唤醒它的主面板后退出
    DistributedNotificationCenter.default().postNotificationName(
        wakeNotification, object: nil, userInfo: nil, deliverImmediately: true
    )
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

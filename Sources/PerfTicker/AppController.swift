import AppKit
import ServiceManagement

/// 主应用控制器：管理状态、采样、面板布局、事件分发与设置交互。
final class AppController: NSObject, NSWindowDelegate {
    let st = AppState()
    let hw = Hardware()
    var settings: Settings
    var sampler: Sampler!

    var window: NSWindow!
    var view: MainContentView!
    var statusItem: NSStatusItem?
    var gadgetWindow: GadgetWindow?
    var aboutWindow: AboutWindow?

    var panels: [Panel] = []
    var titlePanel: TitleBarPanel!
    var indexPanel: IndexStripPanel!
    var watchPanel: WatchPanel!
    var instPanel: InstrumentPanel!
    var chartPanel: ChartPanel!
    var econPanel: EconomyPanel!
    var bookPanel: BookPanel!
    var tapePanel: TapePanel!
    var procPanel: ProcPanel!
    var footerPanel: FooterPanel!

    private var uiTimer: Timer?
    private var lastTick: Int64 = -1
    private var frameCount: Double = 0
    private var ecoLastSave: Double = 0
    private var lastTickMs: Int64 = 0
    private var lastStatusSec: Int64 = 0
    private var prevCpu: [Int32: Double] = [:]
    private var prevPids = Set<Int32>()
    private var prevNames: [Int32: String] = [:]
    private var firstIngest = false
    private var hwProbed = false

    var settingsOpen = false
    private var settingsHover = -1
    private var setPanel = CGRect.zero, setAuto = CGRect.zero, setMarquee = CGRect.zero
    private var setThemeDark = CGRect.zero, setThemeLight = CGRect.zero, setThemeAuto = CGRect.zero, setLog = CGRect.zero

    // 辅助功能：减弱动态效果 / 增强对比度（系统设置即时生效）
    private var reduceMotionObserver: NSKeyValueObservation?
    private var increaseContrastObserver: NSKeyValueObservation?

    var gadgetOn: Bool { gadgetWindow != nil && gadgetWindow!.isVisible }

    override init() {
        let (s, cfgWarn) = Settings.load()
        self.settings = s
        super.init()

        st.intervalMs = settings.intervalMs
        st.periodMs = settings.periodMs
        st.redUp = settings.redUp
        st.economy.enabled = settings.economyOn
        st.procSort = settings.procSort
        st.procSortDesc = settings.procSortDesc
        st.marquee = settings.marquee
        st.economy.restore(total: settings.ecoTotal, peak: settings.ecoPeak, seconds: settings.ecoSeconds)
        st.applyColorMode()

        sampler = Sampler()
        sampler.intervalMs = st.intervalMs
        st.metrics = Catalog.build(cores: sampler.cores)
        st.cpuName = sampler.cpuName
        if let idx = st.metrics.firstIndex(where: { $0.code == settings.selectedCode }) {
            st.selectedIndex = idx
        }

        applyTheme()

        initPanels()
        initWindow()
        initStatusItem()

        if settings.gadget { showGadget() }
        if let warn = cfgWarn { addTape("配置提示 · " + warn, Theme.warn) }
        if settings.themeMode == 2 { watchSystemAppearance() }
        watchAccessibility()

        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.onUiTick()
        }
    }

    /// 跟随系统辅助功能偏好：减弱动态效果 / 增强对比度（HIG Accessibility）
    private func watchAccessibility() {
        let ws = NSWorkspace.shared
        reduceMotionObserver = ws.observe(\.accessibilityDisplayShouldReduceMotion, options: [.initial, .new]) { [weak self] _, ch in
            Motion.reduce = ch.newValue ?? false
            DispatchQueue.main.async { self?.view?.setNeedsDisplay(self?.view?.bounds ?? .zero) }
        }
        increaseContrastObserver = ws.observe(\.accessibilityDisplayShouldIncreaseContrast, options: [.initial, .new]) { [weak self] _, ch in
            Theme.hiContrast = ch.newValue ?? false
            DispatchQueue.main.async { self?.applyTheme() }
        }
    }

    private func initPanels() {
        titlePanel = TitleBarPanel(self)
        indexPanel = IndexStripPanel(self)
        watchPanel = WatchPanel(self)
        instPanel = InstrumentPanel(self)
        chartPanel = ChartPanel(self)
        econPanel = EconomyPanel(self)
        bookPanel = BookPanel(self)
        tapePanel = TapePanel(self)
        procPanel = ProcPanel(self)
        footerPanel = FooterPanel(self)
        panels = [titlePanel, indexPanel, watchPanel, instPanel, chartPanel, econPanel, bookPanel, tapePanel, procPanel, footerPanel]
    }

    private func initWindow() {
        let wa = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defW = min(1440.0, wa.width - 40)
        let defH = min(900.0, wa.height - 40)
        var w = settings.w > 600 ? CGFloat(settings.w) : defW
        var h = settings.h > 400 ? CGFloat(settings.h) : defH
        var x = settings.x > -9999 ? CGFloat(settings.x) : wa.origin.x + (wa.width - w) / 2
        var y = settings.y > -9999 ? CGFloat(settings.y) : wa.origin.y + (wa.height - h) / 2
        // 记忆位置与任何屏幕都不相交（如拔掉外接屏）时回退居中，避免窗口完全不可见
        if settings.x > -9999 {
            let frame = NSRect(x: x, y: y, width: w, height: h)
            if !NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -20, dy: -20).intersects(frame) }) {
                x = wa.origin.x + max(0, (wa.width - w) / 2)
                y = wa.origin.y + max(0, (wa.height - h) / 2)
            }
        }

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1100, height: 680)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = Theme.bgDeep
        window.delegate = self

        view = MainContentView(controller: self)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        if settings.topMost {
            window.level = .floating
            st.topMost = true
        }
        layoutPanels()
    }

    func windowDidResize(_ notification: Notification) {
        layoutPanels()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveSettings()
        window.orderOut(nil)
        return false
    }

    func layoutPanels() {
        guard let win = window else { return }
        let size = win.contentView?.bounds.size ?? NSSize(width: 1280, height: 800)
        let W = size.width, H = size.height

        let titleH: CGFloat = 42, indexH: CGFloat = 58, footerH: CGFloat = 28
        let bottomH = min(300.0, max(200.0, H * 0.238))
        let leftW: CGFloat = 298
        var rightW: CGFloat = W < 1420 ? 300 : 342
        var centerW = W - leftW - rightW
        if centerW < 420 {
            rightW = max(250, W - leftW - 420)
            centerW = W - leftW - rightW
        }

        let y0 = titleH + indexH
        let footerY = H - footerH
        let bottomTop = footerY - bottomH

        titlePanel.bounds = CGRect(x: 0, y: 0, width: W, height: titleH)
        indexPanel.bounds = CGRect(x: 0, y: titleH, width: W, height: indexH)
        watchPanel.bounds = CGRect(x: 0, y: y0, width: leftW, height: max(120, bottomTop - y0))
        procPanel.bounds = CGRect(x: 0, y: bottomTop, width: W, height: H - footerH - bottomTop)
        footerPanel.bounds = CGRect(x: 0, y: footerY, width: W, height: footerH)

        let rightH = max(120, bottomTop - y0)
        let bookH = min(rightH - 220, 330)
        bookPanel.bounds = CGRect(x: W - rightW, y: y0, width: rightW, height: bookH)
        tapePanel.bounds = CGRect(x: W - rightW, y: y0 + bookH, width: rightW, height: rightH - bookH)

        let instH: CGFloat = 98
        let ecoH: CGFloat = st.economy.enabled ? 96 : 0
        instPanel.bounds = CGRect(x: leftW, y: y0, width: centerW, height: instH)
        chartPanel.bounds = CGRect(x: leftW, y: y0 + instH, width: centerW, height: max(80, bottomTop - y0 - instH - ecoH))
        econPanel.bounds = ecoH > 0 ? CGRect(x: leftW, y: bottomTop - ecoH, width: centerW, height: ecoH) : .zero

        view.setNeedsDisplay(view.bounds)
    }

    func findPanel(_ p: CGPoint) -> Panel? {
        for panel in panels where panel.bounds.contains(p) { return panel }
        return nil
    }

    // MARK: - 主题
    private var appearanceObserver: NSKeyValueObservation?

    private func isSystemDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func watchSystemAppearance() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyTheme() }
        }
    }

    func applyTheme() {
        let isDark = settings.themeMode == 0 || (settings.themeMode == 2 && isSystemDark())
        Theme.setTheme(dark: isDark)
        st.applyColorMode()
        if let win = window {
            win.backgroundColor = Theme.bgDeep
            view?.setNeedsDisplay(view.bounds)
        }
    }

    func setThemeMode(_ mode: Int) {
        settings.themeMode = max(0, min(2, mode))
        if mode == 2 { watchSystemAppearance() }
        applyTheme()
        saveSettings()
    }

    // MARK: - 设置持久化
    func saveSettings() {
        if let win = window {
            let f = win.frame
            settings.x = Double(f.origin.x)
            settings.y = Double(f.origin.y)
            settings.w = Double(f.size.width)
            settings.h = Double(f.size.height)
        }
        settings.intervalMs = st.intervalMs
        settings.periodMs = st.periodMs
        settings.redUp = st.redUp
        settings.topMost = st.topMost
        settings.economyOn = st.economy.enabled
        settings.gadget = gadgetOn
        settings.marquee = st.marquee
        settings.ecoTotal = st.economy.total
        settings.ecoPeak = st.economy.peakRate
        settings.ecoSeconds = st.economy.seconds
        settings.selectedCode = st.selected.code
        settings.procSort = st.procSort
        settings.procSortDesc = st.procSortDesc
        settings.save()
    }

    // MARK: - 状态栏托盘
    private func initStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = Art.makeStatusIcon()
            button.imagePosition = .imageLeading
            button.title = " 性能"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开主面板", action: #selector(restoreFromTray), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "营收归零", action: #selector(menuResetEconomy), keyEquivalent: ""))
        let gadgetItem = NSMenuItem(title: "桌面小挂件", action: #selector(toggleGadget), keyEquivalent: "g")
        gadgetItem.state = gadgetOn ? .on : .off
        menu.addItem(gadgetItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(exitApp), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem?.menu = menu
    }

    @objc func restoreFromTray() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func menuResetEconomy() { resetEconomy() }

    @objc func exitApp() {
        saveSettings()
        NSApp.terminate(nil)
    }

    // MARK: - 桌面小挂件
    @objc func toggleGadget() {
        if gadgetOn {
            gadgetWindow?.orderOut(nil)
            gadgetWindow = nil
            addTape("桌面小挂件已关闭", Theme.textFade)
        } else {
            showGadget()
            addTape("桌面小挂件已开启 · 双击标题可展开主面板", Theme.cyan)
        }
        settings.gadget = gadgetOn
        saveSettings()
        titlePanel.invalidate()
    }

    func showGadget() {
        if gadgetWindow == nil {
            gadgetWindow = GadgetWindow(app: self)
        }
        gadgetWindow?.orderFront(nil)
    }

    // MARK: - 界面心跳
    private func onUiTick() {
        let onScreen = window.isVisible && !window.isMiniaturized

        // 动画相位与营收结算都用真实墙钟 dt，避免系统繁忙/休眠恢复时漂移
        let now = nowMs()
        var dt = lastTickMs > 0 ? Double(now - lastTickMs) / 1000 : 0.033
        lastTickMs = now
        if dt < 0 { dt = 0.033 }
        if dt > 0.25 { dt = 0.25 }   // 长时间挂起后不追帧
        frameCount += dt
        st.frame = frameCount

        let snap = sampler.latest
        if !st.paused && snap.tick != lastTick && snap.tick > 0 {
            lastTick = snap.tick
            ingest(snap)
        }

        if st.economy.enabled {
            if !st.paused { st.economy.accrue(dt, st.snap) }
            if onScreen { econPanel.invalidate() }
        }

        if !onScreen { return }

        var tweening = false
        if !st.paused {
            if Motion.reduce {
                // 系统开启「减弱动态效果」：数值直接落定，不做缓动
                for m in st.metrics { m.shown = m.value }
            } else {
                for m in st.metrics where m.tween() { tweening = true }
            }
        }
        if tweening {
            indexPanel.invalidate()
            instPanel.invalidate()
        }

        if chartPanel.advance() { chartPanel.invalidate() }
        if procPanel.advance() { procPanel.invalidate() }
        footerPanel.invalidate()

        if st.economy.enabled && frameCount - ecoLastSave > 15 {
            ecoLastSave = frameCount
            saveSettings()
        }

        // 状态栏气泡简报（每秒一次即可）
        if let button = statusItem?.button, now / 1000 != lastStatusSec {
            lastStatusSec = now / 1000
            let s = st.snap
            var tip = String(format: " CPU %.0f%% · GPU %.0f%% · 内存 %.0f%%", s.cpuPct, s.gpu.available ? s.gpu.utilPct : 0, s.memPct)
            if st.economy.enabled { tip += String(format: " · ¥%.0f", st.economy.total) }
            button.title = tip
        }
    }

    private func ingest(_ s: Snapshot) {
        let prev = st.snap
        st.snap = s
        let now = nowMs()
        let vol = max(0, s.ctxSwitchPerSec)

        for m in st.metrics {
            m.push(m.read(s), now, vol)
        }

        var alive = Set<Int32>()
        for p in s.procs {
            alive.insert(p.pid)
            if let pc = prevCpu[p.pid] { p.cpuDelta = p.cpuPct - pc }
            prevCpu[p.pid] = p.cpuPct
            if st.procHist[p.pid] == nil { st.procHist[p.pid] = ProcHist() }
            st.procHist[p.pid]?.push(p.cpuPct)
        }
        // 进程历史只增不减会长期占用内存：超限后移除已退出进程的条目（以当前快照的 pid 集合为准）
        if st.procHist.count > 1200 {
            for pid in st.procHist.keys.filter({ !alive.contains($0) }).prefix(600) {
                st.procHist.removeValue(forKey: pid)
                prevCpu.removeValue(forKey: pid)
            }
        }
        // prevCpu 超限同样按存活集合剔除；不能整体清空，否则下一帧所有进程的 cpuDelta 会失真为 0
        if prevCpu.count > 4000 {
            for pid in prevCpu.keys where !alive.contains(pid) {
                prevCpu.removeValue(forKey: pid)
            }
        }

        if !hwProbed && !s.procs.isEmpty {
            hwProbed = true
            hw.probe(cpuName: sampler.cpuName, gpuName: s.gpu.name, gpuCores: s.gpu.cores, hasGpu: s.gpu.available, memTotalGB: s.memTotalGB)
            st.economy.applyWeights(hw)
            addTape("硬件探测完成 · \(hw.logicalCores) 核 / \(String(format: "%.0fG", hw.memTotalGB)) 内存 / \(hw.gpuName)", Theme.blue)
        }

        st.procs = s.procs
        sortProcs()
        detectEvents(prev, s)
        if !st.metrics.isEmpty { st.selected.rebuildCandles(st.periodMs) }
        view.setNeedsDisplay(view.bounds)
    }

    func sortProcs() {
        let desc = st.procSortDesc
        st.procs.sort { a, b in
            let res: Bool
            switch st.procSort {
            case 0: res = a.cpuPct > b.cpuPct
            case 1: res = a.gpuPct > b.gpuPct
            case 2: res = a.memMB > b.memMB
            default: res = a.threads > b.threads
            }
            return desc ? res : !res
        }
    }

    private func detectEvents(_ prev: Snapshot, _ s: Snapshot) {
        if !firstIngest {
            firstIngest = true
            addTape("行情接入完成 · 已载入 \(st.metrics.count) 项自选 · \(sampler.cores) 核", Theme.gold)
        }
        let curPids = Set(s.procs.map { $0.pid })
        var curNames: [Int32: String] = [:]
        for p in s.procs { curNames[p.pid] = p.name }

        if !prevPids.isEmpty {
            var added = 0
            for p in s.procs {
                if !prevPids.contains(p.pid) && p.pid > 0 && added < 2 {
                    addTape("新进 \(trim(p.name)) · \(p.pid)", Theme.blue)
                    added += 1
                }
            }
            var removed = 0
            for pid in prevPids {
                if !curPids.contains(pid) && removed < 2 {
                    let nm = prevNames[pid] ?? "\(pid)"
                    addTape("退出 \(trim(nm)) · \(pid)", Theme.textFade)
                    removed += 1
                }
            }
        }
        prevPids = curPids
        prevNames = curNames

        if s.gpu.available && s.gpu.utilPct >= 92 && prev.gpu.utilPct < 92 {
            addTape("GPU 负载触顶 \(String(format: "%.0f%%", s.gpu.utilPct))", Theme.warn)
        }
        if s.cpuPct >= 88 && prev.cpuPct < 88 {
            addTape("CPU 负载预警 \(String(format: "%.0f%%", s.cpuPct))", Theme.warn)
        }
        if s.memPct >= 90 && prev.memPct < 90 {
            addTape("内存水位 \(String(format: "%.0f%%", s.memPct)) 逼近上限", Theme.warn)
        }
        if s.diskReadMBps >= 200 && prev.diskReadMBps < 200 {
            addTape("磁盘突发读取 \(String(format: "%.0fMB/s", s.diskReadMBps))", Theme.cyan)
        }

        var ticks = 0
        for p in s.procs {
            if ticks >= 2 { break }
            if abs(p.cpuDelta) < 1.2 { continue }
            addTape("\(trim(p.name))  \(String(format: "%.1f%%", p.cpuPct))  \(p.cpuDelta > 0 ? "▲" : "▼")\(String(format: "%.1f", abs(p.cpuDelta)))",
                    p.cpuDelta > 0 ? Theme.up : Theme.down)
            ticks += 1
        }
    }

    private func trim(_ s: String) -> String { s.count > 22 ? String(s.prefix(22)) + "…" : s }

    private static let tapeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func addTape(_ text: String, _ color: NSColor) {
        let now = nowMs()
        if let last = st.tape.last, last.text == text && now - last.ms < 5000 { return }
        st.tape.append(TapeEvent(ms: now, time: Self.tapeFormatter.string(from: Date()), text: text, color: color))
        if st.tape.count > 240 { st.tape.removeFirst(st.tape.count - 240) }
    }

    // MARK: - 操作命令入口
    /// 菜单栏「关于 PerfTicker」
    @objc func showAboutPanel() { showAbout() }

    /// 菜单栏「设置…」⌘,
    @objc func showSettingsPanel() {
        if !settingsOpen { toggleSettings() }
    }

    func selectMetric(_ code: String) {
        guard let idx = st.metrics.firstIndex(where: { $0.code == code }) else { return }
        st.selectedIndex = idx
        onMetricChanged()
    }

    func onMetricChanged() {
        st.selected.rebuildCandles(st.periodMs)
        view.setNeedsDisplay(view.bounds)
    }

    func setChartMode(_ period: Int64) {
        if period < Int64(st.intervalMs) * 2 { return }
        st.periodMs = max(500, period)
        st.selected.rebuildCandles(st.periodMs)
        view.setNeedsDisplay(view.bounds)
    }

    func setInterval(_ ms: Int) {
        st.intervalMs = ms
        sampler.intervalMs = ms
        if st.periodMs < Int64(ms) * 2 {
            let periods: [Int64] = [2000, 5000, 10000, 30000, 60000]
            st.periodMs = periods.first(where: { $0 >= Int64(ms) * 2 }) ?? 60000
        }
        st.selected.rebuildCandles(st.periodMs)
        addTape(String(format: "采样周期切换 %.1fs · K 线 %d秒", Double(ms) / 1000, st.periodMs / 1000), Theme.blue)
        view.setNeedsDisplay(view.bounds)
    }

    @objc func togglePause() {
        st.paused = !st.paused
        addTape(st.paused ? "行情已暂停" : "行情恢复推送", st.paused ? Theme.warn : Theme.down)
        view.setNeedsDisplay(view.bounds)
    }

    @objc func toggleTopMost() {
        st.topMost = !st.topMost
        window.level = st.topMost ? .floating : .normal
        view.setNeedsDisplay(view.bounds)
    }

    @objc func toggleEconomy() {
        st.economy.enabled = !st.economy.enabled
        layoutPanels()
        addTape(st.economy.enabled ? "营收系统已启动 · 按占用率结算产能" : "营收系统已关闭",
                st.economy.enabled ? Theme.gold : Theme.textFade)
        view.setNeedsDisplay(view.bounds)
    }

    @objc func toggleColor() {
        st.redUp = !st.redUp
        st.applyColorMode()
        view.setNeedsDisplay(view.bounds)
    }

    func resetEconomy() {
        st.economy.reset()
        saveSettings()
        addTape("营收已归零", Theme.gold)
        view.setNeedsDisplay(view.bounds)
    }

    func toggleSettings() {
        settingsOpen = !settingsOpen
        settingsHover = -1
        view.setNeedsDisplay(view.bounds)
    }

    func toggleMarquee() {
        st.marquee = !st.marquee
        saveSettings()
        footerPanel.invalidate()
    }

    func toggleAutoStart() {
        guard #available(macOS 13.0, *) else {
            addTape("开机自启动需要 macOS 13 及以上", Theme.warn)
            return
        }
        let want = !settings.autoStart
        do {
            if want {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.autoStart = want
            addTape(want ? "已设置开机自启动" : "已取消开机自启动", Theme.gold)
        } catch {
            // 注册失败时回滚开关状态，避免设置与实际不符
            Diag.error("AUTOSTART", "\(error)")
            addTape("开机自启动设置失败 · \(error.localizedDescription)", Theme.warn)
        }
        saveSettings()
        view.setNeedsDisplay(view.bounds)
    }

    func setProcSort(_ i: Int) {
        if st.procSort == i { st.procSortDesc = !st.procSortDesc }
        else { st.procSort = i; st.procSortDesc = true }
        sortProcs()
        procPanel.invalidateView()
        procPanel.invalidate()
    }

    func setSearchActive(_ on: Bool) {
        st.searchActive = on
        procPanel.invalidate()
    }

    func setProcFilter(_ f: String) {
        st.procFilter = f
        st.procScroll = 0
        procPanel.invalidate()
    }

    func togglePin(_ name: String) {
        if st.pinned.contains(name) { st.pinned.remove(name) }
        else { st.pinned.insert(name) }
        sortProcs()
        addTape(st.pinned.contains(name) ? "已置顶 \(trim(name))" : "已取消置顶 \(trim(name))", Theme.gold)
        procPanel.invalidateView()
        procPanel.invalidate()
    }

    func showAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindow(hw: hw)
        }
        aboutWindow?.level = window.level
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    func showProcMenu(pid: Int32, at p: CGPoint) {
        let name = st.procs.first(where: { $0.pid == pid })?.name ?? "\(pid)"
        let menu = NSMenu()
        let killItem = NSMenuItem(title: "全抛 · 结束进程 (\(trim(name)))", action: #selector(menuKillProc(_:)), keyEquivalent: "")
        killItem.representedObject = ["pid": Int(pid), "name": name]
        killItem.target = self
        menu.addItem(killItem)

        let pinned = st.pinned.contains(name)
        let pinItem = NSMenuItem(title: pinned ? "取消置顶" : "置顶到榜首", action: #selector(menuTogglePin(_:)), keyEquivalent: "")
        pinItem.representedObject = name
        pinItem.target = self
        menu.addItem(pinItem)

        let copyItem = NSMenuItem(title: "复制进程名", action: #selector(menuCopyName(_:)), keyEquivalent: "")
        copyItem.representedObject = name
        copyItem.target = self
        menu.addItem(copyItem)

        if let ev = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: ev, for: view)
        }
    }

    @objc private func menuKillProc(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let pidVal = info["pid"] as? Int,
              let name = info["name"] as? String else { return }
        let pid = Int32(truncatingIfNeeded: pidVal)
        if pid == ProcessInfo.processInfo.processIdentifier {
            addTape("全抛被拒绝 · 不能结束行情终端自身", Theme.warn)
            return
        }
        // 防止 PID 复用误杀：菜单弹出后目标可能已退出、PID 被系统分配给别的进程
        let cur = st.procs.first(where: { $0.pid == pid })
        guard let cur = cur, cur.name == name else {
            addTape("全抛取消 · \(trim(name)) (\(pid)) 已退出或已变化", Theme.warn)
            view.setNeedsDisplay(view.bounds)
            return
        }
        if kill(pid, SIGTERM) == 0 {
            addTape("全抛成交 · 已结束 \(trim(name)) (\(pid))", Theme.down)
        } else {
            addTape("全抛失败 · \(trim(name)) (\(pid)) 权限不足或已退出", Theme.warn)
        }
        view.setNeedsDisplay(view.bounds)
    }

    @objc private func menuTogglePin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        togglePin(name)
    }

    @objc private func menuCopyName(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }

    // MARK: - 设置浮层
    func paintSettings(in clip: NSRect) {
        guard settingsOpen else { return }
        let pad: CGFloat = 12, rowH: CGFloat = 38
        let w: CGFloat = 302, h: CGFloat = 252
        let x: CGFloat = TitleBarPanel.leftInset + 100
        let y: CGFloat = titlePanel.bounds.maxY + 6
        setPanel = CGRect(x: x, y: y, width: w, height: h)

        Theme.roundedFill(setPanel.offsetBy(dx: 4, dy: 4), 5, NSColor.black.a(70.0 / 255))
        Theme.roundedFill(setPanel, 5, Theme.popBg)
        Theme.roundedRect(setPanel, 5, fill: nil, stroke: Theme.line2)
        Theme.fill(CGRect(x: setPanel.minX, y: setPanel.minY, width: 3, height: setPanel.height), Theme.gold)

        Theme.text("设置", Theme.uiL, Theme.textHi, CGRect(x: setPanel.minX + pad, y: setPanel.minY + 8, width: 80, height: 20))
        Theme.text("v1.5.0", Theme.numXXS, Theme.textFade, CGRect(x: setPanel.maxX - 58, y: setPanel.minY + 8, width: 46, height: 20), .right)

        var ry = setPanel.minY + 36
        func drawSwitch(_ box: CGRect, _ on: Bool, _ hoverIdx: Int) {
            let bg = on ? Theme.gold.a(0xF0 / 255.0) : Theme.panelSoft
            let bd = on ? Theme.gold : Theme.line2
            Theme.roundedRect(box, box.height / 2, fill: bg, stroke: bd)
            let kr = box.height - 4
            let kx = on ? box.maxX - kr - 2 : box.minX + 2
            Theme.ellipse(CGRect(x: kx, y: box.minY + 2, width: kr, height: kr), on ? (Theme.dark ? rgb(0x14, 0x18, 0x22) : .white) : Theme.textFade)
            if settingsHover == hoverIdx {
                Theme.strokeRect(box.insetBy(dx: -1, dy: -1), Theme.gold.a(90.0 / 255))
            }
        }

        // 开机自启动
        Theme.text("开机自启动", Theme.uiM, settingsHover == 1 ? Theme.textHi : Theme.txt, CGRect(x: setPanel.minX + pad, y: ry, width: 150, height: rowH))
        setAuto = CGRect(x: setPanel.maxX - pad - 38, y: ry + 9, width: 38, height: 20)
        drawSwitch(setAuto, settings.autoStart, 1)
        ry += rowH

        // 底部滚动信息
        Theme.text("底部滚动信息", Theme.uiM, settingsHover == 2 ? Theme.textHi : Theme.txt, CGRect(x: setPanel.minX + pad, y: ry, width: 150, height: rowH))
        setMarquee = CGRect(x: setPanel.maxX - pad - 38, y: ry + 9, width: 38, height: 20)
        drawSwitch(setMarquee, st.marquee, 2)
        ry += rowH

        // 界面主题
        Theme.text("界面主题", Theme.uiM, Theme.txt, CGRect(x: setPanel.minX + pad, y: ry, width: 90, height: 22))
        let sw: CGFloat = 66, sh2: CGFloat = 22, gapx: CGFloat = 3
        let bx = setPanel.maxX - pad - (sw * 3 + gapx * 2)
        setThemeDark = CGRect(x: bx, y: ry, width: sw, height: sh2)
        setThemeLight = CGRect(x: bx + sw + gapx, y: ry, width: sw, height: sh2)
        setThemeAuto = CGRect(x: bx + (sw + gapx) * 2, y: ry, width: sw, height: sh2)

        func themeChip(_ box: CGRect, _ label: String, _ mode: Int) {
            let act = settings.themeMode == mode
            let hov = settingsHover == 3 + mode
            Theme.roundedRect(box, 3, fill: act ? Theme.gold.a(40.0 / 255) : (hov ? Theme.panelSoft : Theme.chipBg), stroke: act ? Theme.gold : Theme.line2)
            Theme.text(label, Theme.uiXS, act ? Theme.gold : (hov ? Theme.textHi : Theme.textDim), box, .center)
        }
        themeChip(setThemeDark, "深色", 0)
        themeChip(setThemeLight, "浅色", 1)
        themeChip(setThemeAuto, "跟随系统", 2)
        ry += 34

        // 诊断日志
        Theme.text("诊断日志", Theme.uiM, settingsHover == 6 ? Theme.textHi : Theme.txt, CGRect(x: setPanel.minX + pad, y: ry, width: 90, height: 22))
        setLog = CGRect(x: setPanel.maxX - pad - 52, y: ry + 1, width: 52, height: 20)
        Theme.roundedRect(setLog, 3, fill: settingsHover == 6 ? Theme.panelSoft : Theme.chipBg, stroke: Theme.line2)
        Theme.text("打开", Theme.uiXS, settingsHover == 6 ? Theme.gold : Theme.textDim, setLog, .center)
        ry += 30

        Theme.text("设置会自动保存到本地配置", Theme.uiXS, Theme.textFade, CGRect(x: setPanel.minX + pad, y: ry, width: 240, height: 18))
    }

    func settingsMouseMove(_ p: CGPoint) {
        var h = -1
        if setAuto.contains(p) { h = 1 }
        else if setMarquee.contains(p) { h = 2 }
        else if setThemeDark.contains(p) { h = 3 }
        else if setThemeLight.contains(p) { h = 4 }
        else if setThemeAuto.contains(p) { h = 5 }
        else if setLog.contains(p) { h = 6 }
        if h != settingsHover {
            settingsHover = h
            view.setNeedsDisplay(view.bounds)
        }
    }

    func settingsClick(_ p: CGPoint) -> Bool {
        if setAuto.contains(p) { toggleAutoStart(); return true }
        if setMarquee.contains(p) { toggleMarquee(); return true }
        if setThemeDark.contains(p) { setThemeMode(0); return true }
        if setThemeLight.contains(p) { setThemeMode(1); return true }
        if setThemeAuto.contains(p) { setThemeMode(2); return true }
        if setLog.contains(p) {
            NSWorkspace.shared.open(Diag.logDir)
            return true
        }
        if !setPanel.contains(p) {
            settingsOpen = false
            view.setNeedsDisplay(view.bounds)
        }
        return true
    }
}

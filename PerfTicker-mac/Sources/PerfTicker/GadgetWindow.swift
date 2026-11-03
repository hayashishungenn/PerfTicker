import AppKit

/// 桌面小挂件：常驻桌面的迷你行情面板，双击标题打开主面板。
final class GadgetWindow: NSWindow {
    private let gadgetView: GadgetView
    init(app: AppController) {
        gadgetView = GadgetView(app: app)
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 372, height: 214),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = gadgetView
        self.isMovableByWindowBackground = false

        let wa = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var gx = CGFloat(app.settings.gadgetX)
        var gy = CGFloat(app.settings.gadgetY)
        if gx < 0 || gy < 0 || gx > wa.maxX - 100 || gy > wa.maxY - 100 {
            gx = wa.maxX - 372 - 28
            gy = wa.minY + 28
        }
        self.setFrameOrigin(NSPoint(x: gx, y: gy))
    }

    func updatePinned(_ pinned: Bool) {
        self.level = pinned ? .floating : .normal
        gadgetView.setNeedsDisplay(gadgetView.bounds)
    }
}

final class GadgetView: NSView {
    unowned let app: AppController
    private var closeRect = CGRect.zero
    private var pinRect = CGRect.zero
    private var hover = 0
    private var isDragging = false
    private var dragStart = NSPoint.zero
    private var timer: Timer?

    init(app: AppController) {
        self.app = app
        super.init(frame: NSRect(x: 0, y: 0, width: 372, height: 214))
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height

        Theme.roundedFill(bounds, 8, Theme.panel.a(0.95))
        Theme.roundedRect(bounds, 8, fill: nil, stroke: Theme.line2, width: 1)
        Theme.roundedFill(CGRect(x: 0, y: 0, width: w, height: 3), 1.5, Theme.gold)

        // 标题行
        let headH: CGFloat = 30
        Theme.text("▮ 性能行情", Theme.uiS, Theme.textHi, CGRect(x: 12, y: 4, width: 90, height: headH))
        Theme.text("挂件", Theme.uiXS, Theme.gold, CGRect(x: 88, y: 4, width: 40, height: headH))

        pinRect = CGRect(x: w - 58, y: 6, width: 22, height: 18)
        closeRect = CGRect(x: w - 30, y: 6, width: 22, height: 18)
        let pinned = app.window.level == .floating

        Theme.roundedRect(pinRect, 3, fill: pinned ? Theme.cyan.a(40.0 / 255) : (hover == 1 ? Theme.panelSoft : nil), stroke: Theme.line2)
        Theme.text("顶", Theme.uiXS, pinned ? Theme.cyan : Theme.textDim, pinRect, .center)

        Theme.roundedRect(closeRect, 3, fill: hover == 2 ? Theme.panelSoft : nil, stroke: Theme.line2)
        Theme.text("✕", Theme.uiXS, hover == 2 ? Theme.up : Theme.textDim, closeRect, .center)

        let s = app.st.snap
        let cpu = s.cpuPct
        let gpu = s.gpu.available ? s.gpu.utilPct : 0
        let mem = s.memPct
        var y: CGFloat = 34

        // CPU / GPU 大数字
        let halfW = (w - 24) / 2
        big(12, y, halfW, "CPU", String(format: "%.1f%%", cpu), "用户态 \(String(format: "%.1f%%", s.cpuUserPct))", Theme.gold)
        big(12 + halfW, y, halfW, "GPU", String(format: "%.1f%%", gpu), s.gpu.available ? "\(s.gpu.name)" : "未检测", Theme.cyan)

        // 迷你走势
        y += 58
        let chartH: CGFloat = 46
        let r = CGRect(x: 12, y: y, width: w - 24, height: chartH)
        Theme.fill(r, Theme.panelHi)
        Theme.strokeRect(r, Theme.line2)

        let data = !app.st.metrics.isEmpty ? app.st.selected.spark(40) : []
        if data.count >= 2 {
            var lo = data.min()!, hi = data.max()!
            if hi - lo < 1e-9 { hi += 1; lo -= 1 }
            let ctx = Theme.cg
            ctx.saveGState()
            ctx.setStrokeColor(Theme.gold.cgColor)
            ctx.setLineWidth(1.2)
            ctx.setLineJoin(.round)
            for (i, d) in data.enumerated() {
                let px = r.minX + CGFloat(i) / CGFloat(data.count - 1) * r.width
                let py = r.maxY - CGFloat((d - lo) / (hi - lo)) * (r.height - 8) - 4
                if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        Theme.text(!app.st.metrics.isEmpty ? app.st.selected.name : "", Theme.uiXS, Theme.textFade,
                   CGRect(x: r.minX, y: r.minY + 3, width: r.width - 8, height: 16), .right)

        // 底部指标
        y += chartH + 10
        small(12, y, halfW, "内存", String(format: "%.1f%%", mem))
        let thermStr: String
        switch s.thermal {
        case 0: thermStr = "正常"
        case 1: thermStr = "温热"
        case 2: thermStr = "较高"
        case 3: thermStr = "过热"
        default: thermStr = "--"
        }
        small(12 + halfW, y, halfW, "热压力", thermStr)

        y += 22
        let eco = app.st.economy
        let total = (eco.total >= 0 ? "+" : "") + fmtThousands(eco.total, decimals: 0)
        Theme.text("营收", Theme.uiXS, Theme.textDim, CGRect(x: 12, y: y, width: 34, height: 18))
        Theme.text("¥ " + total, Theme.numS, eco.total >= 0 ? Theme.up : Theme.down,
                   CGRect(x: 46, y: y - 2, width: 150, height: 20))
        Theme.text(eco.enabled ? String(format: "%+.1f 元/秒", eco.rate) : "已关闭", Theme.uiXS,
                   eco.enabled ? Theme.textFade : Theme.textDim,
                   CGRect(x: w - 120, y: y, width: 108, height: 18), .right)
    }

    private func big(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ label: String, _ value: String, _ sub: String, _ accent: NSColor) {
        Theme.text(label, Theme.uiXS, Theme.textDim, CGRect(x: x, y: y, width: w, height: 16))
        Theme.text(value, Theme.numL, accent, CGRect(x: x, y: y + 14, width: w, height: 28))
        if !sub.isEmpty {
            Theme.textEllipsis(sub, Theme.uiXS, Theme.textFade, CGRect(x: x, y: y + 40, width: w, height: 14))
        }
    }

    private func small(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ label: String, _ value: String) {
        Theme.text(label, Theme.uiXS, Theme.textDim, CGRect(x: x, y: y, width: 34, height: 18))
        Theme.text(value, Theme.uiS, Theme.txt, CGRect(x: x + 36, y: y, width: w - 36, height: 18))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) {
            app.toggleGadget()
            return
        }
        if pinRect.contains(p) {
            let win = window as? GadgetWindow
            let newPin = win?.level != .floating
            win?.updatePinned(newPin)
            return
        }
        if event.clickCount == 2 {
            app.restoreFromTray()
            return
        }
        isDragging = true
        dragStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let win = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        let origin = win.frame.origin
        win.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        dragStart = current
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if let win = window {
            app.settings.gadgetX = Double(win.frame.origin.x)
            app.settings.gadgetY = Double(win.frame.origin.y)
            app.settings.save()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开主面板", action: #selector(openMain), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let topItem = NSMenuItem(title: "总在最前", action: #selector(toggleTop), keyEquivalent: "")
        topItem.state = window?.level == .floating ? .on : .off
        menu.addItem(topItem)
        menu.addItem(NSMenuItem(title: "关闭挂件", action: #selector(closeGadget), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openMain() { app.restoreFromTray() }
    @objc private func toggleTop() {
        let win = window as? GadgetWindow
        win?.updatePinned(win?.level != .floating)
    }
    @objc private func closeGadget() { app.toggleGadget() }
}

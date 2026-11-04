import AppKit

class Panel {
    var bounds = CGRect.zero
    unowned var f: AppController
    var st: AppState { f.st }
    init(_ f: AppController) { self.f = f }

    func paint() {}
    func mouseMove(_ p: CGPoint) {}
    func mouseLeave() {}
    func click(_ p: CGPoint) -> Bool { false }
    func rightClick(_ p: CGPoint) {}
    func advance() -> Bool { false }
    func wheel(_ p: CGPoint, _ dy: CGFloat) {}
    func doubleClick(_ p: CGPoint) {}
    func cursor(at p: CGPoint) -> NSCursor { .arrow }

    var w: CGFloat { bounds.width }
    var h: CGFloat { bounds.height }
    func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY) }
    func invalidate() { f.view.setNeedsDisplay(bounds) }

    func draw() {
        let ctx = Theme.cg
        ctx.saveGState()
        ctx.translateBy(x: bounds.minX, y: bounds.minY)
        ctx.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        paint()
        ctx.restoreGState()
    }

    func chip(_ r: CGRect, _ text: String, active: Bool, hover: Bool, accent: NSColor, font: NSFont = Theme.uiS) {
        let fill = active ? accent.a(38.0 / 255) : hover ? Theme.panelSoft : Theme.chipBg
        let border = active ? accent.a(150.0 / 255) : Theme.line2
        Theme.roundedRect(r, 3.5, fill: fill, stroke: border)
        Theme.text(text, font, active ? accent : hover ? Theme.textHi : Theme.textDim, r, .center)
    }

    /// 带头部（金色竖条 + 标题）的面板通用头。
    func header(_ title: String, sub: String, subX: CGFloat, right: String, bar: NSColor? = nil, h hh: CGFloat = 30) {
        let head = CGRect(x: 0, y: 0, width: w, height: hh)
        Theme.vGrad(head, Theme.headTop, Theme.headBot)
        Theme.hLine(0, w, hh - 1, Theme.line2)
        Theme.fill(CGRect(x: 0, y: 0, width: 2.5, height: hh), bar ?? Theme.gold)
        Theme.text(title, Theme.uiL, Theme.textHi, CGRect(x: 12, y: 0, width: 100, height: hh))
        Theme.text(sub, Theme.brandSub, Theme.textFade, CGRect(x: subX, y: 0, width: 120, height: hh))
        Theme.text(right, Theme.uiXS, Theme.textDim, CGRect(x: w - 70, y: 0, width: 58, height: hh), .right)
    }
}

// MARK: - 标题栏
final class TitleBarPanel: Panel {
    var chipPause = CGRect.zero, chipTop = CGRect.zero, chipColor = CGRect.zero, chipEco = CGRect.zero
    var chipGadget = CGRect.zero, pill = CGRect.zero, gear = CGRect.zero, clock = CGRect.zero
    var segs = [CGRect](repeating: .zero, count: 5)
    let segLabels = ["0.5s", "1s", "2s", "5s", "10s"]
    let segValues = [500, 1000, 2000, 5000, 10000]
    private var hover = -1, hoverSeg = -1
    static let leftInset: CGFloat = 76   // 给红绿灯按钮让位

    func layout() {
        let L = TitleBarPanel.leftInset
        clock = CGRect(x: w - 16 - 104, y: 0, width: 104, height: h)
        var x = w - 16 - 116
        chipColor = CGRect(x: x - 58, y: 10, width: 58, height: 23); x -= 66
        chipTop = CGRect(x: x - 50, y: 10, width: 50, height: 23); x -= 58
        chipGadget = CGRect(x: x - 56, y: 10, width: 56, height: 23); x -= 64
        chipPause = CGRect(x: x - 62, y: 10, width: 62, height: 23); x -= 70
        chipEco = CGRect(x: x - 52, y: 10, width: 52, height: 23); x -= 60
        for i in stride(from: segs.count - 1, through: 0, by: -1) {
            segs[i] = CGRect(x: x - 44 * CGFloat(segs.count - i), y: 10, width: 42, height: 23)
        }
        pill = CGRect(x: L + 236 - 14 + 40, y: 11, width: 132, height: 21)
        gear = CGRect(x: L + 150 - 14 + 40, y: 8, width: 26, height: 26)
    }

    override func paint() {
        layout()
        let L = TitleBarPanel.leftInset
        Theme.vGrad(CGRect(x: 0, y: 0, width: w, height: h), Theme.titleTop, Theme.titleBot)
        Theme.hLine(0, w, h - 1, Theme.line2)
        Theme.gradient(CGRect(x: 0, y: 0, width: w, height: 1),
                       [(Theme.gold.a(0), 0), (Theme.gold.a(120.0 / 255), 0.45), (Theme.gold.a(0), 1)], vertical: false)

        // 品牌
        let logo = CGRect(x: L, y: 9, width: 24, height: 24)
        let path = CGPath(roundedRect: logo, cornerWidth: 6, cornerHeight: 6, transform: nil)
        let ctx = Theme.cg
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        Theme.gradient(logo, [(rgb(0xFF, 0xD9, 0x8A), 0), (rgb(0xD9, 0x9C, 0x1E), 1)], vertical: true)
        ctx.restoreGState()
        let ink = rgb(0x14, 0x18, 0x22)
        Theme.fill(CGRect(x: logo.minX + 6, y: logo.minY + 11, width: 3, height: 9), ink)
        Theme.fill(CGRect(x: logo.minX + 11, y: logo.minY + 6, width: 3, height: 14), ink)
        Theme.fill(CGRect(x: logo.minX + 16, y: logo.minY + 9, width: 3, height: 8), ink)

        Theme.text("性能行情终端", Theme.brandFont, Theme.textHi, CGRect(x: L + 32, y: 5, width: 200, height: 19))
        Theme.text("PERF · TERMINAL", Theme.brandSub, Theme.goldDim, CGRect(x: L + 33, y: 22, width: 200, height: 14))

        // 设置齿轮
        let setOn = f.settingsOpen
        if setOn || hover == 7 { Theme.roundedFill(gear, 4, setOn ? Theme.gold.a(46.0 / 255) : Theme.rowHover) }
        do {
            let gx = gear.midX, gy = gear.midY
            let rOut: CGFloat = 8, rIn: CGFloat = 4.6
            let col = setOn ? Theme.gold : hover == 7 ? Theme.textHi : Theme.textDim
            ctx.setStrokeColor(col.cgColor); ctx.setLineWidth(1.3)
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + 0.26
                ctx.move(to: CGPoint(x: gx + cos(a) * rIn, y: gy + sin(a) * rIn))
                ctx.addLine(to: CGPoint(x: gx + cos(a) * rOut, y: gy + sin(a) * rOut))
            }
            ctx.strokePath()
            ctx.strokeEllipse(in: CGRect(x: gx - rIn, y: gy - rIn, width: rIn * 2, height: rIn * 2))
        }
        Theme.vLine(gear.maxX + 14, 11, h - 11, Theme.line2)

        // 状态胶囊
        let live = !st.paused
        let dotC = live ? Theme.down : Theme.warn
        Theme.roundedRect(pill, pill.height / 2, fill: dotC.a(24.0 / 255), stroke: dotC.a(80.0 / 255))
        let pulse = (sin(st.frame * 3.2) + 1) / 2
        let dotR: CGFloat = 5
        let dotX = pill.minX + 10, dotY = pill.minY + (pill.height - dotR) / 2
        if live { Theme.ellipse(CGRect(x: dotX - 3, y: dotY - 3, width: dotR + 6, height: dotR + 6), dotC.a(CGFloat(40 + 60 * (1 - pulse)) / 255)) }
        Theme.ellipse(CGRect(x: dotX, y: dotY, width: dotR, height: dotR), dotC)
        let pillTxt = live ? String(format: "实时采样 %.1fs", Double(st.intervalMs) / 1000) : "行情已暂停"
        Theme.text(pillTxt, Theme.uiXS, live ? rgb(0x7E, 0xE0, 0xC0) : Theme.warn,
                   CGRect(x: dotX + 10, y: pill.minY, width: pill.width - 20, height: pill.height))

        // 采样周期分段器
        Theme.text("周期", Theme.uiXS, Theme.textFade, CGRect(x: segs[0].minX - 42, y: segs[0].minY, width: 36, height: segs[0].height), .right)
        let segBox = CGRect(x: segs[0].minX - 2, y: segs[0].minY, width: segs[4].maxX - segs[0].minX + 4, height: segs[0].height)
        Theme.roundedRect(segBox, 3.5, fill: Theme.chipBg, stroke: Theme.line2)
        for i in 0..<segs.count {
            let act = st.intervalMs == segValues[i]
            if act { Theme.roundedFill(segs[i], 3, rgb(0xF2, 0xC1, 0x4E, 30.0 / 255)) }
            Theme.text(segLabels[i], Theme.numXXS, act ? Theme.gold : hoverSeg == i ? Theme.textHi : Theme.textDim, segs[i], .center)
        }

        // 功能 chips
        chip(chipPause, st.paused ? "继续" : "暂停", active: st.paused, hover: hover == 3, accent: Theme.gold)
        chip(chipTop, "置顶", active: st.topMost, hover: hover == 4, accent: Theme.blue)
        chip(chipGadget, "挂件", active: f.gadgetOn, hover: hover == 8, accent: Theme.cyan)
        chip(chipColor, st.redUp ? "红涨" : "绿涨", active: true, hover: hover == 5, accent: st.redUp ? Theme.up : Theme.down)
        chip(chipEco, "营收", active: st.economy.enabled, hover: hover == 6, accent: Theme.gold)

        // 时钟
        let now = Date()
        Theme.text(Fmt.hms.string(from: now), Theme.numXL, Theme.goldSoft, CGRect(x: clock.minX, y: 2, width: clock.width, height: 20), .right)
        Theme.text(Fmt.dateCn.string(from: now), Theme.uiXS, Theme.textFade, CGRect(x: clock.minX, y: 21, width: clock.width, height: 14), .right)
    }

    private func hit(_ l: CGPoint) -> (Int, Int) {
        var hv = -1, sg = -1
        if chipPause.contains(l) { hv = 3 } else if chipTop.contains(l) { hv = 4 }
        else if chipColor.contains(l) { hv = 5 } else if chipEco.contains(l) { hv = 6 }
        else if gear.contains(l) { hv = 7 } else if chipGadget.contains(l) { hv = 8 }
        else { for i in 0..<segs.count where segs[i].contains(l) { sg = i } }
        return (hv, sg)
    }

    override func mouseMove(_ p: CGPoint) {
        let (hv, sg) = hit(local(p))
        if hv != hover || sg != hoverSeg { hover = hv; hoverSeg = sg; invalidate() }
    }
    override func mouseLeave() { if hover != -1 || hoverSeg != -1 { hover = -1; hoverSeg = -1; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { hover >= 0 || hoverSeg >= 0 ? .pointingHand : .arrow }

    /// 该点是否落在控件上（否则标题栏可作为拖拽区域）。
    func isInteractive(_ p: CGPoint) -> Bool { let (a, b) = hit(local(p)); return a >= 0 || b >= 0 }

    override func click(_ p: CGPoint) -> Bool {
        let l = local(p)
        if chipPause.contains(l) { f.togglePause(); return true }
        if chipTop.contains(l) { f.toggleTopMost(); return true }
        if chipColor.contains(l) { f.toggleColor(); return true }
        if chipEco.contains(l) { f.toggleEconomy(); return true }
        if gear.contains(l) { f.toggleSettings(); return true }
        if chipGadget.contains(l) { f.toggleGadget(); return true }
        for i in 0..<segs.count where segs[i].contains(l) { f.setInterval(segValues[i]); return true }
        return false
    }
}

// MARK: - 指数条
final class IndexStripPanel: Panel {
    static let codes = ["000001", "000002", "600521", "600522", "000003", "000304", "600036", "000301"]
    private var hover = -1

    private func cell(_ i: Int) -> CGRect {
        let cw = w / CGFloat(Self.codes.count)
        return CGRect(x: cw * CGFloat(i), y: 0, width: cw, height: h)
    }

    override func paint() {
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.titleBot)
        Theme.hLine(0, w, h - 1, Theme.line)
        for (i, code) in Self.codes.enumerated() {
            let c = cell(i)
            guard let m = st.byCode(code) else { continue }
            if i == hover { Theme.fill(c, Theme.rowHover) }
            let now = nowMs()
            if now < m.flashUntil {
                let t = Double(m.flashUntil - now) / 700
                Theme.fill(c, (m.flashDir > 0 ? Theme.up : Theme.down).a(CGFloat(13 * t) / 255))
            }
            if i > 0 { Theme.vLine(c.minX, 10, h - 10, Theme.line) }
            let col = Theme.chgColor(m.shownChg)
            Theme.miniCandles(CGRect(x: c.maxX - 80, y: c.minY + 14, width: 66, height: 32), m.spark(48), bars: 14)
            Theme.textEllipsis(m.name, Theme.uiXS, Theme.textDim, CGRect(x: c.minX + 14, y: c.minY + 6, width: c.width - 28, height: 14))
            Theme.text(m.shownText, Theme.numL, col, CGRect(x: c.minX + 14, y: c.minY + 21, width: 120, height: 22))
            let vw = Theme.measure(m.shownText, Theme.numL)
            Theme.text(m.unit, Theme.uiXS, Theme.textFade, CGRect(x: c.minX + 16 + vw, y: c.minY + 24, width: 44, height: 16))
            Theme.text(m.shownChgText, Theme.numXXS, col, CGRect(x: c.minX + 14, y: c.minY + 43, width: 90, height: 13))
        }
    }

    private func at(_ p: CGPoint) -> Int {
        let l = local(p)
        for i in 0..<Self.codes.count where cell(i).contains(l) { return i }
        return -1
    }
    override func mouseMove(_ p: CGPoint) { let i = at(p); if i != hover { hover = i; invalidate() } }
    override func mouseLeave() { if hover != -1 { hover = -1; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { hover >= 0 ? .pointingHand : .arrow }
    override func click(_ p: CGPoint) -> Bool {
        let i = at(p)
        if i < 0 { return false }
        f.selectMetric(Self.codes[i])
        return true
    }
}

// MARK: - 自选行情
final class WatchPanel: Panel {
    private let headerH: CGFloat = 30, colH: CGFloat = 21, groupH: CGFloat = 23, rowH: CGFloat = 24
    private var hoverRow = -1

    private func groups() -> [(String, [Metric])] {
        Catalog.groupOrder.compactMap { g in
            let items = st.metrics.filter { $0.group == g }
            return items.isEmpty ? nil : (g, items)
        }
    }
    private func contentHeight() -> CGFloat {
        groups().reduce(headerH + colH) { $0 + groupH + CGFloat($1.1.count) * rowH }
    }

    override func paint() {
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.panel)
        Theme.vLine(w - 1, 0, h, Theme.line2)
        header("自选行情", sub: "WATCHLIST", subX: 82, right: "\(st.metrics.count) 项")
        let ch = CGRect(x: 0, y: headerH, width: w, height: colH)
        Theme.fill(ch, Theme.headBot2)
        Theme.text("代码 / 名称", Theme.uiXS, Theme.textFade, CGRect(x: 12, y: ch.minY, width: 150, height: colH))
        Theme.text("走势", Theme.uiXS, Theme.textFade, CGRect(x: w - 170, y: ch.minY, width: 38, height: colH))
        Theme.text("现价", Theme.uiXS, Theme.textFade, CGRect(x: w - 116, y: ch.minY, width: 42, height: colH), .right)
        Theme.text("涨跌", Theme.uiXS, Theme.textFade, CGRect(x: w - 58, y: ch.minY, width: 48, height: colH), .right)

        let contentTop = headerH + colH
        let ctx = Theme.cg
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: contentTop, width: w, height: h - contentTop))
        var y = contentTop - st.watchScroll
        for (g, items) in groups() {
            let gh = CGRect(x: 0, y: y, width: w, height: groupH)
            if gh.maxY > contentTop && gh.minY < h {
                Theme.fill(gh, Theme.stripe2)
                Theme.hLine(0, w, gh.maxY - 1, Theme.line)
                Theme.fill(CGRect(x: 8, y: y + groupH / 2 - 3, width: 2, height: 6), Theme.goldDim)
                Theme.text(g, Theme.uiXS, Theme.txtHi2, CGRect(x: 16, y: gh.minY, width: 100, height: groupH))
                Theme.text("\(items.count)", Theme.numXXS, Theme.textFade, CGRect(x: w - 30, y: gh.minY, width: 18, height: groupH), .right)
            }
            y += groupH
            for m in items {
                let rr = CGRect(x: 0, y: y, width: w, height: rowH)
                if rr.maxY > contentTop && rr.minY < h {
                    let idx = st.metrics.firstIndex { $0 === m } ?? -1
                    if idx == st.selectedIndex {
                        Theme.fill(rr, Theme.rowSel)
                        Theme.fill(CGRect(x: 0, y: y, width: 2.5, height: rowH), Theme.gold)
                    } else if idx == hoverRow { Theme.fill(rr, Theme.rowHover) }
                    paintRow(rr, m, idx == st.selectedIndex)
                }
                y += rowH
            }
        }
        ctx.restoreGState()

        let viewH = h - contentTop, contentH = contentHeight() - contentTop
        if contentH > viewH {
            let thumbH = max(24, viewH * viewH / contentH)
            let t = st.watchScroll / (contentH - viewH)
            Theme.roundedFill(CGRect(x: w - 4, y: contentTop + t * (viewH - thumbH), width: 3, height: thumbH), 1.5, Theme.line2)
        }
    }

    private func paintRow(_ rr: CGRect, _ m: Metric, _ selected: Bool) {
        let now = nowMs()
        if now < m.flashUntil {
            let t = Double(m.flashUntil - now) / 700
            Theme.fill(rr, (m.flashDir > 0 ? Theme.up : Theme.down).a(CGFloat(18 * t) / 255))
        }
        Theme.text(m.code, Theme.mockMono, Theme.textFade, CGRect(x: rr.minX + 10, y: rr.minY, width: 48, height: rr.height))
        Theme.textEllipsis(m.name, selected ? Theme.uiM : Theme.uiS, selected ? Theme.textHi : Theme.txtHi2,
                           CGRect(x: rr.minX + 62, y: rr.minY, width: 96, height: rr.height))
        Theme.miniCandles(CGRect(x: w - 168, y: rr.minY + 5, width: 46, height: 14), m.spark(28), bars: 8)
        let col = Theme.chgColor(m.shownChg)
        Theme.text(m.shownText, Theme.numS, col, CGRect(x: w - 120, y: rr.minY, width: 46, height: rr.height), .right)
        let badge = CGRect(x: w - 62, y: rr.minY + 5, width: 54, height: 14)
        if abs(m.chgPct) > 0.001 { Theme.roundedFill(badge, 2, col.a(26.0 / 255)) }
        Theme.text(m.shownChgText, Theme.numXXS, col, badge, .center)
    }

    private func rowAt(_ l: CGPoint) -> Int {
        guard l.y >= headerH + colH else { return -1 }
        var y = headerH + colH - st.watchScroll
        for (_, items) in groups() {
            y += groupH
            for m in items {
                if CGRect(x: 0, y: y, width: w, height: rowH).contains(l) { return st.metrics.firstIndex { $0 === m } ?? -1 }
                y += rowH
            }
        }
        return -1
    }

    override func mouseMove(_ p: CGPoint) { let i = rowAt(local(p)); if i != hoverRow { hoverRow = i; invalidate() } }
    override func mouseLeave() { if hoverRow != -1 { hoverRow = -1; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { hoverRow >= 0 ? .pointingHand : .arrow }
    override func click(_ p: CGPoint) -> Bool {
        let i = rowAt(local(p))
        if i < 0 { return false }
        st.selectedIndex = i
        f.onMetricChanged()
        return true
    }
    override func wheel(_ p: CGPoint, _ dy: CGFloat) {
        let viewH = h - (headerH + colH)
        let mx = max(0, contentHeight() - (headerH + colH) - viewH)
        st.watchScroll = min(max(0, st.watchScroll - dy), mx)
        invalidate()
    }
}

// MARK: - 品种信息条
final class InstrumentPanel: Panel {
    var tabs = [CGRect](repeating: .zero, count: 5)
    let tabLabels = ["2秒K", "5秒K", "10秒K", "30秒K", "1分K"]
    let tabPeriods: [Int64] = [2000, 5000, 10000, 30000, 60000]
    private var hover = -1

    override func paint() {
        let m = st.selected
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.headBot2)
        Theme.text(m.name, Theme.uiXL, Theme.textHi, CGRect(x: 14, y: 9, width: 260, height: 22))
        let nw = Theme.measure(m.name, Theme.uiXL)
        Theme.text(m.code, Theme.mockMono, Theme.goldDim, CGRect(x: 20 + nw, y: 9, width: 70, height: 22))
        let tag = m.group == "指数" ? "大盘" : m.group
        let tagR = CGRect(x: 24 + nw + 44, y: 12, width: 38, height: 16)
        Theme.roundedRect(tagR, 2, fill: rgb(0xF2, 0xC1, 0x4E, 24.0 / 255), stroke: rgb(0xF2, 0xC1, 0x4E, 70.0 / 255))
        Theme.text(tag, Theme.uiXS, Theme.gold, tagR, .center)

        let tw: CGFloat = 64, gap: CGFloat = 5
        let tx = w - (5 * tw + 4 * gap) - 14
        for i in 0..<5 {
            tabs[i] = CGRect(x: tx + CGFloat(i) * (tw + gap), y: 10, width: tw, height: 23)
            let enabled = tabPeriods[i] >= Int64(st.intervalMs) * 2
            let act = st.periodMs == tabPeriods[i]
            let fill = act ? rgb(0xF2, 0xC1, 0x4E, 36.0 / 255) : hover == i ? Theme.panelSoft : Theme.chipBg
            Theme.roundedRect(tabs[i], 3, fill: fill, stroke: act ? rgb(0xF2, 0xC1, 0x4E, 140.0 / 255) : Theme.line2)
            Theme.text(tabLabels[i], Theme.uiXS, act ? Theme.gold : !enabled ? Theme.textFade : hover == i ? Theme.textHi : Theme.textDim, tabs[i], .center)
        }

        let col = Theme.chgColor(m.shownChg)
        Theme.text(m.shownText, Theme.numHuge, col, CGRect(x: 14, y: 32, width: 220, height: 36))
        let bw2 = Theme.measure(m.shownText, Theme.numHuge)
        Theme.text(m.unit, Theme.uiS, Theme.textDim, CGRect(x: 20 + bw2, y: 46, width: 60, height: 18))

        let sign = m.shownChg >= 0 ? "+" : "-"
        let chgTxt = sign + m.fmt(abs(m.shownChg)) + (m.unit == "%" ? "pt" : "")
        let pctTxt = sign + String(format: "%.2f", abs(m.chgPct)) + "%"
        let cx2 = 20 + bw2 + 70
        Theme.text(chgTxt, Theme.numS, col, CGRect(x: cx2, y: 38, width: 120, height: 16))
        if m.unit != "%" {
            let pb = CGRect(x: cx2 + 76, y: 54, width: 76, height: 16)
            Theme.roundedFill(pb, 2, col.a(38.0 / 255))
            Theme.text(pctTxt, Theme.numXS, col, pb, .center)
        }

        let amp = m.open != 0 ? (m.high - m.low) / abs(m.open) * 100 : 0
        let stats = [("今开", m.fmt(m.open)), ("最高", m.fmt(m.high)), ("最低", m.fmt(m.low)),
                     ("均价", m.fmt(m.count > 0 ? m.sum / Double(m.count) : 0)), ("振幅", String(format: "%.2f%%", amp))]
        var sx: CGFloat = 14
        for (label, val) in stats {
            Theme.text(label, Theme.uiXS, Theme.textFade, CGRect(x: sx, y: 74, width: 34, height: 16))
            Theme.text(val, Theme.numXS, Theme.txt, CGRect(x: sx + 30, y: 74, width: 72, height: 16))
            sx += 104
        }
        Theme.hLine(0, w, h - 1, Theme.line2)
    }

    override func mouseMove(_ p: CGPoint) {
        let l = local(p)
        var hh = -1
        for i in 0..<5 where tabs[i].contains(l) { hh = i }
        if hh != hover { hover = hh; invalidate() }
    }
    override func mouseLeave() { if hover != -1 { hover = -1; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { hover >= 0 ? .pointingHand : .arrow }
    override func click(_ p: CGPoint) -> Bool {
        let l = local(p)
        for i in 0..<5 where tabs[i].contains(l) { f.setChartMode(tabPeriods[i]); return true }
        return false
    }
}

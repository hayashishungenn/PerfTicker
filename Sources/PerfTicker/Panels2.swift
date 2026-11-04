import AppKit

// MARK: - 主力动向
final class BookPanel: Panel {
    private let headerH: CGFloat = 30, rowH: CGFloat = 26
    private var rowCount: Int { max(4, min(10, Int((h - headerH - 26) / rowH))) }
    private var hover = -1
    private var rank: [ProcSample] = []

    private var isGpu: Bool { st.selected.group == "图形" }
    private var isMem: Bool { let n = st.selected.name; return n.contains("内存") || n.contains("交换") || n.contains("压缩") }
    private var title: String { isGpu ? "GPU 持仓" : isMem ? "内存持仓" : st.selected.name.contains("磁盘") ? "磁盘持仓" : "CPU 持仓" }

    private func buildRank() {
        let n = rowCount
        let procs = st.procs
        if isGpu { rank = Array(procs.filter { $0.gpuPct > 0.05 }.sorted { $0.gpuPct > $1.gpuPct }.prefix(n)) }
        else if isMem { rank = Array(procs.sorted { $0.memMB > $1.memMB }.prefix(n)) }
        else { rank = Array(procs.sorted { $0.cpuPct > $1.cpuPct }.prefix(n)) }
    }
    private func val(_ p: ProcSample) -> Double { isGpu ? p.gpuPct : isMem ? p.memMB : p.cpuPct }
    private func fmtVal(_ p: ProcSample) -> String {
        if isGpu { return String(format: "%.1f%%", p.gpuPct) }
        if isMem { return p.memMB >= 1024 ? String(format: "%.2fG", p.memMB / 1024) : String(format: "%.0fM", p.memMB) }
        return String(format: "%.1f%%", p.cpuPct)
    }

    override func paint() {
        buildRank()
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.panel)
        header("主力动向", sub: title, subX: 78, right: "TOP \(rowCount)")
        var y = headerH
        let mx = max(1e-9, rank.map(val).max() ?? 1e-9)
        for i in 0..<rowCount {
            let rr = CGRect(x: 0, y: y, width: w, height: rowH)
            if i < rank.count {
                let p = rank[i]
                let frac = min(1, max(0, val(p) / mx))
                if frac > 0.01 {
                    let bw = max(2, (rr.width - 20) * CGFloat(frac))
                    Theme.fill(CGRect(x: rr.maxX - 10 - bw, y: rr.minY + 2, width: bw, height: rr.height - 4), Theme.up.a(CGFloat(6 + 26 * frac) / 255))
                }
                if i == hover { Theme.fill(rr, Theme.rowHover) }
                let badge = CGRect(x: 10, y: y + (rowH - 15) / 2, width: 15, height: 15)
                let top = i == 0
                Theme.roundedRect(badge, 2.5, fill: top ? rgb(0xF2, 0xC1, 0x4E, 0xE8 / 255.0) : Theme.panelSoft, stroke: top ? Theme.gold : Theme.line2)
                Theme.text("\(i + 1)", Theme.numXXS, top ? Theme.darkInk : Theme.textDim, badge, .center)
                Theme.textEllipsis(p.name, Theme.uiS, Theme.txtHi2, CGRect(x: 32, y: y, width: w - 32 - 74, height: rowH))
                Theme.text(fmtVal(p), Theme.numXS, Theme.up, CGRect(x: rr.maxX - 72, y: y, width: 62, height: rowH), .right)
            } else {
                Theme.text("—", Theme.uiXS, Theme.textFade, CGRect(x: rr.maxX - 72, y: y, width: 62, height: rowH), .right)
            }
            if i < rowCount - 1 { Theme.hLine(10, w - 10, rr.maxY, Theme.line) }
            y += rowH
        }
        let sumR = CGRect(x: 0, y: y, width: w, height: rowH + 4)
        Theme.fill(sumR, Theme.stripe)
        Theme.hLine(0, w, sumR.minY, Theme.line)
        let sum = rank.reduce(0) { $0 + val($1) }
        Theme.text("合计", Theme.uiXS, Theme.textDim, CGRect(x: 12, y: sumR.minY, width: 40, height: sumR.height))
        Theme.text(fmtD(sum, 1) + (isMem ? "M" : "%"), Theme.numXS, Theme.gold, CGRect(x: 46, y: sumR.minY, width: 120, height: sumR.height))
        Theme.text("\(st.procs.count) 只", Theme.uiXS, Theme.textFade, CGRect(x: w - 70, y: sumR.minY, width: 58, height: sumR.height), .right)
    }

    override func mouseMove(_ p: CGPoint) {
        let l = local(p)
        var hh = -1
        for i in 0..<rowCount where CGRect(x: 0, y: headerH + CGFloat(i) * rowH, width: w, height: rowH).contains(l) { hh = i }
        if hh != hover { hover = hh; invalidate() }
    }
    override func mouseLeave() { if hover != -1 { hover = -1; invalidate() } }
}

// MARK: - 逐笔成交
final class TapePanel: Panel {
    private let headerH: CGFloat = 30, rowH: CGFloat = 18.5

    override func paint() {
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.panel)
        header("逐笔成交", sub: "LIVE TAPE", subX: 78, right: "\(st.tape.count)", bar: rgb(0x4D, 0x8D, 0xFF))
        var y = headerH + 4
        let maxRows = Int((h - headerH - 8) / rowH)
        let n = min(maxRows, st.tape.count)
        for i in 0..<n {
            let e = st.tape[st.tape.count - 1 - i]
            Theme.text(e.time, Theme.mockMono, Theme.textFade, CGRect(x: 12, y: y, width: 56, height: rowH))
            Theme.ellipse(CGRect(x: 70, y: y + 7, width: 4, height: 4), e.color)
            Theme.textEllipsis(e.text, Theme.uiXS, Theme.txtHi2, CGRect(x: 80, y: y, width: w - 92, height: rowH))
            y += rowH
        }
        if st.tape.isEmpty { Theme.text("等待行情接入…", Theme.uiS, Theme.textFade, CGRect(x: 0, y: headerH, width: w, height: 40), .center) }
    }
}

// MARK: - 底部状态条 + 跑马灯
final class FooterPanel: Panel {
    private var segs: [(String, NSColor, CGFloat)] = []
    private var segsTick: Int64 = -1
    var aboutRect = CGRect.zero
    private var aboutHover = false

    private func stats() -> [(String, String, NSColor)] {
        let s = st.snap
        let up = Int((nowMs() - st.startMs) / 1000)
        return [
            ("采样", st.paused ? "已暂停" : String(format: "%.1fs", Double(st.intervalMs) / 1000), st.paused ? Theme.warn : Theme.down),
            ("运行", String(format: "%02d:%02d:%02d", up / 3600, up % 3600 / 60, up % 60), Theme.txt),
            ("进程", "\(s.procCount)", Theme.txt), ("线程", "\(s.threads)", Theme.txt),
            ("句柄", s.handles >= 100000 ? "\(s.handles / 1000)K" : "\(s.handles)", Theme.txt),
        ]
    }

    private func buildSegments() {
        segs.removeAll()
        func add(_ t: String, _ c: NSColor) { segs.append((t, c, Theme.measure(t, Theme.uiXS))) }
        for m in st.metrics where m.group != "处理器" {
            add(m.name + " ", Theme.textDim)
            let col = Theme.chgColor(m.chg)
            add(m.display, col)
            add(" " + m.unit + "  ", Theme.textFade)
            add((m.chgPct >= 0 ? "▲" : "▼") + String(format: "%.2f%%", abs(m.chgPct)), col)
            add("   ｜   ", rgb(0x3A, 0x44, 0x55))
        }
    }

    override func paint() {
        let bgTop = Theme.headTop, bgBot = Theme.chartBg2
        Theme.vGrad(CGRect(x: 0, y: 0, width: w, height: h), bgTop, bgBot)
        let items = stats()
        var x: CGFloat = 12
        for (l, v, _) in items { x += Theme.measure(l, Theme.uiXS) + 5 + Theme.measure(v, Theme.numXS) + 20 }
        let statEnd = x + 12
        let mqLeft = statEnd + 12, mqRight = w - 268

        if segsTick != st.snap.tick { buildSegments(); segsTick = st.snap.tick }
        let total = segs.reduce(0) { $0 + $1.2 }
        let ctx = Theme.cg
        if !st.marquee {
            Theme.text("滚动信息已关闭 · 设置中可重新开启", Theme.uiXS, Theme.textFade, CGRect(x: mqLeft, y: 0, width: max(0, mqRight - mqLeft), height: h))
        } else if total > 8 && mqRight - mqLeft > 60 {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: mqLeft, y: 0, width: mqRight - mqLeft, height: h))
            var sx = mqLeft - (Motion.reduce ? 0 : CGFloat(st.frame * 52).truncatingRemainder(dividingBy: total))
            var pass = 0
            while pass < 2 && sx < mqRight {
                for s in segs {
                    if sx >= mqLeft - s.2 && sx < mqRight { Theme.text(s.0, Theme.uiXS, s.1, CGRect(x: sx, y: 0, width: s.2 + 6, height: h)) }
                    sx += s.2
                }
                pass += 1
            }
            Theme.gradient(CGRect(x: mqLeft, y: 0, width: 22, height: h), [(Theme.marqueeFade.a(1), 0), (Theme.marqueeFade.a(0), 1)], vertical: false)
            Theme.gradient(CGRect(x: mqRight - 22, y: 0, width: 22, height: h), [(Theme.marqueeFade.a(0), 0), (Theme.marqueeFade.a(1), 1)], vertical: false)
            ctx.restoreGState()
        }

        x = 12
        for (l, v, c) in items {
            let lw = Theme.measure(l, Theme.uiXS)
            Theme.text(l, Theme.uiXS, Theme.textFade, CGRect(x: x, y: 0, width: lw + 4, height: h))
            x += lw + 5
            let vw = Theme.measure(v, Theme.numXS)
            Theme.text(v, Theme.numXS, c, CGRect(x: x, y: 0, width: vw + 4, height: h))
            x += vw + 20
        }
        Theme.vLine(statEnd, 8, h - 8, Theme.line2)

        aboutRect = CGRect(x: w - 58 - 12, y: 3, width: 58, height: h - 6)
        Theme.roundedRect(aboutRect, 3, fill: aboutHover ? Theme.panelSoft : Theme.chipBg, stroke: Theme.line2)
        Theme.text("关于", Theme.uiXS, aboutHover ? Theme.gold : Theme.textDim, aboutRect, .center)
        Theme.hLine(0, w, 0, Theme.line2)
    }

    override func mouseMove(_ p: CGPoint) {
        let hv = aboutRect.contains(local(p))
        if hv != aboutHover { aboutHover = hv; invalidate() }
    }
    override func mouseLeave() { if aboutHover { aboutHover = false; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { aboutRect.contains(local(p)) ? .pointingHand : .arrow }
    override func click(_ p: CGPoint) -> Bool {
        guard aboutRect.contains(local(p)) else { return false }
        f.showAbout()
        return true
    }
}

// MARK: - 个股列表（进程表）
final class ProcPanel: Panel {
    private let headerH: CGFloat = 34, colH: CGFloat = 22, rowH: CGFloat = 22
    private let sortNames = ["CPU", "GPU", "内存", "线程"]
    private var sortChips = [CGRect](repeating: .zero, count: 4)
    private var searchBox = CGRect.zero, searchClear = CGRect.zero
    private var hoverChip = -1
    private var scrollAnim: CGFloat = 0
    private let nameX: CGFloat = 92
    private var sparkW: CGFloat { max(130, min(260, w * 0.17)) }

    override func advance() -> Bool {
        let target = CGFloat(st.procScroll)
        if abs(scrollAnim - target) < 0.01 {
            if scrollAnim != target { scrollAnim = target; return true }
            return false
        }
        scrollAnim += (target - scrollAnim) * 0.38
        if abs(target - scrollAnim) < 0.02 { scrollAnim = target }
        return true
    }

    private func cols() -> (cpu: CGFloat, chg: CGFloat, gpu: CGFloat, mem: CGFloat, thr: CGFloat, hnd: CGFloat, spark: CGFloat) {
        let spark = w - 12 - sparkW
        let hnd = spark - 10 - 60
        let thr = hnd - 48 - 10
        let mem = thr - 60 - 10
        let gpu = mem - 78 - 10
        let chg = gpu - 58 - 8
        let cpu = chg - 54 - 8
        return (cpu, chg, gpu, mem, thr, hnd, spark)
    }

    private var viewCache: [ProcSample] = []
    private var viewTick: Int64 = -1
    private var viewFilter = ""
    private var viewPins = -1

    /// 排序/置顶变化后立即失效缓存，不等下一个采样 tick
    func invalidateView() { viewTick = -1 }

    func view() -> [ProcSample] {
        let tick = st.snap.tick
        if viewTick == tick && viewFilter == st.procFilter && viewPins == st.pinned.count { return viewCache }
        let fl = st.procFilter.lowercased()
        var list = st.procs.filter { fl.isEmpty || $0.name.lowercased().contains(fl) || String($0.pid).contains(fl) }
        if !st.pinned.isEmpty {
            list = list.filter { st.pinned.contains($0.name) } + list.filter { !st.pinned.contains($0.name) }
        }
        viewCache = list; viewTick = tick; viewFilter = st.procFilter; viewPins = st.pinned.count
        return list
    }

    override func paint() {
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.panel)
        let c = cols()
        let procs = view()
        let head = CGRect(x: 0, y: 0, width: w, height: headerH)
        Theme.vGrad(head, Theme.headTop, Theme.headBot)
        Theme.hLine(0, w, 0, Theme.line2)
        Theme.hLine(0, w, headerH - 1, Theme.line2)
        Theme.text("个股列表", Theme.uiL, Theme.textHi, CGRect(x: 12, y: 0, width: 80, height: headerH))
        Theme.text("进程", Theme.uiXS, Theme.goldDim, CGRect(x: 78, y: 0, width: 40, height: headerH))
        let filtering = !st.procFilter.isEmpty
        let cnt = filtering ? "筛选 \(procs.count) / \(st.procs.count)" : String(format: "%d 只 · 总内存 %.1fG", st.procs.count, st.snap.memUsedGB)
        Theme.text(cnt, Theme.uiXS, filtering ? Theme.gold : Theme.textFade, CGRect(x: 112, y: 0, width: 200, height: headerH))

        let searchX = min(328, max(240, w - 640))
        searchBox = CGRect(x: searchX, y: 7, width: 210, height: 20)
        let active = st.searchActive
        Theme.roundedRect(searchBox, 3, fill: active ? Theme.searchBg : Theme.searchBg2, stroke: active ? Theme.gold : Theme.line2)
        let ctx = Theme.cg
        let mcol = active ? Theme.gold : Theme.textFade
        ctx.setStrokeColor(mcol.cgColor); ctx.setLineWidth(1.2)
        let mx = searchBox.minX + 8, my = searchBox.minY + 10
        ctx.strokeEllipse(in: CGRect(x: mx, y: my - 3, width: 7, height: 7))
        ctx.move(to: CGPoint(x: mx + 6, y: my + 3)); ctx.addLine(to: CGPoint(x: mx + 10, y: my + 7)); ctx.strokePath()
        Theme.text(filtering ? st.procFilter : "搜索进程 / PID", Theme.uiXS, filtering ? Theme.textHi : Theme.textFade,
                   CGRect(x: searchBox.minX + 24, y: searchBox.minY, width: searchBox.width - 44, height: searchBox.height))
        if active && st.frame.truncatingRemainder(dividingBy: 1.0) < 0.55 {
            let tw = Theme.measure(st.procFilter, Theme.uiXS)
            Theme.fill(CGRect(x: searchBox.minX + 25 + tw, y: searchBox.minY + 4, width: 1, height: searchBox.height - 8), Theme.gold)
        }
        if filtering {
            searchClear = CGRect(x: searchBox.maxX - 18, y: searchBox.minY + 5, width: 12, height: 12)
            Theme.text("×", Theme.uiXS, Theme.textDim, searchClear, .center)
        } else { searchClear = .zero }

        var sx = w - 4
        for i in stride(from: 3, through: 0, by: -1) {
            sortChips[i] = CGRect(x: sx - 46, y: 7, width: 42, height: 20)
            sx -= 46
            chip(sortChips[i], sortNames[i], active: st.procSort == i, hover: hoverChip == i, accent: Theme.gold, font: Theme.uiXS)
        }
        Theme.text("排序", Theme.uiXS, Theme.textFade, CGRect(x: sx - 34, y: 0, width: 30, height: headerH), .right)

        let ch2 = CGRect(x: 0, y: headerH, width: w, height: colH)
        Theme.fill(ch2, Theme.headBot2)
        Theme.hLine(0, w, ch2.maxY - 1, Theme.line)
        let hf = Theme.uiXS, hc = Theme.textFade
        Theme.text("代码", hf, hc, CGRect(x: 12, y: ch2.minY, width: 60, height: colH))
        Theme.text("名称 / 进程", hf, hc, CGRect(x: nameX, y: ch2.minY, width: 120, height: colH))
        Theme.text("现价 CPU%", hf, hc, CGRect(x: c.cpu - 64, y: ch2.minY, width: 64, height: colH), .right)
        Theme.text("涨跌", hf, hc, CGRect(x: c.chg - 54, y: ch2.minY, width: 54, height: colH), .right)
        Theme.text("GPU%", hf, hc, CGRect(x: c.gpu - 58, y: ch2.minY, width: 58, height: colH), .right)
        Theme.text("内存", hf, hc, CGRect(x: c.mem - 78, y: ch2.minY, width: 78, height: colH), .right)
        Theme.text("线程", hf, hc, CGRect(x: c.thr - 50, y: ch2.minY, width: 50, height: colH), .right)
        Theme.text("句柄", hf, hc, CGRect(x: c.hnd - 58, y: ch2.minY, width: 58, height: colH), .right)
        Theme.text("K线走势", hf, hc, CGRect(x: c.spark, y: ch2.minY, width: sparkW, height: colH))

        let top = headerH + colH
        let rows = max(1, Int((h - top - 2) / rowH))
        let maxScroll = max(0, procs.count - rows)
        st.procScroll = min(max(0, st.procScroll), maxScroll)
        if scrollAnim > CGFloat(maxScroll) { scrollAnim = CGFloat(maxScroll) }
        var maxCpu = 1.0
        let lo = st.procScroll, hi = min(procs.count, st.procScroll + rows + 1)
        if lo < hi { for i in lo..<hi { maxCpu = max(maxCpu, procs[i].cpuPct) } }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: top, width: w, height: h - top))
        let firstRow = max(0, Int(floor(scrollAnim)) - 1)
        if firstRow < procs.count {
            for idx in firstRow..<procs.count {
                let yy = top + (CGFloat(idx) - scrollAnim) * rowH
                let rr = CGRect(x: 0, y: yy, width: w, height: rowH)
                if rr.maxY < top { continue }
                if rr.minY > h { break }
                let p = procs[idx]
                let hovered = idx == st.hoverProc && hoverChip < 0
                if idx == st.selectedProc {
                    Theme.fill(rr, Theme.rowSel)
                    Theme.fill(CGRect(x: 0, y: rr.minY, width: 2.5, height: rowH), Theme.gold)
                } else if hovered { Theme.fill(rr, Theme.rowHover) }
                else if idx % 2 == 1 { Theme.fill(rr, Theme.stripe) }
                Theme.text(String(p.pid), Theme.mockMono, Theme.textFade, CGRect(x: 12, y: rr.minY, width: 58, height: rowH))
                let pinned = st.pinned.contains(p.name)
                if pinned { Theme.text("★", Theme.uiXS, Theme.gold, CGRect(x: 74, y: rr.minY + 6, width: 10, height: 10), .center) }
                Theme.textEllipsis(p.name, Theme.uiS, pinned ? Theme.goldSoft : Theme.txtHi2,
                                   CGRect(x: nameX, y: rr.minY, width: c.cpu - 78 - nameX, height: rowH))
                let frac = min(1, max(0, p.cpuPct / maxCpu))
                if frac > 0.001 {
                    let bw = max(4, 64 * CGFloat(frac))
                    Theme.gradient(CGRect(x: c.cpu - 64, y: rr.minY + 4, width: bw, height: 14),
                                   [(Theme.up.a(30.0 / 255), 0), (Theme.up.a(1.0 / 255), 1)], vertical: false)
                }
                let cc = p.cpuPct >= 40 ? Theme.up : p.cpuPct >= 8 ? Theme.goldSoft : Theme.txt
                Theme.text(fmtD(p.cpuPct, 1), Theme.numXS, cc, CGRect(x: c.cpu - 64, y: rr.minY, width: 60, height: rowH), .right)
                let small = abs(p.cpuDelta) < 0.05
                Theme.text(small ? "—" : (p.cpuDelta >= 0 ? "+" : "") + fmtD(p.cpuDelta, 1), Theme.numXXS,
                           small ? Theme.textFade : Theme.chgColor(p.cpuDelta), CGRect(x: c.chg - 54, y: rr.minY, width: 50, height: rowH), .right)
                Theme.text(p.gpuPct > 0.05 ? fmtD(p.gpuPct, 1) : "—", Theme.numXXS, Theme.purple, CGRect(x: c.gpu - 58, y: rr.minY, width: 54, height: rowH), .right)
                let mem = p.memMB >= 1024 ? String(format: "%.2fG", p.memMB / 1024) : String(format: "%.0fM", p.memMB)
                Theme.text(mem, Theme.numXXS, Theme.textDim, CGRect(x: c.mem - 78, y: rr.minY, width: 74, height: rowH), .right)
                Theme.text("\(p.threads)", Theme.numXXS, Theme.textDim, CGRect(x: c.thr - 50, y: rr.minY, width: 46, height: rowH), .right)
                Theme.text("\(p.handles)", Theme.numXXS, Theme.textDim, CGRect(x: c.hnd - 58, y: rr.minY, width: 54, height: rowH), .right)
                if let hist = st.procHist[p.pid], hist.len > 2 {
                    Theme.miniCandles(CGRect(x: c.spark, y: rr.minY + 4, width: sparkW, height: 14), hist.snapshot(), bars: 10)
                }
            }
        }
        ctx.restoreGState()

        if procs.count > rows {
            let trackH = h - top - 2
            let thumbH = max(20, trackH * CGFloat(rows) / CGFloat(procs.count))
            let t = maxScroll == 0 ? 0 : CGFloat(st.procScroll) / CGFloat(maxScroll)
            Theme.roundedFill(CGRect(x: w - 5, y: top + t * (trackH - thumbH), width: 3, height: thumbH), 1.5, Theme.line2)
        }
    }

    private func rowAt(_ l: CGPoint) -> Int {
        let top = headerH + colH
        if l.y < top { return -1 }
        let i = Int(floor((l.y - top) / rowH + scrollAnim))
        return i >= 0 && i < view().count ? i : -1
    }

    override func mouseMove(_ p: CGPoint) {
        let l = local(p)
        let r = rowAt(l)
        var chip = -1
        for i in 0..<4 where sortChips[i].contains(l) { chip = i }
        if r != st.hoverProc || chip != hoverChip { st.hoverProc = r; hoverChip = chip; invalidate() }
    }
    override func mouseLeave() { if st.hoverProc != -1 || hoverChip != -1 { st.hoverProc = -1; hoverChip = -1; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor {
        let l = local(p)
        if searchBox.contains(l) { return .iBeam }
        for i in 0..<4 where sortChips[i].contains(l) { return .pointingHand }
        return rowAt(l) >= 0 ? .pointingHand : .arrow
    }
    override func click(_ p: CGPoint) -> Bool {
        let l = local(p)
        if searchBox.contains(l) {
            if searchClear != .zero && searchClear.contains(l) { f.setProcFilter("") } else { f.setSearchActive(true) }
            return true
        }
        for i in 0..<4 where sortChips[i].contains(l) { f.setProcSort(i); return true }
        let idx = rowAt(l)
        if idx >= 0 { st.selectedProc = idx; invalidate(); return true }
        return false
    }
    override func rightClick(_ p: CGPoint) {
        let idx = rowAt(local(p))
        let v = view()
        guard idx >= 0, idx < v.count else { return }
        st.selectedProc = idx
        invalidate()
        f.showProcMenu(pid: v[idx].pid, at: p)
    }
    override func wheel(_ p: CGPoint, _ dy: CGFloat) {
        let rows = max(1, Int((h - headerH - colH - 2) / rowH))
        let mx = max(0, view().count - rows)
        let step = Int((dy / 10).rounded(.awayFromZero))
        st.procScroll = min(max(0, st.procScroll - step), mx)
        invalidate()
    }
}

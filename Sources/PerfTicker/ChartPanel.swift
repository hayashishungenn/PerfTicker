import AppKit

/// 主图：K 线（含均线）+ 成交量 + 十字光标，带插入 / 缩放过渡动画。
final class ChartPanel: Panel {
    private var mouse = CGPoint.zero
    private var inPlot = false
    private var plot = CGRect.zero, vol = CGRect.zero
    private var slot: CGFloat = 1, x0: CGFloat = 0

    private var drawMin = 0.0, drawMax = 0.0
    private var hasScale = false
    private weak var scaleFor: Metric?
    private var slide: CGFloat = 0
    private var lastBucket: Int64 = -1
    private var lcO = 0.0, lcH = 0.0, lcL = 0.0, lcC = 0.0

    private let padL: CGFloat = 8, padR: CGFloat = 62, padT: CGFloat = 24, padB: CGFloat = 18

    private func maxBars() -> Int { max(8, Int(plot.width / max(6, min(20, plot.width / 60)))) }

    private func scaleOf(_ lo0: Double, _ hi0: Double) -> (Double, Double) {
        var lo = lo0, hi = hi0
        if hi - lo < 1e-9 { hi += abs(hi) * 0.01 + 0.5; lo -= abs(lo) * 0.01 + 0.5 }
        let pad = (hi - lo) * 0.10
        var yMax = hi + pad
        let yMin = lo - pad
        if yMax - yMin < 1e-9 { yMax = yMin + 1 }
        return (yMin, yMax)
    }

    override func advance() -> Bool {
        let m = st.selected
        let candles = m.candles
        if candles.isEmpty || plot.width <= 0 { return false }
        var dirty = false
        let bars = min(candles.count, maxBars())
        let first = candles.count - bars
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for i in first..<candles.count { lo = min(lo, candles[i].l); hi = max(hi, candles[i].h) }
        let (tMin, tMax) = scaleOf(lo, hi)
        if !hasScale || scaleFor !== m {
            drawMin = tMin; drawMax = tMax; hasScale = true; scaleFor = m
            lastBucket = -1; dirty = true
        } else {
            let dMin = tMin - drawMin, dMax = tMax - drawMax
            let span = max(1e-9, tMax - tMin)
            if abs(dMin) > span * 0.012 || abs(dMax) > span * 0.012 {
                drawMin += dMin * 0.5; drawMax += dMax * 0.5; dirty = true
            } else if abs(dMin) > 1e-9 || abs(dMax) > 1e-9 {
                drawMin = tMin; drawMax = tMax; dirty = true
            }
        }
        let last = candles[candles.count - 1]
        if lastBucket != last.bucket {
            lastBucket = last.bucket
            lcO = last.o; lcH = last.h; lcL = last.l; lcC = last.c
            slide = 1; dirty = true
        } else {
            let dh = last.h - lcH, dl = last.l - lcL, dc = last.c - lcC
            let eps = max(1e-9, (drawMax - drawMin) * 0.006)
            if abs(dh) > eps || abs(dl) > eps || abs(dc) > eps {
                lcH += dh * 0.55; lcL += dl * 0.55; lcC += dc * 0.55; dirty = true
            } else { lcH = last.h; lcL = last.l; lcC = last.c }
        }
        if slide > 0.006 { slide *= 0.62; dirty = true } else { slide = 0 }
        return dirty
    }

    private func timeText(_ bucketMs: Int64) -> String {
        let t = Date().addingTimeInterval(Double(bucketMs - nowMs()) / 1000)
        return (st.intervalMs >= 1000 ? Fmt.hms : Fmt.hmsTenth).string(from: t)
    }

    override func paint() {
        let m = st.selected
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: h), Theme.chartBg)
        let availH = h - padT - padB
        let volH = max(28, availH * 0.19)
        let gap: CGFloat = 12
        let priceH = availH - volH - gap
        plot = CGRect(x: padL, y: padT, width: w - padL - padR, height: priceH)
        vol = CGRect(x: padL, y: padT + priceH + gap, width: w - padL - padR, height: volH)
        Theme.vGrad(plot, Theme.chartBg2, Theme.chartBg3)

        let candles = m.candles
        drawWatermark()
        if candles.isEmpty {
            Theme.text("正在接收行情数据…", Theme.uiM, Theme.textFade, CGRect(x: 0, y: 0, width: w, height: h), .center)
            return
        }
        let mb = maxBars()
        let bars = min(candles.count, mb)
        let first = candles.count - bars
        slot = plot.width / CGFloat(mb)
        x0 = plot.width - CGFloat(bars) * slot + slide * slot

        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        var vols: [Double] = []
        for i in first..<candles.count { lo = min(lo, candles[i].l); hi = max(hi, candles[i].h); vols.append(candles[i].vol) }
        vols.sort()
        let maxVol = max(1, vols[min(vols.count - 1, Int(Double(vols.count) * 0.92))])
        let (rawMin, rawMax) = scaleOf(lo, hi)
        if !hasScale || scaleFor !== m { drawMin = rawMin; drawMax = rawMax; hasScale = true; scaleFor = m }
        var yMin = drawMin, yMax = drawMax
        if yMax - yMin < 1e-9 { yMin = rawMin; yMax = rawMax }
        let plotRect = plot
        func Py(_ v: Double) -> CGFloat { plotRect.maxY - CGFloat((v - yMin) / (yMax - yMin)) * plotRect.height }

        // 网格 + 右侧坐标轴
        let rows = 4
        for i in 0...rows {
            let v = yMin + (yMax - yMin) * Double(i) / Double(rows)
            let y = floor(Py(v))
            Theme.hLine(plot.minX, plot.maxX, y, (i == 0 || i == rows) ? Theme.line2 : Theme.grid)
            Theme.text(fmtD(v, m.decimals), Theme.numXXS, Theme.textFade, CGRect(x: plot.maxX + 7, y: y - 7, width: 52, height: 14))
        }
        Theme.vLine(plot.maxX + 1, plot.minY, vol.maxY, Theme.line)

        // 时间轴
        let periodMs = max(250, st.periodMs)
        let labelEvery = max(1, Int(ceil(34 / max(1, slot))))
        var i = 0
        while i < bars {
            let c = candles[first + i]
            let x = floor(plot.minX + x0 + (CGFloat(i) + 0.5) * slot)
            if i > 0 { Theme.vLine(x, plot.minY, vol.maxY, Theme.grid) }
            Theme.text(timeText(c.bucket * periodMs), Theme.numXXS, Theme.textFade, CGRect(x: x - 26, y: vol.maxY + 2, width: 52, height: 14), .center)
            i += labelEvery
        }

        drawCandles(m, candles, first, bars, Py)
        drawVolume(candles, first, bars, maxVol)
        drawLegend(m, candles)

        // 最新价参考线
        let ly = Py(lcC)
        if ly >= plot.minY - 1 && ly <= plot.maxY + 1 {
            let lc = Theme.chgColor(m.shownChg)
            Theme.dashLine(from: CGPoint(x: plot.minX, y: floor(ly) + 0.5), to: CGPoint(x: plot.maxX, y: floor(ly) + 0.5), lc.a(80.0 / 255))
            let tag = CGRect(x: plot.maxX + 3, y: ly - 7, width: 56, height: 14)
            Theme.roundedFill(tag, 2, lc)
            Theme.text(m.fmt(lcC), Theme.numXXS, rgb(0x08, 0x0A, 0x0E), tag, .center)
        }
        if inPlot && plot.insetBy(dx: -0.5, dy: -0.5).contains(mouse) {
            drawCrosshair(m, candles, first, bars, Py, yMin, yMax, periodMs)
        }
        Theme.hLine(0, w, h - 1, Theme.line)
    }

    private func drawWatermark() {
        let t = "PERF · TERMINAL"
        let tw = Theme.measure(t, Theme.numBig)
        Theme.text(t, Theme.numBig, Theme.watermark, CGRect(x: (w - tw) / 2, y: h / 2 - 26, width: tw + 4, height: 34))
    }

    private func drawLegend(_ m: Metric, _ candles: [Candle]) {
        var lx = plot.minX + 8
        let ly = plot.minY + 4
        let mas = [5, 10, 20]
        let cols = [Theme.gold, Theme.purple, Theme.cyan]
        for k in 0..<3 {
            let n = mas[k]
            var v = "—"
            if candles.count >= n {
                var s = 0.0
                for i in 0..<n { s += candles[candles.count - 1 - i].c }
                v = fmtD(s / Double(n), m.decimals)
            }
            let label = "MA\(n)"
            Theme.text(label, Theme.numXXS, cols[k], CGRect(x: lx, y: ly, width: 46, height: 13))
            lx += Theme.measure(label, Theme.numXXS) + 6
            Theme.text(v, Theme.numXXS, Theme.textDim, CGRect(x: lx, y: ly, width: 64, height: 13))
            lx += 58
        }
    }

    private func drawCandles(_ m: Metric, _ candles: [Candle], _ first: Int, _ bars: Int, _ Py: (Double) -> CGFloat) {
        let ctx = Theme.cg
        let bodyW = min(12, max(1.5, slot * 0.62))
        ctx.saveGState()
        ctx.clip(to: plot.insetBy(dx: -1, dy: 0))
        ctx.setShouldAntialias(false)
        for i in 0..<bars {
            let c = candles[first + i]
            let isLast = first + i == candles.count - 1
            let o = isLast ? lcO : c.o, h2 = isLast ? lcH : c.h, l2 = isLast ? lcL : c.l, cc = isLast ? lcC : c.c
            let cx = (plot.minX + x0 + (CGFloat(i) + 0.5) * slot).rounded()
            let up = cc >= o
            let col = (up ? Theme.up : Theme.down).cgColor
            let yh = Py(h2).rounded(), yl = Py(l2).rounded(), yo = Py(o).rounded(), yc = Py(cc).rounded()
            ctx.setFillColor(col)
            if abs(yl - yh) >= 1 { ctx.fill(CGRect(x: cx, y: yh, width: 1, height: yl - yh)) }
            let bw = max(1, bodyW.rounded())
            ctx.fill(CGRect(x: (cx - bw / 2).rounded(), y: min(yo, yc), width: bw, height: max(1, abs(yc - yo))))
        }
        ctx.setShouldAntialias(true)
        // 均线
        let conf: [(Int, NSColor)] = [(5, Theme.gold), (10, Theme.purple), (20, Theme.cyan)]
        for (n, col) in conf {
            var started = false
            ctx.setStrokeColor(col.a(210.0 / 255).cgColor)
            ctx.setLineWidth(1.1)
            ctx.setLineJoin(.round)
            for i in 0..<bars {
                let gi = first + i
                if gi < n - 1 { continue }
                var s = 0.0
                for k in 0..<n { s += candles[gi - k].c }
                let pt = CGPoint(x: plot.minX + x0 + (CGFloat(i) + 0.5) * slot, y: Py(s / Double(n)))
                if started { ctx.addLine(to: pt) } else { ctx.move(to: pt); started = true }
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
        // 今开参考线
        let oy = Py(m.open)
        if oy > plot.minY && oy < plot.maxY {
            Theme.dashLine(from: CGPoint(x: plot.minX, y: oy), to: CGPoint(x: plot.maxX, y: oy), Theme.line2, pattern: [4, 4])
            Theme.text("今开 " + m.fmt(m.open), Theme.numXXS, Theme.textFade, CGRect(x: plot.minX + 6, y: oy - 15, width: 130, height: 13))
        }
    }

    private func drawVolume(_ candles: [Candle], _ first: Int, _ bars: Int, _ maxVol: Double) {
        Theme.text("成交量", Theme.uiXS, Theme.textFade, CGRect(x: vol.minX, y: vol.minY - 13, width: 50, height: 12))
        let cur = candles[candles.count - 1].vol
        Theme.text(cur >= 1000 ? String(format: "%.1fK", cur / 1000) : String(format: "%.0f", cur),
                   Theme.numXXS, Theme.textFade, CGRect(x: vol.minX + 44, y: vol.minY - 13, width: 60, height: 12))
        Theme.hLine(vol.minX, vol.maxX, vol.maxY, Theme.line)
        let bw = min(12, max(1, slot * 0.62))
        for i in 0..<bars {
            let c = candles[first + i]
            let cx = plot.minX + x0 + (CGFloat(i) + 0.5) * slot
            let hh = max(1, CGFloat(c.vol / maxVol) * vol.height)
            Theme.fill(CGRect(x: cx - bw / 2, y: vol.maxY - min(hh, vol.height), width: bw, height: min(hh, vol.height)),
                       (c.c >= c.o ? Theme.up : Theme.down).a(140.0 / 255))
        }
    }

    private func drawCrosshair(_ m: Metric, _ candles: [Candle], _ first: Int, _ bars: Int, _ Py: (Double) -> CGFloat,
                               _ yMin: Double, _ yMax: Double, _ periodMs: Int64) {
        let idx = max(0, min(bars - 1, Int((mouse.x - plot.minX - x0) / slot)))
        let c = candles[first + idx]
        let cx = plot.minX + x0 + (CGFloat(idx) + 0.5) * slot
        let my = min(max(mouse.y, plot.minY), plot.maxY)
        let dc = rgb(0x66, 0x77, 0x88)
        Theme.dashLine(from: CGPoint(x: floor(cx) + 0.5, y: plot.minY), to: CGPoint(x: floor(cx) + 0.5, y: plot.maxY), dc)
        Theme.dashLine(from: CGPoint(x: plot.minX, y: floor(my) + 0.5), to: CGPoint(x: plot.maxX, y: floor(my) + 0.5), dc)

        let vAt = yMin + (yMax - yMin) * Double((plot.maxY - my) / plot.height)
        let pt = CGRect(x: plot.maxX + 3, y: my - 7, width: 56, height: 14)
        Theme.roundedFill(pt, 2, Theme.panelSoft)
        Theme.text(fmtD(vAt, m.decimals), Theme.numXXS, Theme.textHi, pt, .center)

        let tt = timeText(c.bucket * periodMs)
        let tw = Theme.measure(tt, Theme.numXXS)
        let tb = CGRect(x: cx - (tw + 10) / 2, y: vol.maxY + 1, width: tw + 10, height: 14)
        Theme.roundedFill(tb, 2, Theme.panelSoft)
        Theme.text(tt, Theme.numXXS, Theme.textHi, tb, .center)

        let chg = c.c - m.open
        let chgPct = m.open != 0 ? chg / abs(m.open) * 100 : 0
        let col = Theme.chgColor(chg)
        let d = m.decimals
        let lines = ["开盘  " + fmtD(c.o, d), "最高  " + fmtD(c.h, d), "最低  " + fmtD(c.l, d), "收盘  " + fmtD(c.c, d),
                     "涨跌  " + (chg >= 0 ? "+" : "") + fmtD(chg, d) + "  (" + (chgPct >= 0 ? "+" : "") + String(format: "%.2f", chgPct) + "%)"]
        let boxW: CGFloat = 158, boxH: CGFloat = 97
        var bx = cx + 16
        if bx + boxW > plot.maxX - 4 { bx = cx - boxW - 16 }
        var by = my + 10
        if by + boxH > plot.maxY { by = my - boxH - 10 }
        let box = CGRect(x: bx, y: by, width: boxW, height: boxH)
        Theme.roundedFill(box.offsetBy(dx: 2, dy: 2), 3, NSColor.black.a(80.0 / 255))
        Theme.roundedRect(box, 3, fill: Theme.chartTag, stroke: Theme.line2)
        Theme.text(tt + " · " + m.name, Theme.uiXS, Theme.textDim, CGRect(x: box.minX + 9, y: box.minY + 5, width: box.width - 14, height: 15))
        for (i, l) in lines.enumerated() {
            Theme.text(l, Theme.numXXS, i == 4 ? col : Theme.txt, CGRect(x: box.minX + 9, y: box.minY + 22 + 14 * CGFloat(i), width: box.width - 14, height: 13))
        }
    }

    override func mouseMove(_ p: CGPoint) {
        let l = local(p)
        if plot.contains(l) || vol.contains(l) { mouse = l; inPlot = true; invalidate() }
        else if inPlot { inPlot = false; invalidate() }
    }
    override func mouseLeave() { if inPlot { inPlot = false; invalidate() } }
    override func cursor(at p: CGPoint) -> NSCursor { .crosshair }
}

// MARK: - 营收专区
final class EconomyPanel: Panel {
    private var resetRect = CGRect.zero
    private var resetHover = false

    override func cursor(at p: CGPoint) -> NSCursor { resetRect.contains(local(p)) ? .pointingHand : .arrow }
    override func mouseMove(_ p: CGPoint) {
        let hv = resetRect.contains(local(p))
        if hv != resetHover { resetHover = hv; invalidate() }
    }
    override func mouseLeave() { if resetHover { resetHover = false; invalidate() } }
    override func click(_ p: CGPoint) -> Bool {
        guard resetRect.contains(local(p)) else { return false }
        f.resetEconomy()
        return true
    }

    private func signed(_ v: Double, _ fmt: String) -> String { (v >= 0 ? "+" : "") + String(format: fmt, v) }

    override func paint() {
        let eco = st.economy
        Theme.vGrad(CGRect(x: 0, y: 0, width: w, height: h), Theme.panelHi, Theme.headBot)
        Theme.hLine(0, w, 0, Theme.line2)
        Theme.hLine(0, w, h - 1, Theme.line2)
        Theme.fill(CGRect(x: 0, y: 0, width: w, height: 2), Theme.gold.a(0xB4 / 255.0))

        let cTot = eco.total >= 0 ? Theme.up : Theme.down
        Theme.text("营收中心", Theme.uiS, Theme.textHi, CGRect(x: 14, y: 8, width: 76, height: 16))
        Theme.text("REVENUE", Theme.brandSub, Theme.textFade, CGRect(x: 62, y: 9, width: 66, height: 14))
        Theme.text("¥", Theme.numS, Theme.gold, CGRect(x: 14, y: 30, width: 16, height: 20))
        Theme.textEllipsis((eco.total >= 0 ? "+" : "-") + fmtThousands(abs(eco.total), decimals: 2), Theme.numXL, cTot, CGRect(x: 26, y: 26, width: 186, height: 26))
        let cRate = eco.rate >= 0 ? Theme.up : Theme.down
        Theme.text(signed(eco.rate, "%.3f"), Theme.numS, cRate, CGRect(x: 14, y: 54, width: 92, height: 18))
        Theme.text("元/s", Theme.uiXS, Theme.textFade, CGRect(x: 88, y: 54, width: 34, height: 18))
        Theme.text("峰值 " + signed(eco.peakRate, "%.2f"), Theme.numXXS, Theme.textDim, CGRect(x: 14, y: 74, width: 106, height: 14))
        Theme.text(String(format: "%02d:%02d", Int(eco.seconds / 60), Int(eco.seconds) % 60), Theme.numXXS, Theme.textFade, CGRect(x: 120, y: 74, width: 60, height: 14))

        resetRect = CGRect(x: 166, y: 9, width: 40, height: 16)
        Theme.roundedRect(resetRect, 3, fill: resetHover ? Theme.up.a(46.0 / 255) : Theme.chipBg, stroke: resetHover ? Theme.up : Theme.line2)
        Theme.text("归零", Theme.uiXS, resetHover ? Theme.up : Theme.textDim, resetRect, .center)
        Theme.vLine(212, 10, h - 10, Theme.line2)

        let avail = w - 226
        let wide = avail >= 5 * 112 + 128
        let sparkW: CGFloat = wide ? 120 : 0
        let cellArea = avail - (wide ? sparkW + 16 : 0)
        var parts = eco.parts.count
        if !wide { parts = max(2, min(eco.parts.count, Int(cellArea / 98))) }
        let cellW = min(170, (cellArea - 6 * CGFloat(parts)) / CGFloat(max(1, parts)))
        for i in 0..<parts {
            let p = eco.parts[i]
            let x0 = 226 + CGFloat(i) * cellW
            if x0 + cellW > w - 2 { break }
            Theme.textEllipsis(p.name, Theme.uiXS, Theme.textDim, CGRect(x: x0, y: 10, width: cellW - 56, height: 14))
            Theme.text(String(format: "%.1f%%", p.loadShown), Theme.numXXS, p.loadShown >= p.breakEven ? Theme.txt : Theme.textFade,
                       CGRect(x: x0 + cellW - 60, y: 10, width: 48, height: 14), .right)
            let barBg = CGRect(x: x0, y: 28, width: cellW - 12, height: 4)
            Theme.roundedFill(barBg, 2, Theme.stripe2)
            let bw = barBg.width * CGFloat(min(1, max(0, p.loadShown / 100)))
            if bw > 1 {
                Theme.gradient(CGRect(x: barBg.minX, y: barBg.minY, width: bw, height: 4),
                               [(Theme.gold.a(0xE0 / 255.0), 0), (Theme.gold.a(0x66 / 255.0), 1)], vertical: false)
            }
            Theme.fill(CGRect(x: barBg.minX + barBg.width * CGFloat(p.breakEven / 100), y: barBg.minY - 2, width: 1, height: 8), rgb(0x70, 0x81, 0x94))
            let c = p.net >= 0 ? Theme.up : Theme.down
            Theme.text(signed(p.net, "%.3f"), Theme.numS, c, CGRect(x: x0, y: 40, width: cellW - 34, height: 18))
            Theme.text("元/s", Theme.uiXS, Theme.textFade, CGRect(x: x0 + cellW - 34, y: 40, width: 32, height: 18))
            let profit = p.loadShown >= p.breakEven
            Theme.text(profit ? "盈利" : "亏损", Theme.uiXS, profit ? Theme.up.a(0xB4 / 255.0) : Theme.down.a(0xA0 / 255.0), CGRect(x: x0, y: 64, width: 40, height: 14))
        }
        if wide {
            let sx = w - sparkW - 14
            Theme.text("净收走势", Theme.uiXS, Theme.textFade, CGRect(x: sx, y: 10, width: sparkW, height: 14))
            if eco.rateHist.count > 2 { Theme.miniCandles(CGRect(x: sx, y: 26, width: sparkW, height: h - 44), eco.rateHist, bars: 10) }
            else { Theme.text("采样中…", Theme.uiXS, Theme.textFade, CGRect(x: sx, y: 34, width: sparkW, height: 18)) }
        }
        if eco.tempPenalty < 0.999 {
            Theme.text(String(format: "热压力降效 %.0f%%", eco.tempPenalty * 100), Theme.uiXS, Theme.warn, CGRect(x: 100, y: 26, width: 110, height: 14), .right)
        }
    }
}

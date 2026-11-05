import AppKit

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

extension NSColor {
    func a(_ alpha: CGFloat) -> NSColor { withAlphaComponent(alpha) }
}

enum Align { case left, center, right }

/// 系统辅助功能偏好（由 AppController 通过 NSWorkspace KVO 更新）
enum Motion {
    static var reduce = false   // 「减弱动态效果」：停跑马灯滚动与数值缓动
}

/// 视觉系统：深/浅两套证券终端配色 + 字体阶梯 + 绘图工具。
enum Theme {
    static var dark = true
    static var hiContrast = false   // 「增强对比度」：描边加强

    static var bgDeep = NSColor.black, bg = NSColor.black, panel = NSColor.black, panelHi = NSColor.black
    static var panelSoft = NSColor.black, rowHover = NSColor.black, rowSel = NSColor.black
    static var line = NSColor.black, line2 = NSColor.black, grid = NSColor.black
    static var titleTop = NSColor.black, titleBot = NSColor.black, headTop = NSColor.black
    static var headBot = NSColor.black, headBot2 = NSColor.black, stripBg = NSColor.black
    static var stripe = NSColor.black, stripe2 = NSColor.black
    static var chartBg = NSColor.black, chartBg2 = NSColor.black, chartBg3 = NSColor.black
    static var searchBg = NSColor.black, searchBg2 = NSColor.black, chipBg = NSColor.black
    static var popBg = NSColor.black, watermark = NSColor.black
    static var marqueeFade = NSColor.black, chartTag = NSColor.black, darkInk = NSColor.black
    static var textHi = NSColor.black, txt = NSColor.black, txtHi2 = NSColor.black
    static var textDim = NSColor.black, textFade = NSColor.black, flat = NSColor.black
    static var up = NSColor.red, down = NSColor.green
    static var gold = NSColor.black, goldDim = NSColor.black, goldSoft = NSColor.black
    static var blue = NSColor.black, purple = NSColor.black, cyan = NSColor.black, warn = NSColor.black

    static func setTheme(dark d: Bool) {
        dark = d
        if d {
            bgDeep = rgb(0x06, 0x08, 0x0C); bg = rgb(0x0A, 0x0D, 0x13)
            panel = rgb(0x0E, 0x12, 0x1A); panelHi = rgb(0x12, 0x17, 0x21); panelSoft = rgb(0x15, 0x1B, 0x26)
            rowHover = rgb(0x18, 0x1F, 0x2C); rowSel = rgb(0x1C, 0x24, 0x33)
            line = rgb(0x18, 0x1F, 0x2B); line2 = rgb(0x23, 0x2C, 0x3B); grid = rgb(0x14, 0x1A, 0x25)
            titleTop = rgb(0x14, 0x19, 0x23); titleBot = rgb(0x0B, 0x0E, 0x15)
            headTop = rgb(0x16, 0x1C, 0x27); headBot = rgb(0x11, 0x16, 0x1F); headBot2 = rgb(0x0C, 0x10, 0x18)
            stripBg = rgb(0x0B, 0x0E, 0x15); stripe = rgb(0x0B, 0x0F, 0x16); stripe2 = rgb(0x0A, 0x0E, 0x15)
            chartBg = rgb(0x07, 0x0A, 0x0F); chartBg2 = rgb(0x0A, 0x0D, 0x14); chartBg3 = rgb(0x08, 0x0B, 0x11)
            searchBg = rgb(0x0B, 0x0F, 0x17); searchBg2 = rgb(0x0E, 0x12, 0x1A)
            chipBg = rgb(255, 255, 255, 20.0 / 255)
            popBg = rgb(0x13, 0x18, 0x23, 0xF8 / 255.0)
            watermark = rgb(236, 244, 255, 13.0 / 255)
            marqueeFade = rgb(0x0E, 0x12, 0x19)
            chartTag = rgb(0x14, 0x19, 0x23, 0xF4 / 255.0); darkInk = rgb(0x12, 0x16, 0x1F)
            textHi = rgb(0xE9, 0xEF, 0xF8); txt = rgb(0xAD, 0xB9, 0xCB); txtHi2 = rgb(0xC2, 0xCC, 0xDA)
            textDim = rgb(0x74, 0x81, 0x93); textFade = rgb(0x46, 0x50, 0x60); flat = rgb(0x9A, 0xA6, 0xB8)
            gold = rgb(0xF2, 0xC1, 0x4E); goldDim = rgb(0xA8, 0x86, 0x36); goldSoft = rgb(0xFF, 0xD9, 0x8A)
            blue = rgb(0x4D, 0x8D, 0xFF); purple = rgb(0xA0, 0x74, 0xFF); cyan = rgb(0x3A, 0xD6, 0xD6)
            warn = rgb(0xFF, 0xA9, 0x40)
        } else {
            bgDeep = rgb(0xEE, 0xF1, 0xF6); bg = rgb(0xF7, 0xF9, 0xFC)
            panel = rgb(0xFF, 0xFF, 0xFF); panelHi = rgb(0xF8, 0xFA, 0xFD); panelSoft = rgb(0xF0, 0xF4, 0xF9)
            rowHover = rgb(0xEC, 0xF2, 0xFA); rowSel = rgb(0xDF, 0xEA, 0xF8)
            line = rgb(0xE6, 0xEB, 0xF2); line2 = rgb(0xD5, 0xDC, 0xE7); grid = rgb(0xEC, 0xF0, 0xF6)
            titleTop = rgb(0xFF, 0xFF, 0xFF); titleBot = rgb(0xF5, 0xF8, 0xFC)
            headTop = rgb(0xFA, 0xFC, 0xFE); headBot = rgb(0xF3, 0xF7, 0xFB); headBot2 = rgb(0xF1, 0xF5, 0xF9)
            stripBg = rgb(0xFF, 0xFF, 0xFF); stripe = rgb(0xFA, 0xFC, 0xFE); stripe2 = rgb(0xF8, 0xFA, 0xFD)
            chartBg = rgb(0xFF, 0xFF, 0xFF); chartBg2 = rgb(0xFD, 0xFE, 0xFF); chartBg3 = rgb(0xF9, 0xFB, 0xFE)
            searchBg = rgb(0xFF, 0xFF, 0xFF); searchBg2 = rgb(0xF7, 0xFA, 0xFD)
            chipBg = rgb(0, 0, 0, 10.0 / 255)
            popBg = rgb(0xFF, 0xFF, 0xFF, 0xFC / 255.0)
            watermark = rgb(20, 32, 48, 16.0 / 255)
            marqueeFade = rgb(0xF6, 0xF9, 0xFC)
            chartTag = rgb(0xFF, 0xFF, 0xFF, 0xF6 / 255.0); darkInk = rgb(0xFF, 0xFF, 0xFF)
            textHi = rgb(0x16, 0x20, 0x2E); txt = rgb(0x3B, 0x46, 0x57); txtHi2 = rgb(0x22, 0x2E, 0x40)
            textDim = rgb(0x6C, 0x77, 0x88); textFade = rgb(0x9A, 0xA4, 0xB3); flat = rgb(0x84, 0x8F, 0x9E)
            gold = rgb(0xB4, 0x84, 0x1A); goldDim = rgb(0x8C, 0x6C, 0x1E); goldSoft = rgb(0x9A, 0x66, 0x00)
            blue = rgb(0x1F, 0x6F, 0xEB); purple = rgb(0x7A, 0x4F, 0xD0); cyan = rgb(0x0E, 0x8C, 0x8C)
            warn = rgb(0xB2, 0x6A, 0x00)
        }
        if hiContrast {
            // HIG「增强对比度」：分隔线/描边与背景拉开更大反差
            line = dark ? rgb(0x2E, 0x38, 0x4A) : rgb(0xB6, 0xC0, 0xD0)
            line2 = dark ? rgb(0x42, 0x50, 0x66) : rgb(0x8A, 0x98, 0xAC)
        }
        applyColorMode(redUp: redUp)
    }

    static var redUp = true

    /// A 股配色：红涨绿跌（可切换），深浅主题各用对应色阶。
    static func applyColorMode(redUp r: Bool) {
        redUp = r
        let red = dark ? rgb(0xFF, 0x4D, 0x4F) : rgb(0xDD, 0x35, 0x38)
        let green = dark ? rgb(0x00, 0xC0, 0x8B) : rgb(0x0B, 0x9D, 0x6E)
        up = r ? red : green
        down = r ? green : red
    }

    static func chgColor(_ v: Double) -> NSColor { v > 1e-9 ? up : v < -1e-9 ? down : flat }

    // ── 字体 ──
    static func num(_ px: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: px, weight: bold ? .bold : .regular)
    }
    static func ui(_ px: CGFloat, bold: Bool = false) -> NSFont {
        NSFont.systemFont(ofSize: px, weight: bold ? .semibold : .regular)
    }
    static let brandFont = ui(15.5, bold: true), brandSub = num(9.5)
    static let numHuge = num(34, bold: true), numBig = num(26, bold: true), numXL = num(19, bold: true)
    static let numL = num(15.5), numM = num(13.5), numS = num(12), numXS = num(11), numXXS = num(10)
    static let uiXL = ui(15, bold: true), uiL = ui(13), uiM = ui(12), uiS = ui(11), uiXS = ui(10)
    static let mockMono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    // ── 绘图工具（视图是 flipped：原点在左上，与 GDI+ 一致）──
    static var cg: CGContext { NSGraphicsContext.current!.cgContext }

    static func fill(_ r: CGRect, _ c: NSColor) {
        cg.setFillColor(c.cgColor)
        cg.fill(r)
    }

    static func hLine(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat, _ c: NSColor) {
        fill(CGRect(x: x1, y: y, width: x2 - x1, height: 1), c)
    }

    static func vLine(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat, _ c: NSColor) {
        fill(CGRect(x: x, y: y1, width: 1, height: y2 - y1), c)
    }

    static func roundedFill(_ r: CGRect, _ rad: CGFloat, _ c: NSColor) {
        let p = CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil)
        cg.setFillColor(c.cgColor)
        cg.addPath(p)
        cg.fillPath()
    }

    static func roundedRect(_ r: CGRect, _ rad: CGFloat, fill f: NSColor?, stroke s: NSColor?, width: CGFloat = 1) {
        let inner = r.insetBy(dx: width / 2, dy: width / 2)
        let p = CGPath(roundedRect: inner, cornerWidth: min(rad, inner.width / 2), cornerHeight: min(rad, inner.height / 2), transform: nil)
        if let f = f { cg.setFillColor(f.cgColor); cg.addPath(p); cg.fillPath() }
        if let s = s { cg.setStrokeColor(s.cgColor); cg.setLineWidth(width); cg.addPath(p); cg.strokePath() }
    }

    static func strokeRect(_ r: CGRect, _ c: NSColor) {
        cg.setStrokeColor(c.cgColor)
        cg.setLineWidth(1)
        cg.stroke(r.insetBy(dx: 0.5, dy: 0.5))
    }

    static func gradient(_ r: CGRect, _ stops: [(NSColor, CGFloat)], vertical: Bool) {
        guard r.width > 0, r.height > 0 else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        let cols = stops.map { $0.0.usingColorSpace(.deviceRGB)?.cgColor ?? $0.0.cgColor } as CFArray
        let locs = stops.map { $0.1 }
        guard let g = CGGradient(colorsSpace: cs, colors: cols, locations: locs) else { return }
        cg.saveGState()
        cg.clip(to: r)
        let a = CGPoint(x: r.minX, y: r.minY)
        let b = vertical ? CGPoint(x: r.minX, y: r.maxY) : CGPoint(x: r.maxX, y: r.minY)
        cg.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    static func vGrad(_ r: CGRect, _ top: NSColor, _ bot: NSColor) {
        gradient(r, [(top, 0), (bot, 1)], vertical: true)
    }

    static func dashLine(from a: CGPoint, to b: CGPoint, _ c: NSColor, pattern: [CGFloat] = [3, 3]) {
        cg.saveGState()
        cg.setStrokeColor(c.cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: pattern)
        cg.move(to: a); cg.addLine(to: b); cg.strokePath()
        cg.restoreGState()
    }

    static func ellipse(_ r: CGRect, _ c: NSColor) {
        cg.setFillColor(c.cgColor)
        cg.fillEllipse(in: r)
    }

    // ── 文字 ──
    // 段落样式缓存（仅主线程绘制路径使用）
    private static var psCache: [String: NSParagraphStyle] = [:]

    private static func attrs(_ f: NSFont, _ c: NSColor, _ al: Align, _ ellipsis: Bool) -> [NSAttributedString.Key: Any] {
        let key = "\(al)-\(ellipsis)"
        let ps: NSParagraphStyle
        if let cached = psCache[key] {
            ps = cached
        } else {
            let p = NSMutableParagraphStyle()
            p.alignment = al == .left ? .left : al == .center ? .center : .right
            p.lineBreakMode = ellipsis ? .byTruncatingTail : .byClipping
            psCache[key] = p
            ps = p
        }
        return [.font: f, .foregroundColor: c, .paragraphStyle: ps]
    }

    static func text(_ s: String, _ f: NSFont, _ c: NSColor, _ r: CGRect, _ al: Align = .left, ellipsis: Bool = false) {
        guard !s.isEmpty, r.width > 0 else { return }
        let a = attrs(f, c, al, ellipsis)
        let h = ceil(f.ascender - f.descender + f.leading)
        let box = CGRect(x: r.minX, y: (r.midY - h / 2).rounded(), width: r.width, height: h)
        (s as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a)
    }

    static func textEllipsis(_ s: String, _ f: NSFont, _ c: NSColor, _ r: CGRect, _ al: Align = .left) {
        text(s, f, c, r, al, ellipsis: true)
    }

    static func measure(_ s: String, _ f: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }

    // ── 迷你图 ──
    static func miniCandles(_ r: CGRect, _ data: [Double], bars barsIn: Int) {
        guard data.count >= 2, r.width >= 6, r.height >= 6 else { return }
        let n = data.count
        var mn = data.min()!, mx = data.max()!
        if mx - mn < 1e-9 {
            // 平坦序列（如恒为 0 的热压力）：一条中性灰线，不渲染十字星墙——健康数据保持安静
            let ctx = cg
            let yy = r.midY.rounded()
            ctx.saveGState()
            ctx.setStrokeColor(textFade.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: r.minX, y: yy))
            ctx.addLine(to: CGPoint(x: r.maxX, y: yy))
            ctx.strokePath()
            ctx.restoreGState()
            return
        }
        let bars = max(3, min(barsIn, max(3, Int(r.width / 3.2))))
        let pad = (mx - mn) * 0.12
        mn -= pad; mx += pad
        let slot = r.width / CGFloat(bars)
        let bw = max(1.1, slot * 0.58)
        func Y(_ v: Double) -> CGFloat { r.maxY - CGFloat((v - mn) / (mx - mn)) * r.height }
        let ctx = cg
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        for i in 0..<bars {
            let i0 = i * n / bars
            var i1 = (i + 1) * n / bars
            if i1 <= i0 { i1 = i0 + 1 }
            if i0 >= n { break }
            let o = data[i0], c = data[min(i1, n) - 1]
            var h = -Double.greatestFiniteMagnitude, l = Double.greatestFiniteMagnitude
            var k = i0
            while k < i1 && k < n { h = max(h, data[k]); l = min(l, data[k]); k += 1 }
            let upBar = c >= o
            let col = upBar ? up : down
            let cx = (r.minX + (CGFloat(i) + 0.5) * slot).rounded() + 0.5
            ctx.setFillColor(col.a(0.85).cgColor)
            ctx.fill(CGRect(x: cx - 0.5, y: Y(h), width: 1, height: max(1, Y(l) - Y(h))))
            let top = Y(max(o, c))
            let hh = max(1, abs(Y(o) - Y(c)))
            ctx.setFillColor(col.cgColor)
            ctx.fill(CGRect(x: (cx - bw / 2).rounded(), y: top.rounded(), width: max(1, bw.rounded()), height: hh.rounded()))
        }
        ctx.restoreGState()
    }
}

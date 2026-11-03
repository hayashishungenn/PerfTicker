import AppKit

/// 关于窗口：开发者 / 组织 / 主页链接 / 开源协议 / 运行环境。
final class AboutWindow: NSWindow {
    init(hw: Hardware) {
        let view = AboutView(hw: hw)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = Theme.panel
        self.contentView = view
        self.center()
    }
}

final class AboutView: NSView {
    private let hw: Hardware
    private var hover = -1
    private var linkRects: [CGRect] = []
    private let links = [
        ("GitHub  github.com/QiuSui1145", "https://github.com/QiuSui1145/"),
        ("Bilibili  space.bilibili.com/1764510273", "https://space.bilibili.com/1764510273")
    ]

    init(hw: Hardware) {
        self.hw = hw
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 420))
        linkRects = Array(repeating: .zero, count: links.count)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height

        Theme.roundedFill(bounds, 8, Theme.popBg)
        Theme.roundedRect(bounds, 8, fill: nil, stroke: Theme.line2)
        Theme.roundedFill(CGRect(x: 0, y: 0, width: w, height: 3), 1.5, Theme.gold)

        let pad: CGFloat = 22
        // 图标 + 标题
        let logo = CGRect(x: pad, y: 24, width: 38, height: 38)
        let path = CGPath(roundedRect: logo, cornerWidth: 9, cornerHeight: 9, transform: nil)
        let ctx = Theme.cg
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        Theme.gradient(logo, [(rgb(0xFF, 0xDF, 0x9A), 0), (rgb(0xC2, 0x88, 0x14), 1)], vertical: true)
        ctx.restoreGState()

        let br = rgb(0x11, 0x15, 0x1E)
        Theme.fill(CGRect(x: logo.minX + 7, y: logo.minY + 21, width: 5, height: 11), br)
        Theme.fill(CGRect(x: logo.minX + 16, y: logo.minY + 10, width: 5, height: 22), br)
        Theme.fill(CGRect(x: logo.minX + 25, y: logo.minY + 16, width: 5, height: 16), br)

        Theme.text("性能行情终端", Theme.uiXL, Theme.textHi, CGRect(x: logo.maxX + 12, y: 22, width: 300, height: 24))
        Theme.text("PerfTicker for macOS · v1.5.0", Theme.numXXS, Theme.textDim, CGRect(x: logo.maxX + 12, y: 44, width: 300, height: 18))

        var y: CGFloat = 86
        func info(_ k: String, _ v: String) {
            Theme.text(k, Theme.uiS, Theme.textDim, CGRect(x: pad, y: y, width: 70, height: 22))
            Theme.text(v, Theme.uiM, Theme.textHi, CGRect(x: pad + 72, y: y, width: 320, height: 22))
            y += 26
        }

        info("开发者", "QiuSui")
        info("组织", "QiuSui_Studio")

        y += 6
        Theme.hLine(pad, w - pad, y, Theme.line)
        y += 12

        for (i, item) in links.enumerated() {
            let r = CGRect(x: pad, y: y, width: w - pad * 2, height: 24)
            linkRects[i] = r
            let hov = hover == i
            Theme.text(item.0, Theme.uiM, hov ? Theme.gold : Theme.blue, r)
            if hov {
                let tw = Theme.measure(item.0, Theme.uiM)
                Theme.fill(CGRect(x: r.minX, y: r.maxY - 3, width: tw, height: 1), Theme.gold)
            }
            y += 28
        }

        y += 6
        Theme.text("开源协议  GPL-3.0", Theme.uiS, Theme.txt, CGRect(x: pad, y: y, width: 240, height: 20))
        y += 24
        Theme.text("本程序以 GPLv3 协议开源，原生适用于 macOS 平台", Theme.uiXS, Theme.textFade,
                   CGRect(x: pad, y: y, width: w - pad * 2, height: 18))

        // 运行环境 / 硬件配置 / 营收基准
        y += 24
        Theme.hLine(pad, w - pad, y, Theme.line)
        y += 10

        func env(_ label: String, _ value: String) {
            Theme.text(label, Theme.uiXS, Theme.textDim, CGRect(x: pad, y: y, width: 64, height: 17))
            Theme.textEllipsis(value, Theme.uiXS, Theme.txt.a(0xB8 / 255.0),
                               CGRect(x: pad + 66, y: y, width: w - pad * 2 - 66, height: 17))
            y += 18
        }

        env("运行环境", hw.osLine)
        env("硬件配置", hw.cpuLine)
        env("", hw.gpuLine)
        env("", hw.memLine)
        env("营收基准", hw.weightLine)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var h = -1
        for (i, r) in linkRects.enumerated() where r.contains(p) { h = i }
        if h != hover {
            hover = h
            setNeedsDisplay(bounds)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in linkRects.enumerated() where r.contains(p) {
            if let url = URL(string: links[i].1) {
                NSWorkspace.shared.open(url)
            }
            return
        }
    }
}

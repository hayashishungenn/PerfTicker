import AppKit

/// 原生图标生成与加载工具，完全复刻原版金色圆角外框 + 3 根 K 线柱设计。
enum Art {
    /// 动态生成与原版 Art.MakeAppIcon() 像素级一致的 NSImage
    static func makeAppIcon(size: CGFloat = 64) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        
        let ctx = Theme.cg
        let scale = size / 64.0
        let r = CGRect(x: 3 * scale, y: 3 * scale, width: 58 * scale, height: 58 * scale)
        let rad = 14 * scale
        
        // 金色渐变底板
        let path = CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        Theme.gradient(
            CGRect(x: 0, y: 0, width: size, height: size),
            [(rgb(0xFF, 0xDF, 0x9A), 0), (rgb(0xC2, 0x88, 0x14), 1)],
            vertical: true
        )
        ctx.restoreGState()
        
        // 3 根暗色 K 线柱 (严格对齐原版 17/30/7/22, 29/15/7/37, 41/24/7/28)
        let ink = rgb(0x11, 0x15, 0x1E)
        Theme.fill(CGRect(x: 17 * scale, y: 30 * scale, width: 7 * scale, height: 22 * scale), ink)
        Theme.fill(CGRect(x: 29 * scale, y: 15 * scale, width: 7 * scale, height: 37 * scale), ink)
        Theme.fill(CGRect(x: 41 * scale, y: 24 * scale, width: 7 * scale, height: 28 * scale), ink)
        
        img.unlockFocus()
        return img
    }

    /// 状态栏专属小图标 (18x18 模板图标)
    static func makeStatusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()
        let ctx = Theme.cg
        let r = CGRect(x: 1, y: 1, width: 16, height: 16)
        let path = CGPath(roundedRect: r, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        Theme.gradient(r, [(rgb(0xFF, 0xDF, 0x9A), 0), (rgb(0xC2, 0x88, 0x14), 1)], vertical: true)
        ctx.restoreGState()
        
        let ink = rgb(0x11, 0x15, 0x1E)
        Theme.fill(CGRect(x: 4.5, y: 8, width: 2, height: 6), ink)
        Theme.fill(CGRect(x: 8, y: 4, width: 2, height: 10), ink)
        Theme.fill(CGRect(x: 11.5, y: 6.5, width: 2, height: 7.5), ink)
        img.unlockFocus()
        return img
    }
}

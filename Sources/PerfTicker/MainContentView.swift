import AppKit

final class MainContentView: NSView {
    unowned let controller: AppController
    private var trackingArea: NSTrackingArea?

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.fill(bounds, Theme.bgDeep)
        for p in controller.panels {
            if p.bounds.intersects(dirtyRect) {
                p.draw()
            }
        }
        controller.paintSettings(in: dirtyRect)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if controller.settingsOpen {
            controller.settingsMouseMove(p)
            return
        }
        if let panel = controller.findPanel(p) {
            panel.mouseMove(p)
            panel.cursor(at: p).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        for p in controller.panels { p.mouseLeave() }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if controller.settingsOpen {
            if controller.settingsClick(p) { return }
        }
        if controller.st.searchActive && !controller.procPanel.bounds.contains(p) {
            controller.setSearchActive(false)
        }
        if let panel = controller.findPanel(p) {
            if event.clickCount == 2 {
                panel.doubleClick(p)
            } else {
                _ = panel.click(p)
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let panel = controller.findPanel(p) {
            panel.rightClick(p)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let panel = controller.findPanel(p) {
            panel.wheel(p, event.scrollingDeltaY)
        }
    }

    override func keyDown(with event: NSEvent) {
        if controller.st.searchActive {
            if event.keyCode == 51 { // Backspace
                if !controller.st.procFilter.isEmpty {
                    controller.setProcFilter(String(controller.st.procFilter.dropLast()))
                }
                return
            }
            if event.keyCode == 36 { // Enter
                controller.setSearchActive(false)
                return
            }
            if event.keyCode == 53 { // Esc
                controller.setSearchActive(false)
                controller.setProcFilter("")
                return
            }
            if let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command) {
                controller.setProcFilter(controller.st.procFilter + chars)
                return
            }
        }

        // 快捷键
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            controller.setSearchActive(true)
            return
        }
        switch event.charactersIgnoringModifiers {
        case " ":
            controller.togglePause()
        case "1":
            controller.setChartMode(2000)
        case "2":
            controller.setChartMode(5000)
        case "3":
            controller.setChartMode(10000)
        case "4":
            controller.setChartMode(30000)
        case "5":
            controller.setChartMode(60000)
        case "t", "T":
            controller.toggleTopMost()
        case "e", "E":
            controller.toggleEconomy()
        case "c", "C":
            controller.toggleColor()
        default:
            if event.keyCode == 99 || event.keyCode == 101 { // F3 / F9：开关挂件
                controller.toggleGadget()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

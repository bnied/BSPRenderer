import AppKit
import CoreGraphics
import QuartzCore

final class GameView: NSView {
    let level = Level.showcase
    let player = Player()
    let renderer: Renderer
    let bsp: Bsp

    var keys = Set<UInt16>()
    var lastTime = CACurrentMediaTime()
    var timer: Timer?

    override init(frame: NSRect) {
        let level = Level.showcase
        self.renderer = Renderer(level: level, width: 480, height: 300)
        self.bsp = Bsp(level: level)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override var acceptsFirstResponder: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        start()
    }

    private func start() {
        timer?.invalidate()
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil); return }   // Esc
        if event.keyCode == 48 { renderer.slowMode.toggle(); return }   // Tab
        keys.insert(event.keyCode)
    }
    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now
        player.update(dt: dt, keys: keys, level: level, bsp: bsp)
        renderer.render(player: player, bsp: bsp)
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.blit(to: ctx, in: bounds)
        drawHUD()
    }

    private func drawHUD() {
        let si = bsp.findSector(player.pos)
        let s = level.sectors[si]
        let slowTag = renderer.slowMode ? "   [SLOW]" : ""
        let text = String(
            format: "sector %d   floor %+d   ceil %+d   feetZ %+d   eyeZ %+d\(slowTag)",
            si, Int(s.floorH), Int(s.ceilH), Int(player.feetZ), Int(player.eyeZ)
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        let astr = NSAttributedString(string: text, attributes: attrs)
        let size = astr.size()
        let pad: CGFloat = 6
        let origin = CGPoint(x: 8, y: bounds.height - size.height - 8)
        NSColor(white: 0, alpha: 0.55).setFill()
        NSBezierPath(rect: CGRect(
            x: origin.x - pad, y: origin.y - pad / 2,
            width: size.width + 2 * pad, height: size.height + pad
        )).fill()
        astr.draw(at: origin)
    }
}

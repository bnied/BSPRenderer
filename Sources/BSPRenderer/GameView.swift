import AppKit
import CoreGraphics
import QuartzCore

final class GameView: NSView {
    let player = Player()
    let renderer = Renderer(width: 480, height: 300)
    let bspRoot: BSPNode

    var keys = Set<UInt16>()
    var lastTime = CACurrentMediaTime()
    var timer: Timer?

    override init(frame: NSRect) {
        self.bspRoot = buildBSP(generateSegs())
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
        keys.insert(event.keyCode)
    }
    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now
        player.update(dt: dt, keys: keys)
        renderer.render(player: player, bspRoot: bspRoot)
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.blit(to: ctx, in: bounds)
    }
}

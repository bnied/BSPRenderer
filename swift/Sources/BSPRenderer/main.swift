import AppKit

// Controls: W/A/S/D or arrows to move & strafe. Left/Right to turn. Esc to quit.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let w: CGFloat = 960, h: CGFloat = 600
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = "BSP Renderer — WASD / arrows, Esc to quit"
        window.center()
        window.isReleasedWhenClosed = false

        let view = GameView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.makeFirstResponder(view)
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

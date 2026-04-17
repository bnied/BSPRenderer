import Foundation

final class Player {
    var pos = Vec2(x: 80, y: 100)
    var angle = 0.0
    let fov = 70.0 * .pi / 180.0
    let moveSpeed = 140.0
    let rotSpeed = 2.4
    let eyeOverFloor = 41.0

    // macOS keyCode constants used for movement.
    private enum Key {
        static let a: UInt16 = 0
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let w: UInt16 = 13
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    func update(dt: Double, keys: Set<UInt16>) {
        let rot = rotSpeed * dt
        let mv = moveSpeed * dt

        if keys.contains(Key.left)  { angle -= rot }
        if keys.contains(Key.right) { angle += rot }

        let cosA = cos(angle), sinA = sin(angle)
        var dx = 0.0, dy = 0.0
        if keys.contains(Key.w) || keys.contains(Key.up)   { dx += cosA * mv; dy += sinA * mv }
        if keys.contains(Key.s) || keys.contains(Key.down) { dx -= cosA * mv; dy -= sinA * mv }
        if keys.contains(Key.a) { dx += sinA * mv; dy -= cosA * mv }
        if keys.contains(Key.d) { dx -= sinA * mv; dy += cosA * mv }

        // Axis-separated probe against all solid linedefs with a player radius.
        let radius = 8.0
        let tryX = Vec2(x: pos.x + dx, y: pos.y)
        if !collides(tryX, radius: radius) { pos.x = tryX.x }
        let tryY = Vec2(x: pos.x, y: pos.y + dy)
        if !collides(tryY, radius: radius) { pos.y = tryY.y }
    }

    private func collides(_ p: Vec2, radius: Double) -> Bool {
        for l in linedefs {
            // Allow passage through two-sided linedefs (floor-height blocking not modeled yet).
            if l.backSector != nil { continue }
            let a = vertices[l.v1]
            let b = vertices[l.v2]
            if pointSegmentDistance(p, a, b) < radius { return true }
        }
        return false
    }

    private func pointSegmentDistance(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let l2 = ab.x * ab.x + ab.y * ab.y
        if l2 < 1e-9 { return (p - a).length }
        var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2
        t = max(0, min(1, t))
        let proj = Vec2(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return (p - proj).length
    }
}

import Foundation

struct Vec2 {
    var x: Double
    var y: Double
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
    var length: Double { (x * x + y * y).squareRoot() }
}

struct RGBA { var r, g, b, a: UInt8 }

@inline(__always)
func shade(_ c: RGBA, _ f: Double) -> RGBA {
    let k = max(0.12, min(1.0, f))
    return RGBA(
        r: UInt8(Double(c.r) * k),
        g: UInt8(Double(c.g) * k),
        b: UInt8(Double(c.b) * k),
        a: 255
    )
}

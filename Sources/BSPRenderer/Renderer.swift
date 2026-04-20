import Foundation
import CoreGraphics

// A visplane accumulates per-column coverage for one sector's floor or
// ceiling. `drawSeg` records spans into it while walking the BSP, then
// the deferred pass renders the plane as scanlines using per-pixel
// inverse projection.
struct Visplane {
    let sectorIndex: Int
    let isCeiling: Bool
    var top: [Int]   // inclusive upper bound per column; Int.max if uncovered
    var bot: [Int]   // inclusive lower bound per column; Int.min if uncovered
    var minX: Int
    var maxX: Int

    init(sectorIndex: Int, isCeiling: Bool, width: Int) {
        self.sectorIndex = sectorIndex
        self.isCeiling = isCeiling
        self.top = [Int](repeating: Int.max, count: width)
        self.bot = [Int](repeating: Int.min, count: width)
        self.minX = width
        self.maxX = -1
    }

    mutating func reset() {
        for i in 0 ..< top.count {
            top[i] = Int.max
            bot[i] = Int.min
        }
        minX = top.count
        maxX = -1
    }

    @inline(__always)
    mutating func extend(_ x: Int, _ yLo: Int, _ yHi: Int) {
        if yLo > yHi { return }
        if yLo < top[x] { top[x] = yLo }
        if yHi > bot[x] { bot[x] = yHi }
        if x < minX { minX = x }
        if x > maxX { maxX = x }
    }
}

final class Renderer {
    let bufW: Int
    let bufH: Int
    var pixels: [UInt8]
    var yTop: [Int]     // current open-region top per column (inclusive)
    var yBot: [Int]     // current open-region bottom per column (inclusive)
    var visplanes: [Visplane]   // 2 per sector: [floor, ceiling] pair per sector, in order

    init(width: Int, height: Int) {
        self.bufW = width
        self.bufH = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
        self.yTop = [Int](repeating: 0, count: width)
        self.yBot = [Int](repeating: height - 1, count: width)
        var planes: [Visplane] = []
        planes.reserveCapacity(sectors.count * 2)
        for si in 0 ..< sectors.count {
            planes.append(Visplane(sectorIndex: si, isCeiling: false, width: width))
            planes.append(Visplane(sectorIndex: si, isCeiling: true, width: width))
        }
        self.visplanes = planes
    }

    // MARK: frame entry

    func render(player: Player, bspRoot: BSPNode) {
        // Reset per-column open region and per-frame visplane coverage.
        for x in 0 ..< bufW {
            yTop[x] = 0
            yBot[x] = bufH - 1
        }
        for i in 0 ..< visplanes.count {
            visplanes[i].reset()
        }
        let playerSector = findSector(pos: player.pos, node: bspRoot)
        let sec = sectors[playerSector]
        let halfW = Double(bufW) / 2.0
        let halfH = Double(bufH) / 2.0
        let horizon = halfH
        // Background fill (dim ceiling on top, dim floor on bottom) as a fallback so any
        // unclosed columns look plausible.
        for y in 0 ..< bufH {
            let c = y < bufH / 2 ? sec.ceilColor : sec.floorColor
            let dc = shade(c, 0.55)
            let rowStart = y * bufW * 4
            for x in 0 ..< bufW {
                let i = rowStart + x * 4
                pixels[i] = dc.r
                pixels[i + 1] = dc.g
                pixels[i + 2] = dc.b
                pixels[i + 3] = 255
            }
        }
        let fovHalfTan = tan(player.fov / 2.0)
        let focal = halfW / fovHalfTan
        let eyeZ = player.eyeZ
        let cosA = cos(player.angle), sinA = sin(player.angle)

        traverseBSP(bspRoot, player: player.pos) { seg in
            self.drawSeg(
                seg,
                player: player,
                cosA: cosA, sinA: sinA,
                halfW: halfW, horizon: horizon,
                fovHalfTan: fovHalfTan, focal: focal,
                eyeZ: eyeZ
            )
        }

        renderVisplanes(focal: focal, halfW: halfW, horizon: horizon,
                        playerPos: player.pos, cosA: cosA, sinA: sinA,
                        eyeZ: eyeZ)

        drawMinimap(player: player)
        drawCrosshair()
    }

    private func renderVisplanes(focal: Double, halfW: Double, horizon: Double,
                                 playerPos: Vec2, cosA: Double, sinA: Double,
                                 eyeZ: Double) {
        for plane in visplanes {
            if plane.maxX < plane.minX { continue }
            let sector = sectors[plane.sectorIndex]
            let planeZ = plane.isCeiling ? sector.ceilH : sector.floorH
            let planeHeight = planeZ - eyeZ
            let color = plane.isCeiling ? sector.ceilColor : sector.floorColor
            let sectorLight = sector.light
            for x in plane.minX ... plane.maxX {
                let yLo = plane.top[x]
                let yHi = plane.bot[x]
                if yLo > yHi { continue }
                fillPlaneColumn(x, yLo, yHi,
                                planeHeight: planeHeight,
                                focal: focal, halfW: halfW, horizon: horizon,
                                playerPos: playerPos, cosA: cosA, sinA: sinA,
                                sectorLight: sectorLight, color: color)
            }
        }
    }

    // MARK: blit

    func blit(to ctx: CGContext, in rect: CGRect) {
        ctx.interpolationQuality = .none

        pixels.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let provider = CGDataProvider(
                dataInfo: nil,
                data: base,
                size: bufW * bufH * 4,
                releaseData: { _, _, _ in }
            )!
            let cs = CGColorSpaceCreateDeviceRGB()
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            guard let img = CGImage(
                width: bufW,
                height: bufH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bufW * 4,
                space: cs,
                bitmapInfo: info,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) else { return }

            // Our buffer has y=0 at the top; CG draws from bottom-left by default. Flip the CTM.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: rect)
            ctx.restoreGState()
        }
    }

    // MARK: pixel ops

    @inline(__always)
    private func putPixel(_ x: Int, _ y: Int, _ c: RGBA) {
        let i = (y * bufW + x) * 4
        pixels[i] = c.r
        pixels[i + 1] = c.g
        pixels[i + 2] = c.b
        pixels[i + 3] = c.a
    }

    @inline(__always)
    private func fillColumn(_ x: Int, _ yLo: Int, _ yHi: Int, _ c: RGBA) {
        if yLo > yHi { return }
        var i = (yLo * bufW + x) * 4
        let stride = bufW * 4
        for _ in yLo ... yHi {
            pixels[i] = c.r
            pixels[i + 1] = c.g
            pixels[i + 2] = c.b
            pixels[i + 3] = 255
            i += stride
        }
    }

    // Fill a vertical strip of a horizontal plane (floor or ceiling) by
    // inverse-projecting each pixel to its world (X, Y), sampling a
    // checkerboard, and depth-shading. `planeHeight` is signed: positive for
    // ceiling (above eye), negative for floor (below eye).
    @inline(__always)
    private func fillPlaneColumn(_ x: Int, _ yLo: Int, _ yHi: Int,
                                 planeHeight: Double,
                                 focal: Double, halfW: Double, horizon: Double,
                                 playerPos: Vec2, cosA: Double, sinA: Double,
                                 sectorLight: Double, color: RGBA) {
        if yLo > yHi { return }
        let absH = abs(planeHeight)
        let xOffset = Double(x) - halfW
        // 70%-brightness dark tile, precomputed once per strip.
        let darkColor = RGBA(
            r: UInt8(Double(color.r) * 0.7),
            g: UInt8(Double(color.g) * 0.7),
            b: UInt8(Double(color.b) * 0.7),
            a: 255
        )
        let tileBits = 4   // 16-unit tiles (1 << 4)
        let tileBias = 1 << 20   // keep integer coords positive for parity math
        var i = (yLo * bufW + x) * 4
        let stride = bufW * 4
        for y in yLo ... yHi {
            let absDy = abs(Double(y) - horizon)
            let depth = absDy > 0.0001 ? absH * focal / absDy : 1e9
            // View-space right offset for this pixel at this depth.
            let r = xOffset * depth / focal
            // forward = (cosA, sinA); right = (-sinA, cosA)
            let wx = playerPos.x + depth * cosA - r * sinA
            let wy = playerPos.y + depth * sinA + r * cosA
            let tx = (Int(wx) + tileBias) >> tileBits
            let ty = (Int(wy) + tileBias) >> tileBits
            let tile = (tx ^ ty) & 1
            let base = tile == 0 ? color : darkColor
            let falloff = 1.0 / (1.0 + depth * 0.004)
            let light = max(0.15, min(1.0, sectorLight * falloff))
            let c = shade(base, light * 0.9)
            pixels[i] = c.r
            pixels[i + 1] = c.g
            pixels[i + 2] = c.b
            pixels[i + 3] = 255
            i += stride
        }
    }

    // MARK: seg drawing

    private func drawSeg(_ seg: Seg,
                         player: Player,
                         cosA: Double, sinA: Double,
                         halfW: Double, horizon: Double,
                         fovHalfTan: Double, focal: Double,
                         eyeZ: Double) {

        // Back-face cull: normal = (-(v2.y-v1.y), v2.x-v1.x) points toward front sector.
        let sdx = seg.v2.x - seg.v1.x
        let sdy = seg.v2.y - seg.v1.y
        let nx = -sdy
        let ny = sdx
        let toPx = player.pos.x - seg.v1.x
        let toPy = player.pos.y - seg.v1.y
        if nx * toPx + ny * toPy <= 0 { return }

        // Transform endpoints to view space.
        //   forward = (cosA, sinA)
        //   r =  (p.x - px) * -sinA + (p.y - py) * cosA  — right-axis (+y → +r at angle 0)
        //   d =  (p.x - px) *  cosA + (p.y - py) * sinA  — forward-axis
        let rx1 = seg.v1.x - player.pos.x
        let ry1 = seg.v1.y - player.pos.y
        let rx2 = seg.v2.x - player.pos.x
        let ry2 = seg.v2.y - player.pos.y
        var r1 = -rx1 * sinA + ry1 * cosA
        var d1 =  rx1 * cosA + ry1 * sinA
        var r2 = -rx2 * sinA + ry2 * cosA
        var d2 =  rx2 * cosA + ry2 * sinA

        // Near plane.
        let near = 1.0
        if d1 < near && d2 < near { return }
        if d1 < near {
            let t = (near - d1) / (d2 - d1)
            r1 = r1 + t * (r2 - r1)
            d1 = near
        } else if d2 < near {
            let t = (near - d2) / (d1 - d2)
            r2 = r2 + t * (r1 - r2)
            d2 = near
        }

        // Left frustum (r + k*d >= 0).
        let k = fovHalfTan
        let lD1 = r1 + k * d1
        let lD2 = r2 + k * d2
        if lD1 < 0 && lD2 < 0 { return }
        if lD1 < 0 {
            let t = lD1 / (lD1 - lD2)
            r1 = r1 + t * (r2 - r1)
            d1 = d1 + t * (d2 - d1)
        } else if lD2 < 0 {
            let t = lD2 / (lD2 - lD1)
            r2 = r2 + t * (r1 - r2)
            d2 = d2 + t * (d1 - d2)
        }

        // Right frustum (k*d - r >= 0).
        let rD1 = k * d1 - r1
        let rD2 = k * d2 - r2
        if rD1 < 0 && rD2 < 0 { return }
        if rD1 < 0 {
            let t = rD1 / (rD1 - rD2)
            r1 = r1 + t * (r2 - r1)
            d1 = d1 + t * (d2 - d1)
        } else if rD2 < 0 {
            let t = rD2 / (rD2 - rD1)
            r2 = r2 + t * (r1 - r2)
            d2 = d2 + t * (d1 - d2)
        }

        // Project to screen X.
        let sx1 = halfW + (r1 / d1) * focal
        let sx2 = halfW + (r2 / d2) * focal
        if sx2 <= sx1 + 0.0001 { return }

        let xStart = max(0, Int(ceil(sx1)))
        let xEnd = min(bufW - 1, Int(floor(sx2)))
        if xStart > xEnd { return }

        let front = sectors[seg.frontSector]
        let fCeil = front.ceilH - eyeZ
        let fFloor = front.floorH - eyeZ
        var bCeil: Double = 0, bFloor: Double = 0
        if let bi = seg.backSector {
            let back = sectors[bi]
            bCeil = back.ceilH - eyeZ
            bFloor = back.floorH - eyeZ
        }

        let lineDef = linedefs[seg.lineDefIndex]
        let frontLight = front.light

        // Perspective-correct interpolation of 1/d across screen X.
        let invD1 = 1.0 / d1
        let invD2 = 1.0 / d2
        let dx = sx2 - sx1

        for x in xStart ... xEnd {
            if yTop[x] > yBot[x] { continue }
            let tLin = (Double(x) - sx1) / dx
            let invD = (1.0 - tLin) * invD1 + tLin * invD2
            let depth = 1.0 / invD

            // Per-column light falloff.
            let falloff = 1.0 / (1.0 + depth * 0.004)
            let light = max(0.15, min(1.0, frontLight * falloff))

            let ceilY  = Int((horizon - fCeil  * focal * invD).rounded())
            let floorY = Int((horizon - fFloor * focal * invD).rounded())

            let top = yTop[x]
            let bot = yBot[x]

            // Ceiling fill → visplane span (deferred to post-BSP pass).
            if ceilY > top {
                let yLo = top
                let yHi = min(ceilY - 1, bot)
                visplanes[seg.frontSector * 2 + 1].extend(x, yLo, yHi)
            }
            // Floor fill → visplane span (deferred to post-BSP pass).
            if floorY < bot {
                let yLo = max(floorY + 1, top)
                let yHi = bot
                visplanes[seg.frontSector * 2].extend(x, yLo, yHi)
            }

            if seg.backSector == nil {
                // Solid wall: fill the open region between ceiling and floor.
                let yLo = max(ceilY, top)
                let yHi = min(floorY, bot)
                fillColumn(x, yLo, yHi, shade(lineDef.wallColor, light))
                // Mark column fully occluded.
                yTop[x] = bot + 1
            } else {
                let backCeilY  = Int((horizon - bCeil  * focal * invD).rounded())
                let backFloorY = Int((horizon - bFloor * focal * invD).rounded())

                // Upper wall: exists when the back ceiling is lower in world (larger screen Y).
                var newTop = max(ceilY, top)
                if backCeilY > ceilY {
                    let yLo = max(ceilY, top)
                    let yHi = min(backCeilY - 1, bot)
                    fillColumn(x, yLo, yHi, shade(lineDef.upperColor, light))
                    newTop = max(backCeilY, top)
                }

                // Lower wall: exists when the back floor is higher in world (smaller screen Y).
                var newBot = min(floorY, bot)
                if backFloorY < floorY {
                    let yLo = max(backFloorY + 1, top)
                    let yHi = min(floorY, bot)
                    fillColumn(x, yLo, yHi, shade(lineDef.lowerColor, light))
                    newBot = min(backFloorY, bot)
                }

                yTop[x] = newTop
                yBot[x] = newBot
                if yTop[x] > yBot[x] {
                    yTop[x] = yBot[x] + 1
                }
            }
        }
    }

    // MARK: overlays

    private func drawCrosshair() {
        let cx = bufW / 2, cy = bufH / 2
        let col = RGBA(r: 255, g: 255, b: 255, a: 255)
        for d in -3 ... 3 where d != 0 {
            let x = cx + d, y = cy + d
            if x >= 0 && x < bufW { putPixel(x, cy, col) }
            if y >= 0 && y < bufH { putPixel(cx, y, col) }
        }
    }

    private func drawMinimap(player: Player) {
        // Auto-fit the map to a fixed minimap box.
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for v in vertices {
            if v.x < minX { minX = v.x }
            if v.y < minY { minY = v.y }
            if v.x > maxX { maxX = v.x }
            if v.y > maxY { maxY = v.y }
        }
        let pad = 8.0
        let boxW = 120.0
        let boxH = 100.0
        let ox = 8.0, oy = 8.0
        let sx = boxW / (maxX - minX + 2 * pad)
        let sy = boxH / (maxY - minY + 2 * pad)
        let s = min(sx, sy)

        func project(_ v: Vec2) -> (Int, Int) {
            (
                Int(ox + ((v.x - minX) + pad) * s),
                Int(oy + ((v.y - minY) + pad) * s)
            )
        }

        // Backdrop.
        for y in Int(oy - 2) ... Int(oy + boxH + 2) {
            for x in Int(ox - 2) ... Int(ox + boxW + 2) {
                if x >= 0 && x < bufW && y >= 0 && y < bufH {
                    putPixel(x, y, RGBA(r: 10, g: 10, b: 14, a: 255))
                }
            }
        }

        // Linedefs — two-sided in gray, one-sided colored.
        for l in linedefs {
            let a = project(vertices[l.v1])
            let b = project(vertices[l.v2])
            let col: RGBA = l.backSector == nil ? l.wallColor : RGBA(r: 120, g: 120, b: 120, a: 255)
            drawLine(x0: a.0, y0: a.1, x1: b.0, y1: b.1, color: col)
        }

        // Player.
        let (pxI, pyI) = project(player.pos)
        for dy in -1 ... 1 {
            for dx in -1 ... 1 {
                let x = pxI + dx, y = pyI + dy
                if x >= 0 && x < bufW && y >= 0 && y < bufH {
                    putPixel(x, y, RGBA(r: 255, g: 255, b: 255, a: 255))
                }
            }
        }
        let hx = pxI + Int(cos(player.angle) * 10)
        let hy = pyI + Int(sin(player.angle) * 10)
        drawLine(x0: pxI, y0: pyI, x1: hx, y1: hy, color: RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    private func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, color: RGBA) {
        var x0 = x0, y0 = y0
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            if x0 >= 0 && x0 < bufW && y0 >= 0 && y0 < bufH { putPixel(x0, y0, color) }
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }
}

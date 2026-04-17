import Foundation

indirect enum BSPNode {
    case leaf(segs: [Seg], sector: Int)
    case node(pStart: Vec2, pDelta: Vec2, left: BSPNode, right: BSPNode)
}

enum SegSide {
    case left
    case right
    case straddle(Vec2)
    case collinear
}

@inline(__always)
func sideOf(_ p: Vec2, pStart: Vec2, pDelta: Vec2) -> Double {
    // Positive → point is on the left of the directed partition line.
    pDelta.x * (p.y - pStart.y) - pDelta.y * (p.x - pStart.x)
}

func classify(seg: Seg, partStart: Vec2, partDelta: Vec2) -> SegSide {
    let eps = 1e-4
    let d1 = sideOf(seg.v1, pStart: partStart, pDelta: partDelta)
    let d2 = sideOf(seg.v2, pStart: partStart, pDelta: partDelta)
    let s1 = d1 > eps ? 1 : (d1 < -eps ? -1 : 0)
    let s2 = d2 > eps ? 1 : (d2 < -eps ? -1 : 0)
    if s1 == 0 && s2 == 0 { return .collinear }
    if s1 >= 0 && s2 >= 0 { return .left }
    if s1 <= 0 && s2 <= 0 { return .right }
    let t = d1 / (d1 - d2)
    let ix = seg.v1.x + t * (seg.v2.x - seg.v1.x)
    let iy = seg.v1.y + t * (seg.v2.y - seg.v1.y)
    return .straddle(Vec2(x: ix, y: iy))
}

func buildBSP(_ segs: [Seg]) -> BSPNode {
    guard segs.count > 1 else {
        return .leaf(segs: segs, sector: segs.first?.frontSector ?? 0)
    }
    // Pick the partition that keeps both sides populated and minimizes splits.
    var bestIdx = -1
    var bestScore = Int.max
    for i in 0 ..< segs.count {
        let pStart = segs[i].v1
        let pDelta = Vec2(x: segs[i].v2.x - segs[i].v1.x, y: segs[i].v2.y - segs[i].v1.y)
        var l = 0, r = 0, s = 0
        for j in 0 ..< segs.count where j != i {
            switch classify(seg: segs[j], partStart: pStart, partDelta: pDelta) {
            case .left: l += 1
            case .right: r += 1
            case .straddle: s += 1
            case .collinear: break
            }
        }
        if l == 0 || r == 0 { continue }
        let score = abs(l - r) + 2 * s
        if score < bestScore {
            bestScore = score
            bestIdx = i
        }
    }
    if bestIdx == -1 {
        // Convex enough — stop.
        return .leaf(segs: segs, sector: segs.first?.frontSector ?? 0)
    }
    let part = segs[bestIdx]
    let pStart = part.v1
    let pDelta = Vec2(x: part.v2.x - part.v1.x, y: part.v2.y - part.v1.y)
    var leftSegs: [Seg] = []
    var rightSegs: [Seg] = [part]
    for j in 0 ..< segs.count where j != bestIdx {
        let seg = segs[j]
        switch classify(seg: seg, partStart: pStart, partDelta: pDelta) {
        case .left:
            leftSegs.append(seg)
        case .right, .collinear:
            rightSegs.append(seg)
        case .straddle(let ix):
            let a = Seg(v1: seg.v1, v2: ix, frontSector: seg.frontSector, backSector: seg.backSector, lineDefIndex: seg.lineDefIndex)
            let b = Seg(v1: ix, v2: seg.v2, frontSector: seg.frontSector, backSector: seg.backSector, lineDefIndex: seg.lineDefIndex)
            if case .left = classify(seg: a, partStart: pStart, partDelta: pDelta) { leftSegs.append(a) } else { rightSegs.append(a) }
            if case .left = classify(seg: b, partStart: pStart, partDelta: pDelta) { leftSegs.append(b) } else { rightSegs.append(b) }
        }
    }
    return .node(
        pStart: pStart,
        pDelta: pDelta,
        left: buildBSP(leftSegs),
        right: buildBSP(rightSegs)
    )
}

func generateSegs() -> [Seg] {
    var out: [Seg] = []
    for (i, l) in linedefs.enumerated() {
        let a = vertices[l.v1]
        let b = vertices[l.v2]
        out.append(Seg(v1: a, v2: b, frontSector: l.frontSector, backSector: l.backSector, lineDefIndex: i))
        if let back = l.backSector {
            out.append(Seg(v1: b, v2: a, frontSector: back, backSector: l.frontSector, lineDefIndex: i))
        }
    }
    return out
}

func findSector(pos: Vec2, node: BSPNode) -> Int {
    switch node {
    case .leaf(_, let sector):
        return sector
    case .node(let pStart, let pDelta, let left, let right):
        return sideOf(pos, pStart: pStart, pDelta: pDelta) >= 0
            ? findSector(pos: pos, node: left)
            : findSector(pos: pos, node: right)
    }
}

func traverseBSP(_ node: BSPNode, player: Vec2, visit: (Seg) -> Void) {
    switch node {
    case .leaf(let segs, _):
        for s in segs { visit(s) }
    case .node(let pStart, let pDelta, let left, let right):
        let d = sideOf(player, pStart: pStart, pDelta: pDelta)
        if d >= 0 {
            traverseBSP(left, player: player, visit: visit)
            traverseBSP(right, player: player, visit: visit)
        } else {
            traverseBSP(right, player: player, visit: visit)
            traverseBSP(left, player: player, visit: visit)
        }
    }
}

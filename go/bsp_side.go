package main

// Binary Space Partition — node type and the geometric primitive that
// classifies a seg against a candidate partition line.
//
// A BSP recursively splits the map's plane into two half-spaces with a chosen
// partition line ("seg"). Internal nodes hold the partition; leaves hold a
// convex bag of segs that all live in a single sector. The point of the BSP
// at render time is twofold:
//
//   1. findSector(pos) descends the tree once and returns the leaf sector
//      the player is currently standing in — O(depth), no per-tick search.
//   2. traverseBSP(playerPos, visit) yields segs front-to-back, which lets
//      the per-column clip arrays (yTop/yBot) terminate occluded columns
//      without ever needing a depth buffer.

// BSPNode is either a leaf (segs + sector) or an internal node (partition
// line + left/right children). Swift's `indirect enum BSPNode` translates
// here as a tagged struct with pointer children — Go would otherwise give us
// a recursive value type of infinite size.
type BSPNode struct {
	leaf   bool
	segs   []Seg // leaf only: segs in this convex region
	sector int   // leaf only: sector all those segs front onto

	pStart, pDelta Vec2     // internal only: partition line as point + direction
	left, right    *BSPNode // internal only: children. left = "front" of pDelta.
}

// SegSide is the result of testing a single seg against a partition line.
type SegSide int

const (
	SideLeft      SegSide = iota // both endpoints in left half-space
	SideRight                    // both endpoints in right half-space
	SideStraddle                 // crosses the line — split at intersection
	SideCollinear                // both endpoints lie on the line
)

// sideOf returns the signed perp-product of (p - pStart) against pDelta.
// Sign convention:  positive → p is to the LEFT of the directed partition,
//                   negative → p is to the RIGHT,
//                   zero    → on the line.
//
// "Left" is arbitrary but consistent — generateSegs() and the back-face cull
// rely on the same sign.
func sideOf(p, pStart, pDelta Vec2) float64 {
	return pDelta.x*(p.y-pStart.y) - pDelta.y*(p.x-pStart.x)
}

// classify tests a seg against a partition line and reports which side it
// falls on. For SideStraddle, it also returns the world-space intersection
// point so the BSP builder can split the seg there.
//
// The eps tolerance keeps endpoints that are *exactly* on the partition (or
// within a sliver of it) from being treated as straddles, which would cause
// pointless hairline splits.
func classify(seg Seg, partStart, partDelta Vec2) (SegSide, Vec2) {
	const eps = 1e-4
	d1 := sideOf(seg.v1, partStart, partDelta)
	d2 := sideOf(seg.v2, partStart, partDelta)

	// Tri-state per endpoint: -1 right, 0 on-line, +1 left.
	s1 := 0
	if d1 > eps {
		s1 = 1
	} else if d1 < -eps {
		s1 = -1
	}
	s2 := 0
	if d2 > eps {
		s2 = 1
	} else if d2 < -eps {
		s2 = -1
	}

	if s1 == 0 && s2 == 0 {
		return SideCollinear, Vec2{}
	}
	if s1 >= 0 && s2 >= 0 {
		return SideLeft, Vec2{}
	}
	if s1 <= 0 && s2 <= 0 {
		return SideRight, Vec2{}
	}
	// Linear interpolation along the seg to find where d crosses zero.
	t := d1 / (d1 - d2)
	ix := seg.v1.x + t*(seg.v2.x-seg.v1.x)
	iy := seg.v1.y + t*(seg.v2.y-seg.v1.y)
	return SideStraddle, Vec2{ix, iy}
}

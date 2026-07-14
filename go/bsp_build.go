package main

import "math"

// BSP wraps a built partition tree with the two query methods the rest of the
// engine needs. It holds the *Level so FindSector can resolve seg sectors and
// callers don't have to thread the level separately.
type BSP struct {
	root  bspNode
	level *Level
}

// NewBSP builds a balanced-ish BSP over the level's segs.
func NewBSP(level *Level) *BSP {
	return &BSP{root: buildBSP(level.generateSegs()), level: level}
}

// FindSector descends the tree to the leaf containing pos and returns its
// sector index. Used both per-tick (player's current sector for HUD + floor
// height) and inside player.Update for collision step-up checks.
func (b *BSP) FindSector(pos Vec2) int {
	return findSector(pos, b.root)
}

// Traverse walks the tree front-to-back from `from` and invokes `visit` on
// every seg in order.
func (b *BSP) Traverse(from Vec2, visit func(Seg)) {
	traverseBSP(b.root, from, visit)
}

// buildBSP constructs a BSP tree from a flat slice of segs. It runs once at
// startup. The recursion ends in two ways:
//
//   - <= 1 seg left: trivial leaf.
//   - No partition can split the remaining segs into two non-empty sides:
//     the region is convex enough that any further split would just produce
//     a one-sided cut. Stop and store the segs as a leaf.
//
// Partition selection is greedy: try every seg as a candidate, score it by
// how unbalanced it leaves the two children plus a heavy 2× weight on
// straddle splits (because each straddle costs us a seg duplication), and
// pick the lowest score. This is small-map-grade quality, not a serious BSP
// builder, but it's deterministic and produces clean trees on the test map.
func buildBSP(segs []Seg) bspNode {
	if len(segs) <= 1 {
		sec := 0
		if len(segs) > 0 {
			sec = segs[0].frontSector
		}
		return &bspLeaf{segs: segs, sector: sec}
	}

	bestIdx := -1
	bestScore := math.MaxInt
	for i := 0; i < len(segs); i++ {
		pStart := segs[i].v1
		pDelta := Vec2{segs[i].v2.x - segs[i].v1.x, segs[i].v2.y - segs[i].v1.y}
		var l, r, s int
		for j := 0; j < len(segs); j++ {
			if j == i {
				continue
			}
			side, _ := classify(segs[j], pStart, pDelta)
			switch side {
			case SideLeft:
				l++
			case SideRight:
				r++
			case SideStraddle:
				s++
			}
			// Collinear segs are ignored for scoring — they get assigned to a
			// side later based on direction agreement.
		}
		// Reject candidates that don't actually partition (one side empty).
		// This is what causes recursion to terminate inside convex regions.
		if l == 0 || r == 0 {
			continue
		}
		score := abs(l-r) + 2*s
		if score < bestScore {
			bestScore = score
			bestIdx = i
		}
	}

	if bestIdx == -1 {
		// Convex enough — every candidate leaves one side empty.
		return &bspLeaf{segs: segs, sector: segs[0].frontSector}
	}

	// Distribute the remaining segs across the two children.
	part := segs[bestIdx]
	pStart := part.v1
	pDelta := Vec2{part.v2.x - part.v1.x, part.v2.y - part.v1.y}

	// The partition seg itself goes on the LEFT (front) side, so traversal
	// emits it before the back side from the player's perspective.
	leftSegs := []Seg{part}
	var rightSegs []Seg

	for j, seg := range segs {
		if j == bestIdx {
			continue
		}
		side, ix := classify(seg, pStart, pDelta)
		switch side {
		case SideLeft:
			leftSegs = append(leftSegs, seg)
		case SideRight:
			rightSegs = append(rightSegs, seg)
		case SideCollinear:
			// Same direction as the partition → front side; opposite → back.
			// Without this rule, collinear segs would all stack on one side
			// and possibly hide back-side rendering.
			sdx := seg.v2.x - seg.v1.x
			sdy := seg.v2.y - seg.v1.y
			if pDelta.x*sdx+pDelta.y*sdy >= 0 {
				leftSegs = append(leftSegs, seg)
			} else {
				rightSegs = append(rightSegs, seg)
			}
		case SideStraddle:
			// Cut the seg in two at the intersection point and re-classify
			// each half. Each half should now land cleanly on one side.
			a := Seg{v1: seg.v1, v2: ix, frontSector: seg.frontSector, backSector: seg.backSector, lineDefIndex: seg.lineDefIndex}
			b := Seg{v1: ix, v2: seg.v2, frontSector: seg.frontSector, backSector: seg.backSector, lineDefIndex: seg.lineDefIndex}
			if sa, _ := classify(a, pStart, pDelta); sa == SideLeft {
				leftSegs = append(leftSegs, a)
			} else {
				rightSegs = append(rightSegs, a)
			}
			if sb, _ := classify(b, pStart, pDelta); sb == SideLeft {
				leftSegs = append(leftSegs, b)
			} else {
				rightSegs = append(rightSegs, b)
			}
		}
	}

	return &bspBranch{
		pStart: pStart,
		pDelta: pDelta,
		left:   buildBSP(leftSegs),
		right:  buildBSP(rightSegs),
	}
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

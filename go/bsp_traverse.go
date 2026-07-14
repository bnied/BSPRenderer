package main

// generateSegs flattens the linedef list into the seg list that the BSP
// builder will consume.
//
// One-sided linedefs produce ONE seg in their authored direction (front-side
// only, because the back is solid and never visible).
//
// Two-sided linedefs produce TWO segs — the second one runs in reverse and
// has its front/back sectors swapped. The BSP needs both because each side
// of a portal will be rasterized from its own sector during traversal, with
// its own ceiling/floor heights and per-sector light level.
func (l *Level) generateSegs() []Seg {
	out := make([]Seg, 0, len(l.linedefs)*2)
	for i, ld := range l.linedefs {
		a := l.vertices[ld.v1]
		b := l.vertices[ld.v2]
		// Authored direction (front side).
		out = append(out, Seg{
			v1: a, v2: b,
			frontSector:  ld.frontSector,
			backSector:   ld.backSector,
			lineDefIndex: i,
		})
		// Reverse direction (back side) for two-sided linedefs.
		if ld.backSector != noSector {
			out = append(out, Seg{
				v1: b, v2: a,
				frontSector:  ld.backSector,
				backSector:   ld.frontSector,
				lineDefIndex: i,
			})
		}
	}
	return out
}

// findSector descends the BSP tree to the leaf containing pos and returns its
// sector index. The type switch makes leaf-only vs branch-only field access
// impossible. Used both per-tick (player's current sector for HUD + floor
// height) and inside player.Update for collision step-up checks.
func findSector(pos Vec2, node bspNode) int {
	switch n := node.(type) {
	case *bspLeaf:
		return n.sector
	case *bspBranch:
		if sideOf(pos, n.pStart, n.pDelta) >= 0 {
			return findSector(pos, n.left)
		}
		return findSector(pos, n.right)
	default:
		panic("unreachable: unknown bspNode")
	}
}

// traverseBSP walks the tree front-to-back from the player's position and
// invokes `visit` on every seg in order. Going front-first is what makes the
// per-column clip arrays (yTop/yBot) work as a no-op depth buffer — by the
// time we reach a far-away seg, columns it would have covered are already
// closed off.
//
// "Front" depends on which side of each partition the player is on, so we
// recurse into the player's side first, then the opposite side.
func traverseBSP(node bspNode, player Vec2, visit func(Seg)) {
	switch n := node.(type) {
	case *bspLeaf:
		for _, s := range n.segs {
			visit(s)
		}
	case *bspBranch:
		if sideOf(player, n.pStart, n.pDelta) >= 0 {
			traverseBSP(n.left, player, visit)
			traverseBSP(n.right, player, visit)
		} else {
			traverseBSP(n.right, player, visit)
			traverseBSP(n.left, player, visit)
		}
	default:
		panic("unreachable: unknown bspNode")
	}
}

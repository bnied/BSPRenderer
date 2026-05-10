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
func generateSegs() []Seg {
	out := make([]Seg, 0, len(linedefs)*2)
	for i, l := range linedefs {
		a := vertices[l.v1]
		b := vertices[l.v2]
		// Authored direction (front side).
		out = append(out, Seg{
			v1: a, v2: b,
			frontSector:  l.frontSector,
			backSector:   l.backSector,
			lineDefIndex: i,
		})
		// Reverse direction (back side) for two-sided linedefs.
		if l.backSector != noSector {
			out = append(out, Seg{
				v1: b, v2: a,
				frontSector:  l.backSector,
				backSector:   l.frontSector,
				lineDefIndex: i,
			})
		}
	}
	return out
}

// findSector descends the BSP tree to the leaf containing pos and returns its
// sector index. Used both per-tick (player's current sector for HUD + floor
// height) and inside player.Update for collision step-up checks.
func findSector(pos Vec2, node *BSPNode) int {
	if node.leaf {
		return node.sector
	}
	if sideOf(pos, node.pStart, node.pDelta) >= 0 {
		return findSector(pos, node.left)
	}
	return findSector(pos, node.right)
}

// traverseBSP walks the tree front-to-back from the player's position and
// invokes `visit` on every seg in order. Going front-first is what makes the
// per-column clip arrays (yTop/yBot) work as a no-op depth buffer — by the
// time we reach a far-away seg, columns it would have covered are already
// closed off.
//
// "Front" depends on which side of each partition the player is on, so we
// recurse into the player's side first, then the opposite side.
func traverseBSP(node *BSPNode, player Vec2, visit func(Seg)) {
	if node.leaf {
		for _, s := range node.segs {
			visit(s)
		}
		return
	}
	if sideOf(player, node.pStart, node.pDelta) >= 0 {
		traverseBSP(node.left, player, visit)
		traverseBSP(node.right, player, visit)
	} else {
		traverseBSP(node.right, player, visit)
		traverseBSP(node.left, player, visit)
	}
}

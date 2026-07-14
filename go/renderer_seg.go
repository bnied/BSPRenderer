package main

import "math"

// drawSeg is the per-seg rasterizer and the engine's single most complex
// function. Once per visible seg, in BSP front-to-back order, it:
//
//   1. Back-face culls (only render segs whose front sector faces us).
//   2. Transforms both endpoints from world space into view space, where
//      forward is +d (depth) and right is +r.
//   3. Clips the seg against the near plane and the left/right frustum
//      planes (each a simple inequality on r ± k*d). Anything fully outside
//      a plane returns early; otherwise the offending endpoint slides along
//      the seg to the plane.
//   4. Projects the clipped endpoints to screen X.
//   5. For each screen column from xStart to xEnd:
//        a. Skip columns the column-clip arrays say are fully occluded.
//        b. Linearly interpolate 1/d (perspective-correct) to find depth.
//        c. Compute the projected ceiling-Y and floor-Y for this column,
//           which together define the open vertical "slot" for this seg.
//        d. Above the ceiling and below the floor: extend the corresponding
//           sector's visplane spans (deferred — see renderer_visplanes.go).
//        e. If the seg is solid: fill the slot with the wall color and mark
//           the column fully occluded so nothing further draws there.
//        f. If the seg is a portal: optionally draw an upper-wall sliver
//           (back ceiling lower than front) and/or a lower-wall sliver (back
//           floor higher than front), then narrow yTop/yBot to the back
//           sector's open range so subsequent farther geometry only paints
//           inside that opening.
//
// All the per-column lighting is a simple distance falloff: 1/(1+d*0.004),
// scaled by the front sector's authored light level and clamped to a 0.15
// floor so far walls don't go pure black.
func (r *Renderer) drawSeg(seg Seg,
	p *Player,
	cosA, sinA, halfW, horizon, fovHalfTan, focal, eyeZ float64) {

	// Back-face cull. The seg's outward normal is (-sdy, sdx) — a 90° CCW
	// rotation of the seg's direction. If the player is on the wrong side
	// of that normal, this seg's "front" is facing away from us.
	sdx := seg.v2.x - seg.v1.x
	sdy := seg.v2.y - seg.v1.y
	nx := -sdy
	ny := sdx
	toPx := p.pos.x - seg.v1.x
	toPy := p.pos.y - seg.v1.y
	if nx*toPx+ny*toPy <= 0 {
		return
	}

	// World → view space. With the player at the origin facing along the
	// +x view axis, an offset (dx, dy) in world maps to:
	//   r = -dx*sinA + dy*cosA   (right axis: + = right of the view ray)
	//   d =  dx*cosA + dy*sinA   (forward axis: + = in front of the eye)
	rx1 := seg.v1.x - p.pos.x
	ry1 := seg.v1.y - p.pos.y
	rx2 := seg.v2.x - p.pos.x
	ry2 := seg.v2.y - p.pos.y
	r1 := -rx1*sinA + ry1*cosA
	d1 := rx1*cosA + ry1*sinA
	r2 := -rx2*sinA + ry2*cosA
	d2 := rx2*cosA + ry2*sinA

	// Near-plane clip. Anything entirely behind d=near disappears; otherwise
	// the offending endpoint slides forward along the seg until d == near.
	const near = 1.0
	if d1 < near && d2 < near {
		return
	}
	if d1 < near {
		t := (near - d1) / (d2 - d1)
		r1 = r1 + t*(r2-r1)
		d1 = near
	} else if d2 < near {
		t := (near - d2) / (d1 - d2)
		r2 = r2 + t*(r1-r2)
		d2 = near
	}

	// Left frustum (r + k*d >= 0).
	k := fovHalfTan
	lD1 := r1 + k*d1
	lD2 := r2 + k*d2
	if lD1 < 0 && lD2 < 0 {
		return
	}
	if lD1 < 0 {
		t := lD1 / (lD1 - lD2)
		r1 = r1 + t*(r2-r1)
		d1 = d1 + t*(d2-d1)
	} else if lD2 < 0 {
		t := lD2 / (lD2 - lD1)
		r2 = r2 + t*(r1-r2)
		d2 = d2 + t*(d1-d2)
	}

	// Right frustum (k*d - r >= 0).
	rD1 := k*d1 - r1
	rD2 := k*d2 - r2
	if rD1 < 0 && rD2 < 0 {
		return
	}
	if rD1 < 0 {
		t := rD1 / (rD1 - rD2)
		r1 = r1 + t*(r2-r1)
		d1 = d1 + t*(d2-d1)
	} else if rD2 < 0 {
		t := rD2 / (rD2 - rD1)
		r2 = r2 + t*(r1-r2)
		d2 = d2 + t*(d1-d2)
	}

	// Pinhole projection to screen X. After culling and clipping we know
	// d > 0 for both endpoints, so the divide is safe and produces a column
	// inside [0, bufW). Reject zero-width slivers — the per-column loop
	// below would divide by 0 when interpolating.
	sx1 := halfW + (r1/d1)*focal
	sx2 := halfW + (r2/d2)*focal
	if sx2 <= sx1+0.0001 {
		return
	}

	xStart := int(math.Ceil(sx1))
	if xStart < 0 {
		xStart = 0
	}
	xEnd := int(math.Floor(sx2))
	if xEnd > r.bufW-1 {
		xEnd = r.bufW - 1
	}
	if xStart > xEnd {
		return
	}

	// Wall heights are stored as world Z; what matters for projection is the
	// signed distance from the eye, so we precompute (sectorZ - eyeZ).
	front := r.level.sector(seg.frontSector)
	fCeil := front.ceilH - eyeZ
	fFloor := front.floorH - eyeZ
	var bCeil, bFloor float64
	if seg.backSector != noSector {
		back := r.level.sector(seg.backSector)
		bCeil = back.ceilH - eyeZ
		bFloor = back.floorH - eyeZ
	}

	lineDef := r.level.linedefs[seg.lineDefIndex]
	frontLight := front.light

	// Perspective-correct interpolation: linear in 1/d across screen X, not
	// in d itself. Ceiling/floor screen Y at column x is then
	//   y = horizon - (sectorZ - eyeZ) * focal * (1/d)
	// which is linear in 1/d for a fixed sectorZ, so we only need one
	// interpolation per column instead of two.
	invD1 := 1.0 / d1
	invD2 := 1.0 / d2
	dx := sx2 - sx1

	for x := xStart; x <= xEnd; x++ {
		if r.slowMode {
			if r.slowColumnBudget <= 0 {
				return
			}
			r.slowColumnBudget--
		}
		if r.yTop[x] > r.yBot[x] {
			continue
		}
		tLin := (float64(x) - sx1) / dx
		invD := (1.0-tLin)*invD1 + tLin*invD2
		depth := 1.0 / invD

		falloff := 1.0 / (1.0 + depth*0.004)
		light := clampF(frontLight*falloff, 0.15, 1.0)

		ceilY := int(math.Round(horizon - fCeil*focal*invD))
		floorY := int(math.Round(horizon - fFloor*focal*invD))

		top := r.yTop[x]
		bot := r.yBot[x]

		// Ceiling visplane span.
		if ceilY > top {
			yLo := top
			yHi := ceilY - 1
			if yHi > bot {
				yHi = bot
			}
			r.visplanes[seg.frontSector*2+1].Extend(x, yLo, yHi)
		}
		// Floor visplane span.
		if floorY < bot {
			yLo := floorY + 1
			if yLo < top {
				yLo = top
			}
			yHi := bot
			r.visplanes[seg.frontSector*2].Extend(x, yLo, yHi)
		}

		if seg.backSector == noSector {
			// Solid wall.
			yLo := ceilY
			if yLo < top {
				yLo = top
			}
			yHi := floorY
			if yHi > bot {
				yHi = bot
			}
			r.fillColumn(x, yLo, yHi, shade(lineDef.wallColor, light))
			r.yTop[x] = bot + 1 // mark fully occluded
		} else {
			backCeilY := int(math.Round(horizon - bCeil*focal*invD))
			backFloorY := int(math.Round(horizon - bFloor*focal*invD))

			// Upper wall.
			newTop := ceilY
			if newTop < top {
				newTop = top
			}
			if backCeilY > ceilY {
				yLo := ceilY
				if yLo < top {
					yLo = top
				}
				yHi := backCeilY - 1
				if yHi > bot {
					yHi = bot
				}
				r.fillColumn(x, yLo, yHi, shade(lineDef.upperColor, light))
				newTop = backCeilY
				if newTop < top {
					newTop = top
				}
			}

			// Lower wall.
			newBot := floorY
			if newBot > bot {
				newBot = bot
			}
			if backFloorY < floorY {
				yLo := backFloorY + 1
				if yLo < top {
					yLo = top
				}
				yHi := floorY
				if yHi > bot {
					yHi = bot
				}
				r.fillColumn(x, yLo, yHi, shade(lineDef.lowerColor, light))
				newBot = backFloorY
				if newBot > bot {
					newBot = bot
				}
			}

			r.yTop[x] = newTop
			r.yBot[x] = newBot
			if r.yTop[x] > r.yBot[x] {
				r.yTop[x] = r.yBot[x] + 1
			}
		}
	}
}

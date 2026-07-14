package main

// renderVisplanes is the deferred second pass of the renderer.
//
// During the BSP walk, drawSeg never colors floor or ceiling pixels directly:
// it only records per-column spans (yLo..yHi) into the appropriate sector's
// floor or ceiling Visplane. After the walk, every visplane that received any
// coverage is rasterized scanline-by-scanline using fillPlaneColumn.
//
// This is what lets multiple sectors' floors and ceilings composite correctly
// without a depth buffer — each visplane only knows about the columns it owns,
// and the column-clip arrays (yTop / yBot) maintained by drawSeg made sure no
// two planes can claim the same pixel.
func (r *Renderer) renderVisplanes(focal, halfW, horizon float64,
	playerPos Vec2, cosA, sinA float64, eyeZ float64) {

	for pi := range r.visplanes {
		plane := &r.visplanes[pi]
		if plane.maxX < plane.minX {
			continue // never written this frame
		}
		sec := r.level.sector(plane.sectorIndex)

		var planeZ float64
		var color RGBA
		if plane.isCeiling {
			planeZ = sec.ceilH
			color = sec.ceilColor
		} else {
			planeZ = sec.floorH
			color = sec.floorColor
		}
		planeHeight := planeZ - eyeZ // signed: + above eye, - below

		for x := plane.minX; x <= plane.maxX; x++ {
			yLo := plane.top[x]
			yHi := plane.bot[x]
			if yLo > yHi {
				continue
			}
			r.fillPlaneColumn(x, yLo, yHi,
				planeHeight, focal, halfW, horizon,
				playerPos, cosA, sinA,
				sec.light, color)
		}
	}
}

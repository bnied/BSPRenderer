package main

import "math"

// Renderer owns the per-frame state for the software renderer:
//
//   pixels        — RGBA framebuffer in row-major order (4 bytes/pixel,
//                   no padding). The Game layer hands this directly to
//                   ebiten.Image.WritePixels each frame.
//   yTop / yBot   — DOOM's ceilingclip / floorclip arrays. For each screen
//                   column they bound the still-open vertical range. Solid
//                   walls close their columns entirely; portals shrink the
//                   open range by their upper/lower walls.
//   visplanes     — 2 entries per sector (floor at 2*si, ceiling at 2*si+1).
//                   See visplane.go.
//   slowMode etc. — debug aid: when enabled (Tab), each frame draws one more
//                   column than the previous one, so you can watch the BSP
//                   walk emit columns left-to-right (or front-to-back from
//                   the player's perspective).
type Renderer struct {
	level      *Level
	bufW, bufH int
	pixels     []uint8
	yTop, yBot []int
	visplanes  []Visplane

	slowMode         bool
	slowStep         int
	slowColumnBudget int
}

func NewRenderer(level *Level, width, height int) *Renderer {
	r := &Renderer{
		level:  level,
		bufW:   width,
		bufH:   height,
		pixels: make([]uint8, width*height*4),
		yTop:   make([]int, width),
		yBot:   make([]int, width),
	}
	for si := range level.sectors {
		r.visplanes = append(r.visplanes,
			NewVisplane(si, false, width), // floor at 2*si
			NewVisplane(si, true, width))  // ceiling at 2*si+1
	}
	return r
}

// Render runs one full frame of the renderer:
//
//   1. Reset per-column open region and per-frame visplane coverage.
//   2. Background fill (dim ceiling/floor of the player's current sector)
//      so any column that somehow ends up unwritten still looks plausible.
//   3. BSP walk → drawSeg for every visible seg, front-to-back.
//   4. Visplane pass → flat floors/ceilings rasterized with inverse
//      projection + checkerboard texture.
//   5. Overlays: minimap and crosshair.
func (r *Renderer) Render(p *Player, bsp *BSP) {
	for x := 0; x < r.bufW; x++ {
		r.yTop[x] = 0
		r.yBot[x] = r.bufH - 1
	}
	for i := range r.visplanes {
		r.visplanes[i].Reset()
	}

	playerSector := bsp.FindSector(p.pos)
	sec := r.level.sector(playerSector)
	halfW := float64(r.bufW) / 2.0
	halfH := float64(r.bufH) / 2.0
	horizon := halfH

	// Background fill — top half = sector ceiling, bottom half = sector
	// floor, both dimmed so legitimate geometry still reads as brighter.
	for y := 0; y < r.bufH; y++ {
		var c RGBA
		if y < r.bufH/2 {
			c = sec.ceilColor
		} else {
			c = sec.floorColor
		}
		dc := shade(c, 0.55)
		rowStart := y * r.bufW * 4
		for x := 0; x < r.bufW; x++ {
			i := rowStart + x*4
			r.pixels[i] = dc.r
			r.pixels[i+1] = dc.g
			r.pixels[i+2] = dc.b
			r.pixels[i+3] = 255
		}
	}

	// Pinhole camera setup. focal = halfW / tan(fov/2) gives us the standard
	// "screen plane is `focal` units in front of the eye" projection.
	fovHalfTan := math.Tan(p.fov / 2.0)
	focal := halfW / fovHalfTan
	eyeZ := p.EyeZ()
	cosA := math.Cos(p.angle)
	sinA := math.Sin(p.angle)

	drawOne := func(seg Seg) {
		r.drawSeg(seg, p, cosA, sinA, halfW, horizon, fovHalfTan, focal, eyeZ)
	}

	if r.slowMode {
		// Buffered traversal so we can stop drawing after `slowStep` columns.
		var segs []Seg
		bsp.Traverse(p.pos, func(s Seg) { segs = append(segs, s) })
		r.slowColumnBudget = r.slowStep
		for _, s := range segs {
			drawOne(s)
		}
		// If budget wasn't exhausted, the whole frame fit; loop back to 0.
		if r.slowColumnBudget > 0 {
			r.slowStep = 0
		} else {
			r.slowStep++
		}
	} else {
		bsp.Traverse(p.pos, drawOne)
	}

	r.renderVisplanes(focal, halfW, horizon, p.pos, cosA, sinA, eyeZ)
	r.drawMinimap(p)
	r.drawCrosshair()
}

// putPixel writes one bounds-checked pixel — used by overlays. The hot inner
// loops in drawSeg / fillPlaneColumn skip the bounds check because they
// pre-clip x/y to the buffer.
func (r *Renderer) putPixel(x, y int, c RGBA) {
	if x < 0 || x >= r.bufW || y < 0 || y >= r.bufH {
		return
	}
	i := (y*r.bufW + x) * 4
	r.pixels[i] = c.r
	r.pixels[i+1] = c.g
	r.pixels[i+2] = c.b
	r.pixels[i+3] = c.a
}

// fillColumn paints a vertical span of column x with a solid color.
// Used by drawSeg for solid walls and upper/lower portal walls.
func (r *Renderer) fillColumn(x, yLo, yHi int, c RGBA) {
	if yLo > yHi {
		return
	}
	if yLo < 0 {
		yLo = 0
	}
	if yHi >= r.bufH {
		yHi = r.bufH - 1
	}
	i := (yLo*r.bufW + x) * 4
	stride := r.bufW * 4
	for y := yLo; y <= yHi; y++ {
		r.pixels[i] = c.r
		r.pixels[i+1] = c.g
		r.pixels[i+2] = c.b
		r.pixels[i+3] = 255
		i += stride
	}
}

package main

import "math"

// drawCrosshair draws a small white "X" centered on the screen.
func (r *Renderer) drawCrosshair() {
	cx, cy := r.bufW/2, r.bufH/2
	col := RGBA{255, 255, 255, 255}
	for d := -3; d <= 3; d++ {
		if d == 0 {
			continue
		}
		r.putPixel(cx+d, cy, col)
		r.putPixel(cx, cy+d, col)
	}
}

// drawMinimap draws a top-down preview of the level into the upper-left
// corner: dark backdrop, all linedefs (one-sided in their wall color, two-
// sided in gray), and a player marker with a heading line.
func (r *Renderer) drawMinimap(p *Player) {
	// Auto-fit the map bounds into a fixed minimap box.
	minX, minY := math.Inf(1), math.Inf(1)
	maxX, maxY := math.Inf(-1), math.Inf(-1)
	for _, v := range vertices {
		if v.x < minX {
			minX = v.x
		}
		if v.y < minY {
			minY = v.y
		}
		if v.x > maxX {
			maxX = v.x
		}
		if v.y > maxY {
			maxY = v.y
		}
	}
	const pad = 8.0
	const boxW = 120.0
	const boxH = 100.0
	const ox = 8.0
	const oy = 8.0
	sx := boxW / (maxX - minX + 2*pad)
	sy := boxH / (maxY - minY + 2*pad)
	s := math.Min(sx, sy)

	project := func(v Vec2) (int, int) {
		return int(ox + ((v.x-minX)+pad)*s),
			int(oy + ((v.y-minY)+pad)*s)
	}

	// Backdrop.
	for y := int(oy - 2); y <= int(oy+boxH+2); y++ {
		for x := int(ox - 2); x <= int(ox+boxW+2); x++ {
			r.putPixel(x, y, RGBA{10, 10, 14, 255})
		}
	}

	// Linedefs.
	for _, l := range linedefs {
		ax, ay := project(vertices[l.v1])
		bx, by := project(vertices[l.v2])
		col := RGBA{120, 120, 120, 255}
		if l.backSector == noSector {
			col = l.wallColor
		}
		r.drawLine(ax, ay, bx, by, col)
	}

	// Player.
	pxI, pyI := project(p.pos)
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			r.putPixel(pxI+dx, pyI+dy, RGBA{255, 255, 255, 255})
		}
	}
	hx := pxI + int(math.Cos(p.angle)*10)
	hy := pyI + int(math.Sin(p.angle)*10)
	r.drawLine(pxI, pyI, hx, hy, RGBA{255, 255, 255, 255})
}

// drawLine is a standard integer Bresenham line, with bounds-checked plotting
// done by putPixel.
func (r *Renderer) drawLine(x0, y0, x1, y1 int, color RGBA) {
	dx := x1 - x0
	if dx < 0 {
		dx = -dx
	}
	sx := 1
	if x0 >= x1 {
		sx = -1
	}
	dy := y1 - y0
	if dy < 0 {
		dy = -dy
	}
	dy = -dy
	sy := 1
	if y0 >= y1 {
		sy = -1
	}
	err := dx + dy
	for {
		r.putPixel(x0, y0, color)
		if x0 == x1 && y0 == y1 {
			return
		}
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			x0 += sx
		}
		if e2 <= dx {
			err += dx
			y0 += sy
		}
	}
}

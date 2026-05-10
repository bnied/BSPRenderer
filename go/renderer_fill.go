package main

import "math"

// fillPlaneColumn rasterizes a vertical strip of a single floor or ceiling
// plane. The plane is horizontal in world space — every pixel in the strip
// belongs to the same world Z (sector floorH or ceilH). For each screen pixel
// we inverse-project to the world (X, Y) it represents, sample a procedural
// 16-unit checkerboard there, and apply distance-based shading.
//
// `planeHeight` is the signed world-Z difference (planeZ - eyeZ): positive for
// ceilings (above eye), negative for floors (below). Only its magnitude
// matters for depth, but the sign matters for which screen y's the column
// covers (handled by the caller's choice of yLo/yHi).
func (r *Renderer) fillPlaneColumn(x, yLo, yHi int,
	planeHeight, focal, halfW, horizon float64,
	playerPos Vec2, cosA, sinA float64,
	sectorLight float64,
	color RGBA) {

	if yLo > yHi {
		return
	}

	// |planeHeight| is what the perspective math actually uses to recover depth.
	absH := math.Abs(planeHeight)
	xOffset := float64(x) - halfW

	// Precompute the dark-tile color once per column rather than per pixel.
	darkColor := RGBA{
		r: uint8(float64(color.r) * 0.7),
		g: uint8(float64(color.g) * 0.7),
		b: uint8(float64(color.b) * 0.7),
		a: 255,
	}

	// Tile size = 1 << tileBits world units. tileBias keeps the integer
	// world coordinates positive so the parity test (tx ^ ty) & 1 is stable
	// across the origin (otherwise -1 >> 4 != +1 >> 4 in awkward ways).
	const tileBits = 4
	const tileBias = 1 << 20

	i := (yLo*r.bufW + x) * 4
	stride := r.bufW * 4

	for y := yLo; y <= yHi; y++ {
		// Pinhole inverse projection. The projected screen-y of a horizontal
		// plane at signed height h is:  sy = horizon - h * focal / depth
		// Solve for depth:              depth = |h| * focal / |sy - horizon|
		absDy := math.Abs(float64(y) - horizon)
		var depth float64
		if absDy > 0.0001 {
			depth = absH * focal / absDy
		} else {
			depth = 1e9 // pixel exactly on the horizon — push to "infinity"
		}

		// View-space right offset for this pixel at this depth.
		// (For a pinhole camera, screen_x = halfW + (right/forward) * focal.)
		right := xOffset * depth / focal

		// Rotate from camera space (forward, right) into world space.
		// forward = (cosA, sinA); right axis = (-sinA, cosA).
		wx := playerPos.x + depth*cosA - right*sinA
		wy := playerPos.y + depth*sinA + right*cosA

		// Checkerboard sample.
		tx := (int(wx) + tileBias) >> tileBits
		ty := (int(wy) + tileBias) >> tileBits
		var base RGBA
		if (tx^ty)&1 == 0 {
			base = color
		} else {
			base = darkColor
		}

		// Distance fog and per-sector light, with a floor so far-away pixels
		// don't go pitch black. The 0.9 factor desaturates planes a touch
		// relative to walls so they read as lit-from-above ground.
		falloff := 1.0 / (1.0 + depth*0.004)
		light := clampF(sectorLight*falloff, 0.15, 1.0)
		c := shade(base, light*0.9)

		r.pixels[i] = c.r
		r.pixels[i+1] = c.g
		r.pixels[i+2] = c.b
		r.pixels[i+3] = 255
		i += stride
	}
}

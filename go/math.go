package main

// Math primitives shared across the engine: a 2-D vector, an 8-bit-per-channel
// color, and a couple of small helpers.
//
// Everything in the world is 2-D-with-heights: positions and movement live in
// (x, y) — see Vec2 — and floors/ceilings have a separate scalar Z stored on
// each Sector. There is no full 3-D vector type because we never need one;
// all the perspective math operates on screen columns whose vertical extent
// is computed from a Z difference and a depth.

import "math"

// Vec2 is a 2-D world or view-space point/vector.
type Vec2 struct {
	x, y float64
}

func (v Vec2) Add(o Vec2) Vec2    { return Vec2{v.x + o.x, v.y + o.y} }
func (v Vec2) Sub(o Vec2) Vec2    { return Vec2{v.x - o.x, v.y - o.y} }
func (v Vec2) Mul(s float64) Vec2 { return Vec2{v.x * s, v.y * s} }
func (v Vec2) Len() float64       { return math.Sqrt(v.x*v.x + v.y*v.y) }

// RGBA is the in-memory pixel format of the framebuffer (matches Ebiten's
// expected byte order when calling Image.WritePixels). Stored straight rather
// than premultiplied — `shade` scales the channels for distance/light.
type RGBA struct {
	r, g, b, a uint8
}

// shade multiplies a color's RGB channels by a brightness factor `f`, clamped
// to [0.12, 1.0]. The 0.12 floor keeps far-away geometry from going pure
// black, which would make portals look like holes in the screen.
func shade(c RGBA, f float64) RGBA {
	k := math.Max(0.12, math.Min(1.0, f))
	return RGBA{
		r: uint8(float64(c.r) * k),
		g: uint8(float64(c.g) * k),
		b: uint8(float64(c.b) * k),
		a: 255,
	}
}

// clampF clamps x into [lo, hi].
func clampF(x, lo, hi float64) float64 {
	if x < lo {
		return lo
	}
	if x > hi {
		return hi
	}
	return x
}

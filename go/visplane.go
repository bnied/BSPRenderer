package main

import "math"

// Visplane — DOOM's deferred floor/ceiling rendering primitive.
//
// During the BSP walk, drawSeg never colors a single floor or ceiling pixel.
// Instead, for each screen column it updates a per-sector Visplane with the
// vertical span of that column that belongs to this sector's floor (or
// ceiling). After the BSP walk, renderVisplanes sweeps every visplane and
// rasterizes the spans by inverse-projecting each pixel back to its world
// (X, Y) for procedural texturing and depth shading.
//
// This is what lets several sectors' floors and ceilings composite correctly
// across the screen without a depth buffer: every column has at most one
// floor visplane span and one ceiling visplane span (per sector), tracked
// independently and rasterized once.
//
// Per renderer there are 2 visplanes per sector — index 2*si is the floor
// and index 2*si+1 is the ceiling. Each plane keeps:
//
//   top[x]  — inclusive upper bound of the span at column x (MaxInt → none)
//   bot[x]  — inclusive lower bound of the span at column x (MinInt → none)
//   minX/maxX — range of columns actually touched this frame, so the
//               rasterizer can skip empty columns cheaply.
type Visplane struct {
	sectorIndex int
	isCeiling   bool
	top, bot    []int
	minX, maxX  int
}

func NewVisplane(sectorIndex int, isCeiling bool, width int) Visplane {
	v := Visplane{
		sectorIndex: sectorIndex,
		isCeiling:   isCeiling,
		top:         make([]int, width),
		bot:         make([]int, width),
	}
	v.Reset()
	return v
}

// Reset wipes coverage at the start of each frame.
func (v *Visplane) Reset() {
	for i := range v.top {
		v.top[i] = math.MaxInt
		v.bot[i] = math.MinInt
	}
	v.minX = len(v.top)
	v.maxX = -1
}

// Extend grows the span at column x to include [yLo..yHi]. The yLo > yHi
// no-op is the easy way to write "I might have nothing to add this column".
func (v *Visplane) Extend(x, yLo, yHi int) {
	if yLo > yHi {
		return
	}
	if yLo < v.top[x] {
		v.top[x] = yLo
	}
	if yHi > v.bot[x] {
		v.bot[x] = yHi
	}
	if x < v.minX {
		v.minX = x
	}
	if x > v.maxX {
		v.maxX = x
	}
}

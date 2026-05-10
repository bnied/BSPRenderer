package main

// Geometry types — the level's "schema". The actual data lives in level.go.
//
// The model follows DOOM's terminology:
//
//   - Sector:  a flat-floored, flat-ceilinged region with a uniform light
//              level. Rooms, corridors, and alcoves are all sectors.
//   - LineDef: an authored edge between two vertices. One-sided linedefs are
//              solid walls; two-sided linedefs are portals between two
//              adjacent sectors and may show upper/lower wall slivers where
//              the sectors' ceiling/floor heights differ.
//   - Seg:     a renderable wall segment. generateSegs() emits one Seg per
//              one-sided linedef and two Segs per two-sided linedef (one per
//              side, so the renderer can draw each side from the perspective
//              of its own front sector). The BSP builder may further split
//              segs at partition crossings.

// noSector is the sentinel for "no back side" — i.e. a one-sided solid wall.
// Real sector indices are >= 0, so any non-negative value is a portal.
const noSector = -1

// Sector is a horizontal-floored region. Floor and ceiling are stored as
// world-space Z heights so portals can compute upper/lower wall extents by
// comparing front and back sector heights.
type Sector struct {
	floorH, ceilH         float64
	floorColor, ceilColor RGBA
	light                 float64 // 0..1 multiplier applied before distance falloff
}

// LineDef is an authored line in the map. wallColor is used when the linedef
// is one-sided; upperColor / lowerColor are used on two-sided linedefs to fill
// the gaps that appear when the back sector's ceiling is lower or floor is
// higher than the front's.
type LineDef struct {
	v1, v2                 int  // indices into the global vertices slice
	frontSector            int
	backSector             int  // noSector → solid one-sided wall
	wallColor              RGBA // solid-wall fill
	upperColor, lowerColor RGBA // step-down ceiling / step-up floor on portals
}

// Seg is a renderable wall segment fed into the BSP. v1/v2 are world-space
// points (not vertex indices) because the BSP builder may split a seg at a
// partition crossing, producing intersection points that aren't in the
// original vertices slice.
type Seg struct {
	v1, v2       Vec2
	frontSector  int
	backSector   int // noSector → solid
	lineDefIndex int // back-pointer for upperColor/lowerColor/wallColor lookup
}

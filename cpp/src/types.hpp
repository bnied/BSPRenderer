#pragma once

// Geometry types — the level's "schema". The actual data lives in level.cpp.
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

#include "math.hpp"

// noSector is the sentinel for "no back side" — i.e. a one-sided solid wall.
// Real sector indices are >= 0.
inline constexpr int noSector = -1;

// Sector is a horizontal-floored region. Floor and ceiling are stored as
// world-space Z heights so portals can compute upper/lower wall extents by
// comparing front and back sector heights.
struct Sector {
    double floorH = 0;
    double ceilH  = 0;
    RGBA   floorColor;
    RGBA   ceilColor;
    double light = 1.0; // 0..1 multiplier applied before distance falloff
};

// LineDef is an authored line in the map. wallColor is used when the linedef
// is one-sided; upperColor / lowerColor are used on two-sided linedefs to fill
// the gaps that appear when the back sector's ceiling is lower or floor is
// higher than the front's.
struct LineDef {
    int  v1 = 0;
    int  v2 = 0;
    int  frontSector = 0;
    int  backSector  = noSector; // noSector → solid one-sided wall
    RGBA wallColor;
    RGBA upperColor;
    RGBA lowerColor;
};

// Seg is a renderable wall segment fed into the BSP. v1/v2 are world-space
// points (not vertex indices) because the BSP builder may split a seg at a
// partition crossing, producing intersection points that aren't in the
// original vertices array.
struct Seg {
    Vec2 v1;
    Vec2 v2;
    int  frontSector  = 0;
    int  backSector   = noSector; // noSector → solid
    int  lineDefIndex = 0;
};

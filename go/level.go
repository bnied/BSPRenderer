package main

// Hand-authored map.
//
// Sectors (12):
//   0 hub          floor   0, ceil  80, warm tan
//   1 (vestigial)  floor  80, ceil  80                 — formerly the pillar
//                                                       interior; now unused
//                                                       since the pillar walls
//                                                       are one-sided. Kept to
//                                                       avoid renumbering.
//   2 catwalk      floor  20, ceil  88, deep green     — first step above hub
//   3 pit          floor -20, ceil  50, violet     — 20 deep so you can climb back out
//   4 corridor     floor   4, ceil  72, blue
//   5 arena        floor  16, ceil 100, deep red
//   6 stair 1      floor  30, ceil  88, orange         — start of staircase
//   7 stair 2      floor  40, ceil  90, gold
//   8 stair 3      floor  50, ceil  92, lime
//   9 stair 4      floor  60, ceil  94, cyan
//  10 overlook     floor  70, ceil 130, bright cool    — top platform, wide
//  11 alcove       floor  30, ceil 110, magenta        — east of arena
//
// Layout (rough; not to scale):
//
//   y=-380              +-------------+
//                       |  OVERLOOK   |
//   y=-280            +-+             +-+
//                       |   STAIR 4   |
//   y=-230             -+             +-
//                       |   STAIR 3   |
//   y=-180             -+             +-
//                       |   STAIR 2   |
//   y=-130             -+             +-
//                       |   STAIR 1   |
//   y=-80              -+             +-
//                       |   CATWALK   |
//   y=0    +-----------+-             +-+----------+
//          |  HUB                                  +- corridor → arena → ALCOVE
//          |  (with one-sided pillar)              |
//   y=240  +---------+-+             +-+----------+
//                     \   PIT         /
//   y=320              +- (trapezoid) +
//
// Each staircase step is +10 floor units (under the 24-unit step-up cap).
// Ceiling rises 2 per step then jumps to 130 in the overlook so the chamber
// reads as "outdoors" relative to the cramped stair shaft.

var vertices = []Vec2{
	// Hub perimeter (axis aligned, with openings)
	{0, 0},     // 0  hub NW
	{80, 0},    // 1  hub N opening west (catwalk entry)
	{160, 0},   // 2  hub N opening east (catwalk entry)
	{240, 0},   // 3  hub NE
	{240, 80},  // 4  hub E opening N (corridor entry)
	{240, 160}, // 5  hub E opening S (corridor entry)
	{240, 240}, // 6  hub SE
	{160, 240}, // 7  hub S opening east (pit entry)
	{80, 240},  // 8  hub S opening west (pit entry)
	{0, 240},   // 9  hub SW
	// Octagonal pillar inscribed in 90..150 × 90..150 (circumradius 30 around
	// center 120,120). Diagonal vertices live in slots 10..13 (the original
	// square's corner indices); cardinal vertices N/E/S/W are added at
	// 38..41 below.
	{99, 99},   // 10 pillar NW
	{141, 99},  // 11 pillar NE
	{141, 141}, // 12 pillar SE
	{99, 141},  // 13 pillar SW
	// Catwalk (rectangle north of hub)
	{80, -80},  // 14 catwalk NW (= stair 1 SW)
	{160, -80}, // 15 catwalk NE (= stair 1 SE)
	// Pit (trapezoidal, widens to the south)
	{60, 320},  // 16 pit SW (diagonal wall from hub opening)
	{180, 320}, // 17 pit SE (diagonal)
	// East corridor + arena (corridor walls are diagonal: y=80 → 60, y=160 → 180)
	{340, 60},  // 18 corridor NE / arena NW
	{340, 180}, // 19 corridor SE / arena SW
	{440, 60},  // 20 arena NE
	{440, 180}, // 21 arena SE
	// Staircase north of the catwalk — each pair is the boundary between two
	// successive sectors (stair 1's N edge = stair 2's S edge, etc.).
	{80, -130},  // 22 stair 1 NW (= stair 2 SW)
	{160, -130}, // 23 stair 1 NE (= stair 2 SE)
	{80, -180},  // 24 stair 2 NW (= stair 3 SW)
	{160, -180}, // 25 stair 2 NE (= stair 3 SE)
	{80, -230},  // 26 stair 3 NW (= stair 4 SW)
	{160, -230}, // 27 stair 3 NE (= stair 4 SE)
	{80, -280},  // 28 stair 4 NW (= overlook S middle west)
	{160, -280}, // 29 stair 4 NE (= overlook S middle east)
	// Overlook room — wider than the stair shaft (x=20..220 vs 80..160).
	{20, -280},  // 30 overlook SW
	{220, -280}, // 31 overlook SE
	{20, -380},  // 32 overlook NW
	{220, -380}, // 33 overlook NE
	// Arena east wall split + alcove (small magenta room east of the arena).
	{440, 100}, // 34 arena E split N / alcove SW
	{440, 140}, // 35 arena E split S / alcove NW
	{540, 100}, // 36 alcove SE
	{540, 140}, // 37 alcove NE
	// Cardinal vertices of the octagonal pillar (the diagonals are at 10..13).
	{120, 90},  // 38 pillar N
	{150, 120}, // 39 pillar E
	{120, 150}, // 40 pillar S
	{90, 120},  // 41 pillar W
}

var (
	mainWall     = RGBA{158, 144, 115, 255} // hub warm tan
	mainUpper    = RGBA{110, 105, 92, 255}  // dim hub for upper wall slivers
	mainLower    = RGBA{118, 96, 72, 255}   // hub-tan brown for lower step
	pillarWall   = RGBA{210, 215, 225, 255} // bright stone pillar
	catwalkWall  = RGBA{108, 170, 82, 255}  // green catwalk
	pitWall      = RGBA{140, 100, 180, 255} // violet pit
	corrWall     = RGBA{94, 134, 200, 255}  // blue corridor
	arenaWall    = RGBA{196, 90, 62, 255}   // red arena
	arenaUpper   = RGBA{140, 70, 50, 255}   // dim red
	arenaLower   = RGBA{220, 130, 90, 255}  // light orange-red step-up
	stair1Wall   = RGBA{210, 130, 70, 255}  // orange
	stair2Wall   = RGBA{220, 180, 80, 255}  // gold
	stair3Wall   = RGBA{140, 210, 90, 255}  // lime
	stair4Wall   = RGBA{90, 190, 220, 255}  // cyan
	overlookWall = RGBA{210, 220, 235, 255} // bright cool gray
	alcoveWall   = RGBA{220, 140, 190, 255} // magenta
)

var sectors = []Sector{
	// 0: Hub — large warm-tan room, baseline floor and ceiling.
	{floorH: 0, ceilH: 80,
		floorColor: RGBA{82, 76, 60, 255},
		ceilColor:  RGBA{50, 56, 70, 255},
		light:      0.85},
	// 1: Vestigial (formerly pillar interior). Unreferenced by any linedef
	// since the pillar is now four one-sided walls; left in the array so we
	// don't have to renumber the existing sectors.
	{floorH: 80, ceilH: 80,
		floorColor: RGBA{40, 40, 45, 255},
		ceilColor:  RGBA{40, 40, 45, 255},
		light:      0.5},
	// 2: Catwalk — raised green platform. Step-up 20 from hub.
	{floorH: 20, ceilH: 88,
		floorColor: RGBA{50, 78, 50, 255},
		ceilColor:  RGBA{35, 55, 40, 255},
		light:      0.95},
	// 3: Pit — sunken violet chamber, lower ceiling. Floor at -20 (not deeper)
	// because maxStepUp=24, so anything deeper would trap the player in the pit.
	{floorH: -20, ceilH: 50,
		floorColor: RGBA{60, 40, 90, 255},
		ceilColor:  RGBA{40, 28, 60, 255},
		light:      0.65},
	// 4: East corridor — slight step up (+4), shorter ceiling.
	{floorH: 4, ceilH: 72,
		floorColor: RGBA{48, 62, 96, 255},
		ceilColor:  RGBA{34, 46, 78, 255},
		light:      0.82},
	// 5: Arena — deep red, taller ceiling, raised floor.
	{floorH: 16, ceilH: 100,
		floorColor: RGBA{112, 62, 46, 255},
		ceilColor:  RGBA{72, 44, 34, 255},
		light:      0.95},
	// 6: Stair 1 — orange.
	{floorH: 30, ceilH: 88,
		floorColor: RGBA{170, 110, 70, 255},
		ceilColor:  RGBA{120, 70, 40, 255},
		light:      0.88},
	// 7: Stair 2 — gold.
	{floorH: 40, ceilH: 90,
		floorColor: RGBA{200, 170, 70, 255},
		ceilColor:  RGBA{150, 120, 40, 255},
		light:      0.90},
	// 8: Stair 3 — lime.
	{floorH: 50, ceilH: 92,
		floorColor: RGBA{130, 200, 80, 255},
		ceilColor:  RGBA{80, 150, 50, 255},
		light:      0.92},
	// 9: Stair 4 — cyan.
	{floorH: 60, ceilH: 94,
		floorColor: RGBA{80, 180, 200, 255},
		ceilColor:  RGBA{40, 130, 160, 255},
		light:      0.94},
	// 10: Overlook — bright cool platform, much taller ceiling.
	{floorH: 70, ceilH: 130,
		floorColor: RGBA{200, 210, 230, 255},
		ceilColor:  RGBA{140, 160, 200, 255},
		light:      1.0},
	// 11: Arena alcove — magenta side room, slight step up from arena.
	{floorH: 30, ceilH: 110,
		floorColor: RGBA{210, 130, 180, 255},
		ceilColor:  RGBA{160, 80, 130, 255},
		light:      0.85},
}

var linedefs = []LineDef{
	// ---- Hub perimeter (front = 0) ----
	{v1: 0, v2: 1, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 1, v2: 2, frontSector: 0, backSector: 2, wallColor: mainWall, upperColor: mainUpper, lowerColor: catwalkWall}, // → catwalk
	{v1: 2, v2: 3, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 3, v2: 4, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 4, v2: 5, frontSector: 0, backSector: 4, wallColor: mainWall, upperColor: corrWall, lowerColor: corrWall}, // → corridor
	{v1: 5, v2: 6, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 6, v2: 7, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 7, v2: 8, frontSector: 0, backSector: 3, wallColor: mainWall, upperColor: pitWall, lowerColor: mainLower}, // → pit
	{v1: 8, v2: 9, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 9, v2: 0, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},

	// ---- Octagonal pillar (one-sided, 8 facets authored CW math so each
	// seg's normal points INTO the hub; fully solid block). Loop traversal:
	// N → NW → W → SW → S → SE → E → NE → N. ----
	{v1: 38, v2: 10, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // N → NW
	{v1: 10, v2: 41, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // NW → W
	{v1: 41, v2: 13, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // W → SW
	{v1: 13, v2: 40, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // SW → S
	{v1: 40, v2: 12, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // S → SE
	{v1: 12, v2: 39, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // SE → E
	{v1: 39, v2: 11, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // E → NE
	{v1: 11, v2: 38, frontSector: 0, backSector: noSector, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall}, // NE → N

	// ---- Catwalk perimeter (front = 2). N wall is now a portal to stair 1. ----
	{v1: 1, v2: 14, frontSector: 2, backSector: noSector, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: catwalkWall},
	{v1: 14, v2: 15, frontSector: 2, backSector: 6, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: stair1Wall}, // → stair 1
	{v1: 15, v2: 2, frontSector: 2, backSector: noSector, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: catwalkWall},

	// ---- Pit perimeter (front = 3, CCW math so normals point INTO pit) ----
	{v1: 7, v2: 17, frontSector: 3, backSector: noSector, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall},  // E diagonal
	{v1: 17, v2: 16, frontSector: 3, backSector: noSector, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall}, // S edge
	{v1: 16, v2: 8, frontSector: 3, backSector: noSector, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall},  // W diagonal

	// ---- East corridor (front = 4) — diagonal N + S walls + portal east ----
	{v1: 4, v2: 18, frontSector: 4, backSector: noSector, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall},
	{v1: 18, v2: 19, frontSector: 4, backSector: 5, wallColor: corrWall, upperColor: arenaUpper, lowerColor: arenaLower}, // → arena
	{v1: 19, v2: 5, frontSector: 4, backSector: noSector, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall},

	// ---- Arena perimeter (front = 5). E wall split into 3 to host the alcove portal. ----
	{v1: 18, v2: 20, frontSector: 5, backSector: noSector, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall},   // N
	{v1: 20, v2: 34, frontSector: 5, backSector: noSector, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall},   // E top
	{v1: 21, v2: 19, frontSector: 5, backSector: noSector, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall},   // S

	// ---- Staircase: 4 steps + overlook. Each portal between successive
	// stairs has lower_color = destination's wall color (going UP) and
	// upper_color = previous step's color (going DOWN). ----
	// Stair 1 (front = 6).
	{v1: 14, v2: 22, frontSector: 6, backSector: noSector, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair1Wall}, // W
	{v1: 22, v2: 23, frontSector: 6, backSector: 7, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair2Wall},        // → stair 2
	{v1: 23, v2: 15, frontSector: 6, backSector: noSector, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair1Wall}, // E
	// Stair 2 (front = 7).
	{v1: 22, v2: 24, frontSector: 7, backSector: noSector, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair2Wall},
	{v1: 24, v2: 25, frontSector: 7, backSector: 8, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair3Wall}, // → stair 3
	{v1: 25, v2: 23, frontSector: 7, backSector: noSector, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair2Wall},
	// Stair 3 (front = 8).
	{v1: 24, v2: 26, frontSector: 8, backSector: noSector, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair3Wall},
	{v1: 26, v2: 27, frontSector: 8, backSector: 9, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair4Wall}, // → stair 4
	{v1: 27, v2: 25, frontSector: 8, backSector: noSector, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair3Wall},
	// Stair 4 (front = 9).
	{v1: 26, v2: 28, frontSector: 9, backSector: noSector, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: stair4Wall},
	{v1: 28, v2: 29, frontSector: 9, backSector: 10, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: overlookWall}, // → overlook
	{v1: 29, v2: 27, frontSector: 9, backSector: noSector, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: stair4Wall},
	// Overlook (front = 10) — five solid walls; portal to stair 4 is the
	// reverse-direction seg of linedef stair4-overlook above.
	{v1: 28, v2: 30, frontSector: 10, backSector: noSector, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall}, // S west
	{v1: 30, v2: 32, frontSector: 10, backSector: noSector, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall}, // W
	{v1: 32, v2: 33, frontSector: 10, backSector: noSector, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall}, // N
	{v1: 33, v2: 31, frontSector: 10, backSector: noSector, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall}, // E
	{v1: 31, v2: 29, frontSector: 10, backSector: noSector, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall}, // S east

	// ---- Arena east wall middle = alcove portal + remaining E wall split. ----
	{v1: 34, v2: 35, frontSector: 5, backSector: 11, wallColor: arenaWall, upperColor: arenaWall, lowerColor: alcoveWall}, // arena → alcove
	{v1: 35, v2: 21, frontSector: 5, backSector: noSector, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall}, // E bottom

	// ---- Alcove perimeter (front = 11). ----
	{v1: 34, v2: 36, frontSector: 11, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall}, // N
	{v1: 36, v2: 37, frontSector: 11, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall}, // E
	{v1: 37, v2: 35, frontSector: 11, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall}, // S
}

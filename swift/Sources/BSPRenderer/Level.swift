import Foundation

// ============================================================
// MARK: - Types

struct Sector {
    var floorH: Double
    var ceilH: Double
    var floorColor: RGBA
    var ceilColor: RGBA
    var light: Double
}

struct LineDef {
    var v1: Int
    var v2: Int
    var frontSector: Int
    var backSector: Int?        // nil = solid one-sided wall
    var wallColor: RGBA         // used for solid walls
    var upperColor: RGBA        // used where back ceiling is lower
    var lowerColor: RGBA        // used where back floor is higher
}

struct Seg {
    var v1: Vec2
    var v2: Vec2
    var frontSector: Int
    var backSector: Int?
    var lineDefIndex: Int
}

// ============================================================
// MARK: - Hand-authored map
//
// Sectors (12):
//   0 hub          floor   0, ceil  80, warm tan
//   1 (vestigial)  floor  80, ceil  80                 — unreferenced; the
//                                                       octagonal pillar walls
//                                                       are one-sided. Kept to
//                                                       avoid renumbering.
//   2 catwalk      floor  20, ceil  88, deep green     — first step above hub
//   3 pit          floor -20, ceil  50, violet     — 20 deep so you can climb back out
//   4 corridor     floor   4, ceil  72, blue
//   5 arena        floor  16, ceil 100, deep red
//   6 stair 1      floor  30, ceil  88, orange
//   7 stair 2      floor  40, ceil  90, gold
//   8 stair 3      floor  50, ceil  92, lime
//   9 stair 4      floor  60, ceil  94, cyan
//  10 overlook     floor  70, ceil 130, bright cool    — top platform
//  11 alcove       floor  30, ceil 110, magenta        — east of arena

// ============================================================
// MARK: - Level
//
// A Level owns the hand-authored geometry (vertices, sectors, linedefs). A
// struct is the right fit: the map is immutable, has value semantics, and its
// arrays are copy-on-write so threading a `Level` through the renderer, player,
// and BSP builder is cheap. This replaces what used to be three loose top-level
// globals; `Level.showcase` is the single authored instance.

struct Level {
    let vertices: [Vec2]
    let sectors: [Sector]
    let linedefs: [LineDef]

    // The single hand-authored showcase map.
    static let showcase = Level(
        vertices: showcaseVertices,
        sectors: showcaseSectors,
        linedefs: showcaseLinedefs
    )

    // generateSegs flattens the linedef list into the seg list the BSP builder
    // consumes. One-sided linedefs produce one seg; two-sided linedefs produce
    // two (one per side, with sectors swapped).
    func generateSegs() -> [Seg] {
        var out: [Seg] = []
        for (i, l) in linedefs.enumerated() {
            let a = vertices[l.v1]
            let b = vertices[l.v2]
            out.append(Seg(v1: a, v2: b, frontSector: l.frontSector, backSector: l.backSector, lineDefIndex: i))
            if let back = l.backSector {
                out.append(Seg(v1: b, v2: a, frontSector: back, backSector: l.frontSector, lineDefIndex: i))
            }
        }
        return out
    }
}

private let showcaseVertices: [Vec2] = [
    // Hub perimeter
    Vec2(x:   0, y:   0),   //  0 hub NW
    Vec2(x:  80, y:   0),   //  1 hub N opening west (catwalk entry)
    Vec2(x: 160, y:   0),   //  2 hub N opening east
    Vec2(x: 240, y:   0),   //  3 hub NE
    Vec2(x: 240, y:  80),   //  4 hub E opening N (corridor entry)
    Vec2(x: 240, y: 160),   //  5 hub E opening S
    Vec2(x: 240, y: 240),   //  6 hub SE
    Vec2(x: 160, y: 240),   //  7 hub S opening east (pit entry)
    Vec2(x:  80, y: 240),   //  8 hub S opening west
    Vec2(x:   0, y: 240),   //  9 hub SW
    // Octagonal pillar diagonals (cardinal vertices live at 38..41).
    Vec2(x:  99, y:  99),   // 10 pillar NW
    Vec2(x: 141, y:  99),   // 11 pillar NE
    Vec2(x: 141, y: 141),   // 12 pillar SE
    Vec2(x:  99, y: 141),   // 13 pillar SW
    // Catwalk
    Vec2(x:  80, y: -80),   // 14 catwalk NW (= stair 1 SW)
    Vec2(x: 160, y: -80),   // 15 catwalk NE (= stair 1 SE)
    // Pit (trapezoid widening southward)
    Vec2(x:  60, y: 320),   // 16 pit SW
    Vec2(x: 180, y: 320),   // 17 pit SE
    // Corridor + arena (corridor walls are diagonal)
    Vec2(x: 340, y:  60),   // 18 corridor NE / arena NW
    Vec2(x: 340, y: 180),   // 19 corridor SE / arena SW
    Vec2(x: 440, y:  60),   // 20 arena NE
    Vec2(x: 440, y: 180),   // 21 arena SE
    // Staircase north of catwalk — each pair = one stair sector boundary.
    Vec2(x:  80, y: -130),  // 22 stair 1 NW (= stair 2 SW)
    Vec2(x: 160, y: -130),  // 23 stair 1 NE
    Vec2(x:  80, y: -180),  // 24 stair 2 NW
    Vec2(x: 160, y: -180),  // 25 stair 2 NE
    Vec2(x:  80, y: -230),  // 26 stair 3 NW
    Vec2(x: 160, y: -230),  // 27 stair 3 NE
    Vec2(x:  80, y: -280),  // 28 stair 4 NW (= overlook S middle west)
    Vec2(x: 160, y: -280),  // 29 stair 4 NE
    // Overlook (wider than the stair shaft)
    Vec2(x:  20, y: -280),  // 30 overlook SW
    Vec2(x: 220, y: -280),  // 31 overlook SE
    Vec2(x:  20, y: -380),  // 32 overlook NW
    Vec2(x: 220, y: -380),  // 33 overlook NE
    // Arena east-wall split + alcove
    Vec2(x: 440, y: 100),   // 34 arena E split N / alcove SW
    Vec2(x: 440, y: 140),   // 35 arena E split S / alcove NW
    Vec2(x: 540, y: 100),   // 36 alcove SE
    Vec2(x: 540, y: 140),   // 37 alcove NE
    // Octagonal pillar cardinal vertices (diagonals at 10..13).
    Vec2(x: 120, y:  90),   // 38 pillar N
    Vec2(x: 150, y: 120),   // 39 pillar E
    Vec2(x: 120, y: 150),   // 40 pillar S
    Vec2(x:  90, y: 120),   // 41 pillar W
]

// Per-sector wall colors.
private let mainWall     = RGBA(r: 158, g: 144, b: 115, a: 255) // hub warm tan
private let mainUpper    = RGBA(r: 110, g: 105, b:  92, a: 255)
private let mainLower    = RGBA(r: 118, g:  96, b:  72, a: 255)
private let pillarWall   = RGBA(r: 210, g: 215, b: 225, a: 255) // bright stone
private let catwalkWall  = RGBA(r: 108, g: 170, b:  82, a: 255) // green
private let pitWall      = RGBA(r: 140, g: 100, b: 180, a: 255) // violet
private let corrWall     = RGBA(r:  94, g: 134, b: 200, a: 255) // blue
private let arenaWall    = RGBA(r: 196, g:  90, b:  62, a: 255) // red
private let arenaUpper   = RGBA(r: 140, g:  70, b:  50, a: 255)
private let arenaLower   = RGBA(r: 220, g: 130, b:  90, a: 255)
private let stair1Wall   = RGBA(r: 210, g: 130, b:  70, a: 255) // orange
private let stair2Wall   = RGBA(r: 220, g: 180, b:  80, a: 255) // gold
private let stair3Wall   = RGBA(r: 140, g: 210, b:  90, a: 255) // lime
private let stair4Wall   = RGBA(r:  90, g: 190, b: 220, a: 255) // cyan
private let overlookWall = RGBA(r: 210, g: 220, b: 235, a: 255) // bright cool gray
private let alcoveWall   = RGBA(r: 220, g: 140, b: 190, a: 255) // magenta

private let showcaseSectors: [Sector] = [
    // 0: Hub.
    Sector(floorH: 0, ceilH: 80,
           floorColor: RGBA(r:  82, g:  76, b:  60, a: 255),
           ceilColor:  RGBA(r:  50, g:  56, b:  70, a: 255),
           light: 0.85),
    // 1: Vestigial — formerly the pillar interior; one-sided pillar walls
    // don't reference it now, but kept to preserve sector indices.
    Sector(floorH: 80, ceilH: 80,
           floorColor: RGBA(r:  40, g:  40, b:  45, a: 255),
           ceilColor:  RGBA(r:  40, g:  40, b:  45, a: 255),
           light: 0.5),
    // 2: Catwalk — green raised platform.
    Sector(floorH: 20, ceilH: 88,
           floorColor: RGBA(r:  50, g:  78, b:  50, a: 255),
           ceilColor:  RGBA(r:  35, g:  55, b:  40, a: 255),
           light: 0.95),
    // 3: Pit — sunken violet, lower ceiling. Floor at -20 (not deeper) because
    // maxStepUp = 24, so anything deeper would trap the player in the pit.
    Sector(floorH: -20, ceilH: 50,
           floorColor: RGBA(r:  60, g:  40, b:  90, a: 255),
           ceilColor:  RGBA(r:  40, g:  28, b:  60, a: 255),
           light: 0.65),
    // 4: East corridor — slight step up, shorter ceiling.
    Sector(floorH: 4, ceilH: 72,
           floorColor: RGBA(r:  48, g:  62, b:  96, a: 255),
           ceilColor:  RGBA(r:  34, g:  46, b:  78, a: 255),
           light: 0.82),
    // 5: Arena — deep red, taller ceiling.
    Sector(floorH: 16, ceilH: 100,
           floorColor: RGBA(r: 112, g:  62, b:  46, a: 255),
           ceilColor:  RGBA(r:  72, g:  44, b:  34, a: 255),
           light: 0.95),
    // 6: Stair 1 — orange.
    Sector(floorH: 30, ceilH: 88,
           floorColor: RGBA(r: 170, g: 110, b:  70, a: 255),
           ceilColor:  RGBA(r: 120, g:  70, b:  40, a: 255),
           light: 0.88),
    // 7: Stair 2 — gold.
    Sector(floorH: 40, ceilH: 90,
           floorColor: RGBA(r: 200, g: 170, b:  70, a: 255),
           ceilColor:  RGBA(r: 150, g: 120, b:  40, a: 255),
           light: 0.90),
    // 8: Stair 3 — lime.
    Sector(floorH: 50, ceilH: 92,
           floorColor: RGBA(r: 130, g: 200, b:  80, a: 255),
           ceilColor:  RGBA(r:  80, g: 150, b:  50, a: 255),
           light: 0.92),
    // 9: Stair 4 — cyan.
    Sector(floorH: 60, ceilH: 94,
           floorColor: RGBA(r:  80, g: 180, b: 200, a: 255),
           ceilColor:  RGBA(r:  40, g: 130, b: 160, a: 255),
           light: 0.94),
    // 10: Overlook — bright cool platform, much taller ceiling.
    Sector(floorH: 70, ceilH: 130,
           floorColor: RGBA(r: 200, g: 210, b: 230, a: 255),
           ceilColor:  RGBA(r: 140, g: 160, b: 200, a: 255),
           light: 1.0),
    // 11: Arena alcove — magenta side room.
    Sector(floorH: 30, ceilH: 110,
           floorColor: RGBA(r: 210, g: 130, b: 180, a: 255),
           ceilColor:  RGBA(r: 160, g:  80, b: 130, a: 255),
           light: 0.85),
]

private let showcaseLinedefs: [LineDef] = [
    // ---- Hub perimeter (front = 0) ----
    LineDef(v1: 0, v2: 1, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 1, v2: 2, frontSector: 0, backSector: 2, wallColor: mainWall, upperColor: mainUpper, lowerColor: catwalkWall), // → catwalk
    LineDef(v1: 2, v2: 3, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 3, v2: 4, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 4, v2: 5, frontSector: 0, backSector: 4, wallColor: mainWall, upperColor: corrWall, lowerColor: corrWall), // → corridor
    LineDef(v1: 5, v2: 6, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 6, v2: 7, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 7, v2: 8, frontSector: 0, backSector: 3, wallColor: mainWall, upperColor: pitWall, lowerColor: mainLower), // → pit
    LineDef(v1: 8, v2: 9, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 9, v2: 0, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),

    // ---- Octagonal pillar (one-sided, 8 facets, CW math).
    // Loop: N → NW → W → SW → S → SE → E → NE → N. ----
    LineDef(v1: 38, v2: 10, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 10, v2: 41, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 41, v2: 13, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 13, v2: 40, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 40, v2: 12, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 12, v2: 39, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 39, v2: 11, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),
    LineDef(v1: 11, v2: 38, frontSector: 0, backSector: nil, wallColor: pillarWall, upperColor: pillarWall, lowerColor: pillarWall),

    // ---- Catwalk (front = 2). N wall is a portal to stair 1. ----
    LineDef(v1: 1, v2: 14, frontSector: 2, backSector: nil, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: catwalkWall),
    LineDef(v1: 14, v2: 15, frontSector: 2, backSector: 6, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: stair1Wall), // → stair 1
    LineDef(v1: 15, v2: 2, frontSector: 2, backSector: nil, wallColor: catwalkWall, upperColor: catwalkWall, lowerColor: catwalkWall),

    // ---- Pit perimeter (front = 3, CCW math so normals point INTO pit) ----
    LineDef(v1: 7, v2: 17, frontSector: 3, backSector: nil, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall),
    LineDef(v1: 17, v2: 16, frontSector: 3, backSector: nil, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall),
    LineDef(v1: 16, v2: 8, frontSector: 3, backSector: nil, wallColor: pitWall, upperColor: pitWall, lowerColor: pitWall),

    // ---- East corridor (front = 4) — diagonal walls + portal east ----
    LineDef(v1: 4, v2: 18, frontSector: 4, backSector: nil, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall),
    LineDef(v1: 18, v2: 19, frontSector: 4, backSector: 5, wallColor: corrWall, upperColor: arenaUpper, lowerColor: arenaLower), // → arena
    LineDef(v1: 19, v2: 5, frontSector: 4, backSector: nil, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall),

    // ---- Arena perimeter (front = 5). E wall split into 3 to host alcove portal. ----
    LineDef(v1: 18, v2: 20, frontSector: 5, backSector: nil, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall),  // N
    LineDef(v1: 20, v2: 34, frontSector: 5, backSector: nil, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall),  // E top
    LineDef(v1: 21, v2: 19, frontSector: 5, backSector: nil, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall),  // S

    // ---- Staircase: 4 steps + overlook. lower_color = destination's color
    // (going up); upper_color = previous step's color (going down). ----
    LineDef(v1: 14, v2: 22, frontSector: 6, backSector: nil, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair1Wall),
    LineDef(v1: 22, v2: 23, frontSector: 6, backSector: 7, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair2Wall),
    LineDef(v1: 23, v2: 15, frontSector: 6, backSector: nil, wallColor: stair1Wall, upperColor: stair1Wall, lowerColor: stair1Wall),
    LineDef(v1: 22, v2: 24, frontSector: 7, backSector: nil, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair2Wall),
    LineDef(v1: 24, v2: 25, frontSector: 7, backSector: 8, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair3Wall),
    LineDef(v1: 25, v2: 23, frontSector: 7, backSector: nil, wallColor: stair2Wall, upperColor: stair2Wall, lowerColor: stair2Wall),
    LineDef(v1: 24, v2: 26, frontSector: 8, backSector: nil, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair3Wall),
    LineDef(v1: 26, v2: 27, frontSector: 8, backSector: 9, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair4Wall),
    LineDef(v1: 27, v2: 25, frontSector: 8, backSector: nil, wallColor: stair3Wall, upperColor: stair3Wall, lowerColor: stair3Wall),
    LineDef(v1: 26, v2: 28, frontSector: 9, backSector: nil, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: stair4Wall),
    LineDef(v1: 28, v2: 29, frontSector: 9, backSector: 10, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: overlookWall),
    LineDef(v1: 29, v2: 27, frontSector: 9, backSector: nil, wallColor: stair4Wall, upperColor: stair4Wall, lowerColor: stair4Wall),
    // Overlook (front = 10) — five solid walls.
    LineDef(v1: 28, v2: 30, frontSector: 10, backSector: nil, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall),
    LineDef(v1: 30, v2: 32, frontSector: 10, backSector: nil, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall),
    LineDef(v1: 32, v2: 33, frontSector: 10, backSector: nil, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall),
    LineDef(v1: 33, v2: 31, frontSector: 10, backSector: nil, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall),
    LineDef(v1: 31, v2: 29, frontSector: 10, backSector: nil, wallColor: overlookWall, upperColor: overlookWall, lowerColor: overlookWall),

    // ---- Arena east middle = alcove portal + remaining E split. ----
    LineDef(v1: 34, v2: 35, frontSector: 5, backSector: 11, wallColor: arenaWall, upperColor: arenaWall, lowerColor: alcoveWall), // → alcove
    LineDef(v1: 35, v2: 21, frontSector: 5, backSector: nil, wallColor: arenaWall, upperColor: arenaWall, lowerColor: arenaWall),

    // ---- Alcove perimeter (front = 11). ----
    LineDef(v1: 34, v2: 36, frontSector: 11, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),
    LineDef(v1: 36, v2: 37, frontSector: 11, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),
    LineDef(v1: 37, v2: 35, frontSector: 11, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),
]

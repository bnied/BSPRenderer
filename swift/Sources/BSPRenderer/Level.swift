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
//   alcove (2, green, low ceiling)
//        v10──v11
//         │    │
//         │    │                      east (1, red, raised + tall)
//  v0──v1─┴────┴─v2──v3────v4    v4──v12
//   │                      │    │    │
//   │        main (0, gray)│door│    │
//   │                      │    │    │
//   │                      │    │    │
//   │                      │v5──v13
//   │                      │
//  v9──v8────v7──v6
//       │     \
//       │      \       corridor (3, blue, slight step up + drop ceiling)
//       │       \
//      v15──────v14
//       │        │     south (4, violet, sunken floor + tall ceiling)
//      v17──────v16     -- trapezoid with angled east/west walls

let vertices: [Vec2] = [
    // Main hall perimeter
    Vec2(x:   0, y:    0),   //  0 main NW
    Vec2(x:  80, y:    0),   //  1 alcove opening west
    Vec2(x: 140, y:    0),   //  2 alcove opening east
    Vec2(x: 240, y:    0),   //  3 main NE
    Vec2(x: 240, y:   80),   //  4 door top
    Vec2(x: 240, y:  140),   //  5 door bottom
    Vec2(x: 240, y:  200),   //  6 main SE
    Vec2(x: 150, y:  200),   //  7 corridor opening east
    Vec2(x:  90, y:  200),   //  8 corridor opening west
    Vec2(x:   0, y:  200),   //  9 main SW
    // Alcove
    Vec2(x:  80, y:  -50),   // 10 alcove NW
    Vec2(x: 140, y:  -50),   // 11 alcove NE
    // East room
    Vec2(x: 360, y:   80),   // 12 east NE
    Vec2(x: 360, y:  140),   // 13 east SE
    // Corridor (angled walls from main to south chamber)
    Vec2(x: 200, y:  300),   // 14 corridor SE / south NE
    Vec2(x: 140, y:  300),   // 15 corridor SW / south NW
    // South chamber (trapezoid widening southward)
    Vec2(x: 240, y:  360),   // 16 south SE
    Vec2(x: 100, y:  360),   // 17 south SW
]

// Per-sector wall colors, chosen so each sector reads as its own palette.
let mainWall   = RGBA(r: 158, g: 144, b: 115, a: 255)
let mainUpper  = RGBA(r: 110, g: 105, b:  92, a: 255)
let mainLower  = RGBA(r: 118, g:  96, b:  72, a: 255)

let eastWall   = RGBA(r: 196, g:  90, b:  62, a: 255)

let alcoveWall = RGBA(r: 108, g: 170, b:  82, a: 255)

let corrWall   = RGBA(r:  94, g: 134, b: 200, a: 255)

let southWall  = RGBA(r: 168, g: 108, b: 206, a: 255)

let sectors: [Sector] = [
    // 0: Main hall — warm tan
    Sector(
        floorH: 0, ceilH: 64,
        floorColor: RGBA(r:  82, g:  76, b:  60, a: 255),
        ceilColor:  RGBA(r:  50, g:  56, b:  70, a: 255),
        light: 0.85
    ),
    // 1: East room — red, raised floor, taller ceiling
    Sector(
        floorH: 16, ceilH: 88,
        floorColor: RGBA(r: 112, g:  62, b:  46, a: 255),
        ceilColor:  RGBA(r:  72, g:  44, b:  34, a: 255),
        light: 0.95
    ),
    // 2: Alcove — green, low ceiling, raised floor
    Sector(
        floorH: -12, ceilH: 48,
        floorColor: RGBA(r:  58, g:  84, b:  52, a: 255),
        ceilColor:  RGBA(r:  42, g:  62, b:  40, a: 255),
        light: 0.9
    ),
    // 3: Diagonal corridor — blue, slight step up
    Sector(
        floorH: 4, ceilH: 68,
        floorColor: RGBA(r:  48, g:  62, b:  96, a: 255),
        ceilColor:  RGBA(r:  34, g:  46, b:  78, a: 255),
        light: 0.82
    ),
    // 4: South chamber — violet, sunken floor
    Sector(
        floorH: -12, ceilH: 52,
        floorColor: RGBA(r:  76, g:  52, b:  96, a: 255),
        ceilColor:  RGBA(r:  52, g:  38, b:  76, a: 255),
        light: 0.7
    ),
]

let linedefs: [LineDef] = [
    // ---- Main hall perimeter (front = 0) ----
    LineDef(v1: 0, v2: 1, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    // Two-sided: opens into alcove (low-ceiling lintel above).
    LineDef(v1: 1, v2: 2, frontSector: 0, backSector: 2, wallColor: mainWall, upperColor: alcoveWall, lowerColor: mainLower),
    LineDef(v1: 2, v2: 3, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 3, v2: 4, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    // Two-sided: door into east room (step up + taller ceiling on the other side).
    LineDef(v1: 4, v2: 5, frontSector: 0, backSector: 1, wallColor: mainWall, upperColor: mainUpper, lowerColor: eastWall),
    LineDef(v1: 5, v2: 6, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 6, v2: 7, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    // Two-sided: opens into corridor (both upper and lower walls visible from main).
    LineDef(v1: 7, v2: 8, frontSector: 0, backSector: 3, wallColor: mainWall, upperColor: corrWall, lowerColor: corrWall),
    LineDef(v1: 8, v2: 9, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),
    LineDef(v1: 9, v2: 0, frontSector: 0, backSector: nil, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower),

    // ---- Alcove (front = 2) ----
    LineDef(v1: 1, v2: 10, frontSector: 2, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),
    LineDef(v1: 10, v2: 11, frontSector: 2, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),
    LineDef(v1: 11, v2: 2, frontSector: 2, backSector: nil, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall),

    // ---- East room (front = 1) ----
    LineDef(v1: 4, v2: 12, frontSector: 1, backSector: nil, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall),
    LineDef(v1: 12, v2: 13, frontSector: 1, backSector: nil, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall),
    LineDef(v1: 13, v2: 5, frontSector: 1, backSector: nil, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall),

    // ---- Diagonal corridor (front = 3) — angled E and W walls ----
    LineDef(v1: 7, v2: 14, frontSector: 3, backSector: nil, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall),
    // Two-sided at the south end: opens into the south chamber.
    LineDef(v1: 14, v2: 15, frontSector: 3, backSector: 4, wallColor: corrWall, upperColor: corrWall, lowerColor: southWall),
    LineDef(v1: 15, v2: 8, frontSector: 3, backSector: nil, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall),

    // ---- South chamber (front = 4) — trapezoid with angled E and W walls ----
    LineDef(v1: 14, v2: 16, frontSector: 4, backSector: nil, wallColor: southWall, upperColor: southWall, lowerColor: southWall),
    LineDef(v1: 16, v2: 17, frontSector: 4, backSector: nil, wallColor: southWall, upperColor: southWall, lowerColor: southWall),
    LineDef(v1: 17, v2: 15, frontSector: 4, backSector: nil, wallColor: southWall, upperColor: southWall, lowerColor: southWall),
]

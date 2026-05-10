// Hand-authored map.
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

#include "level.hpp"

const std::vector<Vec2> vertices = {
    // Main hall perimeter
    {  0,    0},  //  0 main NW
    { 80,    0},  //  1 alcove opening west
    {140,    0},  //  2 alcove opening east
    {240,    0},  //  3 main NE
    {240,   80},  //  4 door top
    {240,  140},  //  5 door bottom
    {240,  200},  //  6 main SE
    {150,  200},  //  7 corridor opening east
    { 90,  200},  //  8 corridor opening west
    {  0,  200},  //  9 main SW
    // Alcove
    { 80,  -50},  // 10 alcove NW
    {140,  -50},  // 11 alcove NE
    // East room
    {360,   80},  // 12 east NE
    {360,  140},  // 13 east SE
    // Corridor
    {200,  300},  // 14 corridor SE / south NE
    {140,  300},  // 15 corridor SW / south NW
    // South chamber
    {240,  360},  // 16 south SE
    {100,  360},  // 17 south SW
};

// Per-sector wall colors, chosen so each sector reads as its own palette.
namespace {
    constexpr RGBA mainWall   = {158, 144, 115, 255};
    constexpr RGBA mainUpper  = {110, 105,  92, 255};
    constexpr RGBA mainLower  = {118,  96,  72, 255};
    constexpr RGBA eastWall   = {196,  90,  62, 255};
    constexpr RGBA alcoveWall = {108, 170,  82, 255};
    constexpr RGBA corrWall   = { 94, 134, 200, 255};
    constexpr RGBA southWall  = {168, 108, 206, 255};
}

const std::vector<Sector> sectors = {
    // 0: Main hall — warm tan
    {  0,  64, {82,  76, 60, 255}, {50, 56, 70, 255}, 0.85},
    // 1: East room — red, raised floor, taller ceiling
    { 16,  88, {112, 62, 46, 255}, {72, 44, 34, 255}, 0.95},
    // 2: Alcove — green, low ceiling, raised floor
    {-12,  48, {58,  84, 52, 255}, {42, 62, 40, 255}, 0.9},
    // 3: Diagonal corridor — blue, slight step up
    {  4,  68, {48,  62, 96, 255}, {34, 46, 78, 255}, 0.82},
    // 4: South chamber — violet, sunken floor
    {-12,  52, {76,  52, 96, 255}, {52, 38, 76, 255}, 0.7},
};

const std::vector<LineDef> linedefs = {
    // ---- Main hall perimeter (front = 0) ----
    {0, 1, 0, noSector, mainWall, mainUpper, mainLower},
    {1, 2, 0, 2,        mainWall, alcoveWall, mainLower},
    {2, 3, 0, noSector, mainWall, mainUpper, mainLower},
    {3, 4, 0, noSector, mainWall, mainUpper, mainLower},
    {4, 5, 0, 1,        mainWall, mainUpper, eastWall},
    {5, 6, 0, noSector, mainWall, mainUpper, mainLower},
    {6, 7, 0, noSector, mainWall, mainUpper, mainLower},
    {7, 8, 0, 3,        mainWall, corrWall, corrWall},
    {8, 9, 0, noSector, mainWall, mainUpper, mainLower},
    {9, 0, 0, noSector, mainWall, mainUpper, mainLower},

    // ---- Alcove (front = 2) ----
    { 1, 10, 2, noSector, alcoveWall, alcoveWall, alcoveWall},
    {10, 11, 2, noSector, alcoveWall, alcoveWall, alcoveWall},
    {11,  2, 2, noSector, alcoveWall, alcoveWall, alcoveWall},

    // ---- East room (front = 1) ----
    { 4, 12, 1, noSector, eastWall, eastWall, eastWall},
    {12, 13, 1, noSector, eastWall, eastWall, eastWall},
    {13,  5, 1, noSector, eastWall, eastWall, eastWall},

    // ---- Diagonal corridor (front = 3) ----
    { 7, 14, 3, noSector, corrWall, corrWall, corrWall},
    {14, 15, 3, 4,        corrWall, corrWall, southWall},
    {15,  8, 3, noSector, corrWall, corrWall, corrWall},

    // ---- South chamber (front = 4) ----
    {14, 16, 4, noSector, southWall, southWall, southWall},
    {16, 17, 4, noSector, southWall, southWall, southWall},
    {17, 15, 4, noSector, southWall, southWall, southWall},
};

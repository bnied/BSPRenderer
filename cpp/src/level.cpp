// Hand-authored map.
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
//  10 overlook     floor  70, ceil 130, bright cool    — top of staircase
//  11 alcove       floor  30, ceil 110, magenta        — east of arena

#include "level.hpp"

const std::vector<Vec2> vertices = {
    // Hub perimeter
    {  0,    0},  //  0 hub NW
    { 80,    0},  //  1 hub N opening west (catwalk entry)
    {160,    0},  //  2 hub N opening east
    {240,    0},  //  3 hub NE
    {240,   80},  //  4 hub E opening N (corridor entry)
    {240,  160},  //  5 hub E opening S
    {240,  240},  //  6 hub SE
    {160,  240},  //  7 hub S opening east (pit entry)
    { 80,  240},  //  8 hub S opening west
    {  0,  240},  //  9 hub SW
    // Octagonal pillar diagonals (cardinals at 38..41).
    { 99,   99},  // 10 pillar NW
    {141,   99},  // 11 pillar NE
    {141,  141},  // 12 pillar SE
    { 99,  141},  // 13 pillar SW
    // Catwalk
    { 80,  -80},  // 14 catwalk NW (= stair 1 SW)
    {160,  -80},  // 15 catwalk NE (= stair 1 SE)
    // Pit (trapezoid widening southward)
    { 60,  320},  // 16 pit SW
    {180,  320},  // 17 pit SE
    // Corridor + arena (corridor walls are diagonal)
    {340,   60},  // 18 corridor NE / arena NW
    {340,  180},  // 19 corridor SE / arena SW
    {440,   60},  // 20 arena NE
    {440,  180},  // 21 arena SE
    // Staircase
    { 80, -130},  // 22 stair 1 NW
    {160, -130},  // 23 stair 1 NE
    { 80, -180},  // 24 stair 2 NW
    {160, -180},  // 25 stair 2 NE
    { 80, -230},  // 26 stair 3 NW
    {160, -230},  // 27 stair 3 NE
    { 80, -280},  // 28 stair 4 NW
    {160, -280},  // 29 stair 4 NE
    // Overlook (wider than the stair shaft)
    { 20, -280},  // 30 overlook SW
    {220, -280},  // 31 overlook SE
    { 20, -380},  // 32 overlook NW
    {220, -380},  // 33 overlook NE
    // Arena east-wall split + alcove
    {440,  100},  // 34 arena E split N / alcove SW
    {440,  140},  // 35 arena E split S / alcove NW
    {540,  100},  // 36 alcove SE
    {540,  140},  // 37 alcove NE
    // Octagonal pillar cardinal vertices (diagonals at 10..13).
    {120,   90},  // 38 pillar N
    {150,  120},  // 39 pillar E
    {120,  150},  // 40 pillar S
    { 90,  120},  // 41 pillar W
};

namespace {
    constexpr RGBA mainWall     = {158, 144, 115, 255}; // hub warm tan
    constexpr RGBA mainUpper    = {110, 105,  92, 255};
    constexpr RGBA mainLower    = {118,  96,  72, 255};
    constexpr RGBA pillarWall   = {210, 215, 225, 255}; // bright stone
    constexpr RGBA catwalkWall  = {108, 170,  82, 255}; // green
    constexpr RGBA pitWall      = {140, 100, 180, 255}; // violet
    constexpr RGBA corrWall     = { 94, 134, 200, 255}; // blue
    constexpr RGBA arenaWall    = {196,  90,  62, 255}; // red
    constexpr RGBA arenaUpper   = {140,  70,  50, 255};
    constexpr RGBA arenaLower   = {220, 130,  90, 255};
    constexpr RGBA stair1Wall   = {210, 130,  70, 255}; // orange
    constexpr RGBA stair2Wall   = {220, 180,  80, 255}; // gold
    constexpr RGBA stair3Wall   = {140, 210,  90, 255}; // lime
    constexpr RGBA stair4Wall   = { 90, 190, 220, 255}; // cyan
    constexpr RGBA overlookWall = {210, 220, 235, 255}; // bright cool gray
    constexpr RGBA alcoveWall   = {220, 140, 190, 255}; // magenta
}

const std::vector<Sector> sectors = {
    // 0: Hub.
    {  0,  80, { 82,  76,  60, 255}, { 50,  56,  70, 255}, 0.85},
    // 1: Vestigial (was pillar interior; one-sided pillar walls don't reference it now).
    { 80,  80, { 40,  40,  45, 255}, { 40,  40,  45, 255}, 0.5},
    // 2: Catwalk — green raised platform.
    { 20,  88, { 50,  78,  50, 255}, { 35,  55,  40, 255}, 0.95},
    // 3: Pit — sunken violet. Floor at -20 (not deeper) because
    // maxStepUp = 24, so anything deeper would trap the player in the pit.
    {-20,  50, { 60,  40,  90, 255}, { 40,  28,  60, 255}, 0.65},
    // 4: East corridor — slight step up.
    {  4,  72, { 48,  62,  96, 255}, { 34,  46,  78, 255}, 0.82},
    // 5: Arena — deep red, taller ceiling.
    { 16, 100, {112,  62,  46, 255}, { 72,  44,  34, 255}, 0.95},
    // 6: Stair 1 — orange.
    { 30,  88, {170, 110,  70, 255}, {120,  70,  40, 255}, 0.88},
    // 7: Stair 2 — gold.
    { 40,  90, {200, 170,  70, 255}, {150, 120,  40, 255}, 0.90},
    // 8: Stair 3 — lime.
    { 50,  92, {130, 200,  80, 255}, { 80, 150,  50, 255}, 0.92},
    // 9: Stair 4 — cyan.
    { 60,  94, { 80, 180, 200, 255}, { 40, 130, 160, 255}, 0.94},
    // 10: Overlook — bright cool, much taller ceiling.
    { 70, 130, {200, 210, 230, 255}, {140, 160, 200, 255}, 1.0},
    // 11: Arena alcove — magenta.
    { 30, 110, {210, 130, 180, 255}, {160,  80, 130, 255}, 0.85},
};

const std::vector<LineDef> linedefs = {
    // ---- Hub perimeter (front = 0) ----
    {0, 1, 0, noSector, mainWall, mainUpper, mainLower},
    {1, 2, 0, 2,        mainWall, mainUpper, catwalkWall}, // → catwalk
    {2, 3, 0, noSector, mainWall, mainUpper, mainLower},
    {3, 4, 0, noSector, mainWall, mainUpper, mainLower},
    {4, 5, 0, 4,        mainWall, corrWall,  corrWall},    // → corridor
    {5, 6, 0, noSector, mainWall, mainUpper, mainLower},
    {6, 7, 0, noSector, mainWall, mainUpper, mainLower},
    {7, 8, 0, 3,        mainWall, pitWall,   mainLower},   // → pit
    {8, 9, 0, noSector, mainWall, mainUpper, mainLower},
    {9, 0, 0, noSector, mainWall, mainUpper, mainLower},

    // ---- Octagonal pillar (one-sided, 8 facets, CW math).
    // Loop: N → NW → W → SW → S → SE → E → NE → N. ----
    {38, 10, 0, noSector, pillarWall, pillarWall, pillarWall},
    {10, 41, 0, noSector, pillarWall, pillarWall, pillarWall},
    {41, 13, 0, noSector, pillarWall, pillarWall, pillarWall},
    {13, 40, 0, noSector, pillarWall, pillarWall, pillarWall},
    {40, 12, 0, noSector, pillarWall, pillarWall, pillarWall},
    {12, 39, 0, noSector, pillarWall, pillarWall, pillarWall},
    {39, 11, 0, noSector, pillarWall, pillarWall, pillarWall},
    {11, 38, 0, noSector, pillarWall, pillarWall, pillarWall},

    // ---- Catwalk (front = 2). N wall is a portal to stair 1. ----
    { 1, 14, 2, noSector, catwalkWall, catwalkWall, catwalkWall},
    {14, 15, 2, 6,        catwalkWall, catwalkWall, stair1Wall}, // → stair 1
    {15,  2, 2, noSector, catwalkWall, catwalkWall, catwalkWall},

    // ---- Pit perimeter (front = 3, CCW math) ----
    { 7, 17, 3, noSector, pitWall, pitWall, pitWall},
    {17, 16, 3, noSector, pitWall, pitWall, pitWall},
    {16,  8, 3, noSector, pitWall, pitWall, pitWall},

    // ---- East corridor (front = 4) ----
    { 4, 18, 4, noSector, corrWall, corrWall, corrWall},
    {18, 19, 4, 5,        corrWall, arenaUpper, arenaLower}, // → arena
    {19,  5, 4, noSector, corrWall, corrWall, corrWall},

    // ---- Arena perimeter (front = 5). E wall split into 3 to host alcove portal. ----
    {18, 20, 5, noSector, arenaWall, arenaWall, arenaWall}, // N
    {20, 34, 5, noSector, arenaWall, arenaWall, arenaWall}, // E top
    {21, 19, 5, noSector, arenaWall, arenaWall, arenaWall}, // S

    // ---- Staircase: 4 steps + overlook. ----
    {14, 22, 6, noSector, stair1Wall, stair1Wall, stair1Wall},
    {22, 23, 6, 7,        stair1Wall, stair1Wall, stair2Wall},
    {23, 15, 6, noSector, stair1Wall, stair1Wall, stair1Wall},
    {22, 24, 7, noSector, stair2Wall, stair2Wall, stair2Wall},
    {24, 25, 7, 8,        stair2Wall, stair2Wall, stair3Wall},
    {25, 23, 7, noSector, stair2Wall, stair2Wall, stair2Wall},
    {24, 26, 8, noSector, stair3Wall, stair3Wall, stair3Wall},
    {26, 27, 8, 9,        stair3Wall, stair3Wall, stair4Wall},
    {27, 25, 8, noSector, stair3Wall, stair3Wall, stair3Wall},
    {26, 28, 9, noSector, stair4Wall, stair4Wall, stair4Wall},
    {28, 29, 9, 10,       stair4Wall, stair4Wall, overlookWall},
    {29, 27, 9, noSector, stair4Wall, stair4Wall, stair4Wall},
    // Overlook (front = 10) — five solid walls.
    {28, 30, 10, noSector, overlookWall, overlookWall, overlookWall},
    {30, 32, 10, noSector, overlookWall, overlookWall, overlookWall},
    {32, 33, 10, noSector, overlookWall, overlookWall, overlookWall},
    {33, 31, 10, noSector, overlookWall, overlookWall, overlookWall},
    {31, 29, 10, noSector, overlookWall, overlookWall, overlookWall},

    // ---- Arena east middle = alcove portal + remaining E split. ----
    {34, 35, 5, 11,       arenaWall, arenaWall, alcoveWall}, // → alcove
    {35, 21, 5, noSector, arenaWall, arenaWall, arenaWall},

    // ---- Alcove perimeter (front = 11). ----
    {34, 36, 11, noSector, alcoveWall, alcoveWall, alcoveWall}, // N
    {36, 37, 11, noSector, alcoveWall, alcoveWall, alcoveWall}, // E
    {37, 35, 11, noSector, alcoveWall, alcoveWall, alcoveWall}, // S
};

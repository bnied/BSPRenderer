// Hand-authored map + level/math types.
//
// Sectors (12):
//   0 hub          floor   0, ceil  80, warm tan
//   1 (vestigial)  floor  80, ceil  80                 — unreferenced; the
//                                                       octagonal pillar walls
//                                                       are one-sided. Kept to
//                                                       avoid renumbering.
//   2 catwalk      floor  20, ceil  88, deep green     — first step above hub
//   3 pit          floor -20, ceil  50, violet         — 20 deep so you can climb back out
//   4 corridor     floor   4, ceil  72, blue
//   5 arena        floor  16, ceil 100, deep red
//   6 stair 1      floor  30, ceil  88, orange
//   7 stair 2      floor  40, ceil  90, gold
//   8 stair 3      floor  50, ceil  92, lime
//   9 stair 4      floor  60, ceil  94, cyan
//  10 overlook     floor  70, ceil 130, bright cool    — top of staircase
//  11 alcove       floor  30, ceil 110, magenta        — east of arena

const std = @import("std");

// ---------------------------------------------------------------------------
// Math primitives
// ---------------------------------------------------------------------------

pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn scale(a: Vec2, s: f64) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub fn dot(a: Vec2, b: Vec2) f64 {
        return a.x * b.x + a.y * b.y;
    }
    pub fn length(a: Vec2) f64 {
        return @sqrt(a.x * a.x + a.y * a.y);
    }
};

pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub fn clampD(x: f64, lo: f64, hi: f64) f64 {
    return if (x < lo) lo else if (x > hi) hi else x;
}

// shade multiplies RGB by a brightness factor clamped to [0.12, 1.0]. The
// floor keeps far geometry from going pure black, which would make portals
// look like holes in the screen.
pub fn shade(c: RGBA, f: f64) RGBA {
    const k = clampD(f, 0.12, 1.0);
    return .{
        .r = @intFromFloat(@as(f64, @floatFromInt(c.r)) * k),
        .g = @intFromFloat(@as(f64, @floatFromInt(c.g)) * k),
        .b = @intFromFloat(@as(f64, @floatFromInt(c.b)) * k),
        .a = 255,
    };
}

// ---------------------------------------------------------------------------
// Level types
// ---------------------------------------------------------------------------

// noSector is the sentinel for "no back side" — i.e. a one-sided solid wall.
pub const no_sector: i32 = -1;

pub const Sector = struct {
    floor_h: f64,
    ceil_h: f64,
    floor_color: RGBA,
    ceil_color: RGBA,
    light: f64 = 1.0,
};

pub const LineDef = struct {
    v1: u32,
    v2: u32,
    front_sector: i32,
    back_sector: i32 = no_sector,
    wall_color: RGBA,
    upper_color: RGBA,
    lower_color: RGBA,
};

// Seg is a renderable wall segment. v1/v2 are world-space points (not vertex
// indices) because the BSP builder may split a seg at a partition crossing.
pub const Seg = struct {
    v1: Vec2,
    v2: Vec2,
    front_sector: i32,
    back_sector: i32 = no_sector,
    linedef_index: u32 = 0,
};

// Level bundles the four map arrays as slices, replacing what used to be
// file-level globals. It carries no ownership: `showcase` below points its
// slices straight at comptime `..._data` constants, so the whole value lives
// in .rodata — constructing it costs nothing at runtime. Callers thread a
// `Level` (or `*const Level`) explicitly instead of reaching for globals.
pub const Level = struct {
    vertices: []const Vec2,
    sectors:  []const Sector,
    linedefs: []const LineDef,
    segs:     []const Seg,
};

// ---------------------------------------------------------------------------
// Authored level data
// ---------------------------------------------------------------------------

const vertices_data = [_]Vec2{
    // Hub perimeter
    .{ .x = 0,   .y = 0   }, //  0 hub NW
    .{ .x = 80,  .y = 0   }, //  1 hub N opening west (catwalk entry)
    .{ .x = 160, .y = 0   }, //  2 hub N opening east
    .{ .x = 240, .y = 0   }, //  3 hub NE
    .{ .x = 240, .y = 80  }, //  4 hub E opening N (corridor entry)
    .{ .x = 240, .y = 160 }, //  5 hub E opening S
    .{ .x = 240, .y = 240 }, //  6 hub SE
    .{ .x = 160, .y = 240 }, //  7 hub S opening east (pit entry)
    .{ .x = 80,  .y = 240 }, //  8 hub S opening west
    .{ .x = 0,   .y = 240 }, //  9 hub SW
    // Octagonal pillar diagonals (cardinals at 38..41).
    .{ .x = 99,  .y = 99  }, // 10 pillar NW
    .{ .x = 141, .y = 99  }, // 11 pillar NE
    .{ .x = 141, .y = 141 }, // 12 pillar SE
    .{ .x = 99,  .y = 141 }, // 13 pillar SW
    // Catwalk
    .{ .x = 80,  .y = -80 }, // 14 catwalk NW (= stair 1 SW)
    .{ .x = 160, .y = -80 }, // 15 catwalk NE (= stair 1 SE)
    // Pit (trapezoid widening southward)
    .{ .x = 60,  .y = 320 }, // 16 pit SW
    .{ .x = 180, .y = 320 }, // 17 pit SE
    // Corridor + arena (corridor walls are diagonal)
    .{ .x = 340, .y = 60  }, // 18 corridor NE / arena NW
    .{ .x = 340, .y = 180 }, // 19 corridor SE / arena SW
    .{ .x = 440, .y = 60  }, // 20 arena NE
    .{ .x = 440, .y = 180 }, // 21 arena SE
    // Staircase
    .{ .x = 80,  .y = -130 }, // 22 stair 1 NW
    .{ .x = 160, .y = -130 }, // 23 stair 1 NE
    .{ .x = 80,  .y = -180 }, // 24 stair 2 NW
    .{ .x = 160, .y = -180 }, // 25 stair 2 NE
    .{ .x = 80,  .y = -230 }, // 26 stair 3 NW
    .{ .x = 160, .y = -230 }, // 27 stair 3 NE
    .{ .x = 80,  .y = -280 }, // 28 stair 4 NW
    .{ .x = 160, .y = -280 }, // 29 stair 4 NE
    // Overlook (wider than the stair shaft)
    .{ .x = 20,  .y = -280 }, // 30 overlook SW
    .{ .x = 220, .y = -280 }, // 31 overlook SE
    .{ .x = 20,  .y = -380 }, // 32 overlook NW
    .{ .x = 220, .y = -380 }, // 33 overlook NE
    // Arena east-wall split + alcove
    .{ .x = 440, .y = 100 }, // 34 arena E split N / alcove SW
    .{ .x = 440, .y = 140 }, // 35 arena E split S / alcove NW
    .{ .x = 540, .y = 100 }, // 36 alcove SE
    .{ .x = 540, .y = 140 }, // 37 alcove NE
    // Octagonal pillar cardinal vertices (diagonals at 10..13).
    .{ .x = 120, .y = 90  }, // 38 pillar N
    .{ .x = 150, .y = 120 }, // 39 pillar E
    .{ .x = 120, .y = 150 }, // 40 pillar S
    .{ .x = 90,  .y = 120 }, // 41 pillar W
};

const main_wall: RGBA     = .{ .r = 158, .g = 144, .b = 115 };
const main_upper: RGBA    = .{ .r = 110, .g = 105, .b = 92  };
const main_lower: RGBA    = .{ .r = 118, .g = 96,  .b = 72  };
const pillar_wall: RGBA   = .{ .r = 210, .g = 215, .b = 225 };
const catwalk_wall: RGBA  = .{ .r = 108, .g = 170, .b = 82  };
const pit_wall: RGBA      = .{ .r = 140, .g = 100, .b = 180 };
const corr_wall: RGBA     = .{ .r = 94,  .g = 134, .b = 200 };
const arena_wall: RGBA    = .{ .r = 196, .g = 90,  .b = 62  };
const arena_upper: RGBA   = .{ .r = 140, .g = 70,  .b = 50  };
const arena_lower: RGBA   = .{ .r = 220, .g = 130, .b = 90  };
const stair1_wall: RGBA   = .{ .r = 210, .g = 130, .b = 70  };
const stair2_wall: RGBA   = .{ .r = 220, .g = 180, .b = 80  };
const stair3_wall: RGBA   = .{ .r = 140, .g = 210, .b = 90  };
const stair4_wall: RGBA   = .{ .r = 90,  .g = 190, .b = 220 };
const overlook_wall: RGBA = .{ .r = 210, .g = 220, .b = 235 };
const alcove_wall: RGBA   = .{ .r = 220, .g = 140, .b = 190 };

const sectors_data = [_]Sector{
    // 0: Hub.
    .{ .floor_h =   0, .ceil_h =  80, .floor_color = .{ .r =  82, .g =  76, .b =  60 }, .ceil_color = .{ .r =  50, .g =  56, .b =  70 }, .light = 0.85 },
    // 1: Vestigial (was pillar interior; pillar walls are one-sided now).
    .{ .floor_h =  80, .ceil_h =  80, .floor_color = .{ .r =  40, .g =  40, .b =  45 }, .ceil_color = .{ .r =  40, .g =  40, .b =  45 }, .light = 0.5 },
    // 2: Catwalk — green raised platform.
    .{ .floor_h =  20, .ceil_h =  88, .floor_color = .{ .r =  50, .g =  78, .b =  50 }, .ceil_color = .{ .r =  35, .g =  55, .b =  40 }, .light = 0.95 },
    // 3: Pit — sunken violet. Floor at -20 (not deeper) because maxStepUp = 24.
    .{ .floor_h = -20, .ceil_h =  50, .floor_color = .{ .r =  60, .g =  40, .b =  90 }, .ceil_color = .{ .r =  40, .g =  28, .b =  60 }, .light = 0.65 },
    // 4: East corridor — slight step up.
    .{ .floor_h =   4, .ceil_h =  72, .floor_color = .{ .r =  48, .g =  62, .b =  96 }, .ceil_color = .{ .r =  34, .g =  46, .b =  78 }, .light = 0.82 },
    // 5: Arena — deep red, taller ceiling.
    .{ .floor_h =  16, .ceil_h = 100, .floor_color = .{ .r = 112, .g =  62, .b =  46 }, .ceil_color = .{ .r =  72, .g =  44, .b =  34 }, .light = 0.95 },
    // 6: Stair 1 — orange.
    .{ .floor_h =  30, .ceil_h =  88, .floor_color = .{ .r = 170, .g = 110, .b =  70 }, .ceil_color = .{ .r = 120, .g =  70, .b =  40 }, .light = 0.88 },
    // 7: Stair 2 — gold.
    .{ .floor_h =  40, .ceil_h =  90, .floor_color = .{ .r = 200, .g = 170, .b =  70 }, .ceil_color = .{ .r = 150, .g = 120, .b =  40 }, .light = 0.90 },
    // 8: Stair 3 — lime.
    .{ .floor_h =  50, .ceil_h =  92, .floor_color = .{ .r = 130, .g = 200, .b =  80 }, .ceil_color = .{ .r =  80, .g = 150, .b =  50 }, .light = 0.92 },
    // 9: Stair 4 — cyan.
    .{ .floor_h =  60, .ceil_h =  94, .floor_color = .{ .r =  80, .g = 180, .b = 200 }, .ceil_color = .{ .r =  40, .g = 130, .b = 160 }, .light = 0.94 },
    // 10: Overlook — bright cool, much taller ceiling.
    .{ .floor_h =  70, .ceil_h = 130, .floor_color = .{ .r = 200, .g = 210, .b = 230 }, .ceil_color = .{ .r = 140, .g = 160, .b = 200 }, .light = 1.0 },
    // 11: Arena alcove — magenta.
    .{ .floor_h =  30, .ceil_h = 110, .floor_color = .{ .r = 210, .g = 130, .b = 180 }, .ceil_color = .{ .r = 160, .g =  80, .b = 130 }, .light = 0.85 },
};

const linedefs_data = [_]LineDef{
    // ---- Hub perimeter (front = 0) ----
    .{ .v1 = 0, .v2 = 1, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 1, .v2 = 2, .front_sector = 0, .back_sector = 2,         .wall_color = main_wall, .upper_color = main_upper, .lower_color = catwalk_wall }, // → catwalk
    .{ .v1 = 2, .v2 = 3, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 3, .v2 = 4, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 4, .v2 = 5, .front_sector = 0, .back_sector = 4,         .wall_color = main_wall, .upper_color = corr_wall,  .lower_color = corr_wall },    // → corridor
    .{ .v1 = 5, .v2 = 6, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 6, .v2 = 7, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 7, .v2 = 8, .front_sector = 0, .back_sector = 3,         .wall_color = main_wall, .upper_color = pit_wall,   .lower_color = main_lower },   // → pit
    .{ .v1 = 8, .v2 = 9, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },
    .{ .v1 = 9, .v2 = 0, .front_sector = 0, .back_sector = no_sector, .wall_color = main_wall, .upper_color = main_upper, .lower_color = main_lower },

    // ---- Octagonal pillar (one-sided, 8 facets, CW math).
    // Loop: N → NW → W → SW → S → SE → E → NE → N. ----
    .{ .v1 = 38, .v2 = 10, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 10, .v2 = 41, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 41, .v2 = 13, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 13, .v2 = 40, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 40, .v2 = 12, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 12, .v2 = 39, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 39, .v2 = 11, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },
    .{ .v1 = 11, .v2 = 38, .front_sector = 0, .back_sector = no_sector, .wall_color = pillar_wall, .upper_color = pillar_wall, .lower_color = pillar_wall },

    // ---- Catwalk (front = 2). N wall is a portal to stair 1. ----
    .{ .v1 =  1, .v2 = 14, .front_sector = 2, .back_sector = no_sector, .wall_color = catwalk_wall, .upper_color = catwalk_wall, .lower_color = catwalk_wall },
    .{ .v1 = 14, .v2 = 15, .front_sector = 2, .back_sector = 6,         .wall_color = catwalk_wall, .upper_color = catwalk_wall, .lower_color = stair1_wall }, // → stair 1
    .{ .v1 = 15, .v2 =  2, .front_sector = 2, .back_sector = no_sector, .wall_color = catwalk_wall, .upper_color = catwalk_wall, .lower_color = catwalk_wall },

    // ---- Pit perimeter (front = 3, CCW math) ----
    .{ .v1 =  7, .v2 = 17, .front_sector = 3, .back_sector = no_sector, .wall_color = pit_wall, .upper_color = pit_wall, .lower_color = pit_wall },
    .{ .v1 = 17, .v2 = 16, .front_sector = 3, .back_sector = no_sector, .wall_color = pit_wall, .upper_color = pit_wall, .lower_color = pit_wall },
    .{ .v1 = 16, .v2 =  8, .front_sector = 3, .back_sector = no_sector, .wall_color = pit_wall, .upper_color = pit_wall, .lower_color = pit_wall },

    // ---- East corridor (front = 4) ----
    .{ .v1 =  4, .v2 = 18, .front_sector = 4, .back_sector = no_sector, .wall_color = corr_wall, .upper_color = corr_wall,   .lower_color = corr_wall },
    .{ .v1 = 18, .v2 = 19, .front_sector = 4, .back_sector = 5,         .wall_color = corr_wall, .upper_color = arena_upper, .lower_color = arena_lower }, // → arena
    .{ .v1 = 19, .v2 =  5, .front_sector = 4, .back_sector = no_sector, .wall_color = corr_wall, .upper_color = corr_wall,   .lower_color = corr_wall },

    // ---- Arena perimeter (front = 5). E wall split into 3 to host alcove portal. ----
    .{ .v1 = 18, .v2 = 20, .front_sector = 5, .back_sector = no_sector, .wall_color = arena_wall, .upper_color = arena_wall, .lower_color = arena_wall }, // N
    .{ .v1 = 20, .v2 = 34, .front_sector = 5, .back_sector = no_sector, .wall_color = arena_wall, .upper_color = arena_wall, .lower_color = arena_wall }, // E top
    .{ .v1 = 21, .v2 = 19, .front_sector = 5, .back_sector = no_sector, .wall_color = arena_wall, .upper_color = arena_wall, .lower_color = arena_wall }, // S

    // ---- Staircase: 4 steps + overlook. ----
    .{ .v1 = 14, .v2 = 22, .front_sector = 6, .back_sector = no_sector, .wall_color = stair1_wall, .upper_color = stair1_wall, .lower_color = stair1_wall },
    .{ .v1 = 22, .v2 = 23, .front_sector = 6, .back_sector = 7,         .wall_color = stair1_wall, .upper_color = stair1_wall, .lower_color = stair2_wall },
    .{ .v1 = 23, .v2 = 15, .front_sector = 6, .back_sector = no_sector, .wall_color = stair1_wall, .upper_color = stair1_wall, .lower_color = stair1_wall },
    .{ .v1 = 22, .v2 = 24, .front_sector = 7, .back_sector = no_sector, .wall_color = stair2_wall, .upper_color = stair2_wall, .lower_color = stair2_wall },
    .{ .v1 = 24, .v2 = 25, .front_sector = 7, .back_sector = 8,         .wall_color = stair2_wall, .upper_color = stair2_wall, .lower_color = stair3_wall },
    .{ .v1 = 25, .v2 = 23, .front_sector = 7, .back_sector = no_sector, .wall_color = stair2_wall, .upper_color = stair2_wall, .lower_color = stair2_wall },
    .{ .v1 = 24, .v2 = 26, .front_sector = 8, .back_sector = no_sector, .wall_color = stair3_wall, .upper_color = stair3_wall, .lower_color = stair3_wall },
    .{ .v1 = 26, .v2 = 27, .front_sector = 8, .back_sector = 9,         .wall_color = stair3_wall, .upper_color = stair3_wall, .lower_color = stair4_wall },
    .{ .v1 = 27, .v2 = 25, .front_sector = 8, .back_sector = no_sector, .wall_color = stair3_wall, .upper_color = stair3_wall, .lower_color = stair3_wall },
    .{ .v1 = 26, .v2 = 28, .front_sector = 9, .back_sector = no_sector, .wall_color = stair4_wall, .upper_color = stair4_wall, .lower_color = stair4_wall },
    .{ .v1 = 28, .v2 = 29, .front_sector = 9, .back_sector = 10,        .wall_color = stair4_wall, .upper_color = stair4_wall, .lower_color = overlook_wall },
    .{ .v1 = 29, .v2 = 27, .front_sector = 9, .back_sector = no_sector, .wall_color = stair4_wall, .upper_color = stair4_wall, .lower_color = stair4_wall },
    // Overlook (front = 10) — five solid walls.
    .{ .v1 = 28, .v2 = 30, .front_sector = 10, .back_sector = no_sector, .wall_color = overlook_wall, .upper_color = overlook_wall, .lower_color = overlook_wall },
    .{ .v1 = 30, .v2 = 32, .front_sector = 10, .back_sector = no_sector, .wall_color = overlook_wall, .upper_color = overlook_wall, .lower_color = overlook_wall },
    .{ .v1 = 32, .v2 = 33, .front_sector = 10, .back_sector = no_sector, .wall_color = overlook_wall, .upper_color = overlook_wall, .lower_color = overlook_wall },
    .{ .v1 = 33, .v2 = 31, .front_sector = 10, .back_sector = no_sector, .wall_color = overlook_wall, .upper_color = overlook_wall, .lower_color = overlook_wall },
    .{ .v1 = 31, .v2 = 29, .front_sector = 10, .back_sector = no_sector, .wall_color = overlook_wall, .upper_color = overlook_wall, .lower_color = overlook_wall },

    // ---- Arena east middle = alcove portal + remaining E split. ----
    .{ .v1 = 34, .v2 = 35, .front_sector = 5, .back_sector = 11,        .wall_color = arena_wall, .upper_color = arena_wall, .lower_color = alcove_wall }, // → alcove
    .{ .v1 = 35, .v2 = 21, .front_sector = 5, .back_sector = no_sector, .wall_color = arena_wall, .upper_color = arena_wall, .lower_color = arena_wall },

    // ---- Alcove perimeter (front = 11). ----
    .{ .v1 = 34, .v2 = 36, .front_sector = 11, .back_sector = no_sector, .wall_color = alcove_wall, .upper_color = alcove_wall, .lower_color = alcove_wall }, // N
    .{ .v1 = 36, .v2 = 37, .front_sector = 11, .back_sector = no_sector, .wall_color = alcove_wall, .upper_color = alcove_wall, .lower_color = alcove_wall }, // E
    .{ .v1 = 37, .v2 = 35, .front_sector = 11, .back_sector = no_sector, .wall_color = alcove_wall, .upper_color = alcove_wall, .lower_color = alcove_wall }, // S
};

// ---------------------------------------------------------------------------
// Comptime seg generation
//
// The other ports call generateSegs() at startup; Zig computes the seg list at
// compile time, so it lives in .rodata and there's no runtime initialization.
// One-sided linedefs produce one seg; two-sided linedefs produce two (one per
// side with sectors swapped, so the renderer can draw each side from the
// right front sector).
// ---------------------------------------------------------------------------

const segs_data: []const Seg = blk: {
    @setEvalBranchQuota(20_000);
    var buf: [linedefs_data.len * 2]Seg = undefined;
    var n: usize = 0;
    for (linedefs_data, 0..) |l, i| {
        const a = vertices_data[l.v1];
        const b = vertices_data[l.v2];
        buf[n] = .{
            .v1 = a,
            .v2 = b,
            .front_sector = l.front_sector,
            .back_sector = l.back_sector,
            .linedef_index = @intCast(i),
        };
        n += 1;
        if (l.back_sector != no_sector) {
            buf[n] = .{
                .v1 = b,
                .v2 = a,
                .front_sector = l.back_sector,
                .back_sector = l.front_sector,
                .linedef_index = @intCast(i),
            };
            n += 1;
        }
    }
    const final = buf;
    break :blk final[0..n];
};

// The one authored level. Slices point at the comptime `..._data` constants
// above, so `showcase` is itself a comptime value in .rodata — no allocation,
// no startup init.
pub const showcase: Level = .{
    .vertices = &vertices_data,
    .sectors  = &sectors_data,
    .linedefs = &linedefs_data,
    .segs     = segs_data,
};

//! Hand-authored map.
//!
//! Sectors (12):
//!   0  hub          floor   0, ceil  80, warm tan
//!   1  (vestigial)  floor  80, ceil  80               — unreferenced; the
//!                                                      octagonal pillar walls
//!                                                      are one-sided. Kept to
//!                                                      avoid renumbering.
//!   2  catwalk      floor  20, ceil  88, deep green   — first step above hub
//!   3  pit          floor -20, ceil  50, violet     — 20 deep so you can climb back out
//!   4  corridor     floor   4, ceil  72, blue
//!   5  arena        floor  16, ceil 100, deep red
//!   6  stair 1      floor  30, ceil  88, orange
//!   7  stair 2      floor  40, ceil  90, gold
//!   8  stair 3      floor  50, ceil  92, lime
//!   9  stair 4      floor  60, ceil  94, cyan
//!  10  overlook     floor  70, ceil 130, bright cool  — top of staircase
//!  11  alcove       floor  30, ceil 110, magenta      — east of arena

use crate::geometry::{LineDef, Sector, Seg, NO_SECTOR};
use crate::math_utils::{Rgba, Vec2};

/// The map, as an owned object instead of three loose module-level statics.
///
/// A `Level` owns the hand-authored geometry (vertices, sectors, linedefs) and
/// knows how to flatten its linedefs into the renderable seg list the BSP
/// consumes. Passing a `&Level` into the BSP builder, the [`crate::player::Player`],
/// and the [`crate::renderer::Renderer`] makes the map dependency explicit and
/// keeps the world out of global state — there is no reason two `Level`s
/// couldn't coexist.
pub struct Level {
    pub vertices: Vec<Vec2>,
    pub sectors: Vec<Sector>,
    pub linedefs: Vec<LineDef>,
}

impl Level {
    /// The single hand-authored showcase map. See the module-level doc comment
    /// for the sector table.
    pub fn showcase() -> Self {
        Self {
            vertices: VERTICES.to_vec(),
            sectors: SECTORS.to_vec(),
            linedefs: LINEDEFS.to_vec(),
        }
    }

    /// Borrow sector `i`.
    pub fn sector(&self, i: usize) -> &Sector {
        &self.sectors[i]
    }

    /// Flatten the linedef list into the seg list that the BSP builder will
    /// consume.
    ///
    /// One-sided linedefs produce ONE seg in their authored direction (front
    /// side only, because the back is solid and never visible).
    ///
    /// Two-sided linedefs produce TWO segs — the second runs in reverse and has
    /// its front/back sectors swapped. The BSP needs both because each side of a
    /// portal will be rasterized from its own sector during traversal, with its
    /// own ceiling/floor heights and per-sector light.
    pub fn generate_segs(&self) -> Vec<Seg> {
        let mut out = Vec::with_capacity(self.linedefs.len() * 2);
        for (i, l) in self.linedefs.iter().enumerate() {
            let a = self.vertices[l.v1];
            let b = self.vertices[l.v2];
            // Authored direction (front side).
            out.push(Seg {
                v1: a,
                v2: b,
                front_sector: l.front_sector,
                back_sector: l.back_sector,
                linedef_index: i,
            });
            // Reverse direction (back side) for two-sided linedefs.
            if l.back_sector != NO_SECTOR {
                out.push(Seg {
                    v1: b,
                    v2: a,
                    front_sector: l.back_sector as usize,
                    back_sector: l.front_sector as i32,
                    linedef_index: i,
                });
            }
        }
        out
    }
}

static VERTICES: [Vec2; 42] = [
    // Hub perimeter
    Vec2::new(0.0, 0.0),       //  0  hub NW
    Vec2::new(80.0, 0.0),      //  1  hub N opening west (catwalk entry)
    Vec2::new(160.0, 0.0),     //  2  hub N opening east
    Vec2::new(240.0, 0.0),     //  3  hub NE
    Vec2::new(240.0, 80.0),    //  4  hub E opening N (corridor entry)
    Vec2::new(240.0, 160.0),   //  5  hub E opening S
    Vec2::new(240.0, 240.0),   //  6  hub SE
    Vec2::new(160.0, 240.0),   //  7  hub S opening east (pit entry)
    Vec2::new(80.0, 240.0),    //  8  hub S opening west
    Vec2::new(0.0, 240.0),     //  9  hub SW
    // Octagonal pillar diagonals (cardinals at 38..41).
    Vec2::new(99.0, 99.0),     // 10  pillar NW
    Vec2::new(141.0, 99.0),    // 11  pillar NE
    Vec2::new(141.0, 141.0),   // 12  pillar SE
    Vec2::new(99.0, 141.0),    // 13  pillar SW
    // Catwalk
    Vec2::new(80.0, -80.0),    // 14  catwalk NW (= stair 1 SW)
    Vec2::new(160.0, -80.0),   // 15  catwalk NE (= stair 1 SE)
    // Pit (trapezoid widening southward)
    Vec2::new(60.0, 320.0),    // 16  pit SW
    Vec2::new(180.0, 320.0),   // 17  pit SE
    // Corridor + arena
    Vec2::new(340.0, 60.0),    // 18  corridor NE / arena NW
    Vec2::new(340.0, 180.0),   // 19  corridor SE / arena SW
    Vec2::new(440.0, 60.0),    // 20  arena NE
    Vec2::new(440.0, 180.0),   // 21  arena SE
    // Staircase
    Vec2::new(80.0, -130.0),   // 22  stair 1 NW
    Vec2::new(160.0, -130.0),  // 23  stair 1 NE
    Vec2::new(80.0, -180.0),   // 24  stair 2 NW
    Vec2::new(160.0, -180.0),  // 25  stair 2 NE
    Vec2::new(80.0, -230.0),   // 26  stair 3 NW
    Vec2::new(160.0, -230.0),  // 27  stair 3 NE
    Vec2::new(80.0, -280.0),   // 28  stair 4 NW
    Vec2::new(160.0, -280.0),  // 29  stair 4 NE
    // Overlook (wider than the stair shaft)
    Vec2::new(20.0, -280.0),   // 30  overlook SW
    Vec2::new(220.0, -280.0),  // 31  overlook SE
    Vec2::new(20.0, -380.0),   // 32  overlook NW
    Vec2::new(220.0, -380.0),  // 33  overlook NE
    // Arena east-wall split + alcove
    Vec2::new(440.0, 100.0),   // 34  arena E split N / alcove SW
    Vec2::new(440.0, 140.0),   // 35  arena E split S / alcove NW
    Vec2::new(540.0, 100.0),   // 36  alcove SE
    Vec2::new(540.0, 140.0),   // 37  alcove NE
    // Octagonal pillar cardinal vertices.
    Vec2::new(120.0, 90.0),    // 38  pillar N
    Vec2::new(150.0, 120.0),   // 39  pillar E
    Vec2::new(120.0, 150.0),   // 40  pillar S
    Vec2::new(90.0, 120.0),    // 41  pillar W
];

const MAIN_WALL: Rgba = Rgba::new(158, 144, 115, 255);
const MAIN_UPPER: Rgba = Rgba::new(110, 105, 92, 255);
const MAIN_LOWER: Rgba = Rgba::new(118, 96, 72, 255);
const PILLAR_WALL: Rgba = Rgba::new(210, 215, 225, 255);
const CATWALK_WALL: Rgba = Rgba::new(108, 170, 82, 255);
const PIT_WALL: Rgba = Rgba::new(140, 100, 180, 255);
const CORR_WALL: Rgba = Rgba::new(94, 134, 200, 255);
const ARENA_WALL: Rgba = Rgba::new(196, 90, 62, 255);
const ARENA_UPPER: Rgba = Rgba::new(140, 70, 50, 255);
const ARENA_LOWER: Rgba = Rgba::new(220, 130, 90, 255);
const STAIR1_WALL: Rgba = Rgba::new(210, 130, 70, 255);
const STAIR2_WALL: Rgba = Rgba::new(220, 180, 80, 255);
const STAIR3_WALL: Rgba = Rgba::new(140, 210, 90, 255);
const STAIR4_WALL: Rgba = Rgba::new(90, 190, 220, 255);
const OVERLOOK_WALL: Rgba = Rgba::new(210, 220, 235, 255);
const ALCOVE_WALL: Rgba = Rgba::new(220, 140, 190, 255);

static SECTORS: [Sector; 12] = [
    // 0: Hub.
    Sector { floor_h: 0.0, ceil_h: 80.0,
             floor_color: Rgba::new(82, 76, 60, 255),
             ceil_color: Rgba::new(50, 56, 70, 255),
             light: 0.85 },
    // 1: Vestigial (was pillar interior).
    Sector { floor_h: 80.0, ceil_h: 80.0,
             floor_color: Rgba::new(40, 40, 45, 255),
             ceil_color: Rgba::new(40, 40, 45, 255),
             light: 0.5 },
    // 2: Catwalk — green raised platform.
    Sector { floor_h: 20.0, ceil_h: 88.0,
             floor_color: Rgba::new(50, 78, 50, 255),
             ceil_color: Rgba::new(35, 55, 40, 255),
             light: 0.95 },
    // 3: Pit — sunken violet. Floor at -20 (not deeper) because
    // MAX_STEP_UP = 24, so anything deeper would trap the player in the pit.
    Sector { floor_h: -20.0, ceil_h: 50.0,
             floor_color: Rgba::new(60, 40, 90, 255),
             ceil_color: Rgba::new(40, 28, 60, 255),
             light: 0.65 },
    // 4: East corridor — slight step up.
    Sector { floor_h: 4.0, ceil_h: 72.0,
             floor_color: Rgba::new(48, 62, 96, 255),
             ceil_color: Rgba::new(34, 46, 78, 255),
             light: 0.82 },
    // 5: Arena — deep red, taller ceiling.
    Sector { floor_h: 16.0, ceil_h: 100.0,
             floor_color: Rgba::new(112, 62, 46, 255),
             ceil_color: Rgba::new(72, 44, 34, 255),
             light: 0.95 },
    // 6: Stair 1 — orange.
    Sector { floor_h: 30.0, ceil_h: 88.0,
             floor_color: Rgba::new(170, 110, 70, 255),
             ceil_color: Rgba::new(120, 70, 40, 255),
             light: 0.88 },
    // 7: Stair 2 — gold.
    Sector { floor_h: 40.0, ceil_h: 90.0,
             floor_color: Rgba::new(200, 170, 70, 255),
             ceil_color: Rgba::new(150, 120, 40, 255),
             light: 0.90 },
    // 8: Stair 3 — lime.
    Sector { floor_h: 50.0, ceil_h: 92.0,
             floor_color: Rgba::new(130, 200, 80, 255),
             ceil_color: Rgba::new(80, 150, 50, 255),
             light: 0.92 },
    // 9: Stair 4 — cyan.
    Sector { floor_h: 60.0, ceil_h: 94.0,
             floor_color: Rgba::new(80, 180, 200, 255),
             ceil_color: Rgba::new(40, 130, 160, 255),
             light: 0.94 },
    // 10: Overlook — bright cool, much taller ceiling.
    Sector { floor_h: 70.0, ceil_h: 130.0,
             floor_color: Rgba::new(200, 210, 230, 255),
             ceil_color: Rgba::new(140, 160, 200, 255),
             light: 1.0 },
    // 11: Arena alcove — magenta.
    Sector { floor_h: 30.0, ceil_h: 110.0,
             floor_color: Rgba::new(210, 130, 180, 255),
             ceil_color: Rgba::new(160, 80, 130, 255),
             light: 0.85 },
];

const fn ld(v1: usize, v2: usize, front: usize, back: i32, w: Rgba, u: Rgba, l: Rgba) -> LineDef {
    LineDef {
        v1,
        v2,
        front_sector: front,
        back_sector: back,
        wall_color: w,
        upper_color: u,
        lower_color: l,
    }
}

static LINEDEFS: [LineDef; 52] = [
    // ---- Hub perimeter (front = 0) ----
    ld(0, 1, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(1, 2, 0, 2, MAIN_WALL, MAIN_UPPER, CATWALK_WALL),
    ld(2, 3, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(3, 4, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(4, 5, 0, 4, MAIN_WALL, CORR_WALL, CORR_WALL),
    ld(5, 6, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(6, 7, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(7, 8, 0, 3, MAIN_WALL, PIT_WALL, MAIN_LOWER),
    ld(8, 9, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(9, 0, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),

    // ---- Octagonal pillar (one-sided, 8 facets, CW math) ----
    ld(38, 10, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(10, 41, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(41, 13, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(13, 40, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(40, 12, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(12, 39, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(39, 11, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),
    ld(11, 38, 0, NO_SECTOR, PILLAR_WALL, PILLAR_WALL, PILLAR_WALL),

    // ---- Catwalk (front = 2). N wall is a portal to stair 1. ----
    ld(1, 14, 2, NO_SECTOR, CATWALK_WALL, CATWALK_WALL, CATWALK_WALL),
    ld(14, 15, 2, 6, CATWALK_WALL, CATWALK_WALL, STAIR1_WALL),
    ld(15, 2, 2, NO_SECTOR, CATWALK_WALL, CATWALK_WALL, CATWALK_WALL),

    // ---- Pit perimeter (front = 3, CCW math) ----
    ld(7, 17, 3, NO_SECTOR, PIT_WALL, PIT_WALL, PIT_WALL),
    ld(17, 16, 3, NO_SECTOR, PIT_WALL, PIT_WALL, PIT_WALL),
    ld(16, 8, 3, NO_SECTOR, PIT_WALL, PIT_WALL, PIT_WALL),

    // ---- East corridor (front = 4) ----
    ld(4, 18, 4, NO_SECTOR, CORR_WALL, CORR_WALL, CORR_WALL),
    ld(18, 19, 4, 5, CORR_WALL, ARENA_UPPER, ARENA_LOWER),
    ld(19, 5, 4, NO_SECTOR, CORR_WALL, CORR_WALL, CORR_WALL),

    // ---- Arena perimeter (front = 5). E wall split into 3. ----
    ld(18, 20, 5, NO_SECTOR, ARENA_WALL, ARENA_WALL, ARENA_WALL),
    ld(20, 34, 5, NO_SECTOR, ARENA_WALL, ARENA_WALL, ARENA_WALL),
    ld(21, 19, 5, NO_SECTOR, ARENA_WALL, ARENA_WALL, ARENA_WALL),

    // ---- Staircase: 4 steps + overlook. ----
    ld(14, 22, 6, NO_SECTOR, STAIR1_WALL, STAIR1_WALL, STAIR1_WALL),
    ld(22, 23, 6, 7, STAIR1_WALL, STAIR1_WALL, STAIR2_WALL),
    ld(23, 15, 6, NO_SECTOR, STAIR1_WALL, STAIR1_WALL, STAIR1_WALL),
    ld(22, 24, 7, NO_SECTOR, STAIR2_WALL, STAIR2_WALL, STAIR2_WALL),
    ld(24, 25, 7, 8, STAIR2_WALL, STAIR2_WALL, STAIR3_WALL),
    ld(25, 23, 7, NO_SECTOR, STAIR2_WALL, STAIR2_WALL, STAIR2_WALL),
    ld(24, 26, 8, NO_SECTOR, STAIR3_WALL, STAIR3_WALL, STAIR3_WALL),
    ld(26, 27, 8, 9, STAIR3_WALL, STAIR3_WALL, STAIR4_WALL),
    ld(27, 25, 8, NO_SECTOR, STAIR3_WALL, STAIR3_WALL, STAIR3_WALL),
    ld(26, 28, 9, NO_SECTOR, STAIR4_WALL, STAIR4_WALL, STAIR4_WALL),
    ld(28, 29, 9, 10, STAIR4_WALL, STAIR4_WALL, OVERLOOK_WALL),
    ld(29, 27, 9, NO_SECTOR, STAIR4_WALL, STAIR4_WALL, STAIR4_WALL),
    ld(28, 30, 10, NO_SECTOR, OVERLOOK_WALL, OVERLOOK_WALL, OVERLOOK_WALL),
    ld(30, 32, 10, NO_SECTOR, OVERLOOK_WALL, OVERLOOK_WALL, OVERLOOK_WALL),
    ld(32, 33, 10, NO_SECTOR, OVERLOOK_WALL, OVERLOOK_WALL, OVERLOOK_WALL),
    ld(33, 31, 10, NO_SECTOR, OVERLOOK_WALL, OVERLOOK_WALL, OVERLOOK_WALL),
    ld(31, 29, 10, NO_SECTOR, OVERLOOK_WALL, OVERLOOK_WALL, OVERLOOK_WALL),

    // ---- Arena east middle = alcove portal + remaining E split. ----
    ld(34, 35, 5, 11, ARENA_WALL, ARENA_WALL, ALCOVE_WALL),
    ld(35, 21, 5, NO_SECTOR, ARENA_WALL, ARENA_WALL, ARENA_WALL),

    // ---- Alcove perimeter (front = 11). ----
    ld(34, 36, 11, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
    ld(36, 37, 11, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
    ld(37, 35, 11, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
];

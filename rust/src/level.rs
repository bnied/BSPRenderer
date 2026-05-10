//! Hand-authored map. See the ASCII sketch in the original `Level.swift`.

use crate::geometry::{LineDef, Sector, NO_SECTOR};
use crate::math_utils::{Rgba, Vec2};

pub static VERTICES: [Vec2; 18] = [
    // Main hall perimeter
    Vec2::new(0.0, 0.0),       // 0  main NW
    Vec2::new(80.0, 0.0),      // 1  alcove opening west
    Vec2::new(140.0, 0.0),     // 2  alcove opening east
    Vec2::new(240.0, 0.0),     // 3  main NE
    Vec2::new(240.0, 80.0),    // 4  door top
    Vec2::new(240.0, 140.0),   // 5  door bottom
    Vec2::new(240.0, 200.0),   // 6  main SE
    Vec2::new(150.0, 200.0),   // 7  corridor opening east
    Vec2::new(90.0, 200.0),    // 8  corridor opening west
    Vec2::new(0.0, 200.0),     // 9  main SW
    // Alcove
    Vec2::new(80.0, -50.0),    // 10 alcove NW
    Vec2::new(140.0, -50.0),   // 11 alcove NE
    // East room
    Vec2::new(360.0, 80.0),    // 12 east NE
    Vec2::new(360.0, 140.0),   // 13 east SE
    // Corridor
    Vec2::new(200.0, 300.0),   // 14 corridor SE / south NE
    Vec2::new(140.0, 300.0),   // 15 corridor SW / south NW
    // South chamber
    Vec2::new(240.0, 360.0),   // 16 south SE
    Vec2::new(100.0, 360.0),   // 17 south SW
];

const MAIN_WALL: Rgba = Rgba::new(158, 144, 115, 255);
const MAIN_UPPER: Rgba = Rgba::new(110, 105, 92, 255);
const MAIN_LOWER: Rgba = Rgba::new(118, 96, 72, 255);
const EAST_WALL: Rgba = Rgba::new(196, 90, 62, 255);
const ALCOVE_WALL: Rgba = Rgba::new(108, 170, 82, 255);
const CORR_WALL: Rgba = Rgba::new(94, 134, 200, 255);
const SOUTH_WALL: Rgba = Rgba::new(168, 108, 206, 255);

pub static SECTORS: [Sector; 5] = [
    // 0: Main hall — warm tan
    Sector {
        floor_h: 0.0,
        ceil_h: 64.0,
        floor_color: Rgba::new(82, 76, 60, 255),
        ceil_color: Rgba::new(50, 56, 70, 255),
        light: 0.85,
    },
    // 1: East room — red, raised floor, taller ceiling
    Sector {
        floor_h: 16.0,
        ceil_h: 88.0,
        floor_color: Rgba::new(112, 62, 46, 255),
        ceil_color: Rgba::new(72, 44, 34, 255),
        light: 0.95,
    },
    // 2: Alcove — green, low ceiling, raised floor
    Sector {
        floor_h: -12.0,
        ceil_h: 48.0,
        floor_color: Rgba::new(58, 84, 52, 255),
        ceil_color: Rgba::new(42, 62, 40, 255),
        light: 0.9,
    },
    // 3: Diagonal corridor — blue, slight step up
    Sector {
        floor_h: 4.0,
        ceil_h: 68.0,
        floor_color: Rgba::new(48, 62, 96, 255),
        ceil_color: Rgba::new(34, 46, 78, 255),
        light: 0.82,
    },
    // 4: South chamber — violet, sunken floor
    Sector {
        floor_h: -12.0,
        ceil_h: 52.0,
        floor_color: Rgba::new(76, 52, 96, 255),
        ceil_color: Rgba::new(52, 38, 76, 255),
        light: 0.7,
    },
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

pub static LINEDEFS: [LineDef; 22] = [
    // ---- Main hall perimeter (front = 0) ----
    ld(0, 1, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(1, 2, 0, 2, MAIN_WALL, ALCOVE_WALL, MAIN_LOWER),
    ld(2, 3, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(3, 4, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(4, 5, 0, 1, MAIN_WALL, MAIN_UPPER, EAST_WALL),
    ld(5, 6, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(6, 7, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(7, 8, 0, 3, MAIN_WALL, CORR_WALL, CORR_WALL),
    ld(8, 9, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    ld(9, 0, 0, NO_SECTOR, MAIN_WALL, MAIN_UPPER, MAIN_LOWER),
    // ---- Alcove (front = 2) ----
    ld(1, 10, 2, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
    ld(10, 11, 2, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
    ld(11, 2, 2, NO_SECTOR, ALCOVE_WALL, ALCOVE_WALL, ALCOVE_WALL),
    // ---- East room (front = 1) ----
    ld(4, 12, 1, NO_SECTOR, EAST_WALL, EAST_WALL, EAST_WALL),
    ld(12, 13, 1, NO_SECTOR, EAST_WALL, EAST_WALL, EAST_WALL),
    ld(13, 5, 1, NO_SECTOR, EAST_WALL, EAST_WALL, EAST_WALL),
    // ---- Diagonal corridor (front = 3) ----
    ld(7, 14, 3, NO_SECTOR, CORR_WALL, CORR_WALL, CORR_WALL),
    ld(14, 15, 3, 4, CORR_WALL, CORR_WALL, SOUTH_WALL),
    ld(15, 8, 3, NO_SECTOR, CORR_WALL, CORR_WALL, CORR_WALL),
    // ---- South chamber (front = 4) ----
    ld(14, 16, 4, NO_SECTOR, SOUTH_WALL, SOUTH_WALL, SOUTH_WALL),
    ld(16, 17, 4, NO_SECTOR, SOUTH_WALL, SOUTH_WALL, SOUTH_WALL),
    ld(17, 15, 4, NO_SECTOR, SOUTH_WALL, SOUTH_WALL, SOUTH_WALL),
];

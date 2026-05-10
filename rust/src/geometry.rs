//! Geometry types — the level's "schema". The actual data lives in [`crate::level`].
//!
//! The model follows DOOM's terminology:
//!
//!   - **Sector**:  a flat-floored, flat-ceilinged region with a uniform light
//!                  level. Rooms, corridors, and alcoves are all sectors.
//!   - **LineDef**: an authored edge between two vertices. One-sided linedefs
//!                  are solid walls; two-sided linedefs are portals between
//!                  two adjacent sectors and may show upper/lower wall slivers
//!                  where the sectors' ceiling/floor heights differ.
//!   - **Seg**:     a renderable wall segment. `generate_segs` emits one Seg
//!                  per one-sided linedef and two Segs per two-sided linedef
//!                  (one per side, so the renderer can draw each side from
//!                  the perspective of its own front sector). The BSP builder
//!                  may further split segs at partition crossings.

use crate::math_utils::{Rgba, Vec2};

/// Sentinel for "no back side" — i.e. a one-sided solid wall.
/// Real sector indices are >= 0 (we use [`Option`] of `usize` would be more
/// Rust-idiomatic, but matching the other ports' wire types makes the renderer
/// math line up character-for-character with the Go/Swift originals).
pub const NO_SECTOR: i32 = -1;

/// Horizontal-floored region. Floor and ceiling are stored as world-space Z
/// heights so portals can compute upper/lower wall extents by comparing front
/// and back sector heights.
#[derive(Clone, Copy, Debug)]
pub struct Sector {
    pub floor_h: f64,
    pub ceil_h: f64,
    pub floor_color: Rgba,
    pub ceil_color: Rgba,
    /// 0..1 multiplier applied before distance falloff.
    pub light: f64,
}

/// Authored line in the map. `wall_color` is used when the linedef is
/// one-sided; `upper_color` / `lower_color` are used on two-sided linedefs to
/// fill the gaps that appear when the back sector's ceiling is lower or floor
/// is higher than the front's.
#[derive(Clone, Copy, Debug)]
pub struct LineDef {
    pub v1: usize,
    pub v2: usize,
    pub front_sector: usize,
    /// [`NO_SECTOR`] → solid one-sided wall.
    pub back_sector: i32,
    pub wall_color: Rgba,
    pub upper_color: Rgba,
    pub lower_color: Rgba,
}

/// Renderable wall segment fed into the BSP. `v1`/`v2` are world-space points
/// (not vertex indices) because the BSP builder may split a seg at a partition
/// crossing, producing intersection points that aren't in the original
/// vertices array.
#[derive(Clone, Copy, Debug)]
pub struct Seg {
    pub v1: Vec2,
    pub v2: Vec2,
    pub front_sector: usize,
    /// [`NO_SECTOR`] → solid.
    pub back_sector: i32,
    pub linedef_index: usize,
}

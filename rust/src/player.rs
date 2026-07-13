//! Player physics: movement, collision, and the camera-height policy.
//!
//! The player is a 2-D circle of radius 8 in the (x, y) plane that auto-snaps
//! its feet Z to the current sector's floor height. Step-up across portals is
//! gated by `MAX_STEP_UP`; portals whose vertical opening is shorter than
//! the player's standing height are treated as solid.
//!
//! Vertical camera motion is interesting: see [`Player::eye_z`] and
//! [`Player::eye_follow_factor`].

use std::f64::consts::PI;

use crate::bsp::Bsp;
use crate::geometry::NO_SECTOR;
use crate::level::Level;
use crate::math_utils::{clamp_f, Vec2};

/// Per-tick boolean key state. The main loop fills this in from winit
/// events; the player has no idea winit exists.
#[derive(Clone, Copy, Debug, Default)]
pub struct Input {
    pub forward: bool,
    pub back: bool,
    pub strafe_l: bool,
    pub strafe_r: bool,
    pub turn_l: bool,
    pub turn_r: bool,
}

pub struct Player {
    /// (x, y) world position.
    pub pos: Vec2,
    /// Z of the feet — tracks current sector's floor_h.
    pub feet_z: f64,
    /// Facing angle in radians; 0 = +x, π/2 = +y.
    pub angle: f64,
    /// Total horizontal field of view, radians.
    pub fov: f64,
    /// World units per second.
    pub move_speed: f64,
    /// Radians per second.
    pub rot_speed: f64,
    /// How high above the feet the eye sits (standing height).
    pub eye_over_floor: f64,
    /// See [`Player::eye_z`].
    pub eye_follow_factor: f64,
    /// Eye Z when standing in a "baseline" sector.
    pub baseline_eye_z: f64,
}

impl Player {
    /// Spawn just north of the hub's south wall, facing north — looking
    /// straight down the catwalk into the colored staircase chain. The
    /// octagonal pillar is behind the player (turn around to discover it).
    pub fn new() -> Self {
        Self {
            pos: Vec2::new(120.0, 50.0),
            feet_z: 0.0,
            angle: -PI / 2.0,
            fov: 70.0 * PI / 180.0,
            move_speed: 140.0,
            rot_speed: 2.4,
            eye_over_floor: 41.0,
            eye_follow_factor: 1.0,
            baseline_eye_z: 41.0,
        }
    }

    /// Blend two camera-height policies:
    ///
    ///   - `eye_follow_factor = 1.0` → eye is rigidly attached to feet. The
    ///     camera physically rises and falls the full step amount, but
    ///     because feet and eye move together, the floor stays at a constant
    ///     screen distance below the horizon.
    ///   - `eye_follow_factor = 0.0` → fixed-baseline camera. Eye Z never
    ///     changes; the floor's screen position reflects the sector's true
    ///     Z, so steps up/down are visible as the floor sliding on screen.
    ///   - in between → partial bobbing.
    ///
    /// We use 1.0 by default — the camera rises/falls with the player and
    /// the scene around them is what changes (back-sector ceilings come into
    /// view, upper walls open, etc.).
    pub fn eye_z(&self) -> f64 {
        let feet_baseline = self.baseline_eye_z - self.eye_over_floor;
        self.baseline_eye_z + self.eye_follow_factor * (self.feet_z - feet_baseline)
    }

    /// Advance by `dt` seconds of simulation time. Movement is axis-separated
    /// and probed against all solid linedefs so the player can slide along
    /// walls instead of getting stuck on them.
    pub fn update(&mut self, dt: f64, input: Input, level: &Level, bsp: &Bsp) {
        let rot = self.rot_speed * dt;
        let mv = self.move_speed * dt;

        if input.turn_l {
            self.angle -= rot;
        }
        if input.turn_r {
            self.angle += rot;
        }

        let cos_a = self.angle.cos();
        let sin_a = self.angle.sin();

        // Compose desired (dx, dy) in world space from the four movement keys.
        // forward = (cosA, sinA); right = (-sinA, cosA).
        let mut dx = 0.0;
        let mut dy = 0.0;
        if input.forward {
            dx += cos_a * mv;
            dy += sin_a * mv;
        }
        if input.back {
            dx -= cos_a * mv;
            dy -= sin_a * mv;
        }
        if input.strafe_l {
            dx += sin_a * mv;
            dy -= cos_a * mv;
        }
        if input.strafe_r {
            dx -= sin_a * mv;
            dy += cos_a * mv;
        }

        let radius = 8.0;
        let current_floor_h = level.sector(bsp.find_sector(self.pos)).floor_h;

        let try_x = Vec2::new(self.pos.x + dx, self.pos.y);
        if !self.collides(try_x, radius, current_floor_h, level) {
            self.pos = try_x;
        }
        let try_y = Vec2::new(self.pos.x, self.pos.y + dy);
        if !self.collides(try_y, radius, current_floor_h, level) {
            self.pos = try_y;
        }

        // Snap feet to the new sector's floor (no gravity / falling).
        self.feet_z = level.sector(bsp.find_sector(self.pos)).floor_h;
    }

    /// A linedef blocks movement if it's one-sided, OR a portal whose
    /// opening is too short, OR the back-side floor is more than
    /// `MAX_STEP_UP` above the side we're standing on.
    fn collides(&self, pos: Vec2, radius: f64, current_floor_h: f64, level: &Level) -> bool {
        const MAX_STEP_UP: f64 = 24.0;
        for l in level.linedefs.iter() {
            let a = level.vertices[l.v1];
            let b = level.vertices[l.v2];
            if point_segment_distance(pos, a, b) >= radius {
                continue;
            }
            if l.back_sector == NO_SECTOR {
                return true;
            }
            let front = level.sector(l.front_sector);
            let back = level.sector(l.back_sector as usize);

            // Portal opening must be tall enough to fit through.
            let opening_top = front.ceil_h.min(back.ceil_h);
            let opening_bottom = front.floor_h.max(back.floor_h);
            if opening_top - opening_bottom < self.eye_over_floor {
                return true;
            }

            // Step-up gate: which side is the probe entering?
            let pdx = b.x - a.x;
            let pdy = b.y - a.y;
            let side = pdx * (pos.y - a.y) - pdy * (pos.x - a.x);
            let target_floor_h = if side > 0.0 { back.floor_h } else { front.floor_h };
            if target_floor_h - current_floor_h > MAX_STEP_UP {
                return true;
            }
        }
        false
    }
}

/// Perpendicular distance from point `p` to segment `ab`, clamped to endpoints.
fn point_segment_distance(p: Vec2, a: Vec2, b: Vec2) -> f64 {
    let ab = b.sub(a);
    let l2 = ab.x * ab.x + ab.y * ab.y;
    if l2 < 1e-9 {
        return p.sub(a).length();
    }
    let mut t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2;
    t = clamp_f(t, 0.0, 1.0);
    let proj = Vec2::new(a.x + ab.x * t, a.y + ab.y * t);
    p.sub(proj).length()
}

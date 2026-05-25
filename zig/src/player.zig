// Player physics: movement, collision, and the camera-height policy.
//
// The player is a 2-D circle of radius 8 in the (x, y) plane that auto-snaps
// its feet Z to the current sector's floor height. Step-up across portals is
// gated by maxStepUp; portals whose vertical opening is shorter than the
// player's standing height are treated as solid.

const std = @import("std");
const level = @import("level.zig");
const bsp = @import("bsp.zig");
const Vec2 = level.Vec2;

// Input is the per-tick boolean key state. The SDL layer fills this in; the
// player has no idea SDL exists.
pub const Input = struct {
    forward: bool = false,
    back:    bool = false,
    strafe_l: bool = false,
    strafe_r: bool = false,
    turn_l:   bool = false,
    turn_r:   bool = false,
};

pub const Player = struct {
    // Spawn just north of the hub's south wall, facing north — looking
    // straight down the catwalk into the colored staircase chain. The
    // octagonal pillar is behind the player (turn around to discover it).
    pos: Vec2 = .{ .x = 120, .y = 50 },
    feet_z: f64 = 0,
    angle: f64 = -std.math.pi / 2.0,
    fov: f64 = 70.0 * std.math.pi / 180.0,
    move_speed: f64 = 140.0,
    rot_speed: f64 = 2.4,
    eye_over_floor: f64 = 41.0,
    eye_follow_factor: f64 = 1.0,
    baseline_eye_z: f64 = 41.0,

    // eyeZ blends two camera-height policies:
    //
    //   eye_follow_factor = 1.0  →  eye rigidly attached to feet. Camera
    //                               physically rises and falls the full step
    //                               amount, but the floor stays at a constant
    //                               screen distance below the horizon.
    //
    //   eye_follow_factor = 0.0  →  fixed-baseline camera. Eye Z never changes;
    //                               the floor's screen position reflects the
    //                               sector's true Z, so steps are visible.
    pub fn eyeZ(self: Player) f64 {
        const feet_baseline = self.baseline_eye_z - self.eye_over_floor;
        return self.baseline_eye_z + self.eye_follow_factor * (self.feet_z - feet_baseline);
    }

    pub fn update(self: *Player, dt: f64, in: Input, bsp_root: *const bsp.BSPNode) void {
        const rot = self.rot_speed * dt;
        const mv  = self.move_speed * dt;

        if (in.turn_l) self.angle -= rot;
        if (in.turn_r) self.angle += rot;

        const cosA = @cos(self.angle);
        const sinA = @sin(self.angle);

        // Compose desired (dx, dy) in world space from the four movement keys.
        // forward = (cosA, sinA); right = (-sinA, cosA).
        var dx: f64 = 0;
        var dy: f64 = 0;
        if (in.forward)  { dx += cosA * mv; dy += sinA * mv; }
        if (in.back)     { dx -= cosA * mv; dy -= sinA * mv; }
        if (in.strafe_l) { dx += sinA * mv; dy -= cosA * mv; }
        if (in.strafe_r) { dx -= sinA * mv; dy += cosA * mv; }

        // Axis-separated probe so the player slides along walls instead of
        // sticking to them.
        const radius: f64 = 8.0;
        const cur_sector: usize = @intCast(bsp.findSector(self.pos, bsp_root));
        const current_floor_h = level.sectors[cur_sector].floor_h;

        const try_x: Vec2 = .{ .x = self.pos.x + dx, .y = self.pos.y };
        if (!collides(try_x, radius, current_floor_h, self.eye_over_floor)) self.pos.x = try_x.x;
        const try_y: Vec2 = .{ .x = self.pos.x, .y = self.pos.y + dy };
        if (!collides(try_y, radius, current_floor_h, self.eye_over_floor)) self.pos.y = try_y.y;

        // Snap feet to the new sector's floor (no gravity / falling).
        const new_sector: usize = @intCast(bsp.findSector(self.pos, bsp_root));
        self.feet_z = level.sectors[new_sector].floor_h;
    }
};

// Perpendicular distance from p to segment ab, clamped to the endpoints.
fn pointSegmentDistance(p: Vec2, a: Vec2, b: Vec2) f64 {
    const ab = Vec2.sub(b, a);
    const l2 = ab.x * ab.x + ab.y * ab.y;
    if (l2 < 1e-9) return Vec2.sub(p, a).length();
    var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2;
    t = level.clampD(t, 0.0, 1.0);
    const proj: Vec2 = .{ .x = a.x + ab.x * t, .y = a.y + ab.y * t };
    return Vec2.sub(p, proj).length();
}

// collides returns true if a circle of `radius` centered at `p` is blocked
// by any linedef:
//   - solid one-sided wall, OR
//   - portal whose opening is too short to walk through, OR
//   - portal whose target floor is more than max_step_up above us.
fn collides(p: Vec2, radius: f64, current_floor_h: f64, eye_over_floor: f64) bool {
    const max_step_up: f64 = 24.0;
    for (level.linedefs) |l| {
        const a = level.vertices[l.v1];
        const b = level.vertices[l.v2];
        if (pointSegmentDistance(p, a, b) >= radius) continue;
        if (l.back_sector == level.no_sector) return true;
        const front = level.sectors[@intCast(l.front_sector)];
        const back  = level.sectors[@intCast(l.back_sector)];

        // Portal opening tall enough for the player to fit through?
        const opening_top    = @min(front.ceil_h,  back.ceil_h);
        const opening_bottom = @max(front.floor_h, back.floor_h);
        if (opening_top - opening_bottom < eye_over_floor) return true;

        // Step-up gate: which side is the probe entering?
        const pdx = b.x - a.x;
        const pdy = b.y - a.y;
        const side = pdx * (p.y - a.y) - pdy * (p.x - a.x);
        const target_floor_h = if (side > 0) back.floor_h else front.floor_h;
        if (target_floor_h - current_floor_h > max_step_up) return true;
    }
    return false;
}

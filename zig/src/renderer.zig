// Renderer — the software renderer.
//
//   pixels        — RGBA framebuffer in row-major order (4 bytes/pixel,
//                   no padding). The SDL layer hands this directly to a
//                   streaming SDL_Texture each frame.
//   y_top / y_bot — DOOM's ceilingclip / floorclip arrays. For each screen
//                   column they bound the still-open vertical range. Solid
//                   walls close their columns entirely; portals shrink the
//                   open range by their upper/lower walls.
//   visplanes     — 2 entries per sector (floor at 2*si, ceiling at 2*si+1).
//                   See visplane.zig.
//   slow_mode etc — debug aid: when enabled (Tab), each frame draws one more
//                   column than the previous one, so you can watch the BSP
//                   walk emit columns front-to-back.

const std = @import("std");
const level = @import("level.zig");
const bsp = @import("bsp.zig");
const visplane_mod = @import("visplane.zig");
const player_mod = @import("player.zig");

const Vec2 = level.Vec2;
const RGBA = level.RGBA;
const Sector = level.Sector;
const Seg = level.Seg;
const Visplane = visplane_mod.Visplane;
const Player = player_mod.Player;

pub const Renderer = struct {
    buf_w: i32,
    buf_h: i32,
    pixels: []u8,
    y_top: []i32,
    y_bot: []i32,
    visplanes: []Visplane,
    allocator: std.mem.Allocator,

    slow_mode: bool = false,
    slow_step: i32 = 0,
    slow_column_budget: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !Renderer {
        const w: usize = @intCast(width);
        const h: usize = @intCast(height);
        const pixels = try allocator.alloc(u8, w * h * 4);
        const y_top = try allocator.alloc(i32, w);
        const y_bot = try allocator.alloc(i32, w);

        const visplanes = try allocator.alloc(Visplane, level.sectors.len * 2);
        for (level.sectors, 0..) |_, si| {
            visplanes[si * 2 + 0] = try Visplane.init(allocator, @intCast(si), false, w); // floor
            visplanes[si * 2 + 1] = try Visplane.init(allocator, @intCast(si), true,  w); // ceiling
        }

        return Renderer{
            .buf_w = width,
            .buf_h = height,
            .pixels = pixels,
            .y_top = y_top,
            .y_bot = y_bot,
            .visplanes = visplanes,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Renderer) void {
        for (self.visplanes) |*vp| vp.deinit(self.allocator);
        self.allocator.free(self.visplanes);
        self.allocator.free(self.y_top);
        self.allocator.free(self.y_bot);
        self.allocator.free(self.pixels);
    }

    pub fn pixelData(self: *const Renderer) [*]const u8 {
        return self.pixels.ptr;
    }

    // render() runs one full frame:
    //   1. Reset per-column open region and per-frame visplane coverage.
    //   2. Background fill (dim ceiling/floor of player's current sector) so
    //      any column that ends up unwritten still looks plausible.
    //   3. BSP walk → drawSeg for every visible seg, front-to-back.
    //   4. Visplane pass → flat floors/ceilings rasterized via inverse projection.
    //   5. Overlays: minimap and crosshair.
    pub fn render(self: *Renderer, player: *const Player, bsp_root: *const bsp.BSPNode) void {
        var x: i32 = 0;
        while (x < self.buf_w) : (x += 1) {
            self.y_top[@intCast(x)] = 0;
            self.y_bot[@intCast(x)] = self.buf_h - 1;
        }
        for (self.visplanes) |*vp| vp.reset();

        const player_sector: usize = @intCast(bsp.findSector(player.pos, bsp_root));
        const sec = level.sectors[player_sector];
        const half_w: f64 = @as(f64, @floatFromInt(self.buf_w)) / 2.0;
        const half_h: f64 = @as(f64, @floatFromInt(self.buf_h)) / 2.0;
        const horizon: f64 = half_h;

        // Background fill — top half = sector ceiling, bottom half = floor,
        // both dimmed so legit geometry reads as brighter.
        const buf_w_u: usize = @intCast(self.buf_w);
        const half_h_i: i32 = @intFromFloat(half_h);
        var y: i32 = 0;
        while (y < self.buf_h) : (y += 1) {
            const c = if (y < half_h_i) sec.ceil_color else sec.floor_color;
            const dc = level.shade(c, 0.55);
            const row_start: usize = @as(usize, @intCast(y)) * buf_w_u * 4;
            var xi: i32 = 0;
            while (xi < self.buf_w) : (xi += 1) {
                const i = row_start + @as(usize, @intCast(xi)) * 4;
                self.pixels[i + 0] = dc.r;
                self.pixels[i + 1] = dc.g;
                self.pixels[i + 2] = dc.b;
                self.pixels[i + 3] = 255;
            }
        }

        // Pinhole camera setup. focal = halfW / tan(fov/2) gives us the
        // standard "screen plane is `focal` units in front of the eye"
        // projection.
        const fov_half_tan = @tan(player.fov / 2.0);
        const focal = half_w / fov_half_tan;
        const eye_z = player.eyeZ();
        const cosA = @cos(player.angle);
        const sinA = @sin(player.angle);

        const ctx: DrawCtx = .{
            .self = self,
            .player = player,
            .cosA = cosA, .sinA = sinA,
            .half_w = half_w, .horizon = horizon,
            .fov_half_tan = fov_half_tan, .focal = focal,
            .eye_z = eye_z,
        };

        if (self.slow_mode) {
            // Buffered traversal so we can cap at `slow_step` columns.
            self.slow_column_budget = self.slow_step;
            bsp.traverseBSP(bsp_root, player.pos, ctx, drawOneSlow);
            if (self.slow_column_budget > 0) self.slow_step = 0 else self.slow_step += 1;
        } else {
            bsp.traverseBSP(bsp_root, player.pos, ctx, drawOne);
        }

        self.renderVisplanes(focal, half_w, horizon, player.pos, cosA, sinA, eye_z);
        self.drawMinimap(player);
        self.drawCrosshair();
    }

    // -------------------------------------------------------------------
    // Pixel ops
    // -------------------------------------------------------------------

    fn putPixel(self: *Renderer, x: i32, y: i32, c: RGBA) void {
        if (x < 0 or x >= self.buf_w or y < 0 or y >= self.buf_h) return;
        const i: usize = (@as(usize, @intCast(y)) * @as(usize, @intCast(self.buf_w)) + @as(usize, @intCast(x))) * 4;
        self.pixels[i + 0] = c.r;
        self.pixels[i + 1] = c.g;
        self.pixels[i + 2] = c.b;
        self.pixels[i + 3] = c.a;
    }

    fn fillColumn(self: *Renderer, x: i32, y_lo_in: i32, y_hi_in: i32, c: RGBA) void {
        var y_lo = y_lo_in;
        var y_hi = y_hi_in;
        if (y_lo > y_hi) return;
        if (y_lo < 0) y_lo = 0;
        if (y_hi >= self.buf_h) y_hi = self.buf_h - 1;
        const stride: usize = @as(usize, @intCast(self.buf_w)) * 4;
        var i: usize = (@as(usize, @intCast(y_lo)) * @as(usize, @intCast(self.buf_w)) + @as(usize, @intCast(x))) * 4;
        var y: i32 = y_lo;
        while (y <= y_hi) : (y += 1) {
            self.pixels[i + 0] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = 255;
            i += stride;
        }
    }

    // -------------------------------------------------------------------
    // Per-seg rasterizer — the engine's most complex function.
    // -------------------------------------------------------------------
    //
    // For each visible seg, in BSP front-to-back order:
    //
    //   1. Back-face cull.
    //   2. Transform both endpoints from world space into view space
    //      (forward = +d, right = +r).
    //   3. Clip against near plane and left/right frustum (each is a simple
    //      inequality on r ± k*d). If fully outside a plane: return.
    //      Otherwise slide the bad endpoint to the plane.
    //   4. Project the clipped endpoints to screen X.
    //   5. For each screen column from xStart to xEnd:
    //        a. Skip columns the column-clip arrays say are fully occluded.
    //        b. Linearly interpolate 1/d (perspective-correct) to find depth.
    //        c. Compute projected ceiling-Y and floor-Y.
    //        d. Above ceiling and below floor: extend the corresponding
    //           sector's visplane spans (deferred to renderVisplanes).
    //        e. Solid seg: fill the slot with the wall color and mark the
    //           column fully occluded.
    //        f. Portal seg: draw upper-wall (back ceiling lower than front)
    //           and/or lower-wall (back floor higher than front) slivers,
    //           then narrow yTop/yBot to the back sector's open range.
    //
    // Per-column lighting is a simple distance falloff: 1/(1+d*0.004) scaled
    // by the front sector's authored light, clamped to a 0.15 floor.
    fn drawSeg(
        self: *Renderer,
        seg: Seg,
        player: *const Player,
        cosA: f64, sinA: f64,
        half_w: f64, horizon: f64,
        fov_half_tan: f64, focal: f64,
        eye_z: f64,
    ) void {
        // Back-face cull. The seg's outward normal is (-sdy, sdx) — a 90° CCW
        // rotation of the seg's direction. If the player is on the wrong side
        // of that normal, this seg's "front" is facing away from us.
        const sdx = seg.v2.x - seg.v1.x;
        const sdy = seg.v2.y - seg.v1.y;
        const nx = -sdy;
        const ny =  sdx;
        const to_px = player.pos.x - seg.v1.x;
        const to_py = player.pos.y - seg.v1.y;
        if (nx * to_px + ny * to_py <= 0) return;

        // World → view space. forward = +x view axis, right = +y view axis.
        //   r = -dx*sinA + dy*cosA
        //   d =  dx*cosA + dy*sinA
        const rx1 = seg.v1.x - player.pos.x;
        const ry1 = seg.v1.y - player.pos.y;
        const rx2 = seg.v2.x - player.pos.x;
        const ry2 = seg.v2.y - player.pos.y;
        var r1 = -rx1 * sinA + ry1 * cosA;
        var d1 =  rx1 * cosA + ry1 * sinA;
        var r2 = -rx2 * sinA + ry2 * cosA;
        var d2 =  rx2 * cosA + ry2 * sinA;

        // Near-plane clip.
        const near: f64 = 1.0;
        if (d1 < near and d2 < near) return;
        if (d1 < near) {
            const t = (near - d1) / (d2 - d1);
            r1 = r1 + t * (r2 - r1);
            d1 = near;
        } else if (d2 < near) {
            const t = (near - d2) / (d1 - d2);
            r2 = r2 + t * (r1 - r2);
            d2 = near;
        }

        // Left frustum (r + k*d >= 0).
        const k = fov_half_tan;
        const l_d1 = r1 + k * d1;
        const l_d2 = r2 + k * d2;
        if (l_d1 < 0 and l_d2 < 0) return;
        if (l_d1 < 0) {
            const t = l_d1 / (l_d1 - l_d2);
            r1 = r1 + t * (r2 - r1);
            d1 = d1 + t * (d2 - d1);
        } else if (l_d2 < 0) {
            const t = l_d2 / (l_d2 - l_d1);
            r2 = r2 + t * (r1 - r2);
            d2 = d2 + t * (d1 - d2);
        }

        // Right frustum (k*d - r >= 0).
        const r_d1 = k * d1 - r1;
        const r_d2 = k * d2 - r2;
        if (r_d1 < 0 and r_d2 < 0) return;
        if (r_d1 < 0) {
            const t = r_d1 / (r_d1 - r_d2);
            r1 = r1 + t * (r2 - r1);
            d1 = d1 + t * (d2 - d1);
        } else if (r_d2 < 0) {
            const t = r_d2 / (r_d2 - r_d1);
            r2 = r2 + t * (r1 - r2);
            d2 = d2 + t * (d1 - d2);
        }

        // Pinhole projection to screen X.
        const sx1 = half_w + (r1 / d1) * focal;
        const sx2 = half_w + (r2 / d2) * focal;
        if (sx2 <= sx1 + 0.0001) return;

        var x_start: i32 = @intFromFloat(@ceil(sx1));
        if (x_start < 0) x_start = 0;
        var x_end: i32 = @intFromFloat(@floor(sx2));
        if (x_end > self.buf_w - 1) x_end = self.buf_w - 1;
        if (x_start > x_end) return;

        // Wall heights stored as world Z; what matters for projection is the
        // signed distance from the eye, so we precompute (sectorZ - eyeZ).
        const front = level.sectors[@intCast(seg.front_sector)];
        const f_ceil  = front.ceil_h  - eye_z;
        const f_floor = front.floor_h - eye_z;
        var b_ceil: f64 = 0;
        var b_floor: f64 = 0;
        if (seg.back_sector != level.no_sector) {
            const back = level.sectors[@intCast(seg.back_sector)];
            b_ceil  = back.ceil_h  - eye_z;
            b_floor = back.floor_h - eye_z;
        }

        const linedef = level.linedefs[seg.linedef_index];
        const front_light = front.light;

        // Perspective-correct interpolation: linear in 1/d across screen X.
        const inv_d1 = 1.0 / d1;
        const inv_d2 = 1.0 / d2;
        const dx = sx2 - sx1;

        var x: i32 = x_start;
        while (x <= x_end) : (x += 1) {
            if (self.slow_mode) {
                if (self.slow_column_budget <= 0) return;
                self.slow_column_budget -= 1;
            }
            const ux: usize = @intCast(x);
            if (self.y_top[ux] > self.y_bot[ux]) continue;
            const t_lin = (@as(f64, @floatFromInt(x)) - sx1) / dx;
            const inv_d = (1.0 - t_lin) * inv_d1 + t_lin * inv_d2;
            const depth = 1.0 / inv_d;

            const falloff = 1.0 / (1.0 + depth * 0.004);
            const light = level.clampD(front_light * falloff, 0.15, 1.0);

            const ceil_y:  i32 = @intFromFloat(@round(horizon - f_ceil  * focal * inv_d));
            const floor_y: i32 = @intFromFloat(@round(horizon - f_floor * focal * inv_d));

            const top = self.y_top[ux];
            const bot = self.y_bot[ux];

            // Ceiling visplane span.
            if (ceil_y > top) {
                const y_lo = top;
                var y_hi = ceil_y - 1;
                if (y_hi > bot) y_hi = bot;
                self.visplanes[@as(usize, @intCast(seg.front_sector)) * 2 + 1].extend(x, y_lo, y_hi);
            }
            // Floor visplane span.
            if (floor_y < bot) {
                var y_lo = floor_y + 1;
                if (y_lo < top) y_lo = top;
                const y_hi = bot;
                self.visplanes[@as(usize, @intCast(seg.front_sector)) * 2].extend(x, y_lo, y_hi);
            }

            if (seg.back_sector == level.no_sector) {
                // Solid wall.
                var y_lo = ceil_y;  if (y_lo < top) y_lo = top;
                var y_hi = floor_y; if (y_hi > bot) y_hi = bot;
                self.fillColumn(x, y_lo, y_hi, level.shade(linedef.wall_color, light));
                self.y_top[ux] = bot + 1; // mark fully occluded
            } else {
                const back_ceil_y:  i32 = @intFromFloat(@round(horizon - b_ceil  * focal * inv_d));
                const back_floor_y: i32 = @intFromFloat(@round(horizon - b_floor * focal * inv_d));

                // Upper wall (back ceiling lower than front).
                var new_top: i32 = if (ceil_y < top) top else ceil_y;
                if (back_ceil_y > ceil_y) {
                    var y_lo = ceil_y;          if (y_lo < top) y_lo = top;
                    var y_hi = back_ceil_y - 1; if (y_hi > bot) y_hi = bot;
                    self.fillColumn(x, y_lo, y_hi, level.shade(linedef.upper_color, light));
                    new_top = if (back_ceil_y < top) top else back_ceil_y;
                }

                // Lower wall (back floor higher than front).
                var new_bot: i32 = if (floor_y > bot) bot else floor_y;
                if (back_floor_y < floor_y) {
                    var y_lo = back_floor_y + 1; if (y_lo < top) y_lo = top;
                    var y_hi = floor_y;          if (y_hi > bot) y_hi = bot;
                    self.fillColumn(x, y_lo, y_hi, level.shade(linedef.lower_color, light));
                    new_bot = if (back_floor_y > bot) bot else back_floor_y;
                }

                self.y_top[ux] = new_top;
                self.y_bot[ux] = new_bot;
                if (self.y_top[ux] > self.y_bot[ux]) self.y_top[ux] = self.y_bot[ux] + 1;
            }
        }
    }

    // -------------------------------------------------------------------
    // Visplane pass
    // -------------------------------------------------------------------

    fn renderVisplanes(
        self: *Renderer,
        focal: f64, half_w: f64, horizon: f64,
        player_pos: Vec2, cosA: f64, sinA: f64, eye_z: f64,
    ) void {
        for (self.visplanes) |*plane| {
            if (plane.max_x < plane.min_x) continue;
            const sec = level.sectors[@intCast(plane.sector_index)];
            const plane_z = if (plane.is_ceiling) sec.ceil_h else sec.floor_h;
            const color   = if (plane.is_ceiling) sec.ceil_color else sec.floor_color;
            const plane_height = plane_z - eye_z;

            var x: i32 = plane.min_x;
            while (x <= plane.max_x) : (x += 1) {
                const ux: usize = @intCast(x);
                const y_lo = plane.top[ux];
                const y_hi = plane.bot[ux];
                if (y_lo > y_hi) continue;
                self.fillPlaneColumn(
                    x, y_lo, y_hi,
                    plane_height, focal, half_w, horizon,
                    player_pos, cosA, sinA,
                    sec.light, color,
                );
            }
        }
    }

    // fillPlaneColumn rasterizes a vertical strip of one floor/ceiling. The
    // plane is horizontal in world space — every pixel in the strip belongs
    // to the same world Z. For each screen pixel we inverse-project to the
    // world (X, Y) it represents, sample a procedural 16-unit checkerboard
    // there, and apply distance-based shading.
    fn fillPlaneColumn(
        self: *Renderer,
        x: i32, y_lo: i32, y_hi: i32,
        plane_height: f64,
        focal: f64, half_w: f64, horizon: f64,
        player_pos: Vec2, cosA: f64, sinA: f64,
        sector_light: f64, color: RGBA,
    ) void {
        if (y_lo > y_hi) return;

        const abs_h = @abs(plane_height);
        const x_offset = @as(f64, @floatFromInt(x)) - half_w;

        // Precompute the dark-tile color once per column.
        const dark_color: RGBA = .{
            .r = @intFromFloat(@as(f64, @floatFromInt(color.r)) * 0.7),
            .g = @intFromFloat(@as(f64, @floatFromInt(color.g)) * 0.7),
            .b = @intFromFloat(@as(f64, @floatFromInt(color.b)) * 0.7),
            .a = 255,
        };

        // Tile size = 1 << tile_bits world units. tile_bias keeps the integer
        // world coordinates positive so the parity test stays stable across
        // the origin.
        const tile_bits: u5 = 4;
        const tile_bias: i32 = 1 << 20;

        const stride: usize = @as(usize, @intCast(self.buf_w)) * 4;
        var i: usize = (@as(usize, @intCast(y_lo)) * @as(usize, @intCast(self.buf_w)) + @as(usize, @intCast(x))) * 4;

        var y: i32 = y_lo;
        while (y <= y_hi) : (y += 1) {
            // sy = horizon - h * focal / depth  →  depth = |h| * focal / |sy - horizon|
            const abs_dy = @abs(@as(f64, @floatFromInt(y)) - horizon);
            const depth = if (abs_dy > 0.0001) abs_h * focal / abs_dy else 1.0e9;

            // View-space right offset for this pixel at this depth.
            const right = x_offset * depth / focal;

            // Camera space (forward, right) → world space.
            const wx = player_pos.x + depth * cosA - right * sinA;
            const wy = player_pos.y + depth * sinA + right * cosA;

            // Checkerboard sample.
            const tx = (@as(i32, @intFromFloat(wx)) + tile_bias) >> tile_bits;
            const ty = (@as(i32, @intFromFloat(wy)) + tile_bias) >> tile_bits;
            const base = if ((@as(u32, @bitCast(tx ^ ty)) & 1) == 0) color else dark_color;

            // Distance fog and per-sector light, with a floor so distant
            // pixels don't go pitch black. The 0.9 desaturates floors a touch
            // relative to walls.
            const falloff = 1.0 / (1.0 + depth * 0.004);
            const light = level.clampD(sector_light * falloff, 0.15, 1.0);
            const c = level.shade(base, light * 0.9);

            self.pixels[i + 0] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = 255;
            i += stride;
        }
    }

    // -------------------------------------------------------------------
    // Overlays
    // -------------------------------------------------------------------

    fn drawCrosshair(self: *Renderer) void {
        const cx = @divTrunc(self.buf_w, 2);
        const cy = @divTrunc(self.buf_h, 2);
        const col: RGBA = .{ .r = 255, .g = 255, .b = 255 };
        var d: i32 = -3;
        while (d <= 3) : (d += 1) {
            if (d == 0) continue;
            self.putPixel(cx + d, cy, col);
            self.putPixel(cx, cy + d, col);
        }
    }

    // drawMinimap draws a top-down preview of the level into the upper-left
    // corner: dark backdrop, all linedefs (one-sided in their wall color,
    // two-sided in gray), and a player marker with a heading line.
    fn drawMinimap(self: *Renderer, player: *const Player) void {
        var min_x: f64 =  std.math.inf(f64);
        var min_y: f64 =  std.math.inf(f64);
        var max_x: f64 = -std.math.inf(f64);
        var max_y: f64 = -std.math.inf(f64);
        for (level.vertices) |v| {
            if (v.x < min_x) min_x = v.x;
            if (v.y < min_y) min_y = v.y;
            if (v.x > max_x) max_x = v.x;
            if (v.y > max_y) max_y = v.y;
        }
        const pad:  f64 = 8.0;
        const box_w: f64 = 120.0;
        const box_h: f64 = 100.0;
        const ox: f64 = 8.0;
        const oy: f64 = 8.0;
        const sx = box_w / (max_x - min_x + 2 * pad);
        const sy = box_h / (max_y - min_y + 2 * pad);
        const s  = @min(sx, sy);

        const project = struct {
            fn p(v: Vec2, mnx: f64, mny: f64, p_: f64, ox_: f64, oy_: f64, s_: f64) struct { x: i32, y: i32 } {
                return .{
                    .x = @intFromFloat(ox_ + ((v.x - mnx) + p_) * s_),
                    .y = @intFromFloat(oy_ + ((v.y - mny) + p_) * s_),
                };
            }
        }.p;

        // Backdrop.
        const back_lo_y: i32 = @intFromFloat(oy - 2);
        const back_hi_y: i32 = @intFromFloat(oy + box_h + 2);
        const back_lo_x: i32 = @intFromFloat(ox - 2);
        const back_hi_x: i32 = @intFromFloat(ox + box_w + 2);
        var by: i32 = back_lo_y;
        while (by <= back_hi_y) : (by += 1) {
            var bx: i32 = back_lo_x;
            while (bx <= back_hi_x) : (bx += 1) {
                self.putPixel(bx, by, .{ .r = 10, .g = 10, .b = 14 });
            }
        }

        // Linedefs.
        for (level.linedefs) |l| {
            const a = project(level.vertices[l.v1], min_x, min_y, pad, ox, oy, s);
            const b = project(level.vertices[l.v2], min_x, min_y, pad, ox, oy, s);
            const col: RGBA = if (l.back_sector == level.no_sector) l.wall_color else .{ .r = 120, .g = 120, .b = 120 };
            self.drawLine(a.x, a.y, b.x, b.y, col);
        }

        // Player marker + heading line.
        const pp = project(player.pos, min_x, min_y, pad, ox, oy, s);
        var dyi: i32 = -1;
        while (dyi <= 1) : (dyi += 1) {
            var dxi: i32 = -1;
            while (dxi <= 1) : (dxi += 1) {
                self.putPixel(pp.x + dxi, pp.y + dyi, .{ .r = 255, .g = 255, .b = 255 });
            }
        }
        const hx: i32 = pp.x + @as(i32, @intFromFloat(@cos(player.angle) * 10.0));
        const hy: i32 = pp.y + @as(i32, @intFromFloat(@sin(player.angle) * 10.0));
        self.drawLine(pp.x, pp.y, hx, hy, .{ .r = 255, .g = 255, .b = 255 });
    }

    // Standard integer Bresenham, with bounds-checked plotting via putPixel.
    fn drawLine(self: *Renderer, x0_in: i32, y0_in: i32, x1: i32, y1: i32, color: RGBA) void {
        var x0 = x0_in;
        var y0 = y0_in;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err: i32 = dx + dy;
        while (true) {
            self.putPixel(x0, y0, color);
            if (x0 == x1 and y0 == y1) return;
            const e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
    }
};

// -------------------------------------------------------------------------
// Visitor adapters
// -------------------------------------------------------------------------
//
// traverseBSP is generic over the visitor closure. Zig closures aren't
// stateful in the same way C++ lambdas are, so we package up the per-frame
// context in a struct and use a pair of static dispatchers.

const DrawCtx = struct {
    self: *Renderer,
    player: *const Player,
    cosA: f64, sinA: f64,
    half_w: f64, horizon: f64,
    fov_half_tan: f64, focal: f64,
    eye_z: f64,
};

fn drawOne(ctx: DrawCtx, seg: Seg) void {
    ctx.self.drawSeg(seg, ctx.player, ctx.cosA, ctx.sinA, ctx.half_w, ctx.horizon, ctx.fov_half_tan, ctx.focal, ctx.eye_z);
}

fn drawOneSlow(ctx: DrawCtx, seg: Seg) void {
    if (ctx.self.slow_column_budget <= 0) return;
    ctx.self.drawSeg(seg, ctx.player, ctx.cosA, ctx.sinA, ctx.half_w, ctx.horizon, ctx.fov_half_tan, ctx.focal, ctx.eye_z);
}

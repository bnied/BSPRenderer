//! Software renderer.
//!
//! Per-frame state:
//!
//!   - `pixels`        — RGBA framebuffer, `Vec<u8>` of length W*H*4 in
//!                       row-major order. The main loop copies this into the
//!                       `pixels` crate's frame buffer each tick.
//!   - `y_top` / `y_bot` — DOOM's ceilingclip / floorclip arrays. For each
//!                       screen column they bound the still-open vertical
//!                       range. Solid walls close their columns entirely;
//!                       portals shrink the open range by their upper/lower
//!                       walls.
//!   - `visplanes`     — 2 entries per sector (floor at 2*si, ceiling at
//!                       2*si+1). See [`crate::visplane`].
//!   - `slow_mode` etc — debug aid: when enabled (Tab), each frame draws one
//!                       more column than the previous one, so you can watch
//!                       the BSP walk emit columns left-to-right (or
//!                       front-to-back from the player's perspective).
//!
//! The Go port splits the renderer across five files (core, seg, fill,
//! visplanes, overlays). Rust prefers all methods on a single `impl` block,
//! so it all lives here — see the section banners.

use crate::bsp::Bsp;
use crate::font::{glyph, ADVANCE, GLYPH_H, GLYPH_W};
use crate::geometry::{Seg, NO_SECTOR};
use crate::level::Level;
use crate::math_utils::{clamp_f, shade, Rgba, Vec2};
use crate::player::Player;
use crate::visplane::Visplane;

pub struct Renderer {
    pub buf_w: usize,
    pub buf_h: usize,
    pub pixels: Vec<u8>,
    y_top: Vec<i32>,
    y_bot: Vec<i32>,
    visplanes: Vec<Visplane>,
    /// Reused per-frame to collect segs from the BSP walk so we don't have
    /// to invoke `draw_seg` from inside a closure that borrows `&mut self`.
    frame_segs: Vec<Seg>,

    pub slow_mode: bool,
    slow_step: i32,
    slow_column_budget: i32,
}

/// Per-frame precomputed values handed to [`Renderer::draw_seg`] — keeps the
/// per-seg signature small.
struct FrameCtx {
    player_pos: Vec2,
    cos_a: f64,
    sin_a: f64,
    half_w: f64,
    horizon: f64,
    fov_half_tan: f64,
    focal: f64,
    eye_z: f64,
}

impl Renderer {
    pub fn new(width: usize, height: usize, level: &Level) -> Self {
        let mut visplanes: Vec<Visplane> = Vec::new();
        for si in 0..level.sectors.len() {
            visplanes.push(Visplane::new(si, false, width)); // floor at 2*si
            visplanes.push(Visplane::new(si, true, width));  // ceiling at 2*si+1
        }
        Self {
            buf_w: width,
            buf_h: height,
            pixels: vec![0u8; width * height * 4],
            y_top: vec![0i32; width],
            y_bot: vec![0i32; width],
            visplanes,
            frame_segs: Vec::with_capacity(64),
            slow_mode: false,
            slow_step: 0,
            slow_column_budget: 0,
        }
    }

    // ---- Core: per-frame entry point --------------------------------------

    /// Run one full frame:
    ///   1. Reset per-column open region and per-frame visplane coverage.
    ///   2. Background fill (dim ceiling/floor of the player's current sector)
    ///      so any column that somehow ends up unwritten still looks plausible.
    ///   3. BSP walk → `draw_seg` for every visible seg, front-to-back.
    ///   4. Visplane pass → flat floors/ceilings rasterized with inverse
    ///      projection + checkerboard texture.
    ///   5. Overlays: minimap and crosshair.
    pub fn render(&mut self, p: &Player, level: &Level, bsp: &Bsp) {
        for x in 0..self.buf_w {
            self.y_top[x] = 0;
            self.y_bot[x] = self.buf_h as i32 - 1;
        }
        for v in &mut self.visplanes {
            v.reset();
        }

        let player_sector = bsp.find_sector(p.pos);
        let sec = *level.sector(player_sector);
        let half_w = self.buf_w as f64 / 2.0;
        let half_h = self.buf_h as f64 / 2.0;
        let horizon = half_h;

        // Background fill — top half = sector ceiling, bottom half = sector
        // floor, both dimmed so legitimate geometry still reads as brighter.
        let ceil_dim = shade(sec.ceil_color, 0.55);
        let floor_dim = shade(sec.floor_color, 0.55);
        let mid = self.buf_h / 2;
        for y in 0..self.buf_h {
            let c = if y < mid { ceil_dim } else { floor_dim };
            let row_start = y * self.buf_w * 4;
            for x in 0..self.buf_w {
                let i = row_start + x * 4;
                self.pixels[i] = c.r;
                self.pixels[i + 1] = c.g;
                self.pixels[i + 2] = c.b;
                self.pixels[i + 3] = 255;
            }
        }

        // Pinhole camera setup. focal = halfW / tan(fov/2) is the standard
        // "screen plane is `focal` units in front of the eye" projection.
        let fov_half_tan = (p.fov / 2.0).tan();
        let ctx = FrameCtx {
            player_pos: p.pos,
            cos_a: p.angle.cos(),
            sin_a: p.angle.sin(),
            half_w,
            horizon,
            fov_half_tan,
            focal: half_w / fov_half_tan,
            eye_z: p.eye_z(),
        };

        // Buffer the BSP walk so we can iterate it from outside the closure
        // (avoids borrowing &mut self while traverse_bsp holds the visitor).
        self.frame_segs.clear();
        // Take ownership of the buffer so the closure can borrow it without
        // clashing with `self` later — we put it back at the end.
        let mut segs = std::mem::take(&mut self.frame_segs);
        bsp.traverse(p.pos, &mut |s: &Seg| segs.push(*s));

        if self.slow_mode {
            self.slow_column_budget = self.slow_step;
            for s in &segs {
                self.draw_seg(s, &ctx, level);
                if self.slow_column_budget <= 0 {
                    break;
                }
            }
            if self.slow_column_budget > 0 {
                self.slow_step = 0;
            } else {
                self.slow_step += 1;
            }
        } else {
            for s in &segs {
                self.draw_seg(s, &ctx, level);
            }
        }
        self.frame_segs = segs;

        self.render_visplanes(&ctx, level);
        self.draw_minimap(p, level);
        self.draw_crosshair();
    }

    // ---- Per-pixel helpers ------------------------------------------------

    fn put_pixel(&mut self, x: i32, y: i32, c: Rgba) {
        if x < 0 || x as usize >= self.buf_w || y < 0 || y as usize >= self.buf_h {
            return;
        }
        let i = (y as usize * self.buf_w + x as usize) * 4;
        self.pixels[i] = c.r;
        self.pixels[i + 1] = c.g;
        self.pixels[i + 2] = c.b;
        self.pixels[i + 3] = c.a;
    }

    fn fill_column(&mut self, x: i32, y_lo: i32, y_hi: i32, c: Rgba) {
        if y_lo > y_hi {
            return;
        }
        let y_lo = y_lo.max(0) as usize;
        let y_hi = (y_hi as usize).min(self.buf_h - 1);
        let mut i = (y_lo * self.buf_w + x as usize) * 4;
        let stride = self.buf_w * 4;
        for _ in y_lo..=y_hi {
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = 255;
            i += stride;
        }
    }

    // ---- Seg rasterization (formerly renderer_seg.go) ---------------------

    /// `draw_seg` is the per-seg rasterizer and the engine's single most
    /// complex function. Once per visible seg, in BSP front-to-back order:
    ///
    ///   1. Back-face cull (only render segs whose front sector faces us).
    ///   2. Transform both endpoints from world space into view space, where
    ///      forward is +d (depth) and right is +r.
    ///   3. Clip against the near plane and the left/right frustum planes
    ///      (each a simple inequality on r ± k*d).
    ///   4. Project clipped endpoints to screen X.
    ///   5. For each screen column from xStart to xEnd:
    ///        a. Skip columns the column-clip arrays say are fully occluded.
    ///        b. Linearly interpolate 1/d (perspective-correct) → depth.
    ///        c. Compute projected ceiling-Y and floor-Y: the open vertical
    ///           slot.
    ///        d. Above the ceiling and below the floor: extend the
    ///           corresponding sector's visplane spans.
    ///        e. If solid: fill slot with wall color, mark column fully
    ///           occluded.
    ///        f. If portal: optionally draw upper/lower wall slivers, then
    ///           narrow yTop/yBot to the back sector's open range.
    fn draw_seg(&mut self, seg: &Seg, ctx: &FrameCtx, level: &Level) {
        // Back-face cull. Outward normal is (-sdy, sdx). If the player is on
        // the wrong side of that normal, this seg's "front" faces away.
        let sdx = seg.v2.x - seg.v1.x;
        let sdy = seg.v2.y - seg.v1.y;
        let nx = -sdy;
        let ny = sdx;
        let to_px = ctx.player_pos.x - seg.v1.x;
        let to_py = ctx.player_pos.y - seg.v1.y;
        if nx * to_px + ny * to_py <= 0.0 {
            return;
        }

        // World → view space.
        let rx1 = seg.v1.x - ctx.player_pos.x;
        let ry1 = seg.v1.y - ctx.player_pos.y;
        let rx2 = seg.v2.x - ctx.player_pos.x;
        let ry2 = seg.v2.y - ctx.player_pos.y;
        let mut r1 = -rx1 * ctx.sin_a + ry1 * ctx.cos_a;
        let mut d1 = rx1 * ctx.cos_a + ry1 * ctx.sin_a;
        let mut r2 = -rx2 * ctx.sin_a + ry2 * ctx.cos_a;
        let mut d2 = rx2 * ctx.cos_a + ry2 * ctx.sin_a;

        // Near-plane clip.
        let near = 1.0;
        if d1 < near && d2 < near {
            return;
        }
        if d1 < near {
            let t = (near - d1) / (d2 - d1);
            r1 += t * (r2 - r1);
            d1 = near;
        } else if d2 < near {
            let t = (near - d2) / (d1 - d2);
            r2 += t * (r1 - r2);
            d2 = near;
        }

        // Left frustum (r + k*d >= 0).
        let k = ctx.fov_half_tan;
        let l_d1 = r1 + k * d1;
        let l_d2 = r2 + k * d2;
        if l_d1 < 0.0 && l_d2 < 0.0 {
            return;
        }
        if l_d1 < 0.0 {
            let t = l_d1 / (l_d1 - l_d2);
            r1 += t * (r2 - r1);
            d1 += t * (d2 - d1);
        } else if l_d2 < 0.0 {
            let t = l_d2 / (l_d2 - l_d1);
            r2 += t * (r1 - r2);
            d2 += t * (d1 - d2);
        }

        // Right frustum (k*d - r >= 0).
        let r_d1 = k * d1 - r1;
        let r_d2 = k * d2 - r2;
        if r_d1 < 0.0 && r_d2 < 0.0 {
            return;
        }
        if r_d1 < 0.0 {
            let t = r_d1 / (r_d1 - r_d2);
            r1 += t * (r2 - r1);
            d1 += t * (d2 - d1);
        } else if r_d2 < 0.0 {
            let t = r_d2 / (r_d2 - r_d1);
            r2 += t * (r1 - r2);
            d2 += t * (d1 - d2);
        }

        let sx1 = ctx.half_w + (r1 / d1) * ctx.focal;
        let sx2 = ctx.half_w + (r2 / d2) * ctx.focal;
        if sx2 <= sx1 + 0.0001 {
            return;
        }

        let mut x_start = sx1.ceil() as i32;
        if x_start < 0 {
            x_start = 0;
        }
        let mut x_end = sx2.floor() as i32;
        if x_end > self.buf_w as i32 - 1 {
            x_end = self.buf_w as i32 - 1;
        }
        if x_start > x_end {
            return;
        }

        let front = *level.sector(seg.front_sector);
        let f_ceil = front.ceil_h - ctx.eye_z;
        let f_floor = front.floor_h - ctx.eye_z;
        let (b_ceil, b_floor) = if seg.back_sector != NO_SECTOR {
            let back = level.sector(seg.back_sector as usize);
            (back.ceil_h - ctx.eye_z, back.floor_h - ctx.eye_z)
        } else {
            (0.0, 0.0)
        };

        let line_def = level.linedefs[seg.linedef_index];
        let front_light = front.light;

        let inv_d1 = 1.0 / d1;
        let inv_d2 = 1.0 / d2;
        let dx = sx2 - sx1;

        let ceil_vp_idx = seg.front_sector * 2 + 1;
        let floor_vp_idx = seg.front_sector * 2;

        for x in x_start..=x_end {
            if self.slow_mode {
                if self.slow_column_budget <= 0 {
                    return;
                }
                self.slow_column_budget -= 1;
            }
            let xi = x as usize;
            let top = self.y_top[xi];
            let bot = self.y_bot[xi];
            if top > bot {
                continue;
            }
            let t_lin = (x as f64 - sx1) / dx;
            let inv_d = (1.0 - t_lin) * inv_d1 + t_lin * inv_d2;
            let depth = 1.0 / inv_d;

            let falloff = 1.0 / (1.0 + depth * 0.004);
            let light = clamp_f(front_light * falloff, 0.15, 1.0);

            let ceil_y = (ctx.horizon - f_ceil * ctx.focal * inv_d).round() as i32;
            let floor_y = (ctx.horizon - f_floor * ctx.focal * inv_d).round() as i32;

            // Ceiling visplane span.
            if ceil_y > top {
                let y_lo = top;
                let mut y_hi = ceil_y - 1;
                if y_hi > bot {
                    y_hi = bot;
                }
                self.visplanes[ceil_vp_idx].extend(x, y_lo, y_hi);
            }
            // Floor visplane span.
            if floor_y < bot {
                let mut y_lo = floor_y + 1;
                if y_lo < top {
                    y_lo = top;
                }
                let y_hi = bot;
                self.visplanes[floor_vp_idx].extend(x, y_lo, y_hi);
            }

            if seg.back_sector == NO_SECTOR {
                // Solid wall.
                let mut y_lo = ceil_y;
                if y_lo < top {
                    y_lo = top;
                }
                let mut y_hi = floor_y;
                if y_hi > bot {
                    y_hi = bot;
                }
                self.fill_column(x, y_lo, y_hi, shade(line_def.wall_color, light));
                self.y_top[xi] = bot + 1;
            } else {
                let back_ceil_y = (ctx.horizon - b_ceil * ctx.focal * inv_d).round() as i32;
                let back_floor_y = (ctx.horizon - b_floor * ctx.focal * inv_d).round() as i32;

                // Upper wall.
                let mut new_top = ceil_y;
                if new_top < top {
                    new_top = top;
                }
                if back_ceil_y > ceil_y {
                    let mut y_lo = ceil_y;
                    if y_lo < top {
                        y_lo = top;
                    }
                    let mut y_hi = back_ceil_y - 1;
                    if y_hi > bot {
                        y_hi = bot;
                    }
                    self.fill_column(x, y_lo, y_hi, shade(line_def.upper_color, light));
                    new_top = back_ceil_y;
                    if new_top < top {
                        new_top = top;
                    }
                }

                // Lower wall.
                let mut new_bot = floor_y;
                if new_bot > bot {
                    new_bot = bot;
                }
                if back_floor_y < floor_y {
                    let mut y_lo = back_floor_y + 1;
                    if y_lo < top {
                        y_lo = top;
                    }
                    let mut y_hi = floor_y;
                    if y_hi > bot {
                        y_hi = bot;
                    }
                    self.fill_column(x, y_lo, y_hi, shade(line_def.lower_color, light));
                    new_bot = back_floor_y;
                    if new_bot > bot {
                        new_bot = bot;
                    }
                }

                self.y_top[xi] = new_top;
                self.y_bot[xi] = new_bot;
                if self.y_top[xi] > self.y_bot[xi] {
                    self.y_top[xi] = self.y_bot[xi] + 1;
                }
            }
        }
    }

    // ---- Visplane pass (formerly renderer_visplanes.go + renderer_fill.go) ----

    fn render_visplanes(&mut self, ctx: &FrameCtx, level: &Level) {
        // Snapshot the (sector_index, is_ceiling, min_x, max_x) before iter
        // since fill_plane_column needs &mut self.pixels; we read top/bot via
        // index into self.visplanes.
        for pi in 0..self.visplanes.len() {
            let (sector_index, is_ceiling, min_x, max_x) = {
                let p = &self.visplanes[pi];
                let Some((min_x, max_x)) = p.covered() else {
                    continue;
                };
                (p.sector_index(), p.is_ceiling(), min_x, max_x)
            };
            let sec = *level.sector(sector_index);
            let (plane_z, color) = if is_ceiling {
                (sec.ceil_h, sec.ceil_color)
            } else {
                (sec.floor_h, sec.floor_color)
            };
            let plane_height = plane_z - ctx.eye_z;

            for x in min_x..=max_x {
                let (y_lo, y_hi) = self.visplanes[pi].span_at(x as usize);
                if y_lo > y_hi {
                    continue;
                }
                self.fill_plane_column(x, y_lo, y_hi, plane_height, ctx,
                                       sec.light, color);
            }
        }
    }

    /// Rasterize one vertical strip of a single floor or ceiling plane.
    ///
    /// The plane is horizontal in world space — every pixel in the strip
    /// belongs to the same world Z. For each screen pixel we inverse-project
    /// to the world (X, Y) it represents, sample a procedural 16-unit
    /// checkerboard there, and apply distance-based shading.
    fn fill_plane_column(&mut self, x: i32, y_lo: i32, y_hi: i32,
                         plane_height: f64, ctx: &FrameCtx,
                         sector_light: f64, color: Rgba) {
        if y_lo > y_hi {
            return;
        }
        let abs_h = plane_height.abs();
        let x_offset = x as f64 - ctx.half_w;

        // Precompute the dark-tile color once per column.
        let dark_color = Rgba::new(
            (color.r as f64 * 0.7) as u8,
            (color.g as f64 * 0.7) as u8,
            (color.b as f64 * 0.7) as u8,
            255,
        );

        // Tile size = 1 << TILE_BITS world units. TILE_BIAS keeps the integer
        // world coordinates positive so the parity test is stable across the
        // origin.
        const TILE_BITS: i64 = 4;
        const TILE_BIAS: i64 = 1 << 20;

        let stride = self.buf_w * 4;
        let mut i = (y_lo as usize * self.buf_w + x as usize) * 4;

        for y in y_lo..=y_hi {
            // Pinhole inverse projection.
            let abs_dy = (y as f64 - ctx.horizon).abs();
            let depth = if abs_dy > 0.0001 {
                abs_h * ctx.focal / abs_dy
            } else {
                1e9
            };

            let right = x_offset * depth / ctx.focal;
            // Camera-space → world space.
            let wx = ctx.player_pos.x + depth * ctx.cos_a - right * ctx.sin_a;
            let wy = ctx.player_pos.y + depth * ctx.sin_a + right * ctx.cos_a;

            let tx = (wx as i64 + TILE_BIAS) >> TILE_BITS;
            let ty = (wy as i64 + TILE_BIAS) >> TILE_BITS;
            let base = if (tx ^ ty) & 1 == 0 { color } else { dark_color };

            let falloff = 1.0 / (1.0 + depth * 0.004);
            let light = clamp_f(sector_light * falloff, 0.15, 1.0);
            let c = shade(base, light * 0.9);

            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = 255;
            i += stride;
        }
    }

    // ---- Overlays (formerly renderer_overlays.go) -------------------------

    fn draw_crosshair(&mut self) {
        let cx = self.buf_w as i32 / 2;
        let cy = self.buf_h as i32 / 2;
        let white = Rgba::new(255, 255, 255, 255);
        for d in -3..=3 {
            if d == 0 {
                continue;
            }
            self.put_pixel(cx + d, cy, white);
            self.put_pixel(cx, cy + d, white);
        }
    }

    fn draw_minimap(&mut self, p: &Player, level: &Level) {
        let mut min_x = f64::INFINITY;
        let mut min_y = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut max_y = f64::NEG_INFINITY;
        for v in level.vertices.iter() {
            if v.x < min_x { min_x = v.x; }
            if v.y < min_y { min_y = v.y; }
            if v.x > max_x { max_x = v.x; }
            if v.y > max_y { max_y = v.y; }
        }
        let pad = 8.0;
        let box_w = 120.0;
        let box_h = 100.0;
        let ox = 8.0;
        let oy = 8.0;
        let sx = box_w / (max_x - min_x + 2.0 * pad);
        let sy = box_h / (max_y - min_y + 2.0 * pad);
        let s = sx.min(sy);

        let project = |v: Vec2| -> (i32, i32) {
            (
                (ox + ((v.x - min_x) + pad) * s) as i32,
                (oy + ((v.y - min_y) + pad) * s) as i32,
            )
        };

        // Backdrop.
        let backdrop = Rgba::new(10, 10, 14, 255);
        let y_start = (oy - 2.0) as i32;
        let y_end = (oy + box_h + 2.0) as i32;
        let x_start = (ox - 2.0) as i32;
        let x_end = (ox + box_w + 2.0) as i32;
        for y in y_start..=y_end {
            for x in x_start..=x_end {
                self.put_pixel(x, y, backdrop);
            }
        }

        // Linedefs.
        for l in level.linedefs.iter() {
            let (ax, ay) = project(level.vertices[l.v1]);
            let (bx, by) = project(level.vertices[l.v2]);
            let col = if l.back_sector != NO_SECTOR {
                Rgba::new(120, 120, 120, 255)
            } else {
                l.wall_color
            };
            self.draw_line(ax, ay, bx, by, col);
        }

        // Player.
        let (px_i, py_i) = project(p.pos);
        let white = Rgba::new(255, 255, 255, 255);
        for dy in -1..=1 {
            for dx in -1..=1 {
                self.put_pixel(px_i + dx, py_i + dy, white);
            }
        }
        let hx = px_i + (p.angle.cos() * 10.0) as i32;
        let hy = py_i + (p.angle.sin() * 10.0) as i32;
        self.draw_line(px_i, py_i, hx, hy, white);
    }

    fn draw_line(&mut self, mut x0: i32, mut y0: i32, x1: i32, y1: i32, color: Rgba) {
        // Standard integer Bresenham.
        let dx = (x1 - x0).abs();
        let sx: i32 = if x0 < x1 { 1 } else { -1 };
        let dy = -(y1 - y0).abs();
        let sy: i32 = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;
        loop {
            self.put_pixel(x0, y0, color);
            if x0 == x1 && y0 == y1 {
                return;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x0 += sx;
            }
            if e2 <= dx {
                err += dx;
                y0 += sy;
            }
        }
    }

    // ---- HUD text -------------------------------------------------------

    /// Fill a rectangle of solid color, alpha-blended over the existing
    /// framebuffer pixels (so we can dim a backdrop behind the HUD without
    /// fully replacing the scene under it). `c.a` is the source alpha.
    fn fill_rect_blend(&mut self, x: i32, y: i32, w: i32, h: i32, c: Rgba) {
        let x0 = x.max(0) as usize;
        let y0 = y.max(0) as usize;
        let x1 = ((x + w) as usize).min(self.buf_w);
        let y1 = ((y + h) as usize).min(self.buf_h);
        let a = c.a as u32;
        let inv = 255 - a;
        for yy in y0..y1 {
            let row_start = (yy * self.buf_w + x0) * 4;
            let mut i = row_start;
            for _ in x0..x1 {
                self.pixels[i] = ((c.r as u32 * a + self.pixels[i] as u32 * inv) / 255) as u8;
                self.pixels[i + 1] = ((c.g as u32 * a + self.pixels[i + 1] as u32 * inv) / 255) as u8;
                self.pixels[i + 2] = ((c.b as u32 * a + self.pixels[i + 2] as u32 * inv) / 255) as u8;
                self.pixels[i + 3] = 255;
                i += 4;
            }
        }
    }

    /// Draw `text` starting at (x, y), one bitmap glyph at a time. No word
    /// wrap, no kerning — characters lay out at fixed `ADVANCE` columns.
    fn draw_text(&mut self, x: i32, y: i32, text: &str, color: Rgba) {
        let mut cx = x;
        for ch in text.chars() {
            let g = glyph(ch);
            for (row, bits) in g.iter().enumerate() {
                for col in 0..GLYPH_W {
                    // Bits are packed into the lowest GLYPH_W bits of the byte,
                    // MSB = leftmost pixel.
                    if (bits >> (GLYPH_W - 1 - col)) & 1 != 0 {
                        self.put_pixel(cx + col as i32, y + row as i32, color);
                    }
                }
            }
            cx += ADVANCE as i32;
        }
    }

    /// Draw the standard HUD line at the top-left (sector + heights + a
    /// `[SLOW]` tag when slow mode is active). Uppercased to match the
    /// authored bitmap-font character set.
    pub fn draw_hud(&mut self, p: &Player, level: &Level, bsp: &Bsp) {
        let si = bsp.find_sector(p.pos);
        let s = *level.sector(si);
        let slow_tag = if self.slow_mode { "  [SLOW]" } else { "" };
        let hud = format!(
            "SECTOR {}  FLOOR {:+}  CEIL {:+}  FEETZ {:+}  EYEZ {:+}{}",
            si,
            s.floor_h as i32,
            s.ceil_h as i32,
            p.feet_z as i32,
            p.eye_z() as i32,
            slow_tag,
        );

        let pad_x = 3i32;
        let pad_y = 2i32;
        let text_w = (hud.chars().count() * ADVANCE) as i32;
        let bg_w = text_w + pad_x * 2;
        let bg_h = GLYPH_H as i32 + pad_y * 2;
        // Dim translucent backdrop so text stays legible on bright walls.
        self.fill_rect_blend(2, 2, bg_w, bg_h, Rgba::new(0, 0, 0, 160));
        self.draw_text(2 + pad_x, 2 + pad_y, &hud, Rgba::new(230, 230, 230, 255));
    }
}

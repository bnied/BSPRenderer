"""Software renderer.

Per-frame state:

  pixels        — RGBA framebuffer, numpy uint8 array of shape (H, W, 4).
                  Row-major; main.py wraps this in a pygame Surface via
                  pygame.image.frombuffer each frame.
  y_top / y_bot — DOOM's ceilingclip / floorclip arrays. For each screen
                  column they bound the still-open vertical range. Solid
                  walls close their columns entirely; portals shrink the
                  open range by their upper/lower walls.
  visplanes     — 2 entries per sector (floor at 2*si, ceiling at 2*si+1).
                  See visplane.py.
  slow_mode etc — debug aid: when enabled (Tab), each frame draws one more
                  column than the previous one, so you can watch the BSP
                  walk emit columns left-to-right (or front-to-back from
                  the player's perspective).

The Go port splits the renderer across five files (core, seg, fill, visplanes,
overlays). Python doesn't support spreading methods across files for a single
class, so it all lives here — see the section banners.
"""

from __future__ import annotations

import math

import numpy as np

from bsp import BSPNode, find_sector, traverse_bsp
from level import linedefs, sectors, vertices
from math_utils import RGBA, Vec2, clamp_f, shade
from geometry import NO_SECTOR, Seg
from player import Player
from visplane import Visplane


class Renderer:
    def __init__(self, width: int, height: int) -> None:
        self.buf_w = width
        self.buf_h = height
        # (H, W, 4) row-major RGBA — pygame.image.frombuffer reads this layout.
        self.pixels = np.zeros((height, width, 4), dtype=np.uint8)
        self.y_top = np.zeros(width, dtype=np.int32)
        self.y_bot = np.zeros(width, dtype=np.int32)
        self.visplanes: list[Visplane] = []
        for si in range(len(sectors)):
            self.visplanes.append(Visplane(si, False, width))  # floor at 2*si
            self.visplanes.append(Visplane(si, True, width))   # ceiling at 2*si+1

        self.slow_mode = False
        self.slow_step = 0
        self.slow_column_budget = 0

    # ---- Core: per-frame entry point --------------------------------------

    def render(self, p: Player, bsp_root: BSPNode) -> None:
        """Run one full frame:
          1. Reset per-column open region and per-frame visplane coverage.
          2. Background fill (dim ceiling/floor of the player's current sector)
             so any column that somehow ends up unwritten still looks plausible.
          3. BSP walk → draw_seg for every visible seg, front-to-back.
          4. Visplane pass → flat floors/ceilings rasterized with inverse
             projection + checkerboard texture.
          5. Overlays: minimap and crosshair.
        """
        self.y_top.fill(0)
        self.y_bot.fill(self.buf_h - 1)
        for v in self.visplanes:
            v.reset()

        player_sector = find_sector(p.pos, bsp_root)
        sec = sectors[player_sector]
        half_w = self.buf_w / 2.0
        half_h = self.buf_h / 2.0
        horizon = half_h

        # Background fill — top half = sector ceiling, bottom half = sector
        # floor, both dimmed so legitimate geometry still reads as brighter.
        ceil_dim = shade(sec.ceil_color, 0.55)
        floor_dim = shade(sec.floor_color, 0.55)
        mid = self.buf_h // 2
        self.pixels[:mid, :] = (ceil_dim.r, ceil_dim.g, ceil_dim.b, 255)
        self.pixels[mid:, :] = (floor_dim.r, floor_dim.g, floor_dim.b, 255)

        # Pinhole camera setup. focal = halfW / tan(fov/2) is the standard
        # "screen plane is `focal` units in front of the eye" projection.
        fov_half_tan = math.tan(p.fov / 2.0)
        focal = half_w / fov_half_tan
        eye_z = p.eye_z()
        cos_a = math.cos(p.angle)
        sin_a = math.sin(p.angle)

        if self.slow_mode:
            buffered: list[Seg] = []
            traverse_bsp(bsp_root, p.pos, buffered.append)
            self.slow_column_budget = self.slow_step
            for s in buffered:
                self._draw_seg(s, p, cos_a, sin_a, half_w, horizon, fov_half_tan, focal, eye_z)
            if self.slow_column_budget > 0:
                self.slow_step = 0
            else:
                self.slow_step += 1
        else:
            traverse_bsp(
                bsp_root, p.pos,
                lambda s: self._draw_seg(s, p, cos_a, sin_a, half_w, horizon, fov_half_tan, focal, eye_z),
            )

        self._render_visplanes(focal, half_w, horizon, p.pos, cos_a, sin_a, eye_z)
        self._draw_minimap(p)
        self._draw_crosshair()

    # ---- Per-pixel helpers ------------------------------------------------

    def _put_pixel(self, x: int, y: int, c: RGBA) -> None:
        """Bounds-checked single pixel. Used by overlays. The hot inner loops
        skip the bounds check because they pre-clip x/y to the buffer."""
        if x < 0 or x >= self.buf_w or y < 0 or y >= self.buf_h:
            return
        self.pixels[y, x] = (c.r, c.g, c.b, c.a)

    def _fill_column(self, x: int, y_lo: int, y_hi: int, c: RGBA) -> None:
        """Paint a vertical span of column x with a solid color."""
        if y_lo > y_hi:
            return
        if y_lo < 0:
            y_lo = 0
        if y_hi >= self.buf_h:
            y_hi = self.buf_h - 1
        self.pixels[y_lo:y_hi + 1, x] = (c.r, c.g, c.b, 255)

    # ---- Seg rasterization (formerly renderer_seg.go) ---------------------
    #
    # _draw_seg is the per-seg rasterizer and the engine's single most complex
    # function. Once per visible seg, in BSP front-to-back order, it:
    #
    #   1. Back-face culls (only render segs whose front sector faces us).
    #   2. Transforms both endpoints from world space into view space, where
    #      forward is +d (depth) and right is +r.
    #   3. Clips against the near plane and the left/right frustum planes
    #      (each a simple inequality on r ± k*d).
    #   4. Projects clipped endpoints to screen X.
    #   5. For each screen column from xStart to xEnd:
    #        a. Skip columns the column-clip arrays say are fully occluded.
    #        b. Linearly interpolate 1/d (perspective-correct) → depth.
    #        c. Compute projected ceiling-Y and floor-Y: the open vertical slot.
    #        d. Above the ceiling and below the floor: extend the corresponding
    #           sector's visplane spans (deferred — see _render_visplanes).
    #        e. If solid: fill slot with wall color, mark column fully occluded.
    #        f. If portal: optionally draw upper/lower wall slivers, then
    #           narrow yTop/yBot to the back sector's open range.
    #
    # Per-column lighting is a simple distance falloff: 1/(1+d*0.004), scaled
    # by the front sector's authored light, clamped to a 0.15 floor.

    def _draw_seg(self, seg: Seg, p: Player,
                  cos_a: float, sin_a: float,
                  half_w: float, horizon: float,
                  fov_half_tan: float, focal: float, eye_z: float) -> None:
        # Back-face cull. Outward normal is (-sdy, sdx). If the player is on
        # the wrong side of that normal, this seg's "front" faces away.
        sdx = seg.v2.x - seg.v1.x
        sdy = seg.v2.y - seg.v1.y
        nx = -sdy
        ny = sdx
        to_px = p.pos.x - seg.v1.x
        to_py = p.pos.y - seg.v1.y
        if nx * to_px + ny * to_py <= 0:
            return

        # World → view space.
        rx1 = seg.v1.x - p.pos.x
        ry1 = seg.v1.y - p.pos.y
        rx2 = seg.v2.x - p.pos.x
        ry2 = seg.v2.y - p.pos.y
        r1 = -rx1 * sin_a + ry1 * cos_a
        d1 = rx1 * cos_a + ry1 * sin_a
        r2 = -rx2 * sin_a + ry2 * cos_a
        d2 = rx2 * cos_a + ry2 * sin_a

        near = 1.0
        if d1 < near and d2 < near:
            return
        if d1 < near:
            t = (near - d1) / (d2 - d1)
            r1 = r1 + t * (r2 - r1)
            d1 = near
        elif d2 < near:
            t = (near - d2) / (d1 - d2)
            r2 = r2 + t * (r1 - r2)
            d2 = near

        # Left frustum (r + k*d >= 0).
        k = fov_half_tan
        l_d1 = r1 + k * d1
        l_d2 = r2 + k * d2
        if l_d1 < 0 and l_d2 < 0:
            return
        if l_d1 < 0:
            t = l_d1 / (l_d1 - l_d2)
            r1 = r1 + t * (r2 - r1)
            d1 = d1 + t * (d2 - d1)
        elif l_d2 < 0:
            t = l_d2 / (l_d2 - l_d1)
            r2 = r2 + t * (r1 - r2)
            d2 = d2 + t * (d1 - d2)

        # Right frustum (k*d - r >= 0).
        r_d1 = k * d1 - r1
        r_d2 = k * d2 - r2
        if r_d1 < 0 and r_d2 < 0:
            return
        if r_d1 < 0:
            t = r_d1 / (r_d1 - r_d2)
            r1 = r1 + t * (r2 - r1)
            d1 = d1 + t * (d2 - d1)
        elif r_d2 < 0:
            t = r_d2 / (r_d2 - r_d1)
            r2 = r2 + t * (r1 - r2)
            d2 = d2 + t * (d1 - d2)

        sx1 = half_w + (r1 / d1) * focal
        sx2 = half_w + (r2 / d2) * focal
        if sx2 <= sx1 + 0.0001:
            return

        x_start = int(math.ceil(sx1))
        if x_start < 0:
            x_start = 0
        x_end = int(math.floor(sx2))
        if x_end > self.buf_w - 1:
            x_end = self.buf_w - 1
        if x_start > x_end:
            return

        front = sectors[seg.front_sector]
        f_ceil = front.ceil_h - eye_z
        f_floor = front.floor_h - eye_z
        b_ceil = b_floor = 0.0
        if seg.back_sector != NO_SECTOR:
            back = sectors[seg.back_sector]
            b_ceil = back.ceil_h - eye_z
            b_floor = back.floor_h - eye_z

        line_def = linedefs[seg.linedef_index]
        front_light = front.light

        inv_d1 = 1.0 / d1
        inv_d2 = 1.0 / d2
        d_x = sx2 - sx1

        ceil_visplane = self.visplanes[seg.front_sector * 2 + 1]
        floor_visplane = self.visplanes[seg.front_sector * 2]
        y_top = self.y_top
        y_bot = self.y_bot

        for x in range(x_start, x_end + 1):
            if self.slow_mode:
                if self.slow_column_budget <= 0:
                    return
                self.slow_column_budget -= 1
            top = int(y_top[x])
            bot = int(y_bot[x])
            if top > bot:
                continue
            t_lin = (x - sx1) / d_x
            inv_d = (1.0 - t_lin) * inv_d1 + t_lin * inv_d2
            depth = 1.0 / inv_d

            falloff = 1.0 / (1.0 + depth * 0.004)
            light = clamp_f(front_light * falloff, 0.15, 1.0)

            ceil_y = int(round(horizon - f_ceil * focal * inv_d))
            floor_y = int(round(horizon - f_floor * focal * inv_d))

            # Ceiling visplane span.
            if ceil_y > top:
                y_lo = top
                y_hi = ceil_y - 1
                if y_hi > bot:
                    y_hi = bot
                ceil_visplane.extend(x, y_lo, y_hi)
            # Floor visplane span.
            if floor_y < bot:
                y_lo = floor_y + 1
                if y_lo < top:
                    y_lo = top
                y_hi = bot
                floor_visplane.extend(x, y_lo, y_hi)

            if seg.back_sector == NO_SECTOR:
                # Solid wall.
                y_lo = ceil_y
                if y_lo < top:
                    y_lo = top
                y_hi = floor_y
                if y_hi > bot:
                    y_hi = bot
                self._fill_column(x, y_lo, y_hi, shade(line_def.wall_color, light))
                y_top[x] = bot + 1  # mark fully occluded
            else:
                back_ceil_y = int(round(horizon - b_ceil * focal * inv_d))
                back_floor_y = int(round(horizon - b_floor * focal * inv_d))

                # Upper wall.
                new_top = ceil_y
                if new_top < top:
                    new_top = top
                if back_ceil_y > ceil_y:
                    y_lo = ceil_y
                    if y_lo < top:
                        y_lo = top
                    y_hi = back_ceil_y - 1
                    if y_hi > bot:
                        y_hi = bot
                    self._fill_column(x, y_lo, y_hi, shade(line_def.upper_color, light))
                    new_top = back_ceil_y
                    if new_top < top:
                        new_top = top

                # Lower wall.
                new_bot = floor_y
                if new_bot > bot:
                    new_bot = bot
                if back_floor_y < floor_y:
                    y_lo = back_floor_y + 1
                    if y_lo < top:
                        y_lo = top
                    y_hi = floor_y
                    if y_hi > bot:
                        y_hi = bot
                    self._fill_column(x, y_lo, y_hi, shade(line_def.lower_color, light))
                    new_bot = back_floor_y
                    if new_bot > bot:
                        new_bot = bot

                y_top[x] = new_top
                y_bot[x] = new_bot
                if y_top[x] > y_bot[x]:
                    y_top[x] = y_bot[x] + 1

    # ---- Visplane pass (formerly renderer_visplanes.go + renderer_fill.go) ----
    #
    # During the BSP walk, _draw_seg never colors floor or ceiling pixels
    # directly: it only records per-column spans (yLo..yHi) into the appropriate
    # sector's floor or ceiling Visplane. After the walk, every visplane that
    # received any coverage is rasterized scanline-by-scanline.

    def _render_visplanes(self, focal: float, half_w: float, horizon: float,
                          player_pos: Vec2, cos_a: float, sin_a: float,
                          eye_z: float) -> None:
        for plane in self.visplanes:
            if plane.max_x < plane.min_x:
                continue
            sec = sectors[plane.sector_index]
            if plane.is_ceiling:
                plane_z = sec.ceil_h
                color = sec.ceil_color
            else:
                plane_z = sec.floor_h
                color = sec.floor_color
            plane_height = plane_z - eye_z  # signed: + above eye, - below

            for x in range(plane.min_x, plane.max_x + 1):
                y_lo = int(plane.top[x])
                y_hi = int(plane.bot[x])
                if y_lo > y_hi:
                    continue
                self._fill_plane_column(x, y_lo, y_hi,
                                        plane_height, focal, half_w, horizon,
                                        player_pos, cos_a, sin_a,
                                        sec.light, color)

    def _fill_plane_column(self, x: int, y_lo: int, y_hi: int,
                           plane_height: float, focal: float,
                           half_w: float, horizon: float,
                           player_pos: Vec2, cos_a: float, sin_a: float,
                           sector_light: float, color: RGBA) -> None:
        """Rasterize one vertical strip of a single floor or ceiling plane.

        The plane is horizontal in world space — every pixel in the strip
        belongs to the same world Z. For each screen pixel we inverse-project
        to the world (X, Y) it represents, sample a procedural 16-unit
        checkerboard there, and apply distance-based shading.

        plane_height = planeZ - eyeZ; only its magnitude matters for depth,
        but the sign is implicit in the caller's choice of yLo/yHi.
        """
        if y_lo > y_hi:
            return

        abs_h = abs(plane_height)
        x_offset = float(x) - half_w

        # Vectorized over all rows in [y_lo..y_hi]. Profile-critical: this is
        # the engine's hottest inner loop; per-row Python would be ~50× slower.
        ys = np.arange(y_lo, y_hi + 1, dtype=np.float64)
        abs_dy = np.abs(ys - horizon)
        # depth = abs_h * focal / abs_dy, with horizon pixels pushed to "infinity"
        depth = np.where(abs_dy > 0.0001, abs_h * focal / np.maximum(abs_dy, 1e-9), 1e9)
        # View-space right offset for this pixel at this depth.
        right = x_offset * depth / focal
        # Camera-space → world space rotation.
        wx = player_pos.x + depth * cos_a - right * sin_a
        wy = player_pos.y + depth * sin_a + right * cos_a

        # Checkerboard sample. tile_bias keeps the int coordinates positive
        # so the parity test (tx ^ ty) & 1 is stable across the origin.
        tile_bits = 4
        tile_bias = 1 << 20
        tx = (wx.astype(np.int64) + tile_bias) >> tile_bits
        ty = (wy.astype(np.int64) + tile_bias) >> tile_bits
        is_dark = ((tx ^ ty) & 1) != 0  # parity 1 → dark tile

        # Per-pixel light: distance falloff × sector light, clamped to floor.
        falloff = 1.0 / (1.0 + depth * 0.004)
        light = np.clip(sector_light * falloff, 0.15, 1.0) * 0.9
        # shade() floor is 0.12 — apply that too so we match the Go behavior.
        light = np.clip(light, 0.12, 1.0)

        # Combine: light tile is `color`, dark tile is color*0.7. Fold both
        # into per-pixel multipliers so we can do one mul per channel.
        mult = light * np.where(is_dark, 0.7, 1.0)
        r = (color.r * mult).astype(np.uint8)
        g = (color.g * mult).astype(np.uint8)
        b = (color.b * mult).astype(np.uint8)

        col = self.pixels[y_lo:y_hi + 1, x]
        col[:, 0] = r
        col[:, 1] = g
        col[:, 2] = b
        col[:, 3] = 255

    # ---- Overlays (formerly renderer_overlays.go) -------------------------

    def _draw_crosshair(self) -> None:
        cx, cy = self.buf_w // 2, self.buf_h // 2
        white = RGBA(255, 255, 255, 255)
        for d in range(-3, 4):
            if d == 0:
                continue
            self._put_pixel(cx + d, cy, white)
            self._put_pixel(cx, cy + d, white)

    def _draw_minimap(self, p: Player) -> None:
        """Top-down preview of the level in the upper-left: dark backdrop,
        all linedefs (one-sided in their wall color, two-sided gray), player
        marker with a heading line."""
        min_x = min(v.x for v in vertices)
        min_y = min(v.y for v in vertices)
        max_x = max(v.x for v in vertices)
        max_y = max(v.y for v in vertices)

        pad = 8.0
        box_w = 120.0
        box_h = 100.0
        ox = 8.0
        oy = 8.0
        sx = box_w / (max_x - min_x + 2 * pad)
        sy = box_h / (max_y - min_y + 2 * pad)
        s = min(sx, sy)

        def project(v: Vec2) -> tuple[int, int]:
            return (int(ox + ((v.x - min_x) + pad) * s),
                    int(oy + ((v.y - min_y) + pad) * s))

        # Backdrop.
        backdrop = RGBA(10, 10, 14, 255)
        for y in range(int(oy - 2), int(oy + box_h + 2) + 1):
            for x in range(int(ox - 2), int(ox + box_w + 2) + 1):
                self._put_pixel(x, y, backdrop)

        # Linedefs.
        for l in linedefs:
            ax, ay = project(vertices[l.v1])
            bx, by = project(vertices[l.v2])
            col = RGBA(120, 120, 120, 255) if l.back_sector != NO_SECTOR else l.wall_color
            self._draw_line(ax, ay, bx, by, col)

        # Player.
        px_i, py_i = project(p.pos)
        white = RGBA(255, 255, 255, 255)
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                self._put_pixel(px_i + dx, py_i + dy, white)
        hx = px_i + int(math.cos(p.angle) * 10)
        hy = py_i + int(math.sin(p.angle) * 10)
        self._draw_line(px_i, py_i, hx, hy, white)

    def _draw_line(self, x0: int, y0: int, x1: int, y1: int, color: RGBA) -> None:
        """Standard integer Bresenham; bounds-checked plotting via _put_pixel."""
        dx = x1 - x0
        if dx < 0:
            dx = -dx
        sx = 1 if x0 < x1 else -1
        dy = y1 - y0
        if dy < 0:
            dy = -dy
        dy = -dy
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self._put_pixel(x0, y0, color)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

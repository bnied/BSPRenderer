"""Visplane — DOOM's deferred floor/ceiling rendering primitive.

During the BSP walk, draw_seg never colors a single floor or ceiling pixel.
Instead, for each screen column it updates a per-sector Visplane with the
vertical span of that column that belongs to this sector's floor (or
ceiling). After the BSP walk, render_visplanes sweeps every visplane and
rasterizes the spans by inverse-projecting each pixel back to its world
(X, Y) for procedural texturing and depth shading.

This is what lets several sectors' floors and ceilings composite correctly
across the screen without a depth buffer: every column has at most one
floor visplane span and one ceiling visplane span (per sector), tracked
independently and rasterized once.

Per renderer there are 2 visplanes per sector — index 2*si is the floor
and index 2*si+1 is the ceiling. Each plane keeps:

  top[x]  — inclusive upper bound of the span at column x (huge → none)
  bot[x]  — inclusive lower bound of the span at column x (-huge → none)
  min_x/max_x — range of columns actually touched this frame, so the
                rasterizer can skip empty columns cheaply.
"""

from __future__ import annotations

import numpy as np

# Sentinels for "no span yet at this column". Use ordinary ints (not the C-int
# extremes) so the per-frame Reset is a fast numpy fill.
TOP_EMPTY = 1 << 30
BOT_EMPTY = -(1 << 30)


class Visplane:
    __slots__ = ("sector_index", "is_ceiling", "top", "bot", "min_x", "max_x", "_w")

    def __init__(self, sector_index: int, is_ceiling: bool, width: int) -> None:
        self.sector_index = sector_index
        self.is_ceiling = is_ceiling
        self.top = np.empty(width, dtype=np.int32)
        self.bot = np.empty(width, dtype=np.int32)
        self._w = width
        self.reset()

    def reset(self) -> None:
        """Wipe coverage at the start of each frame."""
        self.top.fill(TOP_EMPTY)
        self.bot.fill(BOT_EMPTY)
        self.min_x = self._w
        self.max_x = -1

    def extend(self, x: int, y_lo: int, y_hi: int) -> None:
        """Grow the span at column x to include [y_lo..y_hi]. The y_lo > y_hi
        no-op is the easy way to write "I might have nothing to add this column"."""
        if y_lo > y_hi:
            return
        if y_lo < self.top[x]:
            self.top[x] = y_lo
        if y_hi > self.bot[x]:
            self.bot[x] = y_hi
        if x < self.min_x:
            self.min_x = x
        if x > self.max_x:
            self.max_x = x

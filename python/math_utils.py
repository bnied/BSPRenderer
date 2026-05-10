"""Math primitives shared across the engine: a 2-D vector, an 8-bit-per-channel
color, and a couple of small helpers.

Everything in the world is 2-D-with-heights: positions and movement live in
(x, y) — see Vec2 — and floors/ceilings have a separate scalar Z stored on
each Sector. There is no full 3-D vector type because we never need one;
all the perspective math operates on screen columns whose vertical extent
is computed from a Z difference and a depth.
"""

from __future__ import annotations

import math
from typing import NamedTuple


class Vec2(NamedTuple):
    """2-D world or view-space point/vector."""

    x: float
    y: float

    def add(self, o: "Vec2") -> "Vec2":
        return Vec2(self.x + o.x, self.y + o.y)

    def sub(self, o: "Vec2") -> "Vec2":
        return Vec2(self.x - o.x, self.y - o.y)

    def mul(self, s: float) -> "Vec2":
        return Vec2(self.x * s, self.y * s)

    def length(self) -> float:
        return math.sqrt(self.x * self.x + self.y * self.y)


class RGBA(NamedTuple):
    """In-memory pixel format of the framebuffer (matches numpy's row-major
    uint8 RGBA layout). Stored straight rather than premultiplied — `shade`
    scales the channels for distance/light."""

    r: int
    g: int
    b: int
    a: int


def shade(c: RGBA, f: float) -> RGBA:
    """Multiply an RGB triple by brightness factor `f`, clamped to [0.12, 1.0].
    The 0.12 floor keeps far-away geometry from going pure black, which would
    make portals look like holes in the screen."""
    k = max(0.12, min(1.0, f))
    return RGBA(int(c.r * k), int(c.g * k), int(c.b * k), 255)


def clamp_f(x: float, lo: float, hi: float) -> float:
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x

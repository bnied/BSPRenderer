"""Player physics: movement, collision, and the camera-height policy.

The player is a 2-D circle of radius 8 in the (x, y) plane that auto-snaps
its feet Z to the current sector's floor height. Step-up across portals is
gated by max_step_up; portals whose vertical opening is shorter than the
player's standing height are treated as solid.

Vertical camera motion is interesting: see eye_z() and eye_follow_factor.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from bsp import BSPNode, find_sector
from level import linedefs, sectors, vertices
from math_utils import Vec2, clamp_f
from geometry import NO_SECTOR


@dataclass(slots=True)
class Input:
    """Per-tick boolean key state. Filled in by the main loop; the player has
    no idea pygame exists."""

    forward: bool = False
    back: bool = False
    strafe_l: bool = False
    strafe_r: bool = False
    turn_l: bool = False
    turn_r: bool = False


class Player:
    __slots__ = (
        "pos", "feet_z", "angle", "fov", "move_speed", "rot_speed",
        "eye_over_floor", "eye_follow_factor", "baseline_eye_z",
    )

    def __init__(self) -> None:
        # Spawn just north of the hub's south wall, facing north — looking
        # straight down the catwalk into the colored staircase chain. The
        # octagonal pillar is behind the player (turn around to discover it).
        self.pos = Vec2(120, 50)
        self.feet_z: float = 0.0
        self.angle: float = -math.pi / 2
        self.fov: float = 70.0 * math.pi / 180.0
        self.move_speed: float = 140.0
        self.rot_speed: float = 2.4
        self.eye_over_floor: float = 41.0
        self.eye_follow_factor: float = 1.0
        self.baseline_eye_z: float = 41.0

    def eye_z(self) -> float:
        """Blend two camera-height policies:

          eye_follow_factor = 1.0  →  eye is rigidly attached to feet. The
                                      camera physically rises and falls the
                                      full step amount, but because feet and
                                      eye move together, the floor stays at a
                                      constant screen distance below the
                                      horizon.

          eye_follow_factor = 0.0  →  fixed-baseline camera. Eye Z never
                                      changes; the floor's screen position
                                      reflects the sector's true Z, so steps
                                      up/down are visible as the floor sliding
                                      on screen.

          in between               →  partial bobbing.

        We use 1.0 by default — the camera rises/falls with the player and the
        scene around them is what changes (back-sector ceilings come into view,
        upper walls open, etc.).
        """
        feet_baseline = self.baseline_eye_z - self.eye_over_floor
        return self.baseline_eye_z + self.eye_follow_factor * (self.feet_z - feet_baseline)

    def update(self, dt: float, in_: Input, bsp_root: BSPNode) -> None:
        """Advance by `dt` seconds of simulation time. Movement is
        axis-separated and probed against all solid linedefs so the player
        can slide along walls instead of getting stuck on them."""
        rot = self.rot_speed * dt
        mv = self.move_speed * dt

        if in_.turn_l:
            self.angle -= rot
        if in_.turn_r:
            self.angle += rot

        cos_a = math.cos(self.angle)
        sin_a = math.sin(self.angle)

        # Compose desired (dx, dy) in world space from the four movement keys.
        # forward = (cosA, sinA); right = (-sinA, cosA).
        dx = dy = 0.0
        if in_.forward:
            dx += cos_a * mv
            dy += sin_a * mv
        if in_.back:
            dx -= cos_a * mv
            dy -= sin_a * mv
        if in_.strafe_l:
            dx += sin_a * mv
            dy -= cos_a * mv
        if in_.strafe_r:
            dx -= sin_a * mv
            dy += cos_a * mv

        radius = 8.0
        current_floor_h = sectors[find_sector(self.pos, bsp_root)].floor_h

        try_x = Vec2(self.pos.x + dx, self.pos.y)
        if not self._collides(try_x, radius, current_floor_h):
            self.pos = try_x
        try_y = Vec2(self.pos.x, self.pos.y + dy)
        if not self._collides(try_y, radius, current_floor_h):
            self.pos = try_y

        # Snap feet to the new sector's floor (no gravity / falling).
        self.feet_z = sectors[find_sector(self.pos, bsp_root)].floor_h

    def _collides(self, pos: Vec2, radius: float, current_floor_h: float) -> bool:
        """A linedef blocks movement if it's one-sided, OR a portal whose
        opening is too short, OR the back-side floor is more than max_step_up
        above the side we're standing on."""
        max_step_up = 24.0
        for l in linedefs:
            a = vertices[l.v1]
            b = vertices[l.v2]
            if _point_segment_distance(pos, a, b) >= radius:
                continue
            if l.back_sector == NO_SECTOR:
                return True
            front = sectors[l.front_sector]
            back = sectors[l.back_sector]

            # Portal opening must be tall enough to fit through.
            opening_top = min(front.ceil_h, back.ceil_h)
            opening_bottom = max(front.floor_h, back.floor_h)
            if opening_top - opening_bottom < self.eye_over_floor:
                return True

            # Step-up gate: which side is the probe entering?
            pdx = b.x - a.x
            pdy = b.y - a.y
            side = pdx * (pos.y - a.y) - pdy * (pos.x - a.x)
            target_floor_h = back.floor_h if side > 0 else front.floor_h
            if target_floor_h - current_floor_h > max_step_up:
                return True
        return False


def _point_segment_distance(p: Vec2, a: Vec2, b: Vec2) -> float:
    """Perpendicular distance from point p to segment ab, clamped to endpoints."""
    ab = b.sub(a)
    l2 = ab.x * ab.x + ab.y * ab.y
    if l2 < 1e-9:
        return p.sub(a).length()
    t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2
    t = clamp_f(t, 0.0, 1.0)
    proj = Vec2(a.x + ab.x * t, a.y + ab.y * t)
    return p.sub(proj).length()

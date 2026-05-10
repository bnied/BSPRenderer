"""Geometry types — the level's "schema". The actual data lives in level.py.

The model follows DOOM's terminology:

  - Sector:  a flat-floored, flat-ceilinged region with a uniform light
             level. Rooms, corridors, and alcoves are all sectors.
  - LineDef: an authored edge between two vertices. One-sided linedefs are
             solid walls; two-sided linedefs are portals between two
             adjacent sectors and may show upper/lower wall slivers where
             the sectors' ceiling/floor heights differ.
  - Seg:     a renderable wall segment. generate_segs() emits one Seg per
             one-sided linedef and two Segs per two-sided linedef (one per
             side, so the renderer can draw each side from the perspective
             of its own front sector). The BSP builder may further split
             segs at partition crossings.
"""

from __future__ import annotations

from dataclasses import dataclass

from math_utils import RGBA, Vec2

# Sentinel for "no back side" — i.e. a one-sided solid wall.
# Real sector indices are >= 0, so any non-negative value is a portal.
NO_SECTOR = -1


@dataclass(slots=True)
class Sector:
    """Horizontal-floored region. Floor and ceiling are stored as world-space
    Z heights so portals can compute upper/lower wall extents by comparing
    front and back sector heights."""

    floor_h: float
    ceil_h: float
    floor_color: RGBA
    ceil_color: RGBA
    light: float  # 0..1 multiplier applied before distance falloff


@dataclass(slots=True)
class LineDef:
    """Authored line in the map. wall_color is used when the linedef is
    one-sided; upper_color / lower_color are used on two-sided linedefs to
    fill the gaps that appear when the back sector's ceiling is lower or
    floor is higher than the front's."""

    v1: int  # indices into the global vertices list
    v2: int
    front_sector: int
    back_sector: int  # NO_SECTOR → solid one-sided wall
    wall_color: RGBA
    upper_color: RGBA
    lower_color: RGBA


@dataclass(slots=True)
class Seg:
    """Renderable wall segment fed into the BSP. v1/v2 are world-space
    points (not vertex indices) because the BSP builder may split a seg at
    a partition crossing, producing intersection points that aren't in the
    original vertices list."""

    v1: Vec2
    v2: Vec2
    front_sector: int
    back_sector: int  # NO_SECTOR → solid
    linedef_index: int

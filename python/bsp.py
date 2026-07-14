"""Binary Space Partition — node types, partition classification, builder, and
the per-frame traversal, wrapped as a class.

A BSP recursively splits the map's plane into two half-spaces with a chosen
partition line ("seg"). Internal nodes hold the partition; leaves hold a
convex bag of segs that all live in a single sector. The point of the BSP
at render time is twofold:

  1. Bsp.find_sector(pos) descends the tree once and returns the leaf sector
     the player is currently standing in — O(depth), no per-tick search.
  2. Bsp.traverse(player_pos, visit) yields segs front-to-back, which lets
     the per-column clip arrays (yTop/yBot) terminate occluded columns
     without ever needing a depth buffer.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from enum import IntEnum
from typing import TYPE_CHECKING

from math_utils import Vec2
from geometry import NO_SECTOR, Seg

if TYPE_CHECKING:
    from level import Level


@dataclass(slots=True, frozen=True)
class BSPLeaf:
    """A convex bag of segs that all live in a single sector."""

    segs: list[Seg]
    sector: int


@dataclass(slots=True, frozen=True)
class BSPInternal:
    """A partition line plus the two child half-spaces."""

    p_start: Vec2
    p_delta: Vec2
    left: "BSPNode"
    right: "BSPNode"


BSPNode = BSPLeaf | BSPInternal


class SegSide(IntEnum):
    LEFT = 0       # both endpoints in left half-space
    RIGHT = 1      # both endpoints in right half-space
    STRADDLE = 2   # crosses the line — split at intersection
    COLLINEAR = 3  # both endpoints lie on the line


def side_of(p: Vec2, p_start: Vec2, p_delta: Vec2) -> float:
    """Signed perp-product of (p - p_start) against p_delta.
    Positive → p is to the LEFT of the directed partition,
    negative → p is to the RIGHT, zero → on the line.

    "Left" is arbitrary but consistent — generate_segs() and the back-face
    cull rely on the same sign.
    """
    return p_delta.x * (p.y - p_start.y) - p_delta.y * (p.x - p_start.x)


def classify(seg: Seg, part_start: Vec2, part_delta: Vec2) -> tuple[SegSide, Vec2]:
    """Test a seg against a partition line. For STRADDLE, also returns the
    world-space intersection point so the BSP builder can split there.

    The eps tolerance keeps endpoints that are *exactly* on the partition
    (or within a sliver of it) from being treated as straddles, which would
    cause pointless hairline splits.
    """
    eps = 1e-4
    d1 = side_of(seg.v1, part_start, part_delta)
    d2 = side_of(seg.v2, part_start, part_delta)

    s1 = 1 if d1 > eps else (-1 if d1 < -eps else 0)
    s2 = 1 if d2 > eps else (-1 if d2 < -eps else 0)

    if s1 == 0 and s2 == 0:
        return SegSide.COLLINEAR, Vec2(0, 0)
    if s1 >= 0 and s2 >= 0:
        return SegSide.LEFT, Vec2(0, 0)
    if s1 <= 0 and s2 <= 0:
        return SegSide.RIGHT, Vec2(0, 0)
    # Linear interpolation along the seg to find where d crosses zero.
    t = d1 / (d1 - d2)
    ix = seg.v1.x + t * (seg.v2.x - seg.v1.x)
    iy = seg.v1.y + t * (seg.v2.y - seg.v1.y)
    return SegSide.STRADDLE, Vec2(ix, iy)


def _build_node(segs: list[Seg]) -> BSPNode:
    """Construct a BSP subtree from a flat list of segs. Runs once at startup.

    Recursion ends in two ways:
      - <= 1 seg left: trivial leaf.
      - No partition can split the remaining segs into two non-empty sides:
        the region is convex enough that any further split would just be a
        one-sided cut. Stop and store the segs as a leaf.

    Partition selection is greedy: try every seg as a candidate, score by
    imbalance plus a 2× weight on straddle splits, and pick the lowest.
    Small-map quality, deterministic, clean trees on the test map.
    """
    if len(segs) <= 1:
        sec = segs[0].front_sector if segs else 0
        return BSPLeaf(segs=list(segs), sector=sec)

    best_idx = -1
    best_score = 1 << 30
    n = len(segs)
    for i in range(n):
        p_start = segs[i].v1
        p_delta = Vec2(segs[i].v2.x - segs[i].v1.x, segs[i].v2.y - segs[i].v1.y)
        l = r = s = 0
        for j in range(n):
            if j == i:
                continue
            side, _ = classify(segs[j], p_start, p_delta)
            if side == SegSide.LEFT:
                l += 1
            elif side == SegSide.RIGHT:
                r += 1
            elif side == SegSide.STRADDLE:
                s += 1
            # Collinear segs are ignored for scoring — they get assigned to a
            # side later based on direction agreement.
        if l == 0 or r == 0:
            continue
        score = abs(l - r) + 2 * s
        if score < best_score:
            best_score = score
            best_idx = i

    if best_idx == -1:
        return BSPLeaf(segs=list(segs), sector=segs[0].front_sector)

    part = segs[best_idx]
    p_start = part.v1
    p_delta = Vec2(part.v2.x - part.v1.x, part.v2.y - part.v1.y)

    # The partition seg itself goes on the LEFT (front) side, so traversal
    # emits it before the back side from the player's perspective.
    left_segs: list[Seg] = [part]
    right_segs: list[Seg] = []

    for j, seg in enumerate(segs):
        if j == best_idx:
            continue
        side, ix = classify(seg, p_start, p_delta)
        if side == SegSide.LEFT:
            left_segs.append(seg)
        elif side == SegSide.RIGHT:
            right_segs.append(seg)
        elif side == SegSide.COLLINEAR:
            # Same direction as the partition → front side; opposite → back.
            sdx = seg.v2.x - seg.v1.x
            sdy = seg.v2.y - seg.v1.y
            if p_delta.x * sdx + p_delta.y * sdy >= 0:
                left_segs.append(seg)
            else:
                right_segs.append(seg)
        else:  # STRADDLE
            a = Seg(v1=seg.v1, v2=ix,
                    front_sector=seg.front_sector,
                    back_sector=seg.back_sector,
                    linedef_index=seg.linedef_index)
            b = Seg(v1=ix, v2=seg.v2,
                    front_sector=seg.front_sector,
                    back_sector=seg.back_sector,
                    linedef_index=seg.linedef_index)
            sa, _ = classify(a, p_start, p_delta)
            (left_segs if sa == SegSide.LEFT else right_segs).append(a)
            sb, _ = classify(b, p_start, p_delta)
            (left_segs if sb == SegSide.LEFT else right_segs).append(b)

    return BSPInternal(
        p_start=p_start,
        p_delta=p_delta,
        left=_build_node(left_segs),
        right=_build_node(right_segs),
    )


class Bsp:
    """The BSP tree over a level's segs, exposing the two per-frame queries."""

    __slots__ = ("root",)

    def __init__(self, root: BSPNode) -> None:
        self.root = root

    @classmethod
    def build(cls, level: "Level") -> "Bsp":
        """Build a balanced-ish BSP over the level's segs. The greedy
        partition pick tries every candidate seg and scores by side imbalance
        plus a heavy weight on straddle splits (each split duplicates a seg)."""
        return cls(_build_node(level.generate_segs()))

    def find_sector(self, pos: Vec2) -> int:
        """Descend the BSP tree to the leaf containing pos and return its
        sector index."""
        node = self.root
        while isinstance(node, BSPInternal):
            if side_of(pos, node.p_start, node.p_delta) >= 0:
                node = node.left
            else:
                node = node.right
        return node.sector

    def traverse(self, player: Vec2, visit: Callable[[Seg], None]) -> None:
        """Walk the tree front-to-back from the player's position and invoke
        `visit` on every seg in order. Going front-first is what makes the
        per-column clip arrays act as a no-op depth buffer — by the time we
        reach a far-away seg, columns it would have covered are already closed.
        """
        _traverse(self.root, player, visit)


def _traverse(node: BSPNode, player: Vec2, visit: Callable[[Seg], None]) -> None:
    if isinstance(node, BSPLeaf):
        for s in node.segs:
            visit(s)
        return
    if side_of(player, node.p_start, node.p_delta) >= 0:
        _traverse(node.left, player, visit)
        _traverse(node.right, player, visit)
    else:
        _traverse(node.right, player, visit)
        _traverse(node.left, player, visit)

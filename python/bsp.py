"""Binary Space Partition — node type, partition classification, builder, and
the per-frame traversal helpers.

A BSP recursively splits the map's plane into two half-spaces with a chosen
partition line ("seg"). Internal nodes hold the partition; leaves hold a
convex bag of segs that all live in a single sector. The point of the BSP
at render time is twofold:

  1. find_sector(pos) descends the tree once and returns the leaf sector the
     player is currently standing in — O(depth), no per-tick search.
  2. traverse_bsp(player_pos, visit) yields segs front-to-back, which lets
     the per-column clip arrays (yTop/yBot) terminate occluded columns
     without ever needing a depth buffer.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from enum import IntEnum

from level import linedefs, vertices
from math_utils import Vec2
from geometry import NO_SECTOR, Seg


@dataclass(slots=True)
class BSPNode:
    """Either a leaf (segs + sector) or an internal node (partition line +
    left/right children)."""

    leaf: bool
    # Leaf only:
    segs: list[Seg] = field(default_factory=list)
    sector: int = 0
    # Internal only:
    p_start: Vec2 = Vec2(0, 0)
    p_delta: Vec2 = Vec2(0, 0)
    left: "BSPNode | None" = None
    right: "BSPNode | None" = None


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


def generate_segs() -> list[Seg]:
    """Flatten the linedef list into the seg list that the BSP builder will
    consume.

    One-sided linedefs produce ONE seg in their authored direction (front
    side only, because the back is solid and never visible).

    Two-sided linedefs produce TWO segs — the second runs in reverse and
    has its front/back sectors swapped. The BSP needs both because each
    side of a portal will be rasterized from its own sector during
    traversal, with its own ceiling/floor heights and per-sector light.
    """
    out: list[Seg] = []
    for i, l in enumerate(linedefs):
        a = vertices[l.v1]
        b = vertices[l.v2]
        # Authored direction (front side).
        out.append(Seg(v1=a, v2=b,
                       front_sector=l.front_sector,
                       back_sector=l.back_sector,
                       linedef_index=i))
        # Reverse direction (back side) for two-sided linedefs.
        if l.back_sector != NO_SECTOR:
            out.append(Seg(v1=b, v2=a,
                           front_sector=l.back_sector,
                           back_sector=l.front_sector,
                           linedef_index=i))
    return out


def build_bsp(segs: list[Seg]) -> BSPNode:
    """Construct a BSP tree from a flat list of segs. Runs once at startup.

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
        return BSPNode(leaf=True, segs=list(segs), sector=sec)

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
        return BSPNode(leaf=True, segs=list(segs), sector=segs[0].front_sector)

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

    return BSPNode(
        leaf=False,
        p_start=p_start,
        p_delta=p_delta,
        left=build_bsp(left_segs),
        right=build_bsp(right_segs),
    )


def find_sector(pos: Vec2, node: BSPNode) -> int:
    """Descend the BSP tree to the leaf containing pos and return its
    sector index."""
    while not node.leaf:
        if side_of(pos, node.p_start, node.p_delta) >= 0:
            node = node.left  # type: ignore[assignment]
        else:
            node = node.right  # type: ignore[assignment]
    return node.sector


def traverse_bsp(node: BSPNode, player: Vec2, visit: Callable[[Seg], None]) -> None:
    """Walk the tree front-to-back from the player's position and invoke
    `visit` on every seg in order. Going front-first is what makes the
    per-column clip arrays act as a no-op depth buffer — by the time we
    reach a far-away seg, columns it would have covered are already closed.
    """
    if node.leaf:
        for s in node.segs:
            visit(s)
        return
    if side_of(player, node.p_start, node.p_delta) >= 0:
        traverse_bsp(node.left, player, visit)  # type: ignore[arg-type]
        traverse_bsp(node.right, player, visit)  # type: ignore[arg-type]
    else:
        traverse_bsp(node.right, player, visit)  # type: ignore[arg-type]
        traverse_bsp(node.left, player, visit)  # type: ignore[arg-type]

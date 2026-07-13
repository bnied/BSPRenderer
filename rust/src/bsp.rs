//! Binary Space Partition — node type, partition classification, builder, and
//! the per-frame traversal helpers.
//!
//! A BSP recursively splits the map's plane into two half-spaces with a chosen
//! partition line ("seg"). Internal nodes hold the partition; leaves hold a
//! convex bag of segs that all live in a single sector. The point of the BSP
//! at render time is twofold:
//!
//!   1. [`Bsp::find_sector`] descends the tree once and returns the leaf sector
//!      the player is currently standing in — O(depth), no per-tick search.
//!   2. [`Bsp::traverse`] yields segs front-to-back, which lets the per-column
//!      clip arrays (yTop/yBot) terminate occluded columns without ever
//!      needing a depth buffer.

use crate::geometry::Seg;
use crate::level::Level;
use crate::math_utils::Vec2;

/// The BSP tree, wrapped so callers only touch the two query methods. The node
/// enum ([`BspNode`]) stays a clean leaf/branch variant; `Bsp` just owns the
/// root and hangs the queries off it.
pub struct Bsp {
    root: Box<BspNode>,
}

impl Bsp {
    /// Build a BSP over the level's segs. Runs once at startup.
    pub fn build(level: &Level) -> Self {
        Bsp {
            root: build_bsp(level.generate_segs()),
        }
    }

    /// Descend to the leaf containing `pos` and return its sector index.
    pub fn find_sector(&self, pos: Vec2) -> usize {
        find_sector(pos, &self.root)
    }

    /// Walk the tree front-to-back from the player's position and invoke
    /// `visit` on every seg in order.
    pub fn traverse(&self, player: Vec2, visit: &mut impl FnMut(&Seg)) {
        traverse_bsp(&self.root, player, visit);
    }
}

/// Either a leaf (segs + sector) or an internal node (partition line +
/// left/right children).
#[derive(Debug)]
pub enum BspNode {
    Leaf {
        segs: Vec<Seg>,
        sector: usize,
    },
    Branch {
        p_start: Vec2,
        p_delta: Vec2,
        /// "Left" half-space: same side as the partition's directed normal.
        left: Box<BspNode>,
        right: Box<BspNode>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum SegSide {
    Left,      // both endpoints in left half-space
    Right,     // both endpoints in right half-space
    Straddle,  // crosses the line — split at intersection
    Collinear, // both endpoints lie on the line
}

/// Signed perp-product of (p - p_start) against p_delta.
/// Positive → p is to the LEFT of the directed partition,
/// negative → p is to the RIGHT, zero → on the line.
fn side_of(p: Vec2, p_start: Vec2, p_delta: Vec2) -> f64 {
    p_delta.x * (p.y - p_start.y) - p_delta.y * (p.x - p_start.x)
}

/// Test a seg against a partition line. For [`SegSide::Straddle`], also
/// returns the world-space intersection point so the BSP builder can split
/// there.
///
/// The eps tolerance keeps endpoints that are *exactly* on the partition
/// (or within a sliver of it) from being treated as straddles, which would
/// cause pointless hairline splits.
fn classify(seg: &Seg, part_start: Vec2, part_delta: Vec2) -> (SegSide, Vec2) {
    const EPS: f64 = 1e-4;
    let d1 = side_of(seg.v1, part_start, part_delta);
    let d2 = side_of(seg.v2, part_start, part_delta);

    let s1 = if d1 > EPS { 1 } else if d1 < -EPS { -1 } else { 0 };
    let s2 = if d2 > EPS { 1 } else if d2 < -EPS { -1 } else { 0 };

    if s1 == 0 && s2 == 0 {
        return (SegSide::Collinear, Vec2::default());
    }
    if s1 >= 0 && s2 >= 0 {
        return (SegSide::Left, Vec2::default());
    }
    if s1 <= 0 && s2 <= 0 {
        return (SegSide::Right, Vec2::default());
    }
    // Linear interpolation along the seg to find where d crosses zero.
    let t = d1 / (d1 - d2);
    let ix = seg.v1.x + t * (seg.v2.x - seg.v1.x);
    let iy = seg.v1.y + t * (seg.v2.y - seg.v1.y);
    (SegSide::Straddle, Vec2::new(ix, iy))
}

/// Construct a BSP tree from a flat list of segs. Runs once at startup.
///
/// Recursion ends in two ways:
///   - <= 1 seg left: trivial leaf.
///   - No partition can split the remaining segs into two non-empty sides:
///     the region is convex enough that any further split would just be a
///     one-sided cut. Stop and store the segs as a leaf.
///
/// Partition selection is greedy: try every seg as a candidate, score by
/// imbalance plus a 2× weight on straddle splits, and pick the lowest.
/// Small-map quality, deterministic, clean trees on the test map.
fn build_bsp(segs: Vec<Seg>) -> Box<BspNode> {
    if segs.len() <= 1 {
        let sector = if segs.is_empty() { 0 } else { segs[0].front_sector };
        return Box::new(BspNode::Leaf { segs, sector });
    }

    let n = segs.len();
    let mut best_idx: Option<usize> = None;
    let mut best_score = i64::MAX;

    for i in 0..n {
        let p_start = segs[i].v1;
        let p_delta = Vec2::new(segs[i].v2.x - segs[i].v1.x, segs[i].v2.y - segs[i].v1.y);
        let (mut l, mut r, mut s) = (0i64, 0i64, 0i64);
        for j in 0..n {
            if j == i {
                continue;
            }
            match classify(&segs[j], p_start, p_delta).0 {
                SegSide::Left => l += 1,
                SegSide::Right => r += 1,
                SegSide::Straddle => s += 1,
                SegSide::Collinear => {} // ignored for scoring
            }
        }
        if l == 0 || r == 0 {
            continue; // doesn't actually partition
        }
        let score = (l - r).abs() + 2 * s;
        if score < best_score {
            best_score = score;
            best_idx = Some(i);
        }
    }

    let Some(best_idx) = best_idx else {
        // Convex enough — every candidate leaves one side empty.
        let sector = segs[0].front_sector;
        return Box::new(BspNode::Leaf { segs, sector });
    };

    let part = segs[best_idx];
    let p_start = part.v1;
    let p_delta = Vec2::new(part.v2.x - part.v1.x, part.v2.y - part.v1.y);

    // The partition seg itself goes on the LEFT (front) side, so traversal
    // emits it before the back side from the player's perspective.
    let mut left_segs: Vec<Seg> = vec![part];
    let mut right_segs: Vec<Seg> = Vec::new();

    for (j, seg) in segs.iter().enumerate() {
        if j == best_idx {
            continue;
        }
        let (side, ix) = classify(seg, p_start, p_delta);
        match side {
            SegSide::Left => left_segs.push(*seg),
            SegSide::Right => right_segs.push(*seg),
            SegSide::Collinear => {
                // Same direction as the partition → front side; opposite → back.
                let sdx = seg.v2.x - seg.v1.x;
                let sdy = seg.v2.y - seg.v1.y;
                if p_delta.x * sdx + p_delta.y * sdy >= 0.0 {
                    left_segs.push(*seg);
                } else {
                    right_segs.push(*seg);
                }
            }
            SegSide::Straddle => {
                let a = Seg { v1: seg.v1, v2: ix, ..*seg };
                let b = Seg { v1: ix, v2: seg.v2, ..*seg };
                if classify(&a, p_start, p_delta).0 == SegSide::Left {
                    left_segs.push(a);
                } else {
                    right_segs.push(a);
                }
                if classify(&b, p_start, p_delta).0 == SegSide::Left {
                    left_segs.push(b);
                } else {
                    right_segs.push(b);
                }
            }
        }
    }

    Box::new(BspNode::Branch {
        p_start,
        p_delta,
        left: build_bsp(left_segs),
        right: build_bsp(right_segs),
    })
}

/// Descend the BSP tree to the leaf containing `pos` and return its sector
/// index.
fn find_sector(pos: Vec2, mut node: &BspNode) -> usize {
    loop {
        match node {
            BspNode::Leaf { sector, .. } => return *sector,
            BspNode::Branch { p_start, p_delta, left, right } => {
                node = if side_of(pos, *p_start, *p_delta) >= 0.0 {
                    left
                } else {
                    right
                };
            }
        }
    }
}

/// Walk the tree front-to-back from the player's position and invoke `visit`
/// on every seg in order. Going front-first is what makes the per-column
/// clip arrays act as a no-op depth buffer — by the time we reach a far-away
/// seg, columns it would have covered are already closed off.
fn traverse_bsp<F: FnMut(&Seg)>(node: &BspNode, player: Vec2, visit: &mut F) {
    match node {
        BspNode::Leaf { segs, .. } => {
            for s in segs {
                visit(s);
            }
        }
        BspNode::Branch { p_start, p_delta, left, right } => {
            if side_of(player, *p_start, *p_delta) >= 0.0 {
                traverse_bsp(left, player, visit);
                traverse_bsp(right, player, visit);
            } else {
                traverse_bsp(right, player, visit);
                traverse_bsp(left, player, visit);
            }
        }
    }
}

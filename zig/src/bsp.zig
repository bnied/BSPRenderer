// Binary Space Partition — node type, geometric primitives, builder, and the
// traversal helpers used by both the renderer (front-to-back walk) and the
// player (sector lookup).
//
// A BSP recursively splits the map's plane into two half-spaces with a chosen
// partition line ("seg"). Internal nodes hold the partition; leaves hold a
// convex bag of segs that all live in a single sector. The point of the BSP
// at render time is twofold:
//
//   1. findSector(pos) descends the tree once and returns the leaf sector
//      the player is currently standing in — O(depth), no per-tick search.
//   2. traverseBSP(playerPos, visit) yields segs front-to-back, which lets
//      the per-column clip arrays (yTop/yBot) terminate occluded columns
//      without ever needing a depth buffer.

const std = @import("std");
const level = @import("level.zig");
const Vec2 = level.Vec2;
const Seg = level.Seg;

// BSPNode is a tagged union with two variants — exposes pattern matching
// rather than the C++/Go "flag + maybe-valid fields" idiom.
pub const BSPNode = union(enum) {
    leaf: struct {
        segs: []const Seg,
        sector: i32,
    },
    node: struct {
        p_start: Vec2,
        p_delta: Vec2,
        left: *BSPNode,
        right: *BSPNode,
    },
};

// SegSide is the result of testing a single seg against a partition line.
// The straddle variant carries the intersection point as its payload — the
// other three variants have no payload, so we don't pay for it when it's
// not relevant.
pub const SegSide = union(enum) {
    left,      // both endpoints in the left half-space
    right,     // both endpoints in the right half-space
    collinear, // both endpoints lie on the line
    straddle: Vec2, // crosses the line; payload = intersection point
};

// sideOf returns the signed perp-product of (p - p_start) against p_delta.
//   positive → p is to the LEFT of the directed partition,
//   negative → p is to the RIGHT,
//   zero    → on the line.
pub fn sideOf(p: Vec2, p_start: Vec2, p_delta: Vec2) f64 {
    return p_delta.x * (p.y - p_start.y) - p_delta.y * (p.x - p_start.x);
}

// classify tests a seg against a partition line and reports which side it
// falls on. The eps tolerance keeps endpoints that are *exactly* on the
// partition (or within a sliver of it) from being treated as straddles, which
// would cause pointless hairline splits.
pub fn classify(seg: Seg, p_start: Vec2, p_delta: Vec2) SegSide {
    const eps: f64 = 1.0e-4;
    const d1 = sideOf(seg.v1, p_start, p_delta);
    const d2 = sideOf(seg.v2, p_start, p_delta);

    const s1: i8 = if (d1 > eps) 1 else if (d1 < -eps) -1 else 0;
    const s2: i8 = if (d2 > eps) 1 else if (d2 < -eps) -1 else 0;

    if (s1 == 0 and s2 == 0) return .collinear;
    if (s1 >= 0 and s2 >= 0) return .left;
    if (s1 <= 0 and s2 <= 0) return .right;

    // Linear interpolation along the seg to find where d crosses zero.
    const t = d1 / (d1 - d2);
    return .{ .straddle = .{
        .x = seg.v1.x + t * (seg.v2.x - seg.v1.x),
        .y = seg.v1.y + t * (seg.v2.y - seg.v1.y),
    } };
}

// buildBSP recursively constructs a BSP tree from a slice of segs. It runs
// once at startup. Recursion ends in two ways:
//
//   - <= 1 seg left: trivial leaf.
//   - No partition can split the remaining segs into two non-empty sides:
//     the region is convex enough that any further split would just produce
//     a one-sided cut. Stop and store the segs as a leaf.
//
// Partition selection is greedy: every seg is a candidate, scored by
//   |left - right| + 2 * straddles
// because each straddle costs us a seg duplication. Smallest score wins.
pub fn buildBSP(allocator: std.mem.Allocator, segs: []const Seg) !*BSPNode {
    const node = try allocator.create(BSPNode);

    if (segs.len <= 1) {
        const sector: i32 = if (segs.len == 0) 0 else segs[0].front_sector;
        node.* = .{ .leaf = .{
            .segs = try allocator.dupe(Seg, segs),
            .sector = sector,
        } };
        return node;
    }

    // Greedy partition selection.
    var best_idx: ?usize = null;
    var best_score: i32 = std.math.maxInt(i32);

    for (segs, 0..) |cand, i| {
        const p_start = cand.v1;
        const p_delta = Vec2.sub(cand.v2, cand.v1);
        var l: i32 = 0;
        var r: i32 = 0;
        var s: i32 = 0;
        for (segs, 0..) |other, j| {
            if (j == i) continue;
            switch (classify(other, p_start, p_delta)) {
                .left      => l += 1,
                .right     => r += 1,
                .straddle  => s += 1,
                .collinear => {},
            }
        }
        // Reject candidates that don't actually partition (one side empty).
        // This is what causes recursion to terminate in convex regions.
        if (l == 0 or r == 0) continue;
        const diff: i32 = if (l > r) l - r else r - l;
        const score = diff + 2 * s;
        if (score < best_score) {
            best_score = score;
            best_idx = i;
        }
    }

    if (best_idx == null) {
        // Convex enough — every candidate left one side empty.
        node.* = .{ .leaf = .{
            .segs = try allocator.dupe(Seg, segs),
            .sector = segs[0].front_sector,
        } };
        return node;
    }

    const part = segs[best_idx.?];
    const p_start = part.v1;
    const p_delta = Vec2.sub(part.v2, part.v1);

    // The partition seg itself goes on the LEFT (front) side, so traversal
    // emits it before the back side from the player's perspective.
    var left_segs: std.ArrayList(Seg) = .empty;
    defer left_segs.deinit(allocator);
    var right_segs: std.ArrayList(Seg) = .empty;
    defer right_segs.deinit(allocator);

    try left_segs.append(allocator, part);

    for (segs, 0..) |seg, j| {
        if (j == best_idx.?) continue;
        switch (classify(seg, p_start, p_delta)) {
            .left  => try left_segs.append(allocator, seg),
            .right => try right_segs.append(allocator, seg),
            .collinear => {
                // Same direction as partition → front; opposite → back.
                const sd = Vec2.sub(seg.v2, seg.v1);
                if (Vec2.dot(p_delta, sd) >= 0) {
                    try left_segs.append(allocator, seg);
                } else {
                    try right_segs.append(allocator, seg);
                }
            },
            .straddle => |ix| {
                // Cut at the intersection and re-classify each half.
                const a = Seg{
                    .v1 = seg.v1, .v2 = ix,
                    .front_sector = seg.front_sector,
                    .back_sector = seg.back_sector,
                    .linedef_index = seg.linedef_index,
                };
                const b = Seg{
                    .v1 = ix, .v2 = seg.v2,
                    .front_sector = seg.front_sector,
                    .back_sector = seg.back_sector,
                    .linedef_index = seg.linedef_index,
                };
                if (classify(a, p_start, p_delta) == .left) {
                    try left_segs.append(allocator, a);
                } else {
                    try right_segs.append(allocator, a);
                }
                if (classify(b, p_start, p_delta) == .left) {
                    try left_segs.append(allocator, b);
                } else {
                    try right_segs.append(allocator, b);
                }
            },
        }
    }

    node.* = .{ .node = .{
        .p_start = p_start,
        .p_delta = p_delta,
        .left  = try buildBSP(allocator, left_segs.items),
        .right = try buildBSP(allocator, right_segs.items),
    } };
    return node;
}

// findSector descends the tree to the leaf containing pos and returns its
// sector index.
pub fn findSector(pos: Vec2, node: *const BSPNode) i32 {
    return switch (node.*) {
        .leaf => |l| l.sector,
        .node => |n| if (sideOf(pos, n.p_start, n.p_delta) >= 0)
            findSector(pos, n.left)
        else
            findSector(pos, n.right),
    };
}

// traverseBSP walks the tree front-to-back from the player's position and
// invokes `visit` on every seg in order. "Front" depends on which side of
// each partition the player is on.
pub fn traverseBSP(
    node: *const BSPNode,
    player: Vec2,
    ctx: anytype,
    comptime visit: fn (@TypeOf(ctx), Seg) void,
) void {
    switch (node.*) {
        .leaf => |l| {
            for (l.segs) |s| visit(ctx, s);
        },
        .node => |n| {
            if (sideOf(player, n.p_start, n.p_delta) >= 0) {
                traverseBSP(n.left,  player, ctx, visit);
                traverseBSP(n.right, player, ctx, visit);
            } else {
                traverseBSP(n.right, player, ctx, visit);
                traverseBSP(n.left,  player, ctx, visit);
            }
        },
    }
}

#pragma once

// Binary Space Partition — node type, the geometric primitive that classifies
// a seg against a candidate partition line, the tree builder, and the
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

#include <functional>
#include <memory>
#include <vector>
#include "types.hpp"

// BSPNode is either a leaf (segs + sector) or an internal node (partition
// line + left/right children). The `leaf` flag picks which fields are valid.
// Children are owned via unique_ptr so the struct doesn't have an infinite
// recursive size.
struct BSPNode {
    bool leaf = false;

    // Leaf-only.
    std::vector<Seg> segs;
    int sector = 0;

    // Internal-only.
    Vec2 pStart;
    Vec2 pDelta;
    std::unique_ptr<BSPNode> left;
    std::unique_ptr<BSPNode> right;
};

enum class SegSide {
    Left,      // both endpoints in left half-space
    Right,     // both endpoints in right half-space
    Straddle,  // crosses the line — split at intersection
    Collinear, // both endpoints lie on the line
};

// sideOf returns the signed perp-product of (p - pStart) against pDelta.
//   positive → p is to the LEFT of the directed partition,
//   negative → p is to the RIGHT,
//   zero    → on the line.
inline double sideOf(Vec2 p, Vec2 pStart, Vec2 pDelta) {
    return pDelta.x * (p.y - pStart.y) - pDelta.y * (p.x - pStart.x);
}

// classify tests a seg against a partition line and reports which side it
// falls on. For Straddle, *outIntersection (if non-null) receives the
// world-space intersection point so the BSP builder can split the seg there.
SegSide classify(const Seg& seg, Vec2 partStart, Vec2 partDelta,
                 Vec2* outIntersection = nullptr);

// generateSegs flattens the linedef list into the seg list the BSP builder
// will consume. One-sided linedefs produce one seg; two-sided linedefs
// produce two (one per side, with sectors swapped).
std::vector<Seg> generateSegs();

// buildBSP recursively partitions `segs` into a balanced-ish BSP tree.
std::unique_ptr<BSPNode> buildBSP(std::vector<Seg> segs);

// findSector descends the tree to the leaf containing pos and returns its
// sector index.
int findSector(Vec2 pos, const BSPNode& node);

// traverseBSP walks the tree front-to-back from the player's position and
// invokes `visit` on every seg in order. "Front" depends on which side of
// each partition the player is on.
void traverseBSP(const BSPNode& node, Vec2 player,
                 const std::function<void(const Seg&)>& visit);

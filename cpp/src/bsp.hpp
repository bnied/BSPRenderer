#pragma once

// Binary Space Partition — the tree, wrapped as a class.
//
// A BSP recursively splits the map's plane into two half-spaces with a chosen
// partition line ("seg"). Internal nodes hold the partition; leaves hold a
// convex bag of segs that all live in a single sector. The point of the BSP
// at render time is twofold:
//
//   1. findSector(pos) descends the tree once and returns the leaf sector the
//      player is currently standing in — O(depth), no per-tick search.
//   2. traverse(playerPos, visit) yields segs front-to-back, which lets the
//      per-column clip arrays (yTop/yBot) terminate occluded columns without
//      ever needing a depth buffer.
//
// The node representation is an implementation detail: it lives entirely in
// bsp.cpp as an opaque `Bsp::Node` (a variant of leaf / internal). Callers only
// ever touch the two query methods below.

#include <functional>
#include <memory>
#include "types.hpp"

class Level;

class Bsp {
public:
    // Build a balanced-ish BSP over the level's segs. The greedy partition
    // pick tries every candidate seg and scores by side imbalance plus a heavy
    // weight on straddle splits (each split duplicates a seg).
    explicit Bsp(const Level& level);
    ~Bsp();

    Bsp(Bsp&&) noexcept;
    Bsp& operator=(Bsp&&) noexcept;
    Bsp(const Bsp&) = delete;
    Bsp& operator=(const Bsp&) = delete;

    // findSector descends to the leaf containing pos and returns its sector.
    int findSector(Vec2 pos) const;

    // traverse walks the tree front-to-back from the player's position and
    // invokes `visit` on every seg in order. "Front" depends on which side of
    // each partition the player is on.
    void traverse(Vec2 player,
                  const std::function<void(const Seg&)>& visit) const;

    // Node is opaque: forward-declared here, defined only in bsp.cpp.
    struct Node;

private:
    std::unique_ptr<Node> root_;
};

#include "bsp.hpp"
#include "level.hpp"

#include <climits>
#include <cstdlib>

SegSide classify(const Seg& seg, Vec2 partStart, Vec2 partDelta,
                 Vec2* outIntersection) {
    constexpr double eps = 1e-4;
    double d1 = sideOf(seg.v1, partStart, partDelta);
    double d2 = sideOf(seg.v2, partStart, partDelta);

    // Tri-state per endpoint: -1 right, 0 on-line, +1 left.
    int s1 = 0;
    if      (d1 >  eps) s1 =  1;
    else if (d1 < -eps) s1 = -1;
    int s2 = 0;
    if      (d2 >  eps) s2 =  1;
    else if (d2 < -eps) s2 = -1;

    if (s1 == 0 && s2 == 0) return SegSide::Collinear;
    if (s1 >= 0 && s2 >= 0) return SegSide::Left;
    if (s1 <= 0 && s2 <= 0) return SegSide::Right;

    // Linear interpolation along the seg to find where d crosses zero.
    double t = d1 / (d1 - d2);
    if (outIntersection) {
        outIntersection->x = seg.v1.x + t * (seg.v2.x - seg.v1.x);
        outIntersection->y = seg.v1.y + t * (seg.v2.y - seg.v1.y);
    }
    return SegSide::Straddle;
}

std::vector<Seg> generateSegs() {
    std::vector<Seg> out;
    out.reserve(linedefs.size() * 2);
    for (int i = 0; i < static_cast<int>(linedefs.size()); ++i) {
        const auto& l = linedefs[i];
        Vec2 a = vertices[l.v1];
        Vec2 b = vertices[l.v2];
        // Authored direction (front side).
        out.push_back(Seg{a, b, l.frontSector, l.backSector, i});
        // Reverse direction (back side) for two-sided linedefs.
        if (l.backSector != noSector) {
            out.push_back(Seg{b, a, l.backSector, l.frontSector, i});
        }
    }
    return out;
}

std::unique_ptr<BSPNode> buildBSP(std::vector<Seg> segs) {
    auto node = std::make_unique<BSPNode>();

    if (segs.size() <= 1) {
        node->leaf = true;
        node->sector = segs.empty() ? 0 : segs[0].frontSector;
        node->segs = std::move(segs);
        return node;
    }

    // Greedy partition pick: try every seg as a candidate and score by how
    // unbalanced it leaves the two sides plus a heavy 2× weight on straddle
    // splits (each straddle costs us a seg duplication).
    int bestIdx = -1;
    int bestScore = INT_MAX;
    for (int i = 0; i < static_cast<int>(segs.size()); ++i) {
        Vec2 pStart = segs[i].v1;
        Vec2 pDelta = {segs[i].v2.x - segs[i].v1.x, segs[i].v2.y - segs[i].v1.y};
        int l = 0, r = 0, s = 0;
        for (int j = 0; j < static_cast<int>(segs.size()); ++j) {
            if (j == i) continue;
            switch (classify(segs[j], pStart, pDelta)) {
                case SegSide::Left:      ++l; break;
                case SegSide::Right:     ++r; break;
                case SegSide::Straddle:  ++s; break;
                case SegSide::Collinear: break;
            }
        }
        // Reject candidates that don't actually partition (one side empty).
        // This is what causes recursion to terminate in convex regions.
        if (l == 0 || r == 0) continue;
        int score = std::abs(l - r) + 2 * s;
        if (score < bestScore) {
            bestScore = score;
            bestIdx = i;
        }
    }

    if (bestIdx == -1) {
        // Convex enough — every candidate left one side empty.
        node->leaf = true;
        node->sector = segs[0].frontSector;
        node->segs = std::move(segs);
        return node;
    }

    Seg part = segs[bestIdx];
    Vec2 pStart = part.v1;
    Vec2 pDelta = {part.v2.x - part.v1.x, part.v2.y - part.v1.y};

    // Distribute the remaining segs across the two children. The partition
    // seg itself goes on the LEFT (front) side, so traversal emits it before
    // the back side from the player's perspective.
    std::vector<Seg> leftSegs = {part};
    std::vector<Seg> rightSegs;

    for (int j = 0; j < static_cast<int>(segs.size()); ++j) {
        if (j == bestIdx) continue;
        const Seg& seg = segs[j];
        Vec2 ix;
        switch (classify(seg, pStart, pDelta, &ix)) {
            case SegSide::Left:
                leftSegs.push_back(seg);
                break;
            case SegSide::Right:
                rightSegs.push_back(seg);
                break;
            case SegSide::Collinear: {
                // Same direction as partition → front side; opposite → back.
                double sdx = seg.v2.x - seg.v1.x;
                double sdy = seg.v2.y - seg.v1.y;
                if (pDelta.x * sdx + pDelta.y * sdy >= 0) leftSegs.push_back(seg);
                else                                      rightSegs.push_back(seg);
                break;
            }
            case SegSide::Straddle: {
                // Cut the seg in two at the intersection and re-classify
                // each half. Each should now land cleanly on one side.
                Seg a = {seg.v1, ix, seg.frontSector, seg.backSector, seg.lineDefIndex};
                Seg b = {ix, seg.v2, seg.frontSector, seg.backSector, seg.lineDefIndex};
                if (classify(a, pStart, pDelta) == SegSide::Left) leftSegs.push_back(a);
                else                                              rightSegs.push_back(a);
                if (classify(b, pStart, pDelta) == SegSide::Left) leftSegs.push_back(b);
                else                                              rightSegs.push_back(b);
                break;
            }
        }
    }

    node->leaf = false;
    node->pStart = pStart;
    node->pDelta = pDelta;
    node->left  = buildBSP(std::move(leftSegs));
    node->right = buildBSP(std::move(rightSegs));
    return node;
}

int findSector(Vec2 pos, const BSPNode& node) {
    if (node.leaf) return node.sector;
    if (sideOf(pos, node.pStart, node.pDelta) >= 0) return findSector(pos, *node.left);
    return findSector(pos, *node.right);
}

void traverseBSP(const BSPNode& node, Vec2 player,
                 const std::function<void(const Seg&)>& visit) {
    if (node.leaf) {
        for (const auto& s : node.segs) visit(s);
        return;
    }
    if (sideOf(player, node.pStart, node.pDelta) >= 0) {
        traverseBSP(*node.left,  player, visit);
        traverseBSP(*node.right, player, visit);
    } else {
        traverseBSP(*node.right, player, visit);
        traverseBSP(*node.left,  player, visit);
    }
}

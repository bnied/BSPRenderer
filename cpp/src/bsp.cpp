#include "bsp.hpp"
#include "level.hpp"

#include <climits>
#include <cstdlib>
#include <variant>

// Node is a leaf (segs + sector) or an internal node (partition line + two
// children). Modeled as a std::variant so the "which fields are valid" state
// is carried by the active alternative instead of a hand-managed flag.
struct Bsp::Node {
    struct Leaf {
        std::vector<Seg> segs;
        int sector = 0;
    };
    struct Internal {
        Vec2 pStart;
        Vec2 pDelta;
        std::unique_ptr<Node> left;
        std::unique_ptr<Node> right;
    };
    std::variant<Leaf, Internal> kind;
};

namespace {

using Node = Bsp::Node;

// sideOf returns the signed perp-product of (p - pStart) against pDelta.
//   positive → p is to the LEFT of the directed partition,
//   negative → p is to the RIGHT,
//   zero     → on the line.
double sideOf(Vec2 p, Vec2 pStart, Vec2 pDelta) {
    return pDelta.x * (p.y - pStart.y) - pDelta.y * (p.x - pStart.x);
}

enum class SegSide {
    Left,      // both endpoints in left half-space
    Right,     // both endpoints in right half-space
    Straddle,  // crosses the line — split at intersection
    Collinear, // both endpoints lie on the line
};

// classify tests a seg against a partition line and reports which side it
// falls on. For Straddle, *outIntersection (if non-null) receives the
// world-space intersection point so the builder can split the seg there.
SegSide classify(const Seg& seg, Vec2 partStart, Vec2 partDelta,
                 Vec2* outIntersection = nullptr) {
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

// makeLeaf builds a leaf node owning `segs`.
std::unique_ptr<Node> makeLeaf(std::vector<Seg> segs) {
    auto node = std::make_unique<Node>();
    Node::Leaf leaf;
    leaf.sector = segs.empty() ? 0 : segs[0].frontSector;
    leaf.segs = std::move(segs);
    node->kind = std::move(leaf);
    return node;
}

// buildNode recursively partitions `segs` into a balanced-ish BSP tree.
std::unique_ptr<Node> buildNode(std::vector<Seg> segs) {
    if (segs.size() <= 1) return makeLeaf(std::move(segs));

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

    // Convex enough — every candidate left one side empty.
    if (bestIdx == -1) return makeLeaf(std::move(segs));

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

    auto node = std::make_unique<Node>();
    Node::Internal internal;
    internal.pStart = pStart;
    internal.pDelta = pDelta;
    internal.left  = buildNode(std::move(leftSegs));
    internal.right = buildNode(std::move(rightSegs));
    node->kind = std::move(internal);
    return node;
}

int findSectorIn(Vec2 pos, const Node& node) {
    if (const auto* leaf = std::get_if<Node::Leaf>(&node.kind)) {
        return leaf->sector;
    }
    const auto& in = std::get<Node::Internal>(node.kind);
    if (sideOf(pos, in.pStart, in.pDelta) >= 0) return findSectorIn(pos, *in.left);
    return findSectorIn(pos, *in.right);
}

void traverseIn(const Node& node, Vec2 player,
                const std::function<void(const Seg&)>& visit) {
    if (const auto* leaf = std::get_if<Node::Leaf>(&node.kind)) {
        for (const auto& s : leaf->segs) visit(s);
        return;
    }
    const auto& in = std::get<Node::Internal>(node.kind);
    if (sideOf(player, in.pStart, in.pDelta) >= 0) {
        traverseIn(*in.left,  player, visit);
        traverseIn(*in.right, player, visit);
    } else {
        traverseIn(*in.right, player, visit);
        traverseIn(*in.left,  player, visit);
    }
}

} // namespace

Bsp::Bsp(const Level& level) : root_(buildNode(level.generateSegs())) {}
Bsp::~Bsp() = default;
Bsp::Bsp(Bsp&&) noexcept = default;
Bsp& Bsp::operator=(Bsp&&) noexcept = default;

int Bsp::findSector(Vec2 pos) const {
    return findSectorIn(pos, *root_);
}

void Bsp::traverse(Vec2 player,
                   const std::function<void(const Seg&)>& visit) const {
    traverseIn(*root_, player, visit);
}

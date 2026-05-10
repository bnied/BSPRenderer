#include "player.hpp"
#include "level.hpp"

#include <algorithm>
#include <cmath>

Player::Player() = default;

// eyeZ blends two camera-height policies:
//
//   eyeFollowFactor = 1.0  →  eye is rigidly attached to feet. Camera
//                             physically rises and falls the full step
//                             amount, but because feet and eye move
//                             together, the floor stays at a constant
//                             screen distance below the horizon.
//
//   eyeFollowFactor = 0.0  →  fixed-baseline camera. Eye Z never changes;
//                             the floor's screen position reflects the
//                             sector's true Z, so steps up/down are visible
//                             as the floor sliding on screen.
//
// We use 1.0 by default — the camera rises/falls with the player.
double Player::eyeZ() const {
    double feetBaseline = baselineEyeZ - eyeOverFloor;
    return baselineEyeZ + eyeFollowFactor * (feetZ - feetBaseline);
}

namespace {
// Perpendicular distance from p to segment ab, clamped to the endpoints.
double pointSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
    Vec2 ab = b - a;
    double l2 = ab.x * ab.x + ab.y * ab.y;
    if (l2 < 1e-9) return (p - a).length();
    double t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2;
    t = clampD(t, 0.0, 1.0);
    Vec2 proj{a.x + ab.x * t, a.y + ab.y * t};
    return (p - proj).length();
}
}

void Player::update(double dt, const Input& in, const BSPNode& bspRoot) {
    double rot = rotSpeed * dt;
    double mv  = moveSpeed * dt;

    if (in.turnL) angle -= rot;
    if (in.turnR) angle += rot;

    double cosA = std::cos(angle);
    double sinA = std::sin(angle);

    // Compose desired (dx, dy) in world space from the four movement keys.
    // forward = (cosA, sinA); right = (-sinA, cosA).
    double dx = 0, dy = 0;
    if (in.forward) { dx += cosA * mv; dy += sinA * mv; }
    if (in.back)    { dx -= cosA * mv; dy -= sinA * mv; }
    if (in.strafeL) { dx += sinA * mv; dy -= cosA * mv; }
    if (in.strafeR) { dx -= sinA * mv; dy += cosA * mv; }

    // Axis-separated probe so the player slides along walls instead of
    // sticking to them.
    constexpr double radius = 8.0;
    double currentFloorH = sectors[findSector(pos, bspRoot)].floorH;

    Vec2 tryX{pos.x + dx, pos.y};
    if (!collides(tryX, radius, currentFloorH)) pos.x = tryX.x;
    Vec2 tryY{pos.x, pos.y + dy};
    if (!collides(tryY, radius, currentFloorH)) pos.y = tryY.y;

    // Snap feet to the new sector's floor (no gravity / falling).
    feetZ = sectors[findSector(pos, bspRoot)].floorH;
}

// collides returns true if a circle of `radius` centered at `pos` is blocked
// by any linedef:
//   - solid one-sided wall, OR
//   - portal whose opening is too short to walk through, OR
//   - portal whose target floor is more than maxStepUp above us.
bool Player::collides(Vec2 p, double radius, double currentFloorH) const {
    constexpr double maxStepUp = 24.0;
    for (const auto& l : linedefs) {
        Vec2 a = vertices[l.v1];
        Vec2 b = vertices[l.v2];
        if (pointSegmentDistance(p, a, b) >= radius) continue;
        if (l.backSector == noSector) return true;
        const Sector& front = sectors[l.frontSector];
        const Sector& back  = sectors[l.backSector];

        // Portal opening tall enough for the player to fit through?
        double openingTop    = std::min(front.ceilH,  back.ceilH);
        double openingBottom = std::max(front.floorH, back.floorH);
        if (openingTop - openingBottom < eyeOverFloor) return true;

        // Step-up gate: which side is the probe entering?
        double pdx = b.x - a.x;
        double pdy = b.y - a.y;
        double side = pdx * (p.y - a.y) - pdy * (p.x - a.x);
        double targetFloorH = side > 0 ? back.floorH : front.floorH;
        if (targetFloorH - currentFloorH > maxStepUp) return true;
    }
    return false;
}

#pragma once

// Player physics: movement, collision, and the camera-height policy.
//
// The player is a 2-D circle of radius 8 in the (x, y) plane that auto-snaps
// its feet Z to the current sector's floor height. Step-up across portals is
// gated by maxStepUp; portals whose vertical opening is shorter than the
// player's standing height are treated as solid.
//
// Vertical camera motion is interesting: see eyeZ() and eyeFollowFactor.

#include "bsp.hpp"
#include "math.hpp"

class Level;

// Input is the per-tick boolean key state. The SDL layer fills this in from
// the keyboard scancode array; the player has no idea SDL exists.
struct Input {
    bool forward = false;
    bool back    = false;
    bool strafeL = false;
    bool strafeR = false;
    bool turnL   = false;
    bool turnR   = false;
};

class Player {
public:
    Player();

    // eyeZ blends two camera-height policies (see implementation).
    double eyeZ() const;

    // update advances the player by `dt` seconds with the given input state.
    void update(double dt, const Input& in, const Bsp& bsp, const Level& level);

    // Spawn just north of the hub's south wall, facing north — looking
    // straight down the catwalk into the colored staircase chain. The
    // octagonal pillar is behind the player (turn around to discover it).
    Vec2   pos             {120, 50};      // (x, y) world position
    double feetZ           = 0;            // Z of the feet — tracks current sector's floorH
    double angle           = -3.141592653589793 / 2.0; // facing angle in radians (north)
    double fov             = 70.0 * 3.141592653589793 / 180.0;
    double moveSpeed       = 140.0;
    double rotSpeed        = 2.4;
    double eyeOverFloor    = 41.0;         // standing height
    double eyeFollowFactor = 1.0;          // 1 = rigid, 0 = fixed-baseline
    double baselineEyeZ    = 41.0;

private:
    bool collides(Vec2 pos, double radius, double currentFloorH,
                  const Level& level) const;
};

#pragma once

// Level — the map, as an object instead of three loose globals.
//
// A Level owns the hand-authored geometry (vertices, sectors, linedefs) and
// knows how to flatten its linedefs into the renderable seg list the BSP
// consumes. Passing a `const Level&` into the Bsp builder, the Player, and the
// Renderer makes the map dependency explicit and keeps the world out of global
// state — there is no reason two Levels couldn't coexist.
//
// See level.cpp for the ASCII sketch and the actual showcase-map data.

#include <vector>
#include "types.hpp"

class Level {
public:
    // The single hand-authored showcase map. Returns a reference to a stable
    // program-lifetime instance.
    static const Level& showcase();

    const std::vector<Vec2>&    vertices() const { return vertices_; }
    const std::vector<Sector>&  sectors()  const { return sectors_; }
    const std::vector<LineDef>& linedefs() const { return linedefs_; }

    const Sector& sector(int i) const { return sectors_[i]; }
    Vec2          vertex(int i) const { return vertices_[i]; }

    // generateSegs flattens the linedef list into the seg list the BSP builder
    // consumes. One-sided linedefs produce one seg; two-sided linedefs produce
    // two (one per side, with sectors swapped).
    std::vector<Seg> generateSegs() const;

private:
    Level(std::vector<Vec2> vertices, std::vector<Sector> sectors,
          std::vector<LineDef> linedefs);

    std::vector<Vec2>    vertices_;
    std::vector<Sector>  sectors_;
    std::vector<LineDef> linedefs_;
};

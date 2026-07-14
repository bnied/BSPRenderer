#pragma once

// Visplane — DOOM's deferred floor/ceiling rendering primitive.
//
// During the BSP walk, drawSeg never colors a single floor or ceiling pixel.
// Instead, for each screen column it updates a per-sector Visplane with the
// vertical span of that column that belongs to this sector's floor (or
// ceiling). After the BSP walk, renderVisplanes sweeps every visplane and
// rasterizes the spans by inverse-projecting each pixel back to its world
// (X, Y) for procedural texturing and depth shading.
//
// This is what lets several sectors' floors and ceilings composite correctly
// across the screen without a depth buffer: every column has at most one
// floor visplane span and one ceiling visplane span (per sector), tracked
// independently and rasterized once.
//
// The renderer keeps 2 visplanes per sector — index 2*si is the floor and
// index 2*si+1 is the ceiling. Each plane keeps:
//
//   top(x)  — inclusive upper bound of the span at column x (INT_MAX → none)
//   bot(x)  — inclusive lower bound of the span at column x (INT_MIN → none)
//   minX/maxX — range of columns actually touched this frame, so the
//               rasterizer can skip empty columns cheaply.
//
// The coverage buffers and touched-range bookkeeping are private: reset() and
// extend() are the only ways to mutate them, which keeps minX/maxX and the
// top/bot spans in a consistent state by construction.

#include <vector>

class Visplane {
public:
    Visplane(int sectorIndex, bool isCeiling, int width);

    // Wipe coverage at the start of each frame.
    void reset();

    // Grow the span at column x to include [yLo..yHi]. yLo > yHi is a no-op.
    void extend(int x, int yLo, int yHi);

    int  sectorIndex() const { return sectorIndex_; }
    bool isCeiling()   const { return isCeiling_; }
    int  minX() const { return minX_; }
    int  maxX() const { return maxX_; }
    int  top(int x) const { return top_[x]; }
    int  bot(int x) const { return bot_[x]; }

private:
    int sectorIndex_;
    bool isCeiling_;
    std::vector<int> top_;
    std::vector<int> bot_;
    int minX_;
    int maxX_;
};

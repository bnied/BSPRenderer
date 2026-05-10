#include "visplane.hpp"

#include <climits>

Visplane::Visplane(int sectorIndex_, bool isCeiling_, int width)
    : sectorIndex(sectorIndex_),
      isCeiling(isCeiling_),
      top(width),
      bot(width) {
    reset();
}

void Visplane::reset() {
    for (size_t i = 0; i < top.size(); ++i) {
        top[i] = INT_MAX;
        bot[i] = INT_MIN;
    }
    minX = static_cast<int>(top.size());
    maxX = -1;
}

void Visplane::extend(int x, int yLo, int yHi) {
    if (yLo > yHi) return;
    if (yLo < top[x]) top[x] = yLo;
    if (yHi > bot[x]) bot[x] = yHi;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
}

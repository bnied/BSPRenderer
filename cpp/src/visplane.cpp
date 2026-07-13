#include "visplane.hpp"

#include <climits>

Visplane::Visplane(int sectorIndex, bool isCeiling, int width)
    : sectorIndex_(sectorIndex),
      isCeiling_(isCeiling),
      top_(width),
      bot_(width) {
    reset();
}

void Visplane::reset() {
    for (size_t i = 0; i < top_.size(); ++i) {
        top_[i] = INT_MAX;
        bot_[i] = INT_MIN;
    }
    minX_ = static_cast<int>(top_.size());
    maxX_ = -1;
}

void Visplane::extend(int x, int yLo, int yHi) {
    if (yLo > yHi) return;
    if (yLo < top_[x]) top_[x] = yLo;
    if (yHi > bot_[x]) bot_[x] = yHi;
    if (x < minX_) minX_ = x;
    if (x > maxX_) maxX_ = x;
}

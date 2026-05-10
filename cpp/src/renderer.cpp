#include "renderer.hpp"
#include "level.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

// ============================================================================
// Construction & top-level render entry
// ============================================================================

Renderer::Renderer(int width, int height)
    : bufW(width),
      bufH(height),
      pixels(static_cast<size_t>(width) * height * 4),
      yTop(width),
      yBot(width) {
    visplanes.reserve(sectors.size() * 2);
    for (int si = 0; si < static_cast<int>(sectors.size()); ++si) {
        visplanes.emplace_back(si, false, width); // floor at 2*si
        visplanes.emplace_back(si, true,  width); // ceiling at 2*si+1
    }
}

// render() runs one full frame:
//   1. Reset per-column open region and per-frame visplane coverage.
//   2. Background fill (dim ceiling/floor of player's current sector) so any
//      column that ends up unwritten still looks plausible.
//   3. BSP walk → drawSeg for every visible seg, front-to-back.
//   4. Visplane pass → flat floors/ceilings rasterized via inverse projection.
//   5. Overlays: minimap and crosshair.
void Renderer::render(const Player& player, const BSPNode& bspRoot) {
    for (int x = 0; x < bufW; ++x) {
        yTop[x] = 0;
        yBot[x] = bufH - 1;
    }
    for (auto& vp : visplanes) vp.reset();

    int playerSector = findSector(player.pos, bspRoot);
    const Sector& sec = sectors[playerSector];
    double halfW = bufW / 2.0;
    double halfH = bufH / 2.0;
    double horizon = halfH;

    // Background fill — top half = sector ceiling, bottom half = sector
    // floor, both dimmed so legitimate geometry still reads as brighter.
    for (int y = 0; y < bufH; ++y) {
        RGBA c = (y < bufH / 2) ? sec.ceilColor : sec.floorColor;
        RGBA dc = shade(c, 0.55);
        size_t rowStart = static_cast<size_t>(y) * bufW * 4;
        for (int x = 0; x < bufW; ++x) {
            size_t i = rowStart + x * 4;
            pixels[i + 0] = dc.r;
            pixels[i + 1] = dc.g;
            pixels[i + 2] = dc.b;
            pixels[i + 3] = 255;
        }
    }

    // Pinhole camera setup. focal = halfW / tan(fov/2) gives us the standard
    // "screen plane is `focal` units in front of the eye" projection.
    double fovHalfTan = std::tan(player.fov / 2.0);
    double focal = halfW / fovHalfTan;
    double eyeZ = player.eyeZ();
    double cosA = std::cos(player.angle);
    double sinA = std::sin(player.angle);

    auto drawOne = [&](const Seg& seg) {
        drawSeg(seg, player, cosA, sinA, halfW, horizon, fovHalfTan, focal, eyeZ);
    };

    if (slowMode) {
        // Buffered traversal so we can stop after `slowStep` columns.
        std::vector<Seg> segs;
        traverseBSP(bspRoot, player.pos, [&](const Seg& s) { segs.push_back(s); });
        slowColumnBudget = slowStep;
        for (const auto& s : segs) drawOne(s);
        if (slowColumnBudget > 0) slowStep = 0;
        else                      slowStep += 1;
    } else {
        traverseBSP(bspRoot, player.pos, drawOne);
    }

    renderVisplanes(focal, halfW, horizon, player.pos, cosA, sinA, eyeZ);
    drawMinimap(player);
    drawCrosshair();
}

// ============================================================================
// Pixel ops
// ============================================================================

void Renderer::putPixel(int x, int y, RGBA c) {
    if (x < 0 || x >= bufW || y < 0 || y >= bufH) return;
    size_t i = (static_cast<size_t>(y) * bufW + x) * 4;
    pixels[i + 0] = c.r;
    pixels[i + 1] = c.g;
    pixels[i + 2] = c.b;
    pixels[i + 3] = c.a;
}

void Renderer::fillColumn(int x, int yLo, int yHi, RGBA c) {
    if (yLo > yHi) return;
    if (yLo < 0) yLo = 0;
    if (yHi >= bufH) yHi = bufH - 1;
    size_t i = (static_cast<size_t>(yLo) * bufW + x) * 4;
    size_t stride = static_cast<size_t>(bufW) * 4;
    for (int y = yLo; y <= yHi; ++y) {
        pixels[i + 0] = c.r;
        pixels[i + 1] = c.g;
        pixels[i + 2] = c.b;
        pixels[i + 3] = 255;
        i += stride;
    }
}

// ============================================================================
// Per-seg rasterizer — the engine's most complex function.
// ============================================================================
//
// drawSeg, for each visible seg in BSP front-to-back order:
//
//   1. Back-face culls.
//   2. Transforms both endpoints from world space into view space (forward
//      = +d, right = +r).
//   3. Clips against near plane and left/right frustum (each a simple
//      inequality on r ± k*d). If fully outside a plane: return; otherwise
//      slide the bad endpoint to the plane.
//   4. Projects the clipped endpoints to screen X.
//   5. For each screen column from xStart to xEnd:
//        a. Skip columns the column-clip arrays say are fully occluded.
//        b. Linearly interpolate 1/d (perspective-correct) to find depth.
//        c. Compute projected ceiling-Y and floor-Y.
//        d. Above ceiling and below floor: extend the corresponding sector's
//           visplane spans (deferred to renderVisplanes).
//        e. Solid seg: fill the slot with the wall color and mark the
//           column fully occluded.
//        f. Portal seg: draw upper-wall (back ceiling lower than front)
//           and/or lower-wall (back floor higher than front) slivers, then
//           narrow yTop/yBot to the back sector's open range.
//
// Per-column lighting is a simple distance falloff: 1/(1+d*0.004) scaled by
// the front sector's authored light, clamped to a 0.15 floor.
//
void Renderer::drawSeg(const Seg& seg, const Player& player,
                       double cosA, double sinA,
                       double halfW, double horizon,
                       double fovHalfTan, double focal,
                       double eyeZ) {
    // Back-face cull. The seg's outward normal is (-sdy, sdx) — a 90° CCW
    // rotation of the seg's direction. If the player is on the wrong side
    // of that normal, this seg's "front" is facing away from us.
    double sdx = seg.v2.x - seg.v1.x;
    double sdy = seg.v2.y - seg.v1.y;
    double nx  = -sdy;
    double ny  =  sdx;
    double toPx = player.pos.x - seg.v1.x;
    double toPy = player.pos.y - seg.v1.y;
    if (nx * toPx + ny * toPy <= 0) return;

    // World → view space. With the player at the origin facing along the +x
    // view axis, an offset (dx, dy) in world maps to:
    //   r = -dx*sinA + dy*cosA   (right axis)
    //   d =  dx*cosA + dy*sinA   (forward axis)
    double rx1 = seg.v1.x - player.pos.x;
    double ry1 = seg.v1.y - player.pos.y;
    double rx2 = seg.v2.x - player.pos.x;
    double ry2 = seg.v2.y - player.pos.y;
    double r1 = -rx1 * sinA + ry1 * cosA;
    double d1 =  rx1 * cosA + ry1 * sinA;
    double r2 = -rx2 * sinA + ry2 * cosA;
    double d2 =  rx2 * cosA + ry2 * sinA;

    // Near-plane clip. Anything entirely behind d=near disappears; otherwise
    // the offending endpoint slides forward along the seg until d == near.
    constexpr double near = 1.0;
    if (d1 < near && d2 < near) return;
    if (d1 < near) {
        double t = (near - d1) / (d2 - d1);
        r1 = r1 + t * (r2 - r1);
        d1 = near;
    } else if (d2 < near) {
        double t = (near - d2) / (d1 - d2);
        r2 = r2 + t * (r1 - r2);
        d2 = near;
    }

    // Left frustum (r + k*d >= 0).
    double k = fovHalfTan;
    double lD1 = r1 + k * d1;
    double lD2 = r2 + k * d2;
    if (lD1 < 0 && lD2 < 0) return;
    if (lD1 < 0) {
        double t = lD1 / (lD1 - lD2);
        r1 = r1 + t * (r2 - r1);
        d1 = d1 + t * (d2 - d1);
    } else if (lD2 < 0) {
        double t = lD2 / (lD2 - lD1);
        r2 = r2 + t * (r1 - r2);
        d2 = d2 + t * (d1 - d2);
    }

    // Right frustum (k*d - r >= 0).
    double rD1 = k * d1 - r1;
    double rD2 = k * d2 - r2;
    if (rD1 < 0 && rD2 < 0) return;
    if (rD1 < 0) {
        double t = rD1 / (rD1 - rD2);
        r1 = r1 + t * (r2 - r1);
        d1 = d1 + t * (d2 - d1);
    } else if (rD2 < 0) {
        double t = rD2 / (rD2 - rD1);
        r2 = r2 + t * (r1 - r2);
        d2 = d2 + t * (d1 - d2);
    }

    // Pinhole projection to screen X. After culling and clipping we know
    // d > 0 for both endpoints. Reject zero-width slivers.
    double sx1 = halfW + (r1 / d1) * focal;
    double sx2 = halfW + (r2 / d2) * focal;
    if (sx2 <= sx1 + 0.0001) return;

    int xStart = static_cast<int>(std::ceil(sx1));
    if (xStart < 0) xStart = 0;
    int xEnd = static_cast<int>(std::floor(sx2));
    if (xEnd > bufW - 1) xEnd = bufW - 1;
    if (xStart > xEnd) return;

    // Wall heights are stored as world Z; what matters for projection is the
    // signed distance from the eye, so we precompute (sectorZ - eyeZ).
    const Sector& front = sectors[seg.frontSector];
    double fCeil  = front.ceilH  - eyeZ;
    double fFloor = front.floorH - eyeZ;
    double bCeil = 0, bFloor = 0;
    if (seg.backSector != noSector) {
        const Sector& back = sectors[seg.backSector];
        bCeil  = back.ceilH  - eyeZ;
        bFloor = back.floorH - eyeZ;
    }

    const LineDef& lineDef = linedefs[seg.lineDefIndex];
    double frontLight = front.light;

    // Perspective-correct interpolation: linear in 1/d across screen X, not
    // in d itself.
    //   y = horizon - (sectorZ - eyeZ) * focal * (1/d)
    // is linear in 1/d for a fixed sectorZ, so one interpolation per column
    // is enough.
    double invD1 = 1.0 / d1;
    double invD2 = 1.0 / d2;
    double dx = sx2 - sx1;

    for (int x = xStart; x <= xEnd; ++x) {
        if (slowMode) {
            if (slowColumnBudget <= 0) return;
            slowColumnBudget--;
        }
        if (yTop[x] > yBot[x]) continue;
        double tLin = (static_cast<double>(x) - sx1) / dx;
        double invD = (1.0 - tLin) * invD1 + tLin * invD2;
        double depth = 1.0 / invD;

        double falloff = 1.0 / (1.0 + depth * 0.004);
        double light = clampD(frontLight * falloff, 0.15, 1.0);

        int ceilY  = static_cast<int>(std::lround(horizon - fCeil  * focal * invD));
        int floorY = static_cast<int>(std::lround(horizon - fFloor * focal * invD));

        int top = yTop[x];
        int bot = yBot[x];

        // Ceiling visplane span.
        if (ceilY > top) {
            int yLo = top;
            int yHi = ceilY - 1;
            if (yHi > bot) yHi = bot;
            visplanes[seg.frontSector * 2 + 1].extend(x, yLo, yHi);
        }
        // Floor visplane span.
        if (floorY < bot) {
            int yLo = floorY + 1;
            if (yLo < top) yLo = top;
            int yHi = bot;
            visplanes[seg.frontSector * 2].extend(x, yLo, yHi);
        }

        if (seg.backSector == noSector) {
            // Solid wall.
            int yLo = ceilY;  if (yLo < top) yLo = top;
            int yHi = floorY; if (yHi > bot) yHi = bot;
            fillColumn(x, yLo, yHi, shade(lineDef.wallColor, light));
            yTop[x] = bot + 1; // mark fully occluded
        } else {
            int backCeilY  = static_cast<int>(std::lround(horizon - bCeil  * focal * invD));
            int backFloorY = static_cast<int>(std::lround(horizon - bFloor * focal * invD));

            // Upper wall (back ceiling lower than front).
            int newTop = (ceilY < top) ? top : ceilY;
            if (backCeilY > ceilY) {
                int yLo = ceilY;        if (yLo < top) yLo = top;
                int yHi = backCeilY - 1; if (yHi > bot) yHi = bot;
                fillColumn(x, yLo, yHi, shade(lineDef.upperColor, light));
                newTop = (backCeilY < top) ? top : backCeilY;
            }

            // Lower wall (back floor higher than front).
            int newBot = (floorY > bot) ? bot : floorY;
            if (backFloorY < floorY) {
                int yLo = backFloorY + 1; if (yLo < top) yLo = top;
                int yHi = floorY;         if (yHi > bot) yHi = bot;
                fillColumn(x, yLo, yHi, shade(lineDef.lowerColor, light));
                newBot = (backFloorY > bot) ? bot : backFloorY;
            }

            yTop[x] = newTop;
            yBot[x] = newBot;
            if (yTop[x] > yBot[x]) yTop[x] = yBot[x] + 1;
        }
    }
}

// ============================================================================
// Visplane pass
// ============================================================================

void Renderer::renderVisplanes(double focal, double halfW, double horizon,
                               Vec2 playerPos, double cosA, double sinA,
                               double eyeZ) {
    for (auto& plane : visplanes) {
        if (plane.maxX < plane.minX) continue;
        const Sector& sec = sectors[plane.sectorIndex];
        double planeZ = plane.isCeiling ? sec.ceilH : sec.floorH;
        RGBA color    = plane.isCeiling ? sec.ceilColor : sec.floorColor;
        double planeHeight = planeZ - eyeZ; // signed

        for (int x = plane.minX; x <= plane.maxX; ++x) {
            int yLo = plane.top[x];
            int yHi = plane.bot[x];
            if (yLo > yHi) continue;
            fillPlaneColumn(x, yLo, yHi,
                            planeHeight, focal, halfW, horizon,
                            playerPos, cosA, sinA,
                            sec.light, color);
        }
    }
}

// fillPlaneColumn rasterizes a vertical strip of one floor/ceiling. The plane
// is horizontal in world space — every pixel in the strip belongs to the
// same world Z. For each screen pixel we inverse-project to the world (X, Y)
// it represents, sample a procedural 16-unit checkerboard there, and apply
// distance-based shading.
void Renderer::fillPlaneColumn(int x, int yLo, int yHi,
                               double planeHeight,
                               double focal, double halfW, double horizon,
                               Vec2 playerPos, double cosA, double sinA,
                               double sectorLight, RGBA color) {
    if (yLo > yHi) return;

    double absH = std::fabs(planeHeight);
    double xOffset = static_cast<double>(x) - halfW;

    // Precompute the dark-tile color once per column.
    RGBA darkColor{
        static_cast<std::uint8_t>(color.r * 0.7),
        static_cast<std::uint8_t>(color.g * 0.7),
        static_cast<std::uint8_t>(color.b * 0.7),
        255,
    };

    // Tile size = 1 << tileBits world units. tileBias keeps the integer
    // world coordinates positive so the parity test (tx ^ ty) & 1 is stable
    // across the origin.
    constexpr int tileBits = 4;
    constexpr int tileBias = 1 << 20;

    size_t i = (static_cast<size_t>(yLo) * bufW + x) * 4;
    size_t stride = static_cast<size_t>(bufW) * 4;

    for (int y = yLo; y <= yHi; ++y) {
        // The projected screen-y of a horizontal plane at signed height h is
        //   sy = horizon - h * focal / depth
        // Solve for depth:
        //   depth = |h| * focal / |sy - horizon|
        double absDy = std::fabs(static_cast<double>(y) - horizon);
        double depth = (absDy > 0.0001) ? (absH * focal / absDy) : 1e9;

        // View-space right offset for this pixel at this depth.
        double right = xOffset * depth / focal;

        // Rotate from camera space (forward, right) into world space.
        // forward = (cosA, sinA); right axis = (-sinA, cosA).
        double wx = playerPos.x + depth * cosA - right * sinA;
        double wy = playerPos.y + depth * sinA + right * cosA;

        // Checkerboard sample.
        int tx = (static_cast<int>(wx) + tileBias) >> tileBits;
        int ty = (static_cast<int>(wy) + tileBias) >> tileBits;
        RGBA base = ((tx ^ ty) & 1) == 0 ? color : darkColor;

        // Distance fog and per-sector light, with a floor so distant pixels
        // don't go pitch black. The 0.9 desaturates floors a touch relative
        // to walls so they read as lit-from-above ground.
        double falloff = 1.0 / (1.0 + depth * 0.004);
        double light = clampD(sectorLight * falloff, 0.15, 1.0);
        RGBA c = shade(base, light * 0.9);

        pixels[i + 0] = c.r;
        pixels[i + 1] = c.g;
        pixels[i + 2] = c.b;
        pixels[i + 3] = 255;
        i += stride;
    }
}

// ============================================================================
// Overlays
// ============================================================================

void Renderer::drawCrosshair() {
    int cx = bufW / 2, cy = bufH / 2;
    RGBA col{255, 255, 255, 255};
    for (int d = -3; d <= 3; ++d) {
        if (d == 0) continue;
        putPixel(cx + d, cy, col);
        putPixel(cx, cy + d, col);
    }
}

// drawMinimap draws a top-down preview of the level into the upper-left
// corner: dark backdrop, all linedefs (one-sided in their wall color, two-
// sided in gray), and a player marker with a heading line.
void Renderer::drawMinimap(const Player& player) {
    double minX =  std::numeric_limits<double>::infinity();
    double minY =  std::numeric_limits<double>::infinity();
    double maxX = -std::numeric_limits<double>::infinity();
    double maxY = -std::numeric_limits<double>::infinity();
    for (const auto& v : vertices) {
        if (v.x < minX) minX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.x > maxX) maxX = v.x;
        if (v.y > maxY) maxY = v.y;
    }
    constexpr double pad  = 8.0;
    constexpr double boxW = 120.0;
    constexpr double boxH = 100.0;
    constexpr double ox   = 8.0;
    constexpr double oy   = 8.0;
    double sx = boxW / (maxX - minX + 2 * pad);
    double sy = boxH / (maxY - minY + 2 * pad);
    double s  = std::min(sx, sy);

    auto project = [&](Vec2 v) {
        return std::pair<int, int>{
            static_cast<int>(ox + ((v.x - minX) + pad) * s),
            static_cast<int>(oy + ((v.y - minY) + pad) * s),
        };
    };

    // Backdrop.
    for (int y = static_cast<int>(oy - 2); y <= static_cast<int>(oy + boxH + 2); ++y) {
        for (int x = static_cast<int>(ox - 2); x <= static_cast<int>(ox + boxW + 2); ++x) {
            putPixel(x, y, RGBA{10, 10, 14, 255});
        }
    }

    // Linedefs — two-sided in gray, one-sided in their wall color.
    for (const auto& l : linedefs) {
        auto [ax, ay] = project(vertices[l.v1]);
        auto [bx, by] = project(vertices[l.v2]);
        RGBA col = (l.backSector == noSector) ? l.wallColor : RGBA{120, 120, 120, 255};
        drawLine(ax, ay, bx, by, col);
    }

    // Player marker + heading line.
    auto [pxI, pyI] = project(player.pos);
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            putPixel(pxI + dx, pyI + dy, RGBA{255, 255, 255, 255});
        }
    }
    int hx = pxI + static_cast<int>(std::cos(player.angle) * 10);
    int hy = pyI + static_cast<int>(std::sin(player.angle) * 10);
    drawLine(pxI, pyI, hx, hy, RGBA{255, 255, 255, 255});
}

// Standard integer Bresenham, with bounds-checked plotting via putPixel.
void Renderer::drawLine(int x0, int y0, int x1, int y1, RGBA color) {
    int dx = std::abs(x1 - x0);
    int sx = (x0 < x1) ? 1 : -1;
    int dy = -std::abs(y1 - y0);
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;
    while (true) {
        putPixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) return;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

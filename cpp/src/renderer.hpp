#pragma once

// Renderer — the software renderer.
//
//   pixels        — RGBA framebuffer in row-major order (4 bytes/pixel,
//                   no padding). The SDL layer hands this directly to a
//                   streaming SDL_Texture each frame.
//   yTop / yBot   — DOOM's ceilingclip / floorclip arrays. For each screen
//                   column they bound the still-open vertical range. Solid
//                   walls close their columns entirely; portals shrink the
//                   open range by their upper/lower walls.
//   visplanes     — 2 entries per sector (floor at 2*si, ceiling at 2*si+1).
//                   See visplane.hpp.
//   slowMode etc. — debug aid: when enabled (Tab), each frame draws one more
//                   column than the previous one, so you can watch the BSP
//                   walk emit columns front-to-back.

#include <cstdint>
#include <vector>
#include "bsp.hpp"
#include "math.hpp"
#include "player.hpp"
#include "visplane.hpp"

class Level;

class Renderer {
public:
    Renderer(int width, int height, const Level& level);

    // Run one full frame: reset, BSP walk, visplane pass, overlays.
    void render(const Player& player, const Bsp& bsp);

    int width()  const { return bufW; }
    int height() const { return bufH; }
    const std::uint8_t* pixelData() const { return pixels.data(); }

    bool slowMode = false;

private:
    // ---- per-seg rasterizer (the heart of the renderer) ----
    void drawSeg(const Seg& seg, const Player& player,
                 double cosA, double sinA,
                 double halfW, double horizon,
                 double fovHalfTan, double focal,
                 double eyeZ);

    // ---- visplane pass ----
    void renderVisplanes(double focal, double halfW, double horizon,
                         Vec2 playerPos, double cosA, double sinA, double eyeZ);

    void fillPlaneColumn(int x, int yLo, int yHi,
                         double planeHeight,
                         double focal, double halfW, double horizon,
                         Vec2 playerPos, double cosA, double sinA,
                         double sectorLight, RGBA color);

    // ---- pixel ops ----
    void putPixel(int x, int y, RGBA c);
    void fillColumn(int x, int yLo, int yHi, RGBA c);

    // ---- overlays ----
    void drawCrosshair();
    void drawMinimap(const Player& player);
    void drawLine(int x0, int y0, int x1, int y1, RGBA color);

    const Level& level;
    int bufW;
    int bufH;
    std::vector<std::uint8_t> pixels;
    std::vector<int> yTop;
    std::vector<int> yBot;
    std::vector<Visplane> visplanes;

    int slowStep = 0;
    int slowColumnBudget = 0;
};

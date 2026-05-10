#pragma once

// Math primitives shared across the engine: a 2-D vector, an 8-bit-per-channel
// color, and a couple of small helpers.
//
// Everything in the world is 2-D-with-heights: positions and movement live in
// (x, y) — see Vec2 — and floors/ceilings have a separate scalar Z stored on
// each Sector. There is no full 3-D vector type because we never need one;
// all the perspective math operates on screen columns whose vertical extent
// is computed from a Z difference and a depth.

#include <cmath>
#include <cstdint>

struct Vec2 {
    double x = 0;
    double y = 0;

    Vec2 operator+(Vec2 o) const { return {x + o.x, y + o.y}; }
    Vec2 operator-(Vec2 o) const { return {x - o.x, y - o.y}; }
    Vec2 operator*(double s) const { return {x * s, y * s}; }
    double length() const { return std::sqrt(x * x + y * y); }
};

// RGBA is the in-memory pixel format of the framebuffer. We hand SDL a buffer
// of these via SDL_PIXELFORMAT_RGBA32, so byte order is fixed: R, G, B, A.
struct RGBA {
    std::uint8_t r = 0, g = 0, b = 0, a = 255;
};

// shade multiplies a color's RGB channels by a brightness factor `f`, clamped
// to [0.12, 1.0]. The 0.12 floor keeps far geometry from going pure black,
// which would make portals look like holes in the screen.
inline RGBA shade(RGBA c, double f) {
    double k = f < 0.12 ? 0.12 : (f > 1.0 ? 1.0 : f);
    return {
        static_cast<std::uint8_t>(c.r * k),
        static_cast<std::uint8_t>(c.g * k),
        static_cast<std::uint8_t>(c.b * k),
        255,
    };
}

inline double clampD(double x, double lo, double hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}

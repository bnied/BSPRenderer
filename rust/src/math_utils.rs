//! Math primitives shared across the engine: a 2-D vector, an 8-bit-per-channel
//! color, and a couple of small helpers.
//!
//! Everything in the world is 2-D-with-heights: positions and movement live in
//! (x, y) — see [`Vec2`] — and floors/ceilings have a separate scalar Z stored
//! on each Sector. There is no full 3-D vector type because we never need one;
//! all the perspective math operates on screen columns whose vertical extent
//! is computed from a Z difference and a depth.

#[derive(Clone, Copy, Debug, Default)]
pub struct Vec2 {
    pub x: f64,
    pub y: f64,
}

impl Vec2 {
    pub const fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }

    pub fn sub(self, o: Vec2) -> Vec2 {
        Vec2::new(self.x - o.x, self.y - o.y)
    }

    pub fn length(self) -> f64 {
        (self.x * self.x + self.y * self.y).sqrt()
    }
}

/// In-memory pixel format of the framebuffer (matches the `[u8]` row-major
/// RGBA layout that `pixels` expects). Stored straight rather than premultiplied
/// — [`shade`] scales the channels for distance/light.
#[derive(Clone, Copy, Debug)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba {
    pub const fn new(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }
}

/// Multiply an RGB triple by brightness factor `f`, clamped to [0.12, 1.0].
/// The 0.12 floor keeps far-away geometry from going pure black, which would
/// make portals look like holes in the screen.
pub fn shade(c: Rgba, f: f64) -> Rgba {
    let k = f.max(0.12).min(1.0);
    Rgba::new(
        (c.r as f64 * k) as u8,
        (c.g as f64 * k) as u8,
        (c.b as f64 * k) as u8,
        255,
    )
}

pub fn clamp_f(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { lo } else if x > hi { hi } else { x }
}

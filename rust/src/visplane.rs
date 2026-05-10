//! Visplane — DOOM's deferred floor/ceiling rendering primitive.
//!
//! During the BSP walk, `draw_seg` never colors a single floor or ceiling
//! pixel. Instead, for each screen column it updates a per-sector
//! [`Visplane`] with the vertical span of that column that belongs to this
//! sector's floor (or ceiling). After the BSP walk, the visplane sweep
//! rasterizes the spans by inverse-projecting each pixel back to its world
//! (X, Y) for procedural texturing and depth shading.
//!
//! This is what lets several sectors' floors and ceilings composite correctly
//! across the screen without a depth buffer: every column has at most one
//! floor visplane span and one ceiling visplane span (per sector), tracked
//! independently and rasterized once.
//!
//! Per renderer there are 2 visplanes per sector — index `2*si` is the floor
//! and `2*si+1` is the ceiling. Each plane keeps:
//!
//!   - `top[x]` — inclusive upper bound of the span at column x (huge → none)
//!   - `bot[x]` — inclusive lower bound of the span at column x (-huge → none)
//!   - `min_x` / `max_x` — range of columns actually touched this frame, so
//!                        the rasterizer can skip empty columns cheaply.

/// "No span yet at this column" sentinels. We use ordinary (non-extreme)
/// integers so a per-frame `fill` is a fast memset rather than touching
/// every i32::MIN/MAX path.
pub const TOP_EMPTY: i32 = 1 << 30;
pub const BOT_EMPTY: i32 = -(1 << 30);

#[derive(Debug)]
pub struct Visplane {
    pub sector_index: usize,
    pub is_ceiling: bool,
    pub top: Vec<i32>,
    pub bot: Vec<i32>,
    pub min_x: i32,
    pub max_x: i32,
}

impl Visplane {
    pub fn new(sector_index: usize, is_ceiling: bool, width: usize) -> Self {
        let mut v = Self {
            sector_index,
            is_ceiling,
            top: vec![TOP_EMPTY; width],
            bot: vec![BOT_EMPTY; width],
            min_x: width as i32,
            max_x: -1,
        };
        v.reset();
        v
    }

    /// Wipe coverage at the start of each frame.
    pub fn reset(&mut self) {
        self.top.fill(TOP_EMPTY);
        self.bot.fill(BOT_EMPTY);
        self.min_x = self.top.len() as i32;
        self.max_x = -1;
    }

    /// Grow the span at column `x` to include `[y_lo..y_hi]`. The `y_lo > y_hi`
    /// no-op is the easy way to write "I might have nothing to add this column".
    pub fn extend(&mut self, x: i32, y_lo: i32, y_hi: i32) {
        if y_lo > y_hi {
            return;
        }
        let xi = x as usize;
        if y_lo < self.top[xi] {
            self.top[xi] = y_lo;
        }
        if y_hi > self.bot[xi] {
            self.bot[xi] = y_hi;
        }
        if x < self.min_x {
            self.min_x = x;
        }
        if x > self.max_x {
            self.max_x = x;
        }
    }
}

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

/// The coverage buffers (`top`/`bot`) and the touched-range bookkeeping
/// (`min_x`/`max_x`) are private: [`Visplane::reset`] and [`Visplane::extend`]
/// are the only ways to mutate them, which keeps `min_x`/`max_x` and the
/// `top`/`bot` spans consistent by construction. Read access is via the
/// accessors below.
#[derive(Debug)]
pub struct Visplane {
    sector_index: usize,
    is_ceiling: bool,
    top: Vec<i32>,
    bot: Vec<i32>,
    min_x: i32,
    max_x: i32,
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

    /// The inclusive column range `[min_x, max_x]` this plane received coverage
    /// on this frame, or `None` if it was never touched.
    pub fn covered(&self) -> Option<(i32, i32)> {
        (self.max_x >= self.min_x).then_some((self.min_x, self.max_x))
    }

    /// The `(top, bot)` span at column `x`. Only meaningful for columns inside
    /// [`Visplane::covered`]; elsewhere it returns the empty sentinels.
    pub fn span_at(&self, x: usize) -> (i32, i32) {
        (self.top[x], self.bot[x])
    }

    pub fn sector_index(&self) -> usize {
        self.sector_index
    }

    pub fn is_ceiling(&self) -> bool {
        self.is_ceiling
    }
}

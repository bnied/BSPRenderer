// Visplane — DOOM's deferred floor/ceiling rendering primitive.
//
// During the BSP walk, drawSeg never colors a single floor or ceiling pixel.
// Instead, for each screen column it updates a per-sector Visplane with the
// vertical span of that column that belongs to this sector's floor (or
// ceiling). After the BSP walk, renderVisplanes sweeps every visplane and
// rasterizes the spans by inverse-projecting each pixel back to its world
// (X, Y) for procedural texturing and depth shading.
//
// The renderer keeps 2 visplanes per sector — index 2*si is the floor and
// index 2*si+1 is the ceiling. Each plane keeps:
//
//   top[x]  — inclusive upper bound of the span at column x (maxInt → none)
//   bot[x]  — inclusive lower bound of the span at column x (minInt → none)
//   min_x/max_x — range of columns actually touched this frame, so the
//                 rasterizer can skip empty columns cheaply.

const std = @import("std");

pub const Visplane = struct {
    sector_index: i32,
    is_ceiling: bool,
    top: []i32,
    bot: []i32,
    min_x: i32,
    max_x: i32,

    pub fn init(allocator: std.mem.Allocator, sector_index: i32, is_ceiling: bool, width: usize) !Visplane {
        const top = try allocator.alloc(i32, width);
        const bot = try allocator.alloc(i32, width);
        var v = Visplane{
            .sector_index = sector_index,
            .is_ceiling = is_ceiling,
            .top = top,
            .bot = bot,
            .min_x = 0,
            .max_x = -1,
        };
        v.reset();
        return v;
    }

    pub fn deinit(self: *Visplane, allocator: std.mem.Allocator) void {
        allocator.free(self.top);
        allocator.free(self.bot);
    }

    // Wipe coverage at the start of each frame.
    pub fn reset(self: *Visplane) void {
        @memset(self.top, std.math.maxInt(i32));
        @memset(self.bot, std.math.minInt(i32));
        self.min_x = @intCast(self.top.len);
        self.max_x = -1;
    }

    // Grow the span at column x to include [y_lo..y_hi]. y_lo > y_hi is a no-op.
    pub fn extend(self: *Visplane, x: i32, y_lo: i32, y_hi: i32) void {
        if (y_lo > y_hi) return;
        const ux: usize = @intCast(x);
        if (y_lo < self.top[ux]) self.top[ux] = y_lo;
        if (y_hi > self.bot[ux]) self.bot[ux] = y_hi;
        if (x < self.min_x) self.min_x = x;
        if (x > self.max_x) self.max_x = x;
    }
};

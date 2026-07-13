// BSPRenderer — DOOM-style software renderer (Zig port).
//
// Architecture mirrors the Swift / C++ / Go / Python / Rust ports — same
// pipeline, same hand-authored map, same controls. See `../README.md` for
// the high-level overview.
//
// What this port does differently from its siblings:
//
//   - The seg list is computed at *compile time* (see level.zig). The other
//     ports call generateSegs() at startup; here the result lives in .rodata.
//
//   - Tagged unions (BSPNode, SegSide) replace the "flag + maybe-valid
//     fields" pattern used in C++/Go/Rust.
//
//   - The BSP tree is allocated into a single ArenaAllocator that's freed
//     in one shot at shutdown, instead of per-node smart-pointer ownership.
//
//   - Manual event loop. SDL3's callback-main convention is C-flavored;
//     a plain `pub fn main` matches Zig's grain better.

const std = @import("std");
const level = @import("level.zig");
const bsp = @import("bsp.zig");
const player_mod = @import("player.zig");
const renderer_mod = @import("renderer.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const internal_w: c_int = 480;
const internal_h: c_int = 300;
const window_w:   c_int = 960;
const window_h:   c_int = 600;

pub fn main() !void {
    // Arena allocator for the BSP. Built once, freed in one shot.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const bsp_alloc = arena.allocator();

    // Separate GPA for everything else so leaks in renderer code surface
    // distinctly from the BSP arena.
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ---- SDL init ----
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return error.SDLInit;
    }
    defer c.SDL_Quit();

    var window: ?*c.SDL_Window = null;
    var sdl_renderer: ?*c.SDL_Renderer = null;
    if (!c.SDL_CreateWindowAndRenderer(
        "BSP Renderer (Zig) — WASD / arrows, Tab = slow mode, Esc to quit",
        window_w, window_h,
        c.SDL_WINDOW_RESIZABLE,
        &window, &sdl_renderer,
    )) {
        std.log.err("CreateWindowAndRenderer failed: {s}", .{c.SDL_GetError()});
        return error.SDLCreateWindow;
    }
    defer c.SDL_DestroyRenderer(sdl_renderer);
    defer c.SDL_DestroyWindow(window);

    _ = c.SDL_SetRenderVSync(sdl_renderer, 1);

    // Logical presentation gives a fixed internal resolution that SDL upscales
    // to the window with integer scaling.
    _ = c.SDL_SetRenderLogicalPresentation(
        sdl_renderer,
        internal_w, internal_h,
        c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
    );

    const texture = c.SDL_CreateTexture(
        sdl_renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STREAMING,
        internal_w, internal_h,
    ) orelse {
        std.log.err("CreateTexture failed: {s}", .{c.SDL_GetError()});
        return error.SDLCreateTexture;
    };
    defer c.SDL_DestroyTexture(texture);
    _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

    // ---- Build the world ----
    const lvl = &level.showcase;
    var player: player_mod.Player = .{};
    var renderer = try renderer_mod.Renderer.init(allocator, lvl, internal_w, internal_h);
    defer renderer.deinit();
    const bsp_root = try bsp.buildBSP(bsp_alloc, lvl.segs);

    // ---- Main loop ----
    var last_tick_ns: u64 = c.SDL_GetTicksNS();
    var running = true;
    while (running) {
        // Drain events.
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE) running = false;
                    if (event.key.key == c.SDLK_TAB)    renderer.slow_mode = !renderer.slow_mode;
                },
                else => {},
            }
        }

        // Wall-clock dt, capped so a huge stall doesn't teleport the player
        // through walls on the next frame.
        const now_ns: u64 = c.SDL_GetTicksNS();
        var dt: f64 = @as(f64, @floatFromInt(now_ns - last_tick_ns)) / 1.0e9;
        if (dt > 0.05) dt = 0.05;
        last_tick_ns = now_ns;

        // Translate SDL keyboard state into our agnostic Input struct.
        var num_keys: c_int = 0;
        const keys = c.SDL_GetKeyboardState(&num_keys);
        const in: player_mod.Input = .{
            .forward  = keys[c.SDL_SCANCODE_W] or keys[c.SDL_SCANCODE_UP],
            .back     = keys[c.SDL_SCANCODE_S] or keys[c.SDL_SCANCODE_DOWN],
            .strafe_l = keys[c.SDL_SCANCODE_A],
            .strafe_r = keys[c.SDL_SCANCODE_D],
            .turn_l   = keys[c.SDL_SCANCODE_LEFT],
            .turn_r   = keys[c.SDL_SCANCODE_RIGHT],
        };

        player.update(dt, in, lvl, bsp_root);
        renderer.render(&player, bsp_root);

        // Push our RGBA buffer into the streaming texture.
        _ = c.SDL_UpdateTexture(texture, null, renderer.pixelData(), renderer.buf_w * 4);

        _ = c.SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(sdl_renderer);
        _ = c.SDL_RenderTexture(sdl_renderer, texture, null, null);

        // HUD overlay using SDL3's built-in 8×8 debug font.
        const si: usize = @intCast(bsp.findSector(player.pos, bsp_root));
        const sec = lvl.sectors[si];
        var hud_buf: [160]u8 = undefined;
        const hud = try std.fmt.bufPrintZ(&hud_buf,
            "sector {d}   floor {d}   ceil {d}   feetZ {d}   eyeZ {d}{s}",
            .{
                si,
                @as(i32, @intFromFloat(sec.floor_h)),
                @as(i32, @intFromFloat(sec.ceil_h)),
                @as(i32, @intFromFloat(player.feet_z)),
                @as(i32, @intFromFloat(player.eyeZ())),
                if (renderer.slow_mode) "   [SLOW]" else "",
            },
        );

        // Dim backdrop behind the text so it stays legible over any scene.
        const text_w_pix: f32 = @floatFromInt(hud.len * 8);
        var bg: c.SDL_FRect = .{ .x = 2.0, .y = 2.0, .w = text_w_pix + 6.0, .h = 12.0 };
        _ = c.SDL_SetRenderDrawBlendMode(sdl_renderer, c.SDL_BLENDMODE_BLEND);
        _ = c.SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 140);
        _ = c.SDL_RenderFillRect(sdl_renderer, &bg);
        _ = c.SDL_SetRenderDrawColor(sdl_renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderDebugText(sdl_renderer, 4, 4, hud.ptr);

        _ = c.SDL_RenderPresent(sdl_renderer);
    }
}

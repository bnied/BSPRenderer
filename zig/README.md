# BSP Renderer (Zig)

A DOOM-style software renderer written in Zig with [SDL3](https://www.libsdl.org/). Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is a Zig port of the original [Swift/AppKit version](../swift/), and a sibling of the [C++](../cpp/), [Go](../go/), [Python](../python/), and [Rust](../rust/) ports. The architecture is identical across all six.

## Build and run

Requires Zig 0.16+ and SDL3:

```
brew install zig sdl3
```

Then from this directory:

```
zig build run
```

`zig build` alone produces `zig-out/bin/bsprenderer`; `zig build run` builds and launches; `rm -rf zig-out .zig-cache` for a clean.

## Controls

| Key | Action |
|-----|--------|
| `W` / `↑` | Forward |
| `S` / `↓` | Backward |
| `A` / `D` | Strafe left / right |
| `←` / `→` | Turn |
| `Tab` | Toggle slow-render mode (watch the BSP walk emit columns) |
| `Esc` | Quit |

## Architecture

One executable target, six modules in `src/`:

| File | Purpose |
|------|---------|
| `main.zig` | SDL3 init, event loop, input wiring, HUD |
| `renderer.zig` | BSP-driven software renderer + RGBA streaming-texture blit |
| `bsp.zig` | BSP tree builder, seg classifier, traversal |
| `player.zig` | Position, angle, movement, collision |
| `level.zig` | `Vec2` / `RGBA` / `Sector` / `LineDef` / `Seg` types, hand-authored map, **comptime seg generation** |
| `visplane.zig` | Per-sector deferred floor/ceiling coverage primitive |

### What this port does differently from its siblings

The renderer pipeline is identical. The interesting deltas are language-specific:

- **Comptime seg generation.** `level.zig` computes the seg list at compile time inside a `comptime` block — the other ports call `generateSegs()` at startup, but here the result lives in `.rodata` and there's no runtime initialization for that data. Look for `pub const segs: []const Seg = blk: { ... };` at the bottom of `level.zig`.

- **Tagged unions for `BSPNode` and `SegSide`.** The C++/Go/Rust ports use a "flag + maybe-valid fields" struct for `BSPNode`. Zig's `union(enum)` makes that a real algebraic type, and `switch` with payload capture (`.straddle => |ix| ...`) replaces the `outIntersection` out-parameter pattern.

- **Arena allocator for the BSP.** The tree is built once at startup into a `std.heap.ArenaAllocator` and freed in one shot at shutdown. No per-node ownership, no `unique_ptr`/`Box`/`Rc`.

- **Explicit allocator threading.** `buildBSP`, `Renderer.init`, and `Visplane.init` all take an `std.mem.Allocator` parameter. There is no hidden global allocator.

### Rendering pipeline

Same six stages as every other port:

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `buildBSP` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverseBSP` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `y_top[x]` / `y_bot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded.

### SDL3 integration

- `@cImport({ @cInclude("SDL3/SDL.h"); })` pulls the SDL3 headers directly into Zig; no binding crate, no FFI wrapper module.
- Plain `pub fn main` with a hand-rolled `SDL_PollEvent` loop, instead of SDL3's `SDL_MAIN_USE_CALLBACKS` convention used by the C++ port — the callback-main model is C-flavored, and a manual loop matches Zig's grain better.
- Internal 480×300 RGBA buffer pushed each frame to a streaming `SDL_Texture` via `SDL_UpdateTexture`, then upscaled to the window with `SDL_LOGICAL_PRESENTATION_INTEGER_SCALE` + `SDL_SCALEMODE_NEAREST`.
- HUD uses SDL3's built-in 8×8 debug font (`SDL_RenderDebugText`).

### Current level

Twelve sectors with varied floor and ceiling heights, an octagonal pillar in the hub, a sunken pit, a four-step colored staircase climbing to an overlook, a diagonal corridor leading to an arena with an attached alcove.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.
- macOS-focused build path (hardcoded `/opt/homebrew` include/lib paths in `build.zig`). On Linux, drop those `addIncludePath` / `addLibraryPath` calls and let `linkSystemLibrary("SDL3")` find SDL3 via `pkg-config`.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

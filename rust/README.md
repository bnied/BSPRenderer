# BSP Renderer (Rust)

A DOOM-style software renderer written in Rust with [winit](https://github.com/rust-windowing/winit) + the [pixels](https://github.com/parasyte/pixels) crate. Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is a Rust port of the original [Swift/AppKit version](../swift/), and a sibling of the [C++ port](../cpp/), [Go port](../go/), and [Python port](../python/). The architecture is identical across all five.

## Build and run

Requires Rust 1.85+ (edition 2024). From this directory:

```
cargo run --release
```

`--release` matters: the debug build is several times slower, and the per-column work in `draw_seg` / `fill_plane_column` is what determines the frame rate.

Cargo will fetch and compile the `pixels` and `winit` dependency trees on first build (~15 seconds on a fast machine because `wgpu` is in there).

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

One binary target, eight source files in `src/`. Rust prefers all methods on a single `impl` block, so the renderer's five Go files (`renderer*.go`) collapse into one `renderer.rs`.

| File | Purpose |
|------|---------|
| `main.rs` | winit `ApplicationHandler` impl: window creation, event loop, input routing, framebuffer blit |
| `renderer.rs` | BSP-driven software renderer (seg raster + visplane pass + overlays + HUD) |
| `bsp.rs` | BSP tree builder, seg classifier, traversal — `BspNode` is a tagged enum (`Leaf` / `Branch`) |
| `player.rs` | Position, angle, movement, collision |
| `level.rs` | Hand-authored map: vertices, sectors, linedefs, all as `pub static` arrays |
| `visplane.rs` | Per-sector deferred floor/ceiling coverage primitive |
| `font.rs` | Hand-authored 5x7 bitmap font for the HUD (the other ports get free framework text rendering — `pixels` doesn't, so we bake one) |
| `geometry.rs` | `Sector` / `LineDef` / `Seg` types |
| `math_utils.rs` | `Vec2`, `Rgba`, `shade`, `clamp_f` |

### Rendering pipeline

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `build_bsp` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverse_bsp` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `y_top[x]` / `y_bot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded.

### Rust-specific notes

- **Borrow-checker around the BSP visitor.** `traverse_bsp` takes a `&mut FnMut(&Seg)`. Calling `Renderer::draw_seg` from inside that closure would conflict with the renderer's `&mut self`. The Rust port resolves this the same way the Go port handles its `slow_mode` path: collect segs into a reusable `frame_segs: Vec<Seg>` first, then iterate. Same allocation cost across frames since the buffer is reused.
- **Window lifetime + `Pixels<'static>` transmute.** `pixels::Pixels` borrows from a `SurfaceTexture`, which borrows from a `Window`. Rust can't represent that self-reference directly inside a struct, so the window is wrapped in an `Arc` and the pixels' lifetime is `transmute`d to `'static`. To keep this sound, **field declaration order matters**: `pixels` must be declared before `window` in `App` so Rust drops it first.
- **Static map data.** Vertices, sectors, and linedefs are `pub static [T; N]` arrays with `const fn` constructors, so the entire map is baked into the binary's data segment with no init-time work.

### Current level

Five sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

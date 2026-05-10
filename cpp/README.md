# BSP Renderer (C++)

A DOOM-style software renderer written in C++20 with [SDL3](https://www.libsdl.org/). Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is a C++ port of the original [Swift/AppKit version](../swift/), and a sibling of the [Go port](../go/) and [Python port](../python/). The architecture is identical across all four.

## Build and run

Requires SDL3 and `pkg-config`:

```
brew install sdl3 pkg-config
```

Then from this directory:

```
make run
```

`make` alone builds the `bsprenderer` binary; `make run` builds and launches it; `make clean` removes binaries and intermediate `.o` / `.d` files.

Built with `clang++ -std=c++20 -O2`.

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

One executable target, six translation units in `src/`:

| File | Purpose |
|------|---------|
| `main.cpp` | SDL3 callback entry points (`SDL_AppInit` / `SDL_AppIterate` / etc.), input routing, HUD |
| `renderer.{cpp,hpp}` | BSP-driven software renderer + RGBA streaming-texture blit |
| `bsp.{cpp,hpp}` | BSP tree builder, seg classifier, traversal |
| `player.{cpp,hpp}` | Position, angle, movement, collision |
| `level.{cpp,hpp}` | `Sector` / `LineDef` / `Seg` types + the hand-authored map |
| `visplane.{cpp,hpp}` | Per-sector deferred floor/ceiling coverage primitive |
| `math.hpp`, `types.hpp` | `Vec2`, `RGBA`, helpers; geometry types |

### Rendering pipeline

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `buildBSP` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverseBSP` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `yTop[x]` / `yBot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded.

### SDL3 specifics

- Uses the new **callback main model** (`SDL_MAIN_USE_CALLBACKS`): no manual event loop, SDL drives `SDL_AppInit` / `SDL_AppIterate` / `SDL_AppEvent` / `SDL_AppQuit`.
- Internal 480×300 RGBA buffer is pushed each frame to a streaming `SDL_Texture` via `SDL_UpdateTexture`, then upscaled to the window with `SDL_LOGICAL_PRESENTATION_INTEGER_SCALE` + `SDL_SCALEMODE_NEAREST` for the chunky-pixel look.
- HUD uses SDL3's built-in 8×8 debug font (`SDL_RenderDebugText`).

### Current level

Five sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

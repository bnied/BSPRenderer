# BSP Renderer (Python)

A DOOM-style software renderer written in Python with [pygame-ce](https://pyga.me/) and [numpy](https://numpy.org/). Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is a Python port of the original [Swift/AppKit version](../swift/), and a sibling of the [C++ port](../cpp/), [Go port](../go/), and [Rust port](../rust/). The architecture is identical across all five.

## Build and run

Uses [uv](https://docs.astral.sh/uv/) for dependency management.

```
uv run python main.py
```

`uv` will create a `.venv/`, install pygame-ce + numpy, and launch.

Requires Python 3.13+.

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

One executable, eight source files. The Go port spreads its renderer across five files (`renderer*.go`); Python doesn't support splitting a class across files, so all renderer methods live in a single `renderer.py`.

| File | Purpose |
|------|---------|
| `main.py` | pygame-ce window, event loop, input routing, framebuffer blit, HUD |
| `renderer.py` | BSP-driven software renderer (seg raster + visplane pass + overlays) |
| `bsp.py` | BSP tree builder, seg classifier, traversal |
| `player.py` | Position, angle, movement, collision |
| `level.py` | Hand-authored map: vertices, sectors, linedefs |
| `visplane.py` | Per-sector floor/ceiling deferred-coverage primitive |
| `geometry.py` | `Sector` / `LineDef` / `Seg` dataclasses (named to avoid shadowing stdlib `types`) |
| `math_utils.py` | `Vec2`, `RGBA`, `shade`, `clamp_f` |

### Rendering pipeline

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `build_bsp` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverse_bsp` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `y_top[x]` / `y_bot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded. **The per-column inner loop is vectorized over rows with numpy** — pure-Python per-pixel work would run at <5 FPS; numpy keeps the engine playable.

### Performance notes

The framebuffer is a `(H, W, 4)` numpy uint8 array, wrapped each frame as a pygame `Surface` via `pygame.image.frombuffer` (no copy) and upscaled with nearest-neighbor to the 960×600 window.

The main vectorization win is `_fill_plane_column` — per-pixel inverse projection, checkerboard sampling, and shading all happen as numpy array operations across a column's row range. Per-seg rasterization (`_draw_seg`) keeps a plain Python per-column loop; each column does cheap O(1) work outside the column-fill (which is itself a numpy slice assignment).

### Current level

Five sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.
- Slower than the Go and C++ ports — Python per-column overhead dominates at 480×300. Acceptable but not 60-FPS-tight.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

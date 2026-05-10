# BSP Renderer (Go)

A DOOM-style software renderer written in Go with [Ebitengine](https://ebitengine.org/) (Ebiten v2). Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is a Go port of the original [Swift/AppKit version](../swift/), and a sibling of the [C++ port](../cpp/) and [Python port](../python/). The architecture is identical across all four.

## Build and run

Requires Go 1.24+. From this directory:

```
go run .
```

To produce a standalone binary:

```
go build -o BSPRenderer
./BSPRenderer
```

Ebiten dependencies are pulled automatically from `go.mod` on first build.

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

One executable target, with the renderer split across five files (the same way the rest of the engine is organized — Go lets methods on the same struct live in different files of the same package).

| File | Purpose |
|------|---------|
| `main.go` | Ebiten `Game` impl: `Update` + `Draw` + `Layout`, input routing, HUD |
| `renderer.go` | Per-frame state + frame entry point + small pixel helpers |
| `renderer_seg.go` | `drawSeg` — the per-seg rasterizer (cull / clip / project / per-column 1/d) |
| `renderer_visplanes.go` | Visplane sweep after the BSP walk |
| `renderer_fill.go` | `fillPlaneColumn` — per-pixel inverse projection + checkerboard + shade |
| `renderer_overlays.go` | Minimap and crosshair |
| `bsp_build.go` | BSP tree construction (greedy partition selection) |
| `bsp_side.go` | Side classification + the `BSPNode` type |
| `bsp_traverse.go` | `generateSegs`, `findSector`, `traverseBSP` |
| `player.go` | Position, angle, movement, collision |
| `level.go` | Hand-authored map: vertices, sectors, linedefs |
| `visplane.go` | Per-sector deferred floor/ceiling coverage primitive |
| `types.go` | `Sector` / `LineDef` / `Seg` |
| `math.go` | `Vec2`, `RGBA`, `shade`, `clampF` |

### Rendering pipeline

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `buildBSP` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverseBSP` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `yTop[x]` / `yBot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded.

### Ebiten specifics

- The renderer fills a `[]uint8` RGBA buffer of shape (480 × 300 × 4); each frame it's handed to the `*ebiten.Image` screen via `WritePixels`.
- `Layout` returns a fixed (480, 300) regardless of window size, so Ebiten always upscales with nearest-neighbor to whatever the window is currently sized to (defaulting to 960×600).
- HUD uses `ebitenutil.DebugPrintAt` (Ebiten's bitmap font).

### Current level

Five sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

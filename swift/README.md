# BSP Renderer (Swift)

A DOOM-style software renderer written in Swift / AppKit. Runs as a macOS executable. Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a visplane system.

This is the original version. See also the [C++ port](../cpp/), [Go port](../go/), [Python port](../python/), and [Rust port](../rust/) — same engine, same level, same controls, four other languages.

## Build and run

```
swift run
```

Requires Swift 5.9+ and macOS 12+.

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

One executable target, seven source files:

| File | Purpose |
|------|---------|
| `main.swift` | `AppDelegate` + bootstrap |
| `GameView.swift` | `NSView` shell, game loop, input routing |
| `Renderer.swift` | BSP-driven software renderer + `CGImage` blit |
| `BSP.swift` | BSP tree builder, seg classifier, traversal |
| `Player.swift` | Position, angle, movement, collision |
| `Level.swift` | `Sector` / `LineDef` / `Seg` types + the hand-authored map |
| `Math.swift` | `Vec2`, `RGBA`, `shade` |

### Rendering pipeline

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, `buildBSP` recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back traversal.** `traverseBSP` walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** For each seg: back-face cull, view-space transform, near + left + right frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `yTop[x]` / `yBot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** During traversal, floor and ceiling spans are accumulated per sector into `Visplane` structs instead of being drawn immediately. After the BSP walk, each visplane scanline is inverse-projected to world coordinates, checkerboard-sampled, and depth-shaded. This lets multiple sectors' floors and ceilings composite correctly without double-drawing.

### Current level

Five sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination. See the ASCII sketch at the top of `Level.swift`.

### Known limitations

- No textures — walls are solid colors; floors and ceilings use a procedural checkerboard.
- No sprites, no enemies, no doors-that-open, no sound.

## License

[GNU General Public License v2](../LICENSE) — the same license the original DOOM source code is released under.

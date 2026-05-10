# BSPRenderer

A DOOM-style software renderer, ported to five languages. Walls render with flat colors and distance-shaded per-column light falloff; floors and ceilings use perspective-correct inverse-projected checkerboard via a [visplane](https://doomwiki.org/wiki/Visplane) system. Same engine, same hand-authored level, same controls — five implementations of the same architecture, side by side.

## Ports

| Language | Path | Library / framework | Build & run |
|----------|------|---------------------|-------------|
| Swift    | [`swift/`](swift/)   | AppKit (`NSView` + `CGImage`)   | `cd swift && swift run` |
| C++      | [`cpp/`](cpp/)       | SDL3 (callback main + streaming texture) | `cd cpp && make run` |
| Go       | [`go/`](go/)         | Ebitengine v2                   | `cd go && go run .` |
| Python   | [`python/`](python/) | pygame-ce (SDL2) + numpy        | `cd python && uv run main.py` |
| Rust     | [`rust/`](rust/)     | winit + pixels (wgpu under the hood) | `cd rust && cargo run --release` |

Each port has its own README with build prerequisites, file layout, and notes on language/library specifics. The Swift version is the original; the other four are line-for-line ports of the same architecture.

## Controls (every port)

| Key | Action |
|-----|--------|
| `W` / `↑` | Forward |
| `S` / `↓` | Backward |
| `A` / `D` | Strafe left / right |
| `←` / `→` | Turn |
| `Tab` | Toggle slow-render mode (watch the BSP walk emit columns) |
| `Esc` | Quit |

## Architecture (every port)

The same six-stage pipeline regardless of language:

1. **Level → segs.** Each one-sided linedef produces one seg; each two-sided linedef produces two segs (one per side, with the back sector tracked for portal handling).
2. **BSP build.** At startup, the BSP builder recursively selects a partition that keeps both sides populated and minimizes straddle splits; straddling segs are split at the intersection. Leaves are subsectors.
3. **Front-to-back BSP traversal.** Per frame, walks the tree from the player's side outward, handing segs to the renderer in near-to-far order.
4. **Per-seg rasterization.** Back-face cull, view-space transform, near + L + R frustum clip, screen-X projection, then per-column rendering with perspective-correct `1/d` interpolation.
5. **Per-column clip.** `yTop[x]` / `yBot[x]` arrays act as DOOM's `ceilingclip` / `floorclip` — each seg narrows the open region for its columns, so no depth buffer is needed. Solid walls mark columns fully occluded; two-sided segs open portals bounded by the back sector's floor and ceiling projections, with upper / lower walls drawn where sector heights differ.
6. **Visplane pass.** Floor and ceiling spans are accumulated per sector into `Visplane` structs during the BSP walk, then rasterized after by inverse-projecting each pixel back to its world (X, Y), sampling a procedural checkerboard, and depth-shading.

The level itself is identical across all five ports: 5 sectors with varied floor and ceiling heights, two pairs of non-axis-aligned walls (a diagonal corridor and a trapezoidal south chamber), four two-sided portals that exercise every upper/lower-wall combination.

## Why five?

Started in Swift on macOS for fun. The other four ports translate that engine into idiomatic forms in each language without changing any behavior, which makes them an interesting reference for what a software-rendered 2.5-D engine looks like across:

- a value-typed, retain-counted, native-compiled language (Swift, the original)
- a manual-memory, low-level systems language (C++)
- a GC'd systems language designed for fast compilation (Go)
- a slow-but-vectorized scripting language (Python + numpy for the hot floor/ceiling loop)
- a borrow-checked, native-compiled systems language (Rust)

The Swift / C++ / Go / Rust versions hit 60 FPS comfortably; the Python port lands around 30–45 FPS at 480×300 because per-column work in pure Python dominates even with numpy-vectorized inner loops.

## Repo layout

```
BSPRenderer/
├── README.md     ← you are here
├── LICENSE       ← GPLv2, applies to all five ports
├── .gitignore    ← covers all five languages' build artifacts
├── swift/
├── cpp/
├── go/
├── python/
└── rust/
```

## License

[GNU General Public License v2](LICENSE) — the same license the original DOOM source code is released under.

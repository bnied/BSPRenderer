"""BSPRenderer — DOOM-style software renderer (Python port).

This is a Python port of a Swift/AppKit project, mirroring the structure of
the existing Go and C++ ports. The architecture is unchanged:

  1. Level definition (level.py) — hand-authored vertices, sectors, and
     linedefs. Each two-sided linedef is a portal between two sectors.

  2. Seg generation + BSP build (bsp.py) — every linedef becomes one or two
     segs (one for one-sided walls, two for portals). The BSP is built once
     at startup by recursively choosing a partition seg that keeps both
     subspaces populated and minimizes straddle splits.

  3. Per-frame BSP traversal (bsp.py) — front-to-back walk from the player's
     side, handing each seg to the renderer.

  4. Per-seg rasterization (renderer.py::_draw_seg) — back-face cull,
     view-space transform, near + L + R frustum clipping, screen-x
     projection, then per-column 1/d interpolation. y_top/y_bot per-column
     arrays serve as DOOM's ceilingclip/floorclip — solid walls fully
     occlude, two-sided portals narrow the open region. Floor/ceiling pixels
     are NOT drawn here; instead, spans are recorded into per-sector
     visplanes.

  5. Visplane pass (renderer.py::_render_visplanes + _fill_plane_column) —
     after the BSP walk, every visplane that received coverage is rasterized
     by inverse-projecting each pixel back to its world (X, Y), sampling a
     procedural checkerboard, and depth-shading.

  6. Overlays (renderer.py::_draw_minimap + _draw_crosshair) — minimap and
     crosshair.

Windowing/input/blit is handled by pygame-ce (SDL2). Internal resolution is
480x300; we upscale with nearest-neighbor (chunky pixel) to the 960x600 window.
"""

from __future__ import annotations

import sys
import time

import pygame

from bsp import build_bsp, find_sector, generate_segs
from level import sectors
from player import Input, Player
from renderer import Renderer

INTERNAL_W = 480
INTERNAL_H = 300
WINDOW_W = 960
WINDOW_H = 600


def main() -> None:
    pygame.init()
    pygame.display.set_caption(
        "BSP Renderer (Python) — WASD / arrows, Tab = slow mode, Esc to quit"
    )
    screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("menlo,monaco,consolas,monospace", 14)

    player = Player()
    renderer = Renderer(INTERNAL_W, INTERNAL_H)
    bsp_root = build_bsp(generate_segs())

    last = time.perf_counter()
    running = True
    while running:
        now = time.perf_counter()
        dt = now - last
        if dt > 0.05:  # clamp huge dt's (e.g. after a window stall)
            dt = 0.05
        last = now

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key == pygame.K_TAB:
                    renderer.slow_mode = not renderer.slow_mode

        keys = pygame.key.get_pressed()
        in_ = Input(
            forward=keys[pygame.K_w] or keys[pygame.K_UP],
            back=keys[pygame.K_s] or keys[pygame.K_DOWN],
            strafe_l=keys[pygame.K_a],
            strafe_r=keys[pygame.K_d],
            turn_l=keys[pygame.K_LEFT],
            turn_r=keys[pygame.K_RIGHT],
        )

        player.update(dt, in_, bsp_root)
        renderer.render(player, bsp_root)

        # Wrap the numpy buffer in a pygame Surface and upscale to the window.
        # frombuffer reads (H, W, 4) row-major RGBA — matches our pixel layout.
        # transform.scale returns a fresh surface each frame; pre-allocating a
        # destination doesn't work because frombuffer's RGBA surface format
        # doesn't match SRCALPHA-flag surfaces (different byte ordering).
        frame = pygame.image.frombuffer(renderer.pixels, (INTERNAL_W, INTERNAL_H), "RGBA")
        upscaled = pygame.transform.scale(frame, (WINDOW_W, WINDOW_H))
        screen.blit(upscaled, (0, 0))

        # HUD: dim backdrop + sector / height / slow-mode info.
        si = find_sector(player.pos, bsp_root)
        s = sectors[si]
        slow_tag = "   [SLOW]" if renderer.slow_mode else ""
        fps = clock.get_fps()
        hud = (f"sector {si}   floor {int(s.floor_h):+d}   ceil {int(s.ceil_h):+d}"
               f"   feetZ {int(player.feet_z):+d}   eyeZ {int(player.eye_z()):+d}"
               f"   {fps:.0f} fps{slow_tag}")
        text = font.render(hud, True, (230, 230, 230))
        backdrop = pygame.Surface((text.get_width() + 12, text.get_height() + 8))
        backdrop.set_alpha(140)
        backdrop.fill((0, 0, 0))
        screen.blit(backdrop, (4, 4))
        screen.blit(text, (10, 8))

        pygame.display.flip()
        clock.tick(60)

    pygame.quit()
    sys.exit(0)


if __name__ == "__main__":
    main()

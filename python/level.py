"""Hand-authored map.

Sectors (12):
  0  hub          floor   0, ceil  80, warm tan
  1  (vestigial)  floor  80, ceil  80               — unreferenced; the
                                                     octagonal pillar walls
                                                     are one-sided. Kept to
                                                     avoid renumbering.
  2  catwalk      floor  20, ceil  88, deep green   — first step above hub
  3  pit          floor -20, ceil  50, violet     — 20 deep so you can climb back out
  4  corridor     floor   4, ceil  72, blue
  5  arena        floor  16, ceil 100, deep red
  6  stair 1      floor  30, ceil  88, orange
  7  stair 2      floor  40, ceil  90, gold
  8  stair 3      floor  50, ceil  92, lime
  9  stair 4      floor  60, ceil  94, cyan
 10  overlook     floor  70, ceil 130, bright cool  — top of staircase
 11  alcove       floor  30, ceil 110, magenta      — east of arena
"""

from math_utils import RGBA, Vec2
from geometry import NO_SECTOR, LineDef, Sector

vertices: list[Vec2] = [
    # Hub perimeter
    Vec2(0, 0),       # 0  hub NW
    Vec2(80, 0),      # 1  hub N opening west (catwalk entry)
    Vec2(160, 0),     # 2  hub N opening east
    Vec2(240, 0),     # 3  hub NE
    Vec2(240, 80),    # 4  hub E opening N (corridor entry)
    Vec2(240, 160),   # 5  hub E opening S
    Vec2(240, 240),   # 6  hub SE
    Vec2(160, 240),   # 7  hub S opening east (pit entry)
    Vec2(80, 240),    # 8  hub S opening west
    Vec2(0, 240),     # 9  hub SW
    # Octagonal pillar diagonals (cardinals at 38..41).
    Vec2(99, 99),     # 10 pillar NW
    Vec2(141, 99),    # 11 pillar NE
    Vec2(141, 141),   # 12 pillar SE
    Vec2(99, 141),    # 13 pillar SW
    # Catwalk
    Vec2(80, -80),    # 14 catwalk NW (= stair 1 SW)
    Vec2(160, -80),   # 15 catwalk NE (= stair 1 SE)
    # Pit (trapezoid widening southward)
    Vec2(60, 320),    # 16 pit SW
    Vec2(180, 320),   # 17 pit SE
    # Corridor + arena (corridor walls are diagonal)
    Vec2(340, 60),    # 18 corridor NE / arena NW
    Vec2(340, 180),   # 19 corridor SE / arena SW
    Vec2(440, 60),    # 20 arena NE
    Vec2(440, 180),   # 21 arena SE
    # Staircase
    Vec2(80, -130),   # 22 stair 1 NW (= stair 2 SW)
    Vec2(160, -130),  # 23 stair 1 NE
    Vec2(80, -180),   # 24 stair 2 NW
    Vec2(160, -180),  # 25 stair 2 NE
    Vec2(80, -230),   # 26 stair 3 NW
    Vec2(160, -230),  # 27 stair 3 NE
    Vec2(80, -280),   # 28 stair 4 NW (= overlook S middle west)
    Vec2(160, -280),  # 29 stair 4 NE
    # Overlook (wider than the stair shaft)
    Vec2(20, -280),   # 30 overlook SW
    Vec2(220, -280),  # 31 overlook SE
    Vec2(20, -380),   # 32 overlook NW
    Vec2(220, -380),  # 33 overlook NE
    # Arena east-wall split + alcove
    Vec2(440, 100),   # 34 arena E split N / alcove SW
    Vec2(440, 140),   # 35 arena E split S / alcove NW
    Vec2(540, 100),   # 36 alcove SE
    Vec2(540, 140),   # 37 alcove NE
    # Octagonal pillar cardinal vertices (diagonals at 10..13).
    Vec2(120, 90),    # 38 pillar N
    Vec2(150, 120),   # 39 pillar E
    Vec2(120, 150),   # 40 pillar S
    Vec2(90, 120),    # 41 pillar W
]

main_wall = RGBA(158, 144, 115, 255)
main_upper = RGBA(110, 105, 92, 255)
main_lower = RGBA(118, 96, 72, 255)
pillar_wall = RGBA(210, 215, 225, 255)
catwalk_wall = RGBA(108, 170, 82, 255)
pit_wall = RGBA(140, 100, 180, 255)
corr_wall = RGBA(94, 134, 200, 255)
arena_wall = RGBA(196, 90, 62, 255)
arena_upper = RGBA(140, 70, 50, 255)
arena_lower = RGBA(220, 130, 90, 255)
stair1_wall = RGBA(210, 130, 70, 255)
stair2_wall = RGBA(220, 180, 80, 255)
stair3_wall = RGBA(140, 210, 90, 255)
stair4_wall = RGBA(90, 190, 220, 255)
overlook_wall = RGBA(210, 220, 235, 255)
alcove_wall = RGBA(220, 140, 190, 255)

sectors: list[Sector] = [
    # 0: Hub.
    Sector(floor_h=0, ceil_h=80,
           floor_color=RGBA(82, 76, 60, 255),
           ceil_color=RGBA(50, 56, 70, 255),
           light=0.85),
    # 1: Vestigial (was pillar interior).
    Sector(floor_h=80, ceil_h=80,
           floor_color=RGBA(40, 40, 45, 255),
           ceil_color=RGBA(40, 40, 45, 255),
           light=0.5),
    # 2: Catwalk — green raised platform.
    Sector(floor_h=20, ceil_h=88,
           floor_color=RGBA(50, 78, 50, 255),
           ceil_color=RGBA(35, 55, 40, 255),
           light=0.95),
    # 3: Pit — sunken violet. Floor at -20 (not deeper) because
    # max_step_up = 24, so anything deeper would trap the player in the pit.
    Sector(floor_h=-20, ceil_h=50,
           floor_color=RGBA(60, 40, 90, 255),
           ceil_color=RGBA(40, 28, 60, 255),
           light=0.65),
    # 4: East corridor — slight step up.
    Sector(floor_h=4, ceil_h=72,
           floor_color=RGBA(48, 62, 96, 255),
           ceil_color=RGBA(34, 46, 78, 255),
           light=0.82),
    # 5: Arena — deep red, taller ceiling.
    Sector(floor_h=16, ceil_h=100,
           floor_color=RGBA(112, 62, 46, 255),
           ceil_color=RGBA(72, 44, 34, 255),
           light=0.95),
    # 6: Stair 1 — orange.
    Sector(floor_h=30, ceil_h=88,
           floor_color=RGBA(170, 110, 70, 255),
           ceil_color=RGBA(120, 70, 40, 255),
           light=0.88),
    # 7: Stair 2 — gold.
    Sector(floor_h=40, ceil_h=90,
           floor_color=RGBA(200, 170, 70, 255),
           ceil_color=RGBA(150, 120, 40, 255),
           light=0.90),
    # 8: Stair 3 — lime.
    Sector(floor_h=50, ceil_h=92,
           floor_color=RGBA(130, 200, 80, 255),
           ceil_color=RGBA(80, 150, 50, 255),
           light=0.92),
    # 9: Stair 4 — cyan.
    Sector(floor_h=60, ceil_h=94,
           floor_color=RGBA(80, 180, 200, 255),
           ceil_color=RGBA(40, 130, 160, 255),
           light=0.94),
    # 10: Overlook — bright cool, much taller ceiling.
    Sector(floor_h=70, ceil_h=130,
           floor_color=RGBA(200, 210, 230, 255),
           ceil_color=RGBA(140, 160, 200, 255),
           light=1.0),
    # 11: Arena alcove — magenta.
    Sector(floor_h=30, ceil_h=110,
           floor_color=RGBA(210, 130, 180, 255),
           ceil_color=RGBA(160, 80, 130, 255),
           light=0.85),
]

linedefs: list[LineDef] = [
    # ---- Hub perimeter (front = 0) ----
    LineDef(0, 1, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(1, 2, 0, 2, main_wall, main_upper, catwalk_wall),       # → catwalk
    LineDef(2, 3, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(3, 4, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(4, 5, 0, 4, main_wall, corr_wall, corr_wall),           # → corridor
    LineDef(5, 6, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(6, 7, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(7, 8, 0, 3, main_wall, pit_wall, main_lower),           # → pit
    LineDef(8, 9, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(9, 0, 0, NO_SECTOR, main_wall, main_upper, main_lower),

    # ---- Octagonal pillar (one-sided, 8 facets, CW math) ----
    LineDef(38, 10, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(10, 41, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(41, 13, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(13, 40, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(40, 12, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(12, 39, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(39, 11, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),
    LineDef(11, 38, 0, NO_SECTOR, pillar_wall, pillar_wall, pillar_wall),

    # ---- Catwalk (front = 2). N wall is a portal to stair 1. ----
    LineDef(1, 14, 2, NO_SECTOR, catwalk_wall, catwalk_wall, catwalk_wall),
    LineDef(14, 15, 2, 6, catwalk_wall, catwalk_wall, stair1_wall),  # → stair 1
    LineDef(15, 2, 2, NO_SECTOR, catwalk_wall, catwalk_wall, catwalk_wall),

    # ---- Pit perimeter (front = 3, CCW math) ----
    LineDef(7, 17, 3, NO_SECTOR, pit_wall, pit_wall, pit_wall),
    LineDef(17, 16, 3, NO_SECTOR, pit_wall, pit_wall, pit_wall),
    LineDef(16, 8, 3, NO_SECTOR, pit_wall, pit_wall, pit_wall),

    # ---- East corridor (front = 4) ----
    LineDef(4, 18, 4, NO_SECTOR, corr_wall, corr_wall, corr_wall),
    LineDef(18, 19, 4, 5, corr_wall, arena_upper, arena_lower),  # → arena
    LineDef(19, 5, 4, NO_SECTOR, corr_wall, corr_wall, corr_wall),

    # ---- Arena perimeter (front = 5). E wall split into 3. ----
    LineDef(18, 20, 5, NO_SECTOR, arena_wall, arena_wall, arena_wall),  # N
    LineDef(20, 34, 5, NO_SECTOR, arena_wall, arena_wall, arena_wall),  # E top
    LineDef(21, 19, 5, NO_SECTOR, arena_wall, arena_wall, arena_wall),  # S

    # ---- Staircase: 4 steps + overlook. ----
    LineDef(14, 22, 6, NO_SECTOR, stair1_wall, stair1_wall, stair1_wall),
    LineDef(22, 23, 6, 7, stair1_wall, stair1_wall, stair2_wall),
    LineDef(23, 15, 6, NO_SECTOR, stair1_wall, stair1_wall, stair1_wall),
    LineDef(22, 24, 7, NO_SECTOR, stair2_wall, stair2_wall, stair2_wall),
    LineDef(24, 25, 7, 8, stair2_wall, stair2_wall, stair3_wall),
    LineDef(25, 23, 7, NO_SECTOR, stair2_wall, stair2_wall, stair2_wall),
    LineDef(24, 26, 8, NO_SECTOR, stair3_wall, stair3_wall, stair3_wall),
    LineDef(26, 27, 8, 9, stair3_wall, stair3_wall, stair4_wall),
    LineDef(27, 25, 8, NO_SECTOR, stair3_wall, stair3_wall, stair3_wall),
    LineDef(26, 28, 9, NO_SECTOR, stair4_wall, stair4_wall, stair4_wall),
    LineDef(28, 29, 9, 10, stair4_wall, stair4_wall, overlook_wall),
    LineDef(29, 27, 9, NO_SECTOR, stair4_wall, stair4_wall, stair4_wall),
    # Overlook (front = 10) — five solid walls.
    LineDef(28, 30, 10, NO_SECTOR, overlook_wall, overlook_wall, overlook_wall),
    LineDef(30, 32, 10, NO_SECTOR, overlook_wall, overlook_wall, overlook_wall),
    LineDef(32, 33, 10, NO_SECTOR, overlook_wall, overlook_wall, overlook_wall),
    LineDef(33, 31, 10, NO_SECTOR, overlook_wall, overlook_wall, overlook_wall),
    LineDef(31, 29, 10, NO_SECTOR, overlook_wall, overlook_wall, overlook_wall),

    # ---- Arena east middle = alcove portal + remaining E split. ----
    LineDef(34, 35, 5, 11, arena_wall, arena_wall, alcove_wall),         # → alcove
    LineDef(35, 21, 5, NO_SECTOR, arena_wall, arena_wall, arena_wall),

    # ---- Alcove perimeter (front = 11). ----
    LineDef(34, 36, 11, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),  # N
    LineDef(36, 37, 11, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),  # E
    LineDef(37, 35, 11, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),  # S
]

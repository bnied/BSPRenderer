"""Hand-authored map. See the ASCII sketch in the original Level.swift."""

from math_utils import RGBA, Vec2
from geometry import NO_SECTOR, LineDef, Sector

vertices: list[Vec2] = [
    # Main hall perimeter
    Vec2(0, 0),      # 0  main NW
    Vec2(80, 0),     # 1  alcove opening west
    Vec2(140, 0),    # 2  alcove opening east
    Vec2(240, 0),    # 3  main NE
    Vec2(240, 80),   # 4  door top
    Vec2(240, 140),  # 5  door bottom
    Vec2(240, 200),  # 6  main SE
    Vec2(150, 200),  # 7  corridor opening east
    Vec2(90, 200),   # 8  corridor opening west
    Vec2(0, 200),    # 9  main SW
    # Alcove
    Vec2(80, -50),   # 10 alcove NW
    Vec2(140, -50),  # 11 alcove NE
    # East room
    Vec2(360, 80),   # 12 east NE
    Vec2(360, 140),  # 13 east SE
    # Corridor
    Vec2(200, 300),  # 14 corridor SE / south NE
    Vec2(140, 300),  # 15 corridor SW / south NW
    # South chamber
    Vec2(240, 360),  # 16 south SE
    Vec2(100, 360),  # 17 south SW
]

main_wall = RGBA(158, 144, 115, 255)
main_upper = RGBA(110, 105, 92, 255)
main_lower = RGBA(118, 96, 72, 255)
east_wall = RGBA(196, 90, 62, 255)
alcove_wall = RGBA(108, 170, 82, 255)
corr_wall = RGBA(94, 134, 200, 255)
south_wall = RGBA(168, 108, 206, 255)

sectors: list[Sector] = [
    # 0: Main hall — warm tan
    Sector(floor_h=0, ceil_h=64,
           floor_color=RGBA(82, 76, 60, 255),
           ceil_color=RGBA(50, 56, 70, 255),
           light=0.85),
    # 1: East room — red, raised floor, taller ceiling
    Sector(floor_h=16, ceil_h=88,
           floor_color=RGBA(112, 62, 46, 255),
           ceil_color=RGBA(72, 44, 34, 255),
           light=0.95),
    # 2: Alcove — green, low ceiling, raised floor
    Sector(floor_h=-12, ceil_h=48,
           floor_color=RGBA(58, 84, 52, 255),
           ceil_color=RGBA(42, 62, 40, 255),
           light=0.9),
    # 3: Diagonal corridor — blue, slight step up
    Sector(floor_h=4, ceil_h=68,
           floor_color=RGBA(48, 62, 96, 255),
           ceil_color=RGBA(34, 46, 78, 255),
           light=0.82),
    # 4: South chamber — violet, sunken floor
    Sector(floor_h=-12, ceil_h=52,
           floor_color=RGBA(76, 52, 96, 255),
           ceil_color=RGBA(52, 38, 76, 255),
           light=0.7),
]

linedefs: list[LineDef] = [
    # ---- Main hall perimeter (front = 0) ----
    LineDef(0, 1, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(1, 2, 0, 2, main_wall, alcove_wall, main_lower),
    LineDef(2, 3, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(3, 4, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(4, 5, 0, 1, main_wall, main_upper, east_wall),
    LineDef(5, 6, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(6, 7, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(7, 8, 0, 3, main_wall, corr_wall, corr_wall),
    LineDef(8, 9, 0, NO_SECTOR, main_wall, main_upper, main_lower),
    LineDef(9, 0, 0, NO_SECTOR, main_wall, main_upper, main_lower),

    # ---- Alcove (front = 2) ----
    LineDef(1, 10, 2, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),
    LineDef(10, 11, 2, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),
    LineDef(11, 2, 2, NO_SECTOR, alcove_wall, alcove_wall, alcove_wall),

    # ---- East room (front = 1) ----
    LineDef(4, 12, 1, NO_SECTOR, east_wall, east_wall, east_wall),
    LineDef(12, 13, 1, NO_SECTOR, east_wall, east_wall, east_wall),
    LineDef(13, 5, 1, NO_SECTOR, east_wall, east_wall, east_wall),

    # ---- Diagonal corridor (front = 3) ----
    LineDef(7, 14, 3, NO_SECTOR, corr_wall, corr_wall, corr_wall),
    LineDef(14, 15, 3, 4, corr_wall, corr_wall, south_wall),
    LineDef(15, 8, 3, NO_SECTOR, corr_wall, corr_wall, corr_wall),

    # ---- South chamber (front = 4) ----
    LineDef(14, 16, 4, NO_SECTOR, south_wall, south_wall, south_wall),
    LineDef(16, 17, 4, NO_SECTOR, south_wall, south_wall, south_wall),
    LineDef(17, 15, 4, NO_SECTOR, south_wall, south_wall, south_wall),
]

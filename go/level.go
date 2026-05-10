package main

// Hand-authored map. See the ASCII sketch in the original Level.swift.

var vertices = []Vec2{
	// Main hall perimeter
	{0, 0},     // 0  main NW
	{80, 0},    // 1  alcove opening west
	{140, 0},   // 2  alcove opening east
	{240, 0},   // 3  main NE
	{240, 80},  // 4  door top
	{240, 140}, // 5  door bottom
	{240, 200}, // 6  main SE
	{150, 200}, // 7  corridor opening east
	{90, 200},  // 8  corridor opening west
	{0, 200},   // 9  main SW
	// Alcove
	{80, -50},  // 10 alcove NW
	{140, -50}, // 11 alcove NE
	// East room
	{360, 80},  // 12 east NE
	{360, 140}, // 13 east SE
	// Corridor
	{200, 300}, // 14 corridor SE / south NE
	{140, 300}, // 15 corridor SW / south NW
	// South chamber
	{240, 360}, // 16 south SE
	{100, 360}, // 17 south SW
}

var (
	mainWall   = RGBA{158, 144, 115, 255}
	mainUpper  = RGBA{110, 105, 92, 255}
	mainLower  = RGBA{118, 96, 72, 255}
	eastWall   = RGBA{196, 90, 62, 255}
	alcoveWall = RGBA{108, 170, 82, 255}
	corrWall   = RGBA{94, 134, 200, 255}
	southWall  = RGBA{168, 108, 206, 255}
)

var sectors = []Sector{
	// 0: Main hall — warm tan
	{floorH: 0, ceilH: 64,
		floorColor: RGBA{82, 76, 60, 255},
		ceilColor:  RGBA{50, 56, 70, 255},
		light:      0.85},
	// 1: East room — red, raised floor, taller ceiling
	{floorH: 16, ceilH: 88,
		floorColor: RGBA{112, 62, 46, 255},
		ceilColor:  RGBA{72, 44, 34, 255},
		light:      0.95},
	// 2: Alcove — green, low ceiling, raised floor
	{floorH: -12, ceilH: 48,
		floorColor: RGBA{58, 84, 52, 255},
		ceilColor:  RGBA{42, 62, 40, 255},
		light:      0.9},
	// 3: Diagonal corridor — blue, slight step up
	{floorH: 4, ceilH: 68,
		floorColor: RGBA{48, 62, 96, 255},
		ceilColor:  RGBA{34, 46, 78, 255},
		light:      0.82},
	// 4: South chamber — violet, sunken floor
	{floorH: -12, ceilH: 52,
		floorColor: RGBA{76, 52, 96, 255},
		ceilColor:  RGBA{52, 38, 76, 255},
		light:      0.7},
}

var linedefs = []LineDef{
	// ---- Main hall perimeter (front = 0) ----
	{v1: 0, v2: 1, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 1, v2: 2, frontSector: 0, backSector: 2, wallColor: mainWall, upperColor: alcoveWall, lowerColor: mainLower},
	{v1: 2, v2: 3, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 3, v2: 4, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 4, v2: 5, frontSector: 0, backSector: 1, wallColor: mainWall, upperColor: mainUpper, lowerColor: eastWall},
	{v1: 5, v2: 6, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 6, v2: 7, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 7, v2: 8, frontSector: 0, backSector: 3, wallColor: mainWall, upperColor: corrWall, lowerColor: corrWall},
	{v1: 8, v2: 9, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},
	{v1: 9, v2: 0, frontSector: 0, backSector: noSector, wallColor: mainWall, upperColor: mainUpper, lowerColor: mainLower},

	// ---- Alcove (front = 2) ----
	{v1: 1, v2: 10, frontSector: 2, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall},
	{v1: 10, v2: 11, frontSector: 2, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall},
	{v1: 11, v2: 2, frontSector: 2, backSector: noSector, wallColor: alcoveWall, upperColor: alcoveWall, lowerColor: alcoveWall},

	// ---- East room (front = 1) ----
	{v1: 4, v2: 12, frontSector: 1, backSector: noSector, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall},
	{v1: 12, v2: 13, frontSector: 1, backSector: noSector, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall},
	{v1: 13, v2: 5, frontSector: 1, backSector: noSector, wallColor: eastWall, upperColor: eastWall, lowerColor: eastWall},

	// ---- Diagonal corridor (front = 3) ----
	{v1: 7, v2: 14, frontSector: 3, backSector: noSector, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall},
	{v1: 14, v2: 15, frontSector: 3, backSector: 4, wallColor: corrWall, upperColor: corrWall, lowerColor: southWall},
	{v1: 15, v2: 8, frontSector: 3, backSector: noSector, wallColor: corrWall, upperColor: corrWall, lowerColor: corrWall},

	// ---- South chamber (front = 4) ----
	{v1: 14, v2: 16, frontSector: 4, backSector: noSector, wallColor: southWall, upperColor: southWall, lowerColor: southWall},
	{v1: 16, v2: 17, frontSector: 4, backSector: noSector, wallColor: southWall, upperColor: southWall, lowerColor: southWall},
	{v1: 17, v2: 15, frontSector: 4, backSector: noSector, wallColor: southWall, upperColor: southWall, lowerColor: southWall},
}

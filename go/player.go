package main

// Player physics: movement, collision, and the camera-height policy.
//
// The player is a 2-D circle of radius 8 in the (x, y) plane that auto-snaps
// its feet Z to the current sector's floor height. Step-up across portals is
// gated by maxStepUp; portals whose vertical opening is shorter than the
// player's standing height are treated as solid.
//
// Vertical camera motion is interesting: see EyeZ() and eyeFollowFactor.

import "math"

type Player struct {
	level           *Level  // the map, for collision queries against its linedefs
	pos             Vec2    // (x, y) world position
	feetZ           float64 // Z of the feet — tracks current sector's floorH
	angle           float64 // facing angle in radians; 0 = +x, π/2 = +y
	fov             float64 // total horizontal field of view, radians
	moveSpeed       float64 // world units per second
	rotSpeed        float64 // radians per second
	eyeOverFloor    float64 // how high above feet the eye sits (standing height)
	eyeFollowFactor float64 // see EyeZ()
	baselineEyeZ    float64 // eye Z when standing in a "baseline" sector
}

// NewPlayer drops the player just north of the hub's south wall, facing
// north — looking straight down the catwalk into the colored staircase and
// the bright overlook at the end. The pillar is behind the player, so the
// first frame shows off the deep portal chain (hub → catwalk → 4 stair
// sectors → overlook) rather than being dominated by the pillar. Turn
// around to discover the pillar, the pit (south), and the corridor (east).
func NewPlayer(level *Level) *Player {
	return &Player{
		level:           level,
		pos:             Vec2{120, 50},
		angle:           -math.Pi / 2,
		fov:             70.0 * math.Pi / 180.0,
		moveSpeed:       140.0,
		rotSpeed:        2.4,
		eyeOverFloor:    41.0,
		eyeFollowFactor: 1.0,
		baselineEyeZ:    41.0,
	}
}

// EyeZ blends two camera-height policies:
//
//   eyeFollowFactor = 1.0  →  eye is rigidly attached to feet. Camera
//                             physically rises and falls the full step
//                             amount, but because feet and eye move
//                             together, the floor stays at a constant
//                             screen distance below the horizon.
//
//   eyeFollowFactor = 0.0  →  fixed-baseline camera. Eye Z never changes;
//                             the floor's screen position reflects the
//                             sector's true Z, so steps up/down are visible
//                             as the floor sliding on screen.
//
//   in between             →  partial bobbing. Useful if you want both the
//                             physical "step-up" feeling and the visual
//                             "the floor moved" cue at once.
//
// We use 1.0 by default — the camera rises/falls with the player and the
// scene around them is what changes (back-sector ceilings come into view,
// upper walls open, etc.).
func (p *Player) EyeZ() float64 {
	feetBaseline := p.baselineEyeZ - p.eyeOverFloor
	return p.baselineEyeZ + p.eyeFollowFactor*(p.feetZ-feetBaseline)
}

// Input is the per-tick boolean key state. The Game layer in main.go fills
// this in from the windowing system; the player has no idea Ebiten exists.
type Input struct {
	forward, back, strafeL, strafeR, turnL, turnR bool
}

// Update advances the player by `dt` seconds of simulation time given the
// current input state. Movement is axis-separated and probed against all
// solid linedefs so the player can slide along walls instead of getting
// stuck on them.
func (p *Player) Update(dt float64, in Input, bsp *BSP) {
	rot := p.rotSpeed * dt
	mv := p.moveSpeed * dt

	if in.turnL {
		p.angle -= rot
	}
	if in.turnR {
		p.angle += rot
	}

	cosA := math.Cos(p.angle)
	sinA := math.Sin(p.angle)

	// Compose desired (dx, dy) in world space from the four movement keys.
	// forward = (cosA, sinA); right = (-sinA, cosA).
	dx, dy := 0.0, 0.0
	if in.forward {
		dx += cosA * mv
		dy += sinA * mv
	}
	if in.back {
		dx -= cosA * mv
		dy -= sinA * mv
	}
	if in.strafeL {
		dx += sinA * mv
		dy -= cosA * mv
	}
	if in.strafeR {
		dx -= sinA * mv
		dy += cosA * mv
	}

	// Axis-separated probe lets the player slide along walls.
	radius := 8.0
	currentFloorH := p.level.sector(bsp.FindSector(p.pos)).floorH

	tryX := Vec2{p.pos.x + dx, p.pos.y}
	if !p.collides(tryX, radius, currentFloorH) {
		p.pos.x = tryX.x
	}
	tryY := Vec2{p.pos.x, p.pos.y + dy}
	if !p.collides(tryY, radius, currentFloorH) {
		p.pos.y = tryY.y
	}

	// Snap feet to the new sector's floor (no gravity / falling).
	p.feetZ = p.level.sector(bsp.FindSector(p.pos)).floorH
}

// collides returns true if a circle of `radius` centered at `pos` is blocked
// by any linedef. A linedef is "blocking" if either:
//
//   - it's one-sided (a solid wall), OR
//   - it's a portal whose opening (top - bottom) is too short to walk
//     through, OR
//   - the back-side floor is more than maxStepUp above the side we're
//     standing on (cliff-like step).
func (p *Player) collides(pos Vec2, radius, currentFloorH float64) bool {
	const maxStepUp = 24.0
	for _, l := range p.level.linedefs {
		a := p.level.vertex(l.v1)
		b := p.level.vertex(l.v2)
		if pointSegmentDistance(pos, a, b) >= radius {
			continue // not touching this wall
		}
		if l.backSector == noSector {
			return true // solid one-sided wall
		}
		front := p.level.sector(l.frontSector)
		back := p.level.sector(l.backSector)

		// Portal opening must be tall enough for the player to fit through.
		openingTop := math.Min(front.ceilH, back.ceilH)
		openingBottom := math.Max(front.floorH, back.floorH)
		if openingTop-openingBottom < p.eyeOverFloor {
			return true
		}

		// Step-up gate: which side is the probe entering?
		pdx := b.x - a.x
		pdy := b.y - a.y
		side := pdx*(pos.y-a.y) - pdy*(pos.x-a.x)
		var targetFloorH float64
		if side > 0 {
			targetFloorH = back.floorH
		} else {
			targetFloorH = front.floorH
		}
		if targetFloorH-currentFloorH > maxStepUp {
			return true
		}
	}
	return false
}

// pointSegmentDistance returns the perpendicular distance from point p to the
// line segment ab, clamped to the endpoints.
func pointSegmentDistance(p, a, b Vec2) float64 {
	ab := b.Sub(a)
	l2 := ab.x*ab.x + ab.y*ab.y
	if l2 < 1e-9 {
		return p.Sub(a).Len()
	}
	t := ((p.x-a.x)*ab.x + (p.y-a.y)*ab.y) / l2
	t = clampF(t, 0, 1)
	proj := Vec2{a.x + ab.x*t, a.y + ab.y*t}
	return p.Sub(proj).Len()
}

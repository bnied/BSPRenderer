// BSPRenderer — DOOM-style software renderer.
//
// This is a Go port of a Swift/AppKit project. The architecture is unchanged:
//
//   1. Level definition (level.go) — hand-authored vertices, sectors, and
//      linedefs. Each two-sided linedef is a portal between two sectors.
//
//   2. Seg generation + BSP build (bsp_build.go) — every linedef becomes one
//      or two segs (one for one-sided walls, two for portals so each side
//      can be drawn from the right sector). The BSP is built once at startup
//      by recursively choosing a partition seg that keeps both subspaces
//      populated and minimizes straddle splits.
//
//   3. Per-frame BSP traversal (bsp_traverse.go) — front-to-back walk from
//      the player's current side, handing each seg to the renderer.
//
//   4. Per-seg rasterization (renderer_seg.go) — back-face cull, view-space
//      transform, near + L + R frustum clipping, screen-x projection, then
//      per-column 1/d interpolation. yTop/yBot per-column arrays serve as
//      DOOM's ceilingclip/floorclip — solid walls fully occlude, two-sided
//      portals narrow the open region. Floor/ceiling pixels are NOT drawn
//      here; instead, spans are recorded into per-sector visplanes.
//
//   5. Visplane pass (renderer_visplanes.go + renderer_fill.go) — after the
//      BSP walk, every visplane that received coverage is rasterized by
//      inverse-projecting each pixel back to its world (X, Y), sampling a
//      procedural checkerboard, and depth-shading.
//
//   6. Overlays (renderer_overlays.go) — minimap and crosshair.
//
// Windowing/input/blit is handled by Ebiten. Internal resolution is 480x300;
// Ebiten upscales to the 960x600 window with point-sampled (chunky pixel)
// scaling.

package main

import (
	"fmt"
	"image/color"
	"log"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/ebitenutil"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

const (
	internalW = 480
	internalH = 300
	windowW   = 960
	windowH   = 600
)

// Game is Ebiten's per-frame entry point. Update runs at a fixed tick rate
// (defaults to 60 Hz); Draw runs once per displayed frame.
type Game struct {
	level    *Level
	player   *Player
	renderer *Renderer
	bsp      *BSP
	last     time.Time
}

func NewGame() *Game {
	level := NewShowcaseLevel()
	return &Game{
		level:    level,
		player:   NewPlayer(level),
		renderer: NewRenderer(level, internalW, internalH),
		bsp:      NewBSP(level),
		last:     time.Now(),
	}
}

// Update polls keyboard state, advances the player by the elapsed wall-clock
// dt, and runs the renderer to fill its pixel buffer for this frame.
func (g *Game) Update() error {
	now := time.Now()
	dt := now.Sub(g.last).Seconds()
	if dt > 0.05 { // clamp huge dt's (e.g. after a window stall)
		dt = 0.05
	}
	g.last = now

	if ebiten.IsKeyPressed(ebiten.KeyEscape) {
		return ebiten.Termination
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyTab) {
		g.renderer.slowMode = !g.renderer.slowMode
	}

	in := Input{
		forward: ebiten.IsKeyPressed(ebiten.KeyW) || ebiten.IsKeyPressed(ebiten.KeyArrowUp),
		back:    ebiten.IsKeyPressed(ebiten.KeyS) || ebiten.IsKeyPressed(ebiten.KeyArrowDown),
		strafeL: ebiten.IsKeyPressed(ebiten.KeyA),
		strafeR: ebiten.IsKeyPressed(ebiten.KeyD),
		turnL:   ebiten.IsKeyPressed(ebiten.KeyArrowLeft),
		turnR:   ebiten.IsKeyPressed(ebiten.KeyArrowRight),
	}

	g.player.Update(dt, in, g.bsp)
	g.renderer.Render(g.player, g.bsp)
	return nil
}

// Draw blits the renderer's RGBA buffer to the screen and overlays the HUD.
// Ebiten will upscale `screen` to the window with nearest-neighbor sampling
// because we set ScreenFilterEnabled to false implicitly via Layout.
func (g *Game) Draw(screen *ebiten.Image) {
	screen.WritePixels(g.renderer.pixels)

	si := g.bsp.FindSector(g.player.pos)
	s := g.level.sector(si)
	slowTag := ""
	if g.renderer.slowMode {
		slowTag = "   [SLOW]"
	}
	hud := fmt.Sprintf("sector %d   floor %+d   ceil %+d   feetZ %+d   eyeZ %+d%s",
		si, int(s.floorH), int(s.ceilH), int(g.player.feetZ), int(g.player.EyeZ()), slowTag)

	// Dim backdrop behind the HUD text so it stays legible over any scene.
	const padX, padY = 6, 4
	textW := len(hud) * 6 // ebitenutil's bitmap font is ~6px wide per char
	bg := color.NRGBA{0, 0, 0, 140}
	ebitenutil.DrawRect(screen, 4, 4, float64(textW+padX*2), float64(12+padY*2), bg)
	ebitenutil.DebugPrintAt(screen, hud, 4+padX, 4+padY)
}

// Layout fixes the renderer-side resolution. Returning a constant means
// Ebiten always hands Draw a 480x300 image regardless of window size.
func (g *Game) Layout(outsideW, outsideH int) (int, int) {
	return internalW, internalH
}

func main() {
	ebiten.SetWindowSize(windowW, windowH)
	ebiten.SetWindowTitle("BSP Renderer (Go) — WASD / arrows, Tab = slow mode, Esc to quit")
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	if err := ebiten.RunGame(NewGame()); err != nil {
		log.Fatal(err)
	}
}

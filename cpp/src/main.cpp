// BSPRenderer — DOOM-style software renderer.
//
// C++ port of the Swift/AppKit original. Architecture is unchanged:
//
//   1. Level definition (level.cpp) — hand-authored vertices, sectors, and
//      linedefs. Each two-sided linedef is a portal between two sectors.
//
//   2. Seg generation + BSP build (bsp.cpp) — every linedef becomes one or
//      two segs (one for one-sided walls, two for portals so each side can
//      be drawn from the right sector). The BSP is built once at startup
//      by recursively choosing a partition seg that keeps both subspaces
//      populated and minimizes straddle splits.
//
//   3. Per-frame BSP traversal (bsp.cpp) — front-to-back walk from the
//      player's current side, handing each seg to the renderer.
//
//   4. Per-seg rasterization (renderer.cpp) — back-face cull, view-space
//      transform, near + L + R frustum clipping, screen-x projection, then
//      per-column 1/d interpolation. yTop/yBot per-column arrays serve as
//      DOOM's ceilingclip/floorclip — solid walls fully occlude, two-sided
//      portals narrow the open region. Floor/ceiling pixels are NOT drawn
//      here; instead, spans are recorded into per-sector visplanes.
//
//   5. Visplane pass (renderer.cpp) — after the BSP walk, every visplane
//      that received coverage is rasterized by inverse-projecting each
//      pixel back to its world (X, Y), sampling a procedural checkerboard,
//      and depth-shading.
//
//   6. Overlays (renderer.cpp) — minimap and crosshair.
//
// Windowing/input/blit is handled by SDL3 using the new callback main model.
// Internal resolution is 480x300; SDL upscales to the 960x600 window with
// nearest-neighbor sampling via logical presentation.

#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include <cstdio>
#include <memory>

#include "bsp.hpp"
#include "level.hpp"
#include "player.hpp"
#include "renderer.hpp"

namespace {

constexpr int internalW = 480;
constexpr int internalH = 300;
constexpr int windowW   = 960;
constexpr int windowH   = 600;

// AppState is the bag of "everything alive for the lifetime of the program".
// SDL3 callbacks pass us a void* we previously stashed in SDL_AppInit; we
// keep a typed pointer to this struct in there.
struct AppState {
    SDL_Window*   window   = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Texture*  texture  = nullptr;

    std::unique_ptr<Player>   player;
    std::unique_ptr<Renderer> rendererSW; // software renderer, distinct from SDL_Renderer
    std::unique_ptr<BSPNode>  bsp;

    Uint64 lastTickNS = 0;
};

} // namespace

// ----------------------------------------------------------------------------
// SDL3 callback entry points
// ----------------------------------------------------------------------------

extern "C" SDL_AppResult SDL_AppInit(void** appstate, int /*argc*/, char* /*argv*/[]) {
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    auto state = new AppState();

    if (!SDL_CreateWindowAndRenderer(
            "BSP Renderer (C++) — WASD / arrows, Tab = slow mode, Esc to quit",
            windowW, windowH,
            SDL_WINDOW_RESIZABLE,
            &state->window, &state->renderer)) {
        SDL_Log("CreateWindowAndRenderer failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    SDL_SetRenderVSync(state->renderer, 1);

    // Logical presentation gives us a fixed internal resolution that SDL
    // upscales to the window with integer scaling — same effect as the Swift
    // original's "draw 480x300 to a 960x600 window" pipeline.
    SDL_SetRenderLogicalPresentation(state->renderer,
                                     internalW, internalH,
                                     SDL_LOGICAL_PRESENTATION_INTEGER_SCALE);

    // Streaming texture is the path SDL recommends for "I have a CPU pixel
    // buffer I want to push every frame": we update its contents with
    // SDL_UpdateTexture and let SDL_RenderTexture move it to the screen.
    state->texture = SDL_CreateTexture(state->renderer,
                                       SDL_PIXELFORMAT_RGBA32,
                                       SDL_TEXTUREACCESS_STREAMING,
                                       internalW, internalH);
    if (!state->texture) {
        SDL_Log("CreateTexture failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    SDL_SetTextureScaleMode(state->texture, SDL_SCALEMODE_NEAREST);

    // Build the world.
    state->player     = std::make_unique<Player>();
    state->rendererSW = std::make_unique<Renderer>(internalW, internalH);
    state->bsp        = buildBSP(generateSegs());
    state->lastTickNS = SDL_GetTicksNS();

    *appstate = state;
    return SDL_APP_CONTINUE;
}

extern "C" SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event* event) {
    auto state = static_cast<AppState*>(appstate);

    switch (event->type) {
        case SDL_EVENT_QUIT:
            return SDL_APP_SUCCESS;
        case SDL_EVENT_KEY_DOWN:
            if (event->key.key == SDLK_ESCAPE) return SDL_APP_SUCCESS;
            if (event->key.key == SDLK_TAB)    state->rendererSW->slowMode = !state->rendererSW->slowMode;
            break;
        default:
            break;
    }
    return SDL_APP_CONTINUE;
}

extern "C" SDL_AppResult SDL_AppIterate(void* appstate) {
    auto state = static_cast<AppState*>(appstate);

    // Wall-clock dt with a hard cap so a huge stall (window dragged, debugger
    // paused) doesn't teleport the player through walls on the next frame.
    Uint64 nowNS = SDL_GetTicksNS();
    double dt = static_cast<double>(nowNS - state->lastTickNS) / 1e9;
    if (dt > 0.05) dt = 0.05;
    state->lastTickNS = nowNS;

    // Translate SDL keyboard state into our agnostic Input struct.
    const bool* keys = SDL_GetKeyboardState(nullptr);
    Input in;
    in.forward = keys[SDL_SCANCODE_W] || keys[SDL_SCANCODE_UP];
    in.back    = keys[SDL_SCANCODE_S] || keys[SDL_SCANCODE_DOWN];
    in.strafeL = keys[SDL_SCANCODE_A];
    in.strafeR = keys[SDL_SCANCODE_D];
    in.turnL   = keys[SDL_SCANCODE_LEFT];
    in.turnR   = keys[SDL_SCANCODE_RIGHT];

    state->player->update(dt, in, *state->bsp);
    state->rendererSW->render(*state->player, *state->bsp);

    // Push our RGBA buffer into the streaming texture.
    SDL_UpdateTexture(state->texture, nullptr,
                      state->rendererSW->pixelData(),
                      state->rendererSW->width() * 4);

    SDL_SetRenderDrawColor(state->renderer, 0, 0, 0, 255);
    SDL_RenderClear(state->renderer);
    SDL_RenderTexture(state->renderer, state->texture, nullptr, nullptr);

    // HUD overlay using SDL3's built-in 8x8 debug font. Logical-presentation
    // coordinates, so this lands in the top-left of the 480x300 internal
    // viewport regardless of window size.
    int si = findSector(state->player->pos, *state->bsp);
    const Sector& s = sectors[si];
    char hud[160];
    std::snprintf(hud, sizeof(hud),
                  "sector %d   floor %+d   ceil %+d   feetZ %+d   eyeZ %+d%s",
                  si,
                  static_cast<int>(s.floorH),
                  static_cast<int>(s.ceilH),
                  static_cast<int>(state->player->feetZ),
                  static_cast<int>(state->player->eyeZ()),
                  state->rendererSW->slowMode ? "   [SLOW]" : "");

    // Dim backdrop behind the text so it stays legible over any scene.
    int textW = static_cast<int>(SDL_strlen(hud)) * 8;
    SDL_FRect bg{2.0f, 2.0f, static_cast<float>(textW + 6), 12.0f};
    SDL_SetRenderDrawBlendMode(state->renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(state->renderer, 0, 0, 0, 140);
    SDL_RenderFillRect(state->renderer, &bg);
    SDL_SetRenderDrawColor(state->renderer, 255, 255, 255, 255);
    SDL_RenderDebugText(state->renderer, 4, 4, hud);

    SDL_RenderPresent(state->renderer);
    return SDL_APP_CONTINUE;
}

extern "C" void SDL_AppQuit(void* appstate, SDL_AppResult /*result*/) {
    auto state = static_cast<AppState*>(appstate);
    if (!state) return;
    if (state->texture)  SDL_DestroyTexture(state->texture);
    if (state->renderer) SDL_DestroyRenderer(state->renderer);
    if (state->window)   SDL_DestroyWindow(state->window);
    delete state;
}

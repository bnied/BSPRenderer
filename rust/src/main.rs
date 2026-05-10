//! BSPRenderer — DOOM-style software renderer (Rust port).
//!
//! This is a Rust port of a Swift/AppKit project, mirroring the structure of
//! the existing C++, Go, and Python ports. The architecture is unchanged:
//!
//!   1. Level definition ([`level`]) — hand-authored vertices, sectors, and
//!      linedefs. Each two-sided linedef is a portal between two sectors.
//!
//!   2. Seg generation + BSP build ([`bsp`]) — every linedef becomes one or
//!      two segs (one for one-sided walls, two for portals). The BSP is built
//!      once at startup by recursively choosing a partition seg that keeps
//!      both subspaces populated and minimizes straddle splits.
//!
//!   3. Per-frame BSP traversal ([`bsp::traverse_bsp`]) — front-to-back walk
//!      from the player's side, handing each seg to the renderer.
//!
//!   4. Per-seg rasterization ([`renderer::Renderer::render`]) — back-face
//!      cull, view-space transform, near + L + R frustum clipping, screen-x
//!      projection, then per-column 1/d interpolation. y_top/y_bot per-column
//!      arrays serve as DOOM's ceilingclip/floorclip.
//!
//!   5. Visplane pass — after the BSP walk, every visplane that received
//!      coverage is rasterized by inverse-projecting each pixel back to its
//!      world (X, Y), sampling a procedural checkerboard, and depth-shading.
//!
//!   6. Overlays — minimap and crosshair.
//!
//! Windowing/input/blit is handled by `winit` + the `pixels` crate. Internal
//! resolution is 480x300; the `pixels` crate handles upscale to the window.

mod bsp;
mod font;
mod geometry;
mod level;
mod math_utils;
mod player;
mod renderer;
mod visplane;

use std::sync::Arc;
use std::time::Instant;

use pixels::{Pixels, SurfaceTexture};
use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};

use crate::bsp::{build_bsp, generate_segs, BspNode};
use crate::player::{Input, Player};
use crate::renderer::Renderer;

const INTERNAL_W: u32 = 480;
const INTERNAL_H: u32 = 300;
const WINDOW_W: u32 = 960;
const WINDOW_H: u32 = 600;

/// Holds everything alive for the lifetime of the program. winit 0.30's
/// `ApplicationHandler` model defers window creation until `resumed`, so the
/// window/pixels fields are `Option`s populated there.
///
/// FIELD ORDER MATTERS: Rust drops struct fields in declaration order, and
/// `pixels` borrows from `window` (via the Arc transmuted to 'static below).
/// `pixels` MUST be declared before `window` so it drops first — otherwise
/// `window`'s Arc would drop, the Window would be released, and `pixels`'
/// destructor would run against a freed surface.
struct App {
    pixels: Option<Pixels<'static>>,
    window: Option<Arc<Window>>,
    player: Player,
    renderer: Renderer,
    bsp_root: Box<BspNode>,
    input: Input,
    last: Instant,
}

impl App {
    fn new() -> Self {
        Self {
            pixels: None,
            window: None,
            player: Player::new(),
            renderer: Renderer::new(INTERNAL_W as usize, INTERNAL_H as usize),
            bsp_root: build_bsp(generate_segs()),
            input: Input::default(),
            last: Instant::now(),
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        let attrs = Window::default_attributes()
            .with_title(
                "BSP Renderer (Rust) — WASD / arrows, Tab = slow mode, Esc to quit",
            )
            .with_inner_size(LogicalSize::new(WINDOW_W, WINDOW_H));
        let window = Arc::new(
            event_loop
                .create_window(attrs)
                .expect("failed to create window"),
        );

        let size = window.inner_size();
        let surface_texture = SurfaceTexture::new(size.width, size.height, Arc::clone(&window));
        let pixels = Pixels::new(INTERNAL_W, INTERNAL_H, surface_texture)
            .expect("failed to create pixels surface");

        // pixels borrows the window via Arc; we keep the Arc alive in
        // self.window for at least as long as self.pixels, so the underlying
        // borrow is sound. The transmute upgrades the lifetime to 'static
        // because we can't name the actual self-referential lifetime in
        // a struct field.
        let pixels: Pixels<'static> = unsafe { std::mem::transmute(pixels) };

        self.window = Some(window);
        self.pixels = Some(pixels);
        self.last = Instant::now();
        if let Some(w) = &self.window {
            w.request_redraw();
        }
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _id: WindowId,
        event: WindowEvent,
    ) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::Resized(new_size) => {
                if let Some(p) = &mut self.pixels {
                    let _ = p.resize_surface(new_size.width, new_size.height);
                }
            }
            WindowEvent::KeyboardInput {
                event:
                    KeyEvent {
                        physical_key: PhysicalKey::Code(code),
                        state,
                        ..
                    },
                ..
            } => {
                let pressed = state == ElementState::Pressed;
                match code {
                    KeyCode::Escape if pressed => event_loop.exit(),
                    KeyCode::Tab if pressed => {
                        self.renderer.slow_mode = !self.renderer.slow_mode;
                    }
                    KeyCode::KeyW | KeyCode::ArrowUp => self.input.forward = pressed,
                    KeyCode::KeyS | KeyCode::ArrowDown => self.input.back = pressed,
                    KeyCode::KeyA => self.input.strafe_l = pressed,
                    KeyCode::KeyD => self.input.strafe_r = pressed,
                    KeyCode::ArrowLeft => self.input.turn_l = pressed,
                    KeyCode::ArrowRight => self.input.turn_r = pressed,
                    _ => {}
                }
            }
            WindowEvent::RedrawRequested => {
                let now = Instant::now();
                let mut dt = (now - self.last).as_secs_f64();
                if dt > 0.05 {
                    // Clamp huge dt's (e.g. after a window stall).
                    dt = 0.05;
                }
                self.last = now;

                self.player.update(dt, self.input, &self.bsp_root);
                self.renderer.render(&self.player, &self.bsp_root);
                self.renderer.draw_hud(&self.player, &self.bsp_root);

                if let Some(p) = &mut self.pixels {
                    p.frame_mut().copy_from_slice(&self.renderer.pixels);
                    if let Err(e) = p.render() {
                        eprintln!("pixels render error: {e}");
                        event_loop.exit();
                        return;
                    }
                }

                if let Some(w) = &self.window {
                    w.request_redraw();
                }
            }
            _ => {}
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let event_loop = EventLoop::new()?;
    event_loop.set_control_flow(ControlFlow::Poll);
    let mut app = App::new();
    event_loop.run_app(&mut app)?;
    Ok(())
}

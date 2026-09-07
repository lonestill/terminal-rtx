mod camera;
mod metal;
mod renderer;

use std::io::{self, stdout, Write};
use std::panic;
use std::time::{Duration, Instant};

use crossterm::{
    cursor::{Hide, Show},
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, size, EnterAlternateScreen, LeaveAlternateScreen},
};

use camera::Camera;
use metal::{MetalRtx, RtxUniforms};
use renderer::TerminalRenderer;

fn restore_terminal() {
    let _ = disable_raw_mode();
    let mut out = stdout();
    let _ = out.write_all(b"\x1b[?2025l\x1b[?7h\x1b[?25h\x1b[0m");
    let _ = execute!(out, Show, LeaveAlternateScreen);
}

fn main() -> io::Result<()> {
    let mut metal = match MetalRtx::init() {
        Some(m) => m,
        None => {
            eprintln!("Metal initialization failed. Apple Silicon GPU required.");
            return Ok(());
        }
    };

    let orig_hook = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        restore_terminal();
        orig_hook(info);
    }));

    enable_raw_mode()?;
    let mut out = stdout();
    execute!(out, EnterAlternateScreen, Hide)?;
    let _ = out.write_all(b"\x1b[?7l");
    let _ = out.flush();

    let mut camera = Camera::new();
    let mut renderer = TerminalRenderer::new();

    let mut scene_id = 0u32;
    let mut last_frame = Instant::now();
    let start_time = Instant::now();

    let mut frame_count = 0u32;
    let mut fps_timer = Instant::now();
    let mut current_fps = 60.0f32;

    let target_frame_dur = Duration::from_micros(16667);

    let res = (|| -> io::Result<()> {
        loop {
            let now = Instant::now();
            let dt = now.duration_since(last_frame).as_secs_f32().min(0.1);
            last_frame = now;

            frame_count += 1;
            if fps_timer.elapsed() >= Duration::from_secs(1) {
                current_fps = (frame_count as f32) / fps_timer.elapsed().as_secs_f32();
                frame_count = 0;
                fps_timer = Instant::now();
            }

            let move_step = (3.5f32 * dt).max(0.01);
            let rot_step = (2.4f32 * dt).max(0.01);

            let mut move_fwd = 0.0f32;
            let mut move_side = 0.0f32;
            let mut move_vert = 0.0f32;
            let mut rot_yaw = 0.0f32;
            let mut rot_pitch = 0.0f32;

            while event::poll(Duration::from_millis(0))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press || key.kind == KeyEventKind::Repeat {
                        match key.code {
                            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => return Ok(()),
                            KeyCode::Char('w') | KeyCode::Char('W') => move_fwd += 1.0,
                            KeyCode::Char('s') | KeyCode::Char('S') => move_fwd -= 1.0,
                            KeyCode::Char('a') | KeyCode::Char('A') => move_side -= 1.0,
                            KeyCode::Char('d') | KeyCode::Char('D') => move_side += 1.0,
                            KeyCode::Char(' ') | KeyCode::Char('e') | KeyCode::Char('E') => move_vert += 1.0,
                            KeyCode::Char('c') | KeyCode::Char('C') => move_vert -= 1.0,
                            KeyCode::Left => rot_yaw -= 1.0,
                            KeyCode::Right => rot_yaw += 1.0,
                            KeyCode::Up => rot_pitch += 1.0,
                            KeyCode::Down => rot_pitch -= 1.0,
                            KeyCode::Char('1') => scene_id = 0,
                            KeyCode::Char('2') => scene_id = 1,
                            KeyCode::Char('3') => scene_id = 2,
                            _ => {}
                        }
                    }
                }
            }

            if move_fwd != 0.0 {
                camera.move_forward(move_fwd.clamp(-1.0, 1.0) * move_step);
            }
            if move_side != 0.0 {
                camera.move_right(move_side.clamp(-1.0, 1.0) * move_step);
            }
            if move_vert != 0.0 {
                camera.move_up(move_vert.clamp(-1.0, 1.0) * move_step);
            }
            if rot_yaw != 0.0 || rot_pitch != 0.0 {
                camera.rotate(rot_yaw.clamp(-1.0, 1.0) * rot_step, rot_pitch.clamp(-1.0, 1.0) * rot_step);
            }

            let (cols, rows) = size()?;
            let width = (cols as usize).max(20);
            let canvas_rows = (rows as usize).saturating_sub(1).max(5);
            let height = canvas_rows * 2;

            let time = start_time.elapsed().as_secs_f32();

            let uniforms = RtxUniforms {
                cam_pos: camera.pos,
                cam_dir: camera.dir(),
                cam_up: camera.up(),
                cam_right: camera.right(),
                width: width as u32,
                height: height as u32,
                time,
                scene_id,
            };

            let scene_name = match scene_id {
                0 => "Cyberpunk Mirror Hall",
                1 => "Mandelbulb 3D Fractal",
                _ => "Infinite Chrome Spheres",
            };

            let hud = if width >= 115 {
                format!(
                    "TERMINAL-RTX :: {:.1} FPS | [{}] | Pos: {:.1}, {:.1}, {:.1} | [WASD] Move [Arrows] Look [1-3] Scene [Q] Quit",
                    current_fps, scene_name, camera.pos[0], camera.pos[1], camera.pos[2]
                )
            } else if width >= 75 {
                format!(
                    "RTX :: {:.1} FPS | [{}] | [WASD] Move [1-3] Scene [Q] Quit",
                    current_fps, scene_name
                )
            } else {
                format!("RTX :: {:.1} FPS | [{}] | [Q] Quit", current_fps, scene_name)
            };

            if let Some(pixels) = metal.render(&uniforms) {
                renderer.render_frame(&mut out, pixels, width, canvas_rows, &hud)?;
            }

            let elapsed_frame = now.elapsed();
            if elapsed_frame < target_frame_dur {
                std::thread::sleep(target_frame_dur - elapsed_frame);
            }
        }
    })();

    restore_terminal();
    res
}

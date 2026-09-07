mod metal;
mod renderer;

use std::io::{self, stdout, Write};
use std::panic;
use std::time::{Duration, Instant};

use crossterm::{
    cursor::{Hide, Show},
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, size, Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen},
};

use metal::{MetalRtx, RtxUniforms};
use renderer::TerminalRenderer;

fn restore_terminal() {
    let _ = disable_raw_mode();
    let mut out = stdout();
    let _ = out.write_all(b"\x1b[?2025l\x1b[?7h\x1b[?25h\x1b[0m\x1b[2J");
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
    execute!(out, EnterAlternateScreen, Hide, Clear(ClearType::All))?;
    let _ = out.write_all(b"\x1b[?7l\x1b[2J\x1b[H");
    let _ = out.flush();

    let mut renderer = TerminalRenderer::new();

    let args: Vec<String> = std::env::args().collect();
    let mut fullscreen = args.iter().any(|a| a == "--full" || a == "--fullscreen" || a == "-f");

    let mut scene_id = 0u32;
    let mut quality_mode = 0u32;
    let mut show_hud = true;
    let mut paused = false;

    let mut sim_time = 0.0f32;
    let mut last_instant = Instant::now();

    let mut frame_count = 0u32;
    let mut fps_timer = Instant::now();
    let mut current_fps = 60.0f32;
    let mut last_term_size = size()?;

    let target_frame_dur = Duration::from_micros(16667);

    let res = (|| -> io::Result<()> {
        loop {
            let now = Instant::now();
            let dt = now.duration_since(last_instant).as_secs_f32().min(0.05);
            last_instant = now;

            if !paused {
                sim_time += dt;
            }

            frame_count += 1;
            if fps_timer.elapsed() >= Duration::from_secs(1) {
                current_fps = (frame_count as f32) / fps_timer.elapsed().as_secs_f32();
                frame_count = 0;
                fps_timer = Instant::now();
            }

            while event::poll(Duration::from_millis(0))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        match key.code {
                            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => return Ok(()),
                            KeyCode::Char('1') => scene_id = 0,
                            KeyCode::Char('2') => scene_id = 1,
                            KeyCode::Char('3') => scene_id = 2,
                            KeyCode::Char(' ') => paused = !paused,
                            KeyCode::Char('f') | KeyCode::Char('F') => {
                                fullscreen = !fullscreen;
                                let _ = execute!(out, Clear(ClearType::All));
                            }
                            KeyCode::Char('h') | KeyCode::Char('H') => {
                                show_hud = !show_hud;
                                let _ = execute!(out, Clear(ClearType::All));
                            }
                            KeyCode::Char('t') | KeyCode::Char('T') | KeyCode::Tab => {
                                quality_mode = (quality_mode + 1) % 3;
                            }
                            _ => {}
                        }
                    }
                }
            }

            let term_size = size()?;
            if term_size != last_term_size {
                let _ = execute!(out, Clear(ClearType::All));
                last_term_size = term_size;
            }

            let (cols, rows) = term_size;
            let (view_w, canvas_rows, left_pad, top_pad) = if fullscreen {
                let w = cols as usize;
                let h_rows = (rows as usize).saturating_sub(if show_hud { 2 } else { 1 }).max(5);
                (w, h_rows, 0, 0)
            } else {
                let w = (cols as usize).min(112).max(20);
                let h_rows = (rows as usize).saturating_sub(if show_hud { 2 } else { 1 }).min(36).max(5);
                let lp = ((cols as usize).saturating_sub(w)) / 2;
                let tp = ((rows as usize).saturating_sub(h_rows + if show_hud { 1 } else { 0 })) / 2;
                (w, h_rows, lp, tp)
            };
            let height = canvas_rows * 2;

            let (cam_pos, cam_target) = match scene_id {
                0 => {
                    let angle = sim_time * 0.45;
                    let radius = 2.35f32;
                    let pos = [radius * angle.sin(), 0.65 + 0.12 * (sim_time * 0.25).sin(), -radius * angle.cos()];
                    let target = [0.0f32, 0.18f32, 0.0f32];
                    (pos, target)
                }
                1 => {
                    let angle = sim_time * 0.32;
                    let radius = 2.1f32;
                    let pos = [radius * angle.sin(), 0.4 * (sim_time * 0.2).sin(), -radius * angle.cos()];
                    let target = [0.0f32, 0.0f32, 0.0f32];
                    (pos, target)
                }
                _ => {
                    let angle = sim_time * 0.35;
                    let radius = 2.6f32;
                    let pos = [radius * angle.sin(), 0.65 + 0.15 * (sim_time * 0.2).sin(), -radius * angle.cos()];
                    let target = [0.0f32, 0.1f32, 0.0f32];
                    (pos, target)
                }
            };

            let fwd = [cam_target[0] - cam_pos[0], cam_target[1] - cam_pos[1], cam_target[2] - cam_pos[2]];
            let fwd_len = (fwd[0] * fwd[0] + fwd[1] * fwd[1] + fwd[2] * fwd[2]).sqrt().max(0.001);
            let cam_dir = [fwd[0] / fwd_len, fwd[1] / fwd_len, fwd[2] / fwd_len];

            let world_up = [0.0f32, 1.0f32, 0.0f32];
            let right_raw = [
                cam_dir[1] * world_up[2] - cam_dir[2] * world_up[1],
                cam_dir[2] * world_up[0] - cam_dir[0] * world_up[2],
                cam_dir[0] * world_up[1] - cam_dir[1] * world_up[0],
            ];
            let right_len = (right_raw[0] * right_raw[0] + right_raw[1] * right_raw[1] + right_raw[2] * right_raw[2]).sqrt().max(0.001);
            let cam_right = [right_raw[0] / right_len, right_raw[1] / right_len, right_raw[2] / right_len];

            let cam_up = [
                cam_right[1] * cam_dir[2] - cam_right[2] * cam_dir[1],
                cam_right[2] * cam_dir[0] - cam_right[0] * cam_dir[2],
                cam_right[0] * cam_dir[1] - cam_right[1] * cam_dir[0],
            ];

            let uniforms = RtxUniforms {
                cam_pos,
                cam_dir,
                cam_up,
                cam_right,
                width: view_w as u32,
                height: height as u32,
                time: sim_time,
                scene_id,
                quality_mode,
            };

            let scene_name = match scene_id {
                0 => "1: Hall",
                1 => "2: Mandelbulb",
                _ => "3: Spheres",
            };

            let q_name = match quality_mode {
                0 => "ULTRA 4x",
                1 => "HIGH 2x",
                _ => "FAST 1x",
            };

            let mode_name = if fullscreen { "FULL" } else { "16:9" };

            let hud = if show_hud {
                format!(" RTX {:.0} FPS  │  {}  │  {}  │  {}  │  [Space] Pause  [F] Mode  [H] Hide", current_fps, scene_name, q_name, mode_name)
            } else {
                String::new()
            };

            if let Some(pixels) = metal.render(&uniforms) {
                renderer.render_frame(&mut out, pixels, view_w, canvas_rows, left_pad, top_pad, &hud)?;
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

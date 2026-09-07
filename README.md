# terminal-rtx

Real-time 3D raymarching engine rendering directly to terminal emulators using Rust and Apple Silicon Metal Shading Language (MSL).

## Architecture

- **Compute Pipeline**: Metal compute kernels evaluate signed distance fields (SDF) on Apple Silicon GPU using Unified Memory Architecture (`MTLResourceStorageModeShared`). Framebuffer pointers are accessed by the host runtime without PCIe copy overhead.
- **Rendering**: Employs Unicode Half-Blocks (`\u{2580}`) where foreground and background ANSI 24-bit TrueColor codes double vertical terminal resolution (e.g. a 120x40 character terminal renders a 120x80 pixel viewport).
- **Terminal I/O Optimization**:
  - Direct row addressing (`\x1b[{row};1H`) eliminates newline-induced terminal scrolling.
  - Disabled autowrap (`\x1b[?7l`) prevents line wrapping edge artifacts.
  - DEC Mode 2025 synchronized update sequences (`\x1b[?2025h` / `\x1b[?2025l`) enable atomic frame rendering on supporting terminal emulators.
  - Custom integer serialization minimizes formatting overhead, allowing steady 60 FPS output.

## Shader Capabilities

- **Raymarching**: Bounded-step distance field intersection with analytic surface normals.
- **Antialiasing**: Multi-sample subpixel supersampling (4x Ultra SSAA, 2x High SSAA, 1x Fast Native).
- **Optics & Shading**:
  - PBR Fresnel reflection using Schlick's approximation.
  - Secondary recursive reflection bounce rays.
  - Analytical directional soft shadows with penumbra estimation.
  - Ambient occlusion via geometric distance sampling.
  - ACES filmic tonemapping and sRGB gamma correction.

## Requirements

- macOS 12.0+ running on Apple Silicon (M1/M2/M3/M4 or Pro/Max/Ultra).
- Rust 1.70+.
- Modern terminal emulator supporting 24-bit TrueColor (iTerm2, Terminal.app, Alacritty, Kitty, Ghostty, WezTerm).

## Build & Run

```bash
git clone https://github.com/lonestill/terminal-rtx.git
cd terminal-rtx
cargo run --release
```

Or using the helper script:

```bash
./run.sh
```

## Controls

| Key | Action |
|---|---|
| `Space` | Pause / resume camera orbit rotation |
| `1` / `2` / `3` | Switch scene (`1: Hall`, `2: Mandelbulb`, `3: Spheres`) |
| `T` / `Tab` | Cycle quality mode (`ULTRA 4x` -> `HIGH 2x` -> `FAST 1x`) |
| `H` | Toggle status HUD visibility (full clean screen recording) |
| `Q` / `Esc` | Terminate engine |

## Performance

Tested on Apple M1:

| Quality Mode | GPU Frame Time | Internal Throughput |
|---|---|---|
| **ULTRA 4x SSAA** | 1.2 ms | ~800 FPS |
| **HIGH 2x SSAA** | 0.7 ms | ~1450 FPS |
| **FAST 1x Native** | 0.5 ms | ~2000 FPS |

## License

MIT License. See [LICENSE](LICENSE) for details.

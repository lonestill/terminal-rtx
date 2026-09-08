# terminal-rtx

Real-time 3D raymarching engine rendering directly to terminal emulators using Rust, Apple Silicon Metal, and cross-platform Vulkan compute via WebGPU (wgpu).

## Architecture

- **Compute Pipeline**:
  - **macOS**: Native Apple Silicon Metal compute pipeline using Unified Memory Architecture (`MTLResourceStorageModeShared`).
  - **Linux / Cross-Platform**: Headless Vulkan compute pipeline (`wgpu` + WGSL) supporting AMD Radeon, Intel Arc, and Nvidia GeForce GPUs. Operates headlessly without X11 or Wayland window requirements, streaming raw TrueColor ANSI buffers straight to any terminal.
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

- **macOS**: macOS 12.0+ on Apple Silicon or Intel with Metal.
- **Linux**: Any modern 64-bit Linux distribution with standard Vulkan drivers:
  - **AMD Radeon**: `mesa-vulkan-drivers` (Ubuntu/Debian) or `vulkan-radeon` (Arch Linux).
  - **Intel**: `mesa-vulkan-drivers` (Ubuntu/Debian) or `vulkan-intel` (Arch Linux).
  - **Nvidia**: `nvidia-driver` with Vulkan support.
- **Rust**: 1.70+.
- Modern terminal emulator supporting 24-bit TrueColor (iTerm2, Terminal.app, Alacritty, Kitty, Ghostty, WezTerm, Foot).

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

To render across the entire terminal at full resolution:

```bash
./run.sh --full
# or: cargo run --release -- -f
```

To force the WGPU backend on macOS (testing cross-platform WGSL shader):

```bash
./run.sh --wgpu
# or: cargo run --release -- -w
```

## Controls

| Key | Action |
|---|---|
| `Space` | Pause / resume camera orbit rotation |
| `1` / `2` / `3` | Switch scene (`1: Hall`, `2: Mandelbulb`, `3: Spheres`) |
| `T` / `Tab` | Cycle quality mode (`ULTRA 4x` -> `HIGH 2x` -> `FAST 1x`) |
| `F` | Toggle fullscreen mode (full resolution vs 16:9 cinematic) |
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

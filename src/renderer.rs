use std::io::{self, Write};

pub struct TerminalRenderer {
    buffer: Vec<u8>,
}

impl TerminalRenderer {
    pub fn new() -> Self {
        Self {
            buffer: Vec::with_capacity(128 * 1024),
        }
    }

    pub fn render_frame<W: Write>(
        &mut self,
        writer: &mut W,
        pixels: &[u32],
        width: usize,
        height: usize,
        hud_text: &str,
    ) -> io::Result<()> {
        self.buffer.clear();

        self.buffer.extend_from_slice(b"[H");

        let term_rows = height / 2;

        let mut last_fg = 0xffffffffu32;
        let mut last_bg = 0xffffffffu32;

        for row in 0..term_rows {
            if row == 0 && !hud_text.is_empty() {
                self.buffer.extend_from_slice(b"[0m[1;30;46m ");
                let max_len = width.saturating_sub(2);
                let truncated = if hud_text.len() > max_len {
                    &hud_text[..max_len]
                } else {
                    hud_text
                };
                self.buffer.extend_from_slice(truncated.as_bytes());
                for _ in 0..max_len.saturating_sub(hud_text.len()) {
                    self.buffer.push(b' ');
                }
                self.buffer.extend_from_slice(b" [0m
");
                last_fg = 0xffffffff;
                last_bg = 0xffffffff;
                continue;
            }

            let y_top = row * 2;
            let y_bot = y_top + 1;

            let row_top_offset = y_top * width;
            let row_bot_offset = y_bot * width;

            for col in 0..width {
                let px_top = pixels[row_top_offset + col];
                let px_bot = if y_bot < height {
                    pixels[row_bot_offset + col]
                } else {
                    0
                };

                let fg_rgb = px_top & 0x00ffffff;
                let bg_rgb = px_bot & 0x00ffffff;

                if fg_rgb != last_fg {
                    let r = (fg_rgb & 0xff) as u8;
                    let g = ((fg_rgb >> 8) & 0xff) as u8;
                    let b = ((fg_rgb >> 16) & 0xff) as u8;
                    write!(self.buffer, "[38;2;{};{};{}m", r, g, b)?;
                    last_fg = fg_rgb;
                }

                if bg_rgb != last_bg {
                    let r = (bg_rgb & 0xff) as u8;
                    let g = ((bg_rgb >> 8) & 0xff) as u8;
                    let b = ((bg_rgb >> 16) & 0xff) as u8;
                    write!(self.buffer, "[48;2;{};{};{}m", r, g, b)?;
                    last_bg = bg_rgb;
                }

                self.buffer.extend_from_slice("▀".as_bytes());
            }

            if row + 1 < term_rows {
                self.buffer.extend_from_slice(b"
");
            }
        }

        self.buffer.extend_from_slice(b"[0m");
        writer.write_all(&self.buffer)?;
        writer.flush()?;
        Ok(())
    }
}

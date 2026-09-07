use std::io::{self, Write};

#[inline(always)]
fn push_u16(buf: &mut Vec<u8>, mut val: u16) {
    if val == 0 {
        buf.push(b'0');
        return;
    }
    let mut temp = [0u8; 5];
    let mut idx = 0;
    while val > 0 {
        temp[idx] = b'0' + (val % 10) as u8;
        val /= 10;
        idx += 1;
    }
    while idx > 0 {
        idx -= 1;
        buf.push(temp[idx]);
    }
}

#[inline(always)]
fn push_u8(buf: &mut Vec<u8>, val: u8) {
    if val >= 100 {
        buf.push(b'0' + val / 100);
        buf.push(b'0' + (val / 10) % 10);
        buf.push(b'0' + val % 10);
    } else if val >= 10 {
        buf.push(b'0' + val / 10);
        buf.push(b'0' + val % 10);
    } else {
        buf.push(b'0' + val);
    }
}

#[inline(always)]
fn push_fg(buf: &mut Vec<u8>, r: u8, g: u8, b: u8) {
    buf.extend_from_slice(b"\x1b[38;2;");
    push_u8(buf, r);
    buf.push(b';');
    push_u8(buf, g);
    buf.push(b';');
    push_u8(buf, b);
    buf.push(b'm');
}

#[inline(always)]
fn push_bg(buf: &mut Vec<u8>, r: u8, g: u8, b: u8) {
    buf.extend_from_slice(b"\x1b[48;2;");
    push_u8(buf, r);
    buf.push(b';');
    push_u8(buf, g);
    buf.push(b';');
    push_u8(buf, b);
    buf.push(b'm');
}

pub struct TerminalRenderer {
    buffer: Vec<u8>,
}

impl TerminalRenderer {
    pub fn new() -> Self {
        Self {
            buffer: Vec::with_capacity(256 * 1024),
        }
    }

    pub fn render_frame<W: Write>(
        &mut self,
        writer: &mut W,
        pixels: &[u32],
        width: usize,
        canvas_rows: usize,
        left_pad: usize,
        top_pad: usize,
        hud_text: &str,
    ) -> io::Result<()> {
        self.buffer.clear();
        self.buffer.extend_from_slice(b"\x1b[?2025h");

        let start_row = if !hud_text.is_empty() {
            let hud_line = (top_pad + 1) as u16;
            let hud_col = (left_pad + 1) as u16;
            self.buffer.extend_from_slice(b"\x1b[");
            push_u16(&mut self.buffer, hud_line);
            self.buffer.push(b';');
            push_u16(&mut self.buffer, hud_col);
            self.buffer.extend_from_slice(b"H\x1b[0m\x1b[48;2;16;18;24m\x1b[38;2;220;225;235m ");
            let max_hud_chars = width.saturating_sub(2);
            let mut char_count = 0;
            for c in hud_text.chars() {
                if char_count >= max_hud_chars {
                    break;
                }
                let mut b = [0u8; 4];
                self.buffer.extend_from_slice(c.encode_utf8(&mut b).as_bytes());
                char_count += 1;
            }
            while char_count < max_hud_chars {
                self.buffer.push(b' ');
                char_count += 1;
            }
            self.buffer.extend_from_slice(b" \x1b[0m");
            (top_pad + 2) as u16
        } else {
            (top_pad + 1) as u16
        };

        let term_col = (left_pad + 1) as u16;

        let mut last_fg = 0xffffffffu32;
        let mut last_bg = 0xffffffffu32;

        let height = canvas_rows * 2;

        for row_idx in 0..canvas_rows {
            let term_line = start_row + row_idx as u16;
            self.buffer.extend_from_slice(b"\x1b[");
            push_u16(&mut self.buffer, term_line);
            self.buffer.push(b';');
            push_u16(&mut self.buffer, term_col);
            self.buffer.extend_from_slice(b"H");

            let y_top = row_idx * 2;
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
                    push_fg(&mut self.buffer, r, g, b);
                    last_fg = fg_rgb;
                }
                if bg_rgb != last_bg {
                    let r = (bg_rgb & 0xff) as u8;
                    let g = ((bg_rgb >> 8) & 0xff) as u8;
                    let b = ((bg_rgb >> 16) & 0xff) as u8;
                    push_bg(&mut self.buffer, r, g, b);
                    last_bg = bg_rgb;
                }
                self.buffer.extend_from_slice("▀".as_bytes());
            }
        }

        self.buffer.extend_from_slice(b"\x1b[0m\x1b[?2025l");
        writer.write_all(&self.buffer)?;
        writer.flush()?;
        Ok(())
    }
}

use std::ffi::CString;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct RtxUniforms {
    pub cam_pos: [f32; 3],
    pub cam_dir: [f32; 3],
    pub cam_up: [f32; 3],
    pub cam_right: [f32; 3],
    pub width: u32,
    pub height: u32,
    pub time: f32,
    pub scene_id: u32,
}

extern "C" {
    fn metal_rtx_init(msl_source: *const std::os::raw::c_char) -> i32;
    fn metal_rtx_render(uniforms: *const RtxUniforms) -> i32;
    fn metal_rtx_get_pixel_buffer() -> *const u32;
    fn metal_rtx_release();
}

pub struct MetalRtx;

impl MetalRtx {
    pub fn init() -> Option<Self> {
        let msl = include_str!("../metal/rtx.metal");
        let c_str = CString::new(msl).ok()?;
        let ret = unsafe { metal_rtx_init(c_str.as_ptr()) };
        if ret == 0 {
            Some(Self)
        } else {
            None
        }
    }

    pub fn render(&mut self, uniforms: &RtxUniforms) -> Option<&[u32]> {
        let ret = unsafe { metal_rtx_render(uniforms) };
        if ret != 0 {
            return None;
        }

        let ptr = unsafe { metal_rtx_get_pixel_buffer() };
        if ptr.is_null() {
            return None;
        }

        let len = (uniforms.width as usize) * (uniforms.height as usize);
        let slice = unsafe { std::slice::from_raw_parts(ptr, len) };
        Some(slice)
    }
}

impl Drop for MetalRtx {
    fn drop(&mut self) {
        unsafe {
            metal_rtx_release();
        }
    }
}

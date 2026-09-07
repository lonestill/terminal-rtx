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
    pub quality_mode: u32,
}

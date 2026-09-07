use pollster::FutureExt;
use crate::uniforms::RtxUniforms;

#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuUniforms {
    cam_pos: [f32; 3],
    _pad0: f32,
    cam_dir: [f32; 3],
    _pad1: f32,
    cam_up: [f32; 3],
    _pad2: f32,
    cam_right: [f32; 3],
    _pad3: f32,
    width: u32,
    height: u32,
    time: f32,
    scene_id: u32,
    quality_mode: u32,
    _pad4: u32,
    _pad5: u32,
    _pad6: u32,
}

pub struct WgpuRtx {
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::ComputePipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    uniform_buf: wgpu::Buffer,
    storage_buf: Option<wgpu::Buffer>,
    staging_buf: Option<wgpu::Buffer>,
    bind_group: Option<wgpu::BindGroup>,
    current_w: u32,
    current_h: u32,
    pixel_cache: Vec<u32>,
    pub adapter_name: String,
}

impl WgpuRtx {
    pub fn init() -> Option<Self> {
        let instance = wgpu::Instance::default();
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
                ..Default::default()
            })
            .block_on()
            .ok()?;

        let adapter_name = adapter.get_info().name;

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor::default())
            .block_on()
            .ok()?;

        let shader_src = include_str!("../shaders/rtx.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: None,
            source: wgpu::ShaderSource::Wgsl(shader_src.into()),
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: None,
            layout: None,
            module: &shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        let bind_group_layout = pipeline.get_bind_group_layout(0);
        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: std::mem::size_of::<GpuUniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Some(Self {
            device,
            queue,
            pipeline,
            bind_group_layout,
            uniform_buf,
            storage_buf: None,
            staging_buf: None,
            bind_group: None,
            current_w: 0,
            current_h: 0,
            pixel_cache: Vec::new(),
            adapter_name,
        })
    }

    pub fn render(&mut self, uniforms: &RtxUniforms) -> Option<&[u32]> {
        let w = uniforms.width;
        let h = uniforms.height;
        let pixel_count = (w as usize) * (h as usize);
        let byte_size = (pixel_count * 4) as u64;

        if self.current_w != w || self.current_h != h || self.storage_buf.is_none() {
            let storage = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size: byte_size,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let staging = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size: byte_size,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let bg = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: self.uniform_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: storage.as_entire_binding(),
                    },
                ],
            });

            self.storage_buf = Some(storage);
            self.staging_buf = Some(staging);
            self.bind_group = Some(bg);
            self.current_w = w;
            self.current_h = h;
            self.pixel_cache.resize(pixel_count, 0);
        }

        let gpu_uniforms = GpuUniforms {
            cam_pos: uniforms.cam_pos,
            _pad0: 0.0,
            cam_dir: uniforms.cam_dir,
            _pad1: 0.0,
            cam_up: uniforms.cam_up,
            _pad2: 0.0,
            cam_right: uniforms.cam_right,
            _pad3: 0.0,
            width: w,
            height: h,
            time: uniforms.time,
            scene_id: uniforms.scene_id,
            quality_mode: uniforms.quality_mode,
            _pad4: 0,
            _pad5: 0,
            _pad6: 0,
        };

        self.queue.write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&gpu_uniforms));

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, self.bind_group.as_ref()?, &[]);
            let workgroups_x = (w + 15) / 16;
            let workgroups_y = (h + 15) / 16;
            pass.dispatch_workgroups(workgroups_x, workgroups_y, 1);
        }

        encoder.copy_buffer_to_buffer(self.storage_buf.as_ref()?, 0, self.staging_buf.as_ref()?, 0, byte_size);
        self.queue.submit(Some(encoder.finish()));

        let staging = self.staging_buf.as_ref()?;
        let slice = staging.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |res| {
            let _ = tx.send(res);
        });
        let _ = self.device.poll(wgpu::PollType::wait_indefinitely());
        rx.recv().ok()?.ok()?;

        let data = slice.get_mapped_range().ok()?;
        let u32_slice: &[u32] = bytemuck::cast_slice(&data);
        self.pixel_cache.copy_from_slice(u32_slice);
        drop(data);
        staging.unmap();

        Some(&self.pixel_cache)
    }
}

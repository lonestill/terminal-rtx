pub struct Camera {
    pub pos: [f32; 3],
    pub yaw: f32,
    pub pitch: f32,
}

impl Camera {
    pub fn new() -> Self {
        Self {
            pos: [0.0, 0.75, -2.4],
            yaw: 1.57079,
            pitch: -0.15,
        }
    }

    pub fn dir(&self) -> [f32; 3] {
        let cp = self.pitch.cos();
        let sp = self.pitch.sin();
        let cy = self.yaw.cos();
        let sy = self.yaw.sin();
        [cp * cy, sp, cp * sy]
    }

    pub fn right(&self) -> [f32; 3] {
        let cy = self.yaw.cos();
        let sy = self.yaw.sin();
        [-sy, 0.0, cy]
    }

    pub fn up(&self) -> [f32; 3] {
        let d = self.dir();
        let r = self.right();
        [
            r[1] * d[2] - r[2] * d[1],
            r[2] * d[0] - r[0] * d[2],
            r[0] * d[1] - r[1] * d[0],
        ]
    }

    pub fn move_forward(&mut self, dist: f32) {
        let d = self.dir();
        self.pos[0] += d[0] * dist;
        self.pos[1] += d[1] * dist;
        self.pos[2] += d[2] * dist;
    }

    pub fn move_right(&mut self, dist: f32) {
        let r = self.right();
        self.pos[0] += r[0] * dist;
        self.pos[1] += r[1] * dist;
        self.pos[2] += r[2] * dist;
    }

    pub fn move_up(&mut self, dist: f32) {
        self.pos[1] += dist;
    }

    pub fn rotate(&mut self, dyaw: f32, dpitch: f32) {
        self.yaw += dyaw;
        self.pitch = (self.pitch + dpitch).clamp(-1.45, 1.45);
    }
}

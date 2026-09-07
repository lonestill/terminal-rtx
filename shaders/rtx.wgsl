struct Uniforms {
    cam_pos: vec3<f32>,
    _pad0: f32,
    cam_dir: vec3<f32>,
    _pad1: f32,
    cam_up: vec3<f32>,
    _pad2: f32,
    cam_right: vec3<f32>,
    _pad3: f32,
    width: u32,
    height: u32,
    time: f32,
    scene_id: u32,
    quality_mode: u32,
    _pad4: u32,
    _pad5: u32,
    _pad6: u32,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read_write> pixels: array<u32>;

fn rotate_y(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

fn rotate_x(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

fn sd_sphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sd_box(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn sd_torus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sd_plane(p: vec3<f32>, h: f32) -> f32 {
    return p.y - h;
}

fn sd_mandelbulb(p: vec3<f32>, power: f32) -> f32 {
    var z = p;
    var dr = 1.0;
    var r = 0.0;
    for (var i = 0; i < 4; i++) {
        r = length(z);
        if (r > 4.0) {
            break;
        }
        let theta = acos(clamp(z.z / r, -1.0, 1.0));
        let phi = atan2(z.y, z.x);
        dr = pow(r, power - 1.0) * power * dr + 1.0;
        let zr = pow(r, power);
        let th_p = theta * power;
        let ph_p = phi * power;
        z = zr * vec3<f32>(sin(th_p) * cos(ph_p), sin(ph_p) * sin(th_p), cos(th_p)) + p;
    }
    return 0.5 * log(r) * r / dr;
}

fn fmod_val(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn map_scene(p: vec3<f32>, scene_id: u32, time: f32) -> vec2<f32> {
    if (scene_id == 1u) {
        let rot_p = rotate_y(rotate_x(p, time * 0.2), time * 0.3);
        let d_bulb = sd_mandelbulb(rot_p * 0.9, 8.0 + sin(time * 0.5) * 0.5);
        return vec2<f32>(d_bulb / 0.9, 6.0);
    } else if (scene_id == 2u) {
        let d_floor = sd_plane(p, -1.2);
        var rep_p = p;
        rep_p.x = fmod_val(abs(rep_p.x) + 2.0, 4.0) - 2.0;
        rep_p.z = fmod_val(abs(rep_p.z) + 2.0, 4.0) - 2.0;
        let d_sphere = sd_sphere(rep_p - vec3<f32>(0.0, -0.2, 0.0), 0.9);
        if (d_floor < d_sphere) {
            return vec2<f32>(d_floor, 1.0);
        } else {
            return vec2<f32>(d_sphere, 5.0);
        }
    }

    let d_floor = sd_plane(p, -1.0);
    let rot_p = rotate_y(rotate_x(p - vec3<f32>(0.0, 0.2 + sin(time) * 0.15, 0.0), time * 0.7), time * 0.5);
    let d_torus = sd_torus(rot_p, vec2<f32>(0.85, 0.28));

    let s_pos = vec3<f32>(sin(time * 1.5) * 1.8, 0.2, cos(time * 1.5) * 1.8);
    let d_sphere = sd_sphere(p - s_pos, 0.4);

    let c1_pos = vec3<f32>(-2.8, 0.5, 1.5);
    let d_col1 = sd_box(p - c1_pos, vec3<f32>(0.2, 1.5, 0.2));

    let c2_pos = vec3<f32>(2.8, 0.5, -1.5);
    let d_col2 = sd_box(p - c2_pos, vec3<f32>(0.2, 1.5, 0.2));

    var min_d = d_floor;
    var mat = 1.0;

    if (d_torus < min_d) {
        min_d = d_torus;
        mat = 2.0;
    }
    if (d_sphere < min_d) {
        min_d = d_sphere;
        mat = 5.0;
    }
    if (d_col1 < min_d) {
        min_d = d_col1;
        mat = 3.0;
    }
    if (d_col2 < min_d) {
        min_d = d_col2;
        mat = 4.0;
    }

    return vec2<f32>(min_d, mat);
}

fn calc_normal(p: vec3<f32>, scene_id: u32, time: f32) -> vec3<f32> {
    let e = 0.0015;
    let dx = map_scene(p + vec3<f32>(e, 0.0, 0.0), scene_id, time).x - map_scene(p - vec3<f32>(e, 0.0, 0.0), scene_id, time).x;
    let dy = map_scene(p + vec3<f32>(0.0, e, 0.0), scene_id, time).x - map_scene(p - vec3<f32>(0.0, e, 0.0), scene_id, time).x;
    let dz = map_scene(p + vec3<f32>(0.0, 0.0, e), scene_id, time).x - map_scene(p - vec3<f32>(0.0, 0.0, e), scene_id, time).x;
    return normalize(vec3<f32>(dx, dy, dz));
}

fn calc_soft_shadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32, scene_id: u32, time: f32) -> f32 {
    var res = 1.0;
    var t = mint;
    for (var i = 0; i < 28; i++) {
        let h = map_scene(ro + rd * t, scene_id, time).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.2);
        if (res < 0.02 || t > maxt) {
            break;
        }
    }
    return clamp(res, 0.0, 1.0);
}

fn calc_ao(p: vec3<f32>, n: vec3<f32>, scene_id: u32, time: f32) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 0; i < 6; i++) {
        let h = 0.01 + 0.15 * f32(i) / 5.0;
        let d = map_scene(p + h * n, scene_id, time).x;
        occ += (h - d) * sca;
        sca *= 0.88;
    }
    return clamp(1.0 - 2.8 * occ, 0.0, 1.0);
}

fn shade_surface(
    p: vec3<f32>,
    n: vec3<f32>,
    rd: vec3<f32>,
    mat: f32,
    light1_pos: vec3<f32>,
    light1_col: vec3<f32>,
    light2_pos: vec3<f32>,
    light2_col: vec3<f32>,
    scene_id: u32,
    time: f32
) -> vec3<f32> {
    if (mat == 3.0) {
        let stripe = smoothstep(0.15, 0.25, abs(sin(p.y * 5.0 + time * 2.0)));
        return mix(vec3<f32>(0.05, 0.12, 0.2), vec3<f32>(0.3, 2.2, 3.2), stripe);
    }
    if (mat == 4.0) {
        let stripe = smoothstep(0.15, 0.25, abs(sin(p.y * 5.0 - time * 2.0)));
        return mix(vec3<f32>(0.2, 0.05, 0.12), vec3<f32>(3.2, 0.3, 2.2), stripe);
    }

    var base_col = vec3<f32>(0.8);
    var metallic = 0.0;
    var roughness = 0.3;

    if (mat == 1.0) {
        let tile = abs(fract(p.xz * 0.5) - 0.5);
        let seam = smoothstep(0.015, 0.04, min(tile.x, tile.y));
        let checker = fmod_val(floor(p.x * 0.5) + floor(p.z * 0.5), 2.0);
        let tile_col = select(vec3<f32>(0.26, 0.27, 0.32), vec3<f32>(0.12, 0.13, 0.16), checker == 0.0);
        base_col = mix(vec3<f32>(0.02, 0.02, 0.03), tile_col, seam);
        metallic = 0.8;
        roughness = mix(0.45, 0.1, seam);
    } else if (mat == 2.0) {
        base_col = vec3<f32>(1.0, 0.82, 0.32);
        metallic = 0.95;
        roughness = 0.08;
    } else if (mat == 5.0) {
        base_col = vec3<f32>(0.92, 0.95, 1.0);
        metallic = 0.98;
        roughness = 0.04;
    } else if (mat == 6.0) {
        let d_center = length(p);
        base_col = vec3<f32>(
            0.5 + 0.5 * sin(d_center * 3.5 + time * 0.4),
            0.5 + 0.5 * sin(d_center * 3.5 + 2.09 + time * 0.4),
            0.5 + 0.5 * sin(d_center * 3.5 + 4.18 + time * 0.4)
        );
        metallic = 0.35;
        roughness = 0.35;
    }

    let ao = calc_ao(p, n, scene_id, time);

    var l1_dir = light1_pos - p;
    let l1_dist = length(l1_dir);
    l1_dir /= max(l1_dist, 0.001);
    let l1_att = 1.0 / (1.0 + 0.15 * l1_dist + 0.08 * l1_dist * l1_dist);
    let l1_diff = max(dot(n, l1_dir), 0.0);
    var l1_shadow = 0.0;
    if (l1_diff > 0.0) {
        l1_shadow = calc_soft_shadow(p + n * 0.01, l1_dir, 0.02, l1_dist, 8.0, scene_id, time);
    }
    let h1 = normalize(l1_dir - rd);
    let l1_spec = pow(max(dot(n, h1), 0.0), (1.0 - roughness) * 48.0 + 8.0);

    var l2_dir = light2_pos - p;
    let l2_dist = length(l2_dir);
    l2_dir /= max(l2_dist, 0.001);
    let l2_att = 1.0 / (1.0 + 0.15 * l2_dist + 0.08 * l2_dist * l2_dist);
    let l2_diff = max(dot(n, l2_dir), 0.0);
    var l2_shadow = 0.0;
    if (l2_diff > 0.0) {
        l2_shadow = calc_soft_shadow(p + n * 0.01, l2_dir, 0.02, l2_dist, 8.0, scene_id, time);
    }
    let h2 = normalize(l2_dir - rd);
    let l2_spec = pow(max(dot(n, h2), 0.0), (1.0 - roughness) * 48.0 + 8.0);

    let ambient = vec3<f32>(0.03, 0.04, 0.07) * ao;
    let light_diffuse = (light1_col * l1_diff * l1_att * l1_shadow + light2_col * l2_diff * l2_att * l2_shadow);
    let light_spec = (light1_col * l1_spec * l1_att * l1_shadow + light2_col * l2_spec * l2_att * l2_shadow);

    return ambient * base_col + light_diffuse * base_col * (1.0 - metallic) + light_spec;
}

fn tonemap_aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn trace_ray(
    ro: vec3<f32>,
    rd: vec3<f32>,
    light1_pos: vec3<f32>,
    light1_col: vec3<f32>,
    light2_pos: vec3<f32>,
    light2_col: vec3<f32>,
    scene_id: u32,
    time: f32
) -> vec3<f32> {
    var t = 0.0;
    var mat = 0.0;
    var hit = false;

    for (var i = 0; i < 75; i++) {
        let p = ro + rd * t;
        let res = map_scene(p, scene_id, time);
        if (res.x < 0.0015) {
            hit = true;
            mat = res.y;
            break;
        }
        t += res.x;
        if (t > 28.0) {
            break;
        }
    }

    let v1 = light1_pos - ro;
    let proj1 = max(dot(v1, rd), 0.0);
    let d1 = length(light1_pos - (ro + rd * proj1));
    var glow = light1_col * (0.025 / (d1 * d1 + 0.05));

    let v2 = light2_pos - ro;
    let proj2 = max(dot(v2, rd), 0.0);
    let d2 = length(light2_pos - (ro + rd * proj2));
    glow += light2_col * (0.025 / (d2 * d2 + 0.05));

    var col = vec3<f32>(0.004, 0.006, 0.012) + vec3<f32>(0.008, 0.015, 0.03) * max(-rd.y, 0.0) + glow;

    if (hit) {
        let p = ro + rd * t;
        let n = calc_normal(p, scene_id, time);
        col = shade_surface(p, n, rd, mat, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);

        if (mat == 1.0 || mat == 2.0 || mat == 5.0) {
            let f0 = select(0.06, 0.9, mat == 5.0 || mat == 2.0);
            let cos_t = clamp(dot(n, -rd), 0.0, 1.0);
            let fresnel = f0 + (1.0 - f0) * pow(1.0 - cos_t, 5.0);

            let r_rd = reflect(rd, n);
            let r_ro = p + n * 0.012;
            var r_t = 0.0;
            var r_mat = 0.0;
            var r_hit = false;

            for (var j = 0; j < 32; j++) {
                let rp = r_ro + r_rd * r_t;
                let r_res = map_scene(rp, scene_id, time);
                if (r_res.x < 0.002) {
                    r_hit = true;
                    r_mat = r_res.y;
                    break;
                }
                r_t += r_res.x;
                if (r_t > 20.0) {
                    break;
                }
            }

            var refl_col = vec3<f32>(0.008, 0.012, 0.025);
            if (r_hit) {
                let rp = r_ro + r_rd * r_t;
                let rn = calc_normal(rp, scene_id, time);
                refl_col = shade_surface(rp, rn, r_rd, r_mat, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
            }
            col = mix(col, refl_col, fresnel);
        }
    }

    return col;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= uniforms.width || id.y >= uniforms.height) {
        return;
    }

    let w = f32(uniforms.width);
    let h = f32(uniforms.height);
    let x = f32(id.x);
    let y = f32(id.y);

    let cam_pos = uniforms.cam_pos;
    let cam_dir = uniforms.cam_dir;
    let cam_up = uniforms.cam_up;
    let cam_right = uniforms.cam_right;

    let time = uniforms.time;
    let scene_id = uniforms.scene_id;
    let quality = uniforms.quality_mode;

    let light1_pos = vec3<f32>(sin(time * 0.9) * 2.5, 1.8, cos(time * 0.9) * 2.5);
    let light1_col = vec3<f32>(0.3, 1.2, 1.8);

    let light2_pos = vec3<f32>(sin(time * 0.8 + 3.14) * 2.5, 1.5, cos(time * 0.8 + 3.14) * 2.5);
    let light2_col = vec3<f32>(1.8, 0.3, 1.2);

    var col = vec3<f32>(0.0);

    if (quality == 0u) {
        let offsets = array<vec2<f32>, 4>(
            vec2<f32>(-0.25, -0.25),
            vec2<f32>( 0.25, -0.25),
            vec2<f32>(-0.25,  0.25),
            vec2<f32>( 0.25,  0.25)
        );
        for (var s = 0; s < 4; s++) {
            let sx = x + offsets[s].x;
            let sy = y + offsets[s].y;
            let uv_x = (2.0 * sx - w) / h;
            let uv_y = (h - 2.0 * sy) / h;
            let rd = normalize(cam_dir + uv_x * cam_right * 0.8 + uv_y * cam_up * 0.8);
            col += trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
        }
        col *= 0.25;
    } else if (quality == 1u) {
        let offsets = array<vec2<f32>, 2>(
            vec2<f32>(-0.25,  0.25),
            vec2<f32>( 0.25, -0.25)
        );
        for (var s = 0; s < 2; s++) {
            let sx = x + offsets[s].x;
            let sy = y + offsets[s].y;
            let uv_x = (2.0 * sx - w) / h;
            let uv_y = (h - 2.0 * sy) / h;
            let rd = normalize(cam_dir + uv_x * cam_right * 0.8 + uv_y * cam_up * 0.8);
            col += trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
        }
        col *= 0.5;
    } else {
        let uv_x = (2.0 * x - w) / h;
        let uv_y = (h - 2.0 * y) / h;
        let rd = normalize(cam_dir + uv_x * cam_right * 0.8 + uv_y * cam_up * 0.8);
        col = trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
    }

    col = tonemap_aces(col);
    col = smoothstep(vec3<f32>(0.0), vec3<f32>(1.0), col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    let ir = u32(clamp(col.r * 255.0, 0.0, 255.0));
    let ig = u32(clamp(col.g * 255.0, 0.0, 255.0));
    let ib = u32(clamp(col.b * 255.0, 0.0, 255.0));

    pixels[id.y * uniforms.width + id.x] = ir | (ig << 8u) | (ib << 16u) | 0xff000000u;
}

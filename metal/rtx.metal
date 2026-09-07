#include <metal_stdlib>
using namespace metal;

struct RtxUniforms {
    float cam_pos[3];
    float cam_dir[3];
    float cam_up[3];
    float cam_right[3];
    uint32_t width;
    uint32_t height;
    float time;
    uint32_t scene_id;
    uint32_t quality_mode;
};

static inline float3 rotate_y(float3 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

static inline float3 rotate_x(float3 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

static inline float sd_sphere(float3 p, float r) {
    return length(p) - r;
}

static inline float sd_box(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return length(max(d, 0.0f)) + min(max(d.x, max(d.y, d.z)), 0.0f);
}

static inline float sd_torus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

static inline float sd_plane(float3 p, float h) {
    return p.y - h;
}

static inline float sd_mandelbulb(float3 p, float power, thread float& trap) {
    float3 z = p;
    float dr = 1.0f;
    float r = 0.0f;
    trap = 1e10f;
    for (int i = 0; i < 4; ++i) {
        r = length(z);
        if (r > 4.0f) break;
        trap = min(trap, r);
        float theta = acos(clamp(z.z / r, -1.0f, 1.0f));
        float phi = atan2(z.y, z.x);
        dr = pow(r, power - 1.0f) * power * dr + 1.0f;
        float zr = pow(r, power);
        theta = theta * power;
        phi = phi * power;
        z = zr * float3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta)) + p;
    }
    return 0.5f * log(r) * r / dr;
}

static inline float2 map_scene(float3 p, uint32_t scene_id, float time) {
    if (scene_id == 1) {
        float trap = 0.0f;
        float3 rot_p = rotate_y(rotate_x(p, time * 0.2f), time * 0.3f);
        float d_bulb = sd_mandelbulb(rot_p * 0.9f, 8.0f + sin(time * 0.5f) * 0.5f, trap);
        return float2(d_bulb / 0.9f, 6.0f);
    } else if (scene_id == 2) {
        float d_floor = sd_plane(p, -1.2f);
        float3 rep_p = p;
        rep_p.x = fmod(abs(rep_p.x) + 2.0f, 4.0f) - 2.0f;
        rep_p.z = fmod(abs(rep_p.z) + 2.0f, 4.0f) - 2.0f;
        float d_sphere = sd_sphere(rep_p - float3(0.0f, -0.2f, 0.0f), 0.9f);
        if (d_floor < d_sphere) {
            return float2(d_floor, 1.0f);
        } else {
            return float2(d_sphere, 5.0f);
        }
    }

    float d_floor = sd_plane(p, -1.0f);

    float3 rot_p = rotate_y(rotate_x(p - float3(0.0f, 0.2f + sin(time) * 0.15f, 0.0f), time * 0.7f), time * 0.5f);
    float d_torus = sd_torus(rot_p, float2(0.85f, 0.28f));

    float3 s_pos = float3(sin(time * 1.5f) * 1.8f, 0.2f, cos(time * 1.5f) * 1.8f);
    float d_sphere = sd_sphere(p - s_pos, 0.4f);

    float3 c1_pos = float3(-2.8f, 0.5f, 1.5f);
    float d_col1 = sd_box(p - c1_pos, float3(0.2f, 1.5f, 0.2f));

    float3 c2_pos = float3(2.8f, 0.5f, -1.5f);
    float d_col2 = sd_box(p - c2_pos, float3(0.2f, 1.5f, 0.2f));

    float min_d = d_floor;
    float mat = 1.0f;

    if (d_torus < min_d) {
        min_d = d_torus;
        mat = 2.0f;
    }
    if (d_sphere < min_d) {
        min_d = d_sphere;
        mat = 5.0f;
    }
    if (d_col1 < min_d) {
        min_d = d_col1;
        mat = 3.0f;
    }
    if (d_col2 < min_d) {
        min_d = d_col2;
        mat = 4.0f;
    }

    return float2(min_d, mat);
}

static inline float3 calc_normal(float3 p, uint32_t scene_id, float time) {
    float2 e = float2(0.0015f, 0.0f);
    return normalize(float3(
        map_scene(p + e.xyy, scene_id, time).x - map_scene(p - e.xyy, scene_id, time).x,
        map_scene(p + e.yxy, scene_id, time).x - map_scene(p - e.yxy, scene_id, time).x,
        map_scene(p + e.yyx, scene_id, time).x - map_scene(p - e.yyx, scene_id, time).x
    ));
}

static inline float calc_soft_shadow(float3 ro, float3 rd, float mint, float maxt, float k, uint32_t scene_id, float time) {
    float res = 1.0f;
    float t = mint;
    for (int i = 0; i < 28; ++i) {
        float h = map_scene(ro + rd * t, scene_id, time).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.02f, 0.2f);
        if (res < 0.02f || t > maxt) break;
    }
    return clamp(res, 0.0f, 1.0f);
}

static inline float calc_ao(float3 p, float3 n, uint32_t scene_id, float time) {
    float occ = 0.0f;
    float sca = 1.0f;
    for (int i = 0; i < 6; ++i) {
        float h = 0.01f + 0.15f * (float)i / 5.0f;
        float d = map_scene(p + h * n, scene_id, time).x;
        occ += (h - d) * sca;
        sca *= 0.88f;
    }
    return clamp(1.0f - 2.8f * occ, 0.0f, 1.0f);
}

static inline float3 shade_surface(
    float3 p,
    float3 n,
    float3 rd,
    float mat,
    float3 light1_pos,
    float3 light1_col,
    float3 light2_pos,
    float3 light2_col,
    uint32_t scene_id,
    float time
) {
    if (mat == 3.0f) {
        float stripe = smoothstep(0.15f, 0.25f, abs(sin(p.y * 5.0f + time * 2.0f)));
        return mix(float3(0.05f, 0.12f, 0.2f), float3(0.3f, 2.2f, 3.2f), stripe);
    }
    if (mat == 4.0f) {
        float stripe = smoothstep(0.15f, 0.25f, abs(sin(p.y * 5.0f - time * 2.0f)));
        return mix(float3(0.2f, 0.05f, 0.12f), float3(3.2f, 0.3f, 2.2f), stripe);
    }

    float3 base_col = float3(0.8f);
    float metallic = 0.0f;
    float roughness = 0.3f;

    if (mat == 1.0f) {
        float2 tile = abs(fract(p.xz * 0.5f) - 0.5f);
        float seam = smoothstep(0.015f, 0.04f, min(tile.x, tile.y));
        float checker = fmod(floor(p.x * 0.5f) + floor(p.z * 0.5f), 2.0f);
        base_col = mix(float3(0.02f, 0.02f, 0.03f), (checker == 0.0f ? float3(0.12f, 0.13f, 0.16f) : float3(0.26f, 0.27f, 0.32f)), seam);
        metallic = 0.8f;
        roughness = mix(0.45f, 0.1f, seam);
    } else if (mat == 2.0f) {
        base_col = float3(1.0f, 0.82f, 0.32f);
        metallic = 0.95f;
        roughness = 0.08f;
    } else if (mat == 5.0f) {
        base_col = float3(0.92f, 0.95f, 1.0f);
        metallic = 0.98f;
        roughness = 0.04f;
    } else if (mat == 6.0f) {
        float d_center = length(p);
        base_col = float3(
            0.5f + 0.5f * sin(d_center * 3.5f + time * 0.4f),
            0.5f + 0.5f * sin(d_center * 3.5f + 2.09f + time * 0.4f),
            0.5f + 0.5f * sin(d_center * 3.5f + 4.18f + time * 0.4f)
        );
        metallic = 0.35f;
        roughness = 0.35f;
    }

    float ao = calc_ao(p, n, scene_id, time);

    float3 l1_dir = light1_pos - p;
    float l1_dist = length(l1_dir);
    l1_dir /= max(l1_dist, 0.001f);
    float l1_att = 1.0f / (1.0f + 0.15f * l1_dist + 0.08f * l1_dist * l1_dist);
    float l1_diff = max(dot(n, l1_dir), 0.0f);
    float l1_shadow = (l1_diff > 0.0f) ? calc_soft_shadow(p + n * 0.01f, l1_dir, 0.02f, l1_dist, 8.0f, scene_id, time) : 0.0f;
    float3 h1 = normalize(l1_dir - rd);
    float l1_spec = pow(max(dot(n, h1), 0.0f), (1.0f - roughness) * 48.0f + 8.0f);

    float3 l2_dir = light2_pos - p;
    float l2_dist = length(l2_dir);
    l2_dir /= max(l2_dist, 0.001f);
    float l2_att = 1.0f / (1.0f + 0.15f * l2_dist + 0.08f * l2_dist * l2_dist);
    float l2_diff = max(dot(n, l2_dir), 0.0f);
    float l2_shadow = (l2_diff > 0.0f) ? calc_soft_shadow(p + n * 0.01f, l2_dir, 0.02f, l2_dist, 8.0f, scene_id, time) : 0.0f;
    float3 h2 = normalize(l2_dir - rd);
    float l2_spec = pow(max(dot(n, h2), 0.0f), (1.0f - roughness) * 48.0f + 8.0f);

    float3 ambient = float3(0.03f, 0.04f, 0.07f) * ao;
    float3 light_diffuse = (light1_col * l1_diff * l1_att * l1_shadow + light2_col * l2_diff * l2_att * l2_shadow);
    float3 light_spec = (light1_col * l1_spec * l1_att * l1_shadow + light2_col * l2_spec * l2_att * l2_shadow);

    float3 result = ambient * base_col + light_diffuse * base_col * (1.0f - metallic) + light_spec;
    return result;
}

static inline float3 tonemap_aces(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

static inline float3 trace_ray(
    float3 ro,
    float3 rd,
    float3 light1_pos,
    float3 light1_col,
    float3 light2_pos,
    float3 light2_col,
    uint32_t scene_id,
    float time
) {
    float t = 0.0f;
    float mat = 0.0f;
    bool hit = false;

    for (int i = 0; i < 75; ++i) {
        float3 p = ro + rd * t;
        float2 res = map_scene(p, scene_id, time);
        if (res.x < 0.0015f) {
            hit = true;
            mat = res.y;
            break;
        }
        t += res.x;
        if (t > 28.0f) break;
    }

    float3 v1 = light1_pos - ro;
    float proj1 = max(dot(v1, rd), 0.0f);
    float d1 = length(light1_pos - (ro + rd * proj1));
    float3 glow = light1_col * (0.025f / (d1 * d1 + 0.05f));

    float3 v2 = light2_pos - ro;
    float proj2 = max(dot(v2, rd), 0.0f);
    float d2 = length(light2_pos - (ro + rd * proj2));
    glow += light2_col * (0.025f / (d2 * d2 + 0.05f));

    float3 col = float3(0.004f, 0.006f, 0.012f) + float3(0.008f, 0.015f, 0.03f) * max(-rd.y, 0.0f) + glow;

    if (hit) {
        float3 p = ro + rd * t;
        float3 n = calc_normal(p, scene_id, time);
        col = shade_surface(p, n, rd, mat, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);

        if (mat == 1.0f || mat == 2.0f || mat == 5.0f) {
            float f0 = (mat == 5.0f || mat == 2.0f) ? 0.9f : 0.06f;
            float cos_t = clamp(dot(n, -rd), 0.0f, 1.0f);
            float fresnel = f0 + (1.0f - f0) * pow(1.0f - cos_t, 5.0f);

            float3 r_rd = reflect(rd, n);
            float3 r_ro = p + n * 0.012f;
            float r_t = 0.0f;
            float r_mat = 0.0f;
            bool r_hit = false;

            for (int j = 0; j < 32; ++j) {
                float3 rp = r_ro + r_rd * r_t;
                float2 r_res = map_scene(rp, scene_id, time);
                if (r_res.x < 0.002f) {
                    r_hit = true;
                    r_mat = r_res.y;
                    break;
                }
                r_t += r_res.x;
                if (r_t > 20.0f) break;
            }

            float3 refl_col = float3(0.008f, 0.012f, 0.025f);
            if (r_hit) {
                float3 rp = r_ro + r_rd * r_t;
                float3 rn = calc_normal(rp, scene_id, time);
                refl_col = shade_surface(rp, rn, r_rd, r_mat, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
            }
            col = mix(col, refl_col, fresnel);
        }
    }

    return col;
}

kernel void rtx_render(
    constant RtxUniforms& uniforms [[buffer(0)]],
    device uint32_t* pixels [[buffer(1)]],
    uint2 id [[thread_position_in_grid]]
) {
    if (id.x >= uniforms.width || id.y >= uniforms.height) {
        return;
    }

    float w = (float)uniforms.width;
    float h = (float)uniforms.height;
    float x = (float)id.x;
    float y = (float)id.y;

    float3 cam_pos = float3(uniforms.cam_pos[0], uniforms.cam_pos[1], uniforms.cam_pos[2]);
    float3 cam_dir = float3(uniforms.cam_dir[0], uniforms.cam_dir[1], uniforms.cam_dir[2]);
    float3 cam_up = float3(uniforms.cam_up[0], uniforms.cam_up[1], uniforms.cam_up[2]);
    float3 cam_right = float3(uniforms.cam_right[0], uniforms.cam_right[1], uniforms.cam_right[2]);

    float time = uniforms.time;
    uint32_t scene_id = uniforms.scene_id;
    uint32_t quality = uniforms.quality_mode;

    float3 light1_pos = float3(sin(time * 0.9f) * 2.5f, 1.8f, cos(time * 0.9f) * 2.5f);
    float3 light1_col = float3(0.3f, 1.2f, 1.8f);

    float3 light2_pos = float3(sin(time * 0.8f + 3.14f) * 2.5f, 1.5f, cos(time * 0.8f + 3.14f) * 2.5f);
    float3 light2_col = float3(1.8f, 0.3f, 1.2f);

    float3 col = float3(0.0f);

    if (quality == 0) {
        float2 offsets[4] = {
            float2(-0.25f, -0.25f),
            float2( 0.25f, -0.25f),
            float2(-0.25f,  0.25f),
            float2( 0.25f,  0.25f)
        };
        for (int s = 0; s < 4; ++s) {
            float sx = x + offsets[s].x;
            float sy = y + offsets[s].y;
            float uv_x = (2.0f * sx - w) / h;
            float uv_y = (h - 2.0f * sy) / h;
            float3 rd = normalize(cam_dir + uv_x * cam_right * 0.8f + uv_y * cam_up * 0.8f);
            col += trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
        }
        col *= 0.25f;
    } else if (quality == 1) {
        float2 offsets[2] = {
            float2(-0.25f,  0.25f),
            float2( 0.25f, -0.25f)
        };
        for (int s = 0; s < 2; ++s) {
            float sx = x + offsets[s].x;
            float sy = y + offsets[s].y;
            float uv_x = (2.0f * sx - w) / h;
            float uv_y = (h - 2.0f * sy) / h;
            float3 rd = normalize(cam_dir + uv_x * cam_right * 0.8f + uv_y * cam_up * 0.8f);
            col += trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
        }
        col *= 0.5f;
    } else {
        float uv_x = (2.0f * x - w) / h;
        float uv_y = (h - 2.0f * y) / h;
        float3 rd = normalize(cam_dir + uv_x * cam_right * 0.8f + uv_y * cam_up * 0.8f);
        col = trace_ray(cam_pos, rd, light1_pos, light1_col, light2_pos, light2_col, scene_id, time);
    }

    col = tonemap_aces(col);
    col = smoothstep(0.0f, 1.0f, col);
    col = pow(col, float3(1.0f / 2.2f));

    uint32_t ir = (uint32_t)clamp(col.r * 255.0f, 0.0f, 255.0f);
    uint32_t ig = (uint32_t)clamp(col.g * 255.0f, 0.0f, 255.0f);
    uint32_t ib = (uint32_t)clamp(col.b * 255.0f, 0.0f, 255.0f);

    pixels[id.y * uniforms.width + id.x] = ir | (ig << 8) | (ib << 16) | (0xff000000);
}

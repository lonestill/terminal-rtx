#ifndef METAL_BRIDGE_H
#define METAL_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float cam_pos[3];
    float cam_dir[3];
    float cam_up[3];
    float cam_right[3];
    uint32_t width;
    uint32_t height;
    float time;
    uint32_t scene_id;
    uint32_t quality_mode;
} RtxUniforms;

int metal_rtx_init(const char* msl_source);
int metal_rtx_render(const RtxUniforms* uniforms);
const uint32_t* metal_rtx_get_pixel_buffer(void);
void metal_rtx_release(void);

#ifdef __cplusplus
}
#endif

#endif

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include "metal_bridge.h"

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_pipeline = nil;
static id<MTLBuffer> g_pixel_buffer = nil;
static NSUInteger g_current_buf_size = 0;

int metal_rtx_init(const char* msl_source) {
    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (g_device == nil) {
            return -1;
        }

        g_queue = [g_device newCommandQueue];
        if (g_queue == nil) {
            return -2;
        }

        NSString* source = [NSString stringWithUTF8String:msl_source];
        NSError* err = nil;
        id<MTLLibrary> library = [g_device newLibraryWithSource:source options:nil error:&err];
        if (library == nil) {
            return -3;
        }

        id<MTLFunction> kernel = [library newFunctionWithName:@"rtx_render"];
        if (kernel == nil) {
            return -4;
        }

        g_pipeline = [g_device newComputePipelineStateWithFunction:kernel error:&err];
        if (g_pipeline == nil) {
            return -5;
        }

        return 0;
    }
}

int metal_rtx_render(const RtxUniforms* uniforms) {
    if (g_device == nil || g_queue == nil || g_pipeline == nil || uniforms == nil) {
        return -1;
    }

    @autoreleasepool {
        NSUInteger needed_bytes = (NSUInteger)uniforms->width * (NSUInteger)uniforms->height * sizeof(uint32_t);
        if (g_pixel_buffer == nil || g_current_buf_size < needed_bytes) {
            g_pixel_buffer = [g_device newBufferWithLength:needed_bytes options:MTLResourceStorageModeShared];
            g_current_buf_size = needed_bytes;
        }

        if (g_pixel_buffer == nil) {
            return -2;
        }

        id<MTLCommandBuffer> cmd = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        [enc setComputePipelineState:g_pipeline];
        [enc setBytes:uniforms length:sizeof(RtxUniforms) atIndex:0];
        [enc setBuffer:g_pixel_buffer offset:0 atIndex:1];

        NSUInteger w = uniforms->width;
        NSUInteger h = uniforms->height;

        MTLSize grid = MTLSizeMake(w, h, 1);

        NSUInteger threadGroupW = 16;
        NSUInteger threadGroupH = 16;
        if (threadGroupW * threadGroupH > g_pipeline.maxTotalThreadsPerThreadgroup) {
            threadGroupW = 8;
            threadGroupH = 8;
        }
        MTLSize group = MTLSizeMake(threadGroupW, threadGroupH, 1);

        [enc dispatchThreads:grid threadsPerThreadgroup:group];
        [enc endEncoding];

        [cmd commit];
        [cmd waitUntilCompleted];

        return 0;
    }
}

const uint32_t* metal_rtx_get_pixel_buffer(void) {
    if (g_pixel_buffer == nil) {
        return NULL;
    }
    return (const uint32_t*)[g_pixel_buffer contents];
}

void metal_rtx_release(void) {
    g_pixel_buffer = nil;
    g_pipeline = nil;
    g_queue = nil;
    g_device = nil;
    g_current_buf_size = 0;
}

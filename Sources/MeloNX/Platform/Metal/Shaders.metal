// Shaders.metal
// MeloNX Air5 Edition
//
// Metal shaders for framebuffer blitting and post-processing.

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex / Fragment data structures

struct BlitVertex {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct BlitVaryings {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Blit (full-screen quad)

vertex BlitVaryings blitVertex(BlitVertex in [[stage_in]]) {
    BlitVaryings out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 blitFragment(BlitVaryings in [[stage_in]],
                              texture2d<float> framebuffer [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    return framebuffer.sample(samp, in.texCoord);
}

// MARK: - Upscaling (Bicubic – used for sub-native render scale → native display)

static float4 bicubicWeight(float t) {
    float4 n = float4(1.0, 2.0, 3.0, 4.0) - t;
    float4 s = n * n * n;
    float x  = s.x;
    float y  = s.y - 4.0 * s.x;
    float z  = s.z - 4.0 * s.y + 6.0 * s.x;
    float w  = 6.0 - x - y - z;
    return float4(x, y, z, w) * (1.0 / 6.0);
}

fragment float4 upscaleFragment(BlitVaryings in [[stage_in]],
                                 texture2d<float> source [[texture(0)]],
                                 sampler samp [[sampler(0)]]) {
    float2 texSize  = float2(source.get_width(), source.get_height());
    float2 texCoord = in.texCoord * texSize - 0.5;
    float2 fxy      = fract(texCoord);
    texCoord        = texCoord - fxy;

    float4 xcubic = bicubicWeight(fxy.x);
    float4 ycubic = bicubicWeight(fxy.y);

    float4 c = texCoord.xxyy + float4(-0.5, 1.5, -0.5, 1.5);
    float4 s  = float4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
    float4 offset = c + float4(xcubic.yw, ycubic.yw) / s;

    float4 sample0 = source.sample(samp, float2(offset.x, offset.z) / texSize);
    float4 sample1 = source.sample(samp, float2(offset.y, offset.z) / texSize);
    float4 sample2 = source.sample(samp, float2(offset.x, offset.w) / texSize);
    float4 sample3 = source.sample(samp, float2(offset.y, offset.w) / texSize);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix(mix(sample1, sample0, sx), mix(sample3, sample2, sx), sy);
}

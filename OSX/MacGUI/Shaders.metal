//
// This source file is part of VirtualC64 - A Commodore 64 emulator
//
// Copyright (C) Dirk W. Hoffmann. www.dirkwhoffmann.de
// Licensed under the GNU General Public License v3
//
// See https://www.gnu.org for license information
//

#include <metal_stdlib>

using namespace metal;

#define SCALE_FACTOR 4

//
// Main vertex shader (for drawing the quad)
// 

struct Uniforms {
    float4x4 modelViewProjection;
    float alpha;
};

struct InVertex {
    float4 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct ProjectedVertex {
    float4 position [[position]];
    float2 texCoords [[user(tex_coords)]];
    float  alpha;
};

struct FragmentUniforms {
    uint scanline;
    float scanlineBrightness;
    float scanlineWeight;
    float bloomFactor;
    uint mask;
    float maskBrightness;
};

vertex ProjectedVertex vertex_main(device InVertex *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   ushort vid [[vertex_id]])
{
    ProjectedVertex out;

    out.position = uniforms.modelViewProjection * float4(vertices[vid].position);
    out.texCoords = vertices[vid].texCoords;
    out.alpha = uniforms.alpha;
    return out;
}

float4 dotMaskWeight(int dotmaskType, uint2 pixel, float brightness) {
    
    float shadow = 0;//brightness * brightness;
    
    switch (dotmaskType) {
            
        case 1:
            switch(pixel.x % 3) {
                case 0: return float4(brightness, 1.0, brightness, 0.0);
                case 1: return float4(1.0, brightness, 1.0, 0.0);
                default: return float4(shadow, shadow, shadow, 0.0);
            }
        case 2:
            switch(pixel.x % 4) {
                case 0: return float4(1.0, brightness, brightness, 0.0);
                case 1: return float4(brightness, 1.0, brightness, 0.0);
                case 2: return float4(brightness, brightness, 1.0, 0.0);
                default: return float4(shadow, shadow, shadow, 0.0);
            }
        case 3:
            switch((pixel.x + ((pixel.y / 6) % 2)) % 3) {
                case 0: return float4(brightness, 1.0, brightness, 0.0);
                case 1: return float4(1.0, brightness, 1.0, 0.0);
                default: return float4(shadow, shadow, shadow, 0.0);
            }
        case 4:
            switch((pixel.x + ((pixel.y / 6) % 2)) % 4) {
                case 0: return float4(1.0, brightness, brightness, 0.0);
                case 1: return float4(brightness, 1.0, brightness, 0.0);
                case 2: return float4(brightness, brightness, 1.0, 0.0);
                default: return float4(shadow, shadow, shadow, 0.0);
            }
    }
    return float4(1.0, 1.0, 1.0, 0.0);
}

fragment half4 fragment_main(ProjectedVertex vert [[stage_in]],
                             texture2d<float, access::sample> texture [[texture(0)]],
                             texture2d<float, access::sample> blur [[texture(1)]],
                             constant FragmentUniforms &uniforms [[buffer(0)]],
                             sampler texSampler [[sampler(0)]])
{
    uint2 pixel = uint2(uint(vert.position.x), uint(vert.position.y));
    
    // Read fragment from texture
    float2 tc = float2(vert.texCoords.x, vert.texCoords.y);
    float4 color = texture.sample(texSampler, tc);
    float4 bloomCol = blur.sample(texSampler, tc);
    bloomCol = pow(bloomCol, uniforms.bloomFactor);
    color = saturate(color + bloomCol * uniforms.scanlineBrightness);
    
    // Apply dot mask effect
    color *= dotMaskWeight(uniforms.mask, pixel, uniforms.maskBrightness);

    return half4(color.r, color.g, color.b, vert.alpha);
}


//
// Texture upscalers (first post-processing stage)
//

kernel void bypassupscaler(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                           texture2d<half, access::write> outTexture  [[ texture(1) ]],
                           uint2                          gid         [[ thread_position_in_grid ]])
{
    half4 result = inTexture.read(uint2(gid.x / SCALE_FACTOR, gid.y / SCALE_FACTOR));
    outTexture.write(result, gid);
}

struct CrtParameters {
    float scanlineWeight;
};

//
// Scanline upscaler
//
//
kernel void scanline_upscaler(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                              texture2d<half, access::write> outTexture  [[ texture(1) ]],
                              constant CrtParameters         &params     [[ buffer(0) ]],
                              uint2                          gid         [[ thread_position_in_grid ]])
{
    half4 color = inTexture.read(uint2(gid.x / SCALE_FACTOR, gid.y / SCALE_FACTOR));
    if ((gid.y % SCALE_FACTOR) >= SCALE_FACTOR / 2) {
        color *= params.scanlineWeight;
    }
    outTexture.write(color, gid);
}

//
// Texture filter (second post-processing stage)
//

//
// Bypass filter
//

kernel void bypass(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                   texture2d<half, access::write> outTexture  [[ texture(1) ]],
                   uint2                          gid         [[ thread_position_in_grid ]])
{
    half4 result = inTexture.read(uint2(gid.x, gid.y));
    outTexture.write(result, gid);
}

/*
kernel void bloom(texture2d<float, access::sample>  inTexture   [[ texture(0) ]],
                  texture2d<float, access::write> outTexture  [[ texture(1) ]],
                  texture2d<float, access::sample> blur [[texture(3)]],
                  constant CrtParameters         &params     [[ buffer(0) ]],
                  uint2                          gid         [[ thread_position_in_grid ]])
{
    constexpr sampler _sampler(coord::normalized,
                               address::repeat,
                               filter::linear);
    // Get blur value
    float2 uv = float2(gid.x, gid.y);
    uv.x /= outTexture.get_width();
    uv.y /= outTexture.get_height();
    float4 bloomCol = blur.sample(_sampler, uv);
    
    bloomCol = pow(bloomCol, 1.5);
    
    float4 outColor = inTexture.read(gid);
    outTexture.write(saturate(outColor + bloomCol * params.bloomFactor), gid);
}*/

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct RasterizerData
{
    float2 texCoord [[user(locn0)]];

    float4 position [[position]];
};

vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]])
{
    float2 uv = float2((int(vertexID) & 1) << 1, 1 - (int(vertexID) & 2));

    RasterizerData out;
    out.texCoord = uv;
    out.position = float4((uv.x * 2.0) - 1.0, 1.0 - (uv.y * 2.0), 0.0, 1.0);

    return out;
}

struct FragmentOut
{
    float depth [[depth(any)]];
};

fragment FragmentOut fragmentShader(RasterizerData in [[stage_in]])
{
    if (in.texCoord.x < 0.5)
        discard_fragment();

    FragmentOut out = {};

    if (in.texCoord.y < 0.5)
        out.depth = 1.0;

    return out;
}

fragment float4 presentFragmentShader(RasterizerData in [[stage_in]])
{
    return float4(1.0);
}

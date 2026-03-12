#include <metal_stdlib>
using namespace metal;

struct SceneUniforms {
    float4x4 viewProjectionMatrix;
    float3 lightDirection;
    float ambientLight;
};

struct GridVertex {
    float3 position;
    float4 color;
};

struct CubeVertex {
    float3 position;
    float3 normal;
};

struct VoxelInstanceGPU {
    float3 position;
    uint paletteIndex;
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float paletteIndex;
};

struct GridVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex GridVertexOut grid_vertex(
    const device GridVertex *vertices [[buffer(0)]],
    constant SceneUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    float3 worldPosition = vertices[vertexID].position;
    GridVertexOut out;
    out.position = uniforms.viewProjectionMatrix * float4(worldPosition, 1.0);
    out.color = vertices[vertexID].color;
    return out;
}

fragment half4 grid_fragment(GridVertexOut in [[stage_in]]) {
    return half4(in.color);
}

fragment half4 hover_fragment() {
    return half4(1.0, 1.0, 1.0, 0.32);
}

fragment half4 preview_fragment() {
    return half4(1.0, 0.85, 0.35, 1.0);
}

vertex VertexOut voxel_vertex(
    const device CubeVertex *vertices [[buffer(0)]],
    const device VoxelInstanceGPU *instances [[buffer(1)]],
    constant SceneUniforms &uniforms [[buffer(2)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    CubeVertex cubeVertex = vertices[vertexID];
    VoxelInstanceGPU voxelInstance = instances[instanceID];

    float3 worldPosition = cubeVertex.position + voxelInstance.position;

    VertexOut out;
    out.position = uniforms.viewProjectionMatrix * float4(worldPosition, 1.0);
    out.normal = cubeVertex.normal;
    out.paletteIndex = float(voxelInstance.paletteIndex);
    return out;
}

fragment half4 voxel_fragment(
    VertexOut in [[stage_in]],
    constant SceneUniforms &uniforms [[buffer(0)]],
    texture2d<half> paletteTexture [[texture(0)]]
) {
    constexpr sampler paletteSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float paletteWidth = float(paletteTexture.get_width());
    float u = (in.paletteIndex + 0.5) / paletteWidth;
    half4 baseColor = paletteTexture.sample(paletteSampler, float2(u, 0.5));

    float3 normal = normalize(in.normal);
    float diffuse = max(dot(normal, normalize(uniforms.lightDirection)), 0.0);
    float light = uniforms.ambientLight + ((1.0 - uniforms.ambientLight) * diffuse);

    return half4(baseColor.rgb * half(light), baseColor.a);
}

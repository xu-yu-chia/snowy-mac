#include <metal_stdlib>
using namespace metal;

struct FrameUniforms { float2 viewport; float time; float padding; };
struct SnowVertex { float2 position; float2 material; };
struct ParticleInstance { float2 position; float radius; float opacity; };
struct DriftOut { float4 position [[position]]; float2 material; float2 point; };
struct FlakeOut { float4 position [[position]]; float2 uv; float opacity; };
struct StreakInstance { float2 position; float2 vector; float width; float opacity; };

float4 project(float2 point, constant FrameUniforms &frame) {
    return float4(point.x / frame.viewport.x * 2 - 1, 1 - point.y / frame.viewport.y * 2, 0, 1);
}

vertex DriftOut driftVertex(uint id [[vertex_id]], const device SnowVertex *vertices [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]]) {
    SnowVertex v = vertices[id];
    return { project(v.position, frame), v.material, v.position };
}

fragment half4 driftFragment(DriftOut in [[stage_in]]) {
    float shade = smoothstep(0.0, 1.0, in.material.x);
    float grain = fract(52.9829189 * fract(dot(in.point, float2(0.06711056, 0.00583715))));
    half3 color = mix(half3(0.76, 0.84, 0.93), half3(0.99, 0.995, 1.0), half(shade));
    color += half((grain - 0.5) * 0.012);
    half alpha = half(in.material.y);
    return half4(color * alpha, alpha);
}

vertex FlakeOut flakeVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                            const device ParticleInstance *particles [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]]) {
    const float2 corners[6] = { {-1,-1}, {1,-1}, {-1,1}, {1,-1}, {1,1}, {-1,1} };
    ParticleInstance p = particles[instance];
    float2 uv = corners[id];
    return { project(p.position + uv * (p.radius + 0.6), frame), uv, p.opacity };
}

fragment half4 flakeFragment(FlakeOut in [[stage_in]]) {
    float distance = length(in.uv);
    half alpha = half((1 - smoothstep(0.30, 1.0, distance)) * in.opacity);
    return half4(half3(0.96, 0.98, 1.0) * alpha, alpha);
}

// Water bodies (puddles, flood) reuse the drift vertices: material.x 0 = bottom, 1 = surface.
fragment half4 waterFragment(DriftOut in [[stage_in]]) {
    float depth = clamp(in.material.x, 0.0, 1.0);
    half3 color = mix(half3(0.30, 0.42, 0.55), half3(0.58, 0.70, 0.82), half(depth));
    // A thin bright line where the surface catches the light.
    float shine = pow(depth, 48.0);
    color = mix(color, half3(0.92, 0.96, 1.0), half(shine * 0.8));
    half alpha = half(min(1.0, in.material.y + shine * 0.35));
    return half4(color * alpha, alpha);
}

// Rain streaks: a thin quad from position - vector (tail) to position (head).
vertex FlakeOut streakVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                             const device StreakInstance *streaks [[buffer(0)]],
                             constant FrameUniforms &frame [[buffer(1)]]) {
    const float2 corners[6] = { {0,-1}, {1,-1}, {0,1}, {1,-1}, {1,1}, {0,1} };
    StreakInstance s = streaks[instance];
    float2 corner = corners[id];
    float len = length(s.vector);
    float2 dir = len > 0.001 ? s.vector / len : float2(0, 1);
    float2 normal = float2(-dir.y, dir.x);
    float2 point = s.position - s.vector * (1.0 - corner.x) + normal * corner.y * (s.width * 0.5 + 0.5);
    return { project(point, frame), corner, s.opacity };
}

fragment half4 streakFragment(FlakeOut in [[stage_in]]) {
    // Fade in from the tail and soften the sides.
    float along = smoothstep(0.0, 0.6, in.uv.x);
    float across = 1.0 - smoothstep(0.35, 1.0, abs(in.uv.y));
    half alpha = half(along * across * in.opacity);
    return half4(half3(0.80, 0.87, 0.95) * alpha, alpha);
}

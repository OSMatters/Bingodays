#include <metal_stdlib>
using namespace metal;

// Animate only the green portal pigment in the flattened illustration.
// Keeping the original alpha and foreground pixels preserves its silhouette,
// characters, and speech bubbles without needing replacement artwork.
[[ stitchable ]] half4 onboardingPortalWaves(
    float2 position,
    half4 color,
    float2 size,
    float time
) {
    if (color.a < 0.01h) {
        return color;
    }

    float3 original = float3(color.rgb) / float(color.a);
    float greenDominance = original.g - max(original.r, original.b);
    if (greenDominance < 0.06) {
        return color;
    }

    float2 source = position / size * float2(1025.0, 1534.0);
    // The small green emitter is part of the character's stationary prop.
    float2 emitter = (source - float2(110.0, 691.0)) / float2(34.0, 30.0);
    if (dot(emitter, emitter) < 1.0) {
        return color;
    }

    float2 portal = (source - float2(490.0, 880.0)) / float2(435.0, 610.0);
    float radius = length(portal);
    float angle = atan2(portal.y, portal.x);
    // A slow angular flow with a softer traveling wave through the spiral.
    float phase = angle * 7.0 - radius * 18.0 - time * 1.25
        + 1.4 * sin(angle * 3.0 + radius * 7.0 - time * 0.65)
        + 0.4 * sin(angle * 5.0 - radius * 9.0 + time * 0.4);
    float wave = sin(phase);
    // Differentiate the periodic value so atan2's wrap cannot create a seam.
    float edge = max(fwidth(wave) * 0.65, 0.025);
    float band = smoothstep(-edge, edge, wave);
    float3 deepGreen = float3(76.0, 174.0, 0.0) / 255.0;
    float3 limeGreen = float3(176.0, 236.0, 66.0) / 255.0;
    float3 flowingColor = mix(deepGreen, limeGreen, band);

    float coverage = smoothstep(0.06, 0.18, greenDominance);
    float entrance = smoothstep(0.0, 1.2, time);
    float3 result = mix(original, flowingColor, coverage * entrance);
    return half4(half3(result) * color.a, color.a);
}

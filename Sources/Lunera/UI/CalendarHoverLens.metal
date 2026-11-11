#include <metal_stdlib>
using namespace metal;

// Matches CalendarHoverLens.sourcePosition, including the compact poly6 kernel.
[[ stitchable ]] float2 calendarHoverLens(float2 position, float2 focus,
                                        float2 cellPitch, float radius, float strength,
                                        float maximumStrength) {
    if (strength <= 0 || radius <= 0 || any(cellPitch <= 0)) {
        return position;
    }
    float2 delta = position - focus;
    float2 q = delta / cellPitch;
    float distanceSquared = dot(q, q) / (radius * radius);
    if (distanceSquared >= 1) {
        return position;
    }
    float remaining = 1 - distanceSquared;
    float weight = remaining * remaining * remaining;
    float scale = 1 - clamp(strength, 0.0f, maximumStrength) * weight;
    return focus + delta * scale;
}

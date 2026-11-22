#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

// Must be IDENTICAL in genie.frag (same members, same order).
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = closed (collapsed into target), 1 = fully open
    float delay;      // per-row delay, ~0.6
    float flip;       // 0 = bar on top, 1 = bar on bottom
    vec2 target;      // suction point, item-local pixels
};

void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;

    // v = 0 at the panel edge nearest the bar, 1 at the far edge.
    float v = mix(qt_MultiTexCoord0.y, 1.0 - qt_MultiTexCoord0.y, flip);
    float p = clamp(progress, 0.0, 1.0);
    vec2 pos = qt_Vertex.xy;

    // Vertical: one global factor for every row, so row order can never invert.
    pos.y = target.y + (pos.y - target.y) * p;

    // Horizontal: each row opens on its own schedule, far edge first.
    float e = clamp(p * (1.0 + delay) - (1.0 - v) * delay, 0.0, 1.0);
    e = smoothstep(0.0, 1.0, e);
    pos.x = mix(target.x, pos.x, e);

    gl_Position = qt_Matrix * vec4(pos, 0.0, 1.0);
}

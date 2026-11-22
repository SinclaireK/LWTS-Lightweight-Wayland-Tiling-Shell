#version 440
// Directional blur along the motion of the plate while it moves: 9 taps, `amount` = the smear vector in texture units (x, y).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 amount;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 c = vec4(0.0);
    float w = 0.0;
    for (int i = -4; i <= 4; ++i) {
        float t = float(i) / 4.0;
        float k = 1.0 - abs(t) * 0.6;
        c += texture(source, qt_TexCoord0 + t * amount) * k;
        w += k;
    }
    fragColor = c / w * qt_Opacity;
}

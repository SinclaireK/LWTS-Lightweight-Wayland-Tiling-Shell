// AppIcon engine: any coloured app icon -> a one-ink monochrome glyph (Nothing: clean, high contrast, no pixel art, no colour).
// Source of the compiled appicon.frag.qsb; rebuild after edits: /usr/lib/qt6/bin/qsb --qt6 -o appicon.frag.qsb appicon.frag
// A shader edit needs `lwts restart` (reload keeps the old one).
//  - alpha of the icon is kept (smooth edges); brightness comes from luminance (flipped for a dark ink on a light bar) + local contrast, so a logo
//    pops out of a coloured body whatever the colours: glyph near full ink, body a dim plate (never below 0.20), detail = 0 (symbolic icon) = one level.
//  - the dot motif lives in the empty (transparent) part of the square: every second pixel in both directions stays lit at `faint`, a dotted grid.
//  - `cells` = the icon size in px (pixel grid of that field + texel step of the neighbourhood).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 ink;      // Theme.text
  float dark;    // 1 = light ink on a dark bar, 0 = dark ink on a light bar
  float detail;  // 1 = brightness from the icon, 0 = silhouette
  float cells;   // icon size in px
  float faint;   // opacity of a dot of the field
};
layout(binding = 1) uniform sampler2D source;
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
  vec2 uv = qt_TexCoord0;
  float px = 1.0 / cells;
  vec4 s = texture(source, uv);
  float a = s.a;
  vec3 c = a > 0.001 ? s.rgb / a : vec3(0.0);
  float l = luma(c);
  float k = mix(1.0 - l, l, dark);   // how much this part stands out against the bar
  float sl = 0.0, sa = 0.0;          // alpha weighted mean luminance around the pixel
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
    vec4 q = texture(source, uv + vec2(float(i), float(j)) * px);
    sl += luma(q.rgb); sa += q.a;
  }
  float avg = sa > 0.2 ? sl / sa : l;
  float sd = mix(avg - l, l - avg, dark);   // positive = brighter (in ink terms) than the neighbours
  float tone = mix(0.7, clamp(0.10 + 1.1 * smoothstep(0.35, 0.95, k) + 3.2 * sd, 0.0, 1.0), detail);
  float level = (0.20 + 0.80 * smoothstep(0.20, 0.85, tone)) * 0.95;   // never a hard white
  vec2 ci = mod(floor(uv * cells), 2.0);
  float field = (ci.x < 0.5 && ci.y < 0.5) ? faint : 0.0;
  float alpha = level * a + field * (1.0 - a);
  fragColor = vec4(ink.rgb * alpha, alpha) * qt_Opacity;
}

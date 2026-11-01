shader_type spatial;
render_mode unshaded, fog_disabled;

// The movie screen's face: soft drifting patches of projected light over a pale base, a vignette towards
// the frame, a bright hotspot where the projector aims, and film grain. It reads no TIME: `phase` is
// advanced by the lot's own script, so recordings and tests see the same picture.

uniform float energy = 1.0;
uniform float phase = 0.0;
uniform vec3 cool : source_color = vec3(0.50, 0.62, 0.82);
uniform vec3 warm : source_color = vec3(0.86, 0.80, 0.66);
// The panel is 32 x 12 m, its centre 10 m up.
uniform vec2 panel_size = vec2(32.0, 12.0);
uniform float panel_centre_y = 10.0;

varying vec3 world_at;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(world_at.x / panel_size.x + 0.5, (world_at.y - panel_centre_y) / panel_size.y + 0.5);
	// Patches of light: two layers of slow waves, a scene that brightens and dims.
	float a = sin(uv.x * 5.0 + phase * 0.35) * sin(uv.y * 4.0 - phase * 0.27);
	float b = sin(uv.x * 11.0 - phase * 0.5 + 2.0) * sin(uv.y * 7.0 + phase * 0.41);
	float patch = 0.5 + 0.35 * a + 0.15 * b;
	vec3 picture = mix(cool, warm, smoothstep(0.25, 0.8, patch)) * (0.45 + 0.55 * patch);
	// Hotspot and vignette.
	vec2 c = uv * 2.0 - 1.0;
	vec2 cs = c * vec2(0.8, 1.0);
	float spot = 1.0 - 0.28 * dot(cs, cs);
	float vignette = smoothstep(1.35, 0.55, length(c * vec2(0.8, 1.1)));
	// Film grain, re-rolled 12 times a second.
	float grain = hash(floor(uv * panel_size * 9.0) + floor(phase * 12.0)) - 0.5;
	vec3 col = picture * spot * mix(0.35, 1.0, vignette) + grain * 0.05;
	// A thin dark masking inside the panel's edge.
	float inside = step(0.012, uv.x) * step(uv.x, 0.988) * step(0.03, uv.y) * step(uv.y, 0.97);
	ALBEDO = max(col, vec3(0.0)) * energy * inside;
}

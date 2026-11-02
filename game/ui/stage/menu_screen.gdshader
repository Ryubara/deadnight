shader_type spatial;
render_mode unshaded, fog_disabled, specular_disabled;

// The picture on the stage's movie screen: soft patches of projected light drifting over a pale
// base, a dim edge and a hot centre where the projector aims. It reads no TIME: `phase` is the
// stage's own clock, so captures repeat. Smooth waves only (no hash), so it is the same on every
// GPU and does not shimmer at a low resolution.

uniform float energy = 0.8;
uniform float phase = 0.0;
uniform vec3 cool : source_color = vec3(0.45, 0.56, 0.78);
uniform vec3 warm : source_color = vec3(0.86, 0.78, 0.62);

void fragment() {
	vec2 uv = UV;
	float a = sin(uv.x * 5.0 + phase * 0.3) * sin(uv.y * 4.0 - phase * 0.23);
	float b = sin(uv.x * 9.0 - phase * 0.41 + 2.0) * sin(uv.y * 6.0 + phase * 0.33);
	float patch = 0.5 + 0.34 * a + 0.16 * b;
	vec3 picture = mix(cool, warm, smoothstep(0.3, 0.8, patch)) * (0.4 + 0.6 * patch);
	vec2 c = (uv * 2.0 - 1.0) * vec2(0.8, 1.0);
	float spot = 1.0 - 0.3 * dot(c, c);
	float vignette = smoothstep(1.4, 0.5, length(c * vec2(1.0, 1.15)));
	// The projector's slow breathing.
	float breathe = 0.94 + 0.06 * sin(phase * 1.3);
	ALBEDO = picture * spot * mix(0.4, 1.0, vignette) * energy * breathe;
}

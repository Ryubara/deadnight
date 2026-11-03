shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// A blood mark on a floor or a wall, one quad lying on the surface (its +Z is the surface normal)
// and no texture: a lumpy blot with a few satellite drops, stretched along the way the blood
// flew. It dries from wet red to dark over its life and then fades out. `progress` is 0 when it
// lands and 1 when it is gone. The node's x and y scale is its size; z stays 1, so the lift off the
// surface in `vertex` is in metres. docs/design/shot-feedback.md.

uniform vec4 wet_colour : source_color = vec4(0.5, 0.025, 0.04, 1.0);
uniform vec4 dried_colour : source_color = vec4(0.2, 0.02, 0.03, 1.0);
uniform vec4 highlight : source_color = vec4(0.82, 0.1, 0.1, 1.0);
uniform float progress = 0.0;
uniform float seed = 0.0;
// 1 is round; more stretches the blot along the node's x axis.
uniform float stretch = 1.6;
// The share of life after which the mark fades.
uniform float fade_from = 0.6;
uniform float lift = 0.01;
uniform float lift_per_metre = 0.002;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void vertex() {
	// Lifted off the surface a little more the farther it is, or it flickers in the depth buffer.
	float far_away = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	VERTEX.z += lift + lift_per_metre * far_away;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x /= stretch;
	float px = max(fwidth(length(p)), 0.002);
	float angle = atan(p.y, p.x);
	float edge = 0.38 + 0.07 * sin(angle * 3.0 + seed) + 0.04 * sin(angle * 5.0 + seed * 2.3) + 0.025 * sin(angle * 9.0 + seed * 4.1);
	float cover = 1.0 - smoothstep(edge - px, edge + px, length(p));
	float core = 1.0 - smoothstep(edge * 0.35 - px, edge * 0.6, length(p - vec2(-0.1, 0.1)));
	// Satellite drops round the blot, in the stretched direction mostly.
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float a = hash(fi + 1.0) * 6.2832;
		float r = 0.52 + 0.1 * hash(fi + 9.0);
		vec2 c = vec2(cos(a) * r, sin(a) * r * 0.9);
		float rad = 0.03 + 0.05 * hash(fi + 17.0);
		cover = max(cover, 1.0 - smoothstep(rad - px, rad + px, length(p - c)));
	}
	float dry = smoothstep(0.0, 0.5, progress);
	vec3 base = mix(wet_colour.rgb, dried_colour.rgb, dry);
	ALBEDO = mix(base, highlight.rgb, core * (1.0 - dry) * 0.5);
	ALPHA = cover * (1.0 - smoothstep(fade_from, 1.0, progress));
}

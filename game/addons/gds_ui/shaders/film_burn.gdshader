shader_type canvas_item;
// A film-burn wipe. Phase one (reveal = 0): the burn front eats outward from `origin` and leaves
// char behind it. Phase two (reveal = 1): the char burns away from the same point and the new
// screen shows through. Procedural noise only; it never samples the screen, so it is safe in the
// Compatibility renderer and WebGL2.

#include "res://addons/gds_ui/shaders/gds_hash.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.5, 0.5);
uniform float aspect = 1.7778;
uniform float max_dist = 1.2;
uniform float edge_width : hint_range(0.02, 0.4) = 0.16;
uniform float noise_scale = 5.0;

// The colours are the tokens burn_hot, burn_flame, burn_ember and burn_char; UITransitionShader
// sets them, and these defaults only cover a shader previewed on its own.
uniform vec3 burn_hot = vec3(1.0, 0.96, 0.78);
uniform vec3 burn_flame = vec3(1.0, 0.62, 0.16);
uniform vec3 burn_ember = vec3(0.78, 0.2, 0.05);
uniform vec3 burn_char = vec3(0.04, 0.03, 0.03);

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total / 0.9375;
}

vec3 fire_ramp(float t) {
	// t = 0 at the burn front, 1 at the inner edge of the burning band.
	vec3 c = mix(burn_hot, burn_flame, smoothstep(0.0, 0.3, t));
	c = mix(c, burn_ember, smoothstep(0.25, 0.7, t));
	return mix(c, burn_char, smoothstep(0.65, 1.0, t));
}

void fragment() {
	vec2 centred = (UV - origin) * vec2(aspect, 1.0);
	float dist = length(centred) / max_dist;
	float grain = fbm(UV * vec2(aspect, 1.0) * noise_scale);
	float v = dist * 0.72 + grain * 0.28;
	float front = mix(-edge_width, 1.0 + edge_width, progress);
	float m = front - v;
	vec4 colour = vec4(0.0);
	if (m >= edge_width) {
		// Behind the band: char while closing, burned through (clear) while revealing.
		colour = vec4(burn_char, reveal > 0.5 ? 0.0 : 1.0);
	} else if (m >= 0.0) {
		float t = m / edge_width;
		float flicker = 0.85 + 0.15 * value_noise(UV * 60.0);
		float band_alpha = reveal > 0.5 ? 1.0 - smoothstep(0.55, 1.0, t) : 1.0;
		colour = vec4(fire_ramp(t) * flicker, band_alpha);
	} else {
		// Ahead of the front: untouched paper (reveal) or clear with a heat glow (close).
		float glow = smoothstep(-0.14, 0.0, m);
		colour = reveal > 0.5 ? vec4(burn_char, 1.0) : vec4(burn_flame, glow * 0.35);
		if (reveal > 0.5) {
			colour.rgb = mix(burn_char, burn_ember, glow * 0.6);
		}
	}
	COLOR = colour;
}

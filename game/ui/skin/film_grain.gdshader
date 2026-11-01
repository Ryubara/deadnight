shader_type canvas_item;
// Film over the whole game: grain, vignette, a projector's brightness flicker and the odd scratch.
// Purely additive to what is below (black or white speckle with alpha), so it never reads the
// screen: it works in the Compatibility renderer and in a web build.

#include "res://addons/gds_ui/shaders/gds_hash.gdshaderinc"

uniform float grain : hint_range(0.0, 0.3) = 0.055;
uniform float grain_px = 1.5;
uniform float vignette : hint_range(0.0, 1.0) = 0.62;
uniform float flicker : hint_range(0.0, 0.2) = 0.05;
uniform float scratches : hint_range(0.0, 1.0) = 0.5;
// 0 freezes the time-based parts (reduced motion).
uniform float motion : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float t = TIME * motion;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / grain_px);
	// Film runs at 24 frames a second; each frame has its own grain.
	float frame = floor(t * 24.0);
	float n = hash21(cell + mod(frame, 64.0) * vec2(113.0, 71.0));
	float speck = (n - 0.5) * 2.0;
	vec4 col = vec4(vec3(step(0.0, speck)), abs(speck) * grain * (speck > 0.0 ? 0.55 : 1.0));

	// Vignette: darker towards the corners, a little tighter than the window's shape.
	vec2 q = UV - 0.5;
	q.x *= res.x / res.y * 0.62;
	float edge = smoothstep(0.18, 0.78, length(q));
	float shade = edge * vignette;

	// Projector brightness: a slow breath plus a random twitch, 12 times a second.
	float twitch = hash21(vec2(floor(t * 12.0), 3.0));
	float dim = flicker * motion * (0.35 + 0.65 * step(0.8, twitch)) * (0.5 + 0.5 * sin(t * 5.1));

	// A vertical scratch that appears for a few frames at a time.
	float seed = floor(t * 3.0);
	float where = hash21(vec2(seed, 9.0));
	float live = step(0.62, hash21(vec2(seed, 5.0))) * scratches * motion;
	float line = (1.0 - smoothstep(0.0, 1.6 / res.x, abs(UV.x - where))) * live;
	line *= step(0.35, hash21(vec2(floor(UV.y * 40.0), seed)));

	float dark = clamp(shade + dim, 0.0, 1.0);
	// Grain over the dark layer (not mixed with it, or the vignette would be speckled too).
	float alpha = dark + col.a * (1.0 - dark);
	vec3 rgb = col.rgb * col.a * (1.0 - dark) / max(alpha, 0.0001);
	rgb = mix(rgb, vec3(0.95, 0.9, 0.8), line * 0.5);
	alpha = max(alpha, line * 0.16);
	COLOR = vec4(rgb, alpha);
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Blue fire off the wings (a cosmetic-tier test, issue #1053; not shipped): the same fan of feathers, wider and
// longer, drawn additively with a scrolling value noise eating the shape from the tip. Drawn the way the game's
// shock arc is (docs/design/perks.md, "The shock shader"): two flat colours, an electric blue body round a pale core,
// hard edges anti-aliased on the edge only, a sine-free hash, no texture, no light, no dynamic loop: it runs in the
// Compatibility renderer and in a browser alike. One draw for both wings.

uniform float energy = 1.5;
uniform vec3 core : source_color = vec3(0.82, 0.94, 1.0);
uniform vec3 body : source_color = vec3(0.08, 0.38, 1.0);
uniform float speed = 1.5;
// How much of the shape is the pale core, and where the body ends.
uniform float core_from = 0.55;
uniform float edge_at = 0.12;

varying float seed;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	seed = COLOR.r;
	float t = TIME * 2.2 + seed * 6.28;
	VERTEX.x += sin(t + UV.y * 5.0) * 0.025 * UV.y;
	VERTEX.y += cos(t * 0.7 + UV.y * 3.0) * 0.015 * UV.y;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	vec2 q = vec2(UV.x * 2.0 + seed * 13.0, UV.y * 3.0 - TIME * speed);
	float n = vnoise(q * 2.0) * 0.6 + vnoise(q * 4.6) * 0.4;
	float shape = (1.0 - across) - UV.y * 0.55 + (n - 0.5) * 0.9;
	float aa = fwidth(shape) + 0.01;
	float lit = smoothstep(edge_at - aa, edge_at + aa, shape);
	float hot = smoothstep(core_from - aa, core_from + aa, shape);
	ALBEDO = mix(body, core, hot) * lit * energy;
}

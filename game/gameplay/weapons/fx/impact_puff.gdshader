shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// A toon puff or mark for a shot that landed, one billboard quad and no texture: a flat disc with a
// wobbly edge and a lighter crescent on one side, fading as `progress` goes from 0 to 1. Dust grey on
// a wall, dark red on a zombie, a small dark dot for the mark a hit leaves. The node's scale is its
// size (the script grows it). docs/design/shot-feedback.md has the numbers.

uniform vec4 colour : source_color = vec4(0.62, 0.58, 0.5, 1.0);
uniform vec4 highlight : source_color = vec4(0.8, 0.77, 0.68, 1.0);
// 0 at the start of the puff, 1 when it is gone.
uniform float progress = 0.0;
// Where the wobble of the edge starts, so two puffs differ.
uniform float seed = 0.0;
// 0 a round dot, up to a lumpy cloud.
uniform float lumpiness = 0.12;
// The crescent of light, 0 for none (the mark is flat).
uniform float crescent = 1.0;
// Progress from which the puff fades (it holds its colour before).
uniform float fade_from = 0.35;

void vertex() {
	// Face the camera, keeping the node's own scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float edge = 0.82 + lumpiness * sin(angle * 3.0 + seed) + lumpiness * 0.5 * sin(angle * 5.0 + seed * 2.3);
	float dist = length(p);
	float pixel = max(fwidth(dist), 0.0001);
	float disc = 1.0 - smoothstep(edge - pixel, edge, dist);
	// The crescent: the disc minus the same disc nudged towards the lower right.
	float shifted = 1.0 - smoothstep(edge - pixel, edge, length(p - vec2(0.22, -0.22)));
	float light = clamp(disc - shifted, 0.0, 1.0) * crescent;
	ALBEDO = mix(colour.rgb, highlight.rgb, light);
	ALPHA = disc * colour.a * (1.0 - smoothstep(fade_from, 1.0, progress));
}

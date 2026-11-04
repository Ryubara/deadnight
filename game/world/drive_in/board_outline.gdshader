shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// The ghost of a missing board (`BoardOutline`): a faint plank drawn where the board was, so a torn barricade
// reads as one that can be mended. A frame round the plank's face, a very faint fill and a nail at each end, all
// additive and unshaded, the same family as the lot's light cards (`glow.gdshader`) and the moon's haze.
//
// The quad's UV runs 0..1 across the face and UV2 is its size in metres, so the stroke and the nails keep their
// width on a 1.5 m window board and a 4.1 m fence board alike.

uniform vec4 tint : source_color = vec4(0.616, 0.706, 0.91, 1.0);
uniform float energy = 1.0;
// The frame's width (m) and how soft its inner edge is (a share of the width).
uniform float line_width = 0.04;
// The fill's strength against the frame's (1).
uniform float fill = 0.16;
// A nail: its radius and its distance from the board's end (m), against the frame's strength.
uniform float nail_radius = 0.035;
uniform float nail_inset = 0.14;
uniform float nail_strength = 0.9;

varying vec2 size;

void vertex() {
	size = UV2;
}

void fragment() {
	vec2 at = UV * size;
	vec2 to_edge = min(at, size - at);
	float frame = 1.0 - smoothstep(line_width * 0.5, line_width, min(to_edge.x, to_edge.y));
	float to_nail = length(vec2(to_edge.x - nail_inset, at.y - size.y * 0.5));
	float nail = (1.0 - smoothstep(nail_radius * 0.5, nail_radius, to_nail)) * nail_strength;
	float shape = max(max(frame, nail), fill);
	ALBEDO = tint.rgb * energy * shape;
	ALPHA = 1.0;
}

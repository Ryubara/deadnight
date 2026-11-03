shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// A cheap stand-in for light that a real light cannot afford in Compatibility (8 lights a mesh, no shadows):
// an additive quad whose brightness falls off from its centre. Laid flat on the asphalt it is the pool under a
// lamp; as a billboard it is the halo round a bulb, a sign or a breaker lamp. `energy` is what the lot's
// circuits drive (0 draws nothing).
//
// The small map's light cards (`game/world/smallmap/lights/`) use the same shader, so they build no program the
// lot does not: `card` makes it a soft-edged rectangle that fades along V (a moon shaft, the light under a door),
// `bars` and `rails` cut it with the shadows of a window's bars, and `mask` is a greyscale picture over it (chalk
// lettering). With the defaults the picture is the lot's, unchanged.

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform float energy = 1.0;
// Higher is a tighter core with a softer skirt.
uniform float falloff = 2.0;
uniform bool billboard = false;
// A rectangle instead of a disc: soft over `edge` (a share of U, of V) at its sides and ends, brightest at V = 0 and
// `fade` dimmer at V = 1.
uniform bool card = false;
uniform vec2 edge = vec2(0.2, 0.15);
uniform float fade = 0.0;
// Bar shadows: `bars` evenly spaced across U, `rails` across V (0 for none); `shadow` of each cell is dark.
uniform float bars = 0.0;
uniform float rails = 0.0;
uniform float shadow = 0.3;
// A greyscale picture over the card (the red channel), read from `mask_rect` (offset, size) of the texture.
uniform sampler2D mask : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Two world-space clip planes (`GlowClip`): a point is not drawn where dot(point, xyz) > w, so a glow
// stops at the wall it hangs on or stands near instead of showing in the room behind it. A plane with a
// zero normal is off (the defaults draw the picture the lot always had).
uniform vec4 clip_a = vec4(0.0);
uniform vec4 clip_b = vec4(0.0);

varying vec3 world_at;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	world_at = (INV_VIEW_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0))).xyz;
}

// 1 in the light between bars, 0 in a bar's shadow: `count` bars across 0..1, soft by a little of a cell.
float bar_light(float at, float count) {
	float cell = fract(at * (count + 1.0));
	float from_bar = min(cell, 1.0 - cell);
	float half_shadow = shadow * 0.5;
	return smoothstep(half_shadow, half_shadow + 0.08, from_bar);
}

void fragment() {
	if (dot(world_at, clip_a.xyz) > clip_a.w && dot(clip_a.xyz, clip_a.xyz) > 0.0) {
		discard;
	}
	if (dot(world_at, clip_b.xyz) > clip_b.w && dot(clip_b.xyz, clip_b.xyz) > 0.0) {
		discard;
	}
	float shape;
	if (card) {
		vec2 inside = min(UV, 1.0 - UV);
		vec2 soft = max(edge, vec2(0.001));
		shape = smoothstep(0.0, soft.x, inside.x) * smoothstep(0.0, soft.y, inside.y);
		shape *= 1.0 - fade * UV.y;
		if (bars > 0.0) {
			shape *= bar_light(UV.x, bars);
		}
		if (rails > 0.0) {
			shape *= bar_light(UV.y, rails);
		}
		shape *= texture(mask, mask_rect.xy + UV * mask_rect.zw).r;
	} else {
		float r = clamp(length(UV * 2.0 - 1.0), 0.0, 1.0);
		shape = pow(1.0 - r, falloff);
	}
	// The edge reaches exactly zero so no quad shows its square.
	ALBEDO = tint.rgb * energy * shape;
	ALPHA = 1.0;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// A cheap stand-in for light that a real light cannot afford in Compatibility (8 lights a mesh, no shadows):
// an additive quad whose brightness falls off from its centre. Laid flat on the asphalt it is the pool under a
// lamp; as a billboard it is the halo round a bulb, a sign or a breaker lamp. `energy` is what the lot's
// circuits drive (0 draws nothing).

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform float energy = 1.0;
// Higher is a tighter core with a softer skirt.
uniform float falloff = 2.0;
uniform bool billboard = false;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	float r = clamp(length(UV * 2.0 - 1.0), 0.0, 1.0);
	float shape = pow(1.0 - r, falloff);
	// The edge reaches exactly zero so no quad shows its square.
	ALBEDO = tint.rgb * energy * shape;
	ALPHA = 1.0;
}

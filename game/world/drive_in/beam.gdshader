shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Haze in the projector's beam: additive, brightest at the lens (vertex colour), softer towards the
// silhouette where a face turns edge-on to the eye, so the cone has no visible rim.

uniform vec4 tint : source_color = vec4(0.82, 0.88, 1.0, 1.0);
uniform float energy = 0.3;

void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(smoothstep(0.0, 0.9, face), 1.5);
	ALBEDO = tint.rgb * energy * COLOR.r * soft;
	ALPHA = 1.0;
}

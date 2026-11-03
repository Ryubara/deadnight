shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Haze in the projector's beam: additive, brightest at the lens (vertex colour), softer towards the
// silhouette where a face turns edge-on to the eye, so the cone has no visible rim.

uniform vec4 tint : source_color = vec4(0.82, 0.88, 1.0, 1.0);
uniform float energy = 0.3;
// The small map's lamp cones: haze closer to the eye than this (metres) fades out, so a camera that
// walks through a cone is not washed over by it. 0 (the projector's beam) leaves it as it was.
uniform float near_fade = 0.0;
// Two world-space clip planes, as in `glow.gdshader`: the small map's cones stop at a wall.
uniform vec4 clip_a = vec4(0.0);
uniform vec4 clip_b = vec4(0.0);

varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(world_at, clip_a.xyz) > clip_a.w && dot(clip_a.xyz, clip_a.xyz) > 0.0) {
		discard;
	}
	if (dot(world_at, clip_b.xyz) > clip_b.w && dot(clip_b.xyz, clip_b.xyz) > 0.0) {
		discard;
	}
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(smoothstep(0.0, 0.9, face), 1.5);
	if (near_fade > 0.0) {
		soft *= smoothstep(0.2 * near_fade, near_fade, -VERTEX.z);
	}
	ALBEDO = tint.rgb * energy * COLOR.r * soft;
	ALPHA = 1.0;
}

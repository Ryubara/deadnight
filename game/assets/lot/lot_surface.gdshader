shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// The lot's paint (tools/world/build_lot_textures.py writes this file): a greyscale pattern times a palette tint,
// projected in world space onto the face's dominant plane, metres_per_tile metres a repeat.
uniform sampler2D pattern : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float metres_per_tile = 2.0;

varying vec2 world_uv;

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 facing = abs((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 plane = vec2(at.x, -at.y);
	if (facing.y >= facing.x && facing.y >= facing.z) {
		plane = at.xz;
	} else if (facing.x > facing.z) {
		plane = vec2(at.z, -at.y);
	}
	world_uv = plane / metres_per_tile;
}

void fragment() {
	ALBEDO = tint.rgb * texture(pattern, world_uv).rgb;
	ROUGHNESS = 1.0;
}

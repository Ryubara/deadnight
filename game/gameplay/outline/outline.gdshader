shader_type spatial;
// One copy of the mesh pushed `reach` pixels along `direction` on the screen, drawn only outside the
// mesh's own silhouette (the stencil the mask pass wrote) and writing the stencil as it goes, so a
// pixel takes its colour once. Several copies in a ring around the body make an outline that is the
// same number of pixels wide at any distance, with no gaps at the hard edges of a low-poly mesh
// (an outline made by pushing vertices along their normals splits there), and that works on a
// skinned mesh, because the vertex function sees the pose.
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, blend_mix;
stencil_mode read, write, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.12, 1.0);
// The unit direction on the screen this copy moves along.
uniform vec2 direction = vec2(1.0, 0.0);
// How far it moves, in pixels of a 1080-high screen: scaled to the real height below, so the line
// is as thick relative to the picture on a phone, a window and a scaled-down render.
uniform float reach = 3.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pixels = reach * VIEWPORT_SIZE.y / 1080.0;
	clip.xy += direction * pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}

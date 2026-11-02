shader_type spatial;
// The first pass of an outline: writes 1 into the stencil buffer wherever the mesh is, in front of a
// wall or behind it (no depth test), and draws nothing. The passes that follow (outline.gdshader) draw
// only where the stencil is not 1, so the body stays unfilled and only its silhouette edge is coloured.
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, blend_mix;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}

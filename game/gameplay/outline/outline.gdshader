shader_type spatial;
// One copy of the mesh pushed `reach` pixels along `direction` on the screen, drawn only outside the
// mesh's own silhouette (the stencil the mask pass wrote), only where the mesh is hidden (its depth is
// behind what the scene drew there: the depth texture) and writing the stencil as it goes, so a
// pixel takes its colour once. Several copies in a ring around the body make an outline that is the
// same number of pixels wide at any distance, with no gaps at the hard edges of a low-poly mesh
// (an outline made by pushing vertices along their normals splits there), and that works on a
// skinned mesh, because the vertex function sees the pose.
// Back faces are culled: a copy's back face lies behind the body's own front face, which would count as
// hidden by it.
render_mode unshaded, depth_test_disabled, cull_back, fog_disabled, blend_mix;
stencil_mode read, write, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.12, 1.0);
// The unit direction on the screen this copy moves along.
uniform vec2 direction = vec2(1.0, 0.0);
// How far it moves, in pixels of a 1080-high screen: scaled to the real height below, so the line
// is as thick relative to the picture on a phone, a window and a scaled-down render.
uniform float reach = 3.0;
// What the scene's opaque things wrote into the depth buffer (a copy the renderer makes for a shader
// that asks, in Compatibility too). The body's own surface is in it where nothing hides it.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
// How much nearer than the mesh the scene has to be to hide it: a fixed part and a part per metre, for
// the depth buffer's precision
uniform float hidden_margin = 0.12;
uniform float hidden_margin_per_metre = 0.01;
// ... and how many times the depth buffer's step across the surface (see `hides_around`).
uniform float hidden_margin_slope = 4.0;

varying float own_depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pixels = reach * VIEWPORT_SIZE.y / 1080.0;
	clip.xy += direction * pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
	own_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

// The distance in front of the camera of what the scene drew at `uv`. Compatibility's depth buffer holds
// 0 to 1, so the clip depth is 2 * depth - 1.
float scene_distance_at(vec2 uv, mat4 inv_projection) {
	float depth = texture(scene_depth, uv).r;
	vec4 seen = inv_projection * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	return -seen.z / seen.w;
}

// True when what the scene drew round `uv` (the pixel and four a pixel and a half away) is nearer than
// `depth` by the margin. All of them have to be: a surface that is only a rounding away (the ground
// beside a foot) does not hide what is at `uv`. The margin grows with the surface's slope there: a foot
// that sinks a few centimetres into the ground is metres along the view where the ground is seen at a
// grazing angle, and a depth step of an occluder's edge only widens the margin on that pixel.
bool hides_around(vec2 uv, float depth, mat4 inv_projection, vec2 viewport) {
	vec2 step = 1.5 / viewport;
	float middle = scene_distance_at(uv, inv_projection);
	float right = scene_distance_at(uv + vec2(step.x, 0.0), inv_projection);
	float left = scene_distance_at(uv - vec2(step.x, 0.0), inv_projection);
	float up = scene_distance_at(uv - vec2(0.0, step.y), inv_projection);
	float down = scene_distance_at(uv + vec2(0.0, step.y), inv_projection);
	float far_most = max(max(max(middle, right), max(left, up)), down);
	float slope = max(abs(right - left), abs(up - down));
	return depth > far_most + hidden_margin + hidden_margin_per_metre * far_most + hidden_margin_slope * slope;
}

void fragment() {
	// A copy of the body shows the body's own surface here, which was drawn `shift` away on the screen
	// (y is up in clip space, down in the picture). The line belongs where that surface is hidden: the
	// scene is nearer than it both where the surface really is and where its copy lands. The first test
	// keeps the line off a body standing on the ground (the ground at the copy's pixel is nearer than the
	// foot, though it hides nothing); the second cuts the line at an occluder's edge instead of letting
	// it spill a line's width beyond.
	vec2 shift = vec2(direction.x, -direction.y) * reach * VIEWPORT_SIZE.y / 1080.0 / VIEWPORT_SIZE;
	float here = scene_distance_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	bool hidden_here = own_depth > here + hidden_margin + hidden_margin_per_metre * here;
	bool hidden_there = hides_around(SCREEN_UV - shift, own_depth, INV_PROJECTION_MATRIX, VIEWPORT_SIZE);
	if (!(hidden_here && hidden_there)) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}

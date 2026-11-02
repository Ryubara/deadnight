shader_type canvas_item;
// The lot at night: stars, a treeline, rows of parked cars, and the big screen throwing light on
// all of it, with the projector's beam crossing the dark. One procedural pass; no textures and
// no screen reads, so it is the same in the Compatibility renderer and on the web.

#include "res://addons/gds_ui/shaders/gds_hash.gdshaderinc"

uniform vec4 sky_top : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.12, 0.08, 0.16, 1.0);
uniform vec4 light_color : source_color = vec4(0.62, 0.76, 1.0, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float aspect = 1.7778;
// 0 freezes the flicker and the twinkle (reduced motion).
uniform float motion : hint_range(0.0, 1.0) = 1.0;

const float HORIZON = 0.7;
const vec2 SCREEN_CENTRE = vec2(0.83, 0.545);  // x is a fraction of the width
const vec2 SCREEN_HALF = vec2(0.22, 0.078);   // in heights
const vec2 BEAM_FROM = vec2(0.10, 1.2);       // x is a fraction of the width

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float box(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - half_size + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Silhouette of one parked car facing sideways: a body with wheel arches cut into it, a tyre in
// each arch (a thin ring of lit gravel shows round it), and a cabin with a raked windscreen and
// rear window, so the roofline and the wheels read even as a dark shape.
float car(vec2 p, float h) {
	float body = box(p - vec2(0.0, -h * 0.4), vec2(h * 2.1, h * 0.3), h * 0.16);
	// The cabin is a box whose front and back are cut slantwise by a line each: the windscreen
	// leans back from the bonnet, the rear window from the boot.
	float cabin = box(p - vec2(-h * 0.25, -h * 0.9), vec2(h * 1.4, h * 0.4), h * 0.1);
	float rake_front = dot(p - vec2(h * 1.05, -h * 0.7), normalize(vec2(1.0, -1.0)));
	float rake_back = dot(p - vec2(-h * 1.55, -h * 0.7), normalize(vec2(-1.0, -1.0)));
	cabin = max(cabin, max(rake_front, rake_back));
	float hull = min(body, cabin);
	vec2 front_wheel = vec2(h * 1.3, -h * 0.2);
	vec2 back_wheel = vec2(-h * 1.3, -h * 0.2);
	float arches = min(length(p - front_wheel), length(p - back_wheel)) - h * 0.46;
	float tyres = min(length(p - front_wheel), length(p - back_wheel)) - h * 0.37;
	return min(max(hull, -arches), tyres);
}

void fragment() {
	float t = TIME * motion;
	vec2 p = vec2(UV.x * aspect, UV.y);
	vec3 col = mix(sky_top.rgb, sky_horizon.rgb, smoothstep(0.0, HORIZON, UV.y));

	// What the big screen is showing: bright and cool, drifting, with the odd white-out.
	float level = 0.6 + 0.22 * vnoise(vec2(t * 2.2, 1.0)) + 0.18 * step(0.86, hash11(floor(t * 8.0)));
	vec2 sc = vec2(SCREEN_CENTRE.x * aspect, SCREEN_CENTRE.y);
	vec2 sp = p - sc;
	float sd = box(sp, SCREEN_HALF, 0.004);

	// Stars, thinning towards the glow and the horizon.
	vec2 sg = p * 90.0;
	vec2 cell = floor(sg);
	float star = step(0.985, hash21(cell));
	float twinkle = 0.55 + 0.45 * sin(t * (1.5 + hash21(cell + 4.0) * 3.0) + hash21(cell) * 40.0);
	float d_star = length(fract(sg) - 0.5);
	star *= (1.0 - smoothstep(0.0, 0.35, d_star)) * twinkle;
	col += vec3(0.85, 0.9, 1.0) * star * (1.0 - smoothstep(0.1, HORIZON, UV.y)) * 0.8;

	// The glow the screen throws on sky and ground.
	float glow = exp(-max(sd, 0.0) * 3.4) * 0.5 + exp(-max(sd, 0.0) * 11.0) * 0.45;
	col += light_color.rgb * glow * level * 0.95;
	col += warm_color.rgb * exp(-abs(UV.y - HORIZON) * 22.0) * 0.045;

	// Treeline: two octaves of noise as a ragged edge.
	float ridge = HORIZON - 0.02 - 0.05 * vnoise(vec2(p.x * 7.0, 2.0)) - 0.022 * vnoise(vec2(p.x * 29.0, 7.0));
	float tree = smoothstep(ridge, ridge + 0.002, UV.y);
	vec3 tree_col = vec3(0.012, 0.012, 0.025) + light_color.rgb * glow * level * 0.05;
	col = mix(col, tree_col, tree);

	// Ground in front of the trees, brighter under the screen.
	float ground = smoothstep(HORIZON - 0.004, HORIZON, UV.y);
	vec3 ground_col = mix(sky_horizon.rgb * 0.8, vec3(0.02, 0.018, 0.04), smoothstep(HORIZON, 1.2, UV.y));
	ground_col += light_color.rgb * exp(-max(sd, 0.0) * 2.6) * level * 0.32 * (1.0 - smoothstep(HORIZON, 1.0, UV.y) * 0.4);
	// A bright streak of the screen reflected in the lot's wet gravel.
	// (A squared product, not pow(): pow of a negative base is undefined in GLSL ES 3.0.)
	float streak_x = (p.x - sc.x) / 0.22;
	float streak = exp(-streak_x * streak_x) * smoothstep(HORIZON, HORIZON + 0.25, UV.y);
	ground_col += light_color.rgb * streak * level * 0.16 * (0.6 + 0.4 * vnoise(vec2(p.x * 40.0, UV.y * 6.0 + t)));
	col = mix(col, ground_col, ground);

	// The screen itself: its tower, then the picture.
	float legs = 0.0;
	legs += step(abs(abs(sp.x) - SCREEN_HALF.x * 0.6), 0.008) * step(SCREEN_HALF.y, sp.y) * step(sp.y, 0.3);
	col = mix(col, vec3(0.012, 0.012, 0.025), clamp(legs, 0.0, 1.0) * step(UV.y, HORIZON + 0.03));
	vec2 pic = sp / SCREEN_HALF;
	// The picture: a cool sky, a big warm sun and a ragged ridge, letterboxed, with film bands.
	float ridge_pic = 0.35 + 0.22 * vnoise(vec2(pic.x * 2.6 + 3.0, 1.0)) + 0.1 * vnoise(vec2(pic.x * 9.0, 4.0));
	vec3 picture = mix(light_color.rgb * 0.55, light_color.rgb * 1.05, (1.0 - smoothstep(-1.0, 1.0, pic.y)));
	float sun = 1.0 - smoothstep(0.0, 0.5, length(pic - vec2(-0.25 + 0.05 * sin(t * 0.3), -0.12)));
	picture = mix(picture, warm_color.rgb * 1.3, sun);
	picture = mix(picture, vec3(0.04, 0.03, 0.07), smoothstep(ridge_pic, ridge_pic + 0.03, pic.y));
	picture *= level * (0.94 + 0.06 * (0.5 + 0.5 * sin(pic.y * 70.0 + t * 8.0)));
	picture *= 1.0 - 0.5 * smoothstep(0.55, 1.1, length(pic * vec2(0.8, 1.0)));
	picture *= 1.0 - smoothstep(0.9, 0.98, abs(pic.y));
	float inside = 1.0 - smoothstep(-0.003, 0.003, sd);
	float frame = 1.0 - smoothstep(0.0, 0.016, sd);
	col = mix(col, vec3(0.02, 0.02, 0.035), frame * (1.0 - inside));
	col = mix(col, picture, inside);

	// Rows of parked cars: small and far, then big and near, dark against the lit gravel.
	for (int row = 0; row < 2; row++) {
		float h = row == 0 ? 0.038 : 0.105;
		float base = row == 0 ? 0.835 : 0.975;
		float spacing = h * 6.2;
		float shift = row == 0 ? 0.3 : 0.62;
		float idx = floor(p.x / spacing + shift);
		float lx = (p.x / spacing + shift - idx - 0.5) * spacing;
		float present = step(0.28, hash21(vec2(idx, float(row) * 13.0)));
		float lean = 0.85 + 0.3 * hash21(vec2(idx, 5.0 + float(row)));
		vec2 q = vec2(lx, p.y - base);
		float d = car(q, h * lean);
		float body = (1.0 - smoothstep(-0.0015, 0.0015, d)) * present;
		// Rim light on the edge that faces the screen.
		float rim = (1.0 - smoothstep(0.0, 0.012, -d)) * (1.0 - smoothstep(-h * 0.6, 0.0, q.y + h * 0.2));
		float toward = clamp((p.x - sc.x * 0.5) / (aspect * 0.5), 0.0, 1.0);
		vec3 car_col = vec3(0.006, 0.006, 0.014) + light_color.rgb * rim * level * 0.55 * (0.35 + 0.65 * toward);
		col = mix(col, car_col, body);
		// Windscreen glint from the big screen, and a taillight on some of the cars.
		float glint = (1.0 - smoothstep(0.0, h * 0.5, abs(q.y + h * 0.95))) * body * step(0.0, q.x + h * 0.3);
		col += light_color.rgb * glint * level * 0.1 * toward;
		float tail_on = step(0.5, hash21(vec2(idx, 31.0 + float(row))));
		float tail = (1.0 - smoothstep(0.0, h * 0.22, length(q - vec2(-h * 2.0 * lean, -h * 0.42)))) * present * tail_on;
		col += tail_color.rgb * tail * (0.55 + 0.25 * sin(t * 0.8 + idx));
	}

	// The projector's beam: a cone from below left to the screen, thick with dust.
	vec2 from = vec2(BEAM_FROM.x * aspect, BEAM_FROM.y);
	vec2 along_dir = normalize(sc - from);
	vec2 v = p - from;
	float along = dot(v, along_dir);
	float across = abs(v.x * along_dir.y - v.y * along_dir.x);
	float beam_len = length(sc - from);
	// Behind the projector `along` is negative: keep the spread positive so the edges stay ordered.
	float spread = max(along * 0.17, 0.001);
	float inside_beam = (1.0 - smoothstep(spread * 0.25, spread, across)) * smoothstep(0.1, 0.5, along) * (1.0 - smoothstep(beam_len - 0.45, beam_len, along));
	float dust = vnoise(p * 28.0 + vec2(t * 0.12, -t * 0.4));
	dust = smoothstep(0.55, 0.95, dust);
	col += light_color.rgb * inside_beam * (0.09 + dust * 0.22) * level;

	COLOR = vec4(col, 1.0);
}

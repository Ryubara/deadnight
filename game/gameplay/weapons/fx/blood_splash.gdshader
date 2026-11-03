shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// The blood a zombie throws when it is hit, one billboard quad and no texture: a blot at the wound,
// drops flung out along the shot (round ones, or streaks that shrink as they fly), a few flung back,
// and for a melee blow a tapering smear. The node's scale is the splash's diameter, so a position
// here is in half-widths of the quad (1.0 is the farthest a drop flies). Everything is a function of
// `progress` (0 to 1) and `seed`, so a capture and a test see the same splash. The numbers and why:
// docs/design/shot-feedback.md.

uniform vec4 colour : source_color = vec4(0.5, 0.025, 0.04, 1.0);
uniform vec4 highlight : source_color = vec4(0.82, 0.1, 0.1, 1.0);
uniform float progress = 0.0;
uniform float seed = 0.0;
// The way the blood flies, in the world (ZERO sprays all round).
uniform vec3 spray_dir = vec3(0.0, 0.0, 0.0);
uniform int drops : hint_range(1, 16) = 8;
// Half the angle the drops fan across, in radians.
uniform float cone = 0.7;
// The biggest drop's radius, the blot's radius, in half-widths.
uniform float drop_radius = 0.1;
uniform float blot_radius = 0.2;
uniform float streak = 0.5;
uniform float smear = 0.0;
// The share of drops flung back, and the pull of gravity on them (half-widths in the whole life).
uniform float back = 0.12;
uniform float fall = 0.35;

varying vec2 aim;
varying float side;
varying vec2 down;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
	// The shot's direction in the camera's plane; `side` is how much of it is across the view (a
	// shot straight away from the camera sprays all round the wound).
	vec3 d = (VIEW_MATRIX * vec4(spray_dir, 0.0)).xyz;
	side = length(d.xy);
	aim = side > 0.001 ? d.xy / side : vec2(0.0, 1.0);
	vec2 g = (VIEW_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xy;
	down = length(g) > 0.001 ? normalize(g) : vec2(0.0, -1.0);
}

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

// Distance from p to the segment a-b.
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float px = max(fwidth(length(p)), 0.002);
	float t = progress;
	float fly = 1.0 - (1.0 - t) * (1.0 - t);
	float base = atan(aim.y, aim.x);
	float spread = mix(3.14159, cone, smoothstep(0.15, 0.7, side));
	float shrink = 1.0 - smoothstep(0.55, 1.0, t);

	// Drops.
	float cover = 0.0;
	float wet = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= drops) {
			break;
		}
		float fi = float(i);
		float r1 = hash(fi + 1.0);
		float r2 = hash(fi + 21.0);
		float r3 = hash(fi + 41.0);
		float angle = base + (r1 * 2.0 - 1.0) * spread;
		if (hash(fi + 61.0) < back) {
			angle += 3.14159;
		}
		float dist = (0.35 + 0.65 * r2) * mix(0.55, 1.0, side);
		vec2 dir = vec2(cos(angle), sin(angle));
		vec2 head = dir * dist * fly + down * fall * t * t * (0.4 + r3);
		float len = dist * streak * 0.5 * (1.0 - t) * (0.4 + r3);
		vec2 tail = head - dir * len;
		float radius = drop_radius * (0.35 + 0.65 * r3) * shrink;
		float d = seg(p, tail, head) - radius;
		float inside = 1.0 - smoothstep(-px, px, d);
		cover = max(cover, inside);
		// A lighter glint toward the upper left of each drop, the toon wet look.
		wet = max(wet, inside * (1.0 - smoothstep(radius * 0.2, radius * 0.7, length(p - head - vec2(-0.28, 0.28) * radius))));
	}

	// The blot at the wound: a lumpy disc that opens and goes in the first third.
	float open = 1.0 - (1.0 - min(t * 3.0, 1.0)) * (1.0 - min(t * 3.0, 1.0));
	float lump = 1.0 + 0.22 * sin(atan(p.y, p.x) * 3.0 + seed) + 0.12 * sin(atan(p.y, p.x) * 5.0 + seed * 2.3);
	float blot_r = blot_radius * open * lump * (1.0 - smoothstep(0.35, 0.7, t));
	float blot = 1.0 - smoothstep(blot_r - px, blot_r + px, length(p));
	cover = max(cover, blot);
	wet = max(wet, blot * (1.0 - smoothstep(blot_r * 0.2, blot_r * 0.6, length(p - vec2(-0.3, 0.3) * blot_r))));

	// A melee blow's smear: a tapering streak along the blow.
	if (smear > 0.0) {
		vec2 perp = vec2(-aim.y, aim.x);
		float u = dot(p, aim);
		float v = dot(p, perp);
		float length_s = smear * 0.95 * fly;
		float k = clamp(u / max(length_s, 0.001), 0.0, 1.0);
		float width = blot_radius * 0.9 * pow(1.0 - k, 0.8) * (1.0 + 0.2 * sin(u * 24.0 + seed));
		float s = (1.0 - smoothstep(-px, px, abs(v) - width)) * step(-blot_radius * 0.5, u) * step(u, length_s);
		s *= 1.0 - smoothstep(0.5, 1.0, t);
		cover = max(cover, s);
	}

	ALBEDO = mix(colour.rgb, highlight.rgb, wet);
	ALPHA = cover * colour.a;
}

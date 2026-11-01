// The drive-in's night sky: a deep gradient, a hazy horizon that the fog fades into, faint light from the
// screen's side, a field of small stars and a moon. Drawn once per sky pixel and never moving (it reads no clock), so the
// sky's radiance, which lights shiny surfaces, is baked once. Works in the Compatibility renderer.
shader_type sky;

// The direction towards the moon; the scene's Moon light shines the opposite way (a test keeps them equal).
uniform vec3 moon_direction = vec3(0.3, 0.62, -0.72);
uniform vec3 zenith_color : source_color = vec3(0.02, 0.03, 0.09);
uniform vec3 mid_color : source_color = vec3(0.04, 0.07, 0.18);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.11, 0.26);
uniform vec3 ground_color : source_color = vec3(0.03, 0.05, 0.12);
// The glow of the screen over the north horizon.
uniform vec3 screen_glow_direction = vec3(0.0, 0.0, -1.0);
uniform vec3 screen_glow_color : source_color = vec3(0.2, 0.3, 0.55);
uniform vec3 moon_color : source_color = vec3(0.86, 0.92, 1.0);
uniform float moon_radius : hint_range(0.01, 0.2) = 0.045;
uniform float moon_halo : hint_range(0.0, 1.0) = 0.35;
// Stars: a grid of `star_scale` cells across a radian; one in `star_chance` has a star.
uniform float star_scale = 46.0;
uniform float star_chance : hint_range(0.0, 1.0) = 0.05;
uniform float star_size : hint_range(0.05, 0.5) = 0.22;
uniform float star_brightness = 1.3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash31(vec3 p) {
	return vec3(hash13(p), hash13(p + 17.1), hash13(p + 41.7));
}

vec3 stars(vec3 dir) {
	vec3 p = dir * star_scale;
	vec3 cell = floor(p);
	if (hash13(cell) > star_chance) {
		return vec3(0.0);
	}
	vec3 centre = cell + 0.25 + 0.5 * hash31(cell + 7.0);
	// The star is a point on the sphere's shell: measure across the sky, not through the cell.
	float d = length(p - centre);
	float shine = smoothstep(star_size, 0.0, d);
	// A few warm, a few cool, most white-blue.
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.65), step(0.85, hash13(cell + 3.0)));
	float size_roll = 0.35 + 0.65 * hash13(cell + 11.0);
	return tint * shine * size_roll * star_brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	// Above the horizon: horizon to mid to zenith. Below: the dark the fog blends into.
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.25, up));
	col = mix(col, zenith_color, smoothstep(0.2, 0.9, up));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, up));
	// The screen's light, strongest low over the north.
	vec3 flat_dir = normalize(vec3(dir.x, 0.0, dir.z) + vec3(0.0001));
	float toward = max(dot(flat_dir, normalize(screen_glow_direction)), 0.0);
	col += screen_glow_color * pow(toward, 4.0) * smoothstep(0.55, 0.0, up) * smoothstep(-0.1, 0.05, up);
	// Stars fade into the haze near the horizon and are hidden behind the moon's glare.
	float moon_cos = dot(dir, normalize(moon_direction));
	float angle = acos(clamp(moon_cos, -1.0, 1.0));
	float star_fade = smoothstep(0.02, 0.35, up) * smoothstep(moon_radius * 2.0, moon_radius * 10.0, angle);
	col += stars(dir) * star_fade;
	// The moon: a disc with a soft edge, and a halo.
	float disc = smoothstep(moon_radius, moon_radius * 0.88, angle);
	float halo = moon_halo * exp(-angle * 7.0);
	col += moon_color * (halo * 0.5 + disc * 2.2);
	COLOR = col;
}

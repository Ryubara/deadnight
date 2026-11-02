shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// The toon muzzle flash, in one quad and no texture: a hard-edged spiky star (`shape` 0) or a teardrop
// tongue along the barrel (`shape` 1), two flat colours (an orange rim round a pale core), anti-aliased
// on the edge only. The script turns the quad to face the camera (and spins the star) when a shot is
// fired: it lives two frames. Additive and unshaded, so it costs one transparent quad and no light slot. Also the
// spark of an impact at a small size. docs/design/shot-feedback.md has the numbers.

uniform vec4 rim_colour : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 core_colour : source_color = vec4(1.0, 0.92, 0.6, 1.0);
// 0 a star, 1 a tongue (pointing along +U, the quad's right).
uniform float shape = 0.0;
// Points of the star.
uniform float spikes = 5.0;
// 0 a round blob, 1 spikes all the way in to the core.
uniform float spike_depth = 0.6;
// How much of the star the pale core fills.
uniform float core_size = 0.42;
uniform float energy = 1.0;
// A flat disc of the rim colour behind the star, at this brightness (0 draws none), for a star that fills only `star_fill`
// of the quad (1 fills it all, as the impact sparks do).
uniform float halo = 0.0;
uniform float star_fill = 1.0;

float star_edge(vec2 p) {
	float angle = atan(p.y, p.x);
	// 1 on a spike, 0 between two.
	float ray = pow(abs(cos(angle * spikes * 0.5)), 3.0);
	return mix(1.0 - spike_depth, 1.0, ray);
}

// Inside the shape scaled by `scale`: 1 inside, 0 outside, a pixel of blend on the edge.
float inside(vec2 p, float scale) {
	float edge;
	float dist;
	if (shape < 0.5) {
		edge = star_edge(p) * scale;
		dist = length(p);
	} else {
		float t = clamp((p.x + 0.2) / 1.2, 0.0, 1.0);
		edge = 0.4 * (1.0 - t) * scale;
		dist = abs(p.y);
		if (p.x < -0.2) {
			dist = 9.0;
		}
	}
	float pixel = max(fwidth(dist), 0.0001);
	return 1.0 - smoothstep(edge - pixel, edge, dist);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 q = p / star_fill;
	float outer = inside(q, 1.0);
	float inner = inside(q, core_size);
	vec3 colour = mix(rim_colour.rgb, core_colour.rgb, inner) * energy;
	float disc = 0.0;
	if (halo > 0.0) {
		float d = length(p);
		float pixel = max(fwidth(d), 0.0001);
		disc = (1.0 - smoothstep(0.96 - pixel, 0.96, d)) * halo;
	}
	// Where only the glow is, the glow's colour; the star over it.
	ALBEDO = mix(rim_colour.rgb * energy, colour, outer);
	ALPHA = max(outer, disc);
}

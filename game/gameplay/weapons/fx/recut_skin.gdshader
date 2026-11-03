shader_type spatial;
// The re-cut skin (Deadnight #787, docs/research/recut-skin.md): the look a weapon wears for as long as it is
// held re-cut. It stands in the weapon's own palette material (the same surface, the same draw call, the palette
// texture sampled here), so a model needs no texture work of its own: whatever mesh wears it gets
//   - a colder, harder base (the palette's colours kept, but pulled toward ink blue and made metal),
//   - a lattice of cells and trace lines drawn from the model's own coordinates (so it does not swim as the
//     weapon moves), a share of the cells burning and blinking,
//   - a bright pulse that runs down the barrel's length every few seconds,
//   - a fresnel rim, the colour that says "upgraded" from across a room,
//   - a slow breath over all of it.
// `reveal` sweeps the skin on from the butt to the muzzle (the ignition when it is bought, the press' strike on the
// bench) and `boost` is a flash over everything. Both are 1 and 0 for a weapon that has simply been worn a while.
// No extra lights, no second pass, no blending: the Compatibility renderer and a phone pay for one lit
// surface, as they did before.
render_mode cull_disabled;

// The weapon's own palette (a swatch a part), copied from its material by `RecutSkin`.
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec4 base_colour : source_color = vec4(1.0);
uniform float base_metallic = 0.4;
uniform float base_roughness = 0.415;

// The colours: the shadows of the skin, the light of its cells and the white of its pulse.
uniform vec4 deep : source_color = vec4(0.03, 0.07, 0.16, 1.0);
uniform vec4 cold : source_color = vec4(0.1, 0.62, 1.0, 1.0);
uniform vec4 spark : source_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform vec4 fringe : source_color = vec4(0.55, 0.3, 1.0, 1.0);
// How far the palette is pulled toward `deep` (0 keeps the weapon's colours), and the metal it is given.
uniform float darken : hint_range(0.0, 1.0) = 0.55;
uniform float skin_metallic : hint_range(0.0, 1.0) = 0.85;
uniform float skin_roughness : hint_range(0.0, 1.0) = 0.32;

// The lattice, in the model's own units (metres at the weapon's real length): a cell, the width of its trace,
// the share of cells that burn and how fast they blink.
uniform float cell_size = 0.03;
uniform float line_width = 0.05;
uniform float live_share = 0.2;
uniform float blink_rate = 1.6;
// The pulse down the barrel: bands a metre, and how fast they run.
uniform float wave_frequency = 1.7;
uniform float wave_speed = 0.55;
// The rim's tightness and the strength of the glow (the emission's multiplier).
uniform float rim_power = 2.6;
uniform float glow = 1.5;
uniform float breath_rate = 1.8;

// 0 to 1: how far the skin has swept over the weapon, from the butt (+X) to the muzzle (-X), across the
// model's length along X (`span`: the model's lowest and highest X). `edge` is the width of the front.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform vec2 span = vec2(-0.5, 0.5);
uniform float edge = 0.22;
// A flash over everything (the press' strike), added to the glow.
uniform float boost : hint_range(0.0, 4.0) = 0.0;

// The mesh's place in the weapon (its node's transform up to the weapon's root): the lattice and the pulse run
// across the whole weapon, not from the origin of each of its parts.
uniform mat4 to_root = mat4(1.0);

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = (to_root * vec4(VERTEX, 1.0)).xyz;
	model_normal = mat3(to_root) * NORMAL;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 paint = texture(palette, UV) * base_colour;

	// How much of the skin is here: the sweep's front passes each point once.
	float along = clamp((span.y - model_position.x) / max(span.y - span.x, 0.001), 0.0, 1.0);
	float skin = clamp((reveal * (1.0 + edge) - along) / edge, 0.0, 1.0);
	float front = 4.0 * skin * (1.0 - skin);

	// The lattice on the face this point lies on (a face of the model is flat to one of its axes), turned
	// a quarter so the cells are diamonds: scales, not the squares of a tiled floor.
	vec3 facing = abs(model_normal);
	vec2 plane = model_position.yz;
	float seed = 1.0;
	if (facing.z >= facing.x && facing.z >= facing.y) {
		plane = model_position.xy;
		seed = 3.0;
	} else if (facing.y >= facing.x) {
		plane = model_position.xz;
		seed = 2.0;
	}
	vec2 grid = (mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * plane) / cell_size;
	vec2 cell = floor(grid);
	vec2 inside = fract(grid);
	vec2 to_edge = min(inside, 1.0 - inside);
	float nearest = min(to_edge.x, to_edge.y);
	float aa = max(fwidth(grid.x), fwidth(grid.y));
	float line = 1.0 - smoothstep(line_width, line_width + aa + 0.03, nearest);
	// A trace is one edge of a cell, and only some edges are wired: the rest is seam.
	bool upright = to_edge.x < to_edge.y;
	vec2 edge_key = upright ? vec2(round(grid.x), cell.y) : vec2(cell.x + 57.0, round(grid.y));
	float wired = step(0.4, hash21(edge_key + seed * 31.0));
	float trace = line * mix(0.18, 1.0, wired);
	float luck = hash21(cell + seed * 17.0);
	float live = step(1.0 - live_share, luck);
	float blink = 0.5 + 0.5 * sin(TIME * blink_rate * (0.6 + luck) + luck * 40.0);
	float cell_light = live * (0.15 + 0.85 * blink) * (1.0 - line);

	// The pulse: a band that runs from the butt to the muzzle, lighting the traces it crosses.
	float run = fract(model_position.x * wave_frequency + TIME * wave_speed);
	float pulse = smoothstep(0.8, 1.0, run) * (1.0 - smoothstep(0.98, 1.0, run) * 0.5);
	float breath = 0.78 + 0.22 * sin(TIME * breath_rate);

	// The swatch's brightness stays in the skin, so a grip, a barrel and a brass band still read apart.
	float swatch = dot(paint.rgb, vec3(0.299, 0.587, 0.114));
	vec3 tinted = mix(paint.rgb, deep.rgb * (0.6 + 2.2 * swatch), darken);
	ALBEDO = mix(paint.rgb, tinted, skin);
	METALLIC = mix(base_metallic, skin_metallic, skin);
	ROUGHNESS = mix(base_roughness, skin_roughness, skin);

	// The rim, with a violet fringe at the very edge: the oil-slick shift of a thing from somewhere else.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 rim_colour = mix(cold.rgb, fringe.rgb, smoothstep(0.55, 1.0, rim));
	vec3 light = cold.rgb * (0.5 * trace * breath + 0.7 * cell_light * breath);
	light += rim_colour * 1.1 * rim * breath;
	light += spark.rgb * (pulse * (0.2 + 1.1 * trace) + 0.3 * rim * rim);
	// The front of the sweep burns white as it goes by.
	light += spark.rgb * front * 1.6;
	EMISSION = (light * skin * glow) + (boost * cold.rgb * (0.4 + 0.6 * swatch));
}

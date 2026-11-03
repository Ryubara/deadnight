shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

// The small map's outside backdrop (issue #638): palette-atlas models past the playable bounds, seen through windows
// and broken walls. Two reasons it lights and fogs itself instead of taking the renderer's light and fog:
// - The map's own fog is dense indoors (about 0.035) and would sink everything past 40 m into the fog colour. Here the
//   haze follows the scene's fog near and is capped far, so the screen, the cars and the trees 100 m out still read as
//   layered silhouettes.
// - Unshaded, a backdrop mesh takes no light pass (Compatibility draws a pass per light that reaches a mesh) and only
//   the moon and the ambient light it: a lamp indoors never lights the drive-in.
// `Backdrop` copies the environment's ambient and fog and the moon's light into these uniforms every frame (their
// energies applied), so the round's darkening (`NightLight`) reaches the backdrop too. The colours are sRGB values as
// they are: the Compatibility renderer lights in sRGB space, and the lot's fog colour passed through `srgb_to_linear`
// came out ten times too dark.

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec3 ambient = vec3(0.0725, 0.0866, 0.1318);
uniform vec3 moon_color = vec3(0.2216, 0.2541, 0.3276);
// World direction towards the moon.
uniform vec3 moon_direction = vec3(0.3011, 0.6222, -0.7226);
uniform vec3 haze_color = vec3(0.086, 0.133, 0.29);
uniform float fog_density = 0.013;
// The haze never passes `haze_near` at 20 m and `haze_far` at 150 m, rising between.
uniform float haze_near = 0.5;
uniform float haze_far = 0.82;
// How much brighter than the fog the haze is at 150 m.
uniform float horizon_gain = 2.2;
// Atlas cells (index = column + 5 x row) that glow: the drive-in atlas's Amber (6) bulbs and its Pink (19) neon.
// -1 is none. The props atlas has other colours in those cells, so its material sets both to -1.
uniform int glow_cell_a = -1;
uniform int glow_cell_b = -1;
uniform float glow_energy = 2.5;

void fragment() {
	vec3 albedo = texture(atlas, UV).rgb * COLOR.rgb;
	vec3 to_moon = normalize((VIEW_MATRIX * vec4(moon_direction, 0.0)).xyz);
	vec3 lit = albedo * (ambient + moon_color * max(dot(NORMAL, to_moon), 0.0));
	// Godot's UV starts at the image's top, where the atlas's first row is.
	int cell = int(floor(UV.x * 5.0)) + 5 * int(floor(UV.y * 5.0));
	if (cell == glow_cell_a || cell == glow_cell_b) {
		lit += albedo * glow_energy;
	}
	float d = length(VERTEX);
	float far = smoothstep(20.0, 150.0, d);
	float cap = mix(haze_near, haze_far, far);
	// Far off, the haze brightens towards the sky's horizon (lit by the screen), so the layers part.
	vec3 haze = haze_color * mix(1.0, horizon_gain, far);
	ALBEDO = mix(lit, haze, min(1.0 - exp(-fog_density * d), cap));
}

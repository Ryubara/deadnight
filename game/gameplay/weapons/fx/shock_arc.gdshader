shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
#include "res://addons/gds_ui/shaders/gds_hash.gdshaderinc"

// The reload shock, in one flat quad on the ground and no texture (docs/design/perks.md): a ring that runs
// out to the shock's radius, jagged bolts that fork from the player to the ring, and a flash at the
// middle, in the game's toon style: two flat colours (an electric rim round a pale core), hard edges,
// anti-aliased on the edge only, like the muzzle flash (`flash_star.gdshader`). Additive and unshaded:
// one transparent quad, no light slot, and nothing a Compatibility renderer or a browser lacks (no screen
// texture, no depth texture, no dynamic loops, a sine-free hash).
//
// `progress` runs 0 to 1 over the effect's life; the script sets it each frame. `seed` makes each
// shock's bolts different; it is changed a few times a second so they crackle.

uniform vec4 rim_colour : source_color = vec4(0.15, 0.5, 1.0, 1.0);
uniform vec4 core_colour : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
// Bolts round the ring; odd, so the seam of atan() falls between two of them.
uniform float bolts = 7.0;
uniform float energy = 1.5;
// How far a bolt's zig-zag swings off its straight line, in radians, and the pieces it is cut into.
uniform float jag = 0.32;
uniform float pieces = 6.0;

const float TAU_F = 6.28318530718;

// The distance (as a share of the quad's half width) between a point and the zig-zag of the bolt in its
// sector, and 0 to 1 along it.
float bolt_distance(float angle, float r, float sector) {
	float index = floor(angle / sector + 0.5);
	float local = angle - index * sector;
	float slot = mod(index + bolts, bolts);
	float t = r * pieces;
	float piece = floor(t);
	float a = hash21(vec2(piece, slot + seed)) - 0.5;
	float b = hash21(vec2(piece + 1.0, slot + seed)) - 0.5;
	float offset = mix(a, b, fract(t)) * jag * min(r * 3.0, 1.0);
	return abs(local - offset) * r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float sector = TAU_F / bolts;
	float pixel = max(fwidth(r), 0.0001);
	// The ring runs out fast and slows, thinning as it goes.
	float run = 1.0 - (1.0 - progress) * (1.0 - progress);
	float radius = 0.08 + 0.9 * run;
	float width = mix(0.07, 0.02, progress);
	float ring_d = abs(r - radius);
	float ring = 1.0 - smoothstep(width - pixel, width, ring_d);
	float ring_core = 1.0 - smoothstep(width * 0.4 - pixel, width * 0.4, ring_d);
	// The bolts reach the ring and fade at its tip; they live in the first part of the shock.
	float reach = 1.0 - smoothstep(radius - 0.05, radius, r);
	float live = 1.0 - smoothstep(0.55, 0.95, progress);
	float d = bolt_distance(angle, max(r, 0.001), sector);
	float thick = mix(0.045, 0.012, r) * (0.6 + 0.4 * live);
	float bolt_pixel = max(fwidth(d), 0.0001);
	float bolt = (1.0 - smoothstep(thick - bolt_pixel, thick, d)) * reach * live;
	float bolt_core = (1.0 - smoothstep(thick * 0.4 - bolt_pixel, thick * 0.4, d)) * reach * live;
	// The flash at the middle, in the first moments.
	float flash_size = 0.15 * (1.0 - smoothstep(0.0, 0.3, progress));
	float flash = 1.0 - smoothstep(flash_size - pixel, flash_size, r);
	// A pale disc inside the ring, hardly there, so the ground it covers reads as charged.
	float disc = (1.0 - smoothstep(radius - pixel, radius, r)) * 0.12 * (1.0 - progress);
	float coverage = max(max(ring, bolt), max(flash, disc));
	float core = max(max(ring_core, bolt_core), flash);
	float fade = 1.0 - smoothstep(0.8, 1.0, progress);
	ALBEDO = mix(rim_colour.rgb, core_colour.rgb, core) * energy;
	ALPHA = coverage * fade;
}

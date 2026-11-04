shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// The wings' body (a cosmetic-tier test, issue #1053; not shipped): near-black feathers with a blue ember along the
// edge and the tip, so the silhouette reads in the dark before any flame is added. One opaque surface.

uniform vec3 body : source_color = vec3(0.025, 0.03, 0.07);
uniform vec3 ember : source_color = vec3(0.08, 0.38, 1.0);

void fragment() {
	float edge = pow(abs(UV.x * 2.0 - 1.0), 2.5);
	float tip = smoothstep(0.55, 1.0, UV.y);
	float rib = 1.0 - smoothstep(0.0, 0.08, abs(UV.x - 0.5));
	vec3 col = body + ember * (edge * 0.55 + tip * 0.4 + rib * 0.15);
	ALBEDO = col;
}

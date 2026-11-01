shader_type canvas_item;
// A projector iris. Closing (reveal = 0) the circle shrinks toward `origin`; opening
// (reveal = 1) it grows from the same point. A warm rim rides the edge. Procedural; it never
// samples the screen, so it is safe in the Compatibility renderer and WebGL2.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.5, 0.5);
uniform float aspect = 1.7778;
uniform float max_dist = 1.2;
uniform float rim_width : hint_range(0.01, 0.2) = 0.05;

// The colours are the tokens iris_shade, iris_rim and iris_rim_hot; UITransitionShader sets them,
// and these defaults only cover a shader previewed on its own.
uniform vec3 iris_shade = vec3(0.02, 0.015, 0.02);
uniform vec3 iris_rim = vec3(1.0, 0.72, 0.3);
uniform vec3 iris_rim_hot = vec3(1.0, 0.95, 0.8);

void fragment() {
	vec2 centred = (UV - origin) * vec2(aspect, 1.0);
	float dist = length(centred) / max_dist;
	float open = reveal > 0.5 ? progress : 1.0 - progress;
	// Slight wobble, like a hand-cranked iris; it fades out as the circle closes to a point.
	// (The nudge keeps atan defined at the exact origin.)
	float angle = atan(centred.y, centred.x + 0.00001);
	dist += 0.006 * sin(angle * 7.0 + progress * 6.0) * smoothstep(0.0, 0.3, open);
	// The radius runs from just inside zero to past the corners, so the rim leaves the frame.
	float radius = open * (1.0 + rim_width * 3.0) - rim_width;
	float outside = dist - radius;
	vec4 colour = vec4(iris_shade, 1.0);
	if (outside < -rim_width) {
		colour = vec4(0.0);
	} else if (outside < 0.0) {
		// Inside the edge: a soft warm glow that brightens toward the rim.
		float t = (outside + rim_width) / rim_width;
		colour = vec4(mix(iris_rim, iris_rim_hot, t), smoothstep(0.0, 1.0, t) * 0.9);
	} else if (outside < rim_width) {
		// Outside the edge: the hot rim cools into the black.
		float t = outside / rim_width;
		colour = vec4(mix(iris_rim_hot, iris_shade, smoothstep(0.0, 0.7, t)), 1.0);
	}
	COLOR = colour;
}

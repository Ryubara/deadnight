// Sine-free hashes (Hoskins' hash11 and hash12), shared by a game's own skin shaders and the film burn.
// `fract(sin(x) * 43758.5)` loses precision at large arguments, shows stripes and differs between
// GPUs; these use only fract, multiply and add, so a desktop and a WebGL2 browser agree.
// Both take any real input (negative too) and return a value in [0, 1).

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

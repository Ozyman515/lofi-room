shader_type spatial;
render_mode unshaded;

// Low-poly buildings: each one gets its own tint and window pattern, hazier the farther it is.

uniform vec3 near_color : source_color = vec3(0.16, 0.05, 0.22);
uniform vec3 alt_color : source_color = vec3(0.09, 0.08, 0.30);
uniform vec3 haze_color : source_color = vec3(0.82, 0.31, 0.62);
uniform vec3 window_color : source_color = vec3(1.6, 1.1, 0.6);
uniform float haze_start = 10.0;
uniform float haze_end = 70.0;
uniform float flash = 0.0;      // lightning lights the city up

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// straight-ahead rows keep the old haze; buildings wrapped around to the sides stay hazy too
	float dist = max(-wpos.z, 0.7 * length(wpos.xz));
	float haze = smoothstep(haze_start, haze_end, dist);
	float seed = MODEL_MATRIX[3].x * 3.1 + MODEL_MATRIX[3].z * 1.7;
	float tint = hash(vec2(seed, 5.0));

	vec3 col = mix(near_color, alt_color, tint) * (0.8 + 0.8 * hash(vec2(seed, 9.0)));
	col = mix(col, haze_color, haze);
	col *= 1.0 + 0.3 * wnrm.x;   // left-facing sides darker, right-facing lighter

	if (wnrm.y < 0.5) {
		float k = max(1.0, dist / 14.0);   // bigger windows far away so they don't shimmer
		vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), wnrm));
		if (tang.x + tang.z < 0.0) {
			tang = -tang;
		}
		float u = dot(wpos, tang);
		vec2 cell = vec2(u * 2.0, wpos.y * 1.6) / k;
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float on = step(0.55 + 0.25 * tint, hash(id + seed));
		float inside = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75);
		col = mix(col, window_color, on * inside * (1.0 - haze * 0.7));
	}
	col += vec3(0.55, 0.6, 0.95) * flash;
	ALBEDO = col;
}

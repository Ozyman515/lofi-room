shader_type sky;

// Dusk sky for the whole world: no edges, no rectangle. Pink at the horizon, purple above,
// with a faint far skyline all the way around and a soft haze below the horizon.

uniform vec3 sky_top : source_color = vec3(0.30, 0.06, 0.38);
uniform vec3 sky_bottom : source_color = vec3(1.0, 0.40, 0.64);
uniform vec3 far_color : source_color = vec3(0.82, 0.31, 0.62);
uniform vec3 below_color : source_color = vec3(0.36, 0.09, 0.42);
uniform float overcast : hint_range(0.0, 1.0) = 0.0;   // 0 = clear dusk, 1 = heavy storm clouds
uniform float snowy : hint_range(0.0, 1.0) = 0.0;      // pale grey-pink instead of dark slate
uniform float flash = 0.0;                              // lightning

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// A sprinkle of faint stars; they twinkle a little and fade out as the clouds roll in.
float stars(vec3 d, float time) {
	vec3 p = d * 70.0;
	vec3 c = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash3(c);
	if (h < 0.951) {
		return 0.0;
	}
	vec3 off = (vec3(hash3(c + 1.7), hash3(c + 4.1), hash3(c + 9.3)) - 0.5) * 0.6;
	float d2 = length(f - off);
	float tw = 0.65 + 0.35 * sin(time * (1.0 + h * 3.0) + h * 40.0);
	return smoothstep(0.16, 0.0, d2) * tw * (0.35 + 0.65 * (h - 0.951) / 0.049);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col = mix(sky_bottom, sky_top, smoothstep(-0.02, 0.55, y));
	col += vec3(1.0, 0.55, 0.65) * 0.18 * exp(-abs(y) * 7.0);

	float az = atan(d.x, -d.z);
	float far_h = 0.015 + hash(floor(az * 14.0) + 3.0) * 0.06;
	if (y < far_h) {
		col = mix(far_color, below_color, smoothstep(0.0, -0.45, y));
	}
	// weather: pull everything towards a cloud colour, darker for storms, paler for snow
	vec3 cloud = mix(vec3(0.20, 0.10, 0.30), vec3(0.62, 0.50, 0.68), snowy);
	cloud *= mix(1.0, 0.55, max(overcast - snowy * 0.5, 0.0));
	float streak = 0.5 + 0.5 * sin(atan(d.x, -d.z) * 5.0 + y * 9.0);
	cloud *= 0.85 + 0.3 * streak * smoothstep(0.0, 0.6, y);
	col = mix(col, cloud + vec3(0.12, 0.05, 0.14) * exp(-abs(y) * 5.0), overcast * 0.85);
	float star_vis = (1.0 - smoothstep(0.30, 0.70, overcast)) * smoothstep(0.06, 0.40, y) * (1.0 - clamp(flash * 1.5, 0.0, 1.0));
	col += vec3(1.0, 0.92, 0.98) * stars(d, TIME) * 0.55 * star_vis;
	col += vec3(0.75, 0.80, 1.0) * flash * (0.35 + 0.65 * smoothstep(-0.1, 0.6, y));
	COLOR = col;
}

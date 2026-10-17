shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

// The tornado funnel: dark swirling cloud with streaks that spiral around it, bending as it sways.
uniform float t = 0.0;
uniform float flash = 0.0;
uniform float height = 4.4;
uniform float sway_k = 1.0;
uniform float fade = 1.0;
uniform float swirl_speed = 1.0;
uniform vec3 tint = vec3(0.30, 0.27, 0.34);

varying float vh;
varying vec3 vnrm;
varying vec3 vpos;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// value noise that repeats every `period` cells in x, so the funnel has no seam
float vn(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(vec2(mod(i.x, period), i.y));
	float b = h21(vec2(mod(i.x + 1.0, period), i.y));
	float c = h21(vec2(mod(i.x, period), i.y + 1.0));
	float d = h21(vec2(mod(i.x + 1.0, period), i.y + 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vh = VERTEX.y / height + 0.5;
	VERTEX.x += (sin(t * 1.1 + vh * 3.0) * 0.20 + sin(vh * 5.0 - t * 1.7) * 0.09) * vh * sway_k;
	VERTEX.z += sin(t * 0.9 + vh * 2.5) * 0.10 * vh * sway_k;
	vnrm = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vpos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float n1 = vn(vec2(u * 12.0 + vh * 4.0 - t * swirl_speed * 1.2, vh * 9.0 - t * 0.5), 12.0);
	float n2 = vn(vec2(u * 24.0 - vh * 8.0 + t * swirl_speed * 1.8, vh * 20.0 + t * 0.3), 24.0);
	float n = n1 * 0.6 + n2 * 0.4;
	vec3 col = mix(vec3(0.03, 0.03, 0.06), tint, n);
	col *= 0.6 + 0.5 * vh;
	col += vec3(0.45, 0.50, 0.85) * flash * 0.30;
	float rim = pow(clamp(abs(dot(normalize(vnrm), normalize(-vpos))), 0.0, 1.0), 0.5);
	ALBEDO = col;
	ALPHA = fade * clamp((0.80 + 0.20 * n) * (0.50 + 0.50 * (1.0 - rim)) * smoothstep(0.0, 0.06, vh) * (1.0 - 0.15 * vh * vh), 0.0, 1.0);
}

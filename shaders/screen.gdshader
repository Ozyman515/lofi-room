shader_type spatial;
render_mode unshaded, fog_disabled;

// PC monitor. Shows media/monitor.gif (or .png/.jpg/.webp) as the "wallpaper", or an animated
// visualizer when there's no file, with the music player UI drawn on top.

uniform sampler2D media_tex : source_color, filter_linear, repeat_disable;
uniform bool use_media = false;
uniform float media_aspect = 1.7778;
uniform float screen_aspect = 1.8;
uniform sampler2D ui_tex : filter_linear, repeat_disable;
uniform bool use_ui = false;
uniform float ui_gamma = 2.2;

vec2 cover_uv(vec2 uv) {
	float k = media_aspect / screen_aspect;
	vec2 r = uv - 0.5;
	if (k > 1.0) {
		r.x /= k;
	} else {
		r.y *= k;
	}
	return r + 0.5;
}

void fragment() {
	vec2 uv = UV;
	vec3 col;
	if (use_media) {
		col = texture(media_tex, cover_uv(uv)).rgb * 1.15;
	} else {
		float t = TIME * 0.3;
		vec3 a = vec3(0.35, 0.20, 0.90);
		vec3 b = vec3(1.0, 0.35, 0.75);
		float w = 0.5 + 0.5 * sin(uv.x * 6.0 + t * 2.0 + sin(uv.y * 4.0 + t));
		col = mix(a, b, w * uv.y + (1.0 - uv.y) * 0.2);

		float id = floor(uv.x * 24.0);
		float f = fract(uv.x * 24.0);
		float bar_h = 0.12 + 0.28 * (0.5 + 0.5 * sin(TIME * 1.5 + id * 1.7));
		float inbar = step(1.0 - uv.y, bar_h) * step(0.15, f) * step(f, 0.85);
		col = mix(col, vec3(1.0, 0.85, 0.95), inbar * 0.8);
		col *= 1.4;
	}
	if (use_ui) {
		// the UI viewport has premultiplied alpha; its colours are sRGB so convert to linear
		vec4 ui = texture(ui_tex, uv);
		col = pow(ui.rgb, vec3(ui_gamma)) + col * (1.0 - ui.a);
	}
	ALBEDO = col;
}

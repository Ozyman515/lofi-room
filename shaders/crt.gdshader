shader_type spatial;
render_mode unshaded, fog_disabled;

// Old CRT. Picture priority: VCR video > media/tv.gif (or .png/.jpg/.webp) > blue "CH 3" screen.
// The VCR menu / on-screen display is drawn on top, then curved glass, scanlines and flicker.

uniform sampler2D media_tex : source_color, filter_linear, repeat_disable;
uniform bool use_media = false;
uniform float media_aspect = 1.3333;
uniform float screen_aspect = 1.3333;
uniform sampler2D video_tex : source_color, filter_linear, repeat_disable;
uniform bool use_video = false;
uniform float video_aspect = 1.7778;
uniform int video_mode = 0;        // 0 original shape, 1 zoom/crop to fill, 2 stretch, 3 forced 16:9
uniform sampler2D ui_tex : filter_linear, repeat_disable;
uniform bool use_ui = false;
uniform float ui_gamma = 2.2;
uniform bool use_console = false;  // the game console is switched on: it takes over the whole screen
uniform bool console_file = false; // true when media/console.gif (.png...) exists, otherwise a built-in 8-bit scene plays
uniform sampler2D console_tex : source_color, filter_nearest, repeat_disable;
uniform float console_aspect = 1.3333;
uniform bool console_contain = false;   // keep the picture's own shape, black bars around it (handheld games)
uniform int crt_mode = 1;          // 0 = clean picture (flat, no scanlines), 1 = old TV, 2 = stronger CRT
uniform float tv_power = 1.0;      // 1 = on, 0 = off; in between plays the old CRT switch-off squash

const int GC[7] = int[7](14, 17, 16, 16, 16, 17, 14);   // C
const int GH[7] = int[7](17, 17, 17, 31, 17, 17, 17);   // H
const int G3[7] = int[7](30, 1, 1, 14, 1, 1, 30);       // 3

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float glyph_pixel(int ci, int cx, int cy) {
	if (cx < 0 || cx > 4 || cy < 0 || cy > 6) {
		return 0.0;
	}
	int row = 0;
	if (ci == 0) {
		row = GC[cy];
	} else if (ci == 1) {
		row = GH[cy];
	} else if (ci == 3) {
		row = G3[cy];
	} else {
		return 0.0;
	}
	return float((row >> (4 - cx)) & 1);
}

bool in_rect(vec2 g, float x0, float y0, float x1, float y1) {
	return g.x >= x0 && g.x < x1 && g.y >= y0 && g.y < y1;
}

// The secret cart: a little run-and-gun in the spirit of the old jungle shooters, drawn on a 160x120 pixel grid.
// A commando runs through the jungle at night, jumps the water, shoots soldiers, a weapon pod flies past.
// g.y counts up from the bottom.
float player_y(float tt) {
	float m = mod(40.0 + tt * 40.0, 130.0);
	if (m > 84.0 && m < 126.0) {
		return 24.0 + floor(20.0 * sin(3.14159 * (m - 84.0) / 42.0));
	}
	return 24.0;
}

bool in_gap(float wx) {
	float m = mod(wx, 130.0);
	return m > 100.0 && m < 122.0;
}

vec3 console_scene(vec2 uv, float t) {
	vec2 g = floor(vec2(uv.x * 160.0, (1.0 - uv.y) * 120.0));
	float x = g.x;
	float y = g.y;
	float scroll = t * 40.0;
	float wx = x + scroll;
	// night sky
	vec3 col = mix(vec3(0.02, 0.03, 0.12), vec3(0.14, 0.34, 0.46), clamp(1.0 - (y - 20.0) / 100.0, 0.0, 1.0));
	col = floor(col * 8.0 + 0.5) / 8.0;
	if (y > 62.0 && hash(g + 3.0) > 0.985) {
		col = vec3(0.9, 0.95, 1.0) * (0.6 + 0.4 * step(0.5, fract(t * 1.3 + hash(g))));
	}
	vec2 mc = g - vec2(128.0, 98.0);
	if (dot(mc, mc) < 49.0) {
		col = vec3(0.96, 0.94, 0.72);
		if (dot(g - vec2(125.0, 100.0), g - vec2(125.0, 100.0)) < 5.0) {
			col = vec3(0.80, 0.78, 0.55);
		}
	}
	// far mountains
	float mh = 38.0 + floor(13.0 * sin((x + t * 3.0) * 0.04) + 7.0 * sin((x + t * 3.0) * 0.11 + 1.0));
	if (y < mh) {
		col = vec3(0.07, 0.17, 0.26);
		if (y > mh - 2.0) {
			col = vec3(0.12, 0.26, 0.36);
		}
	}
	// palm trees drifting by
	float wx2 = x + t * 16.0;
	float cell = floor(wx2 / 52.0);
	float dx = mod(wx2, 52.0) - 26.0;
	float th = 50.0 + floor(14.0 * hash(vec2(cell, 7.0)));
	if (y >= 24.0 && y < th && abs(dx) < 2.0) {
		col = vec3(0.30, 0.18, 0.10);
		if (mod(y, 4.0) < 1.0) {
			col = vec3(0.20, 0.11, 0.07);
		}
	}
	float arch = th - 0.42 * abs(dx);
	if (abs(dx) < 15.0 && y >= arch && y < arch + 3.0) {
		col = mod(y + abs(dx), 2.0) < 1.0 ? vec3(0.06, 0.34, 0.16) : vec3(0.12, 0.50, 0.24);
	}
	float arch2 = th + 5.0 - 0.9 * abs(dx);
	if (abs(dx) < 7.0 && y >= arch2 && y < arch2 + 2.0) {
		col = vec3(0.10, 0.44, 0.20);
	}
	// a ledge in the air
	float lm = mod(wx, 210.0);
	if (lm > 150.0 && lm < 198.0) {
		if (y >= 58.0 && y < 62.0) {
			col = y >= 60.0 ? vec3(0.45, 0.90, 0.30) : vec3(0.30, 0.65, 0.20);
		} else if (y >= 54.0 && y < 58.0) {
			col = vec3(0.40, 0.24, 0.10);
			if (mod(floor(wx / 6.0) + floor(y / 4.0), 3.0) < 1.0) {
				col = vec3(0.28, 0.15, 0.07);
			}
		}
	}
	// ground, with water gaps
	if (y < 24.0) {
		if (in_gap(wx)) {
			col = vec3(0.08, 0.26, 0.62);
			if (mod(floor(x * 0.5 + t * 6.0) + floor(y / 3.0) * 3.0, 7.0) < 1.0) {
				col = vec3(0.30, 0.55, 0.90);
			}
		} else {
			col = vec3(0.45, 0.28, 0.12);
			if (mod(floor(wx / 8.0) + floor(y / 6.0) * 2.0, 5.0) < 1.0) {
				col = vec3(0.30, 0.17, 0.08);
			}
			if (y >= 21.0) {
				col = y >= 23.0 ? vec3(0.45, 0.92, 0.32) : vec3(0.30, 0.70, 0.22);
			}
		}
	}
	// bullets
	for (int i = 0; i < 4; i++) {
		float age = mod(t + float(i) * 0.25, 1.0);
		float by = player_y(t - age) + 9.0;
		float bx = 54.0 + age * 120.0;
		if (in_rect(g, bx, by, bx + 3.0, by + 2.0)) {
			col = vec3(1.0, 0.95, 0.5);
		}
	}
	// two soldiers run in and get shot
	for (int i = 0; i < 2; i++) {
		float u = mod(t + float(i) * 2.1, 4.2);
		float ex = 168.0 - 40.0 * u;
		if (u < 1.5) {
			bool sa = mod(floor(t * 8.0), 2.0) > 0.5;
			if (in_rect(g, ex + 1.0, 24.0 + (sa ? 2.0 : 0.0), ex + 3.0, 31.0) || in_rect(g, ex + 4.0, 24.0 + (sa ? 0.0 : 2.0), ex + 6.0, 31.0)) { col = vec3(0.50, 0.52, 0.58); }
			if (in_rect(g, ex, 31.0, ex + 7.0, 37.0)) { col = vec3(0.62, 0.64, 0.70); }
			if (in_rect(g, ex + 1.0, 37.0, ex + 6.0, 41.0)) { col = vec3(0.95, 0.76, 0.60); }
			if (in_rect(g, ex, 40.0, ex + 7.0, 43.0)) { col = vec3(0.40, 0.42, 0.50); }
			if (in_rect(g, ex - 4.0, 33.0, ex + 1.0, 35.0)) { col = vec3(0.15, 0.15, 0.18); }
		} else if (u < 1.72) {
			float k = (u - 1.5) / 0.22;
			float r = 3.0 + 8.0 * k;
			vec2 d = g - vec2(108.0, 34.0);
			if (abs(d.x) < r && abs(d.y) < r) {
				col = abs(d.x) + abs(d.y) < r ? vec3(1.0, 0.93, 0.55) : vec3(1.0, 0.45, 0.10);
			}
		}
	}
	// the flying weapon pod
	float px2 = 160.0 - mod(t * 26.0 + 40.0, 210.0);
	float py2 = 90.0 + floor(6.0 * sin(t * 3.0));
	if (in_rect(g, px2, py2, px2 + 9.0, py2 + 5.0) && !(g.x == px2 || g.x == px2 + 8.0) ) {
		col = vec3(0.85, 0.15, 0.20);
		if (in_rect(g, px2 + 3.0, py2 + 1.0, px2 + 6.0, py2 + 4.0)) {
			col = vec3(0.95, 0.95, 0.98);
		}
	}
	// the commando
	float hx = 40.0;
	float hy = player_y(t);
	bool air = hy > 24.5;
	if (air) {
		// somersault
		vec2 d = g - vec2(hx + 4.0, hy + 8.0);
		if (abs(d.x) < 4.0 && abs(d.y) < 4.0) {
			float f = mod(floor(t * 14.0), 4.0);
			bool a1 = f < 2.0 ? d.x * d.y > 0.0 : d.x * d.y < 0.0;
			col = a1 ? vec3(0.92, 0.92, 0.96) : vec3(0.15, 0.32, 0.80);
			if (abs(d.x) < 1.0 && abs(d.y) < 1.0) {
				col = vec3(1.0, 0.78, 0.60);
			}
		}
	} else {
		bool step_a = mod(floor(t * 9.0), 2.0) > 0.5;
		if (step_a) {
			if (in_rect(g, hx + 1.0, hy, hx + 4.0, hy + 7.0) || in_rect(g, hx + 5.0, hy + 2.0, hx + 8.0, hy + 7.0)) { col = vec3(0.12, 0.30, 0.78); }
		} else {
			if (in_rect(g, hx, hy + 2.0, hx + 3.0, hy + 7.0) || in_rect(g, hx + 4.0, hy, hx + 7.0, hy + 7.0)) { col = vec3(0.12, 0.30, 0.78); }
		}
		if (in_rect(g, hx + (step_a ? 1.0 : 4.0), hy, hx + (step_a ? 4.0 : 7.0), hy + 1.0)) { col = vec3(0.95, 0.95, 0.98); }   // shoes
		if (in_rect(g, hx + 1.0, hy + 7.0, hx + 7.0, hy + 12.0)) { col = vec3(1.0, 0.76, 0.58); }                                 // bare chest
		if (in_rect(g, hx + 2.0, hy + 12.0, hx + 7.0, hy + 16.0)) { col = vec3(1.0, 0.76, 0.58); }                                // head
		if (in_rect(g, hx + 2.0, hy + 14.0, hx + 8.0, hy + 15.0)) { col = vec3(0.90, 0.10, 0.15); }                               // red headband
		if (in_rect(g, hx + 5.0, hy + 8.0, hx + 14.0, hy + 10.0)) { col = vec3(0.16, 0.16, 0.20); }                               // rifle
	}
	// lives: three medals
	for (int i = 0; i < 3; i++) {
		float mx = 6.0 + float(i) * 8.0;
		if (in_rect(g, mx + 1.0, 111.0, mx + 4.0, 115.0)) { col = i == 2 ? vec3(0.8, 0.1, 0.15) : vec3(0.2, 0.4, 0.95); }
		if (in_rect(g, mx, 107.0, mx + 5.0, 111.0)) { col = vec3(1.0, 0.84, 0.25); }
	}
	return pow(col, vec3(2.2));
}

// fill the screen, cropping the extra
vec2 cover_uv(vec2 uv, float aspect) {
	float k = aspect / screen_aspect;
	vec2 r = uv - 0.5;
	if (k > 1.0) {
		r.x /= k;
	} else {
		r.y *= k;
	}
	return r + 0.5;
}

// fit inside the screen with black bars
vec2 contain_uv(vec2 uv, float aspect) {
	float k = aspect / screen_aspect;
	vec2 r = uv - 0.5;
	if (k > 1.0) {
		r.y *= k;
	} else {
		r.x /= k;
	}
	return r + 0.5;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	vec2 raw = c;
	float bulge = crt_mode == 0 ? 0.0 : (crt_mode == 2 ? 0.14 : 0.08);
	c *= 1.0 + bulge * dot(c, c);                // curved glass
	vec2 u = c * 0.5 + 0.5;
	float inside = step(0.0, u.x) * step(u.x, 1.0) * step(0.0, u.y) * step(u.y, 1.0);
	vec2 uc = clamp(u, 0.0, 1.0);
	float t = TIME;
	vec3 col;
	float noise_amt = 0.05;

	if (use_console) {
		if (console_file) {
			if (console_contain) {
				vec2 cu = contain_uv(uc, console_aspect);
				float ins = step(0.0, cu.x) * step(cu.x, 1.0) * step(0.0, cu.y) * step(cu.y, 1.0);
				col = texture(console_tex, clamp(cu, 0.0, 1.0)).rgb * ins;
			} else {
				col = texture(console_tex, cover_uv(uc, console_aspect)).rgb;
			}
		} else {
			col = console_scene(uc, t);
		}
		noise_amt = 0.03;
	} else if (use_video) {
		vec2 vuv;
		if (video_mode == 1) {
			vuv = cover_uv(uc, video_aspect);          // crop the extra so the picture fills the screen
		} else if (video_mode == 2) {
			vuv = uc;                                  // squeeze/stretch to the whole screen
		} else if (video_mode == 3) {
			vuv = contain_uv(uc, 1.7778);              // pretend the picture is 16:9
		} else {
			vuv = contain_uv(uc, video_aspect);
		}
		float vin = step(0.0, vuv.x) * step(vuv.x, 1.0) * step(0.0, vuv.y) * step(vuv.y, 1.0);
		col = texture(video_tex, clamp(vuv, 0.0, 1.0)).rgb * vin;
		noise_amt = 0.025;
	} else if (use_media) {
		col = texture(media_tex, cover_uv(uc, media_aspect)).rgb;
		noise_amt = 0.03;
	} else {
		col = vec3(0.02, 0.10, 0.82);            // blue screen
		col += 0.06 * smoothstep(1.0, 0.0, length(c));
		// on-screen "CH 3", top right, 5x7 pixel font
		vec2 q = (u - vec2(0.66, 0.07)) / vec2(0.012, 0.0165);
		if (q.x >= 0.0 && q.x < 24.0 && q.y >= 0.0 && q.y < 7.0) {
			int ci = int(floor(q.x / 6.0));
			int cx = int(floor(q.x - float(ci) * 6.0));
			int cy = int(floor(q.y));
			col = mix(col, vec3(0.80, 1.0, 0.85), glyph_pixel(ci, cx, cy));
		}
	}

	if (use_ui && !use_console) {
		// the UI viewport has premultiplied alpha; its colours are sRGB so convert to linear
		vec4 ui = texture(ui_tex, uc);
		col = pow(ui.rgb, vec3(ui_gamma)) + col * (1.0 - ui.a);
	}

	// scanlines, slow rolling bar, flicker, noise, vignette (all gone in the clean mode)
	if (crt_mode == 1) {
		col *= 0.90 + 0.10 * sin(u.y * 300.0);
		col += 0.04 * smoothstep(0.08, 0.0, abs(fract(u.y - t * 0.10) - 0.5) - 0.42);
		col *= 0.97 + 0.03 * sin(t * 40.0);
		col += (hash(u * 500.0 + t) - 0.5) * noise_amt;
		col *= 1.0 - 0.40 * dot(c, c) * 0.5;
	} else if (crt_mode == 2) {
		col *= 0.78 + 0.22 * sin(u.y * 480.0);
		float tri = mod(floor(u.x * 960.0), 3.0);                     // faint red / green / blue stripes
		col *= vec3(tri < 1.0 ? 1.0 : 0.86, (tri >= 1.0 && tri < 2.0) ? 1.0 : 0.86, tri >= 2.0 ? 1.0 : 0.86) * 1.08;
		col += 0.06 * smoothstep(0.10, 0.0, abs(fract(u.y - t * 0.10) - 0.5) - 0.40);
		col *= 0.95 + 0.05 * sin(t * 40.0);
		col += (hash(u * 500.0 + t) - 0.5) * noise_amt * 1.6;
		col *= 1.0 - 0.75 * dot(c, c) * 0.5;
	}

	// switch-off / switch-on: picture squashes to a bright line, then a dot
	float hh = clamp((tv_power - 0.35) / 0.65, 0.0, 1.0);
	float ww = clamp(tv_power / 0.35, 0.0, 1.0);
	float mask = step(abs(raw.y), max(hh, 0.012)) * step(abs(raw.x), ww);
	col = mix(vec3(1.2), col, hh);
	ALBEDO = col * 1.3 * inside * mask;
	if (tv_power < 0.001) {
		ALBEDO = vec3(0.012, 0.014, 0.018);     // dead glass
	}
}

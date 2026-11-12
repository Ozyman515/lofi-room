shader_type spatial;
// The room's NEW look (room_look.gd): a textured model (Quaternius Downtown City kit, CC0) recoloured to the room's
// palette. The texture's brightness picks a colour along dark -> mid -> light; its normal map keeps the brick and stone detail.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_nrm = false;
uniform vec3 dark : source_color = vec3(0.07, 0.04, 0.14);
uniform vec3 mid : source_color = vec3(0.30, 0.15, 0.45);
uniform vec3 light : source_color = vec3(0.82, 0.52, 0.78);
uniform float contrast = 1.2;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float rough = 0.85;
uniform vec3 emit_col : source_color = vec3(0.0);
uniform float emit_k = 0.0;
uniform float self_lit = 0.3;            // (the room's own city glows softly; so do these)

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec3 c = texture(tex, uv).rgb;
	float l = clamp((dot(c, vec3(0.299, 0.587, 0.114)) - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 g = l < 0.5 ? mix(dark, mid, l * 2.0) : mix(mid, light, (l - 0.5) * 2.0);
	ALBEDO = g;
	ROUGHNESS = rough;
	if (use_nrm) {
		NORMAL_MAP = texture(nrm, uv).rgb;
	}
	EMISSION = emit_col * emit_k * (0.25 + l) + g * self_lit;
}

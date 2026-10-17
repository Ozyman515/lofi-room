shader_type spatial;
render_mode cull_disabled, fog_disabled;

// Heavy blackout curtain: dark navy cloth with soft vertical folds.
uniform vec3 cloth : source_color = vec3(0.05, 0.04, 0.11);
uniform float folds = 30.0;

void fragment() {
	float f = 0.5 + 0.5 * sin(UV.x * folds * 6.2831853);
	ALBEDO = cloth * (0.55 + 0.9 * f);
	ROUGHNESS = 1.0;
	// the edge towards the bottom is a little brighter (hem)
	float hem = smoothstep(0.985, 1.0, UV.y);
	ALBEDO += vec3(0.05, 0.04, 0.09) * hem;
}

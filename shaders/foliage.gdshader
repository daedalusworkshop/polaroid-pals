// Leaf cards, grass tufts and flowers: alpha-cut pixel textures, sphere normals for
// soft volumetric bushes, wind sway (vertex alpha = sway weight), wrap lighting.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, world_vertex_coords;

uniform sampler2D leaf_tex : source_color, filter_nearest;
uniform float instanced = 0.0;        // 1 = MultiMesh with per-instance tint in custom data
uniform float wind = 1.0;
uniform float wrap = 0.45;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float depth_mode = 0.0;
uniform float band_soft = 0.03;
uniform float up_normals = 0.0;       // 1 = force normals up (grass matches terrain)

varying vec3 w_nrm;
varying vec3 tint;
varying vec3 w_pos;

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

void vertex() {
	float t = TIME;
	vec3 wp = VERTEX;
	float sway = (sin(t * 1.4 + wp.x * 0.31 + wp.z * 0.23) + 0.5 * sin(t * 2.9 + wp.z * 0.7 + wp.x * 0.2)) * 0.07 * wind * COLOR.a;
	VERTEX += vec3(sway, 0.0, sway * 0.6);
	w_nrm = up_normals > 0.5 ? vec3(0.0, 1.0, 0.0) : normalize(NORMAL);
	tint = instanced > 0.5 ? COLOR.rgb : vec3(1.0);
	w_pos = wp;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	if (t.a < 0.5) discard;
	vec3 col = (instanced > 0.5 ? to_lin(tint) : to_lin(COLOR.rgb)) * t.rgb;
	if (snow > 0.0) {
		float s = step(1.0 - snow * 0.7, w_nrm.y + t.r * 0.15);
		col = mix(col, vec3(0.86, 0.9, 0.98), s);
	}
	col *= 1.0 - wet * 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(w_nrm, 0.0)).xyz);
	if (depth_mode > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = to_lin(vec3(clamp(sqrt(length(VERTEX) / 250.0), 0.0, 1.0)));
	} else {
		ALBEDO = col;
	}
	ROUGHNESS = 1.0;
}

void light() {
	if (depth_mode < 0.5) {
		float a = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
		float q = smoothstep(0.08, 0.08 + band_soft, a) * 0.6 + smoothstep(0.5, 0.5 + band_soft, a) * 0.4;
		DIFFUSE_LIGHT += q * LIGHT_COLOR / PI;
	}
}

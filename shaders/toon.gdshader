// Cozy toon shading: two hard light bands over a tinted ambient (so shadows read
// blue-violet instead of black), painterly ground noise, moss and snow caps.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float terrain = 0.0;          // 1 = add world-space painterly patches
uniform float moss = 0.0;             // global moss amount (vertex alpha = mossiness)
uniform vec3 moss_color : source_color = vec3(0.36, 0.56, 0.27);
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float depth_mode = 0.0;       // photo depth pass
uniform float band_soft = 0.02;

varying vec3 w_pos;
varying vec3 w_nrm;

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = to_lin(COLOR.rgb);
	if (terrain > 0.5) {
		vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * w_pos.xz;
		float n = vnoise(q * 0.21) * 0.6 + vnoise(q * 0.73 + 7.0) * 0.4;
		col *= 0.93 + step(0.58, n) * 0.08 - step(n, 0.36) * 0.06;
	}
	float up = w_nrm.y;
	float h = hash(floor(w_pos.xz * 2.5) + floor(w_pos.y * 2.5) * 13.0);
	if (moss > 0.0 && COLOR.a > 0.0) {
		float m = step(1.0 - moss * COLOR.a * 0.6 + h * 0.25, up);
		col = mix(col, to_lin(moss_color) * (0.85 + h * 0.3), m);
	}
	if (snow > 0.0) {
		float s = step(1.0 - snow * 0.85 + h * 0.18, up);
		col = mix(col, vec3(0.86, 0.9, 0.98), s);
	}
	// laid-stone courses on vertical faces of mossy (ruin) stonework
	if (moss > 0.0 && COLOR.a > 0.95 && abs(up) < 0.4) {
		float row = floor(w_pos.y * 1.7);
		float along = (abs(w_nrm.x) > abs(w_nrm.z) ? w_pos.z : w_pos.x) * 0.9 + row * 0.5;
		float joint = max(step(fract(w_pos.y * 1.7), 0.07), step(fract(along), 0.05));
		col *= 1.0 - joint * 0.16;
		col *= 0.95 + hash(vec2(row, floor(along))) * 0.1;
	}
	// soft sky occlusion: downward and sideways faces read darker, so forms hold up in shade
	col *= mix(0.7, 1.0, clamp(up * 0.5 + 0.55, 0.0, 1.0));
	col *= 1.0 - wet * 0.28;
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
		float a = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
		float q = smoothstep(0.03, 0.03 + band_soft, a) * 0.62 + smoothstep(0.42, 0.42 + band_soft, a) * 0.38;
		DIFFUSE_LIGHT += q * LIGHT_COLOR / PI;
	}
}

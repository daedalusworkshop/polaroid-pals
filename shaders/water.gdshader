// Stylised water: sky-tinted fresnel, pixel sparkle lines, scrolling for falls.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 deep : source_color = vec3(0.16, 0.36, 0.45);
uniform vec3 shallow : source_color = vec3(0.35, 0.62, 0.62);
uniform vec3 sky : source_color = vec3(0.7, 0.85, 0.95);
uniform vec3 sparkle : source_color = vec3(1.0, 0.98, 0.9);
uniform float flow = 0.0;             // >0 = waterfall (scroll along UV.y)
uniform float light = 1.0;
uniform float depth_mode = 0.0;

varying vec3 w_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (depth_mode > 0.5) {
		ALBEDO = vec3(pow(clamp(sqrt(length(VERTEX) / 250.0), 0.0, 1.0), 2.2));
	} else if (flow > 0.0) {
		vec2 cell = floor(vec2(UV.x * 10.0, UV.y * 40.0 - TIME * flow * 6.0));
		float s = hash(vec2(cell.x, cell.y));
		vec3 c = mix(shallow, vec3(0.92, 0.96, 1.0), step(0.45, s) * 0.7 + 0.2);
		ALBEDO = c * light;
	} else {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 c = mix(deep, shallow, 0.35);
		c = mix(c, sky, clamp(fres * 1.2, 0.0, 0.85));
		vec2 p = floor(w_pos.xz * 2.0);
		float wave = sin(w_pos.x * 0.8 + TIME * 1.3 + sin(w_pos.z * 0.6 + TIME) * 1.5);
		float s = step(0.965, hash(p + floor(TIME * 1.5))) * step(0.3, wave);
		c = mix(c, sparkle, s * 0.8);
		ALBEDO = c * light;
	}
}

// Self-lit surfaces: windows, lanterns, vending machines, signs.
// Vertex alpha = brightness during the day; everything blooms up at night.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float night = 0.0;
uniform float depth_mode = 0.0;
uniform sampler2D glyph_tex : source_color, filter_nearest;
uniform float use_tex = 0.0;
uniform vec3 glyph_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float flicker = 0.0;

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

void fragment() {
	vec3 c = to_lin(COLOR.rgb);
	if (use_tex > 0.5) {
		float g = texture(glyph_tex, UV).a;
		c = mix(c, to_lin(glyph_color), g);
	}
	float level = mix(COLOR.a, 1.25, night);
	if (flicker > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float id = fract(sin(dot(floor(wp.xz * 0.5), vec2(12.9, 78.2))) * 43758.5);
		float f = step(0.93, id) * step(0.6, fract(sin(floor(TIME * 9.0) + id * 50.0) * 43758.5));
		level *= 1.0 - f * 0.7 * night;
	}
	ALBEDO = depth_mode > 0.5 ? to_lin(vec3(clamp(sqrt(length(VERTEX) / 250.0), 0.0, 1.0))) : c * level;
}

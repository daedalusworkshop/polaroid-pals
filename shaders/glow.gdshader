// Self-lit surfaces: windows, lanterns, vending machines, signs.
// Vertex alpha = brightness during the day; everything blooms up at night.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float night = 0.0;
uniform float depth_mode = 0.0;
uniform sampler2D glyph_tex : source_color, filter_nearest;
uniform float use_tex = 0.0;
uniform vec3 glyph_color : source_color = vec3(1.0, 0.96, 0.86);

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

void fragment() {
	vec3 c = to_lin(COLOR.rgb);
	if (use_tex > 0.5) {
		float g = texture(glyph_tex, UV).a;
		c = mix(c, to_lin(glyph_color), g);
	}
	float level = mix(COLOR.a, 1.25, night);
	ALBEDO = depth_mode > 0.5 ? to_lin(vec3(clamp(sqrt(length(VERTEX) / 250.0), 0.0, 1.0))) : c * level;
}

// Painted light shafts: axis-aligned billboards along the sun direction.
// Node scale.x = width, scale.y = length. Mesh is a quad spanning x -0.5..0.5, y 0..-1.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 ray_dir = vec3(0.3, -1.0, 0.2);   // travel direction of light
uniform vec3 color : source_color = vec3(1.0, 0.95, 0.75);
uniform float strength = 0.25;
uniform float depth_mode = 0.0;

varying float fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float l = length(MODEL_MATRIX[1].xyz);
	vec3 axis = normalize(ray_dir);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(axis, normalize(cam - origin)));
	vec3 world = origin + side * VERTEX.x * w + axis * (-VERTEX.y) * l;
	float cd = length(cam - world);
	fade = smoothstep(2.0, 9.0, cd) * (1.0 - smoothstep(90.0, 140.0, cd));
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float a = pow(edge, 1.6) * sin(UV.y * 3.14159) * strength * fade;
	a *= 0.8 + 0.2 * sin(TIME * 0.5 + UV.y * 3.0);
	ALBEDO = depth_mode > 0.5 ? vec3(0.0) : color * a;
}

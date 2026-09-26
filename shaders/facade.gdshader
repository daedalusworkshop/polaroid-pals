// Building facades: pixel-art bays from the facade atlas are painted over the
// wall colour (vertex colour). Glass pixels open onto a tiny parallax room
// ("interior mapping"); rooms switch their lights on one by one after dusk,
// a few flicker blue with TV light. Shoji paper glows when its room is lit.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 sky_col : source_color = vec3(0.7, 0.8, 0.9);
uniform float night = 0.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float depth_mode = 0.0;
uniform float band_soft = 0.02;
uniform vec3 room_size = vec3(2.4, 2.8, 3.0);   // bay width, height, room depth (m)

varying vec3 w_pos;
varying vec3 w_nrm;

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Colour seen through the window at this pixel; returns rgb, alpha = how lit.
vec4 room(vec2 luv, vec3 n, vec3 cam, float seed) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 tn = normalize(cross(up, n));
	vec3 v = normalize(w_pos - cam);
	vec3 dir = vec3(dot(v, tn) / room_size.x, dot(v, up) / room_size.y, dot(v, -n) / room_size.z);
	vec3 pos = vec3(luv.x, 1.0 - luv.y, 0.0);
	dir.z = max(dir.z, 0.001);
	vec3 bound = step(vec3(0.0), dir);
	vec3 tt = (bound - pos) / dir;
	float t = min(min(tt.x, tt.y), tt.z);
	vec3 hit = pos + dir * t;
	float kind = hash(vec2(seed, 3.1));
	vec3 paper = mix(vec3(0.93, 0.86, 0.72), mix(vec3(0.72, 0.82, 0.78), vec3(0.9, 0.78, 0.8), kind), step(0.5, hash(vec2(seed, 7.7))));
	vec3 c;
	if (t == tt.z) {
		c = paper;
		// back wall: a shelf, a picture frame or a doorway
		float f = hash(vec2(seed, 1.3));
		if (f < 0.35 && hit.y < 0.55 && hit.y > 0.1 && abs(hit.x - 0.3) < 0.18) c = vec3(0.45, 0.32, 0.22);
		else if (f < 0.7 && hit.y > 0.5 && hit.y < 0.75 && abs(hit.x - 0.6) < 0.12) c = vec3(0.35, 0.5, 0.62);
		else if (hit.y < 0.8 && abs(hit.x - 0.75) < 0.1) c = paper * 0.55;
	} else if (t == tt.y) {
		c = dir.y < 0.0 ? vec3(0.55, 0.4, 0.28) : vec3(0.95, 0.92, 0.85);
		// a ceiling lamp
		if (dir.y > 0.0 && length(hit.xz - vec2(0.5, 0.5)) < 0.12) c = vec3(1.4, 1.25, 0.95);
	} else {
		c = paper * 0.78;
	}
	c *= 1.0 - hit.z * 0.35;
	float lit = step(hash(vec2(seed, 5.5)) * 0.9 + 0.05, night);
	return vec4(c, lit);
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	vec3 wall = to_lin(COLOR.rgb);
	vec3 col = wall;
	vec3 emit = vec3(0.0);
	float up = w_nrm.y;
	vec2 luv = fract(UV * 8.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	// one random seed per actual window on the wall
	vec3 tn = normalize(cross(vec3(0.0, 1.0, 0.0), w_nrm));
	vec3 origin = w_pos - tn * luv.x * room_size.x + vec3(0.0, luv.y * room_size.y, 0.0);
	float seed = hash(floor(origin.xz * 0.45) + floor(origin.y * 0.4) * 17.0 + floor(UV * 8.0) * 0.13);
	if (tex.a > 0.95) {
		col = tex.rgb;
	} else if (tex.a > 0.7) {
		vec4 r = room(luv, normalize(w_nrm), cam, seed);
		float tv = step(0.88, hash(vec2(seed, 9.1))) * r.a;
		vec3 lamp = mix(vec3(1.0, 0.78, 0.5), vec3(0.55, 0.7, 1.1) * (0.7 + 0.3 * sin(TIME * 13.0 + seed * 40.0) * sin(TIME * 3.1)), tv);
		vec3 lit_room = r.rgb * lamp * 1.25;
		vec3 day_room = r.rgb * 0.22;
		float fres = pow(1.0 - clamp(abs(dot(normalize(cam - w_pos), w_nrm)), 0.0, 1.0), 2.0);
		vec3 refl = sky_col * (0.25 + fres * 0.5) * (1.0 - night * 0.8);
		col = vec3(0.01);
		emit = mix(day_room, lit_room, r.a) + refl * (1.0 - r.a * 0.7);
	} else if (tex.a > 0.55) {
		col = tex.rgb;
		float lit = step(hash(vec2(seed, 5.5)) * 0.9 + 0.05, night);
		emit = tex.rgb * vec3(1.0, 0.72, 0.42) * lit * 0.9;
	} else if (tex.a > 0.01) {
		col = mix(wall, tex.rgb, tex.a);
	}
	if (snow > 0.0) {
		float h = hash(floor(w_pos.xz * 2.5) + floor(w_pos.y * 2.5) * 13.0);
		col = mix(col, vec3(0.86, 0.9, 0.98), step(1.0 - snow * 0.85 + h * 0.18, up));
	}
	col *= mix(0.72, 1.0, clamp(up * 0.5 + 0.55, 0.0, 1.0));
	col *= 1.0 - wet * 0.25;
	if (depth_mode > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = to_lin(vec3(clamp(sqrt(length(VERTEX) / 250.0), 0.0, 1.0)));
	} else {
		ALBEDO = col;
		EMISSION = emit;
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

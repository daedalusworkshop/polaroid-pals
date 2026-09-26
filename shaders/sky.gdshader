// Pixel sky: banded gradient, crisp sun/moon disc, blocky drifting clouds, stars.
shader_type sky;

uniform vec3 top : source_color = vec3(0.3, 0.55, 0.9);
uniform vec3 horizon : source_color = vec3(0.8, 0.9, 0.95);
uniform vec3 ground : source_color = vec3(0.35, 0.45, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.75, 0.85);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);   // towards the sun
uniform float sun_size = 0.035;
uniform float cloud_cover = 0.45;
uniform float cloud_time = 0.0;
uniform float stars = 0.0;
uniform float depth_mode = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += vnoise(p) * a; p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	if (depth_mode > 0.5) {
		COLOR = vec3(1.0);
	} else {
		vec3 d = EYEDIR;
		float h = d.y;
		float band = floor(clamp(h, 0.0, 1.0) * 14.0) / 14.0;
		vec3 c = mix(horizon, top, smoothstep(0.0, 0.75, band));
		c = mix(c, ground, smoothstep(0.0, -0.12, h));
		// sun / moon glow + disc
		vec3 sd = normalize(sun_dir);
		float cosang = dot(d, sd);
		float glow = smoothstep(0.75, 1.0, cosang);
		c = mix(c, sun_color, floor(glow * glow * 4.0) / 4.0 * 0.45);
		c = mix(c, sun_color * 1.3, step(1.0 - sun_size * sun_size, cosang));
		// stars
		if (stars > 0.0 && h > 0.0) {
			vec2 sp = floor(d.xz / (h + 0.3) * 90.0);
			float s = step(0.992, hash(sp)) * stars * smoothstep(0.0, 0.2, h);
			c = mix(c, vec3(1.0, 0.97, 0.9), s);
		}
		// clouds on a flat layer
		if (h > 0.01) {
			vec2 uv = d.xz / (h + 0.12) * 0.55 + vec2(cloud_time * 0.01, cloud_time * 0.004);
			float n = fbm(uv);
			float thr = 0.64 - cloud_cover * 0.22;
			float cm = step(thr, n);
			float lit = step(thr + 0.03, fbm(uv + sd.xz * 0.05));
			vec3 cc = mix(cloud_shade, cloud_lit, lit);
			c = mix(c, cc, cm * smoothstep(0.01, 0.12, h));
		}
		COLOR = c;
	}
}

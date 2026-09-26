// Final look for the low-res frame: exposure, film grade, vignette and a gentle
// ordered dither that keeps colours in chunky pixel-art steps. In the darkroom
// (photo development) it also applies real depth of field from the depth pass.
shader_type canvas_item;

uniform sampler2D depth_tex : filter_nearest;
uniform float use_dof = 0.0;
uniform float focus = 0.3;            // encoded depth of the focus plane
uniform float blur = 0.0;             // max circle-of-confusion radius in pixels
uniform float dof_scale = 6.0;

uniform float exposure = 0.0;         // EV
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform vec3 lift = vec3(0.0);
uniform vec3 gain = vec3(1.0);
uniform float mono = 0.0;
uniform float vignette = 0.22;
uniform float grain = 0.0;
uniform float levels = 40.0;
uniform float dither = 0.7;
uniform float seed = 0.0;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
const vec2 DISK[12] = vec2[](
	vec2(1.0, 0.0), vec2(0.5, 0.866), vec2(-0.5, 0.866), vec2(-1.0, 0.0), vec2(-0.5, -0.866), vec2(0.5, -0.866),
	vec2(0.5, 0.0), vec2(0.25, 0.433), vec2(-0.25, 0.433), vec2(-0.5, 0.0), vec2(-0.25, -0.433), vec2(0.25, -0.433));

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float coc(float d) {
	return clamp(abs(d - focus) * dof_scale, 0.0, 1.0) * blur;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, UV).rgb;
	if (use_dof > 0.5 && blur > 0.3) {
		float r = coc(texture(depth_tex, UV).r);
		vec3 acc = c;
		float wsum = 1.0;
		for (int i = 0; i < 12; i++) {
			// Sample at our own radius, but let blurry foreground bleed over sharp areas.
			vec2 o = DISK[i] * max(r, 0.0);
			vec2 suv = UV + o * px;
			float sd = texture(depth_tex, suv).r;
			float sr = coc(sd);
			vec2 o2 = DISK[i] * max(r, sr * step(sd, focus));
			vec3 s = texture(TEXTURE, UV + o2 * px).rgb;
			float w = smoothstep(0.0, 1.0, max(r, sr * step(sd, focus)));
			acc += s * w;
			wsum += w;
		}
		c = acc / wsum;
	}
	c *= exp2(exposure);
	c = lift + c * (gain - lift);
	c = (c - 0.5) * contrast + 0.5;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, vec3(l * 1.02, l, l * 0.97), mono);
	vec2 q = UV - 0.5;
	c *= 1.0 - dot(q, q) * vignette * 2.0;
	if (grain > 0.0) {
		c += (hash(UV * 997.0 + seed) - 0.5) * grain;
	}
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float b = BAYER[p.x + p.y * 4] / 16.0 - 0.47;
	c = floor(clamp(c, 0.0, 1.0) * levels + b * dither + 0.5) / levels;
	COLOR = vec4(c, 1.0);
}

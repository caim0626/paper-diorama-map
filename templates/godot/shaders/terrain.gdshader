shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// The ground of the map (RegionView): three small tiles laid by what the land is doing there —
// the paper ground where it is flat (meadow in patches over it, greener-grey as it rises), the earth road where `mask` says a
// road runs, the ink rock wherever it slopes more than a road's ramp — lit in three flat steps from one
// side, and thinned into the paper with distance like the cut-outs standing on it.

uniform sampler2D ground : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D road : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cliff : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D meadow : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D mask : filter_linear; // r = road, g = water (PaperTerrain.road_mask)
uniform vec2 size_m = vec2(160.0, 90.0); // the sheet in metres
uniform float tile_m = 3.0; // metres a ground or road tile covers
uniform float cliff_m = 5.0; // metres a cliff tile covers
uniform vec3 paper : source_color = vec3(0.953, 0.918, 0.839);
uniform vec3 ink : source_color = vec3(0.114, 0.106, 0.118);
uniform vec3 light_dir = vec3(-0.55, 0.75, 0.35); // toward the light: upper left, a little from the front
uniform float fog_near = 26.0;
uniform float fog_far = 70.0;

varying vec3 world;
varying vec3 wnormal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) { // smooth value noise, 0 .. 1
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnormal);
	float steep = smoothstep(0.86, 0.74, n.y); // 0 flat (a road's ramp too) .. 1 a cliff face
	vec4 m = texture(mask, world.xz / size_m);
	vec3 g = texture(ground, world.xz / tile_m).rgb;
	float grassy = noise(world.xz * 0.07) * 0.65 + noise(world.xz * 0.23) * 0.35; // meadow in patches over the paper
	g = mix(g, texture(meadow, world.xz / tile_m + vec2(0.21, 0.63)).rgb, smoothstep(0.6, 0.63, grassy));
	g = mix(g, g * vec3(0.86, 0.9, 0.82), floor(smoothstep(1.2, 6.0, world.y) * 3.0) / 3.0 * 0.8); // higher ground greener-grey, in steps
	vec3 r = texture(road, world.xz / tile_m + vec2(0.37, 0.11)).rgb;
	r = mix(r, paper, 0.18); // the earth a shade nearer the paper, so the road is a road and not a stain
	vec2 cuv = abs(n.x) > abs(n.z) ? world.zy : world.xy;
	vec3 c = texture(cliff, cuv / cliff_m * vec2(1.0, -1.0)).rgb;
	float on_road = smoothstep(0.44, 0.56, m.r) * (1.0 - steep);
	vec3 col = mix(g, r, on_road);
	float rim = smoothstep(0.28, 0.44, m.r) * (1.0 - smoothstep(0.44, 0.6, m.r)) * (1.0 - steep);
	col = mix(col, col * vec3(0.72, 0.68, 0.62), rim); // the road's edge, a darker line like the cut-outs' outlines
	col = mix(col, c, steep);
	col = mix(col, col * vec3(0.78, 0.80, 0.82), m.g); // the river bed under the water
	float lit = dot(n, normalize(light_dir));
	float band = lit > 0.55 ? 1.0 : (lit > 0.25 ? 0.84 : 0.7); // three flat steps of light: full on the cliffs,
	col *= mix(max(band, 0.95), band, steep); // barely a shade on the open ground
	float f = clamp((-VERTEX.z - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	ALBEDO = mix(col, paper, floor(f * 6.0 + 0.5) / 6.0);
}

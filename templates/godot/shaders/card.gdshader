shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;
// A paper cut-out standing in the world: always square to the camera, upright, cut out
// at hard alpha. Distance fades it into the paper in flat steps, like ink thinning out.

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0); // uv rect of this prop in the sheet
uniform vec3 paper : source_color = vec3(0.953, 0.918, 0.839);
uniform vec3 ink : source_color = vec3(0.114, 0.106, 0.118);
uniform float fog_near = 5.0;
uniform float fog_far = 22.0;
uniform float fade = 0.0; // 1 = gone
uniform vec2 near_fade = vec2(0.5, 1.4); // cut-outs right at the lens dissolve instead of filling it
uniform float sway = 0.0; // metres the top leans in the wind (grass, reeds, trees)
uniform vec3 hole = vec3(-1.0, -1.0, 0.0); // a window round the walker (screen x, y, his depth): what stands
uniform float hole_r = 0.0; // in front of him there is thinned out, so he is never lost behind a tree

varying float flip;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void vertex() {
	flip = MODEL_MATRIX[0].x < 0.0 ? -1.0 : 1.0;
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 back = vec3(-right.z, 0.0, right.x);
	float gust = sin(TIME * 1.4 + MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.23) * 0.7 + sin(TIME * 2.3 + MODEL_MATRIX[3].x) * 0.3;
	vec3 world = MODEL_MATRIX[3].xyz + right * (VERTEX.x * length(MODEL_MATRIX[0].xyz) + sway * gust * VERTEX.y * VERTEX.y)
		+ vec3(0.0, 1.0, 0.0) * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(back, 0.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	if (flip < 0.0) {
		uv.x = 1.0 - uv.x;
	}
	vec4 c = texture(tex, region.xy + uv * region.zw);
	if (c.a < 0.5) {
		discard;
	}
	vec3 col = c.rgb;
	float b = bayer4(FRAGCOORD.xy);
	float depth = -VERTEX.z;
	float gone = max(fade, 1.0 - clamp((depth - near_fade.x) / (near_fade.y - near_fade.x), 0.0, 1.0));
	if (gone > 0.0 && b < gone) {
		discard;
	}
	if (hole_r > 0.0 && depth < hole.z - 1.0 && distance(FRAGCOORD.xy, hole.xy) < hole_r && b < 0.62) {
		discard;
	}
	float f = clamp((depth - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	// six flat washes between the ink and the paper, like ink thinned in steps (no dither: it read as noise)
	float steps = floor(f * 6.0 + 0.5) / 6.0;
	ALBEDO = mix(col, paper, steps);
}

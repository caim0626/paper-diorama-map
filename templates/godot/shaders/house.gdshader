shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// A paper-box building on the map: its walls painted with flat elevation drawings, its roof a
// tiled texture; each face lit in one of three flat steps by which way it faces, thinned into the paper
// with distance like everything else on the map.

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 paper : source_color = vec3(0.953, 0.918, 0.839);
uniform vec3 light_dir = vec3(-0.55, 0.75, 0.35);
uniform float fog_near = 30.0;
uniform float fog_far = 80.0;

uniform vec3 hole = vec3(-1.0, -1.0, 0.0); // a window round the walker (screen x, y, his depth): this in front
uniform float hole_r = 0.0; // of him is thinned out, so he is never lost behind a building

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

varying vec3 wnormal;

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	if (hole_r > 0.0 && -VERTEX.z < hole.z - 1.0 && distance(FRAGCOORD.xy, hole.xy) < hole_r && bayer4(FRAGCOORD.xy) < 0.7) {
		discard;
	}
	float lit = dot(normalize(wnormal), normalize(light_dir));
	vec3 col = c.rgb * (lit > 0.55 ? 1.0 : (lit > 0.1 ? 0.84 : 0.7));
	float f = clamp((-VERTEX.z - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	ALBEDO = mix(col, paper, floor(f * 6.0 + 0.5) / 6.0);
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The ink beams along a paper-box building's edges (PaperHouse._edges): its thick outline, whichever
// way the camera turns.

uniform vec3 ink : source_color = vec3(0.114, 0.106, 0.118);
uniform vec3 hole = vec3(-1.0, -1.0, 0.0); // a window round the walker (screen x, y, his depth): this in front
uniform float hole_r = 0.0; // of him is thinned out, so he is never lost behind a building

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	if (hole_r > 0.0 && -VERTEX.z < hole.z - 1.0 && distance(FRAGCOORD.xy, hole.xy) < hole_r && bayer4(FRAGCOORD.xy) < 0.7) {
		discard;
	}
	ALBEDO = ink;
}

shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// A cut-out's shadow on the map: a soft ink oval lying on the ground under its foot.

uniform vec3 ink : source_color = vec3(0.114, 0.106, 0.118);
uniform float strength = 0.22;

void fragment() {
	float d = length((UV - 0.5) * 2.0);
	ALBEDO = ink;
	ALPHA = strength * (1.0 - smoothstep(0.55, 1.0, d));
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The river on the map: a sheet of slate-grey water just under the banks, with short ink
// ripples drifting downstream in rows. Only shows where the river has cut the ground below it.

uniform vec3 water : source_color = vec3(0.56, 0.60, 0.62);
uniform vec3 deep : source_color = vec3(0.42, 0.46, 0.49);
uniform vec3 paper : source_color = vec3(0.953, 0.918, 0.839);
uniform vec3 ink : source_color = vec3(0.114, 0.106, 0.118);
uniform float fog_near = 26.0;
uniform float fog_far = 70.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = floor(world.xz * 6.0) / 6.0;
	vec3 col = mix(water, deep, step(0.5, hash(floor(q * 0.5))) * 0.35);
	float row = floor(q.y * 1.5);
	float run = fract(q.x * 0.35 + hash(vec2(row, 3.0)) - TIME * 0.12);
	float ripple = step(0.82, run) * step(fract(q.y * 1.5), 0.18);
	col = mix(col, mix(ink, water, 0.45), ripple);
	float f = clamp((-VERTEX.z - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	ALBEDO = mix(col, paper, floor(f * 6.0 + 0.5) / 6.0);
}

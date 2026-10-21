shader_type spatial;
// Greybox material: a flat color with world-space grid lines every meter (thicker every 5 m),
// so distances and heights are easy to read while testing.

uniform vec4 albedo : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform float line_width = 0.02;
uniform float line_strength = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	return 1.0 - smoothstep(0.0, width, min(g.x, g.y));
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	float lines = max(grid(p, 1.0, line_width), grid(p, 5.0, line_width * 2.5));
	ALBEDO = mix(albedo.rgb, albedo.rgb * 0.45, lines * line_strength);
	ROUGHNESS = 0.85;
}

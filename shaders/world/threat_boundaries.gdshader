shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 line_color : source_color = vec4(1.0, 0.82, 0.45, 0.65);
uniform float fade_begin : hint_range(0.0, 10000.0) = 2000.0;
uniform float fade_end : hint_range(1.0, 30000.0) = 6000.0;

varying float forward_distance;

void vertex() {
	// Fade along travel only, preserving the full horizontal span of each line.
	forward_distance = abs((MODEL_MATRIX * vec4(VERTEX, 1.0)).z - INV_VIEW_MATRIX[3].z);
}

void fragment() {
	float visibility = 1.0 - smoothstep(fade_begin, max(fade_begin + 1.0, fade_end), forward_distance);
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * visibility;
}

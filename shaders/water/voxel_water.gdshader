shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_toon;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 shallow_color : source_color = vec4(0.13, 0.48, 0.47, 1.0);
uniform vec4 deep_color : source_color = vec4(0.055, 0.25, 0.34, 1.0);
uniform vec4 shore_color : source_color = vec4(0.56, 0.78, 0.66, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.48, 0.75, 0.73, 1.0);
uniform float depth_band_size : hint_range(5.0, 100.0, 5.0) = 20.0;
uniform float shore_depth : hint_range(1.0, 40.0, 1.0) = 15.0;
uniform float ripple_strength : hint_range(0.0, 0.3, 0.01) = 0.1;
uniform float animation_speed : hint_range(0.0, 2.0, 0.05) = 0.4;

varying vec3 world_position;

void vertex() {
	// No displacement: the surface and voxel shorelines stay exactly at Y = 0.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	float water_depth = depth_band_size * 4.0;
	if (scene_depth > 0.0) {
		// Forward+ reverse-Z depth reconstructs the opaque terrain below the water.
		vec4 floor_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
		floor_view /= floor_view.w;
		vec3 floor_world = (INV_VIEW_MATRIX * floor_view).xyz;
		water_depth = world_position.y - floor_world.y;
		// Keep zero-height voxel tops dry, including nearly coplanar depth samples.
		if (water_depth < 0.25) {
			discard;
		}
	}

	// Snap depth to the smallest supported terrain step (10 meters) to avoid band flicker.
	float voxel_depth = floor(water_depth / 10.0 + 0.5) * 10.0;
	float band = clamp(floor(voxel_depth / depth_band_size) / 3.0, 0.0, 1.0);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, band);
	float shore = 1.0 - step(shore_depth, voxel_depth);
	color = mix(color, shore_color.rgb, shore * 0.4);

	// Ten-meter squares repeat every 2560 meters, exactly dividing each origin shift.
	vec2 cell = floor(mod(world_position.xz / 10.0, vec2(256.0)));
	float phase = TIME * animation_speed;
	float wave = sin(dot(cell, vec2(1.0, 2.0)) * (TAU / 64.0) + phase);
	wave += sin(dot(cell, vec2(2.0, -1.0)) * (TAU / 32.0) - phase * 0.7);
	float tone = floor(clamp(wave * 0.25 + 0.5, 0.0, 1.0) * 3.0) / 3.0;
	// Fade subpixel squares before they shimmer at fleet-view distances.
	float footprint = max(length(dFdx(world_position.xz / 10.0)), length(dFdy(world_position.xz / 10.0)));
	float detail = 1.0 - smoothstep(0.5, 2.0, footprint);
	float sparkle = step(0.87, cell_hash(cell)) * step(0.66, tone);
	color *= 1.0 + (tone - 0.5) * ripple_strength * detail;
	color = mix(color, highlight_color.rgb, sparkle * ripple_strength * 2.0 * detail);
	ALBEDO = color;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	ALPHA = mix(0.88, 0.98, band);
}

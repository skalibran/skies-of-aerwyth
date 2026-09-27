shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

instance uniform float camera_fade_coverage : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D camera_fade_blue_noise : filter_nearest, repeat_enable;
// Five-meter noise grains fit the fifty-meter cloud voxels.
uniform float camera_fade_noise_density : hint_range(0.02, 2.0, 0.02) = 0.2;
uniform float distance_fade_start = 8000.0;
uniform float distance_fade_end = 10000.0;
uniform vec4 emission_color : source_color = vec4(0.12, 0.14, 0.17, 1.0);

varying vec3 surface_position;
varying vec3 surface_normal;
varying vec3 camera_offset;


// Dungeon Directive's dominant-axis blue-noise cutout, with exact endpoints.
float get_noise_threshold(vec3 position, vec3 normal) {
	vec2 noise_size = vec2(textureSize(camera_fade_blue_noise, 0));
	vec3 dominant_axis = abs(normalize(normal));
	vec2 noise_position;
	if (dominant_axis.x > dominant_axis.y && dominant_axis.x > dominant_axis.z) {
		noise_position = position.yz;
	} else if (dominant_axis.y > dominant_axis.z) {
		noise_position = position.xz;
	} else {
		noise_position = position.xy;
	}
	float threshold = textureLod(camera_fade_blue_noise,
		noise_position * camera_fade_noise_density / noise_size, 0.0).r;
	return (threshold * 255.0 + 0.5) / 256.0;
}

void vertex() {
	// Clouds stay world-aligned. Local coordinates anchor the pattern through rebasing.
	surface_position = VERTEX;
	surface_normal = NORMAL;
	camera_offset = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	// Match the former StandardMaterial3D's sRGB vertex colors.
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4)),
		COLOR.rgb / 12.92, lessThan(COLOR.rgb, vec3(0.04045)));
}

void fragment() {
	float camera_distance = length(camera_offset);
	float far_coverage = 1.0 - smoothstep(distance_fade_start,
		max(distance_fade_end, distance_fade_start + 1.0), camera_distance);
	if (min(camera_fade_coverage, far_coverage) <= get_noise_threshold(surface_position, surface_normal)) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	EMISSION = emission_color.rgb;
}

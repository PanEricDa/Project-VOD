shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// 本体原材质的主颜色由 UnitStateComponent 在运行时传入。
uniform vec4 base_color : source_color = vec4(1.0);
// 原材质存在 albedo 贴图时，由状态组件传入以保留单位原有配色。
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_base_texture = false;
// 与 StandardMaterial3D 的 UV1 设置对应，保持来源材质的纹理映射方式。
uniform vec3 base_uv_scale = vec3(1.0);
uniform vec3 base_uv_offset = vec3(0.0);
uniform bool use_triplanar = false;
uniform bool use_world_triplanar = false;
// 溶解边缘的金白色高光。
uniform vec4 edge_color : source_color = vec4(1.0, 0.72, 0.22, 1.0);
uniform float edge_emission_energy : hint_range(0.0, 10.0) = 1.6;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.001, 0.5) = 0.08;
uniform float noise_scale : hint_range(0.1, 20.0) = 4.0;
// 每次死亡由 UnitState 注入不同偏移，令溶解碎片图案不重复。
uniform vec3 noise_offset = vec3(0.0);

varying vec3 source_local_position;
varying vec3 source_world_position;
varying vec3 source_world_normal;
varying vec2 source_uv;


void vertex() {
	source_local_position = VERTEX;
	source_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	source_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	source_uv = UV;
}


float _hash_3d(vec3 value) {
	value = fract(value * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}


float _value_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 local = fract(position);
	local = local * local * (3.0 - 2.0 * local);

	float a = _hash_3d(cell + vec3(0.0, 0.0, 0.0));
	float b = _hash_3d(cell + vec3(1.0, 0.0, 0.0));
	float c = _hash_3d(cell + vec3(0.0, 1.0, 0.0));
	float d = _hash_3d(cell + vec3(1.0, 1.0, 0.0));
	float e = _hash_3d(cell + vec3(0.0, 0.0, 1.0));
	float f = _hash_3d(cell + vec3(1.0, 0.0, 1.0));
	float g = _hash_3d(cell + vec3(0.0, 1.0, 1.0));
	float h = _hash_3d(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(a, b, local.x), mix(c, d, local.x), local.y),
		mix(mix(e, f, local.x), mix(g, h, local.x), local.y),
		local.z
	);
}


vec3 _sample_source_albedo() {
	if (!use_base_texture) {
		return base_color.rgb;
	}
	if (!use_triplanar) {
		vec2 mapped_uv = source_uv * base_uv_scale.xy + base_uv_offset.xy;
		return base_color.rgb * texture(base_texture, mapped_uv).rgb;
	}
	vec3 mapping_position = source_local_position;
	if (use_world_triplanar) {
		mapping_position = source_world_position;
	}
	mapping_position = mapping_position * base_uv_scale + base_uv_offset;
	vec3 weights = abs(normalize(source_world_normal));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 x_projection = texture(base_texture, mapping_position.zy).rgb;
	vec3 y_projection = texture(base_texture, mapping_position.xz).rgb;
	vec3 z_projection = texture(base_texture, mapping_position.xy).rgb;
	return base_color.rgb * (
		x_projection * weights.x
		+ y_projection * weights.y
		+ z_projection * weights.z
	);
}


void fragment() {
	float noise = _value_noise(VERTEX * noise_scale + noise_offset);
	// 进度 0 时完整显示，进度 1 时所有碎片均被裁除。
	float threshold = dissolve_progress * 1.2 - 0.1;
	if (noise < threshold) {
		discard;
	}

	float edge = 1.0 - smoothstep(threshold, threshold + edge_width, noise);
	vec3 source_albedo = _sample_source_albedo();
	ALBEDO = mix(source_albedo, edge_color.rgb, edge);
	EMISSION = edge_color.rgb * edge * edge_emission_energy;
	ROUGHNESS = 0.72;
}

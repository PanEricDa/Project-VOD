// 玩家锁定目标的正式圆环材质。
// 在水平面片的 UV 空间中绘制边缘柔和的金黄色环形区域：
// - ring_color 为金黄色基础色与自发光颜色，取值 0～1；
// - outer_radius / inner_radius 为环形内外半径，单位为 UV 比例（0.5 贴满面片边缘）；
// - edge_smooth 控制环形边缘的软化宽度，单位为 UV 比例；
// - emission_strength 为自发光强度，保持克制以保证不同光照下可读；
// - overall_alpha 为总透明度（0～1），由 TargetLockIndicator.gd 独占写入，
//   业务组件不得直接设置该参数。
// 渲染保持正常深度遮挡（不关闭深度测试，圆环会被墙体与地形正常遮挡），
// 无光照模式，双面可见。
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 ring_color : source_color = vec4(1.0, 0.78, 0.16, 1.0);
uniform float outer_radius = 0.5;
uniform float inner_radius = 0.45;
uniform float edge_smooth = 0.02;
uniform float emission_strength = 0.6;
uniform float overall_alpha = 0.0;

void fragment() {
	float dist = length(UV - vec2(0.5));
	float aa = max(edge_smooth, 0.001);
	float ring = smoothstep(inner_radius - aa, inner_radius + aa, dist)
		* (1.0 - smoothstep(outer_radius - aa, outer_radius + aa, dist));
	ALBEDO = ring_color.rgb;
	EMISSION = ring_color.rgb * emission_strength;
	ALPHA = ring * clamp(overall_alpha, 0.0, 1.0);
}

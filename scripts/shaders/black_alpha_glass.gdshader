shader_type spatial;
// 黑色 = 透明玻璃（Black-Alpha，连续灰度映射）：贴图亮度直接决定不透明度。
// - 越黑越透：亮度 0（黑）→ alpha 0（全透明）；亮度 1（白）→ alpha 1（全实）。
// - 中间值按 alpha_power 曲线连续过渡（默认线性），非二值阈值。
// - blend_mix：半透明混合；cull_disabled：单面片双面可见；depth_draw_never：
//   玻璃不写深度，透明区域不遮挡背后物体。
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_power : hint_range(0.1, 4.0) = 1.0;   // 亮度→透明度曲线指数：1=线性，<1 整体更透，>1 整体更实
uniform float alpha_scale : hint_range(0.0, 2.0) = 1.0;   // 整体透明度缩放（<1 更透）
uniform float roughness : hint_range(0.0, 1.0) = 0.2;     // 玻璃表面粗糙度
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	// 亮度（Rec.709 luma）
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 越黑越透：黑(0)→全透，白(1)→全实，中间按曲线连续过渡
	float alpha = pow(clamp(lum, 0.0, 1.0), alpha_power);
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = clamp(alpha * alpha_scale, 0.0, 1.0) * c.a;
}

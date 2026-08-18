shader_type spatial;
// 投影阴影：采样角色立绘（SubViewport 输出的含 alpha 纹理），输出与角色轮廓一致的
// 暗色“投影”阴影（区别于圆形晕影）。阴影形状由立绘 alpha 决定，铺在角色脚下。
// - unshaded：阴影本身不受光照。
// - blend_mix：alpha 混合（透明淡出，务必保留）。
// - cull_disabled：双面，平躺后从任何角度仍可见。
render_mode unshaded, blend_mix, cull_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white;  // 角色立绘纹理（含 alpha）
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);  // 阴影颜色（RGBA）

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = shadow_color.rgb;
	ALPHA = tex.a * shadow_color.a;
}

shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

// 外发光（穿透层）：在角色整体剪影（SubViewport 合成纹理）外缘向外发出柔和渐变光晕。
// - depth_test_disabled：发光层忽略深度，始终可见（穿透墙体等遮挡物）。
// - 只输出轮廓外的光晕，角色内部（alpha>0 区域）输出透明，由独立的角色本体层负责显示。
// repeat_disable：采样越界时 clamp 到边缘，避免 wrap 到对侧产生伪影。
uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform vec4 glow_color : source_color = vec4(1.0, 0.84, 0.2, 1.0);
uniform float glow_radius : hint_range(0.0, 80.0) = 24.0;   // 发光半径（viewport 像素）
uniform float glow_intensity : hint_range(0.0, 8.0) = 2.0;  // 发光强度
uniform vec2 texel_size = vec2(0.001953125, 0.001953125);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;     // 淡入淡出（脚本按悬停驱动）

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float a = c.a;

	// 3 圈 × 8 方向采样（较原 4×12 减半），距离越远权重越低 → 宽柔渐变光晕
	float glow = 0.0;
	float total_w = 0.0;
	const int RINGS = 3;
	const int DIRS = 8;
	for (int r = 1; r <= RINGS; r++) {
		float dist = glow_radius * float(r) / float(RINGS);
		float w = 1.0 / float(r);
		for (int i = 0; i < DIRS; i++) {
			float ang = 6.28318530718 * float(i) / float(DIRS);
			vec2 d = vec2(cos(ang), sin(ang)) * texel_size * dist;
			vec2 suv = clamp(UV + d, vec2(0.0), vec2(1.0));
			glow += texture(albedo_tex, suv).a * w;
			total_w += w;
		}
	}
	float g = clamp(glow / max(total_w, 0.0001) * glow_intensity, 0.0, 1.0);
	// 只在透明区（轮廓外）发光；本体区域 alpha=0（由角色本体层显示）
	float amount = (1.0 - a) * g * glow_amount;

	ALBEDO = glow_color.rgb;
	ALPHA = amount * glow_color.a;
}

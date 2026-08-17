shader_type spatial;
// 遮挡洞型看穿：墙上打个洞，中心洞透明、边缘平滑过渡，墙其余保持实心。
// - blend_mix：半透明混合，平滑过渡（无噪声/无 discard 硬边）。
// - depth_prepass_alpha：透明几何的深度预通道写深度，用于排序与阴影。
// - cull_back（默认）：只渲染正面，底面不穿帮。
// 由 OcclusionShatter 组件施加，fade(0~1) 动画淡入淡出。
render_mode blend_mix, depth_prepass_alpha;

uniform float fade : hint_range(0.0, 1.0) = 0.0;          // 虚化进度：0=完全可见，1=看穿状态
uniform float roughness : hint_range(0.0, 1.0) = 1.0;      // 继承原材质粗糙度
uniform float metallic : hint_range(0.0, 1.0) = 0.0;       // 继承原材质金属度
uniform vec3 axis_origin = vec3(0.0);                      // 喇叭口起点（角色球心）
uniform vec3 axis_dir = vec3(0.0, 0.0, 1.0);               // 喇叭口朝向（球心→相机，单位向量）
uniform float core_radius : hint_range(0.0, 10.0) = 0.8;   // 完全透明的洞半径（主轴周围）
uniform float falloff : hint_range(0.0, 20.0) = 1.0;       // 洞边缘平滑过渡带宽度
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	// 片元到喇叭口主轴的垂直距离
	vec3 to_axis = world_pos - axis_origin;
	float along = dot(to_axis, axis_dir);
	float dist = length(to_axis - axis_dir * along);
	// 洞型看穿：中心（dist<core）完全透明，向外平滑过渡到不透明（墙其余实心）
	float radial = smoothstep(core_radius, core_radius + falloff, dist);
	float target_alpha = radial;  // 0（洞中心）→ 1（远端不透明）
	// fade 从 0（完全可见）平滑过渡到看穿状态
	float alpha = mix(1.0, target_alpha, fade);
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = base.a * alpha;
}

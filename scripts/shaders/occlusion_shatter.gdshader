shader_type spatial;
// 遮挡洞型看穿：墙上打“多个洞”，中心洞透明、边缘平滑过渡，墙其余保持实心。
// 支持同一堵墙被多个角色同时遮挡：每个被挡角色在墙上各打一个洞（axis_origins/axis_dirs 数组），
// 取所有洞的并集（min radial），从而两个角色都被墙体挡住时都能被看穿。
// - blend_mix：半透明混合，平滑过渡（无噪声/无 discard 硬边）。
// - depth_prepass_alpha：透明几何的深度预通道写深度，用于排序与阴影。
// - cull_back（默认）：只渲染正面，底面不穿帮。
// 由 OcclusionShatter 组件施加，fade(0~1) 动画淡入淡出。
render_mode blend_mix, depth_prepass_alpha;

const int MAX_HOLES = 16;  // 单堵墙同时支持的最大洞数（与 OcclusionShatter.MAX_HOLES 保持一致）

uniform float fade : hint_range(0.0, 1.0) = 0.0;          // 虚化进度：0=完全可见，1=看穿状态
uniform float roughness : hint_range(0.0, 1.0) = 1.0;      // 继承原材质粗糙度
uniform float metallic : hint_range(0.0, 1.0) = 0.0;       // 继承原材质金属度
uniform int hole_count = 0;                                // 实际生效的洞数量（<= 16）
uniform vec3 axis_origins[16];                             // 各洞喇叭口起点（角色球心）
uniform vec3 axis_dirs[16];                                // 各洞喇叭口朝向（球心→相机，单位向量）
uniform float core_radius : hint_range(0.0, 10.0) = 0.8;   // 完全透明的洞半径（主轴周围）
uniform float falloff : hint_range(0.0, 20.0) = 1.0;       // 洞边缘平滑过渡带宽度
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 片元到单个喇叭口主轴的垂直距离 → 洞型径向系数（0=洞中心全透，1=远端不透明）
float hole_radial(vec3 wp, vec3 origin, vec3 dir) {
	vec3 to_axis = wp - origin;
	float along = dot(to_axis, dir);
	float dist = length(to_axis - dir * along);
	return smoothstep(core_radius, core_radius + falloff, dist);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	// 取所有洞的并集：任一洞命中的地方即透明（min）。无洞时保持径向=1（不透明）。
	float radial = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= hole_count) {
			break;  // 只计算实际生效的洞
		}
		radial = min(radial, hole_radial(world_pos, axis_origins[i], axis_dirs[i]));
	}
	// fade 从 0（完全可见）平滑过渡到看穿状态
	float alpha = mix(1.0, radial, fade);
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = base.a * alpha;
}

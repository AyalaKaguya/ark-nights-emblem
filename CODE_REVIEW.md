# ArkNight-Emblem — GDScript Code Review

> 审查范围：`scripts/` 全部 10 个 `.gd`、`scripts/shaders/` 3 个 `.gdshader`、`scenes/character/hd2d_character.tscn`、`node_3d.tscn`、`project.godot`、`tests/`。
> 方式：静态通读 + 对照 Godot 4.7 / GDScript 2.0 最佳实践。**本报告未修改任何代码。**
> 角色：GodotGameplayScripter（类型安全 / 信号完整性 / 节点组合 / 资源格式）。

---

## 一、总体评价

代码整体质量**良好**，能看出作者有清晰的工程意识：

- 信号全部 `snake_case`、参数完整类型化、带 `##` 文档注释 ✅
- `CharacterStateMachine` 用 Callable 注入解耦动画播放，状态机与宿主分离设计干净 ✅
- `collision_rids.gd` 作为共享工具、主动不加 `class_name` 避免 SHADOW 警告，注释到位 ✅
- `.tscn` 文件头 `format=3`、无注释、UID 正确 ✅
- 已有 `tests/` 用 SceneTree 脚本验证碰撞数学与路径平滑，是好习惯 ✅
- `HD2DCharacter` 内有相机缓存、悬停每 4 帧节流、遮挡用阴影副本保阴影等细致优化 ✅

但存在 **2 处真实逻辑缺陷**、若干 **类型安全缺口** 与 **可维护性** 问题，按严重度列出。

---

## 二、严重度排序的发现

### 🔴 HIGH — 真实逻辑缺陷

#### F1. `HD2DCharacter.move_to()` 未清空 `_path` / `_path_callback`
**文件**：`scripts/character/hd2d_character.gd`（`move_to` vs `stop_moving`）

`stop_moving()` 会清空 `_path` 与 `_path_callback`，但 `move_to()` **没有**：
```gdscript
func move_to(target: Vector3, arrive: Callable = Callable()) -> void:
    _move_target = target
    _has_move_target = true
    _arrive_callback = arrive
    _move_dir = _dir_to(_move_target)
    set_state(CharacterState.Id.MOVE)
    # ❌ 缺少：_path = PackedVector3Array(); _path_callback = Callable()
```

后果：`_update_movement()` 在到达直接目标后判断 `if _path.size() > 0:` —— 若此前 `move_along_path()` 留下的路径尚未走完（角色正沿导航路径移动时被打断 / 同角色同时被 AI 的 `move_to` 驱动），会在到达直行点后**继续把旧导航路径走完**，造成"瞬移式续走"。

**复现场景**：玩家右键导航（走 path）→ 同一角色被 `move_to` 直行驱动（如 AI 漫游目标、脚本化移动）→ 到达直行点后续走旧 path。
**建议**：`move_to` 起始处调用与 `stop_moving` 对称的清空逻辑（`_path = PackedVector3Array(); _path_callback = Callable()`）。

---

#### F2. `AiController` 对目标的 duck-typing 守卫不一致
**文件**：`scripts/ai/ai_controller.gd`（`_process` / `_decide` / `_wander`）

`_process` 只守卫了 `get_state` 与 `stop_moving`：
```gdscript
if _target == null or not _target.has_method("get_state"): return
...
if _target.has_method("stop_moving"): _target.stop_moving()
```
但 `_decide()` 直接调用 `_target.set_state(...)`、`_wander()` 直接调用 `_target.move_to(...)`，**没有任何 `has_method` 守卫**。若 `target_path` 指向一个只有 `get_state` 但没有 `move_to`/`set_state` 的节点，会在运行时抛 `Method not found`。

**建议**（任选其一，推荐其一）：
- 将 `_target` 类型化为 `HD2DCharacter`（`hd2d_character.gd` 与 `ai_controller.gd` 无循环依赖，可安全 `preload`），彻底消除 duck-typing 风险；
- 或在 `_ready` 解析后统一校验所需方法集，缺失则 `push_error` 并返回。

---

### 🟠 MEDIUM — 类型安全 / 健壮性

#### F3. `HD2DCharacter` 用 `StaticBody3D` 作拾取体，却每帧移动 `global_position`
**文件**：`scenes/character/hd2d_character.tscn` + `hd2d_character.gd`

`PickBody` 是 `StaticBody3D`，而角色通过 `_update_movement` 每帧直接改 `global_position`。Godot 中 `StaticBody3D` 预期静止，每帧移动会触发 broadphase / 物理状态更新的非预期开销，且不符合语义。该碰撞体仅用于鼠标射线拾取。

**建议**：若只需射线拾取，可改为 `Area3D`（与 `Interactable` 的 `PickArea` 一致），或在文档中明确"本 StaticBody 仅作射线目标、不参与动力学"的约束。

#### F4. 悬停射线 `collision_mask = 3` 含多余层
**文件**：`scripts/character/hd2d_character.gd`（`_update_hover`，行 ~306）

```gdscript
query.collision_mask = 3  # layer 1（墙/地面）+ layer 2（角色拾取体）
query.exclude = _get_wall_rids()
```
`PickBody` 在 layer 2，但 mask 把 layer 1（地面/墙）也纳入。射线取**最近命中**，若地面/墙体在 layer 1 且比角色胶囊更靠近相机（俯视、贴地等情形），`hit.get("collider")` 会是地面而非角色，`is_ancestor_of` 失败 → 悬停失效。虽然后续 `exclude` 排除了 `occlusion_wall`，但 ground 仍在 mask 内。

**建议**：悬停专用射线 mask 直接设为 `2`（仅角色拾取层），与 `_try_select` 的 `mask=4`（layer 3，交互拾取区）保持对称清晰。

#### F5. `CharacterStateMachine._init` 参数未类型化
**文件**：`scripts/character/character_state_machine.gd`

```gdscript
func _init(play_animation: Callable, is_finished: Callable) -> void:  # ❌ 当前无类型
```
应显式标注 `Callable` 与返回 `-> void`，符合"生产代码零未类型参数"准则。

#### F6. `AiController._target` / `PlayerController._character` 为 `Variant` + duck-typing
**文件**：`scripts/ai/ai_controller.gd`、`scripts/player/player_controller.gd`

两者都用 `var _target: Variant = null` / `var _character: Variant = null` 并通过 `has_method` 调用。运行时才能发现方法缺失（且见 F2）。`HD2DCharacter` 已 `class_name`，无循环依赖，**强烈建议直接类型化为 `HD2DCharacter`**，让错误在解析期暴露。

#### F7. `OcclusionShatter` 多个 Dictionary 未类型化
**文件**：`scripts/camera/occlusion_shatter.gd`

`_fades`、`_infos`、`_originals`、`_shadow_dupes`、`_shadow_states`、`_last_active` 均为无类型 `Dictionary`。GDScript 2.0 支持 `Dictionary[MeshInstance3D, float]` 等写法，类型化可带来运行时校验与编辑器补全。

---

### 🟡 LOW — 规范 / 可维护性

#### F8. `CharacterState` 有 `class_name` 但无显式 `extends`
**文件**：`scripts/character/character_state.gd`
当前靠"无 `extends` 默认 `RefCounted`"工作，能编译。建议显式 `extends RefCounted` 以避免未来 Godot 版本或拼写改动带来的意外。

#### F9. `InteractableBeacon` 用字符串路径 `extends` 而非 `class_name`
**文件**：`scripts/interaction/interactable_beacon.gd`
基类有 `class_name Interactable`，子类应写 `extends Interactable` 以符合项目约定，避免路径硬编码。

#### F10. `RpgCamera.focus` 未校验 `is Node3D`
**文件**：`scripts/camera/rpg_camera.gd`（`_ready` / `@onready`）
`focus_path` 若指向非 `Node3D` 节点，`get_node_or_null` 返回值赋给 `focus: Node3D` 不报错，但后续 `focus.global_position` 会在运行时崩溃。建议 `_ready` 增加 `focus is Node3D` 校验。

#### F11. `_update_movement` 中 `_path_index += 1` 与 `_advance_path_point` 内部自增重复
**文件**：`scripts/character/hd2d_character.gd`
到达点后手动 `_path_index += 1` 再调 `_advance_path_point()`，而后者循环内已自增推进已到达点。当前逻辑正确但冗余，后续改动路径推进逻辑时易引入"跳点" bug。建议统一由 `_advance_path_point` 负责推进，调用方不手动 `+1`。

#### F12. `_get_wall_rids()` 缓存一次性失效
**文件**：`scripts/character/hd2d_character.gd`
`_wall_rids_valid` 一旦置 true 不再刷新；若运行时动态增删 `occlusion_wall` 物体，缓存会过期。静态世界无碍，动态场景需失效机制。

#### F13. `set_skeleton_data()` 与 `skeleton_data` 导出属性命名易混淆
**文件**：`scripts/character/hd2d_character.gd`
直接赋值 `skeleton_data = x` 不会更新 SpineSprite（Godot 不会把 `set_skeleton_data` 当作该属性 setter）。应在注释/API 上明确"切换骨骼必须调用 `set_skeleton_data()` 方法"。

#### F14. `project.godot` 未开启 GDScript 严格警告
缺少 `gdscript/warnings/enable_all_warnings=true`。建议开启，让 F5/F6 这类类型问题在解析期暴露。

#### F15. 跨系统通信依赖 `get_tree().get_nodes_in_group(...)` + 直接方法调用
`PlayerController`、`AIController`、`RpgCamera` 之间无统一信号总线。当前规模可接受；随系统增长，建议引入带类型的 `EventBus` Autoload 解耦（如选中变更、状态变更广播）。

---

### 🟢 架构可维护性提示

- **`HD2DCharacter` 约 700 行单文件**，同时负责 billboard、glow、方向指示器、悬浮状态面板、移动、角色间避让、悬停、朝向。建议逐步抽出 `BillboardComponent` / `HoverComponent` / `StatusPanelComponent` / `CollisionAvoidanceComponent`，遵循"组合优于巨型脚本"。这是**可维护性**建议，非阻塞问题。

---

## 三、值得保留的优点（不要回退）

1. 信号命名与类型化规范统一，文档注释充足。
2. `CharacterStateMachine` 通过 Callable 注入与宿主解耦，状态切换 / 一次性动画回退逻辑清晰。
3. `collision_rids.gd` 刻意不加 `class_name` 规避 shadow，注释解释原因——很好的工程判断。
4. 预加载常量代替字符串路径引用脚本，且无循环依赖。
5. `tests/` 用 `--script` SceneTree 验证碰撞钳制与 Chaikin 平滑，提供回归基线。
6. 遮挡系统用"只投阴影副本"保住看穿后的阴影，思路细腻。

---

## 四、建议优先处理顺序

| 优先级 | 项 | 动作 |
|--------|----|------|
| P0 | F1 | `move_to` 内清空 `_path`/`_path_callback`（一行修复，防续走旧路径） |
| P0 | F2 | 统一 AI 目标方法守卫，或把 `_target` 类型化为 `HD2DCharacter` |
| P1 | F3 / F4 | 拾取体改 `Area3D`、悬停 mask 收敛到拾取层 |
| P1 | F5 / F6 | 给 `CharacterStateMachine._init` 与控制器目标加类型 |
| P2 | F7–F15 | 字典类型化、显式 extends、EventBus、严格警告等规范项 |

> 以上所有修改均应在你的授权下由我执行；本次仅作审查，未改动任何文件。

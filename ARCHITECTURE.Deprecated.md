# ArkNight Emblem — 架构指导文档（ADD）

> 版本：1.59 —— 与 GDD v1.61 / 战斗道具空槽规则竖切对齐 · 日期：2026-06-30
> 角色：架构师视角 · 适用范围：GDScript + Godot 4.7 + Spine 扩展

---

## 目录

1. [文档定位与设计哲学](#1-文档定位与设计哲学)
2. [分层架构总览](#2-分层架构总览)
3. [L0 · 全局服务层](#3-l0--全局服务层)
4. [L1 · 世界控制层](#4-l1--世界控制层)
5. [L2 · 游戏逻辑层](#5-l2--游戏逻辑层)
6. [L3 · 表现层](#6-l3--表现层)
7. [资源复用体系](#7-资源复用体系)
8. [目录结构与命名](#8-目录结构与命名)
9. [信号流与依赖规则](#9-信号流与依赖规则)
10. [数据驱动与存档](#10-数据驱动与存档)
11. [输入路由](#11-输入路由)
12. [扩展性指引](#12-扩展性指引)
13. [反模式清单](#13-反模式清单)
14. [实施路线](#14-实施路线)

---

## 1. 文档定位与设计哲学

### 1.1 文档定位

本文档是 ArkNight Emblem 的**架构指导文档（ADD）**，与 [GDD.md](./GDD.md) v1.61 配套：

- **GDD** 回答"游戏是什么"——玩法、数值、系统设计
- **ADD** 回答"代码怎么组织"——分层、模块、依赖、扩展点

GDD 描述的所有系统（双资源、实时/回合切换、统一地图、通信锚点、基建、装备、技能、状态效果、8 职业、6 干员战斗）都必须在 ADD 中找到对应的模块归属。

### 1.2 当前实现基线（2026-06-28）

当前工程已经具备 M0 可玩竖切，架构基线如下：

| 模块 | 当前落点 | 状态 |
|------|----------|------|
| 启动入口 | `scenes/bootstrap.tscn` + `scripts/bootstrap.gd` | 加载地图、生成开发期 4 人小队、实例化 HUD 与开发期输入 |
| 地图加载 | `WorldDirector.load_map("dragon_outer")` | 已接入 `MapManifest`、`MapInstance`、场景内 `TerrainRegion` 与 `TerrainData` 正式地形类型 |
| 首张地图 | `scenes/maps/dragon_outer.tscn` + `data/maps/dragon_outer.tres` | 灰盒场景包含标准根节点；Manifest 描述入口、手写地形成本覆盖、阻挡格，并引用带波次/奖励/剧情标记的 EncounterData；场景内 `TerrainRegion` 通过 `terrain_id` 引用 `rubble_slow` / `cover_blocked` / `originium_pollution`，并写入 `GameGrid3D` terrain_id 查询表；M0 敌人资源通过 `faction_id` 标注 `infected` 阵营；dragon_outer_intro 的增援波次已配置 `conditions` 示例 |
| 单位 | `OperatorUnit` / `EnemyUnit` / `SummonedUnit` | 开发期小队使用 4 个独立 `OperatorData`（阿米娅、医疗、近卫、重装），M0 敌人已数据驱动；技能通过 `SummonData` 生成不进入小队、不接受玩家指令的临时友方攻击/治疗/防御/条件陷阱、目标状态/血量过滤陷阱、连锁陷阱、地形联动陷阱、限时残留地形、地形转化与残留扩散陷阱召唤物，并保留 `spawn_vfx_id` / `expire_vfx_id` / `hud_icon_text` / `ui_hint` 表现 hook |
| 小队控制 | `scripts/game/squad/squad_controller.gd` | 管理当前地图上的小队成员、主控切换、实时跟随队形和主控阵亡后的自动接管 |
| 战斗 | `BattleController` + `TurnManager` + `BattleState` + `BattleLog` | 实时 WASD/右键移动、1–4 主控切换与小队跟随触发警戒后进入回合；敌方与召唤物自动行动，玩家移动/普攻/技能/召唤，危险地形伤害，按数据条件生成增援波次，胜负回到实时模式；`BattleLog` 记录行动明细、状态效果变化、环境伤害、召唤/退场、召唤治疗、召唤护援、陷阱触发、连锁陷阱触发、地形联动陷阱、限时残留地形、地形转化残留、残留扩散和汇总统计 |
| 输入 | `InputRouter` + `scripts/game/input/bootstrap_input_controller.gd` | REALTIME 与 COMBAT_TURN 输入注册式分发；Bootstrap 不再直接实现 `_unhandled_input` |
| 选择/路径 | `scripts/game/selection/path_preview_controller.gd` + `scripts/game/selection/targeting_controller.gd` | `PathPreviewController` 负责鼠标地面投射、按 `GameGrid3D` 移动成本寻路、路径预览格渲染；`TargetingController` 负责显式选格/选敌，并为普攻、技能和后续道具提供目标 |
| 行动 | `MoveAction` / `AttackAction` / `SkillAction` / `SummonedUnit.ai_take_turn()` | 移动接入网格地形成本与体力；普攻接入物理公式；技能接入体力 + SP + 法术公式；召唤物使用 `SummonData` 配置的自动攻击、治疗、护援、条件陷阱、阵营/状态/血量过滤陷阱、连锁陷阱、地形联动陷阱、限时残留地形、地形转化或残留扩散陷阱行动包，不走玩家输入入口 |
| 相机 | `CameraRig` | 实时跟随 + 战术斜俯视 |
| UI/表现 | `scenes/ui/hud_battle.tscn` + `scenes/ui/panel_item_loadout.tscn` + `scenes/ui/panel_battle_result.tscn` + `scripts/ui/*.gd` + `scripts/visual/skill_effect_presenter.gd` | Bootstrap 暂时实例化；HUD 显示资源、三技能槽、运行时冷却、三槽战斗道具栏、空槽、道具选中槽/数量/稀有度/分类/目标/CD、技能可用状态、状态效果、当前瞄准目标、技能单体/范围命中预览、召唤物剩余轮数、陷阱未启用倒计时、`hud_icon_text` 和 `ui_hint`；ItemLoadoutPanel 显示固定 3 个携带槽、空槽与可用战斗道具库存，槽位点击请求 Bootstrap 在可用道具和空槽之间循环替换对应 `combat_item_slots`；当当前参与者为召唤物时禁用玩家技能/道具入口；独立 BattleResultPanel 展示结构化战斗结算、`BattleLog` 汇总和行动记录；SkillEffectPresenter 监听技能释放和 `summon_visual_requested`，生成开发期技能表现、召唤生成/退场/触发标记、陷阱触发/连锁范围预览与浮字提示，后续迁入正式 UI/VFX 管线 |

这条链路是后续开发的稳定锚点：新增功能应优先挂接到这条运行路径，而不是另起一套测试入口。

### 1.3 设计原则

| 原则 | 含义 | 反例 |
|------|------|------|
| **分层解耦** | L0/L1/L2/L3 自上而下依赖，不反向 | UI 节点直接调用 Unit 内部方法 |
| **数据驱动** | 静态数据用 Resource，运行时可变状态外置 | 在脚本里硬编码技能参数 |
| **协议优先** | 模块间通过鸭子类型方法/信号通信，不强制类型耦合 | 每个调用点都 `as Unit` 强转 |
| **状态外置** | 节点是表现，状态放 Resource/Autoload | 把 `turn_number` 放在场景根节点 |
| **资源可池化** | 高频创建/销毁的对象走对象池 | 地图切换时 `queue_free()` 干员视觉 |
| **演进优于重写** | 增量交付，每阶段可独立运行与验证 | 一次性写完所有模块才集成 |

---

## 2. 分层架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  L3 · 表现层 Presentation                                       │
│  CameraRig · SpineCharacterVisual3D · UI · 特效 · 音频          │
└─────────────────────────────────────────────────────────────────┘
                              ↑ 依赖
┌─────────────────────────────────────────────────────────────────┐
│  L2 · 游戏逻辑层 GameLogic                                      │
│  ModeManager · TurnManager · BattleController · Unit            │
│  Action · Skill · StatusEffect · Stamina/SP/HP Tracker          │
└─────────────────────────────────────────────────────────────────┘
                              ↑ 依赖
┌─────────────────────────────────────────────────────────────────┐
│  L1 · 世界控制层 World                                          │
│  WorldDirector · MapInstance · PortalNode · AnchorNode          │
│  WorldState · MapManifest                                       │
└─────────────────────────────────────────────────────────────────┘
                              ↑ 依赖
┌─────────────────────────────────────────────────────────────────┐
│  L0 · 全局服务层 Bootstrap (Autoload)                           │
│  EventBus · GameStateService · SaveService · AssetLibrary       │
│  ModeManager · InputRouter · SettingsService · SkillRegistry    │
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 层级职责

| 层 | 职责 | 不做的事 |
|----|------|----------|
| **L0** | 跨场景全局服务、信号总线、持久化、资源缓存 | 不持有场景节点引用（除 Autoload 自身） |
| **L1** | 单张地图生命周期、地图间切换、世界级状态 | 不管战斗逻辑、不管 UI |
| **L2** | 战斗/回合/单位/行动/技能/状态等玩法逻辑 | 不管资源加载、不管场景切换 |
| **L3** | 玩家可见的一切：视觉、UI、相机、特效 | 不直接修改游戏状态（通过 EventBus 发请求） |

### 2.2 依赖方向

- 高层 → 低层：✅ 允许（L3 可调用 L0 服务）
- 低层 → 高层：❌ 禁止（L0 不能直接调 L3 的 UI）
- 跨层通信用 `EventBus` 信号总线（见 §3.1）
- 同层通信用直接信号或方法调用

---

## 3. L0 · 全局服务层

所有 L0 服务在 `project.godot` 中注册为 Autoload，全场景可访问。

```ini
# project.godot
[autoload]
EventBus="*res://scripts/autoload/event_bus.gd"
GameStateService="*res://scripts/autoload/game_state_service.gd"
WorldDirector="*res://scripts/autoload/world_director.gd"
ModeManager="*res://scripts/autoload/mode_manager.gd"
SaveService="*res://scripts/autoload/save_service.gd"
AssetLibrary="*res://scripts/autoload/asset_library.gd"
SkillRegistry="*res://scripts/autoload/skill_registry.gd"
InputRouter="*res://scripts/autoload/input_router.gd"
SettingsService="*res://scripts/autoload/settings_service.gd"
```

### 3.1 EventBus — 信号总线

全局事件中枢。所有跨层通信走这里。

```gdscript
# scripts/autoload/event_bus.gd
extends Node
class_name EventBus

# 模式
signal mode_changed(from_mode: int, to_mode: int, scope_center: Vector3, scope_radius: float)

# 回合
signal round_started(round_number: int)
signal turn_started(participant: Node)
signal turn_ended(participant: Node)
signal round_ended(round_number: int)
signal battle_started(battle_state: Resource)
signal battle_ended(result: Dictionary)
signal battle_stat_recorded(entry: Dictionary)

# 单位
signal unit_spawned(unit: Node)
signal unit_died(unit: Node)
signal unit_selected(unit: Node)
signal unit_moved(unit: Node, from: Vector3, to: Vector3)
signal stat_changed(unit: Node, stat_name: String, old_value: float, new_value: float)
signal skill_used(actor: Node, primary_target: Node, skill_data: Resource, affected_targets: Array, total_damage: int)
signal summon_requested(actor: Node, target_position: Vector3, summon_data: Dictionary)
signal summon_retire_requested(summon: Node, reason: String)
signal summon_visual_requested(summon: Node, event_name: String, reason: String, vfx_id: String, ui_hint: String, position: Vector3)

# 世界
signal map_loaded(map_id: String, entry_point: String)
signal map_unloading(map_id: String)
signal anchor_discovered(anchor_id: String)
signal anchor_activated(anchor_id: String)
signal portal_entered(portal_id: String, dest_map: String)

# UI 请求（L3 → L2）
signal request_open_panel(panel_name: String, context: Dictionary)
signal request_close_panel(panel_name: String)
signal request_use_action(action_id: String, target: Variant)
signal request_end_turn()
signal request_toggle_mode()

# 存档
signal save_started(slot_id: String)
signal save_finished(slot_id: String, success: bool)
signal load_started(slot_id: String)
signal load_finished(slot_id: String, success: bool)
```

**使用规则**：
- L2/L3 触发事件用 `EventBus.signal_name.emit(args)`
- L2/L3 监听事件用 `EventBus.signal_name.connect(callable)`
- 信号名必须用过去式或名词短语，避免动词歧义
- 信号参数必须用强类型，禁止 `Variant` 兜底

### 3.2 GameStateService — 运行时游戏状态

存放跨场景/跨地图的运行时可变状态。**不放节点**，全部用 Resource 或 Dictionary 承载。

```gdscript
# scripts/autoload/game_state_service.gd
extends Node
class_name GameStateService

# 当前队伍（跨地图保留引用）
var squad: SquadState = SquadState.new()

# 玩家拥有的干员全集
var owned_operators: Array[String] = []

# 玩家背包（大世界共享）
var shared_inventory: Dictionary = {}

# 小队战斗道具携带槽（固定 3 槽，空字符串代表空槽；空档时由 Bootstrap 注入开发期默认值）
var combat_item_slots: Array[String] = []
var selected_combat_item_slot_index: int = 0

func set_combat_item_slot(slot_index: int, item_id: String) -> bool
func get_combat_item_slot_id(slot_index: int) -> String
func cycle_combat_item_slot(direction: int = 1) -> String

# 任务系统
var quest_state: QuestState = QuestState.new()

# 阵营声望
var faction_reputation: Dictionary = {}  # {faction_id: int}

# 主控角色 ID
var main_control_operator_id: String = ""

# 当前存档槽
var current_save_slot: String = "auto"

signal state_changed(field: String)
```

### 3.3 SaveService — 存档系统

```gdscript
# scripts/autoload/save_service.gd
extends Node
class_name SaveService

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 20

func save(slot_id: String) -> bool
func load(slot_id: String) -> bool
func list_slots() -> Array[Dictionary]  # [{slot_id, timestamp, playtime, chapter}]
func delete_slot(slot_id: String) -> void
func has_slot(slot_id: String) -> bool
```

存档结构（JSON）：

```json
{
  "version": "0.3",
  "timestamp": 1730000000,
  "playtime_seconds": 14400,
  "game_state": {
    "main_control_operator_id": "amiya",
    "owned_operators": ["amiya", "silverash", "mlynar"],
    "squad": {"members": [...], "main_control_index": 0},
    "shared_inventory": {...},
    "combat_item_slots": ["rhodes_medkit", "", "rhodes_shock_grenade"],
    "selected_combat_item_slot_index": 0,
    "quest_state": {...},
    "faction_reputation": {...}
  },
  "world_state": {
    "current_map_id": "dragon_outer",
    "activated_anchors": ["dragon_outer_01", "mine_01"],
    "visited_maps": ["dragon_outer", "abandoned_mine"],
    "world_flags": {"boss_defeated_001": false}
  }
}
```

**存档触发点**：
- 通信锚点激活 → 自动存档到 `auto` 槽
- 营地休息 → 自动存档到 `auto` 槽
- 玩家手动存档 → 选择槽位

### 3.4 AssetLibrary — 资源缓存中心

```gdscript
# scripts/autoload/asset_library.gd
extends Node
class_name AssetLibrary

# 数据 Resource 缓存（LRU）
func get_operator_data(operator_id: String) -> OperatorData
func get_skill_data(skill_id: String) -> SkillData
func get_class_data(class_id: String) -> ClassData
func get_equipment_data(equip_id: String) -> EquipmentData
func get_item_data(item_id: String) -> ItemData
func get_map_manifest(map_id: String) -> MapManifest
func get_enemy_data(enemy_id: String) -> Resource
func get_effect_data(effect_id: String) -> StatusEffect
func get_terrain_data(terrain_id: String) -> TerrainData
func get_summon_data(summon_id: String) -> SummonData

# Spine 资源
func get_spine_skeletons(operator_id: String) -> Dictionary  # {front, back, build}

# 异步预加载
func preload_map(map_id: String) -> void
func is_map_preloaded(map_id: String) -> bool
func acquire_map_scene(map_id: String) -> PackedScene
```

内部用 LRU 缓存，常用数据常驻，长尾数据按需加载。

### 3.5 SkillRegistry — 技能数据注册中心

```gdscript
# scripts/autoload/skill_registry.gd
extends Node
class_name SkillRegistry

# 从 res://data/skills/ 目录扫描所有 SkillData Resource
func reload() -> void

# 查询
func get_skill(skill_id: String) -> SkillData
func get_skills_for_operator(operator_id: String) -> Array[SkillData]
func get_skills_for_class(class_id: String) -> Array[SkillData]
```

### 3.6 ModeManager — 全局模式状态机

```gdscript
# scripts/autoload/mode_manager.gd
extends Node
class_name ModeManager

enum Mode {
    BOOT,             # 启动
    REALTIME,         # 实时探索
    ENVIRONMENT_TURN, # 环境回合（潜行微操）
    COMBAT_TURN,      # 战斗回合
    CAMP,             # 营地
    MENU,             # 菜单/面板打开
    CUTSCENE,         # 剧情演出
    LOADING,          # 地图加载中
}

var current_mode: int = Mode.BOOT
var previous_mode: int = Mode.BOOT  # 用于菜单关闭后恢复

func transition_to(new_mode: int, context: Dictionary = {}) -> void
# 例：transition_to(Mode.COMBAT_TURN, {"center": Vector3(...), "radius": 8.0})

func can_transition_to(new_mode: int) -> bool  # 状态合法性校验
```

**模式切换副作用**（在 `transition_to` 内统一处理）：

| 切换 | 副作用 |
|------|--------|
| → REALTIME | 启用 WASD 输入；相机切自由模式；HUD 切探索模式 |
| → ENVIRONMENT_TURN | 暂停实时移动；相机切战术俯视；HUD 显示回合条 |
| → COMBAT_TURN | 暂停实时移动；相机锁定战场范围；HUD 切战斗模式；创建 BattleState |
| → CAMP | 卸载地图场景；加载营地场景 |
| → MENU | 暂停游戏逻辑（保留模式）；打开 UI 面板 |
| → CUTSCENE | 锁定所有输入；播放演出 |
| → LOADING | 锁定所有输入；显示加载界面 |

### 3.7 InputRouter — 输入路由器

根据 `ModeManager.current_mode` 决定输入流向，避免每个节点各自监听 `_unhandled_input` 造成冲突。

```gdscript
# scripts/autoload/input_router.gd
extends Node
class_name InputRouter

# 各模式的输入处理器（注册式）
var _handlers: Dictionary = {}  # {mode: Callable}

func register_handler(mode: int, handler: Callable) -> void
func unregister_handler(mode: int) -> void

func _unhandled_input(event: InputEvent) -> void:
    var handler := _handlers.get(ModeManager.current_mode) as Callable
    if handler.is_valid():
        handler.call(event)
        # 处理器决定是否 set_input_as_handled
```

### 3.8 SettingsService — 玩家设置

```gdscript
# scripts/autoload/settings_service.gd
extends Node
class_name SettingsService

var settings: Dictionary = {
    "audio_master": 1.0,
    "audio_bgm": 0.8,
    "audio_sfx": 0.9,
    "audio_voice": 1.0,
    "graphics_quality": "high",  # low/medium/high
    "camera_sensitivity": 0.006,
    "subtitle_enabled": true,
    "language": "zh_CN",
    "keybindings": {...},
}

func load_settings() -> void
func save_settings() -> void
func get(key: String) -> Variant
func set(key: String, value: Variant) -> void
```

---

## 4. L1 · 世界控制层

负责单张地图的生命周期、地图间切换、世界级状态持久化。

### 4.1 WorldDirector — 地图生命周期管理（Autoload）

```gdscript
# scripts/autoload/world_director.gd
extends Node
class_name WorldDirector

var current_map_id: String = ""
var current_map: MapInstance = null
var current_entry_point: String = ""

# 加载地图
func load_map(map_id: String, entry_point: String = "default") -> void
    # 1. ModeManager.transition_to(LOADING)
    # 2. 若 current_map 存在 → 卸载（保留 squad 引用）
    # 3. AssetLibrary.acquire_map_scene(map_id) → 实例化
    # 4. SquadController / 队伍实例化流程把当前小队放入入口点
    # 5. ModeManager.transition_to(REALTIME)
    # 6. EventBus.map_loaded.emit(map_id, entry_point)

# 通过通路切换
func transition_via_portal(portal_id: String) -> void
    # 1. 找到 portal 对应的 dest_map + dest_entry
    # 2. 触发过渡动画
    # 3. load_map(dest_map, dest_entry)

# 通过通信锚点传送
func fast_travel_to(anchor_id: String) -> void
    # 1. 校验：必须在 REALTIME 模式 + 锚点已激活
    # 2. 找到 anchor_id 对应的 map_id
    # 3. load_map(map_id, anchor_id)

# 返回营地
func return_to_camp() -> void
func leave_camp_to_world() -> void
```

**关键设计**：
- 队伍（`SquadState`）由 `GameStateService` 持有，**不随地图销毁**
- 地图切换时，干员视觉对象通过 `VisualPool` 归还池，新地图再 acquire
- 加载用 `ResourceLoader.load_threaded_*` 异步预加载，避免卡顿

### 4.2 MapManifest — 地图元数据（Resource）

每张地图对应一个 `MapManifest` Resource，描述该地图的所有元信息。

```gdscript
# scripts/data/map_manifest.gd
extends Resource
class_name MapManifest

@export var map_id: String
@export var display_name: String
@export var scene_path: String  # res://scenes/maps/xxx.tscn
@export var platform_size_meters: Vector2  # 战场尺寸
@export var map_kind: String  # "city" / "mine" / "forest" / "lab" / "ruins" / "camp"
@export var recommended_level_range: Vector2i
@export var enemy_level_range: Vector2i

# 通路列表
@export var portals: Array[PortalDef]  # [{portal_id, dest_map, dest_entry, kind}]

# 锚点列表（初始状态）
@export var anchors: Array[AnchorDef]  # [{anchor_id, position, initial_state}]

# 营地接入点
@export var camp_spots: Array[Vector3]

# 地形移动成本。key 可为 Vector2i 或 "x,y" 格坐标，value 为体力成本；0 或负数表示阻挡
@export var terrain_move_costs: Dictionary

# 阻挡格列表。用于不可通行地形、静态障碍或开发期灰盒阻挡
@export var terrain_blocked_cells: Array[Vector2i]

# 是否读取场景内 TerrainRegion 节点，自动写入 GameGrid3D 地形成本
@export var use_editor_terrain_regions: bool

# 默认入场点
@export var entry_points: Dictionary  # {"default": Vector3, "from_mine": Vector3, ...}
```

`MapManifest` 文件存放：`res://data/maps/<map_id>.tres`

### 4.3 MapInstance — 地图根节点

```gdscript
# scripts/world/map_instance.gd
extends Node3D
class_name MapInstance

@export var map_id: String
var manifest: MapManifest

# 子节点容器（自动收集）
@onready var grid: Grid3D = $Grid
@onready var units_root: Node3D = $Units
@onready var npcs_root: Node3D = $NPCs
@onready var enemies_root: Node3D = $Enemies
@onready var anchors_root: Node3D = $Anchors
@onready var portals_root: Node3D = $Portals
@onready var props_root: Node3D = $Props
@onready var spawn_points: Node3D = $SpawnPoints

func initialize(manifest: MapManifest, entry_point: String) -> void
    # 1. 缓存 manifest
    # 2. 读取场景内 TerrainRegion，写入 GameGrid3D
    # 3. 将 manifest.terrain_move_costs / terrain_blocked_cells 作为覆盖层写入 GameGrid3D
    # 4. 恢复 anchors/portals 状态
    # 5. 注册到 WorldDirector / 发送 map_loaded

func get_entry_position(entry_id: String) -> Vector3
func get_anchor(anchor_id: String) -> AnchorNode
func get_portal(portal_id: String) -> PortalNode
```

**地图场景结构模板**（每张 `.tscn` 文件遵循）：

```
MapDragonOuter (MapInstance)
├── Grid (Grid3D)                       # 0.5m 米制格子组件
├── Units (Node3D)                     ← 玩家干员运行时挂入
├── NPCs (Node3D)
├── Enemies (Node3D)                   ← 战斗时实例化
├── Anchors (Node3D)                   ← 通信锚点
│   ├── Anchor_01 (AnchorNode)
│   └── Anchor_02 (AnchorNode)
├── Portals (Node3D)                   ← 通路入口
│   ├── Portal_To_Mine (PortalNode)
│   └── Portal_To_Forest (PortalNode)
├── TerrainRegions (Node3D)            ← 编辑器地形区域，子节点挂 TerrainRegion
├── Props (Node3D)                     ← 可交互物件
├── SpawnPoints (Node3D)               ← 敌人刷新点
├── Environment (Node3D)               ← 灯光/天空盒/雾
├── CameraRig (CameraRig)              # 模式感知相机
└── Camera3D (Camera3D)
```

### 4.4 PortalNode — 通路入口节点

```gdscript
# scripts/world/portal_node.gd
extends Node3D
class_name PortalNode

@export var portal_id: String
@export var dest_map_id: String
@export var dest_entry_id: String
@export var portal_kind: String  # "road" / "tunnel" / "bridge" / "mountain" / "crevasse" / "secret"

var interactable: bool = true

func interact(actor: Node) -> void:
    if not interactable: return
    EventBus.portal_entered.emit(portal_id, dest_map_id)
    WorldDirector.transition_via_portal(portal_id)
```

### 4.5 AnchorNode — 通信锚点节点

```gdscript
# scripts/world/anchor_node.gd
extends Node3D
class_name AnchorNode

enum State { UNDISCOVERED, DISCOVERED, ACTIVATED }

@export var anchor_id: String
@export var detect_range_meters: float = 30.0
var state: int = State.UNDISCOVERED

# 玩家进入探测范围 → UNDISCOVERED → DISCOVERED
func _process(_delta: float) -> void:
    if state == State.UNDISCOVERED:
        var main_unit := GameStateService.squad.get_main_control_unit()
        if main_unit and _distance_to(main_unit) <= detect_range_meters:
            _set_state(State.DISCOVERED)

# 玩家按 F 互动 → DISCOVERED → ACTIVATED
func interact(actor: Node) -> void:
    if state == State.DISCOVERED:
        _set_state(State.ACTIVATED)
        # 触发：恢复 HP 30% + 体力回满 + 自动存档 + 揭示周边情报
        EventBus.anchor_activated.emit(anchor_id)
        SaveService.save("auto")

func _set_state(new_state: int) -> void:
    state = new_state
    _refresh_visual()
    if new_state == State.DISCOVERED:
        EventBus.anchor_discovered.emit(anchor_id)
    # 持久化到 WorldState
    WorldState.set_anchor_state(anchor_id, new_state)
```

### 4.6 WorldState — 世界级状态（Resource）

跨地图持久化的世界状态，由 `SaveService` 序列化。

```gdscript
# scripts/world/world_state.gd
extends Resource
class_name WorldState

@export var current_map_id: String = ""
@export var current_entry_point: String = "default"

# 通信锚点状态：{anchor_id: state_int}
@export var anchor_states: Dictionary = {}

# 已访问地图
@export var visited_maps: Array[String] = []

# 世界标志位（任务/事件触发记录）
@export var world_flags: Dictionary = {}

# 通路解锁状态
@export var portal_unlocks: Dictionary = {}  # {portal_id: bool}

func set_anchor_state(anchor_id: String, state: int) -> void
func is_anchor_activated(anchor_id: String) -> bool
func visit_map(map_id: String) -> void
func set_flag(flag_id: String, value: Variant) -> void
func get_flag(flag_id: String, default: Variant = null) -> Variant
```

---

## 5. L2 · 游戏逻辑层

### 5.1 TurnManager — 回合编排

```gdscript
# scripts/game/turn/turn_manager.gd
extends Node
class_name TurnManager

# 当前回合参与者（按 initiative 排序）
var turn_order: Array[Node] = []
var current_index: int = -1
var round_number: int = 0

# 战斗上下文（仅 COMBAT_TURN 模式）
var battle_state: BattleState = null

# 启动新回合循环
func begin_battle(scope_center: Vector3, scope_radius: float,
                  allies: Array[Node], enemies: Array[Node],
                  is_ambush: bool, ambush_side: String) -> void
    # 1. 创建 BattleState
    # 2. InitiativeResolver.compute_order(allies + enemies, is_ambush, ambush_side)
    # 3. round_number = 1
    # 4. _begin_round()

func _begin_round() -> void
    # 1. 所有参与者 reset_turn()（回复体力、SP 充能）
    # 2. EventBus.round_started.emit(round_number)
    # 3. current_index = 0
    # 4. _begin_current_turn()

func _begin_current_turn() -> void
    var participant := turn_order[current_index]
    participant.begin_turn()
    EventBus.turn_started.emit(participant)

func end_current_turn() -> void
    var participant := turn_order[current_index]
    participant.end_turn()
    EventBus.turn_ended.emit(participant)
    _advance_to_next()

func delay_current() -> void
    # 将当前参与者排到队列末尾
    var p := turn_order.pop_at(current_index)
    turn_order.append(p)
    _advance_to_next()

func _advance_to_next() -> void
    current_index += 1
    if current_index >= turn_order.size():
        round_number += 1
        _begin_round()
    else:
        _begin_current_turn()

# 战斗结束
func end_battle(result: Dictionary) -> void
    EventBus.battle_ended.emit(result)
    ModeManager.transition_to(ModeManager.Mode.REALTIME)
```

### 5.2 TurnParticipant — 协议规范

回合系统采用鸭子类型协议：任何 `Node` 实现以下方法即可参与回合，不强制基类继承。

```gdscript
# 协议：任何 Node 实现以下方法即可参与回合
func is_turn_scope_participant() -> bool
func get_initiative_speed() -> float        # 速度值，用于排序
func begin_turn() -> void                    # 回合开始时调用
func end_turn() -> void                      # 回合结束时调用
func can_end_turn() -> bool                  # 是否可以手动结束（避免强制操作）
func reset_turn() -> void                    # 每回合开始时重置（体力/SP 等）
func get_participant_kind() -> int           # 0=CHARACTER 1=ENEMY 2=FIELD 3=ITEM 4=TRAP
```

**实现策略**：
- 玩家干员/敌方单位 → 继承 `Unit` 基类（自带完整实现）
- 陷阱/场地效果/可破坏物 → 轻量节点直接实现协议方法，无需继承 `Unit`
- `InitiativeResolver` 通过 `has_method()` 鸭子类型检查，不强转

### 5.3 InitiativeResolver — 速度排序与先手判定

```gdscript
# scripts/game/turn/initiative_resolver.gd
class_name InitiativeResolver

# 伏击方全员 +50 initiative
const AMBUSH_BONUS := 50.0

static func compute_order(participants: Array[Node],
                          is_ambush_round: bool,
                          ambush_side: String) -> Array[Node]:
    var scored := participants.map(func(p):
        var speed := p.get_initiative_speed() if p.has_method("get_initiative_speed") else 0.0
        var kind := p.get_participant_kind() if p.has_method("get_participant_kind") else 0
        var bonus := 0.0
        if is_ambush_round:
            if (ambush_side == "ally" and kind == 0) or \
               (ambush_side == "enemy" and kind == 1):
                bonus = AMBUSH_BONUS
        return {"p": p, "score": speed + bonus}
    )
    scored.sort_custom(func(a, b): return a.score > b.score)
    return scored.map(func(x): return x.p)
```

### 5.4 BattleState — 战斗上下文（Resource）

```gdscript
# scripts/game/turn/battle_state.gd
extends Resource
class_name BattleState

var scope_center: Vector3
var scope_radius: float
var allies: Array[Node] = []
var enemies: Array[Node] = []
var round_number: int = 0
var is_ambush_round: bool = false
var ambush_side: String = ""  # "ally" / "enemy"

# 胜负条件
var victory_condition: String = "wipe"  # "wipe" / "kill_target" / "survive_rounds" / "escort"
var victory_target_id: String = ""
var victory_survive_rounds: int = 0

func check_victory() -> String:
    # 返回 "" / "ally" / "enemy"
    if victory_condition == "wipe":
        if allies.is_empty(): return "enemy"
        if enemies.is_empty(): return "ally"
    # ... 其他条件
    return ""
```

### 5.5 BattleController — 战斗流程编排

```gdscript
# scripts/game/combat/battle_controller.gd
extends Node
class_name BattleController

var turn_manager: TurnManager

# 触发战斗（从 REALTIME 模式进入）
func start_combat(scope_center: Vector3, scope_radius: float,
                  is_ambush: bool = false, ambush_side: String = "") -> void:
    # 1. 收集范围内的 allies + enemies
    var allies := _collect_units_in_scope(scope_center, scope_radius, "ally")
    var enemies := _collect_units_in_scope(scope_center, scope_radius, "enemy")
    # 2. ModeManager.transition_to(COMBAT_TURN, {center, radius})
    # 3. turn_manager.begin_battle(...)
    # 4. EventBus.battle_started.emit(turn_manager.battle_state)

func end_combat(result: Dictionary) -> void:
    turn_manager.end_battle(result)
    # 清理战场、奖励结算、镜头回归
```

### 5.6 Unit — 单位基类

所有可参与战斗/回合的实体基类，拆分子组件实现单一职责。

```gdscript
# scripts/game/unit/unit.gd
extends CharacterBody3D
class_name Unit

# 子组件（场景中作为子节点存在）
@onready var visual: SpineCharacterVisual3D = $Visual              # HD-2D 视觉组件
@onready var stats: UnitStats = _load_stats()                       # Resource
@onready var stamina: StaminaTracker = $StaminaTracker
@onready var sp_tracker: SpTracker = $SpTracker
@onready var hp: HpTracker = $HpTracker
@onready var equipment: EquipmentContainer = $Equipment
@onready var inventory: Inventory = $Inventory
@onready var status_effects: StatusEffectContainer = $StatusEffects

# 身份
@export var unit_id: String
@export var display_name: String
@export var unit_kind: int = 0  # 0=CHARACTER 1=ENEMY 2=NPC

# 移动（米制预算）
@export var movement_budget_meters_per_turn: float = 9.0
var movement_meters_remaining: float = 0.0

signal movement_finished(unit: Node)
signal died(unit: Node)

# === TurnParticipant 协议 ===
func is_turn_scope_participant() -> bool: return true
func get_participant_kind() -> int: return unit_kind
func get_initiative_speed() -> float: return stats.speed
func begin_turn() -> void:
    stamina.refill_at_turn_start()
    sp_tracker.charge_at_turn_start()
    status_effects.tick_at_turn_start(self)
func end_turn() -> void:
    status_effects.tick_at_turn_end(self)
func can_end_turn() -> bool: return true
func reset_turn() -> void:
    movement_meters_remaining = movement_budget_meters_per_turn
    stamina.reset_for_new_round()
    sp_tracker.reset_for_new_round()

# === 移动 API ===
func can_accept_command() -> bool
func move_to_world_position(destination: Vector3, spend_turn_distance: bool) -> bool
func get_move_cost_meters(destination: Vector3) -> float
```

**子类**：
- `OperatorUnit`（玩家干员）— 装备/技能/信赖度
- `EnemyUnit`（敌方单位）— AI 节点 + 仇恨表
- `SummonedUnit`（召唤物）— 复用干员数值，记录 owner/source_skill，拒绝玩家指令，轮到自身时自动攻击附近敌人
- `NpcUnit`（中立NPC）— 对话触发器，不参与战斗

### 5.7 资源 Tracker（体力/SP/HP）

每个 Unit 的子节点，独立信号。

```gdscript
# scripts/game/resource/stamina_tracker.gd
extends Node
class_name StaminaTracker

@export var max_stamina: int = 6
@export var refill_per_turn: int = 4

var current: int = 0

signal changed(current: int, maximum: int)
signal depleted()

func spend(amount: int) -> bool:
    if current < amount: return false
    current -= amount
    changed.emit(current, max_stamina)
    if current == 0: depleted.emit()
    return true

func refill_at_turn_start() -> void:
    current = min(current + refill_per_turn, max_stamina)
    changed.emit(current, max_stamina)

func reset_for_new_round() -> void:
    current = 0
    changed.emit(current, max_stamina)
```

```gdscript
# scripts/game/resource/sp_tracker.gd
extends Node
class_name SpTracker

# 每技能独立 SP
var skill_sp: Dictionary = {}  # {skill_id: {"current": int, "max": int, "initial": int}}
var charge_type: Dictionary = {}  # {skill_id: ChargeType}

enum ChargeType { AUTO, ATTACK, HIT, HEAL, KILL }

signal changed(skill_id: String, current: int, maximum: int)
signal skill_ready(skill_id: String)  # SP 充满

func register_skill(skill_id: String, data: SkillData) -> void
func spend(skill_id: String, amount: int) -> bool
func charge(skill_id: String, amount: int) -> void
func charge_at_turn_start() -> void  # 自动充能
func charge_by_event(event_type: int, amount: int) -> void  # 攻击/受击/治疗/击杀
```

```gdscript
# scripts/game/resource/hp_tracker.gd
extends Node
class_name HpTracker

@export var max_hp: int = 1880  # 照搬明日方舟
var current: int = 1880

signal changed(current: int, maximum: int)
signal depleted()  # HP 归零

func take_damage(amount: int) -> void
func heal(amount: int) -> void
func revive(to_hp: int) -> void
```

### 5.8 Action — 行动系统

```gdscript
# scripts/game/action/action.gd
extends Resource
class_name Action

@export var action_id: String
@export var display_name: String
@export var cost_stamina: int = 0
@export var cost_sp: int = 0
@export var action_kind: String  # "move" / "attack" / "skill" / "item" / "interact" / "defend" / "wait"

# 校验：能否执行
func can_execute(actor: Node, target: Variant) -> bool:
    var u := actor as Unit
    if u == null: return false
    if u.stamina.current < cost_stamina: return false
    return true

# 执行（子类重写）
func execute(actor: Node, target: Variant) -> void:
    pass
```

**子类示例**：

```gdscript
# scripts/game/action/actions/attack_action.gd
extends Action
class_name AttackAction

func execute(actor: Node, target: Variant) -> void:
    super.execute(actor, target)
    var attacker := actor as Unit
    var target_unit := target as Unit
    if attacker == null or target_unit == null: return
    # 1. 扣体力
    attacker.stamina.spend(cost_stamina)
    # 2. 充能 SP（攻击充能型）
    attacker.sp_tracker.charge_by_event(SpTracker.ChargeType.ATTACK, 2)
    # 3. 计算伤害（明日方舟公式）
    var damage := DamageCalculator.calc(attacker.stats, target_unit.stats,
                                         attacker.equipment, attacker.status_effects)
    # 4. 应用伤害
    target_unit.hp.take_damage(damage)
    # 5. 触发动画/特效
    attacker.visual.play_attack()
    EffectPool.spawn_hit_effect(target_unit.global_position)
    # 6. 事件
    EventBus.stat_changed.emit(target_unit, "hp", 0, 0)  # 简化
```

### 5.9 ActionValidator — 行动合法性

```gdscript
# scripts/game/action/action_validator.gd
class_name ActionValidator

static func validate(action: Action, actor: Node, target: Variant) -> String:
    # 返回 "" 表示合法，否则返回错误码
    if not action.can_execute(actor, target):
        return "insufficient_resources"
    if not _check_range(actor, target, action):
        return "out_of_range"
    if not _check_line_of_sight(actor, target):
        return "no_los"
    if not _check_cooldown(actor, action):
        return "on_cooldown"
    return ""

static func _check_range(actor: Node, target: Variant, action: Action) -> bool
static func _check_line_of_sight(actor: Node, target: Variant) -> bool
static func _check_cooldown(actor: Node, action: Action) -> bool
```

### 5.9.1 ItemData 与道具目标

```gdscript
# scripts/data/item_data.gd
extends Resource
class_name ItemData

@export var item_id: String
@export var display_name: String
@export var description: String
@export var icon_path: String
@export var rarity: int
@export var category: String  # healing/support/offense/utility
@export var stackable: bool
@export var max_stack: int
@export var usable_in_combat: bool
@export var usable_in_world: bool
@export var target_type: String  # self/ally/enemy/any
@export var cooldown_rounds: int

@export var heal_hp: int
@export var revive_hp: int
@export var heal_stamina: int
@export var charge_sp_amount: int
@export var damage_amount: int
@export var damage_type: String  # physical/magical/true
@export var aoe_radius_meters: float
@export var apply_status_id: String
@export var status_duration: int
```

`ItemData.rarity` 使用 1-5 档，供正式道具栏排序、筛选、掉落品质和 HUD 标签复用。`ItemData.category` 使用 `healing` / `support` / `offense` / `utility` 四个稳定 ID，供正式道具栏筛选、图标映射和战斗复盘分类复用。`ItemData.target_type` 是道具目标规则的数据源。`self` 只允许当前行动者，`ally` 允许友方干员系单位，`enemy` 允许敌方单位，`any` 允许任意单位。Bootstrap 在解析显式选中目标或默认目标时先检查 `target_type`；`enemy` 道具未选中目标时回退最近存活敌人；`ItemAction.can_execute()` 也会再次校验，避免绕过 UI 时出现非法目标。`ItemData.cooldown_rounds` 声明战斗内冷却轮数，`GameStateService.item_cooldowns` 只作为单场战斗运行时状态，不写入存档，并由 Bootstrap 在 battle_started / battle_ended 清空、在 round_started 递减。攻击类道具通过 `damage_amount`、`damage_type` 和 `aoe_radius_meters` 复用 `DamageCalculator`、`Unit.take_damage()` 与 `Unit.apply_status()` 链路，可对目标同侧单位收集范围目标并记录伤害、命中数量、状态施加数量和击杀数。

当前 `rhodes_medkit` 标记为 `rarity = 2`、`category = healing`、`target_type = ally` 且 `cooldown_rounds = 1`，可治疗或复苏友方干员系单位；`rhodes_sp_injector` 标记为 `rarity = 3`、`category = support`、`target_type = ally` 且 `cooldown_rounds = 2`，可为友方干员每个已注册技能回复 4 点 SP；`rhodes_shock_grenade` 标记为 `rarity = 3`、`category = offense`、`target_type = enemy` 且 `cooldown_rounds = 2`，可造成 1.5 米范围物理伤害并施加 `shock_stagger`；`rhodes_tactical_ration` 标记为 `rarity = 1`、`category = utility`、`target_type = ally` 且 `cooldown_rounds = 1`，可恢复 3 点体力。`GameStateService.combat_item_slots` 保存固定 3 个小队战斗道具携带槽，空字符串代表空槽；`selected_combat_item_slot_index` 保存当前选中槽位，两者写入 `GameStateService.serialize()`。`set_combat_item_slots()` 会补齐固定槽位并保留空字符串，`set_combat_item_slot()` 允许 Bootstrap 按固定槽位替换或清空装备道具，`cycle_combat_item_slot()` 在非空槽之间切换。Bootstrap 只在槽位数组为空时注入开发期默认三件套，并把额外开发期道具放入 `shared_inventory`；`Q` 使用当前道具，`R` 跳过空槽切换当前道具，`I` 打开/关闭 `ItemLoadoutPanel`。HUD 三槽道具栏会显示每个装备槽或空槽的位置、道具名、数量、选中标记、稀有度、分类、目标类型和 CD 标签，点击非空可用槽位会通过 `EventBus.request_use_action` 发出对应 `item_id`；ItemLoadoutPanel 从共享库存收集 `usable_in_combat` 道具，点击槽位时向 Bootstrap 请求在未被其它槽占用的可用道具和空槽之间循环。后续正式道具栏复用同一状态源。

### 5.10 SkillData 与技能系统

```gdscript
# scripts/data/skill_data.gd
extends Resource
class_name SkillData

@export var skill_id: String
@export var display_name: String
@export var description: String
@export var operator_id: String  # 所属干员
@export var slot: int  # 1/2/3
@export var unlock_condition: String  # "initial" / "elite_1" / "elite_2"

# 资源消耗
@export var cost_stamina: int
@export var cost_sp: int
@export var sp_max: int
@export var sp_initial: int
@export var charge_type: int  # SpTracker.ChargeType

# 效果链（按顺序执行）
@export var damage_multiplier: float
@export var heal_multiplier: float
@export var self_buff_duration: int
@export var self_buff_modifiers: Dictionary
@export var target_status_effect: StatusEffect
@export var summon_data: SummonData
@export var summon_operator_id: String
@export var summon_display_name: String
@export var summon_duration_rounds: int

# 冷却
@export var cooldown_turns: int
```

技能 Resource 存放：`res://data/skills/<operator_id>/<skill_id>.tres`
当前竖切中，`summon_data` 优先提供正式召唤配置，旧 `summon_*` 字段保留为兼容兜底。`SkillAction` 将召唤配置转换为 `EventBus.summon_requested`，Bootstrap 负责生成 `SummonedUnit`、注册网格占用、加入友方回合参与者，并在持续轮数结束、被击倒、被新召唤替换或战斗结束后退场。`SummonedUnit` 暂时直接复用 `OperatorData` 数值，但通过 `is_player_controllable() == false` 与普通小队成员分离；同时缓存 `spawn_vfx_id` / `expire_vfx_id` / `ui_hint`，供 Bootstrap、HUD 和表现层使用。

### 5.10.1 SummonData — 召唤物配置

```gdscript
# scripts/data/summon_data.gd
extends Resource
class_name SummonData

@export var summon_id: String
@export var display_name: String
@export var operator_id: String
@export var duration_rounds: int
@export var spawn_rule: String  # target_near/caster_near
@export var max_per_owner: int
@export var limit_policy: String  # replace_oldest/fail

@export var ai_behavior: String
@export var attack_damage_type: String  # physical/magical/true
@export var attack_damage_multiplier: float
@export var attack_range_meters: float
@export var attack_stamina_cost: int
@export var heal_amount: int
@export var heal_multiplier: float
@export var heal_range_meters: float
@export var heal_stamina_cost: int
@export var threat_on_spawn: int
@export var threat_range_meters: float
@export var trap_trigger_radius_meters: float
@export var trap_damage: int
@export var trap_damage_multiplier: float
@export var trap_damage_type: String  # physical/magical/true
@export var trap_status_effect_id: String
@export var trap_arm_delay_rounds: int
@export var trap_max_targets: int
@export var trap_trigger_archetypes: Array[String]
@export var trap_trigger_factions: Array[String]
@export var trap_required_target_status_effect_ids: Array[String]
@export var trap_blocked_target_status_effect_ids: Array[String]
@export var trap_min_target_hp_ratio: float
@export var trap_max_target_hp_ratio: float
@export var trap_chain_radius_meters: float
@export var trap_chain_max_triggers: int
@export var trap_terrain_damage_multipliers: Dictionary
@export var trap_terrain_status_effect_ids: Dictionary
@export var trap_linger_terrain_id: String
@export var trap_linger_terrain_overrides: Dictionary
@export var trap_linger_duration_rounds: int
@export var trap_linger_spread_source_terrain_ids: Array[String]
@export var trap_linger_spread_terrain_id: String
@export var trap_linger_spread_terrain_overrides: Dictionary
@export var trap_linger_spread_duration_rounds: int
@export var trap_linger_spread_radius_cells: int
@export var trap_linger_spread_max_cells: int

@export var spawn_vfx_id: String
@export var expire_vfx_id: String
@export var hud_icon_text: String
@export var ui_hint: String
```

召唤 Resource 存放：`res://data/summons/<summon_id>.tres`。当前阿米娅技能 3 使用 `data/summons/amiya_tactical_echo.tres`，该资源指向 `data/operators/amiya_tactical_echo.tres` 作为运行时数值模板；医疗干员技能 1 使用 `data/summons/rhodes_healing_drone.tres`，在施法者附近生成 `data/operators/rhodes_healing_drone.tres`，并以 `heal_lowest_ally` 行动包自动治疗友方；重装干员技能 1 使用 `data/summons/rhodes_guard_barrier.tres`，在目标附近生成 `data/operators/rhodes_guard_barrier.tres`，并通过 `threat_on_spawn` 吸引附近敌人；近卫干员技能 1 使用 `data/summons/rhodes_shock_mine.tres`，在目标附近生成 `data/operators/rhodes_shock_mine.tres`，并以 `trap_nearest_enemy` 行动包在下轮启用后筛选 `infected` 阵营、`grunt` / `caster` archetype、未带 `shock_stagger` 且 HP 比例不低于 0.2 的敌人，最多命中 2 名进入 `trap_trigger_radius_meters` 的感染者，造成陷阱伤害、施加 `shock_stagger` 状态、写入 `summon_trap` 复盘事件并通过 `summon_retire_requested` 请求退场。`EnemyData.faction_id` 提供阵营 ID，`SummonData.trap_trigger_factions` 为空时不限制阵营；非空时会与 `trap_trigger_archetypes` 一起作为 AND 过滤条件。`trap_required_target_status_effect_ids` 与 `trap_blocked_target_status_effect_ids` 通过 `Unit.has_status()` 过滤目标状态；`trap_min_target_hp_ratio` 与 `trap_max_target_hp_ratio` 通过 `HpTracker.get_ratio()` 过滤目标血量比例。当前震荡地雷使用 blocked 状态列表避开已带 `shock_stagger` 的目标，并用 `trap_min_target_hp_ratio = 0.2` 避免被残血单位骗出陷阱。震荡地雷触发后还会按 `trap_chain_radius_meters` 寻找附近已启用且能命中目标的陷阱，并按 `trap_chain_max_triggers` 上限牵引连锁触发；连锁触发不重复结束当前回合，但会写入 `summon_trap` 复盘并以 `chain_depth` 标注层级。陷阱还会通过 `GameGrid3D.get_world_terrain_id()` 读取所在格地形：`trap_terrain_damage_multipliers` 可按 terrain_id 调整基础伤害，`trap_terrain_status_effect_ids` 可按 terrain_id 追加状态效果；当前 `originium_pollution` 会让震荡地雷伤害 ×1.35 并追加 `amiya_arts_burn`。`trap_linger_terrain_id` 则在陷阱触发后由 `SummonedUnit._apply_trap_linger_terrain()` 读取对应 `TerrainData`，把当前格的 terrain_id、移动成本/阻挡和 hazard 写回 `GameGrid3D`；`trap_linger_terrain_overrides` 可按触发时的 source terrain_id 覆盖默认残留地形，实现污染区、燃烧区等地形转化规则；`trap_linger_spread_source_terrain_ids`、`trap_linger_spread_radius_cells` 与 `trap_linger_spread_max_cells` 控制残留地形是否从指定源地形扩散、按曼哈顿距离扩散多少格，以及最多写入多少个邻格；当 `trap_linger_duration_rounds > 0` 时，`GameGrid3D.set_cell_temporary_terrain()` 会先保存原格 terrain_id、移动成本/阻挡和 hazard 快照，再写入临时地形，并由 Bootstrap 在 `round_started` 调用 `tick_temporary_terrain_rounds()` 到期恢复；战斗结束时 Bootstrap 会调用 `clear_temporary_terrain()` 恢复所有未到期临时地形。当前 `rhodes_shock_mine` 默认留下持续 2 轮的 `data/terrain/shock_residue.tres` 震荡余波；若触发格为 `originium_pollution`，则按覆盖表改为 `data/terrain/originium_shock_residue.tres` 源石震荡余波，并向 1 格范围内最多 4 个可通行邻格扩散，使后续入格单位受到 60 点危险伤害并触发 `shock_stagger`；`BattleLog` 的 `summon_trap` 描述会显示实际残留 terrain_id、持续轮数和扩散格数。Bootstrap 在召唤生成、普通退场和陷阱触发时发出 `summon_visual_requested`，`SkillEffectPresenter` 以开发期地面圈和浮字消费 `spawn_vfx_id` / `expire_vfx_id` / `ui_hint`，并在陷阱召唤生成时读取运行时 `trap_trigger_radius_meters` / `trap_chain_radius_meters` 绘制触发范围与连锁范围预览；HUD 在召唤物状态行展示 `ui_hint` 和未启用倒计时。

> v1.47 扩散衰减补充：`trap_linger_spread_terrain_overrides` 会优先按触发格 `source_terrain_id` 选择扩散残留 TerrainData；未命中覆盖表时使用 `trap_linger_spread_terrain_id`，仍为空则回退到中心格实际残留地形。`trap_linger_spread_duration_rounds = -1` 表示沿用中心残留持续时间，非负值则作为扩散格独立持续时间。当前 `rhodes_shock_mine` 在 `originium_pollution` 上触发时，中心格为持续 2 轮、入格 60 伤害的 `originium_shock_residue`；邻格扩散为持续 1 轮、入格 30 伤害的 `originium_shock_residue_faded`，`BattleLog` 会同时记录扩散 terrain_id、扩散格数和扩散持续轮数。

> v1.48 碎石地形反应补充：`rhodes_shock_mine` 的 `trap_terrain_damage_multipliers` 增加 `rubble_slow = 0.75`，让碎石地形吸收部分爆炸冲击；`trap_linger_terrain_overrides` 增加 `rubble_slow -> rubble_shock_residue`，让残留地形继承碎石缓行的 `move_cost = 2`，并继续通过 `hazard_status_effect_id = shock_stagger` 触发震荡。该切片验证同一陷阱可通过数据同时表达地形强化、地形削弱与残留属性继承。

> v1.49 HUD 图标补充：`SummonData.hud_icon_text` 进入 payload 后由 `SummonedUnit` 缓存，`BattleHud._summon_status_text()` 在召唤物状态标签中显示该短文本图标。当前 `amiya_tactical_echo` / `rhodes_healing_drone` / `rhodes_guard_barrier` / `rhodes_shock_mine` 分别使用「影 / 医 / 盾 / 雷」，作为正式图标资源接入前的可读性占位。

### 5.11 StatusEffect — 状态效果

```gdscript
# scripts/data/status_effect.gd
extends Resource
class_name StatusEffect

@export var effect_id: String
@export var display_name: String
@export var kind: String  # "buff" / "debuff" / "neutral"
@export var max_stacks: int = 1
@export var duration_turns: int = 3
@export var tick_timing: String  # "turn_start" / "turn_end" / "round_start" / "round_end"

# 效果（属性修改器）
@export var modifiers: Dictionary  # {"atk_pct": 0.15, "def_flat": 50, ...}
```

```gdscript
# scripts/game/status/status_effect_container.gd
extends Node
class_name StatusEffectContainer

var active: Array[StatusEffectInstance] = []

func apply(effect: StatusEffect, source: Node, target: Node) -> void
func remove(effect_id: String) -> void
func has(effect_id: String) -> bool
func get_modifier(modifier_name: String) -> float  # 汇总所有同类型 modifier
func tick_at_turn_start(unit: Node) -> void
func tick_at_turn_end(unit: Node) -> void
```

---

## 6. L3 · 表现层

### 6.1 CameraRig

模式感知的轨道相机，根据 `ModeManager.current_mode` 自动切换视角与跟随策略。

```gdscript
# scripts/camera/camera_rig.gd
extends Node3D
class_name CameraRig

@export var follow_target: Node3D  # 通常为主控角色 Unit
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
    EventBus.mode_changed.connect(_on_mode_changed)
    EventBus.unit_selected.connect(_on_unit_selected)

func _on_mode_changed(_from: int, to: int, scope_center: Vector3, scope_radius: float) -> void:
    match to:
        ModeManager.Mode.REALTIME:
            _switch_to_follow_mode()       # 跟随主控角色
        ModeManager.Mode.COMBAT_TURN:
            _switch_to_tactical_mode(scope_center, scope_radius)  # 战场俯视
        ModeManager.Mode.CAMP:
            _switch_to_camp_mode()         # 营地俯瞰
        ModeManager.Mode.MENU:
            pass  # 保持当前视角，不切换

func _on_unit_selected(unit: Node) -> void:
    if ModeManager.current_mode in [ModeManager.Mode.REALTIME, ModeManager.Mode.ENVIRONMENT_TURN]:
        follow_target = unit

# 视角模式（子方法实现各自过渡动画）
func _switch_to_follow_mode() -> void         # 第三人称跟随
func _switch_to_tactical_mode(center: Vector3, radius: float) -> void  # 俯视锁定战场范围
func _switch_to_camp_mode() -> void           # 营地固定俯瞰
```

### 6.2 SpineCharacterVisual3D

HD-2D 角色视觉组件，负责将 Spine 骨骼动画渲染到 3D 场景中。

**核心职责**：
- SubViewport → Sprite3D 的 billboard 渲染（保持像素级清晰）
- Front/Back/Build 三向精灵切换（朝向自动跟随相机）
- 移动动画与待机动画切换
- 镜头跟随旋转

**实现接口**：

```gdscript
# scripts/visual/spine_character_visual_3d.gd
extends Node3D
class_name SpineCharacterVisual3D

# 朝向控制
func set_world_direction(direction: Vector3) -> void
func set_moving(is_moving: bool) -> void

# 战斗动画（按需扩展）
func play_attack() -> void
func play_skill(skill_id: String) -> void
func play_hit() -> void
func play_die() -> void

# 资源注入（避免场景硬编码）
func load_skeletons(operator_id: String) -> void
    var skeletons := AssetLibrary.get_spine_skeletons(operator_id)
    _front_sprite.skeleton = skeletons.front
    _back_sprite.skeleton = skeletons.back
    _build_sprite.skeleton = skeletons.build
```

**关键规则**：
- skeleton 资源通过 `AssetLibrary.get_spine_skeletons()` 注入，不在场景里硬编码
- 一个视觉实例只服务一个 operator_id
- 视觉实例本身通过 `VisualPool` 管理（见 §7.2），不随地图销毁

### 6.3 UI 层

UI 节点全部为 `CanvasLayer` 子节点，由专门管理器加载/卸载。

```gdscript
# scripts/ui/ui_manager.gd
extends Node
class_name UIManager

var _loaded_panels: Dictionary = {}  # {panel_name: Control}

func open_panel(panel_name: String, context: Dictionary = {}) -> void
func close_panel(panel_name: String) -> void
func close_all_panels() -> void
func is_panel_open(panel_name: String) -> bool

# 内部：监听 EventBus.request_open_panel / request_close_panel
```

**UI 面板清单**（对应 GDD §10.4 + 设计稿）：

| 面板 | 触发 | 场景路径 |
|------|------|----------|
| Battle HUD | COMBAT_TURN 模式 | `res://scenes/ui/hud_battle.tscn` |
| Battle Result | `EventBus.battle_ended` | `res://scenes/ui/panel_battle_result.tscn` |
| Explore HUD | REALTIME 模式 | `res://scenes/ui/hud_explore.tscn` |
| Inventory | 快捷键 I | `res://scenes/ui/panel_inventory.tscn` |
| Skills | 快捷键 K | `res://scenes/ui/panel_skills.tscn` |
| Stats | 快捷键 C | `res://scenes/ui/panel_stats.tscn` |
| Map | 快捷键 M | `res://scenes/ui/panel_map.tscn` |
| Quest Log | 快捷键 J | `res://scenes/ui/panel_quest.tscn` |
| Camp Menu | 营地内交互 | `res://scenes/ui/panel_camp.tscn` |

**UI 不直接修改游戏状态**：
- UI 通过 `EventBus.request_*.emit()` 发请求
- L2 监听并执行
- L2 完成后通过 `EventBus.*.emit()` 反馈
- UI 监听反馈信号更新显示

**开发期瞄准预览**：`Bootstrap._setup_hud()` 将 `TargetingController` 绑定给 `BattleHud`。`BattleHud._status_panel_text()` 除状态效果外，还会读取当前玩家干员、锁定敌人或默认最近敌人，显示目标来源、距离，以及 1-3 号技能的单体/范围命中数和距离可用性。该预览只读，不改变 `SkillAction.can_execute()` 与实际目标解析规则。

### 6.4 特效与音频

- `EffectPool`（Autoload 子节点）— 粒子/命中/伤害数字对象池
- `AudioManager`（Autoload）— BGM/SFX/Voice 通道管理，跟随模式切换

---

## 7. 资源复用体系

### 7.1 数据 Resource 模式

所有静态数据用 Resource 类，运行时通过 `AssetLibrary` 访问。

| Resource | 文件目录 | 加载时机 |
|----------|----------|----------|
| `OperatorData` | `res://data/operators/<id>.tres` | 启动时全量加载 |
| `SkillData` | `res://data/skills/<op>/<skill>.tres` | 启动时全量加载 |
| `ClassData` | `res://data/classes/<class>.tres` | 启动时全量加载 |
| `EquipmentData` | `res://data/equipment/<id>.tres` | 按需 |
| `ItemData` | `res://data/items/<id>.tres` | 按需 |
| `MapManifest` | `res://data/maps/<id>.tres` | 启动时全量加载 |
| `StatusEffect` | `res://data/effects/<id>.tres` | 按需 |

**关键规则**：
- 数据 Resource 在运行时**不可变**（只读）
- 若需修改（如装备强化后的数值），用 `duplicate(true)` 拷贝再改
- 任何持有数据 Resource 引用的代码不得直接修改其字段

### 7.2 对象池

#### VisualPool — Spine 角色视觉对象池

```gdscript
# scripts/visual/visual_pool.gd
extends Node
class_name VisualPool

# 池：{operator_id: Array[SpineCharacterVisual3D]}
var _pool: Dictionary = {}
var _max_per_operator: int = 8  # 同一干员最多缓存 8 个视觉实例

func acquire(operator_id: String) -> SpineCharacterVisual3D:
    # 1. 池中有空闲 → 取出并重置状态
    # 2. 池空 → 实例化新视觉，挂载 AssetLibrary 提供的 skeleton
    # 3. 返回

func release(visual: SpineCharacterVisual3D) -> void:
    # 1. 隐藏
    # 2. 停止动画
    # 3. 归还到对应 operator_id 的池
```

**使用场景**：地图切换时，干员视觉不销毁，归还池；新地图加载后重新 acquire。

#### EffectPool — 特效对象池

```gdscript
# scripts/visual/effect_pool.gd
extends Node
class_name EffectPool

func spawn_hit_effect(position: Vector3) -> void
func spawn_damage_number(position: Vector3, amount: int, kind: String) -> void
func spawn_skill_vfx(position: Vector3, skill_id: String) -> void
```

#### ProjectilePool — 投射物池

```gdscript
# scripts/visual/projectile_pool.gd
extends Node
class_name ProjectilePool

func spawn(projectile_id: String, from: Vector3, to: Vector3, on_hit: Callable) -> void
```

### 7.3 场景异步预加载

```gdscript
# AssetLibrary 内部实现
func preload_map(map_id: String) -> void:
    if _preloading_maps.has(map_id): return
    var manifest := get_map_manifest(map_id)
    ResourceLoader.load_threaded_request(manifest.scene_path)
    _preloading_maps[map_id] = true

func acquire_map_scene(map_id: String) -> PackedScene:
    var manifest := get_map_manifest(map_id)
    if ResourceLoader.load_threaded_has(manifest.scene_path):
        return ResourceLoader.load_threaded_get(manifest.scene_path)
    else:
        # 同步加载（兜底）
        return load(manifest.scene_path)
```

**预加载策略**：
- 进入新地图时，预加载该地图所有通路连接的相邻地图
- 玩家接近通路入口时，提升预加载优先级
- 营地场景在主菜单加载时预加载

### 7.4 Spine 资源管理

```gdscript
# AssetLibrary 内部
var _spine_cache: Dictionary = {}  # {operator_id: {front, back, build}}

func get_spine_skeletons(operator_id: String) -> Dictionary:
    if _spine_cache.has(operator_id):
        return _spine_cache[operator_id]
    var path_base := "res://assets/char_spine/%s/" % operator_id
    var result := {
        "front": load(path_base + "front.tres") as SpineSkeletonDataResource,
        "back": load(path_base + "back.tres") as SpineSkeletonDataResource,
        "build": load(path_base + "build.tres") as SpineSkeletonDataResource,
    }
    _spine_cache[operator_id] = result
    return result
```

**关键规则**：skeleton 资源**必须**通过 `AssetLibrary` 运行时注入，禁止在场景文件里硬编码 Spine 引用，避免每个干员场景重复挂载、便于统一缓存与热更新。

---

## 8. 目录结构与命名

### 8.1 完整目录树

```
ark-night-emblem/
├── project.godot
├── GDD.md
├── ARCHITECTURE.md                  # 本文档
├── AGENTS.md
│
├── assets/                          # 美术资源（保持现有）
│   └── char_spine/
│       └── 002_amiya/
│
├── bin/                             # Spine 扩展二进制（保持现有）
│
├── data/                            # 数据 Resource 文件
│   ├── operators/
│   │   ├── 002_amiya.tres
│   │   ├── 103_medic_dev.tres
│   │   ├── 106_guard_dev.tres
│   │   ├── 150_defender_dev.tres
│   │   ├── amiya_tactical_echo.tres
│   │   ├── rhodes_healing_drone.tres
│   │   ├── rhodes_guard_barrier.tres
│   │   └── rhodes_shock_mine.tres
│   ├── skills/
│   │   ├── 002_amiya/
│   │   │   ├── amiya_skill_1.tres
│   │   │   ├── amiya_skill_2.tres
│   │   │   └── amiya_skill_3.tres
│   │   ├── 103_medic_dev/
│   │   │   └── medic_skill_1.tres
│   │   ├── 106_guard_dev/
│   │   │   └── guard_skill_1.tres
│   │   └── 150_defender_dev/
│   │       └── defender_skill_1.tres
│   ├── classes/
│   │   ├── caster.tres
│   │   ├── medic.tres
│   │   ├── guard.tres
│   │   ├── defender.tres
│   │   └── specialist.tres
│   ├── equipment/
│   ├── items/
│   ├── effects/
│   │   └── shock_stagger.tres
│   ├── terrain/
│   │   ├── cover_blocked.tres
│   │   ├── originium_pollution.tres
│   │   ├── originium_shock_residue.tres
│   │   ├── originium_shock_residue_faded.tres
│   │   ├── rubble_shock_residue.tres
│   │   ├── rubble_slow.tres
│   │   └── shock_residue.tres
│   ├── summons/
│   │   ├── amiya_tactical_echo.tres
│   │   ├── rhodes_healing_drone.tres
│   │   ├── rhodes_guard_barrier.tres
│   │   └── rhodes_shock_mine.tres
│   └── maps/
│       ├── dragon_outer.tres
│       └── abandoned_mine.tres
│
├── scenes/
│   ├── maps/                        # 地图场景
│   │   ├── dragon_outer.tscn
│   │   ├── abandoned_mine.tscn
│   │   └── ...
│   ├── camp/
│   │   └── camp_scene.tscn
│   ├── character/
│   │   ├── operator_unit.tscn       # OperatorUnit 基础场景
│   │   └── enemy_unit.tscn
│   ├── ui/
│   │   ├── hud_battle.tscn
│   │   ├── hud_explore.tscn
│   │   ├── panel_inventory.tscn
│   │   ├── panel_skills.tscn
│   │   ├── panel_stats.tscn
│   │   ├── panel_map.tscn
│   │   └── panel_quest.tscn
│   └── test/
│       ├── combat_sandbox.tscn     # 战斗机制沙盒
│       └── world_test.tscn         # 世界流测试
│
├── scripts/
│   ├── autoload/                    # L0 全局服务
│   │   ├── event_bus.gd
│   │   ├── game_state_service.gd
│   │   ├── world_director.gd
│   │   ├── mode_manager.gd
│   │   ├── save_service.gd
│   │   ├── asset_library.gd
│   │   ├── skill_registry.gd
│   │   ├── input_router.gd
│   │   └── settings_service.gd
│   │
│   ├── world/                       # L1 世界层
│   │   ├── map_instance.gd
│   │   ├── terrain_region.gd
│   │   ├── portal_node.gd
│   │   ├── anchor_node.gd
│   │   └── world_state.gd
│   │
│   ├── game/                        # L2 游戏逻辑
│   │   ├── squad/
│   │   │   └── squad_controller.gd  # 当前地图小队成员、主控切换与跟随队形
│   │   ├── input/
│   │   │   └── bootstrap_input_controller.gd  # 开发期模式输入处理器，注册到 InputRouter
│   │   ├── selection/
│   │   │   ├── path_preview_controller.gd     # 鼠标投射、成本路径和路径预览渲染
│   │   │   └── targeting_controller.gd        # 显式选格/选敌和目标标记
│   │   ├── turn/
│   │   │   ├── turn_manager.gd
│   │   │   ├── initiative_resolver.gd
│   │   │   ├── battle_state.gd
│   │   │   └── battle_log.gd
│   │   ├── combat/
│   │   │   └── battle_controller.gd
│   │   ├── unit/
│   │   │   ├── unit.gd              # 单位基类（CharacterBody3D）
│   │   │   ├── operator_unit.gd
│   │   │   ├── enemy_unit.gd
│   │   │   ├── summoned_unit.gd
│   │   │   └── npc_unit.gd
│   │   ├── action/
│   │   │   ├── action.gd            # Resource 基类
│   │   │   ├── action_validator.gd
│   │   │   └── actions/
│   │   │       ├── move_action.gd
│   │   │       ├── attack_action.gd
│   │   │       ├── skill_action.gd
│   │   │       ├── item_action.gd
│   │   │       ├── defend_action.gd
│   │   │       └── wait_action.gd
│   │   ├── resource/
│   │   │   ├── stamina_tracker.gd
│   │   │   ├── sp_tracker.gd
│   │   │   └── hp_tracker.gd
│   │   └── status/
│   │       ├── status_effect_container.gd
│   │       └── status_effect_instance.gd
│   │
│   ├── data/                        # 数据 Resource 类
│   │   ├── operator_data.gd
│   │   ├── class_data.gd
│   │   ├── skill_data.gd
│   │   ├── equipment_data.gd
│   │   ├── item_data.gd
│   │   ├── summon_data.gd
│   │   ├── map_manifest.gd
│   │   ├── status_effect.gd
│   │   ├── portal_def.gd
│   │   └── anchor_def.gd
│   │
│   ├── visual/                      # L3 表现层
│   │   ├── spine_character_visual_3d.gd  # HD-2D 视觉组件
│   │   ├── skill_effect_presenter.gd     # 开发期技能动画/命中/AOE 表现
│   │   ├── visual_pool.gd
│   │   ├── effect_pool.gd
│   │   └── projectile_pool.gd
│   │
│   ├── camera/
│   │   └── camera_rig.gd            # 模式感知相机
│   │
│   ├── ui/
│   │   ├── ui_manager.gd
│   │   ├── hud_battle.gd
│   │   ├── hud_explore.gd
│   │   ├── panel_inventory.gd
│   │   ├── panel_skills.gd
│   │   ├── panel_stats.gd
│   │   └── ...
│   │
│   └── grid/
│       └── grid_3d.gd              # 0.5m 米制格子组件（MapInstance 子节点）
│
└── tests/                           # 自动化测试
```

### 8.2 命名规范

沿用 AGENTS.md 既有约定：

| 类型 | 规范 | 示例 |
|------|------|------|
| 文件 | snake_case | `turn_manager.gd` |
| 类名 | PascalCase + `class_name` | `TurnManager` |
| 变量 | snake_case | `current_index` |
| 函数 | snake_case | `begin_turn()` |
| 信号 | snake_case 过去式/名词 | `round_started`, `anchor_activated` |
| 常量 | SCREAMING_SNAKE_CASE | `MAX_SLOTS` |
| 枚举值 | SCREAMING_SNAKE_CASE | `Mode.COMBAT_TURN` |
| Resource 文件 | snake_case + `.tres` | `amiya.tres` |
| 场景文件 | snake_case + `.tscn` | `dragon_outer.tscn` |

---

## 9. 信号流与依赖规则

### 9.1 跨层通信示意

```
[L3 UI] --request_*.emit()--> [EventBus] --connect--> [L2 Logic]
                                                     │
                                                     ↓ 执行
[L3 UI] <--*.emit()-------- [EventBus] <--connect-- [L2 Logic]
```

### 9.2 典型信号流：玩家点击"使用技能"

```
1. 玩家点击 UI 技能按钮
2. UI 节点: EventBus.request_use_action.emit("skill_amiya_2", target_unit)
3. SkillAction.execute(actor, target):
   - 校验 (ActionValidator)
   - 扣体力 → StaminaTracker.spend() → stamina.changed.emit()
   - 扣 SP → SpTracker.spend() → sp.changed.emit()
   - 应用效果 → StatusEffectContainer.apply()
   - 触发动画 → Unit.visual.play_skill()
   - 触发特效 → EffectPool.spawn_skill_vfx()
4. Unit.died.emit() (若目标死亡) → EventBus.unit_died.emit()
5. TurnManager 检查胜负 → 若胜利 → EventBus.battle_ended.emit()
6. UI 监听各信号 → 更新血条/SP 条/状态图标
```

### 9.3 依赖规则

| 规则 | 说明 |
|------|------|
| L3 不能直接调 L2 方法 | 必须通过 EventBus 信号 |
| L2 不能引用 L3 节点 | L2 不知道 UI 存在 |
| L1 不能引用 L2 业务逻辑 | L1 只管地图生命周期 |
| L0 之间可互相调用 | Autoload 之间允许 |
| L2/L3 通过 `EventBus` 与 L0 通信 | 不直接持有 Autoload 之外的引用 |
| 节点不持有跨场景引用 | 通过 `GameStateService.squad` 间接访问 |

---

## 10. 数据驱动与存档

### 10.1 状态分层

| 层级 | 持久化 | 载体 |
|------|--------|------|
| 玩家档案（永久） | ✅ 存档 | `SaveService` |
| 世界状态（永久） | ✅ 存档 | `WorldState` Resource |
| 队伍状态（永久） | ✅ 存档 | `GameStateService.squad` |
| 战斗道具携带槽（永久） | ✅ 存档 | `GameStateService.combat_item_slots` |
| 战斗状态（临时） | ❌ 不存档 | `BattleState` Resource |
| 战斗道具冷却（临时） | ❌ 不存档 | `GameStateService.item_cooldowns` |
| 单位运行时状态（临时） | ❌ 不存档 | `Unit` 节点 |
| UI 状态（临时） | ❌ 不存档 | UI 节点 |

### 10.2 存档触发点

| 触发 | 槽位 | 时机 |
|------|------|------|
| 通信锚点激活 | `auto` | `EventBus.anchor_activated` |
| 营地休息 | `auto` | 玩家在营地选择"休息" |
| 玩家手动 | 自选 | UI 存档菜单 |
| 战斗胜利 | `auto` | `EventBus.battle_ended` 且 result.winner == "ally" |

### 10.3 存档版本控制

```gdscript
# save_service.gd
const SAVE_VERSION := "0.3"

func _migrate(old_data: Dictionary, old_version: String) -> Dictionary:
    # 版本迁移逻辑
    match old_version:
        "0.0":
            # 0.0 → 0.1 迁移
            old_data["world_state"]["faction_reputation"] = {}
            return old_data
    return old_data
```

---

## 11. 输入路由

### 11.1 各模式输入流向

| 模式 | 主输入 | 处理者 |
|------|--------|--------|
| REALTIME | WASD 移动 + 右键路径移动 + 1–4 主控切换 + 手动开战 | `BootstrapInputController` 注册到 `InputRouter` |
| ENVIRONMENT_TURN | 鼠标点击干员/格子 + 数字键选人 | 后续 `TurnInputHandler` |
| COMBAT_TURN | 方向键移动 + 左键点敌人选目标 + 左键点空格路径移动 + A/S/E/Enter/Space | `BootstrapInputController` 注册到 `InputRouter`，目标解析交给 `TargetingController` |
| CAMP | 鼠标点击设施 | `CampInputHandler` |
| MENU | 鼠标/方向键导航 UI | UI 自身 |
| CUTSCENE | 无（锁定） | — |
| LOADING | 无（锁定） | — |

### 11.2 快捷键映射

| 键 | 行为 | 适用模式 |
|----|------|----------|
| WASD | 移动主控角色 | REALTIME |
| Tab | 切换主控角色 / 进入环境回合 | REALTIME / ENVIRONMENT |
| 1-4 | 选中编队中第 N 名干员 | REALTIME / TURN |
| F | 交互（对话/拾取/开门/激活锚点） | REALTIME |
| Space | 切换模式（实时↔环境回合） | REALTIME / ENVIRONMENT |
| Enter | 结束当前回合 | TURN |
| I | 打开背包 | 任意（暂停游戏） |
| K | 打开技能面板 | 任意 |
| C | 打开属性面板 | 任意 |
| M | 打开地图 | REALTIME |
| J | 任务日志 | 任意 |
| Esc | 关闭面板 / 暂停菜单 | 任意 |

### 11.3 InputRouter 实现要点

- 输入处理器在 `_ready()` 时向 `InputRouter` 注册
- 模式切换时，`InputRouter` 自动路由到新模式的处理器
- 处理器决定是否 `set_input_as_handled()`，避免事件穿透

---

## 12. 扩展性指引

### 12.1 新增职业

1. 创建 `res://data/classes/<new_class>.tres`（`ClassData` Resource）
2. 设置体力上限、回合回复、SP 充能特征
3. 无需改任何代码——`SkillData` 通过 `class_id` 引用

### 12.2 新增技能

1. 创建 `res://data/skills/<operator>/<skill>.tres`（`SkillData` Resource）
2. 配置消耗、SP、效果链
3. 若需要自定义执行逻辑，继承 `Action` 写子类，在 `SkillData` 中关联
4. `SkillRegistry.reload()` 自动加载

### 12.3 新增地图

1. 创建地图场景 `res://scenes/maps/<id>.tscn`（遵循 §4.3 模板）
2. 创建 `res://data/maps/<id>.tres`（`MapManifest`）
3. 配置通路、锚点、入口
4. 在相邻地图的 `MapManifest.portals` 中添加反向通路
5. 无需改代码——`WorldDirector.load_map(map_id)` 即可加载

### 12.4 新增敌人

1. 继承 `EnemyUnit`，添加 AI 节点（行为树/状态机）
2. 创建 `res://data/enemies/<id>.tres` 描述其属性
3. 在地图的 `SpawnPoints` 下放置生成点

### 12.5 新增状态效果

1. 创建 `res://data/effects/<id>.tres`（`StatusEffect` Resource）
2. 配置 modifiers 和持续时间
3. 通过 `StatusEffectContainer.apply()` 应用
4. 无需改代码

### 12.6 新增 UI 面板

1. 创建场景 `res://scenes/ui/panel_<name>.tscn`
2. 脚本继承 `Control`，监听 `EventBus.request_open_panel`
3. 在 `UIManager` 注册面板名
4. 绑定快捷键到 `EventBus.request_open_panel.emit("<name>", {})`

---

## 13. 反模式清单

> 以下做法**明确禁止**，code review 时必须拒绝。

### 13.1 状态管理

| ❌ 禁止 | ✅ 应该 |
|---------|---------|
| 节点直接持有跨地图状态（如 `var visited_maps`） | 放入 `WorldState` Resource |
| Controller 把模式/回合/输入揉在一起 | 拆到 `ModeManager` / `TurnManager` / `InputRouter` |
| 在 `_process` 里轮询全局状态 | 用信号订阅 |
| UI 节点直接修改 Unit 属性 | 通过 EventBus 发请求 |

### 13.2 资源管理

| ❌ 禁止 | ✅ 应该 |
|---------|---------|
| 在场景里硬编码 Spine skeleton 引用 | 通过 `AssetLibrary.get_spine_skeletons()` 获取 |
| 多个实例共享修改同一个 Resource | 用 `duplicate(true)` 拷贝 |
| 地图切换时 `queue_free()` 干员视觉 | 用 `VisualPool.release()` |
| 同步 `load()` 大型场景 | 用 `ResourceLoader.load_threaded_*` |

### 13.3 耦合

| ❌ 禁止 | ✅ 应该 |
|---------|---------|
| L3 UI 节点 `as Unit` 强转调用方法 | 通过 EventBus 信号 |
| 跨场景硬编码 NodePath（`../../Grid`） | 用 `WorldDirector.current_map.grid` 或 EventBus |
| Autoload 持有场景节点引用 | Autoload 只持有 Resource / 数据 |
| 每个节点各自监听 `_unhandled_input` | 统一走 `InputRouter` |

### 13.4 数据驱动

| ❌ 禁止 | ✅ 应该 |
|---------|---------|
| 在脚本里硬编码技能数值 | 用 `SkillData` Resource |
| 在代码里写 `if operator_id == "amiya"` | 用 `OperatorData` 字段查询 |
| 在场景里手写敌人属性 | 用 `EnemyData` Resource |
| 任务进度存在脚本变量里 | 放入 `QuestState` |

### 13.5 命名

| ❌ 禁止 | ✅ 应该 |
|---------|---------|
| 变量名 `data1` `tmp` `x` | 语义化命名 |
| 函数名 `do_stuff()` | `begin_turn()` / `apply_damage()` |
| 信号名 `change` | `stat_changed` / `mode_changed`（过去式） |

---

## 14. 实施路线

### 14.1 与 GDD 里程碑对齐

| GDD 里程碑 | 架构阶段 | 交付物 |
|-----------|----------|--------|
| M0 骨架 | 阶段 1-2 | L0 Autoload 骨架 + Unit 基类 |
| M1 战斗核心 | 阶段 3-5 | TurnManager + 数据驱动化 + 资源 Tracker |
| M2 实时/回合切换 | 阶段 3 | ModeManager 完整实现 + InputRouter |
| M3 HD-2D 化 | 阶段 8 | VisualPool + Spine 资源管理 |
| M4 装备 + 道具 | — | EquipmentContainer + Inventory |
| M5 基建系统 | — | CampScene + 设施节点 |
| M6 大世界壳 | 阶段 4 | MapInstance + PortalNode + AnchorNode |
| M7 Alpha | 阶段 7 | SaveService 完整 + 存档测试 |

### 14.2 实施阶段

```
[阶段 1] 铺 L0 Autoload 骨架
  ├─ 创建 event_bus.gd（信号总线，定义全部跨层信号）
  ├─ 创建 mode_manager.gd（7 态状态机 + 切换副作用）
  ├─ 创建 game_state_service.gd（squad/inventory/quest 等运行时状态）
  ├─ 创建 asset_library.gd（Resource LRU 缓存骨架）
  ├─ 创建 input_router.gd（输入路由器骨架）
  └─ 在 project.godot 注册全部 Autoload

[阶段 2] Unit 基类 + 资源 Tracker
  ├─ 创建 scripts/game/unit/unit.gd（CharacterBody3D 基类）
  ├─ 实现 StaminaTracker / SpTracker / HpTracker 三子节点
  ├─ 实现 TurnParticipant 协议方法
  └─ 单元测试：Tracker 扣费/回复/信号触发

[阶段 3] 回合与模式系统
  ├─ 实现 turn_manager.gd（initiative 排序 + 回合推进）
  ├─ 实现 initiative_resolver.gd（伏击轮加成）
  ├─ 实现 battle_state.gd + battle_controller.gd
  ├─ 完善 ModeManager 切换副作用表
  └─ 集成测试：实时 → 战斗 → 结束 → 实时

[阶段 3A] M0 网格行动
  ├─ 暴露 GameGrid3D world_to_cell / cell_to_world / snap_world_to_cell_center [已完成]
  ├─ GameGrid3D 支持按格移动成本、阻挡格、默认成本和 terrain cost 清理接口 [已完成]
  ├─ MapManifest 支持 terrain_move_costs / terrain_blocked_cells，并在 MapInstance.initialize 写入 GameGrid3D [已完成]
  ├─ 实现 MoveAction：单格移动、按目标格成本扣体力、拒绝占用格/阻挡格 [已完成]
  ├─ Bootstrap 方向键驱动当前玩家单位移动 [已完成]
  ├─ 单位生成/移动维护 Grid 占用表 [已完成]
  ├─ Bootstrap 鼠标悬停路径预览 + 实时右键/战斗左键按路径移动 [已完成]
  ├─ Bootstrap 实时探索 WASD 单格移动 [已完成]
  ├─ Bootstrap 生成 4 个独立 OperatorData 的开发期小队，并在实时探索中按队形跟随主控 [已完成]
  ├─ Bootstrap 实时探索 1–4 数字键切换主控，并让其余存活队员重新跟随 [已完成]
  ├─ 新增 SquadController 接管小队成员列表、主控切换、跟随队形和主控阵亡自动接管 [已完成]
  ├─ 新增 BootstrapInputController，通过 InputRouter 注册 REALTIME/COMBAT_TURN 输入处理器 [已完成]
  ├─ 新增 PathPreviewController 接管鼠标投射、成本路径和 3D 路径预览渲染 [已完成]
  ├─ PathPreviewController 使用 GameGrid3D 移动成本做 Dijkstra 风格路径搜索 [已完成]
  ├─ 新增 TargetingController 接管战斗显式选格/选敌和目标标记 [已完成]
  ├─ 新增 TerrainRegion 编辑器地形区域，MapInstance 初始化时自动写入 GameGrid3D [已完成]
  ├─ TerrainRegion 已接入 TerrainData 正式地形类型 [已完成]
  └─ 下一步：将 TerrainData 进一步接入 TileMap/GridMap 的正式地形导出

[阶段 3B] M1 技能行动
  ├─ 修正 SpTracker：SP 跨回合保留，不在新回合重置 [已完成]
  ├─ 实现 SkillAction：读取 SkillData，检查体力 + SP + 距离 [已完成]
  ├─ 技能伤害使用 DamageCalculator.calc_magical [已完成]
  ├─ Bootstrap 使用 S 键释放阿米娅技能 1 [已完成]
  ├─ Battle HUD 显示首个技能 SP [已完成]
  ├─ Battle HUD 技能按钮显示体力费用和 SP 状态，不满足资源时禁用 [已完成]
  ├─ 技能按钮通过 EventBus.request_use_action 复用 Bootstrap 技能执行路径 [已完成]
  ├─ 普攻和技能 1 优先使用 TargetingController 的已选敌人，未选择时保留最近敌人兜底 [已完成]
  ├─ SkillRegistry 支持按 operator_id + slot 查询技能，并按 slot 排序 [已完成]
  ├─ Bootstrap 技能执行入口泛化为 _try_player_skill_slot(slot, target)，技能 1/2/3 均可按槽位走 SkillAction [已完成]
  ├─ 新增阿米娅技能 2/3 开发期 SkillData [已完成]
  ├─ 新增 SkillCooldownTracker，Unit 每回合开始递减冷却，SkillAction 成功后写入冷却 [已完成]
  ├─ Battle HUD 扩展为 3 技能槽，显示 SP、体力费用和运行时剩余 CD [已完成]
  ├─ Battle HUD 增加当前行动单位状态效果面板 [已完成]
  ├─ SkillAction 支持 self_buff_modifiers 转换为自我状态、target_status_effect 施加目标状态、aoe_radius_meters 收集范围目标 [已完成]
  ├─ SkillData 增加 summon_operator_id / summon_display_name / summon_duration_rounds，用于声明技能召唤物 [已完成]
  ├─ 新增 data/effects/amiya_arts_burn.tres，阿米娅技能 2 可施加法术灼烧 [已完成]
  ├─ 阿米娅技能 3 改为目标周围小范围法术伤害 [已完成]
  ├─ 阿米娅技能 3 配置战术投影召唤物，并由 SkillAction 成功后发出 summon_requested [已完成]
  ├─ StatusEffectContainer 在状态移除/过期/清空时撤销属性修正 [已完成]
  ├─ EventBus 增加 skill_used 信号，SkillAction 成功后广播技能释放结果 [已完成]
  ├─ 新增 SkillEffectPresenter 监听 skill_used，生成施法标记、命中标记、伤害数字和 AOE 范围提示 [已完成]
  └─ 下一步：正式 Spine 动画、粒子特效、音效和技能瞄准范围 UI

[阶段 4] 世界层 + 第一张地图
  ├─ 实现 map_instance.gd（地图根节点 + 自动收集子节点）
  ├─ 实现 portal_node.gd / anchor_node.gd
  ├─ 实现 world_director.gd（load_map / fast_travel / return_to_camp）
  ├─ 创建 scenes/maps/dragon_outer.tscn（龙门外环首张地图）[已完成：M0 灰盒]
  ├─ 创建 data/maps/dragon_outer.tres（MapManifest）[已完成]
  ├─ 将 M0 敌人出生点迁入 MapManifest.enemy_spawns [已完成]
  └─ 集成测试：地图加载 + 通路切换 + 锚点激活

[阶段 4A] 地图遭遇配置
  ├─ 新增 EncounterData Resource [已完成]
  ├─ MapManifest 增加 encounters: Array[Resource] [已完成]
  ├─ dragon_outer.tres 引用 dragon_outer_intro.tres [已完成]
  ├─ Bootstrap 从 current_map.manifest.encounters[0] 生成敌人并启动战斗 [已完成]
  ├─ BattleController/TurnManager/BattleState 接收遭遇胜负条件 [已完成]
  ├─ Bootstrap 在 REALTIME 模式下使用 trigger_center/trigger_radius 做警戒触发 [已完成]
  ├─ EncounterData 支持 enemy_waves / reward_items / reward_lmd / reward_exp / world_flags_on_victory / quest_updates_on_victory [已完成]
  ├─ TurnManager/BattleState 支持战斗中追加增援敌人 [已完成]
  ├─ Bootstrap 在 round_started 时生成波次，在胜利时写入奖励、完成标记、世界 flag 和任务状态 [已完成]
  ├─ Bootstrap 支持 enemy_waves.conditions，按 trigger_min_round、min/max_alive_enemies、required/blocked_world_flags 和 required_quest_states 判断增援波次 [已完成]
  ├─ dragon_outer_intro 的第 2 回合增援增加 conditions 示例，验证条件化波次配置链路 [已完成]
  ├─ Battle HUD 结果面板显示胜负、回合数和 EncounterData 奖励文本 [已完成]
  ├─ Bootstrap 生成 encounter_resolution，包含奖励、任务更新、世界 flag 和重复完成状态 [已完成]
  ├─ Battle HUD 结果面板分区显示奖励、任务更新和世界状态变化 [已完成]
  ├─ 将结果面板拆成 scenes/ui/panel_battle_result.tscn + BattleResultPanel 脚本 [已完成]
  ├─ EventBus 增加 battle_stat_recorded；攻击、技能、道具、移动和敌方攻击成功后上报战斗统计 [已完成]
  ├─ 早期 battle_stats 汇总已验证伤害、治疗、资源、击倒和高亮记录链路 [已完成]
  ├─ BattleResultPanel 增加战斗复盘区，显示汇总统计和关键记录 [已完成]
  ├─ 新增 scripts/game/turn/battle_log.gd，将 battle_stats 汇总与行动 entries 从 Bootstrap 迁入 BattleLog Resource [已完成]
  ├─ Bootstrap 将 battle_stat_recorded 归一化为回合、行动者、目标、阵营、资源和伤害记录后写入 BattleLog [已完成]
  ├─ BattleResultPanel 优先展示 BattleLog entries 的行动描述，兼容旧 highlights 字段 [已完成]
  ├─ StatusEffectContainer 在状态应用、刷新、叠层、移除和过期时上报 battle_stat_recorded [已完成]
  ├─ StatusEffectInstance 在持续伤害/治疗 tick 时上报 BattleLog 事件，并保留来源、目标、状态名和击倒信息 [已完成]
  ├─ BattleLog 汇总 statuses / status_ticks，并生成状态变化与持续结算描述 [已完成]
  ├─ BattleResultPanel 显示状态变化与持续结算次数 [已完成]
  ├─ ItemData 增加 revive_hp；ItemAction 允许具备复苏值的道具作用于倒下单位 [已完成]
  ├─ Unit 增加 revive(to_hp, source)，复苏后上报 BattleLog revive 事件 [已完成]
  ├─ TargetingController / Bootstrap 允许显式选中倒下友方作为复苏道具目标 [已完成]
  ├─ 罗德岛急救包增加开发期 revive_hp，并可复苏倒下友方后继续恢复 HP/体力 [已完成]
  ├─ BattleLog 汇总 revives 并生成复苏行动描述；BattleResultPanel 显示复苏次数 [已完成]
  ├─ TerrainRegion 增加 hazard_damage / hazard_source，MapInstance 写入 GameGrid3D 危险格 [已完成]
  ├─ GameGrid3D 支持 set_cell_hazard / get_world_hazard，并随地形配置清理 [已完成]
  ├─ MoveAction 在战斗移动进入危险格后结算环境伤害，并以 environment_damage 写入 BattleLog [已完成]
  ├─ dragon_outer 增加 OriginiumHazard 开发期源石污染危险区与可视化平面 [已完成]
  ├─ BattleLog 汇总 environment_damage 并生成环境伤害描述；BattleResultPanel 显示环境伤害总量 [已完成]
  ├─ TerrainRegion / GameGrid3D 支持 hazard_status_effect_id，危险格可在入格时触发状态效果 [已完成]
  ├─ MoveAction 入格后从 AssetLibrary 加载地形状态效果并应用到单位，同时写入 terrain_trigger 复盘事件 [已完成]
  ├─ dragon_outer 的 OriginiumHazard 会触发开发期法术灼烧状态 [已完成]
  ├─ BattleLog 汇总 terrain_triggers 并生成地形触发描述；BattleResultPanel 显示环境触发次数 [已完成]
  ├─ 新增 TerrainData Resource，并加入 rubble_slow / cover_blocked / originium_pollution 地形类型 [已完成]
  ├─ AssetLibrary 支持 get_terrain_data 与 terrain 缓存 [已完成]
  ├─ TerrainRegion 支持 terrain_id，从 TerrainData 读取默认移动成本、阻挡、危险伤害和状态触发 [已完成]
  ├─ TerrainRegion 增加 override_* 开关，保留编辑器灰盒覆盖能力 [已完成]
  ├─ dragon_outer 的 TerrainRegion 已切换为 terrain_id 引用正式地形类型 [已完成]
  ├─ 新增 SummonedUnit，复用 OperatorData 数值但不进入 SquadController，小队成员和召唤物身份分离 [已完成]
  ├─ Bootstrap 监听 summon_requested，在目标附近寻找可通行空格，生成战术投影、注册 Grid 占用并加入友方回合参与者 [已完成]
  ├─ TurnManager/BattleState 增加 remove_participant/remove_unit，召唤物退场时同步移出回合顺序和胜负判断列表 [已完成]
  ├─ Bootstrap 在 round_started 驱动召唤物持续轮数，到期或战斗结束时清理占用和场景节点 [已完成]
  ├─ BattleLog 汇总 summons / summon_expires 并生成召唤、退场描述；BattleResultPanel 显示召唤与退场次数 [已完成]
  ├─ SummonedUnit 增加 is_player_controllable() == false，Bootstrap/HUD 不再将召唤物视作玩家可手操干员 [已完成]
  ├─ TurnManager 在召唤物回合延迟触发 SummonedUnit.ai_take_turn，召唤物会自动索敌并以法术伤害攻击附近敌人后结束回合 [已完成]
  ├─ Bootstrap 增加开发期默认召唤上限，同一施法者重复召唤会先替换旧召唤物 [已完成]
  ├─ 召唤物被击倒时通过 _retire_summon 退场，清理 Grid 占用、回合参与者和 BattleState 列表 [已完成]
  ├─ 新增 SummonData Resource 与 data/summons/amiya_tactical_echo.tres，数据化 operator_id、持续轮数、上限策略、AI 行动包、攻击类型、倍率、索敌范围、体力消耗和 VFX/UI 表现 hook 字段 [已完成]
  ├─ SkillData 增加 summon_data 引用；SkillAction 优先使用 SummonData.to_payload()，旧 summon_* 字段保留为兼容兜底 [已完成]
  ├─ AssetLibrary 支持 get_summon_data 与 summons 缓存 [已完成]
  ├─ SummonedUnit 从 payload 读取 ai_behavior / attack_damage_type / attack_damage_multiplier / attack_range_meters / attack_stamina_cost [已完成]
  ├─ Bootstrap 从 payload 读取 max_per_owner / limit_policy，支持 replace_oldest 与 fail 两种开发期上限策略 [已完成]
  ├─ SummonData 增加 spawn_rule、heal_amount、heal_multiplier、heal_range_meters、heal_stamina_cost，支持在施法者附近生成治疗型召唤物 [已完成]
  ├─ SummonedUnit 支持 heal_lowest_ally 行动包，自动治疗范围内生命比例最低的友方，并写入 BattleLog summon_heal [已完成]
  ├─ 新增 rhodes_healing_drone OperatorData / SummonData，以及医疗干员技能 1「部署医疗无人机」[已完成]
  ├─ BattleLog / BattleResultPanel 记录并展示召唤治疗次数 [已完成]
  ├─ SummonData 增加 threat_on_spawn / threat_range_meters，支持防御型召唤物落地时向附近敌人写入仇恨 [已完成]
  ├─ SummonedUnit 支持 guard 行动包，防御型召唤物自身不主动行动，但保留回合生命周期和占格能力 [已完成]
  ├─ Bootstrap 在召唤成功后应用出生仇恨，并以 summon_guard 写入 BattleLog [已完成]
  ├─ 新增 rhodes_guard_barrier OperatorData / SummonData，以及重装干员技能 1「部署阻挡盾」[已完成]
  ├─ BattleLog / BattleResultPanel 记录并展示召唤护援次数 [已完成]
  ├─ EventBus 增加 summon_retire_requested，允许召唤物主动请求 Bootstrap 清理网格占用、回合参与者和场景节点 [已完成]
  ├─ SummonData 增加 trap_trigger_radius_meters / trap_damage / trap_damage_multiplier / trap_damage_type / trap_status_effect_id，支持陷阱型召唤物参数化 [已完成]
  ├─ SummonedUnit 支持 trap_nearest_enemy 行动包，敌人进入触发半径后造成范围伤害、可施加状态、写入 summon_trap 并请求退场 [已完成]
  ├─ 新增 rhodes_shock_mine OperatorData / SummonData、shock_stagger 状态效果、specialist 职业数据，以及近卫干员技能 1「部署震荡地雷」[已完成]
  ├─ BattleLog / BattleResultPanel 记录并展示召唤陷阱触发次数 [已完成]
  ├─ SummonedUnit 缓存 spawn_vfx_id / expire_vfx_id / ui_hint，Bootstrap 在生成、退场和陷阱触发时发出 summon_visual_requested [已完成]
  ├─ SkillEffectPresenter 监听 summon_visual_requested，生成召唤生成/退场/触发的开发期地面标记与浮字提示 [已完成]
  ├─ BattleHud 在召唤物状态行显示 ui_hint，让召唤行为提示进入 HUD 反馈闭环 [已完成]
  ├─ SummonData 增加 hud_icon_text 并写入 payload；SummonedUnit 缓存该字段，BattleHud 在召唤物状态标签中显示文本图标 [已完成]
  ├─ amiya_tactical_echo / rhodes_healing_drone / rhodes_guard_barrier / rhodes_shock_mine 分别配置「影 / 医 / 盾 / 雷」开发期 HUD 图标 [已完成]
  ├─ Bootstrap 将 TargetingController 绑定给 BattleHud，HUD 状态栏显示锁定/默认目标、距离和技能 1-3 的单体/范围命中预览 [已完成]
  ├─ BattleHud 的瞄准预览只读复用 SkillRegistry、TargetingController 和 WorldDirector，不改变 SkillAction 的实际校验与执行路径 [已完成]
  ├─ SummonData 增加 trap_arm_delay_rounds / trap_max_targets / trap_trigger_archetypes / trap_trigger_factions，支持陷阱延迟启用、目标数量上限和敌方 archetype/faction 过滤 [已完成]
  ├─ SummonData 增加 trap_required_target_status_effect_ids / trap_blocked_target_status_effect_ids，支持按目标状态效果筛选陷阱触发对象 [已完成]
  ├─ SummonData 增加 trap_min_target_hp_ratio / trap_max_target_hp_ratio，支持按目标 HP 比例筛选陷阱触发对象 [已完成]
  ├─ SummonedUnit 的 trap_nearest_enemy 行动包按未启用倒计时、archetype/faction/status/HP 比例过滤和最近目标上限收集触发目标 [已完成]
  ├─ rhodes_shock_mine 更新为下轮启用、最多命中 2 名 infected 阵营、grunt/caster、未带 shock_stagger 且 HP 比例不低于 0.2 的感染者，HUD 显示未启用倒计时 [已完成]
  ├─ SummonData 增加 trap_chain_radius_meters / trap_chain_max_triggers，支持陷阱触发后牵引附近已启用陷阱 [已完成]
  ├─ SummonedUnit 支持 trigger_trap_from_chain，连锁触发不重复结束当前回合，并在 BattleLog 中以 chain_depth 标注层级 [已完成]
  ├─ rhodes_shock_mine 更新为可牵引 2.5 米内 1 个已启用且有目标的地雷 [已完成]
  ├─ GameGrid3D 增加 terrain_id 查询表，MapInstance 从 TerrainRegion.terrain_id 写入地形 ID [已完成]
  ├─ SummonData 增加 trap_terrain_damage_multipliers / trap_terrain_status_effect_ids，支持陷阱按所在格地形调整伤害和追加状态 [已完成]
  ├─ SummonedUnit 触发陷阱时读取当前 terrain_id，并将地形倍率写入 summon_trap BattleLog 记录 [已完成]
  ├─ rhodes_shock_mine 在 originium_pollution 地形上伤害 ×1.35，并追加 amiya_arts_burn 法术灼烧 [已完成]
  ├─ SkillEffectPresenter 在陷阱召唤生成时读取 SummonedUnit 的 trap_trigger_radius_meters / trap_chain_radius_meters，绘制触发范围与连锁范围预览地面圈 [已完成]
  ├─ EnemyData 增加 faction_id，infected_grunt_01 / infected_caster_01 标记为 infected，rhodes_shock_mine 通过 trap_trigger_factions 只响应该阵营 [已完成]
  ├─ SummonData 增加 trap_linger_terrain_id，支持陷阱触发后声明残留 TerrainData 地形 [已完成]
  ├─ SummonedUnit 触发陷阱后调用 _apply_trap_linger_terrain()，将自身格 terrain_id、移动成本/阻挡和 hazard 写回 GameGrid3D [已完成]
  ├─ 新增 shock_residue TerrainData，rhodes_shock_mine 触发后残留震荡余波，后续入格单位会触发 shock_stagger [已完成]
  ├─ BattleLog 的 summon_trap 描述追加 linger_terrain_id，方便战斗复盘确认残留地形 [已完成]
  ├─ SummonData 增加 trap_linger_duration_rounds，支持陷阱残留地形按回合持续或永久保留 [已完成]
  ├─ GameGrid3D 增加 set_cell_temporary_terrain / tick_temporary_terrain_rounds / clear_temporary_terrain，临时地形到期后恢复原格地形、移动成本/阻挡和 hazard [已完成]
  ├─ Bootstrap 在 round_started 推进临时地形寿命，并在 battle_ended 恢复未到期临时地形 [已完成]
  ├─ rhodes_shock_mine 的 shock_residue 残留持续 2 轮，BattleLog 的 summon_trap 描述显示残留持续轮数 [已完成]
  ├─ SummonData 增加 trap_linger_terrain_overrides，支持按触发格 terrain_id 覆盖默认残留地形 [已完成]
  ├─ SummonedUnit 触发陷阱时将 source terrain_id 传给 _apply_trap_linger_terrain，并通过 _resolve_linger_terrain_id 选择实际残留地形 [已完成]
  ├─ 新增 originium_shock_residue TerrainData；rhodes_shock_mine 在 originium_pollution 上触发时残留源石震荡余波，入格造成 60 点危险伤害并触发 shock_stagger [已完成]
  ├─ SummonData 增加 trap_linger_spread_source_terrain_ids / trap_linger_spread_radius_cells / trap_linger_spread_max_cells，支持残留地形按源地形、半径和最大格数扩散 [已完成]
  ├─ SummonedUnit 触发陷阱后通过 _apply_trap_linger_spread() 将实际残留 TerrainData 写入邻格，并把扩散格数写入 summon_trap BattleLog 记录 [已完成]
  ├─ rhodes_shock_mine 在 originium_pollution 上触发时，originium_shock_residue_faded 向 1 格范围内最多 4 个可通行邻格扩散 [已完成]
  ├─ SummonData 增加 trap_linger_spread_terrain_id / trap_linger_spread_terrain_overrides / trap_linger_spread_duration_rounds，支持扩散残留使用独立 TerrainData 与持续时间 [已完成]
  ├─ 新增 originium_shock_residue_faded TerrainData；rhodes_shock_mine 在 originium_pollution 上触发时中心格保留 2 轮强源石震荡余波，邻格扩散 1 轮衰减源石震荡余波 [已完成]
  ├─ BattleLog 的 summon_trap 描述显示扩散残留 terrain_id、扩散格数和扩散持续轮数 [已完成]
  ├─ rhodes_shock_mine 在 rubble_slow 地形上触发时伤害 ×0.75，BattleLog 通过 terrain_damage_multiplier 显示削弱倍率 [已完成]
  ├─ 新增 rubble_shock_residue TerrainData；rhodes_shock_mine 在 rubble_slow 上触发时残留碎石震荡余波，保留 move_cost = 2 并触发 shock_stagger [已完成]
  └─ 下一步：将召唤占位表现、文本图标和文本瞄准预览替换为正式粒子、音效、图标资源和范围 UI；扩展不同伤害/状态组合和更多地形反应；TerrainData 继续接入 TileMap/GridMap 正式导出；波次触发继续扩展为可复用条件资源

[阶段 4B] 战斗道具竖切
  ├─ 新增 ItemAction，按 ItemData 对目标 Unit 应用治疗、体力回复、SP 充能和状态效果 [已完成]
  ├─ AssetLibrary 支持 get_item_data / get_effect_data [已完成]
  ├─ 新增 data/items/rhodes_medkit.tres 开发期急救包 [已完成]
  ├─ Bootstrap 初始化开发期共享背包数量，并在使用后扣减 GameStateService.shared_inventory [已完成]
  ├─ Bootstrap 使用 TargetingController 的显式选中单位作为道具目标；治疗类道具仅允许友方目标，未选友方时默认当前行动干员 [已完成]
  ├─ ItemData / ItemAction 支持 revive_hp，罗德岛急救包可复苏倒下友方 [已完成]
  ├─ Battle HUD 增加快捷道具按钮，战斗输入支持 Q 使用快捷道具 [已完成]
  ├─ ItemData 增加 target_type，支持 self / ally / enemy / any 四类目标规则；Bootstrap 与 ItemAction 双侧校验目标类型 [已完成]
  ├─ rhodes_medkit 标记为 ally，BattleHud 快捷道具按钮显示目标类型标签 [已完成]
  ├─ ItemData 增加 cooldown_rounds；GameStateService 记录单场战斗 item_cooldowns，Bootstrap 在 battle_started / battle_ended 清空并在 round_started 递减 [已完成]
  ├─ rhodes_medkit 配置 1 轮冷却；Bootstrap 与 ItemAction 在冷却中禁止使用，BattleHud 显示 CD 并禁用按钮 [已完成]
  ├─ ItemData 增加 rarity；rhodes_medkit 标记为 2 档精良，BattleHud 快捷道具按钮显示稀有度标签 [已完成]
  ├─ ItemData 增加 category，支持 healing / support / offense / utility 四类稳定 ID；BattleHud 显示道具分类标签 [已完成]
  ├─ 新增 rhodes_sp_injector 支援类 SP 针剂，验证 charge_sp_amount 道具效果链路 [已完成]
  ├─ Bootstrap / BattleHud 支持开发期快捷道具列表，Q 使用当前道具，R 切换当前道具 [已完成]
  ├─ ItemData 增加 damage_amount / damage_type / aoe_radius_meters，ItemAction 支持攻击类范围道具伤害与状态施加 [已完成]
  ├─ 新增 rhodes_shock_grenade 攻击类震荡手雷，验证 enemy 目标、范围伤害、状态施加和 BattleLog 记录 [已完成]
  ├─ GameStateService 增加 combat_item_slots / selected_combat_item_slot_index，作为可存档战斗道具携带槽；Bootstrap 仅注入开发期默认槽位 [已完成]
  ├─ BattleHud 将单个快捷道具按钮升级为三槽战斗道具栏，支持按槽位显示数量、稀有度、分类、目标、CD 与点击使用 [已完成]
  ├─ 新增 ItemLoadoutPanel 开发期整备面板，支持按 I 打开并按槽位替换 combat_item_slots；新增 rhodes_tactical_ration 体力补给道具作为未装备库存样例 [已完成]
  ├─ combat_item_slots 改为固定 3 槽，空字符串代表空槽；BattleHud / ItemLoadoutPanel 保留空槽位置，R 切换跳过空槽 [已完成]
  └─ 下一步：正式道具栏拖拽/筛选/排序与更多投掷/环境道具效果

[阶段 5] 数据驱动化
  ├─ 创建 OperatorData / SkillData / ClassData / EquipmentData / ItemData Resource 类
  ├─ 为阿米娅与 3 名开发期职业样例干员填写数据 .tres 文件 [已完成：002_amiya / 103_medic_dev / 106_guard_dev / 150_defender_dev]
  ├─ 创建术师/医疗/近卫/重装 ClassData [已完成]
  ├─ 创建 EnemyData + data/enemies/*.tres [已完成：M0 感染者近卫/术师]
  ├─ 实现 skill_registry.gd（启动时扫描 data/skills/）
  ├─ 完善 AssetLibrary 加载逻辑
  └─ Unit 通过 AssetLibrary 获取属性而非硬编码

[阶段 6] UI 层与 EventBus 联调
  ├─ 实现 ui_manager.gd（面板加载/卸载/上下文）
  ├─ 实现 hud_battle / hud_explore（对应 GDD §10.4 设计稿）
  ├─ 实现 panel_inventory / panel_skills / panel_stats / panel_map / panel_quest
  ├─ 所有 UI 通过 EventBus.request_* 发请求，监听 EventBus.* 更新显示
  └─ 集成测试：UI 操作 → 逻辑执行 → UI 反馈闭环

[阶段 6A] 替换开发 HUD
  ├─ 将 Bootstrap 内的 DevHud 抽出为 hud_battle.tscn [已完成]
  ├─ HUD 订阅 EventBus.turn_started / unit_died / battle_ended [已完成]
  ├─ 操作按钮通过 EventBus.request_use_action / request_end_turn 发请求
  └─ 将 HUD 实例化从 bootstrap.gd 迁入 UIManager

[阶段 7] 存档系统
  ├─ 实现 save_service.gd（JSON 序列化 + 槽位管理）
  ├─ 实现 world_state.gd（跨地图持久化状态）
  ├─ 通信锚点激活 → 自动存档到 auto 槽
  ├─ 营地休息 → 自动存档到 auto 槽
  └─ 集成测试：存档 → 关闭 → 重启 → 读档还原

[阶段 8] 对象池化与性能
  ├─ 实现 visual_pool.gd（Spine 视觉跨地图复用）
  ├─ 实现 effect_pool.gd / projectile_pool.gd
  ├─ 地图切换时干员视觉归还池而非销毁
  ├─ ResourceLoader.load_threaded_* 异步预加载相邻地图
  └─ 性能测试：地图切换 < 1s、战斗 60fps 稳定
```

### 14.3 文档维护

- 本文档随架构演进持续更新
- 每次架构变更需更新版本号 + 日期
- 重大变更在文档末尾追加 changelog
- 与 GDD 保持内容对应，并在标题注明当前对齐的 GDD 版本

### 14.4 Changelog

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.59 | 2026-06-30 | 战斗道具空槽规则竖切：combat_item_slots 改为固定槽位语义，空字符串代表空槽并参与 serialize/deserialize；set_combat_item_slots 补齐固定槽位且不压缩空值；set_combat_item_slot 支持清空槽位；cycle_combat_item_slot 跳过空槽；SaveService.SAVE_VERSION 升至 0.3；BattleHud 与 ItemLoadoutPanel 保留空槽位置并显示未装备；整备面板槽位循环加入空槽选项；GDD 对齐到 v1.61 |
| 1.58 | 2026-06-30 | 战斗道具整备面板竖切：新增 panel_item_loadout.tscn / ItemLoadoutPanel，可按 I 打开并从 shared_inventory 收集 usable_in_combat 道具；Bootstrap 处理槽位循环替换并同步 BattleHud；GameStateService 增加 set_combat_item_slot / get_combat_item_slot_id；新增 rhodes_tactical_ration 体力补给道具；GDD 对齐到 v1.60 |
| 1.57 | 2026-06-30 | 多槽道具 HUD 竖切：BattleHud 将单个快捷道具按钮替换为三槽 ItemBar，每槽显示道具名、数量、选中标记、稀有度、分类、目标和 CD；点击任意可用槽位会发送对应 item_id；Bootstrap 在默认战斗道具槽注入后重新同步 HUD；GDD 对齐到 v1.59 |
| 1.56 | 2026-06-30 | 战斗道具携带槽竖切：GameStateService 增加 combat_item_slots / selected_combat_item_slot_index 并纳入 serialize/deserialize；SaveService.SAVE_VERSION 升至 0.2；Bootstrap 只在槽位为空时注入开发期默认三件套，Q/R 使用同一状态源；item_cooldowns 继续保持单场战斗临时状态；GDD 对齐到 v1.58 |
| 1.55 | 2026-06-28 | 攻击类投掷道具竖切：ItemData 增加 damage_amount / damage_type / aoe_radius_meters；ItemAction 复用 DamageCalculator 对道具范围目标造成物理/法术/真实伤害并可施加状态；Bootstrap 对 enemy 目标道具补最近敌人回退；新增 rhodes_shock_grenade 震荡手雷；BattleLog 记录道具伤害、状态目标和击杀；GDD 对齐到 v1.57 |
| 1.54 | 2026-06-28 | 道具分类与快捷切换竖切：ItemData 增加 category；新增 rhodes_sp_injector 支援类 SP 针剂；Bootstrap 初始化开发期快捷道具列表并支持 R 切换、Q 使用当前道具；BattleHud 显示槽位、稀有度、分类、目标和 CD；BattleLog 道具描述按治疗、复苏、体力回复或 SP 回复生成；GDD 对齐到 v1.56 |
| 1.53 | 2026-06-28 | 道具稀有度竖切：ItemData 增加 rarity；rhodes_medkit 标记为 2 档精良；BattleHud 快捷道具按钮显示稀有度标签，为正式道具栏排序、筛选和掉落品质展示预留数据字段；GDD 对齐到 v1.55 |
| 1.52 | 2026-06-28 | 道具冷却竖切：ItemData 增加 cooldown_rounds；GameStateService 增加单场战斗 item_cooldowns，Bootstrap 在 battle_started/battle_ended 清空并在 round_started 递减；ItemAction 与 Bootstrap 在冷却中禁止使用道具；rhodes_medkit 配置 1 轮冷却；BattleHud 显示 CD 并禁用按钮；GDD 对齐到 v1.54 |
| 1.51 | 2026-06-28 | 道具目标类型数据化竖切：ItemData 增加 target_type；Bootstrap 的道具目标解析与 ItemAction.can_execute() 均按 self/ally/enemy/any 校验目标；rhodes_medkit 标记为 ally；BattleHud 快捷道具按钮显示目标类型标签；GDD 对齐到 v1.53 |
| 1.50 | 2026-06-28 | 技能瞄准预览 HUD 竖切：Bootstrap 将 TargetingController 绑定给 BattleHud；BattleHud 状态栏显示锁定/默认目标、距离，以及当前干员 1-3 号技能的单体/范围命中数和可用/距外提示；预览只读，不改变 SkillAction 的实际目标解析和执行；GDD 对齐到 v1.52 |
| 1.49 | 2026-06-28 | 召唤物 HUD 图标提示竖切：SummonData 增加 hud_icon_text 并写入 payload；SummonedUnit 缓存 hud_icon_text；BattleHud 在召唤物状态标签显示开发期文本图标；战术投影/医疗无人机/阻挡盾/震荡地雷分别配置「影/医/盾/雷」；GDD 对齐到 v1.51 |
| 1.48 | 2026-06-28 | 碎石地形陷阱反应竖切：新增 rubble_shock_residue TerrainData；rhodes_shock_mine 的 trap_terrain_damage_multipliers 增加 rubble_slow = 0.75，并通过 trap_linger_terrain_overrides 将 rubble_slow 残留转化为 rubble_shock_residue；碎石残留保留 move_cost = 2 并触发 shock_stagger；GDD 对齐到 v1.50 |
| 1.47 | 2026-06-28 | 陷阱残留地形扩散衰减竖切：SummonData 增加 trap_linger_spread_terrain_id/trap_linger_spread_terrain_overrides/trap_linger_spread_duration_rounds 并写入 payload；SummonedUnit 支持按源地形覆盖扩散残留 TerrainData 与扩散持续时间，未配置时回退中心残留地形和中心持续时间；新增 originium_shock_residue_faded；rhodes_shock_mine 在 originium_pollution 上触发时中心格为 2 轮 originium_shock_residue，邻格为 1 轮 originium_shock_residue_faded；BattleLog 显示扩散 terrain_id 和持续轮数 |
| 1.46 | 2026-06-28 | 陷阱残留地形扩散规则竖切：SummonData 增加 trap_linger_spread_source_terrain_ids/trap_linger_spread_radius_cells/trap_linger_spread_max_cells 并写入 payload；SummonedUnit 触发陷阱后将实际残留 TerrainData 扩散到邻格，并记录 linger_spread_cells；BattleLog 显示扩散格数；rhodes_shock_mine 在 originium_pollution 上触发时让 originium_shock_residue 向 1 格范围内最多 4 个可通行邻格扩散 |
| 1.45 | 2026-06-28 | 陷阱残留地形转化规则竖切：SummonData 增加 trap_linger_terrain_overrides 并写入 payload；SummonedUnit 根据触发格 source terrain_id 选择实际残留 TerrainData；新增 originium_shock_residue 地形资源；rhodes_shock_mine 在 originium_pollution 上触发时残留源石震荡余波，入格造成 60 点危险伤害并触发 shock_stagger |
| 1.44 | 2026-06-28 | 陷阱残留地形持续规则竖切：SummonData 增加 trap_linger_duration_rounds 并写入 payload；GameGrid3D 增加临时地形快照、回合 tick 和恢复接口；SummonedUnit 按持续轮数写入临时或永久残留地形；Bootstrap 在 round_started 推进临时地形寿命并在 battle_ended 清理；rhodes_shock_mine 的 shock_residue 残留持续 2 轮；BattleLog 显示残留持续轮数 |
| 1.43 | 2026-06-28 | 陷阱残留地形竖切：SummonData 增加 trap_linger_terrain_id 并写入 payload；SummonedUnit 触发陷阱后读取 TerrainData，将残留 terrain_id、移动成本/阻挡和 hazard 写回 GameGrid3D；新增 shock_residue 地形资源；rhodes_shock_mine 触发后留下震荡余波，后续入格单位触发 shock_stagger；BattleLog 的 summon_trap 描述显示残留地形 |
| 1.42 | 2026-06-28 | 陷阱目标血量过滤竖切：SummonData 增加 trap_min_target_hp_ratio/trap_max_target_hp_ratio 并写入 payload；SummonedUnit 使用 HpTracker.get_ratio() 过滤陷阱候选目标；rhodes_shock_mine 只响应 HP 比例不低于 0.2 的目标，避免残血单位骗出陷阱 |
| 1.41 | 2026-06-28 | 陷阱目标状态过滤竖切：SummonData 增加 trap_required_target_status_effect_ids/trap_blocked_target_status_effect_ids 并写入 payload；SummonedUnit 在 trap_nearest_enemy 收集目标时通过 Unit.has_status() 应用状态条件；rhodes_shock_mine 避开已带 shock_stagger 的目标，减少重复控制浪费 |
| 1.40 | 2026-06-28 | 波次条件表达式竖切：EncounterData.enemy_waves 支持 conditions 字典；Bootstrap 在 round_started 按 trigger_round、trigger_min_round、min/max_alive_enemies、required/blocked_world_flags 和 required_quest_states 判断是否生成增援；dragon_outer_intro 的第 2 回合增援加入条件示例 |
| 1.39 | 2026-06-28 | 陷阱阵营过滤竖切：EnemyData 增加 faction_id；感染者近卫/术师资源标记为 infected；SummonData 增加 trap_trigger_factions 并写入 payload；SummonedUnit 的 trap_nearest_enemy 同时按 archetype 与 faction 过滤目标；rhodes_shock_mine 只响应 infected 阵营的 grunt/caster |
| 1.38 | 2026-06-28 | 陷阱范围预览竖切：SkillEffectPresenter 增加 summon_range_mesh、trap_trigger_range_material 与 trap_chain_range_material；监听 summon_visual_requested 的 spawn 事件后读取 SummonedUnit 的 trap_trigger_radius_meters / trap_chain_radius_meters；震荡地雷生成时显示触发范围与连锁范围开发期地面圈 |
| 1.37 | 2026-06-28 | 地形联动陷阱竖切：GameGrid3D 存储并查询 terrain_id；MapInstance 从 TerrainRegion 写入地形 ID；SummonData 增加 trap_terrain_damage_multipliers/trap_terrain_status_effect_ids；SummonedUnit 按陷阱所在格地形调整伤害并追加状态；rhodes_shock_mine 在 originium_pollution 上伤害 ×1.35 并追加 amiya_arts_burn；BattleLog 显示地形倍率 |
| 1.36 | 2026-06-28 | 连锁陷阱召唤物竖切：SummonData 增加 trap_chain_radius_meters/trap_chain_max_triggers；SummonedUnit 支持 trigger_trap_from_chain，连锁触发按距离牵引附近已启用且有目标的陷阱，并避免重复结束当前回合；BattleLog 的 summon_trap 描述显示连锁层级；rhodes_shock_mine 可牵引 2.5 米内 1 个地雷 |
| 1.35 | 2026-06-28 | 条件陷阱召唤物竖切：SummonData 增加 trap_arm_delay_rounds/trap_max_targets/trap_trigger_archetypes；SummonedUnit 支持陷阱未启用倒计时、敌方 archetype 过滤和最近目标上限；rhodes_shock_mine 改为下轮启用、最多命中 2 名 grunt/caster 感染者；BattleHud 显示陷阱未启用倒计时 |
| 1.34 | 2026-06-28 | 召唤表现提示竖切：新增 EventBus.summon_visual_requested；SummonedUnit 缓存 SummonData 的 spawn_vfx_id/expire_vfx_id/ui_hint；Bootstrap 在召唤生成、退场和陷阱触发时发出表现请求；SkillEffectPresenter 生成开发期召唤地面标记与浮字提示；BattleHud 在召唤物状态行展示 ui_hint |
| 1.33 | 2026-06-28 | 陷阱型召唤物竖切：EventBus 增加 summon_retire_requested；SummonData 增加陷阱触发半径、伤害、伤害类型和状态字段；SummonedUnit 支持 trap_nearest_enemy 行动包；新增 rhodes_shock_mine OperatorData/SummonData、shock_stagger 状态、specialist 职业数据和近卫干员技能 1「部署震荡地雷」；BattleLog/结算面板记录召唤陷阱 |
| 1.32 | 2026-06-28 | 防御型阻挡召唤物竖切：SummonData 增加 threat_on_spawn/threat_range_meters；SummonedUnit 支持 guard 行动包；Bootstrap 将召唤出生仇恨写入敌方仇恨表并记录 summon_guard；新增 rhodes_guard_barrier OperatorData/SummonData 和重装干员技能 1「部署阻挡盾」；BattleLog/结算面板记录召唤护援 |
| 1.31 | 2026-06-28 | 治疗型召唤装置竖切：SummonData 增加 spawn_rule 与治疗参数；SummonedUnit 支持 heal_lowest_ally 行动包；新增 rhodes_healing_drone OperatorData/SummonData 和医疗干员技能 1「部署医疗无人机」；BattleLog/结算面板记录召唤治疗 |
| 1.30 | 2026-06-28 | SummonData 数据化召唤配置：新增 scripts/data/summon_data.gd 与 data/summons/amiya_tactical_echo.tres；SkillData 增加 summon_data 引用；SkillAction 优先使用 SummonData.to_payload；AssetLibrary 增加 summon 缓存；SummonedUnit 的 AI 行动包、伤害类型/倍率、索敌范围和体力消耗改为数据驱动；Bootstrap 按 max_per_owner / limit_policy 执行召唤上限 |
| 1.29 | 2026-06-28 | 召唤物自动行动与指令限制：SummonedUnit 增加专属 AI 和 is_player_controllable=false；TurnManager 自动驱动召唤物回合；Bootstrap/HUD 排除召唤物手操入口；同一施法者开发期最多保留 1 个召唤物，重复召唤替换旧召唤物；召唤物被击倒时直接退场并清理回合/Grid 状态 |
| 1.28 | 2026-06-28 | 技能召唤物生命周期竖切：新增 SummonedUnit；SkillData/SkillAction 支持技能请求召唤；Bootstrap 生成战术投影、注册网格与回合参与者，并按轮数或战斗结束清理；TurnManager/BattleState 支持移除参与者；BattleLog/结算面板记录召唤与退场 |
| 1.27 | 2026-06-28 | TerrainData 正式地形类型：新增 TerrainData 和 data/terrain；AssetLibrary 支持地形加载；TerrainRegion 通过 terrain_id 引用地形类型并提供 override_* 灰盒覆盖；dragon_outer 改为引用正式地形类型 |
| 1.26 | 2026-06-28 | 地形触发状态效果：TerrainRegion/GameGrid3D 支持 hazard_status_effect_id；MoveAction 入格时应用地形状态并写入 terrain_trigger；dragon_outer 源石污染区触发法术灼烧 |
| 1.25 | 2026-06-28 | 危险地形与环境伤害记录：TerrainRegion 支持 hazard_damage/hazard_source；GameGrid3D 存储危险格；MoveAction 进入危险格时结算环境伤害并写入 BattleLog；dragon_outer 增加源石污染危险区 |
| 1.24 | 2026-06-28 | 战斗复苏道具与 BattleLog 记录：ItemData 增加 revive_hp；ItemAction/Unit 支持复苏倒下友方；TargetingController 和 Bootstrap 允许选中倒下友方作为道具目标；BattleLog/结算面板记录复苏次数 |
| 1.23 | 2026-06-28 | BattleLog 状态效果记录：StatusEffectContainer 上报状态应用/刷新/叠层/移除/过期；StatusEffectInstance 上报持续伤害/治疗 tick；BattleLog 和 BattleResultPanel 展示状态变化统计与描述 |
| 1.22 | 2026-06-28 | BattleLog 行动记录：新增 `scripts/game/turn/battle_log.gd`，将结算汇总和行动 entries 从 Bootstrap 临时字典迁入 Resource；BattleResultPanel 展示按回合生成的行动描述 |
| 1.21 | 2026-06-28 | 战斗结算复盘统计：新增 `EventBus.battle_stat_recorded`，攻击/技能/道具/移动/敌方攻击上报统计；Bootstrap 聚合 `battle_stats`；BattleResultPanel 显示伤害、治疗、资源、击倒和关键记录 |
| 1.20 | 2026-06-28 | 战斗结算面板独立化：新增 `panel_battle_result.tscn` / `BattleResultPanel`，HUD 只负责转发显示隐藏，结算格式化逻辑迁出 `hud_battle.gd` |
| 1.19 | 2026-06-28 | 战斗道具快速使用竖切：新增 ItemAction、罗德岛急救包、AssetLibrary item/effect 加载、HUD 道具按钮和 Q 快捷键；道具目标复用 TargetingController |
| 1.18 | 2026-06-28 | 技能表现占位与范围提示：新增 EventBus.skill_used 和 SkillEffectPresenter；技能释放后生成施法/命中标记、伤害数字和 AOE 范围提示 |
| 1.17 | 2026-06-28 | 技能差异化效果与状态闭环：SkillAction 支持自我 buff、目标状态和 AOE 目标收集；新增法术灼烧状态；技能 3 改为小范围伤害；状态属性修正过期时可撤销 |
| 1.16 | 2026-06-28 | 技能 2/3 与运行时冷却：新增阿米娅技能 2/3 SkillData；新增 SkillCooldownTracker；SkillAction 成功后设置冷却；HUD 显示剩余 CD 并禁用冷却中的技能 |
| 1.15 | 2026-06-28 | 三技能槽 HUD 骨架：SkillRegistry 支持按干员+槽位查询；Bootstrap 泛化技能槽执行；HUD 增加 3 技能按钮、SP/CD 展示和状态效果面板 |
| 1.14 | 2026-06-28 | 结构化战斗结算反馈：Bootstrap 输出 encounter_resolution；HUD 结果面板分区展示奖励、任务更新和世界状态变化，并标记重复完成不重复发奖 |
| 1.13 | 2026-06-28 | 编辑器地形区域自动入网格：新增 TerrainRegion；MapInstance 初始化时先采集场景内 TerrainRegion，再应用 MapManifest 手写地形覆盖；dragon_outer 增加开发期慢速/阻挡区域 |
| 1.12 | 2026-06-28 | 战斗显式目标选择：新增 TargetingController，战斗左键点敌人锁定目标、点空格继续路径移动；普攻/技能优先使用已选敌人 |
| 1.11 | 2026-06-28 | MapManifest 地形成本配置：新增 terrain_move_costs / terrain_blocked_cells，MapInstance 初始化时写入 GameGrid3D；dragon_outer 增加开发期高成本格和阻挡格 |
| 1.10 | 2026-06-28 | 地形移动成本接口：GameGrid3D 支持按格移动成本/阻挡格；MoveAction 按目标格成本扣体力；PathPreviewController 按成本寻路 |
| 1.9 | 2026-06-28 | PathPreviewController 抽取：鼠标地面投射、BFS 路径生成和 3D 路径预览渲染迁入 L2 选择/路径模块 |
| 1.8 | 2026-06-28 | InputRouter 输入路由：新增 BootstrapInputController，REALTIME/COMBAT_TURN 输入由注册式处理器分发，Bootstrap 不再直接实现 `_unhandled_input` |
| 1.7 | 2026-06-28 | SquadController 抽取：小队成员、主控切换、跟随队形和主控阵亡自动接管迁入 L2 小队控制模块 |
| 1.6 | 2026-06-28 | 开发期主控切换：实时探索支持 1–4 切换主控，跟随队形改为围绕当前主控重排 |
| 1.5 | 2026-06-28 | 开发期 4 人小队数据化：新增医疗/近卫/重装 ClassData 与 3 个独立 OperatorData，Bootstrap 编队不再复用阿米娅 |
| 1.4 | 2026-06-28 | 开发期 4 人小队：Bootstrap 生成主控 + 3 支援单位，实时探索按队形跟随 |
| 1.3 | 2026-06-28 | 实时输入：WASD 单格移动、右键按路径移动，战斗保留左键路径移动 |
| 1.2 | 2026-06-28 | 战斗结算面板：HUD 显示胜负、回合数和 EncounterData 奖励文本 |
| 1.1 | 2026-06-28 | HUD 技能按钮：显示技能费用/SP 状态，按钮触发 request_use_action |
| 1.0 | 2026-06-28 | EncounterData 扩展：回合波次、胜利奖励、世界 flag 与任务状态写入 |
| 0.9 | 2026-06-28 | 鼠标选格与路径预览：Bootstrap 支持悬停预览路径，左键按路径移动 |
| 0.8 | 2026-06-28 | 实时警戒触发：主控干员进入 EncounterData trigger 范围后切入遭遇战 |
| 0.7 | 2026-06-28 | EncounterData：遭遇资源接管敌人出生、战斗范围与胜负条件 |
| 0.6 | 2026-06-27 | 地图遭遇配置：MapManifest.enemy_spawns 接管 M0 敌人出生点 |
| 0.5 | 2026-06-27 | M1 技能竖切：新增 SkillAction、SP 跨回合保留、S 键释放阿米娅技能 1 |
| 0.4 | 2026-06-27 | M0 网格移动：新增 MoveAction、方向键移动、Grid 占用维护 |
| 0.3 | 2026-06-27 | M0 数据驱动化：新增 EnemyData、敌人 .tres、可复用 hud_battle 场景 |
| 0.2 | 2026-06-27 | 对齐 M0 可玩竖切：首张地图、开发 HUD、自动遭遇战、普攻胜负闭环 |
| 0.1 | 2026-06-27 | 首版：四层架构 + 世界控制 + 游戏逻辑 + 资源复用 + 实施路线 |

---

*本文档为活文档，随开发推进持续更新。任何架构决策变更应先在此文档讨论。*

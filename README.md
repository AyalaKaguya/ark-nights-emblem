# 黄昏旅邸：方舟原地图 Web RPG 原型

独立 Babylon.js + TypeScript 网页小游戏。使用本机《明日方舟》PC 客户端的
2026 夏活 `ark_odc_act53side_main` 原场景、原模型、贴图与摆位，搭配公开上游
Spine 干员，完成探索、交互、遭遇战、胜利继续探索和失败重试。
没有迁移或参考本地 Godot 游戏逻辑。

界面采用队伍 RPG 布局：左侧纵向人物肖像、底部圆形当前人物与两排动作槽、
顶部先攻肖像、右上圆形地图。头像、技能、物品、职业图标和框纹理均来自
方舟客户端，小地图由本项目使用的原地图离屏俯视生成。没有使用参考截图中的
博德之门美术素材。来源见 `UI_ASSET_SOURCES.md`。

界面移除了教程、操作提示、任务引导、默认文字日志和原型声明；保留必要的
按钮名称、剧情、角色姓名、生命和回合数据。图标按钮保留无障碍名称。

## 运行

需要 Node.js 24。依赖使用精确版本并提交 `package-lock.json`。

```powershell
npm ci
npm run dev
```

打开终端显示的本地地址（默认 `http://127.0.0.1:5173/`）。

```powershell
npm run typecheck
npm test
npm run test:e2e
npm run build
npm run preview
```

E2E 使用本机 Edge，并在检测到 Chrome 时一起运行；无需把浏览器状态、账号或
游戏客户端交给自动化。源码只读开发诊断供 UI 测试定位，生产构建不提供诊断。
`dist/` 是静态网站，需要 HTTP 服务；资源使用相对基础路径，可部署在子目录。

## QA 产物

从仓库根目录运行命令。QA 产物统一放在 `.qa/`，整目录由 Git 忽略：

| 目录 | 内容 |
| --- | --- |
| `.qa/screenshots/` | E2E 流程及不同窗口尺寸的截图 |
| `.qa/playwright/results/` | 失败截图、追踪与测试附件 |
| `.qa/playwright/report/` | Playwright HTML 报告 |
| `.qa/cache/vitest/` | 单元测试缓存 |
| `.qa/extraction/hotel/`、`.qa/extraction/ui/` | 素材盘点、QA 拼图、提取与校验报告 |

`npm run test:e2e -- --project=edge` 会生成截图与浏览器测试报告。
提取脚本的 `--out` 指定游戏素材目录，`--qa-out` 可指定诊断输出目录。
手工验收记录、临时探针和调研数据也放在 `.qa/` 下。

## 操作

- 左键地面：预览 / 移动；左键角色：选取或指定攻击目标。
- 右键拖动：镜头环绕与俯仰；滚轮：平滑缩放。
- WASD / 方向键 / 中键拖动：自由平移镜头；F / 聚焦按钮：恢复角色跟随。
- E：附近交互；Esc：取消探索移动、待执行指令或关闭弹窗。
- 下方圆形交互按钮依次前往接待、补给和庭院；左侧肖像选择角色。
- 动作栏的“常用 / 物品 / 被动”切换内容，右上地图按钮调整缩放。
- H 或菜单按钮打开暂停菜单，可继续、重玩已触发的遭遇或返回标题。
- 战斗每回合 9 米移动、1 主要动作、1 附赠动作。可以移动、攻击、再移动。
- “疾走”消耗主要动作增加 9 米；“撤离”免本回合机会攻击。
- “振作”使用附赠动作恢复 6 生命，每人每战一次。
- 演出速度 1× / 3× / 跳过只改变表现，不改变战斗结算。

## 实现边界

原地图的静态建筑、原纹理和原导航面已使用实际客户端资源。接待点、补给点、
对话、编队与遭遇战是此原型新设计，不能称为原作剧情或交互复刻。
原 Unity 特殊水面、粒子、风车动画和所有后处理尚未一比一复刻。
本场景导出的两台相机是阴影相机，玩家使用独立新实现的自由相机。

角色来自公开 `Ark-Models`：三名干员使用基建动画，攻击 / 技能暂映射到真实
`Interact` 动画；敌人使用真实战斗动画。不是原干员完整战斗动画集。
素材与运行时的来源、固定提交、许可和哈希见 `ASSET_SOURCES.md`。
地图的只读提取、源包哈希、二进制格式与缺失项见 `public/maps/hotel/README.md`。

## 架构

`rules/` 是纯 TypeScript 权威规则：指令预览 / 执行返回新状态及按时间排序的事件。
XState 5 管理加载、探索、对话、战斗、演出和结算。渲染层无法决定伤害或回合。
Recast 从原作导航三角面重建通路，并以动态圆形占位处理人物避让；高度从原面查询。
Babylon 显示合并后的世界坐标模型，避免 Unity 静态批次二次应用变换。
Spine 3.8 共享一个离屏 WebGL 图集，人物位于三维世界并参与深度遮挡。

## 再次提取资源

```powershell
uv venv .venv-tools
uv pip install --python .venv-tools/Scripts/python.exe UnityPy==1.25.4 Pillow numpy
.venv-tools/Scripts/python.exe -X utf8 tools/extract-hotel.py --client "游戏目录/Arknights_Data/StreamingAssets/AB/Windows"
npm run fetch:actors
```

提取脚本仅写本项目输出目录，不修改客户端文件。公开角色下载脚本验证 SHA-256。
《明日方舟》资源版权属于原权利人，与本原型代码和依赖许可分开记录。
当前交付用于本地同人研究，未执行公网发布。

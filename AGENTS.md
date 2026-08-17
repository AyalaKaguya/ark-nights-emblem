# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4 project named `ArkNight-Emblem`. The root `project.godot` file defines the project configuration, including the main scene UID and rendering settings. The current main scene is `node_3d.tscn`, a minimal `Node3D` scene.

- `assets/` stores game assets. Current Spine character assets live under `assets/char_spine/002_amiya/`.
- `bin/` contains the bundled `spine_godot_extension.gdextension` manifest and platform-specific Spine runtime binaries.
- `scenes/` is reserved for reusable `.tscn` scenes.
- `scripts/` is reserved for GDScript or C# gameplay code.
- `.godot/` is editor-generated cache data and should remain untracked.

## Build, Test, and Development Commands

Use Godot 4.7 or newer where possible, since `project.godot` declares the `4.7` feature set.

```powershell
godot --editor --path .
```

Opens the project in the Godot editor.

```powershell
godot --path .
```

Runs the configured main scene.

```powershell
godot --headless --path . --quit-after 1
```

Performs a quick headless load check for project configuration and import errors.

## Coding Style & Naming Conventions

Keep files UTF-8 encoded, matching `.editorconfig`. For GDScript, use Godot defaults: tabs for indentation, `snake_case` for files, variables, and functions, and `PascalCase` for class names declared with `class_name`.

Prefer organizing scenes by feature under `scenes/`, with matching scripts under `scripts/`. Example: `scenes/character/amiya_view.tscn` and `scripts/character/amiya_view.gd`.

Do not manually edit generated `.import` files unless the change is intentional and reviewed with the corresponding source asset.

## Testing Guidelines

No automated test framework is currently checked in. For now, validate changes by opening the project, running the main scene, and using the headless load check above. If tests are added later, place them under `tests/` and document the runner command here.

For Spine asset changes, verify that the `.atlas`, `.png`, `.skel`, `.import`, and `bin/spine_godot_extension.gdextension` paths remain consistent.

## Commit & Pull Request Guidelines

No Git history is available in this workspace, so there is no existing commit convention to preserve. Use concise, imperative commit messages such as `Add Amiya Spine scene` or `Fix Spine extension path`.

Pull requests should include a short description, the affected scenes/assets, manual validation steps, and screenshots or recordings for visible scene or animation changes. Mention any Godot version or platform-specific runtime changes.


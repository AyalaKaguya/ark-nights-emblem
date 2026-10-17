# UI artwork provenance

The interface uses original **Arknights** artwork from the locally installed PC client. Its layout may follow a party RPG pattern, but no Baldur's Gate 3 images, icons or frames were extracted or included.

The client source root on this machine is `C:\Program Files\Hypergryph Launcher\games\Arknights\Arknights_Data\StreamingAssets\AB\Windows`. The extractor reads selected bundles and writes only to this repository. It does not modify game files, read account data or read authentication configuration.

## Fixed runtime files

The authoritative asset manifest is **`public/ui/manifest.json`** (URL `/ui/manifest.json`). It contains each PNG's source bundle, original Sprite name, original object path ID, dimensions, PNG SHA-256, original nine-slice border and semantic adaptation note. Each source bundle also has its relative path, byte length and SHA-256. There is no separate `source-manifest.json` for UI assets.

| URL group | Files | Source |
|---|---|---|
| `/ui/portraits/` | `amiya.png`, `hoshiguma.png`, `ansel.png` | Original default operator avatar Sprites from `spritepack/ui_char_avatar_8.ab` and `_9.ab`; 180 × 180 |
| `/ui/portraits/` | `melee.png`, `ranged.png` | Original `enemy_1002_nsabr` / `enemy_1003_ncbow` from `spritepack/icon_enemies_0.ab`; 160 × 160 |
| `/ui/skills/` | `amiya.png`, `hoshiguma.png`, `ansel.png` | Original Amiya S2, Hoshiguma S2 and common healing enhancement alpha from `spritepack/skill_icons_0.ab` / `_1.ab`; 128 × 128 |
| `/ui/icons/` | `move.png`, `attack.png`, `dash.png`, `disengage.png`, `rally.png`, `interact.png`, `inventory.png`, `passive.png`, `end-turn.png`, `focus.png`, `menu.png`, `speed.png`, `pause.png`, `cancel.png`, `defense.png`, `block.png`, `resistance.png`, `time.png` | Original battle/common UI symbols; `attack.png` is a 128 × 128 common attack enhancement alpha skill icon |
| `/ui/professions/` | `caster.png`, `tank.png`, `medic.png`, `melee.png`, `ranged.png` | Original Caster, Defender, Medic, Guard, Sniper profession icons |
| `/ui/frames/` | `skill.png`, `portrait.png`, `battle-menu.png`, `character-menu.png`, `rectangle.png`, `rectangle-triangle.png`, `circle.png`, `ring.png`, `skill-panel.png`, `info-panel.png`, `round-panel.png`, `item.png`, `talent.png` | Original battle/common UI frame and background Sprites |
| `/ui/items/` | `rally.png`, `supply.png`, `food.png`, `currency.png`, `material.png`, `manual.png` | Original `ap_supply_lt_60`, `ap_supply_lt_120`, `ap_supply_lt_100_2025_5` (sandwich), `GOLD`, `MTL_GOLD1`, `MTL_SKILL3` |

The current set is 50 PNG assets from 11 targeted bundles. The extractor can generate `public/ui/contact-sheet.jpg` as a local QA overview; this temporary image is ignored by Git. `/ui/validation.json` records independent PNG decoding, size and hash checks.

## Adaptation boundaries

- RPG action semantics are new prototype mappings. The source game does not provide native DnD Move, Dash, Disengage, Rally or End Turn buttons. The manifest identifies which original direction/stat/retreat/play symbol represents each action.
- `disengage.png` uses the original **text-free running retreat symbol**. `cancel.png` uses the original **text-free X symbol**. The candidates containing `QUIT` and the embedded cancellation prompt were excluded and removed.
- `attack.png` is the original large attack enhancement alpha skill illustration, not a newly drawn sword. The original skill's gameplay is not inherited.
- Only `items/rally.png` may represent the prototype's existing Rally command. The other five item images are inventory presentation slots with no new gameplay effect. Original AP-supply, LMD and material mechanics are not implemented by displaying those images.
- All images are cropped from original Sprite data through UnityPy. No AI-generated or hand-drawn image is presented as original game artwork. CSS tinting, clipping, borders and layout remain interface styling.
- Frame Sprites are the original game frames, not BG3 frames. Several source images are rectangular/diamond rather than circular; choose appropriate clipping or nine-slice treatment in CSS rather than claiming the source has a matching RPG HUD.

## Reproduce

```powershell
web/.venv-tools/Scripts/python.exe -X utf8 web/tools/extract-ui.py
```

Dependencies are already in `web/.venv-tools`: UnityPy, Pillow, numpy, lz4. The script imports the sibling map extractor's Arknights LZ4AK decoder; its upstream BSD attribution is in `tools/LICENSE-Ark-Unpacker.txt`. No unrelated client bundles are bulk-extracted.

## Rights

Arknights characters, icons, art, sprites and UI imagery belong to Hypergryph and their respective rights holders. Neither the repository's code license nor this local extraction grants redistribution or commercial-use rights to that artwork. The manifest records original source attribution, not a new asset license.

# Public actor assets and runtime provenance

Retrieved directly from public upstream repositories on 2026-10-14. No Godot
project code, local game assets, or Godot runtime files were used by this Web
actor implementation. The initial actor + runtime download is **1,559,015 bytes
(1.49 MiB)** for 17 source files. Per-file source URL, commit, size, retrieval
timestamp and SHA-256 are recorded in
[`public/actors/source-manifest.json`](public/actors/source-manifest.json).

## Arknights model resources

Source: [isHarryh/Ark-Models](https://github.com/isHarryh/Ark-Models), pinned at
[`8a3857c250a5c271429aefa82c660ff35803166e`](https://github.com/isHarryh/Ark-Models/tree/8a3857c250a5c271429aefa82c660ff35803166e).
Each selected model consists of the upstream `.atlas`, `.png` and binary
`.skel`, downloaded without source modification. All five binary skeletons were
parsed using the bundled official runtime and report **Spine 3.8.99**.

| Local role | Upstream directory | Clips verified in binary skeleton | Presentation mapping |
| --- | --- | --- | --- |
| Amiya / 阿米娅 | `models/002_amiya` | `Default`, `Interact`, `Move`, `Relax`, `Sit`, `Sleep` | Idle=`Relax`; movement=`Move`; attack/skill=`Interact` |
| Hoshiguma / 星熊 | `models/136_hsguma` | `Default`, `Interact`, `Move`, `Relax`, `Sit`, `Sleep` | Idle=`Relax`; movement=`Move`; attack/skill=`Interact` |
| Ansel / 安赛尔 | `models/212_ansel` | `Default`, `Interact`, `Move`, `Relax`, `Sit`, `Sleep` | Idle=`Relax`; movement=`Move`; attack/skill=`Interact` |
| Soldier / 士兵 | `models_enemies/1002_nsabr` | `Attack`, `Die`, `Idle`, `Move_Loop` and additional movement variants | Native attack, movement and death animations |
| Crossbowman / 弩手 | `models_enemies/1003_ncbow` | `Attack`, `Combat`, `Die`, `Idle`, `Move_Loop` | Native attack, movement and death animations |

The three party models are **base/facility models**, not front battle models.
This upstream repository does not include the operators' front battle model
set. The prototype visibly plays their real `Interact` Spine clips for skills
and attacks; it does not claim those are the original game's attack clips.
Skill emphasis and damage tint/fade are small procedural presentation effects.
Operator defeat fades the genuine animated base model because no `Die` clip
exists in these three model files. Enemy defeat uses each original `Die` clip.

The upstream README states that Arknights asset copyrights belong to Shanghai
Hypergryph Network Technology Co., Ltd., forbids commercial use and forbids
harm to the copyright holder's interests. Public availability is **not** a
permissive asset license or a grant for commercial redistribution. The current
prototype is a local fan research prototype. External distribution requires
checking the rights holder's applicable terms.

## Spine runtime

Source: [EsotericSoftware/spine-runtimes, branch 3.8](https://github.com/EsotericSoftware/spine-runtimes/tree/3.8), pinned at
[`8b4844bd4b193ba9e54487ed397a777993cbad56`](https://github.com/EsotericSoftware/spine-runtimes/tree/8b4844bd4b193ba9e54487ed397a777993cbad56).
The official precompiled `spine-ts/build/spine-webgl.js` is stored as
`public/vendor/spine-webgl-3.8.js`, unchanged. Its original license text is
stored in `public/vendor/SPINE_RUNTIME_LICENSE.txt` and remains embedded in the
runtime distribution.

Spine runtime licensing is separate from the character artwork. The runtime
license permits evaluation and defines integration/redistribution requirements
under the Spine Editor License Agreement. Shipping a product containing the
runtime to users who do not hold Spine licenses requires the appropriate Spine
license at integration time. See the included license and
[official license terms](https://esotericsoftware.com/spine-runtimes-license).

## Rendering and verification boundary

- One shared 1024×512 offscreen WebGL canvas renders all active Spine skeletons
  into 256×256 cells. Each actor has its own skeleton/AnimationState but **no
  per-actor WebGL context**. The maximum prototype roster is eight active actors.
- PMA atlas textures are drawn with the Spine renderer's PMA flag. Uploading the
  canvas into Babylon's `DynamicTexture` uses the browser's straight RGBA upload
  with conventional alpha blending. A custom unlit shader discards empty pixels,
  tests scene depth and writes visible pixel depth. Actors are world-space
  upright billboards, so opaque hotel walls can hide them correctly.
- Model height comes from measured Spine idle bounds; feet are anchored at the
  ground. Movement facing mirrors the visual according to camera-relative travel
  direction. UI labels and selection rings are world meshes with separate 2D
  canvases, not additional WebGL contexts.
- Verified in desktop Edge headless/WebGL2: all five binary skeletons parse,
  the three party bodies render with transparent edges, and the shared drawing
  buffer contains animation pixels in the expected three cells, with no WebGL
  error. Full gameplay browser verification is maintained by the main prototype.
  This is not a claim of exact original battle-animation or hotel-layout fidelity.

## Re-fetch / verify

`node tools/fetch-actors.mjs` re-fetches the same pinned public source files and
rebuilds the source manifest, with a 30 MiB safety limit and bounded retries.
`node tools/fetch-actors.mjs --verify` checks every downloaded file's bytes and
SHA-256 without accessing the network. No `.skel` conversion or version-header
rewriting was necessary.

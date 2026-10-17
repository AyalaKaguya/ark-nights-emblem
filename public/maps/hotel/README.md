# Local client scene extraction

This directory contains the actual `ark_odc_act53side_main` scene exported read-only from the locally installed Arknights PC client. The source bundles were not modified. Source files are under `Arknights_Data/StreamingAssets/AB/Windows/scenes/arkvent/ark_odc_act53side_main`, `arts/maps/map_arkodc`, and the common Arkvent prop bundle.

On this machine the read-only source root is `C:\Program Files\Hypergryph Launcher\games\Arknights\Arknights_Data\StreamingAssets\AB\Windows`. `source-manifest.json` stores relative source names, lengths and SHA-256 hashes instead of embedding this machine-specific absolute path into the runtime map.

The game assets remain the property of Hypergryph. They are not covered by the prototype source code's license.

## Reproduce

```powershell
web/.venv-tools/Scripts/python.exe -X utf8 web/tools/extract-hotel.py
```

Dependencies: UnityPy 1.25.4, Pillow, numpy, lz4. The extractor registers Arknights LZ4AK decompression without rewriting the source files. Its compression routine carries the BSD notice in `web/tools/LICENSE-Ark-Unpacker.txt`.

## Loader contract

- `scene.json` contains the full scene geometry, 2,624 original renderer records, materials, original PNG textures, eight lightmap pairs, the authored navigation source mesh, hierarchy, trigger volumes, and the two serialized cameras.
- Production loading uses `scene-runtime.json` (about 2.3 MB) and `geometry.bin` (about 31.4 MB). Each mesh attribute is `{offset, length, kind}`: a 4-byte aligned byte offset, element count, and `float32`/`uint32`, little-endian. Use typed-array views of the downloaded ArrayBuffer. `runtime-validation.json` records a complete binary round-trip comparison against `scene.json`. `--runtime-only` regenerates these two payloads from the existing full JSON.
- `meshes` are merged by original material, lightmap page and active state. `positions` and `normals` are already **world coordinates**, Unity left-handed, Y-up, metres. Apply them directly in Babylon. Do not reapply any original instance matrix.
- Each mesh has flattened `positions` (3), `normals` (3), `uv` (2), `uv2` (2), `colors` (4), and triangle `indices`. `uv2` has each original renderer's lightmap scale/offset applied unless it was already baked by Unity static batching.
- `instances` retain the original names, hierarchy, world bounds and source matrix (16 values, **column-major**) for provenance and selective occlusion. Their `ranges` point to index ranges inside the merged draw chunks.
- Material `textures` map Unity shader slots to local URLs. Material floats, colors and texture transforms remain available. The special water, wind animation and particle shaders need a browser rendering adaptation; a PNG alone does not reproduce them.
- Lightmaps preserve raw Unity RGBM via `path`, and a gamma encoded RGB light multiplier via `decodedPath`. The decoder uses `L = RGB * (5 * A)^2.2`, clamped to a range of 1 for a conventional lightmap texture. Raw data remains available for an HDR shader.
- `navigation[0]` is the original scene's `Navmesh` source geometry transformed to world coordinates (966 vertices / 1,000 triangles, origin `[0,0,0]`). Its upward floor faces have positive Y normals. Rebuild a Recast mesh from this geometry and query floor height for moving characters.
- All 19 exported BoxColliders are **trigger-only DitherGroup occlusion volumes**, not physical barriers. They should not be used as solid navigation obstacles.
- The serialized cameras are `SpineCam` and `ShadowCam`. Neither is the main player view. The `scene_data.ab` bundle contains NavMeshData and occlusion data; it does not supply the player camera configuration.

`play-suggestions.json` contains floor face centres for prototype spawns, interaction markers and a battle encounter. These gameplay meanings are new additions, not original game interaction metadata. The hotel/region boundary still needs comparison with the original scene in-game.

`interest-points.json` retains the original water renderer bounds, smoke emitter transforms, water shader colors/floats, entrance objects and candidate building cluster. Numeric object names do not explicitly label a hotel: the strongest locator is `S_outworld_billboard24` (GO 2609), whose UV triangles overlap the original atlas' MOTEL sign and frame. Its world bounds are x 26.668–32.515, z 22.844–23.422. Confirm this sign visually in the restored scene before assigning a hotel-region label.

`validation.json` records an independent reread of array lengths, finite numbers, index bounds and local texture files. Rendering appearance and custom shader fidelity require a separate browser check. The extraction report lists the remaining missing dependencies (three waterwheel flow textures); all 2,624 original mesh renderers are present.

# Asset production on this laptop

Updated 16 September 2026 after the user's production-pipeline change. Tripo MCP and its Blender add-on are now installed; authentication and generated-model quality have not been verified. The local reconstruction research below is retained as historical context.

## Recommended baseline

Use **approved concept art → hosted Tripo generation → Blender inspection and cleanup → GLB → Godot**. The user rejected repeated hand-authored meshes and textures as both insufficient in quality and too costly in agent tokens. Stop autonomous handmade-model iterations and their subagents. Preserve current assets until replacements are checked. Blender is for focused cleanup, scale, rigging, collision and export, not another full manual reconstruction pass. Start with a small representative pilot to measure reference fidelity, texture quality, mesh usability and credit cost before broad production. See [Tripo setup](../../docs/tripo-setup.md).

Blender lists 8 GB minimum RAM and 2 GB minimum VRAM for Windows/Linux, with higher recommended specifications. These are application requirements, not a budget for arbitrary scenes. Blender binaries use GPL; the Blender Foundation says artwork and saved data remain the creator's property. [Requirements](https://www.blender.org/download/requirements/), [license and artwork](https://www.blender.org/about/license/)

## Small reconstruction candidates

| Candidate | Primary-source findings | Decision |
|---|---|---|
| **TripoSR** | Single-image reconstruction; MIT covers source and pretrained model. Official default is about **6 GB VRAM**. Its script exposes smaller extraction chunks, mesh resolution, optional texture baking and CPU fallback. | First optional trial. Reduce extraction chunk size and resolution; start with vertex colors and no preview video. A lower setting is an experiment, not a verified memory guarantee. [Official repository](https://github.com/VAST-AI-Research/TripoSR), [controls](https://github.com/VAST-AI-Research/TripoSR/blob/main/run.py) |
| **Stable Fast 3D** | About **6 GB VRAM** by default; UV textures, material prediction and optional remeshing. First-party ComfyUI nodes/workflow exist. Weights are gated; Windows support is experimental and lists VS 2022. | Second trial if access, dependencies and memory permit. Useful textured output, but automatic remeshing is not an animation-ready rig. [Official repository](https://github.com/Stability-AI/stable-fast-3d) |

SF3D uses the **Stability AI Community License**, with commercial registration, an annual revenue threshold and use/distribution terms. Record the license/model revision and evaluate its terms before production. [License](https://github.com/Stability-AI/stable-fast-3d/blob/main/LICENSE.md)

No smaller third model was verified as a better fit. **SPAR3D is deferred**: its explicit memory section reports roughly 10.5 GB normally and 7 GB in low-VRAM mode. That is already above a hypothetical 6 GB device; the actual laptop VRAM still needs checking. Larger Hunyuan/TRELLIS pipelines are outside this initial plan. [SPAR3D requirements](https://github.com/Stability-AI/stable-point-aware-3d#low-vram-mode)

## ComfyUI workflow plan

After art approval, inspect existing local nodes/workflows before adding dependencies. SF3D supplies an [official example](https://github.com/Stability-AI/stable-fast-3d/blob/main/demo_files/workflows/sf3d_example.json). TripoSR has a separate experimental [Flowty wrapper](https://github.com/flowtyone/ComfyUI-Flowty-TripoSR), licensed GPL-3.0; its wrapper license differs from the model's MIT license.

Run one object and one reconstruction model at a time. Separate image preparation, reconstruction and Blender cleanup; unload models between stages. Start with modest extraction detail and 512–1024 texture tests, record peak RAM/VRAM, and stop increasing settings before memory pressure causes paging. CPU fallback trades GPU demand for system RAM and time; it is not automatically economical. Close the game/editor and other heavy GPU tasks during a trial.

**Tool status:** discovery exposes callable Blender and ComfyMCP functions. Live connections were not tested; application and model availability remain unverified.

## From approved image to usable asset

The multi-view concept sheets are design references. A single-image reconstructor should receive **one isolated object in one clear three-quarter view**, with plain/removed background, uncropped silhouette, even light, and no captions, inset views, scenery or cast spell effects. Keep the other approved views alongside it for manual checking; passing several independent images is not automatically multi-view fusion.

Inspect every generated mesh against the sheet: backside shape, limb count, thin fins, robe thickness, separated accessories and scale. Then repair geometry, retopologize deformation areas, create/clean UVs, simplify materials, remove painted-in lighting where necessary, make LODs, rig and weight animated parts, author simple collision, and check pivots/sockets. Export a small test asset to Godot and verify shading, orientation, animation and collision. A generated textured mesh is an intermediate asset, not a completed game character.

Keep the source image, model/node versions, license, settings, raw mesh and cleaned Blender file together. No local performance or output-quality claim has been established yet.

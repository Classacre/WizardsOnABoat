# Tripo asset workflow

## Current production route: image references and art book

The user has a Tripo Studio subscription. The configured API key authenticated successfully on 16 September 2026, but its API balance was 0. [Studio and API credits are separate](https://www.tripo3d.ai/help/api-plugins/tripo-studiotripo-api). The user has now requested individual model reference images and a showcase PDF instead of submitting generation jobs. Do not require an API top-up or purchase credits. The installed MCP and CLI are retained.

The user has authorized replacing every existing 3D model using Tripo, with usable rigs for animation. `preproduction/tripo/replacement-manifest.json` tracks all 30 current GLBs. Pose and palette variants of the wizard share one generated base and skeleton. No new modeling subagents or repeated handmade mesh generation.

The clean single-subject wizard reference is `preproduction/tripo/inputs/wizard.png`. Use one isolated subject image per generation. Do not upload the complete turnaround boards to a single-image reconstruction job. Characters and creatures need weighted deforming skeletons; rigid props need root/hinge controls where applicable, while sails and vegetation need appropriate deformation controls. Verify actual skeletons, weights and motion in Godot before marking an asset complete. A static transform or an auto-rig request alone is not evidence of a working character rig.

As of this update, no Tripo model has been generated or replaced. The current deliverables are under `preproduction/model-references`, `output/art` and `output/pdf`. Each subject is a complete object in one view; use Tripo's segmentation stage for components rather than making exploded-part input images. A complete boat reference covers both the hull and sail assets. The exact image prompts and the existing-model coverage map accompany the reference pack.

## Installed and verified

- Official [Tripo MCP](https://github.com/VAST-AI-Research/tripo-mcp), package 0.1.2, installed into `.tools/tripo-venv` from `.tools/tripo-mcp`.
- Official [Blender add-on](https://developers.tripo3d.ai/en/docs/plugins), version 0.7.3, enabled in Blender 5.2.2 LTS as `tripo3d_blender`.
- Global Codex MCP server `tripo3d` launches `D:\AI\WizardsOnABoat\.tools\tripo-venv\Scripts\tripo-mcp.exe`.
- Real MCP initialization, enumeration of 16 tools, and a read-only Blender scene query passed. Image generation, task-status and GLB-import tools are present. Existing Blender MCP remains available on port 9876.
- No generation was submitted and no generation credits were spent during setup. The API key was subsequently configured and its read-only balance query succeeded (0 available credits). Generation quality remains untested.

## Connect your account

1. Obtain a key from [Tripo API keys](https://platform.tripo3d.ai/api-keys).
2. In Blender's 3D viewport press **N**, choose **Tripo Model Generator**, enter the key in its masked **API_KEY** field and click **Confirm**. Do not paste keys into chat or project files.
3. The Tripo server is running now. After reopening Blender, use **Start MCP Server** in this panel, with port **9877**.
4. Reload Codex if the newly registered `tripo3d` tools are not listed in the current session.

## Compatibility adjustments

The upstream add-on reuses Blender MCP operator names and port 9876. `tools/prepare_tripo.py` prepares a local ZIP with a separate `tripomcp` namespace and port 9877, and points the MCP process at that port. It also marks the password property `SKIP_SAVE` so shared `.blend` files do not serialize it. The add-on's local credential confirmation/storage mechanism otherwise remains upstream behavior.

The upstream MCP imports FastMCP v1. Its unbounded dependency installs an incompatible MCP v2, so the environment uses `mcp[cli]<2` (resolved to 1.30.0) and `tripo3d` 0.4.2. These are compatibility fixes, not a replacement custom generator. Upstream add-on updates require reapplying the namespace/port adjustment. The official integration is older than Tripo's newer CLI; check supported generation models and options before committing credits to a production batch.

Read-only verification from the project directory:

```powershell
.tools/tripo-venv/Scripts/python.exe tools/check_tripo.py
codex mcp get tripo3d
```

## Production direction

Use the approved art as the source of truth. Supply isolated subjects without captions or multiple objects for single-image generation; use separate consistent views only with an explicitly supported multiview workflow. Do not feed an entire concept montage to a single-object reconstruction call.

Evaluate a wizard and a creature before scaling production. Compare silhouette, palette, painted lighting, backsides, thin parts and deformation areas. Use Blender for necessary mesh/material cleanup, scale, pivots, rigging and LODs, then export GLB for Godot. Check the imported asset under the game's real lighting. Hosted generation reduces local inference memory needs, but generated meshes still need a sensible polygon and texture budget.

Handmade asset iteration and its subagents are stopped at the user's request. Existing game files and assets are retained. No game or model iteration should resume as part of this installation task.

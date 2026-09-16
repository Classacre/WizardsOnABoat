# Tripo replacements

This directory tracks the user's request to replace all existing 3D assets with textured Tripo-generated assets and usable animation rigs. Generation uses the user's Tripo Studio subscription through the browser. The API balance is separate and was 0 at the last read-only check.

`replacement-manifest.json` includes every existing GLB path and its approved-art reference, planned rig and replacement group. All 30 paths remain pending; the five wizard pose/palette files can use one generated character and skeleton, giving 26 unique generation groups. Original files stay in place until their replacements pass review and import checks.

`inputs/wizard.png` is a single front-view wizard prepared using the built-in image-generation tool from approved `art/01-wizard.png`. It contains one character in an A-pose, with hands free for rigging. `input-prompts.json` records the exact preparation prompt. No multi-view montage is submitted to single-image reconstruction.

Completion requires a downloaded Tripo output, source job identifier, texture inspection, an appropriate rig with checked weights/pivots, a motion test, preserved game scale/orientation, and a successful Godot import. Generated meshes and textures must come from Tripo; Blender is for focused cleanup, rig repair, animation, collision and export.

Static rocks and buildings do not require organic deformation. Their root controls support placement; moving doors and lids use separate hinge controls. These should not be presented as equivalent to a fully weighted creature rig.

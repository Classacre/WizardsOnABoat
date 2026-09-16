# Wizards on a Boat

Godot prototype and visual development for a first-person multiplayer game about wizards sharing a boat. The concept art and core design decisions are approved. Model replacement is currently at the image-reference stage: Tripo generation and rigging have not been completed. See [confirmed decisions](preproduction/decisions.md).

## Showcase and model references

- [Concept art book](output/pdf/Wizards-on-a-Boat-Concept-Art-Book.pdf): 62 pages containing the original style board, all 26 approved concept boards, and 51 complete-subject model references.
- [Single-view reference gallery](preproduction/model-references/index.html): open locally in a browser to browse individual PNGs.
- [Reference image pack](output/art/Wizards-on-a-Boat-Model-Reference-Pack.zip): all 51 PNGs, a portable gallery, exact image prompts and the existing-model coverage map.
- [Reference inventory](preproduction/model-references/README.md): complete objects for Tripo; component segmentation happens after generation.

## Open the project

This repository uses Git LFS for artwork, models, native add-on binaries and finished deliverables. Install Git LFS before cloning, or run `git lfs install` followed by `git lfs pull` in an existing clone.

Open `project.godot` in Godot 4.7.2. The Windows launchers use a local engine at `.tools/godot/Godot_v4.7.2-stable_win64.exe`; engine downloads and local tool environments are not part of the repository. Godot regenerates its `.godot` import cache when the project opens.

## Design and research

- [Review the illustrated collection](preproduction/index.html): open locally in a browser, filter by category, inspect full-size sheets, and save per-board decisions/notes. Use Export review to save a JSON copy; browser notes are not automatically sent to the assistant.
- [Design plan](preproduction/design-plan.md): requirements, visual direction, world/creature roster, spell/economy design, technical candidates, and staged build gates.
- [Art index](preproduction/ART-INDEX.md): direct image links and concise descriptions.
- [Research](preproduction/research/): primary-source findings and proposed adaptations.
- [Exact image prompts](preproduction/prompts/README.md): built-in image-generation prompt archive and style reference.
- [Review validation](preproduction/review-validation.md): what has been checked and the browser-testing limitation.

The supplied style board is treated as visual reference material. Generated concept sheets are proposals, not screenshots of an implemented Godot game or final modeling blueprints.

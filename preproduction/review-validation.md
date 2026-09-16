# Review gallery validation

Checked 16 September 2026. **Source-checked; not browser-tested.**

The automated browser could not open `file:///D:/AI/WizardsOnABoat/preproduction/index.html` because its Browser URL policy rejected local-file navigation. No alternative browser route or local server was used. This prevents a claim of visual, native-dialog, storage-permission, or download verification in a real browser.

## Checks completed

| Area | Evidence |
|---|---|
| Offline structure | CSS and behavior are inline; the manifest is a local classic script. Images and planning documents use relative local paths. No remote scripts, fonts, stylesheets, fetch requests, or tracking calls. |
| Linked documents | All eight document links resolve on disk: design plan, creature research, world/terrain research, magic/multiplayer research, asset pipeline, generation prompt notes, direct art index and creature-sheet review. The reference image link also resolves. External citations inside research documents naturally require internet access to visit. |
| Manifest | The supplied manifest executes and defines 26 boards. The gallery uses its order and categories. All 26 selected PNGs now exist and decode successfully; dimensions, byte sizes and SHA-256 hashes are in asset-verification.json. Selected image data totals approximately 61.1 MiB. The building board points to its corrected v2 image. Missing-image handlers remain available. |
| Review state | Simulated source execution verified status changes, card/lightbox note synchronization, counts, and review restoration from a storage stub. State is keyed by stable board ID. Storage denial displays a warning and leaves export available. |
| Filters and keyboard handlers | Simulated source execution verified category filtering, restoring all boards, previous/next bounds, and arrow navigation. Arrow keys remain text-editing keys in notes. Closing restores the opener's focus. Native Escape handling and modal focus behavior require a real browser check. |
| Export | Simulated source execution verified a valid JSON payload with every board, approval state, notes, timestamps, image path, and an art-review-only notice. The download filename ends in `.json`. Actual browser download completion is unverified. |
| Error states | Simulated source execution verified thumbnail/lightbox image-error handlers, clearing the lightbox error for the next board, and an empty-manifest message with export disabled. |
| Source integrity | Inline JavaScript parses, static element IDs are unique, and accessible heading references resolve. Two missing heading IDs were fixed. The added asset-pipeline and prompt links were preserved. |

The event checks used Node with small in-memory DOM and localStorage stubs, not a browser or a rendered-page test. They created no actual review decisions in a user's browser.

## Handing review decisions back

Open `index.html` with the entire `preproduction` directory kept together. Review controls record **Approve**, **Revise**, or **Undecided**, plus optional notes. These decisions remain in that browser's local storage; **they are not sent to the assistant**. Storage behavior for local files can vary by browser and privacy settings, and moving the gallery may change which saved state is available.

Use **Export review** to download a JSON snapshot, then attach or otherwise share that file in the conversation. If storage is unavailable, keep the page open until exporting. Approving concept boards records art feedback only; game development still waits for the user's explicit instruction to begin.

Remaining manual checks: full and narrow-screen layout, image legibility, actual file loading after the art pack is complete, keyboard focus/Escape, browser persistence after reopening, and a completed JSON download.

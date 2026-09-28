# Little Library

A shared, read-only capability catalogue in the workspace. Click the miniature shelves or **Library** in the scene toolbar. Choose Codex or Claude, search by name or description, filter by kind, and select a book to inspect its metadata. Plugin books list children only when source paths or manifest declarations establish membership.

## Artwork and builds

Original Blender sources and the deterministic export script live in `assets/library/`. Run:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python assets/library/export_library.py
```

The export produces the alcove, closed book, and open book USDZ files in `Sources/DioramaApp/Resources/Library/`. The alcove contains 47,284 triangles and uses no external textures. SceneKit adds the library sign and selected-book emblem. Cover colors are stable across launches and shared by plugin collections.

The Swift Package declares the assets as resources. `build-macos.sh` copies the resource bundle into `Contents/Resources`; the runtime resolves that location explicitly and does not fall back to a developer checkout when running an app bundle. Blender is not needed to run Diorama.

A verified debug app is available at `dist/Diorama-Library.app`. No release was published.

## Discovery

- **Codex:** existing skills, installed apps, and MCP status APIs, plus explicitly configured plugin metadata. A cache directory alone is never treated as installation evidence. Metadata associates apps/tools with plugins only when their declarations are unambiguous.
- **Claude:** scoped local skills and installed-plugin metadata, with settings used to identify disabled plugins. Attached SDK sessions supplement this with commands, tools, plugin metadata, and MCP status. Built-in commands remain separate from skills. Opening the catalogue never creates/resumes a Claude task or sends a prompt.
- Detached Claude items are unverified. Listed workspace capabilities do not guarantee identical access for every subagent, and tool invocation may still require approval. Unsupported or older runtime metadata remains unverified or produces a section error.
- Discovery has its own context-keyed cache, independent of the composer picker. Switching providers/projects invalidates pending presentation updates. Successful sections survive failures in other sections. Refresh bypasses the 60-second cache.

The catalogue is read-only: no installation, configuration changes, invocation, marketplace browsing, or agent book-fetching behavior.

## Validation — 2026-09-26

- `swift test --no-parallel`: **301 tests passed** across 77 suites.
- `node --test helpers/claude/bridge.test.mjs`: **5 tests passed**.
- Native SceneKit tests load every exported model, verify separate library hit targets, selected-book colors, stopped rendering, and one/many-agent layouts.
- Catalogue screenshots cover 380- and 440-point widths, book details, and a 300-item fixture. Snapshot files are in `artifacts/library/`.
- The packaged app was launched from `/tmp`, outside the source checkout, and displayed the bundled library. Native browsing showed 411 Codex entries and 43 local Claude entries; selecting a skill displayed its metadata and matching table-top book.
- Live attached Claude discovery was verified with the mocked SDK helper, not by starting a live Claude task. No prompt was sent for validation.
- A parallel suite run exposed timing contention in existing animation tests; those pass serially. The fixed-size native loading-view fixture now disables intrinsic window resizing, preserving its intended 760×600 viewport.

UI accessibility includes a labeled toolbar alternative to the 3D hit target, semantic book buttons, searchable names, textual availability, focus restoration, and reduced-motion behavior. Escape handling returns from details before closing the library. Full interactive VoiceOver navigation was not exercised.

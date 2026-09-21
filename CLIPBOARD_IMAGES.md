# Clipboard images — Diorama 0.3.9

Paste a copied image or screenshot with Command-V while the message composer has focus. Both new tasks and existing conversations use the native editor. Plain text paste, multiline editing, and Command-Return to send are retained.

PNG and TIFF clipboard representations are converted to PNG and stored under `~/Library/Application Support/Diorama/Pasted Images`, with private directory/file permissions. The composer adds a removable image attachment using the same official Codex `localImage` input as the attachment picker. Changing the clipboard does not invalidate the image. Local copies are retained for retries and recorded image paths; removing a draft attachment does not delete its saved copy. There is no automatic pruning yet.

Image input is limited to 20 MiB, 40 megapixels, and 20 attachments per message. Invalid image data shows an inline error and does not replace the draft. Finder file copies are left to standard paste handling, avoiding accidental attachment of the file icon. Clipboard images in formats other than PNG/TIFF need to be saved and attached through the file picker.

Validation: 23 targeted attachment/execution/rendering tests passed before the final Paste-menu refinement. After that refinement, all 5 clipboard/native-paste/rendering tests passed. Tests use isolated pasteboards and leave the user's clipboard unchanged. A native composer fixture was rendered and inspected at 520 points. Live model image input uses the existing verified `localImage` path; no new live model request was needed for this UI change.

Build recovery: macOS had offloaded both source and build files. Sources were downloaded using Foundation's ubiquitous-item download API. A clean build used `/private/tmp/diorama-clipboard-build`; `build-macos.sh` now accepts optional `DIORAMA_BUILD_PATH` and `DIORAMA_APP_PATH` locations to avoid offloaded caches/bundles.

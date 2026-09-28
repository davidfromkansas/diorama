# Combined-work checkpoint

This checkpoint saves the accumulated project work on `codex/github-workflow-desktop-local-setup`; it does not declare release readiness.

## Validation

- `swift test --no-parallel`: 364 tests in 91 suites passed.
- `npm test --prefix helpers/claude`: 8 tests passed.
- `node --test assets/capybara-motion/controller.test.mjs`: 10 tests passed.
- Long-history append parsing maximum: 374 ms (unchanged 500 ms budget).
- Thirty watcher/model updates: p95 60 ms, maximum 61 ms.
- Thirty mounted conversation layout updates: p95 59 ms, maximum 70 ms. Pixel latency was not measured.

Logs are in `artifacts/pr-checkpoint/`. Existing older evidence retains its own run results and limitations. The current app source includes later capybara changes; earlier packaged-app smoke evidence does not establish that all later changes were included in that binary.

## Remaining review gates

See `DEEP_PROVIDER_OUTPUTS.md` and `REALTIME_VIEWER.md`: finish independent live client scenarios and visible-pixel timing, resolve or document provider buffering and native-control blockers, investigate sustained CPU behavior, and finish supplemental Paper states. Keep the PR a draft until applicable review and acceptance gates are met.

Generated app builds, dependency directories, the duplicate capybara delivery ZIP, and local probe-ready markers remain excluded from Git. Required editable assets and bundled models are included.

# Codex checklist and delegation availability

Investigation: 2026-09-22.

## Root causes

Diorama previously launched `codex app-server --stdio` with inherited defaults. Two separate tool-registration defaults explain the observed missing tools:

- `tools.update_plan.enabled` is opt-in. `resolve_update_plan_enabled` returns false when the setting is absent. The tool registry adds PlanHandler only when it is true.
- V1 agents default to `agents.max_depth = 1`. Before registering collaboration tools, Codex checks whether the next child depth exceeds that limit. A first-level child therefore cannot spawn a grandchild under the default.
- V2 delegation is different: the V1 depth setting is ignored. Model catalog metadata selects V1/V2 behavior. The bundled catalog marked gpt-6-astra as V2, while gpt-5.5 used the V1 path. These must not be treated as the same capability failure.

Source inspected at upstream revision `bf7c87a7b7bdb1b65cbfdca06d15713d3aa20b01`:

- [Configuration defaults and resolution](https://github.com/openai/codex/blob/bf7c87a7b7bdb1b65cbfdca06d15713d3aa20b01/codex-rs/core/src/config/mod.rs)
- [Tool registration and delegation-depth checks](https://github.com/openai/codex/blob/bf7c87a7b7bdb1b65cbfdca06d15713d3aa20b01/codex-rs/core/src/tools/spec_plan.rs)
- [Configuration schema](https://github.com/openai/codex/blob/bf7c87a7b7bdb1b65cbfdca06d15713d3aa20b01/codex-rs/core/config.schema.json)

A third issue was in Diorama itself: the execution transport rejected `thread/list`, so descendant discovery could not run even after a grandchild existed. That read-only method is now allowed, and the pipe regression test exercises it. Transient discovery failures no longer permanently mark the filter unsupported.

## Fix

Diorama now supplies process-local config overrides when launching its App Server:

```
--config tools.update_plan.enabled=true
--config agents.max_depth=2
```

This makes checklists available and permits two V1 delegation levels. It does not force the model to create a checklist or delegate, does not modify global settings, and does not change permissions or authentication.

## Verification

The strict desktop-runtime probe passed with two completed steps and two agent records forming an explicit parent/child/grandchild hierarchy. Saved child history contained the fixture marker and the journal restored successfully. The normal standalone runtime (0.153.4, gpt-6-astra) also passed the same strict test. Desktop runtime: 65.374 seconds; standalone: 56.757 seconds. The 206-test regression suite passes, including a real pipe check that descendant listing reaches App Server. See `evidence/codex-activity-coverage.json` for completed observations. Prior statements that the runtime simply lacked these capabilities were incomplete: the default tool-registration settings had not yet been checked.

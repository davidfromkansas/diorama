# Skills & connectors loading — 0.3.20 (build 23)

Opening the picker previously forced a skill reload, then fetched installed apps, MCP server pages and the entire remote app directory in sequence. The view eagerly created all rows and used pretty-printed JSON as row identity. This made ordinary capability selection depend on directory size and response time.

The picker now:

- Loads skills, installed apps and MCP status independently, publishing each section as it arrives.
- Reuses successful results for 60 seconds for the same project folder and conversation. Refresh status bypasses that cache and requests fresh skill/app discovery. Changing context clears old results; late responses cannot overwrite the new context.
- Keeps remote directory discovery explicit: Browse app directory requests one page of up to 100 entries; Load more apps fetches the next. Entries merge with installed apps by ID, preserving installed choices on directory failure.
- Uses lazy rows, stable capability identifiers and individual section loading indicators.

Selection, authentication and tool approval behavior are unchanged. A cold opening still depends on local App Server startup and each provider's response; this is not a promise of zero latency. The cache is in-memory and may show availability up to 60 seconds old; use Refresh status after external configuration changes.

Validation: 124 regression tests passed, including cache reuse/refresh/expiry, partial results while skills are held, duplicate-open suppression, late responses after a context switch, one-page directory loading/merging and preservation of usable installed apps on catalog failure. A separate opt-in read-only live probe is available with `DIORAMA_INTEGRATIONS_PROBE=1 swift test --filter IntegrationDiscoveryLiveProbe`; it records controller discovery timings in `evidence/integration-discovery.json`. These timings do not measure native sheet animation or rendered first paint.

Live result: cold discovery completed in 2.724 seconds with 42 skills, 11 installed apps and 5 MCP servers; same-context warm reopen took under 1 ms. No directory request was made and no discovery errors occurred. Production packaging and strict deep signature verification passed. No pre-change timing or on-screen latency comparison was collected.

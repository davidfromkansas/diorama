# Project creation and Desktop discovery investigation

Tested September 19–20, 2026. CLI/App Server: **0.153.4**. Installed Desktop: **26.908.40834 (8881)**, `/Applications/ChatGPT.app`. No Diorama product changes in this investigation.

## Result

Use official experimental **project/create**, then **thread/start with projectId**, rather than expecting a folder under `~/Documents/ChatGPT` to register itself. Both API operations passed live probes. **User-observed Desktop result: BIRCH-7392 appears as a standalone thread under Recents, not inside the created project folder.** Conversation discovery is verified by the supplied screenshot; automatic project grouping did not carry over in this test. API persistence does not establish Desktop project integration.

## Evidence

Local results: `.local/project-discovery/evidence.json`. Relevant generated schemas preserved in `.local/project-discovery/schema/`. Scripts: `scripts/verify_project_discovery.py`, `scripts/verify_project_registration.py`, `scripts/verify_project_create.py`. These are one-off designated probes: folder creation is exclusive and they should not be rerun blindly.

| Capability | Result | Evidence |
| --- | --- | --- |
| Folder automatically registers as a Codex project | Not observed | Neither the empty control nor the folder with a completed conversation appeared in `project/list` before explicit registration. This does not prove all Desktop UI behavior. |
| Conversation created using Diorama's start parameters persists | Verified | Fresh App Server listed/read PINE-4821 and its correct cwd after original server closed. |
| Default thread/list discovers test conversation | Verified | Source reported `vscode`; default and cli/vscode filters included it, appServer filter did not. Do not infer source category from transport name. |
| Register existing folder/conversation via project/import | Verified | Returned project ID and thread/read returned matching projectId. |
| Retry project/import with same idempotency key | Verified | Returned same project ID, no duplicate test project. |
| Create project via project/create | Verified | Returned new project with requested name and root. |
| New conversation assigned via thread/start.projectId | Verified | BIRCH-7392 conversation returned and persisted matching projectId. |
| Read projects/assigned conversation after server restart | Verified | Fresh project/read and thread/read returned matching IDs, cwd, and history. |
| New conversation displays in Desktop | Verified by user | Screenshot shows BIRCH-7392 selected under Recents, with the expected prompt and response. |
| Created project grouping displays in Desktop | Not observed in tested workflow | User reports a standalone thread rather than a project folder. Screenshot corroborates standalone placement under Recents. Cause and behavior after Desktop restart remain unverified. |
| Empty-folder autoimport or registered-project refresh after Desktop restart | Unverified | Desktop was not restarted. |

The installed binary's `app-server generate-json-schema --experimental` includes project/list, read, create, import, update, move, and delete. They are absent from the schema generated without `--experimental`. Requests used `capabilities.experimentalApi = true`. No project API documentation was found on the public App Server guide during this investigation; the official installed binary's generated schema and actual responses establish the tested contract, not a stable compatibility guarantee.

## Designated records retained for Desktop checks

All under `~/Documents/ChatGPT/`:

- `Diorama Empty Folder Test 20260919`: empty control, no registered project.
- `Diorama Discovery Test 20260919`: conversation **PINE-4821**, subsequently registered with project/import. Project `01a0ba67-4cc9-7621-a770-48214952c8ff`; thread `01a0ba64-3a0c-7271-a116-3d62dd58e92c`.
- `Diorama Created Project Test 20260919`: created with project/create, conversation **BIRCH-7392**. Project `01a0ba69-1e88-71c3-abc4-9cfbda775e1d`; thread `01a0ba69-1e8b-7a82-9cf2-a23c55682e29`.

Both prompts explicitly prohibited tools/file/network access and returned their marker. No existing project was edited; no source transcripts, provider configuration, or Desktop private state were modified. Test App Servers were closed. Test projects remain for inspection.

## Proposed product flow, subject to Desktop check

New project → name and configurable parent (default user's ChatGPT folder) → create folder → official project/create with persisted idempotency key → thread/start with returned projectId and cwd. Retain project identity for later conversations. Make retries recoverable without duplicates; fall back to a clearly local-only project when installed Codex lacks the experimental API. Do not present an unverified Desktop synchronization guarantee.

Diorama currently supplies cwd and threadSource=user but no projectId and does not expose project methods in its execution transport. The proposed flow is not implemented yet. Existing shared-history writer ownership rules remain separate from project registration.

## Primary documentation

- [Projects and chats](https://learn.chatgpt.com/docs/projects): describes adding local projects and attaching folders; does not establish automatic discovery of the ChatGPT parent directory.
- [App Server](https://learn.chatgpt.com/docs/app-server): thread creation/reading/listing and source/cwd filtering. Source filters have defaults and are not interchangeable with transport identity.

## User observation — September 20, 2026

User supplied a Desktop screenshot and reported that the BIRCH-7392 thread appears independently rather than in a project folder. This narrows the recommendation: official project creation and membership work at the App Server level, but automatic Desktop sidebar grouping is not verified and was not observed in this workflow. Do not ship a promise of automatic Desktop project import. A separately added Desktop project/folder may be needed; that workaround has not yet been tested.

## Manual Desktop folder-add follow-up — September 20, 2026

After being asked to add/open the designated existing folder in Desktop, the user reported that the conversation still did not appear. Their screenshot shows the project `Diorama Created Project Test 20260919` with **No chats**. Thus manually adding the folder did not automatically associate the pre-existing BIRCH-7392 conversation in this test. The earlier standalone conversation visibility remains verified. The cause (including whether Desktop uses a distinct project identity or storage mechanism) has not been established; no such explanation should be stated as fact. Automatic Desktop project grouping is not supported by the tested workflow.

## Duplicate identity investigation and official reassignment — September 20, 2026

The follow-up project/list found **two** project records with identical names and roots. The original API-created project is `01a0ba69-1e88-71c3-abc4-9cfbda775e1d` (position 24). The newly added Desktop project is `01a0ba70-4773-71c2-9319-7307ce80e260` (position 0, created later). BIRCH-7392 was still assigned to the original project. Thus the empty manually added project had a different identity, despite its identical folder. This establishes the identity mismatch; it does not explain why the original API-created project was not displayed in Desktop.

Using the installed official experimental schema for thread/metadata/update, reassigned only designated thread `01a0ba69-1e8b-7a82-9cf2-a23c55682e29` to the Desktop-added project ID. The update response, fresh-connection thread/read, and project-filtered thread/list all confirmed the new assignment. The Desktop-added project's recencyAt now reflects this thread. No prompt was sent, conversation resumed, private state edited, or duplicate project deleted.

Evidence: `.local/project-discovery/desktop-comparison.json` and `desktop-reassignment.json`; scripts `inspect_project_mismatch.py` and `link_desktop_test_project.py`. **Desktop visual refresh after reassignment remains pending user observation.**

Revised implementation direction: reuse provider project IDs for known existing projects; do not equate same folder/name with same project identity or create another project blindly. Official metadata assignment can connect an existing conversation to an existing project. Initial Desktop visibility of a newly API-created project remains unresolved, so do not promise automatic creation-and-sidebar synchronization yet.

## Fresh repeat — September 20, 2026

Created `Diorama Fresh Test 20260920-002606` using official project/create, then started MAPLE-8264 with its projectId. Fresh App Server read and project-filtered list verified membership. User reports the conversation appears under Recents, reproducing the previous standalone-display result. Evidence: `.local/project-discovery/fresh-20260920-002606.json`. Initial automatic Desktop project grouping remains unverified/not observed in two trials. The earlier metadata reassignment visual check was not completed because the user deleted that test project; it must not be reported as failed or successful in Desktop.

## Fresh reassignment visual result — September 20, 2026

Desktop addition again produced a distinct project ID, `01a0ba7f-c342-7283-bc9e-fbd639e3d5a3`. Official thread/metadata/update reassigned MAPLE-8264 to it, confirmed by a fresh thread/read and project-filtered thread/list. After being asked to navigate away and reopen the project, the user supplied a screenshot still showing **No chats**. Therefore matching the Desktop-added project ID did not suffice to update the visible grouping in this trial. The identity mismatch was real but is not a complete explanation of Desktop behavior. A full Desktop restart remains untested; cache/refresh behavior is a hypothesis, not an established cause. Evidence: `.local/project-discovery/fresh-desktop-reassignment.json`.

## Restart-check follow-up screenshot

In response to instructions to quit and reopen Desktop, the user supplied another screenshot showing the designated fresh project with **No chats** and **0 tasks**. The screenshot establishes continued missing grouping; restart execution was not explicitly confirmed and cannot be inferred from the image alone. No successful Desktop grouping has been observed. Further diagnosis should compare a designated conversation created directly inside that Desktop project with the API-created conversation using official metadata, rather than assuming another retry will fix the issue.

## Desktop-native control conversation — September 20, 2026

User created DESKTOP-4192 following instructions to compose within the designated project. Located thread `01a0ba84-1430-7ac1-a526-2498c72f0ea5` using exact cwd and marker. It completed with DESKTOP-4192. Both CLI 0.153.4 and Desktop bundled 0.154.0-alpha.6.2, through independent App Server connections, report projectId null for this control; MAPLE-8264 retains the Desktop-added project ID. Both share the exact cwd, source vscode, threadSource user, paginated history, and no parent. The bundled server's project-filtered list includes MAPLE-8264 only. Thus an older reader version does not explain the observed null-versus-assigned metadata discrepancy.

Read only the designated transcripts' session metadata (excluded instructions and dynamic tool definitions). Desktop originator is `Codex Desktop`; probe originator is `diorama_handoff_probe`. This difference is evidence of client origin, not proof of a grouping rule; do not spoof Desktop identity as a proposed fix. Different models also do not establish a grouping cause.

Evidence: `desktop-native-comparison.json`, `bundled-reader-comparison.json`, and `designated-session-metadata.json` under `.local/project-discovery/`. **Desktop UI placement of DESKTOP-4192 has not yet been explicitly confirmed.** If it appears under the project while its local App Server projectId is null, that would establish that the displayed association is not represented by this local projectId alone. The mechanism remains unknown; no supported additional setter has been established.

## Confirmed Desktop-native grouping

User screenshot shows `Reply DESKTOP-4192` nested under `Diorama Fresh Test 20260920-002606`; user reports only the Desktop-created thread is visible there. Combined with both API-reader results, this establishes that the visible Desktop association is not determined by the tested local App Server projectId alone: the visible control has null projectId, whereas the absent MAPLE-8264 has the Desktop-added projectId. Exact Desktop association mechanism remains unknown. Official project APIs are functional locally but insufficient for the tested Desktop sidebar integration. Do not generalize this to all versions or claim a private/cloud mechanism without evidence. No more user retry steps are justified by the current evidence.

## Public report search — September 20, 2026

Found a close first-hand reproduction in OpenAI's public tracker: [#40935](https://github.com/openai/codex/issues/40935), opened August 26, 2026, still open when retrieved. Reporter used Desktop 26.820.60940 and remote App Server 0.149.1; a valid persisted projectId still produced a Recents-only task, even when the external client shared Desktop's exact App Server process/socket. Restart did not help. Their environment differs from our local test; this corroborates the symptom, not a maintainer-confirmed root cause or universal guarantee.

[#40535](https://github.com/openai/codex/issues/40535) requests an authorized Desktop project/navigation bridge and reports that Desktop host tools expose a different project catalog from a separate local App Server. No supported external bridge or confirmed fix was established in the fetched reports. [#33771](https://github.com/openai/codex/issues/33771) describes separate Desktop assignment/sidebar state and a grouping regression after an update. These are user reports, not official API contracts.

Important correction to earlier wording: we identified a *local API project record created after the Desktop folder-add action*, not independently verified the canonical Desktop host project UUID. Calling it the “exact Desktop project ID” was stronger than the evidence justified. The native Desktop control's null local projectId and positive UI grouping reinforce this distinction. Do not modify private Desktop state to paper over it.

## Canonical Desktop identity verified through host tool

The dedicated Codex app `list_projects` tool is available and succeeded. Earlier statements conflating the blocked computer-use UI with all Desktop access were incorrect. It returns canonical Desktop project ID `f82e8ded-88d6-492a-824f-ce7487fe9b2f` for `Diorama Fresh Test 20260920-002606`. Official local App Server project/read rejects this exact ID with `project not found`. Evidence: `.local/project-discovery/canonical-desktop-id.json`. This directly verifies distinct Desktop and local App Server project identities for the designated folder. Dedicated host tools available to this assistant do not establish an externally callable API for standalone Diorama. No new thread was created during this check.

## Standalone Desktop bridge assessment

Checked both installed generated experimental request schemas (CLI 0.153.4 and Desktop bundled 0.154.0-alpha.6.2): their project methods are project/list, read, create, import, update, move, delete. Neither schema exposes a Desktop catalog/activation method. This is a bounded schema check, not proof no other interface exists anywhere.

Rechecked public documentation/search and open reports #40535 and #40935. No documented, externally callable Desktop host-project bridge was established. The assistant's dedicated Codex app tools successfully list canonical Desktop projects, but their availability inside this conversation is not a callable integration contract for standalone Diorama. Public report #40535 specifically requests such a bridge; #40935 reports the grouping gap even on a shared App Server process. Treat those as first-hand reports, not maintainer guarantees.

Product recommendation: retain official App Server for Diorama execution/history and its own project organization, with cross-Desktop project grouping explicitly unavailable in the tested standalone workflow. A user-invoked Desktop agent/skill could assist through host tools, but is a different, unverified workflow—not automatic standalone sync. Do not implement private endpoint calls, identity spoofing, or Desktop-state edits as a substitute. No Diorama app code or installed bundle changed during this assessment.

# Conversation items and events reference

Generated from **Codex CLI 0.153.4** on 2026-09-20. This is exhaustive for the `ThreadItem`, `UserInput`, `ServerNotification`, and `ServerRequest` unions in this installed version, including comparison with the experimental export. It is not a universal list across providers or future versions. It does not inventory client-initiated request methods or every nested result schema.

Source: local CLI schema, with terminology checked against the [official App Server documentation](https://learn.chatgpt.com/docs/app-server). [Machine-readable inventory](docs/codex-protocol-inventory.json). Presence in a schema does not mean an event is emitted in every client/configuration; some ordinary-export types are themselves documented as experimental or deprecated.

## Conversation items

**19 item types.** Items have an ID and a `type`; turns contain items. Live `item/started` and `item/completed` notifications carry these items. The completed item is authoritative, rather than concatenated streaming deltas.

| Type | Meaning | Diorama now | Useful visual / canvas input |
|---|---|---|---|
| `userMessage` | User text and attached inputs | Message; attachment placeholders | Goal / constraints; attachment gallery |
| `hookPrompt` | Prompt fragments supplied by a hook | Collapsed system context | Context indicator; do not treat as user-authored progress |
| `agentMessage` | Assistant message; may include phase, questions and citations | Markdown message | Short update or answer; agent explicitly authors canvas conclusions |
| `functionCallOutput` | Standalone function output | Raw tool row | Recognized result cards; retain provenance |
| `plan` | Proposed plan text; schema labels this experimental | Assistant Markdown | Plan panel; separate from structured turn/plan/updated steps |
| `reasoning` | Reasoning record | Excluded | Excluded from canvas and visual summaries |
| `commandExecution` | Command, working directory, status and output | Raw tool row | Command status / exit code / duration; verification evidence |
| `fileChange` | File edits and diffs | Raw tool row | Diff cards; changed-file summary |
| `mcpToolCall` | MCP tool invocation and result/error | Raw tool row | Tool-specific cards, tables or galleries when payload supports them |
| `dynamicToolCall` | Dynamic client tool invocation | Raw tool row; execution requests unsupported | Recognized output cards; displaying is not permission to execute |
| `collabAgentToolCall` | Agent collaboration call and reported agent states | Raw tool row | Delegated task cards and dependency flow |
| `subAgentActivity` | Subagent thread/path activity | Raw tool row | Linked agent activity badge |
| `webSearch` | Search/open/find action and optional results | Raw tool row | Queries, source cards and research evidence |
| `imageView` | Image inspected at a local path | Inline local preview + raw details | Image preview; not a historical snapshot |
| `sleep` | Interruptible wait duration | Raw tool row | Waiting indicator, never fabricated progress |
| `imageGeneration` | Generated image result, state and optional saved path | Raw tool row | Generation status and image gallery when image data is available |
| `enteredReviewMode` | Review started | Event row | Review phase marker |
| `exitedReviewMode` | Review ended | Event row | Review outcome when supplied |
| `contextCompaction` | Conversation history compacted | Event row | Small context marker; never mark work complete |

`collabAgentToolCall` is the current spelling. Diorama also accepts the older `collabToolCall` spelling for compatibility; it is not in this version's union.

### Item fields

Fields below are schema properties, not a promise every value is present/non-null. Required-property lists are in the JSON inventory.

- **`userMessage`:** `clientId`, `content`, `id`
- **`hookPrompt`:** `fragments`, `id`
- **`agentMessage`:** `delivery`, `id`, `memoryCitation`, `phase`, `questions`, `text`
- **`functionCallOutput`:** `id`, `name`, `namespace`, `output`
- **`plan`:** `id`, `text`
- **`reasoning`:** `content`, `id`, `summary`
- **`commandExecution`:** `aggregatedOutput`, `command`, `commandActions`, `cwd`, `durationMs`, `exitCode`, `id`, `pluginId`, `processId`, `scriptPath`, `source`, `status`
- **`fileChange`:** `changes`, `id`, `status`
- **`mcpToolCall`:** `appContext`, `arguments`, `durationMs`, `error`, `id`, `mcpAppResourceUri`, `pluginId`, `readOnlyHint`, `result`, `server`, `status`, `tool`
- **`dynamicToolCall`:** `arguments`, `contentItems`, `durationMs`, `id`, `namespace`, `status`, `success`, `tool`
- **`collabAgentToolCall`:** `agentsStates`, `id`, `model`, `prompt`, `reasoningEffort`, `receiverThreadIds`, `senderThreadId`, `status`, `tool`
- **`subAgentActivity`:** `agentPath`, `agentThreadId`, `id`, `kind`
- **`webSearch`:** `action`, `id`, `query`, `results`
- **`imageView`:** `id`, `path`
- **`sleep`:** `durationMs`, `id`
- **`imageGeneration`:** `failure`, `id`, `result`, `revisedPrompt`, `savedPath`, `status`, `transparentBackground`
- **`enteredReviewMode`:** `id`, `review`
- **`exitedReviewMode`:** `id`, `review`
- **`contextCompaction`:** `id`

## Content inside user messages

These are `UserInput` variants, not separate conversation item types.

| Type | Fields |
|---|---|
| `text` | `text`, `text_elements` |
| `image` | `detail`, `url` |
| `localImage` | `detail`, `path` |
| `audio` | `url` |
| `localAudio` | `path` |
| `skill` | `name`, `path` |
| `mention` | `name`, `path` |

## Live notifications

**81 methods** in the ordinary export. Notifications have no request ID and do not require a reply. Not all are conversation content: account, filesystem, model, and connection events appear here too.

For a live UI, prioritize `turn/started`, `turn/completed`, `thread/status/changed`, `turn/plan/updated`, `turn/diff/updated`, item lifecycle, tool output deltas, and `serverRequest/resolved`. Diorama currently handles a subset. HTML view is agent-authored; it does not pretend these events can mechanically explain architecture or decisions.

| Method | Parameter schema |
|---|---|
| `error` | `ErrorNotification` |
| `thread/started` | `ThreadStartedNotification` |
| `thread/status/changed` | `ThreadStatusChangedNotification` |
| `thread/archived` | `ThreadArchivedNotification` |
| `thread/deleted` | `ThreadDeletedNotification` |
| `thread/unarchived` | `ThreadUnarchivedNotification` |
| `thread/closed` | `ThreadClosedNotification` |
| `thread/reverted` | `ThreadRevertedNotification` |
| `skills/changed` | `SkillsChangedNotification` |
| `thread/name/updated` | `ThreadNameUpdatedNotification` |
| `thread/goal/updated` | `ThreadGoalUpdatedNotification` |
| `thread/goal/cleared` | `ThreadGoalClearedNotification` |
| `thread/queue/changed` | `ThreadQueueChangedNotification` |
| `project/changed` | `ProjectChangedNotification` |
| `thread/project/updated` | `ThreadProjectUpdatedNotification` |
| `thread/environment/connected` | `EnvironmentConnectionNotification` |
| `thread/environment/disconnected` | `EnvironmentConnectionNotification` |
| `thread/settings/updated` | `ThreadSettingsUpdatedNotification` |
| `thread/tokenUsage/updated` | `ThreadTokenUsageUpdatedNotification` |
| `turn/started` | `TurnStartedNotification` |
| `hook/started` | `HookStartedNotification` |
| `turn/completed` | `TurnCompletedNotification` |
| `hook/completed` | `HookCompletedNotification` |
| `turn/diff/updated` | `TurnDiffUpdatedNotification` |
| `turn/plan/updated` | `TurnPlanUpdatedNotification` |
| `item/started` | `ItemStartedNotification` |
| `item/autoApprovalReview/started` | `ItemGuardianApprovalReviewStartedNotification` |
| `item/autoApprovalReview/completed` | `ItemGuardianApprovalReviewCompletedNotification` |
| `autoApprovalReview/strictReviewRequired` | `StrictReviewRequiredNotification` |
| `item/completed` | `ItemCompletedNotification` |
| `item/agentMessage/delta` | `AgentMessageDeltaNotification` |
| `item/plan/delta` | `PlanDeltaNotification` |
| `command/exec/outputDelta` | `CommandExecOutputDeltaNotification` |
| `process/outputDelta` | `ProcessOutputDeltaNotification` |
| `process/exited` | `ProcessExitedNotification` |
| `item/commandExecution/outputDelta` | `CommandExecutionOutputDeltaNotification` |
| `item/commandExecution/terminalInteraction` | `TerminalInteractionNotification` |
| `item/fileChange/outputDelta` | `FileChangeOutputDeltaNotification` |
| `item/fileChange/patchUpdated` | `FileChangePatchUpdatedNotification` |
| `serverRequest/resolved` | `ServerRequestResolvedNotification` |
| `item/mcpToolCall/progress` | `McpToolCallProgressNotification` |
| `mcpServer/oauthLogin/completed` | `McpServerOauthLoginCompletedNotification` |
| `mcpServer/startupStatus/updated` | `McpServerStatusUpdatedNotification` |
| `mcpServer/event/stream/notification` | `McpServerEventStreamNotification` |
| `account/updated` | `AccountUpdatedNotification` |
| `account/rateLimits/updated` | `AccountRateLimitsUpdatedNotification` |
| `app/list/updated` | `AppListUpdatedNotification` |
| `remoteControl/status/changed` | `RemoteControlStatusChangedNotification` |
| `externalAgentConfig/import/progress` | `ExternalAgentConfigImportProgressNotification` |
| `externalAgentConfig/import/completed` | `ExternalAgentConfigImportCompletedNotification` |
| `fs/changed` | `FsChangedNotification` |
| `item/reasoning/summaryTextDelta` | `ReasoningSummaryTextDeltaNotification` |
| `item/reasoning/summaryPartAdded` | `ReasoningSummaryPartAddedNotification` |
| `item/reasoning/textDelta` | `ReasoningTextDeltaNotification` |
| `thread/compacted` | `ContextCompactedNotification` |
| `model/rerouted` | `ModelReroutedNotification` |
| `model/verification` | `ModelVerificationNotification` |
| `modelProvider/authRecoveryStarted` | `AuthRecoveryNotification` |
| `modelProvider/authRecoveryCompleted` | `AuthRecoveryNotification` |
| `turn/moderationMetadata` | `TurnModerationMetadataNotification` |
| `model/safetyBuffering/updated` | `ModelSafetyBufferingUpdatedNotification` |
| `warning` | `WarningNotification` |
| `guardianWarning` | `GuardianWarningNotification` |
| `deprecationNotice` | `DeprecationNoticeNotification` |
| `configWarning` | `ConfigWarningNotification` |
| `fuzzyFileSearch/sessionUpdated` | `FuzzyFileSearchSessionUpdatedNotification` |
| `fuzzyFileSearch/sessionCompleted` | `FuzzyFileSearchSessionCompletedNotification` |
| `thread/realtime/started` | `ThreadRealtimeStartedNotification` |
| `thread/realtime/itemAdded` | `ThreadRealtimeItemAddedNotification` |
| `thread/realtime/item/started` | `ThreadRealtimeItemStartedNotification` |
| `thread/realtime/item/transcript/delta` | `ThreadRealtimeItemTranscriptDeltaNotification` |
| `thread/realtime/item/completed` | `ThreadRealtimeItemCompletedNotification` |
| `thread/realtime/transcript/delta` | `ThreadRealtimeTranscriptDeltaNotification` |
| `thread/realtime/transcript/done` | `ThreadRealtimeTranscriptDoneNotification` |
| `thread/realtime/outputAudio/delta` | `ThreadRealtimeOutputAudioDeltaNotification` |
| `thread/realtime/sdp` | `ThreadRealtimeSdpNotification` |
| `thread/realtime/error` | `ThreadRealtimeErrorNotification` |
| `thread/realtime/closed` | `ThreadRealtimeClosedNotification` |
| `windows/worldWritableWarning` | `WindowsWorldWritableWarningNotification` |
| `windowsSandbox/setupCompleted` | `WindowsSandboxSetupCompletedNotification` |
| `account/login/completed` | `AccountLoginCompletedNotification` |

## Server requests

These carry request IDs and require a response. They are not notifications and must not be answered by an HTML page.

| Method | Parameter schema |
|---|---|
| `item/commandExecution/requestApproval` | `CommandExecutionRequestApprovalParams` |
| `item/fileChange/requestApproval` | `FileChangeRequestApprovalParams` |
| `item/tool/requestUserInput` | `ToolRequestUserInputParams` |
| `mcpServer/elicitation/request` | `McpServerElicitationRequestParams` |
| `item/permissions/requestApproval` | `PermissionsRequestApprovalParams` |
| `item/tool/call` | `DynamicToolCallParams` |
| `account/chatgptAuthTokens/refresh` | `ChatgptAuthTokensRefreshParams` |
| `attestation/generate` | `AttestationGenerateParams` |
| `applyPatchApproval` | `ApplyPatchApprovalParams` |
| `execCommandApproval` | `ExecCommandApprovalParams` |

## Experimental export differences

- **items:** No additional union variants.
- **user inputs:** No additional union variants.
- **notifications:** No additional union variants.
- **server requests:** `currentTime/read` added.

This comparison concerns variant names; nested experimental fields and provider-specific MCP payloads can still differ.

## How this relates to HTML view

The page is a concise, agent-maintained interpretation of the work: goal, current state, diagram, plan, status, decisions/questions, latest changes, and next action. Use commands/diffs/results as evidence, not as a substitute for that interpretation. Keep native execution state outside the document, since a saved page may be stale. Never include hidden reasoning or use canvas content to grant approvals.

The native HTML viewer refreshes when its file changes. Maintaining the file is an instruction to the agent, not an event-derived guarantee. See [HTML_VIEW.md](HTML_VIEW.md) for storage, update rules, and limitations.

## Regenerate

```sh
codex --version
codex app-server generate-json-schema --out /tmp/diorama-schema-stable
codex app-server generate-json-schema --experimental --out /tmp/diorama-schema-experimental
python3 scripts/generate_conversation_reference.py --schema-dir /tmp/diorama-schema-stable --experimental-dir /tmp/diorama-schema-experimental --version 0.153.4
```

Use the actual installed version in `--version`. Review newly added variants before claiming UI support. Schema generation is offline and does not start an agent turn.

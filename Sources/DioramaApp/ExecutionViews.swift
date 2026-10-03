import SwiftUI
import DioramaCore

struct ExecutionModelPicker: View {
    let controller: ExecutionController
    @Binding var model: String
    @Binding var effort: String
    var effectiveModel = ""
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([false, true], id: \.self) { claude in
                Text(claude ? "Anthropic" : "OpenAI").font(.caption).foregroundStyle(.secondary)
                let choices = controller.models.filter { $0.id.hasPrefix("claude/") == claude }
                if choices.isEmpty {
                    if controller.connecting { Text("Checking available models…").foregroundStyle(.secondary) }
                    else { Button(claude ? "Connect or refresh Anthropic…" : "Connect or refresh OpenAI…") { openSettings() }.pointingHand() }
                } else {
                    ForEach(choices) { choice in
                        Button { model = choice.id; effort = "" } label: {
                            HStack { Text(choice.name); Spacer(); if choice.id == (model.isEmpty ? effectiveModel : model) { Image(systemName: "checkmark") } }
                        }.pointingHand().buttonStyle(.plain)
                    }
                }
            }
            Button(controller.connecting ? "Refreshing models…" : "Refresh models") {
                Task { await controller.refreshModels() }
            }.pointingHand().disabled(controller.connecting)
            let levels = controller.models.first { $0.id == (model.isEmpty ? effectiveModel : model) }?.efforts ?? []
            if !levels.isEmpty {
                Picker("Reasoning", selection: $effort) {
                    Text("Default").tag("")
                    ForEach(levels, id: \.self) { Text($0.capitalized).tag($0) }
                }.pointingHand()
            }
        }
    }
}

struct NewExecutionTaskView: View {
    let library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var folder = ""
    @State private var prompt = ""
    @State private var attachments: [ConversationAttachment] = []
    @State private var pasteError: String?
    @State private var model = UserDefaults.standard.string(forKey: "defaultAgentModel") ?? ""
    @State private var effort = ""
    @State private var approvalReview: ApprovalReviewChoice = .inherit
    @State private var mode = "default"
    @State private var capabilities: [CapabilityInput] = []
    @State private var queueNext = false
    @State private var goalMode = false
    @State private var preparedID: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New session").font(.title2.bold())
            Text("Work directly in the chosen folder using your selected model and connected account.").foregroundStyle(.secondary)
            HStack {
                Text(folder.isEmpty ? "Choose a working folder" : folder).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("Choose folder…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                    panel.begin { response in
                        if response == .OK { folder = panel.url?.path ?? "" }
                    }
                }.pointingHand().disabled(preparedID != nil || busy)
            }
            ExecutionModelPicker(controller: library.execution, model: $model, effort: $effort, effectiveModel: preparedID.flatMap { library.execution.tasks[$0]?.model } ?? "")
                .disabled(preparedID != nil || busy)
            ComposerTextEditor(text: $prompt, attachments: $attachments, error: $pasteError, disabled: busy)
                .frame(height: 130).border(Color.secondary.opacity(0.3))
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.orange) }
            ComposerAddMenu(controller: library.execution, folder: folder, threadID: preparedID, attachments: $attachments, capabilities: $capabilities, disabled: busy, showsAttachments: true)
            ComposerModeToggles(mode: $mode, goal: $goalMode, queue: $queueNext, showQueue: false).disabled(busy)
            ApprovalReviewPicker(selection: $approvalReview, reviewer: preparedID.flatMap { library.execution.tasks[$0]?.approvalReviewer }, policy: preparedID.flatMap { library.execution.tasks[$0]?.approvalPolicy } ?? .null, sandbox: preparedID.flatMap { library.execution.tasks[$0]?.sandbox } ?? .null, claude: model.hasPrefix("claude/"), isNew: preparedID == nil, supportsAutoMode: library.execution.models.first(where: { $0.id == model })?.supportsAutoMode).disabled(busy)
            if let id = preparedID, let task = library.execution.tasks[id] {
                WorkflowControls(controller: library.execution, task: task, mode: $mode, capabilities: $capabilities, queueNext: $queueNext)
                Text("Ready to send · effective settings").font(.headline)
                ScrollView { Text(task.settings).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 130)
                Text("Diorama requests workspace write access for Codex. Actions outside the workspace may need approval. Global settings are unchanged.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = error ?? library.execution.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !library.execution.connected { Button("Connect to Codex") { Task { await library.execution.connect() } }.pointingHand().disabled(library.execution.connecting) }
            HStack {
                Button("Cancel") { dismiss() }.pointingHand().disabled(busy)
                Spacer()
                if busy || library.execution.connecting { ProgressView().controlSize(.small) }
                Button(preparedID == nil ? "Prepare task" : "Send prompt") {
                    busy = true; error = nil
                    Task {
                        defer { busy = false }
                        do {
                            if let id = preparedID {
                                await library.execution.loadModes()
                                try await library.execution.sendWithGoal(id: id, prompt: prompt, model: model, effort: effort, attachments: attachments, approvalReview: approvalReview, mode: mode, capabilities: capabilities, goal: goalMode)
                                library.selectOwned(id); dismiss()
                            } else {
                                let id = try await library.execution.prepare(folder: folder, title: prompt, model: model, permission: approvalReview)
                                preparedID = id; library.selectOwned(id)
                            }
                        } catch { self.error = error.localizedDescription }
                    }
                }.pointingHand().buttonStyle(.borderedProminent)
                    .disabled(busy || !library.execution.connected || folder.isEmpty || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
            }
        }.padding(24).frame(width: 680)
            .modifier(AttachmentDropTarget(attachments: $attachments, disabled: busy))
            .task { folder = library.selectedFolder?.path ?? ""; await library.execution.connect() }
    }
}

struct ExecutionRequestView: View {
    let request: ExecutionRequest
    let controller: ExecutionController
    @State private var answers: [String: String] = [:]
    @State private var error: String?
    var body: some View {
        if !request.isInput && !request.isElicitation {
            VStack(alignment: .leading, spacing: 8) {
                PermissionReviewCard(request: request, relatedItem: controller.tasks[request.threadID]?.transcript.entries.last(where: {
                    $0.tool?.item["id"] == request.params["itemId"] && $0.turnID == request.params["turnId"].string
                })?.tool?.item ?? .null, connected: controller.connected, respond: respond)
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
        } else { legacyRequest }
    }
    private var legacyRequest: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.isInput ? (request.isBlocking ? "Input required · work paused" : "Question · work continues") : request.isElicitation ? "Connector request" : "Approval requested").font(.headline)
            if let reason = request.params["reason"].string { Text(reason) }
            if let command = request.params["command"].string { Text(command).font(.body.monospaced()).textSelection(.enabled) }
            if request.isElicitation {
                ElicitationFormView(request: request, respond: respond)
            } else if request.isInput {
                ForEach(request.params["questions"].array, id: \.pretty) { question in
                    let id = question["id"].string ?? ""
                    Text(question["question"].string ?? "Question")
                    ForEach(question["options"].array, id: \.pretty) { option in
                        Button { answers[id] = option["label"].string ?? "" } label: {
                            VStack(alignment: .leading) {
                                Text(option["label"].string ?? "Option")
                                Text(option["description"].string ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }.pointingHand()
                    }
                    if question["isSecret"].bool {
                        SecureField("Answer", text: Binding(get: { answers[id, default: ""] }, set: { answers[id] = $0 }))
                    } else {
                        TextField("Answer", text: Binding(get: { answers[id, default: ""] }, set: { answers[id] = $0 }))
                    }
                }
                Button("Submit answers") {
                    let values = answers.mapValues { WireValue.object(["answers": .array([.string($0)])]) }
                    respond(.object(["answers": .object(values)]))
                }.pointingHand().disabled(request.params["questions"].array.contains { answers[$0["id"].string ?? "", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            } else if request.method == "item/permissions/requestApproval" {
                Text(request.params["permissions"].pretty).font(.caption.monospaced()).textSelection(.enabled)
                HStack {
                    Button("Allow for this turn") { respond(.object(["permissions": request.params["permissions"], "scope": .string("turn")])) }.pointingHand()
                    Button("Deny") { respond(.object(["permissions": .object([:]), "scope": .string("turn")])) }.pointingHand()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(request.approvalDecisions) { decision in
                        VStack(alignment: .leading, spacing: 4) {
                            if let scope = decision.scope { Text(scope).font(.caption.monospaced()).textSelection(.enabled) }
                            Button(decision.title) { respond(.object(["decision": decision.value])) }.pointingHand()
                        }
                    }
                }
                if request.approvalDecisions.isEmpty { Text("This approval requires an unsupported decision type. Use the square Stop button in the composer to cancel.").foregroundStyle(.orange) }
            }
            DisclosureGroup { Text(request.params.pretty).font(.caption.monospaced()).textSelection(.enabled) } label: { Text("Request details").disclosurePointingHand() }
            if request.responding { Text("Response sent · awaiting provider resolution").font(.caption) }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).disabled(request.responding || !controller.connected)
    }
    private func respond(_ result: WireValue) {
        Task { do { try await controller.answer(id: request.id, result: result, expectedInstance: request.instanceID) } catch { self.error = error.localizedDescription } }
    }
}

struct ExecutionControls: View {
    @Environment(\.avatarMessages) private var avatarMessages
    let library: LibraryModel
    let session: Session
    @State private var prompt = ""
    @State private var attachments: [ConversationAttachment] = []
    @State private var pasteError: String?
    @State private var model = ""
    @State private var effort = ""
    @State private var approvalReview: ApprovalReviewChoice = .inherit
    @State private var mode = "default"
    @State private var capabilities: [CapabilityInput] = []
    @State private var queueNext = false
    @State private var goalMode = false
    @State private var error: String?
    @State private var retryingWriter = false
    @State private var sending = false
    @State private var recoveredGoal: WireValue = .null
    var body: some View {
        Group {
        if session.observationOnly {
            VStack(alignment: .leading, spacing: 6) {
                if avatarMessages { AvatarReadOnlyTools() }
                Text("Viewing Claude Code Desktop · Continue this conversation in Claude Desktop.")
                let reported = library.activitySnapshot(session).records.last { $0.sessionID == session.sessionID && $0.data["permissionMode"].string != nil }?.data["permissionMode"].string
                Label(reported.map { "Last reported permissions: " + (ApprovalReviewChoice.claude($0)?.title ?? $0) } ?? "Permissions unconfirmed", systemImage: "hand.raised")
            }.font(.caption).foregroundStyle(.secondary).padding(16)
        } else if let task = library.execution.tasks[session.sessionID], task.attached, task.phase != .disconnected {
            VStack(alignment: .leading, spacing: 10) {
                if let error = error ?? task.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if !model.isEmpty, model.hasPrefix("claude/") != (session.provider == .claude) { Text("Your next message continues here with the selected provider. Files and branch stay unchanged.").font(.caption).foregroundStyle(.secondary) }
                if let notice = task.reviewNotice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                let pending = library.execution.requests.values.filter { $0.threadID == task.id }.sorted { $0.receivedAt < $1.receivedAt }
                if let request = pending.first {
                    if pending.count > 1 { Text("1 of \(pending.count) requests").font(.caption).foregroundStyle(.secondary) }
                    if request.isInput || request.isElicitation {
                        ScrollView { ExecutionRequestView(request: request, controller: library.execution).id(request.id) }.frame(maxHeight: 260)
                    } else {
                        ExecutionRequestView(request: request, controller: library.execution).id(request.id)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let record = library.conversations.record(session.id), !record.carried.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Carried queue · paused").font(.caption).foregroundStyle(.secondary)
                        ForEach(record.carried) { item in
                            HStack {
                                Text(item.row["input"].array.compactMap { $0["text"].string }.joined(separator: " ")).lineLimit(1)
                                Spacer()
                                Button("Resume") { Task { do { try await library.resumeCarriedQueue(conversationID: record.id, submissionID: item.id) } catch { self.error = error.localizedDescription } } }.pointingHand()
                                    .disabled(task.phase.active || sending || library.conversations.queueOperations.contains(record.id))
                                Button { Task { do { try await library.removeCarriedQueue(conversationID: record.id, submissionID: item.id) } catch { self.error = error.localizedDescription } } } label: { Image(systemName: "xmark") }.pointingHand()
                                    .accessibilityLabel("Remove carried queued message").disabled(sending || item.destinationID != nil || library.conversations.queueOperations.contains(record.id))
                            }.font(.caption)
                        }
                    }
                }
                if task.parentID == nil {
                    WorkflowControls(controller: library.execution, task: task, mode: $mode, capabilities: $capabilities, queueNext: $queueNext)
                        ConversationComposer(controller: library.execution, model: $model, effort: $effort, prompt: $prompt, attachments: $attachments, approvalReview: $approvalReview,
                                             effectiveModel: task.model, effectiveEffort: task.effort, reviewer: task.approvalReviewer, policy: task.approvalPolicy, sandbox: task.sandbox, sending: sending, active: task.phase.active, canSteer: library.execution.canSteer(id: task.id) || (queueNext && !library.execution.workflowBusy.contains(task.id) && !task.workflow.queueUncertain), queued: queueNext, capabilities: $capabilities, folder: task.folder, threadID: task.id, mode: $mode, goalMode: $goalMode, queueMode: $queueNext) {
                            submit()
                        }
                }
            }.padding(16)
        } else if [Provider.codex, .claude].contains(session.provider),
                  ExecutionController.resumeUnavailableReason(session) == nil,
                  (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty),
                  !(library.execution.tasks[session.sessionID]?.phase == .disconnected && library.execution.tasks[session.sessionID]?.requiresReconciliation == true),
                  retryingWriter || library.execution.resumeErrors[session.sessionID]?.contains("active writer") == true {
            VStack(alignment: .leading, spacing: 8) {
                LockedConversationComposer(checking: sending, details: library.execution.resumeErrors[session.sessionID] ?? "Checking availability…") {
                    submit(retrying: true)
                }
                Text("Your message hasn’t been sent. Retry will send it when the conversation is available.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup {
                    Text(prompt).textSelection(.enabled)
                    AttachmentPicker(attachments: $attachments, disabled: sending)
                } label: { Text("Your message").disclosurePointingHand() }.font(.caption)
            }.padding(16)
        } else if [Provider.codex, .claude].contains(session.provider) {
            VStack(alignment: .leading, spacing: 8) {
                if session.provider == .claude, recoveredGoal != .null, recoveredGoal["status"].string != "complete" {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(recoveredGoal["objective"].string ?? "Saved goal").font(.callout).lineLimit(2)
                            Text("Saved goal · paused").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Review goal") {
                            Task {
                                do {
                                    try await library.execution.resumeImported(session)
                                    await library.execution.loadWorkflow(id: session.sessionID)
                                    await library.readSelected()
                                } catch { self.error = error.localizedDescription }
                            }
                        }.pointingHand().disabled(library.execution.resuming.contains(session.sessionID))
                    }
                }
                if let reason = ExecutionController.resumeUnavailableReason(session) {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if let task = library.execution.tasks[session.sessionID], task.phase == .disconnected, task.requiresReconciliation {
                    Text("Message delivery is uncertain. Check the saved conversation before sending again.")
                        .font(.callout).foregroundStyle(.orange)
                    Button("Check history and reconnect") {
                        Task {
                            do {
                                try await library.execution.resumeImported(session)
                                
                                await library.readSelected()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.pointingHand().disabled(library.execution.resuming.contains(session.sessionID))
                } else {
                    ConversationComposer(controller: library.execution, model: $model, effort: $effort, prompt: $prompt, attachments: $attachments, approvalReview: $approvalReview,
                                         effectiveModel: session.provider == .claude ? "claude/default" : "", sending: sending, active: false, queued: queueNext, capabilities: $capabilities, folder: session.project, threadID: session.sessionID, mode: $mode, goalMode: $goalMode, queueMode: $queueNext) { submit() }
                }
                if library.execution.resumeErrors[session.sessionID]?.contains("active goal") == true {
                    Button("Pause goal and reconnect") { Task { do { try await library.execution.pauseGoalAndResume(session: session) } catch { self.error = error.localizedDescription } } }.pointingHand()
                }
                if let message = error ?? library.execution.resumeErrors[session.sessionID] ?? library.execution.tasks[session.sessionID]?.error {
                    Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }.padding(16)
        }
        }
        .task(id: session.id) {
            recoveredGoal = session.provider == .claude ? ClaudeExecutionTransport.savedGoal(sessionID: session.sessionID) : .null
        }
        .onAppear {
            mode = library.drafts[session.id]?.mode ?? library.execution.tasks[session.sessionID]?.workflow.mode ?? "default"
            if session.provider == .claude { model = library.execution.tasks[session.sessionID]?.model ?? "claude/default" }
            if let draft = library.drafts[session.id] {
                prompt = draft.text
                attachments = draft.attachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            }
        }
        .onChange(of: library.drafts[session.id]?.text) { if let text = library.drafts[session.id]?.text, text != prompt { prompt = text } }
        .onChange(of: library.drafts[session.id]?.attachments) {
            let saved = (library.drafts[session.id]?.attachments ?? []).compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            if saved != attachments { attachments = saved }
        }
        .onChange(of: mode) { library.saveDraft(session.id, text: prompt, attachments: attachments, mode: mode) }
        .onChange(of: prompt) { library.saveDraft(session.id, text: prompt, attachments: attachments) }
        .onChange(of: attachments) { library.saveDraft(session.id, text: prompt, attachments: attachments) }
    }

    private func submit(retrying: Bool = false) {
        guard !sending else { return }
        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if command == "/plan" { goalMode = false; let current = mode.isEmpty ? library.execution.tasks[session.sessionID]?.workflow.mode : mode; mode = current == "plan" ? "default" : "plan"; prompt = ""; return }
        if command == "/fork" { library.forkConversation(session); return }
        if command == "/review" {
            Task { do { if library.execution.tasks[session.sessionID]?.attached != true { try await library.execution.resumeImported(session) }; try await library.execution.review(id: session.sessionID); prompt = "";  } catch { self.error = error.localizedDescription } }
            return
        }
        let submittedMode = mode.isEmpty ? "default" : mode
        let submittedGoal = goalMode
        let submittedCapabilities = capabilities
        let submittedQueue = queueNext
        let submittedPrompt = prompt
        let submittedAttachments = attachments
        let submittedModel = model
        let submittedEffort = effort
        let submittedReview = approvalReview
        let expectedTurn = library.execution.tasks[session.sessionID].flatMap { $0.phase.active ? $0.turnID : nil }
        let crossProvider = !submittedModel.isEmpty && submittedModel.hasPrefix("claude/") != (session.provider == .claude)
        let optimistic = !submittedQueue && !crossProvider
        let message = OutgoingMessage(sessionID: session.sessionID, text: submittedPrompt, attachmentPaths: submittedAttachments.map { $0.url.path }, baselineIDs: Set(library.displayedTranscript.entries.map(\.id)).union(library.execution.tasks[session.sessionID]?.transcript.entries.map(\.id) ?? []))
        if optimistic {
            library.outgoing[message.id] = message
            library.persistOutgoing()
            prompt = ""; attachments = []
            approvalReview = .inherit; capabilities = []; queueNext = false
        }
        sending = true; retryingWriter = retrying; error = nil
        let perform: () async -> Void = {
            sending = true
            library.outgoing[message.id]?.state = .pending
            library.outgoing[message.id]?.error = nil
            library.persistOutgoing()
            defer { sending = false; retryingWriter = false }
            var submitting = false
            var switchedMessage: String?
            do {
                if crossProvider {
                    guard submittedCapabilities.isEmpty else { throw AppServerFailure("Remove selected provider-specific skills or connectors before switching providers.") }
                    guard !submittedQueue else { throw AppServerFailure("Turn Queue off before switching providers. Existing queued messages will stay paused.") }
                    let review = submittedReview
                    let target = try await library.switchProvider(from: session, model: submittedModel, permission: review)
                    let outgoing = OutgoingMessage(sessionID: target.sessionID, text: submittedPrompt, attachmentPaths: submittedAttachments.map { $0.url.path }, baselineIDs: [])
                    switchedMessage = outgoing.id
                    library.outgoing[outgoing.id] = outgoing; library.persistOutgoing()
                    prompt = ""; attachments = []
                    library.saveDraft(target.id, text: "", attachments: [])
                    await library.execution.loadModes()
                    submitting = true
                    try await library.execution.sendWithGoal(id: target.sessionID, prompt: submittedPrompt, model: submittedModel, effort: submittedEffort, attachments: submittedAttachments, approvalReview: review, mode: submittedMode, capabilities: [], goal: false)
                    library.outgoing[outgoing.id]?.state = .accepted
                    library.outgoing[outgoing.id]?.turnID = library.execution.tasks[target.sessionID]?.turnID
                    library.reconcileOutgoing(target.sessionID)
                    return
                } else if submittedQueue {
                    try await library.execution.resumeImported(session)
                    try await library.execution.enqueue(id: session.sessionID, prompt: submittedPrompt, attachments: submittedAttachments, capabilities: submittedCapabilities)
                } else if let expectedTurn {
                    submitting = true
                    try await library.execution.steer(id: session.sessionID, expectedTurnID: expectedTurn, prompt: submittedPrompt, attachments: submittedAttachments)
                } else {
                    await library.execution.loadModes()
                    try await library.execution.resumeImported(session)
                    submitting = true
                    try await library.execution.sendWithGoal(id: session.sessionID, prompt: submittedPrompt, model: submittedModel, effort: submittedEffort, attachments: submittedAttachments, approvalReview: submittedReview, mode: submittedMode, capabilities: submittedCapabilities, goal: submittedGoal)
                }
                if optimistic {
                    library.outgoing[message.id]?.state = .accepted
                    library.outgoing[message.id]?.turnID = library.execution.tasks[session.sessionID]?.turnID
                    library.retryOutgoing.removeValue(forKey: message.id)
                    library.reconcileOutgoing(session.sessionID)
                } else {
                    prompt = ""; attachments = []
                    approvalReview = .inherit; capabilities = []; queueNext = false
                }
            } catch {
                if let id = switchedMessage {
                    library.outgoing[id]?.state = submitting && !(error is ExecutionRPCRejection) ? .uncertain : .failed
                    library.outgoing[id]?.error = error.localizedDescription; library.persistOutgoing()
                    self.error = error.localizedDescription
                } else if optimistic {
                    if error is ExecutionRPCRejection, prompt.isEmpty {
                        prompt = submittedPrompt; attachments = submittedAttachments
                        approvalReview = library.execution.tasks[session.sessionID]?.reportedPermissionChoice == submittedReview ? .inherit : submittedReview
                        library.saveDraft(session.id, text: submittedPrompt, attachments: submittedAttachments)
                    }
                    let uncertain = submitting && !(error is ExecutionRPCRejection)
                    library.outgoing[message.id]?.state = uncertain ? .uncertain : .failed
                    library.outgoing[message.id]?.error = error.localizedDescription
                    library.persistOutgoing()
                } else { self.error = error.localizedDescription }
            }
        }
        if optimistic {
            library.retryOutgoing[message.id] = {
                guard !sending, library.outgoing[message.id]?.state == .failed else { return }
                sending = true
                Task { await perform() }
            }
        }
        Task { await perform() }
    }
}


struct LockedConversationComposer: View {
    let checking: Bool
    let details: String
    let retry: () -> Void
    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "lock").font(.system(size: 21, weight: .regular)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("This is open in another app").font(.system(size: 14, weight: .semibold))
                Text("Quit the app using it, then retry here.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 36)
            Button(action: retry) {
                HStack(spacing: 6) {
                    if checking { ProgressView().controlSize(.small) }
                    Text(checking ? "Checking…" : "Retry")
                }.frame(minWidth: 62, minHeight: 36)
            }.pointingHand().buttonStyle(.plain).disabled(checking).accessibilityLabel(checking ? "Checking conversation availability" : "Retry continuation")
        }
        .padding(.horizontal, 22).padding(.vertical, 22)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .contextMenu { Button("Show connection details") { showingDetails = true }.pointingHand() }
        .popover(isPresented: $showingDetails) { Text(details).font(.caption).textSelection(.enabled).padding(20).frame(width: 360) }
        .help("Closing a window may not release the conversation. Finish any work in the other app before quitting. Right-click for provider details.")
    }
}

/// Presentation only: the controller retains responsibility for turn and permission checks.
struct ConversationComposer: View {
    let controller: ExecutionController
    @Binding var model: String
    @Binding var effort: String
    @Binding var prompt: String
    @Binding var attachments: [ConversationAttachment]
    @Binding var approvalReview: ApprovalReviewChoice
    let effectiveModel: String
    var effectiveEffort = ""
    var reviewer: String? = nil
    var policy: WireValue = .null
    var sandbox: WireValue = .null
    let sending: Bool
    let active: Bool
    var canSteer = false
    var queued = false
    var capabilities: Binding<[CapabilityInput]> = .constant([])
    var folder = ""
    var threadID: String? = nil
    var mode: Binding<String> = .constant("default")
    var goalMode: Binding<Bool> = .constant(false)
    var queueMode: Binding<Bool> = .constant(false)
    var queueAvailable = true
    var creationPresentation = false
    let send: () -> Void
    @Environment(\.avatarMessages) private var avatarMessages
    @Environment(\.avatarConversationTools) private var avatarConversationTools
    @State private var showingOptions = false
    @State private var showingCreationDetails = false
    @State private var showingCreationIntegrations = false
    @FocusState private var optionsFocused: Bool
    @State private var messageHeight: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme
    @State private var pasteError: String?
    @State private var stoppingTurn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if creationPresentation {
                creationComposer
            } else if avatarMessages {
                messagesComposer
            } else {
            VStack(alignment: .leading, spacing: 12) {
                if !attachments.isEmpty { AttachmentPicker(attachments: $attachments, disabled: sending, showsButton: false) }
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty { Text("Do anything").font(.system(size: 16)).foregroundStyle(.tertiary).padding(.top, 4).padding(.leading, 5).allowsHitTesting(false) }
                    ComposerTextEditor(text: $prompt, attachments: $attachments, error: $pasteError, disabled: false) {
                        if !sending && (!active || canSteer) && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) { send() }
                    }.frame(height: 64)
                }
                if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.orange) }
                ComposerToolbarLayout {
                    leadingControls
                    trailingControls
                }

            }
            .padding(16)
            .background(colorScheme == .dark ? DioramaStyle.raised : Color(white: 0.97), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }.modifier(AttachmentDropTarget(attachments: $attachments, disabled: sending))
        .onChange(of: model) { oldModel, newModel in
            if (oldModel.isEmpty ? effectiveModel : oldModel).hasPrefix("claude/") != (newModel.isEmpty ? effectiveModel : newModel).hasPrefix("claude/") { approvalReview = .inherit }
            if model.hasPrefix("claude/") { effort = ""; capabilities.wrappedValue = [] }
            if approvalReview == .fullAccess || (approvalReview == .acceptEdits && !model.hasPrefix("claude/")) || (approvalReview == .autoReview && controller.models.first(where: { $0.id == model })?.supportsAutoMode == false) {
                approvalReview = .inherit
                pasteError = "Permission options changed with the model. Review the selected mode before sending."
            }
        }

    }
    private var creationComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !attachments.isEmpty { AttachmentPicker(attachments: $attachments, disabled: sending, showsButton: false) }
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("What would you like to work on?").font(.system(size: 16)).foregroundStyle(.tertiary)
                        .padding(.top, 4).padding(.leading, 5).allowsHitTesting(false)
                }
                ComposerTextEditor(text: $prompt, attachments: $attachments, error: $pasteError, disabled: sending) {
                    if !sending && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) { send() }
                }.frame(height: 140)
            }
            if mode.wrappedValue == "plan" || goalMode.wrappedValue {
                HStack {
                    if mode.wrappedValue == "plan" { Button("Plan Mode ×") { mode.wrappedValue = "default" }.pointingHand() }
                    if goalMode.wrappedValue { Button("Goal ×") { goalMode.wrappedValue = false }.pointingHand() }
                }.font(.caption).disabled(sending)
            }
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 12) {
                ComposerModelMenu(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel, effectiveEffort: effectiveEffort)
                    .disabled(sending)
                Spacer(minLength: 8)
                Button { showingOptions.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 18)).frame(width: 28, height: 28)
                }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0)).accessibilityLabel("Agent options")
                    .popover(isPresented: $showingOptions) {
                        creationOptions
                            .environment(\.colorScheme, .light).tint(.blue)
                            .avatarPopoverDismissal(isPresented: $showingOptions)
                    }
                Button(action: send) {
                    Text(sending ? "Creating…" : "Create").fontWeight(.semibold)
                        .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.blue.opacity(sending || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) ? 0.4 : 1), in: Capsule())
                }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0, radius: 20, prominent: true))
                    .disabled(sending || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
            }
        }
    }

    private var messagesComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty { AttachmentPicker(attachments: $attachments, disabled: sending, showsButton: false) }
            let modes = [mode.wrappedValue == "plan" ? "Plan Mode" : nil, goalMode.wrappedValue ? "Goal" : nil, queueMode.wrappedValue ? "Queue" : nil].compactMap { $0 }
            if !modes.isEmpty { Text(modes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 10) {
                Button { showingOptions.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 21, weight: .medium)).foregroundStyle(.secondary).frame(width: 32, height: 36)
                }.pointingHand().buttonStyle(.plain).accessibilityLabel("Conversation options")
                    .popover(isPresented: $showingOptions, arrowEdge: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Message options").font(.headline)
                                VStack(alignment: .leading, spacing: 12) {
                                    leadingControls
                                    ComposerModelMenu(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel, effectiveEffort: effectiveEffort).disabled(sending || active)
                                }
                                Divider()
                                avatarConversationTools
                            }.padding(18).frame(width: 340, alignment: .leading)
                        }.frame(maxHeight: 540).environment(\.colorScheme, .light).tint(.blue)
                            .focusable().focused($optionsFocused)
                            .onAppear { optionsFocused = true }
                    .avatarPopoverDismissal(isPresented: $showingOptions)
                    }
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty { Text("Message").foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 4).allowsHitTesting(false) }
                    ComposerTextEditor(text: $prompt, attachments: $attachments, error: $pasteError, disabled: false, measuredHeight: $messageHeight) {
                        if !sending && (!active || canSteer) && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) { send() }
                    }.frame(height: max(28, min(128, messageHeight)))
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.white, in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.black.opacity(0.15)))
                trailingControls
            }
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.orange) }
        }
    }

    private var switchingPermissionProvider: Bool { !model.isEmpty && model.hasPrefix("claude/") != effectiveModel.hasPrefix("claude/") }
    private var leadingControls: some View {
        let layout = (avatarMessages || creationPresentation) ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
                    ComposerAddMenu(controller: controller, folder: folder, threadID: threadID, attachments: $attachments, capabilities: capabilities, disabled: sending, claude: (model.isEmpty ? effectiveModel : model).hasPrefix("claude/"))
                    permissionControl
                    ComposerModeToggles(mode: mode, goal: goalMode, queue: queueMode, showQueue: !creationPresentation, modeDisabled: sending || active, queueDisabled: sending || !queueAvailable)
        }
    }
    private var permissionControl: some View {
        ApprovalReviewPicker(selection: $approvalReview, reviewer: switchingPermissionProvider ? nil : reviewer, policy: switchingPermissionProvider ? .null : policy, sandbox: switchingPermissionProvider ? .null : sandbox, iconOnly: true, claude: (model.isEmpty ? effectiveModel : model).hasPrefix("claude/"), isNew: threadID == nil || switchingPermissionProvider,
                        supportsAutoMode: controller.models.first(where: { $0.id == (model.isEmpty ? effectiveModel : model) })?.supportsAutoMode,
                        unavailable: Dictionary(uniqueKeysWithValues: ApprovalReviewChoice.allCases.compactMap { choice in controller.permissionUnavailable(choice, model: model.isEmpty ? effectiveModel : model).map { (choice, $0) } }),
                        stale: threadID.flatMap { controller.tasks[$0] }.map { !$0.attached } ?? false,
                        unconfirmed: threadID.flatMap { controller.tasks[$0]?.permissionsUnconfirmed } ?? false,
                        notice: threadID.flatMap { controller.tasks[$0]?.permissionNotice }).disabled(sending || active || controller.requests.values.contains { $0.threadID == threadID && $0.isBlocking })
    }
    private var creationOptions: some View {
        VStack(spacing: 2) {
            Button {
                mode.wrappedValue = mode.wrappedValue == "plan" ? "default" : "plan"
                if mode.wrappedValue == "plan" { goalMode.wrappedValue = false }
                showingOptions = false
            } label: {
                ComposerOptionLabel(title: "Plan mode", icon: "map", checked: mode.wrappedValue == "plan")
            }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0)).disabled(sending)
            Button {
                goalMode.wrappedValue.toggle()
                if goalMode.wrappedValue { mode.wrappedValue = "default" }
                showingOptions = false
            } label: {
                ComposerOptionLabel(title: "Goal mode", icon: "scope", checked: goalMode.wrappedValue)
            }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0)).disabled(sending)
            AttachmentPicker(attachments: $attachments, disabled: sending, showsAttachments: false, iconOnly: true, menuRow: true)
            Divider().padding(.horizontal, 8).padding(.vertical, 3)
            Button { showingCreationDetails.toggle() } label: {
                ComposerOptionLabel(title: "More options", icon: "ellipsis", disclosure: true)
            }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0))
                .popover(isPresented: $showingCreationDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                        permissionControl
                        if !(model.isEmpty ? effectiveModel : model).hasPrefix("claude/") {
                            Button { showingCreationIntegrations = true } label: {
                                Label("Skills & connectors…", systemImage: "square.stack.3d.up")
                            }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0)).disabled(sending)
                        }
                    }.padding(16).environment(\.colorScheme, .light)
                        .avatarPopoverDismissal(isPresented: $showingCreationDetails)
                        .sheet(isPresented: $showingCreationIntegrations) {
                            IntegrationPicker(controller: controller, folder: folder, threadID: threadID, selection: capabilities)
                                .background(Color.white).presentationBackground(Color.white).preferredColorScheme(.light)
                        }
                }
        }.padding(6).frame(width: 250)
    }

    private var trailingControls: some View {
        HStack(spacing: 12) {
                    if !avatarMessages {
                        ComposerModelMenu(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel, effectiveEffort: effectiveEffort).disabled(sending || active)
                    }
                    if active && !queued && (model.isEmpty ? effectiveModel : model).hasPrefix("claude/") && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Interrupt & steer", action: send).pointingHand().font(.caption).disabled(sending || !canSteer)
                    }
                    if active && queued {
                        Button("Queue message", action: send).pointingHand().font(.caption)
                            .disabled(sending || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    }
                    Button {
                        if active { stopTurn() } else { send() }
                    } label: {
                        Image(systemName: active ? "stop.fill" : "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 36, height: 36)
                            .background(avatarMessages ? Color.blue : DioramaStyle.accent, in: Circle())
                    }.pointingHand()
                    .buttonStyle(.plain)
                    .accessibilityLabel(active ? "Stop task" : queued ? "Queue message" : "Send message")
                    .help(active ? "Stop the current task" : "Send message (Return); Shift-Return adds a new line")
                    .disabled(active ? stoppingTurn || threadID.flatMap { controller.tasks[$0]?.turnID } == nil : sending || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))        }
    }
    private func stopTurn() {
        guard let threadID, !stoppingTurn else { return }
        stoppingTurn = true
        Task {
            defer { stoppingTurn = false }
            do { try await controller.interrupt(id: threadID) }
            catch { pasteError = error.localizedDescription }
        }
    }
}

private struct HelpLink: View {
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName: "info.circle") }.pointingHand()
            .popover(isPresented: $showing) { Text(text).padding(20).frame(width: 340) }
    }
}

@MainActor
final class DioramaApplicationDelegate: NSObject, NSApplicationDelegate {
    var execution: ExecutionController?
    var developmentReload: DevelopmentReload?
    func applicationDidFinishLaunching(_ notification: Notification) { NSWindow.allowsAutomaticWindowTabbing = false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let developmentReload, developmentReload.isRequestingQuit {
            return .terminateNow // Development reload has already completed idle shutdown.
        }
        guard let execution else { return .terminateNow }
        guard execution.connected || execution.hasUncertainWork else { return .terminateNow }
        Task {
            do {
                if try await execution.requiresQuitConfirmation() {
                    let alert = NSAlert(); alert.messageText = "Stop Diorama tasks before quitting?"
                    alert.informativeText = "Closing a window keeps work running. Quitting stops Diorama tasks and their remaining terminal commands. Tasks in other clients are unaffected."
                    alert.addButton(withTitle: "Keep running"); alert.addButton(withTitle: "Stop tasks and quit")
                    guard alert.runModal() == .alertSecondButtonReturn else { sender.reply(toApplicationShouldTerminate: false); return }
                }
                try await execution.stopAndShutdown(); sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert(); alert.messageText = "Diorama is still open"; alert.informativeText = error.localizedDescription; alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}

struct PlanModeToggle: View {
    @Binding var mode: String

    var body: some View {
        Toggle("Plan Mode", isOn: Binding(
            get: { mode == "plan" },
            set: { mode = $0 ? "plan" : "default" }
        )).pointingHand()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.caption)
        .fixedSize()
        .help("Plan before implementing. Applies when you send your next message. Turn off to return to normal mode.")
    }
}

struct ComposerModeToggles: View {
    @Environment(\.avatarMessages) private var avatarMessages
    @Binding var mode: String
    @Binding var goal: Bool
    @Binding var queue: Bool
    var showQueue = true
    var showGoal = true
    var modeDisabled = false
    var queueDisabled = false
    var body: some View {
        let layout = avatarMessages ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Toggle("Plan Mode", isOn: Binding(get: { mode == "plan" }, set: { enabled in
                mode = enabled ? "plan" : "default"
                if enabled { goal = false }
            })).pointingHand().disabled(modeDisabled)
            if showGoal { Toggle("Goal", isOn: Binding(get: { goal }, set: { enabled in
                goal = enabled
                if enabled { mode = "default"; queue = false }
            })).pointingHand().disabled(modeDisabled).help("Use your next message as a goal to keep pursuing. Applies when sent.")
            }
            if showQueue {
                Toggle("Queue", isOn: Binding(get: { queue }, set: { enabled in
                    queue = enabled
                    if enabled { goal = false }
                })).pointingHand().disabled(queueDisabled).help("Queue your message for the next run")
            }
        }.toggleStyle(.switch).controlSize(.mini).font(.caption).fixedSize()
    }
}

/// Reflows the same controls instead of instantiating two copies of native popovers.
struct ComposerToolbarLayout: Layout {
    var spacing: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? leading.width + spacing + trailing.width
        let fits = leading.width + spacing + trailing.width <= width
        return CGSize(width: width, height: fits ? max(leading.height, trailing.height) : leading.height + spacing + trailing.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let fits = leading.width + spacing + trailing.width <= bounds.width
        subviews[0].place(at: CGPoint(x: bounds.minX, y: fits ? bounds.midY - leading.height / 2 : bounds.minY), proposal: ProposedViewSize(leading))
        subviews[1].place(at: CGPoint(x: max(bounds.minX, bounds.maxX - trailing.width), y: fits ? bounds.midY - trailing.height / 2 : bounds.maxY - trailing.height), proposal: ProposedViewSize(trailing))
    }
}

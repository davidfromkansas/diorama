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
                    Button(claude ? "Log in to Anthropic…" : "Log in to OpenAI…") { openSettings() }
                } else {
                    ForEach(choices) { choice in
                        Button { model = choice.id; effort = "" } label: {
                            HStack { Text(choice.name); Spacer(); if choice.id == (model.isEmpty ? effectiveModel : model) { Image(systemName: "checkmark") } }
                        }.buttonStyle(.plain)
                    }
                }
            }
            let levels = controller.models.first { $0.id == (model.isEmpty ? effectiveModel : model) }?.efforts ?? []
            if !levels.isEmpty {
                Picker("Reasoning", selection: $effort) {
                    Text("Default").tag("")
                    ForEach(levels, id: \.self) { Text($0.capitalized).tag($0) }
                }
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
                }.disabled(preparedID != nil || busy)
            }
            ExecutionModelPicker(controller: library.execution, model: $model, effort: $effort, effectiveModel: preparedID.flatMap { library.execution.tasks[$0]?.model } ?? "")
                .disabled(preparedID != nil || busy)
            ComposerTextEditor(text: $prompt, attachments: $attachments, error: $pasteError, disabled: busy)
                .frame(height: 130).border(Color.secondary.opacity(0.3))
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.orange) }
            ComposerAddMenu(controller: library.execution, folder: folder, threadID: preparedID, attachments: $attachments, capabilities: $capabilities, disabled: busy, showsAttachments: true)
            ComposerModeToggles(mode: $mode, goal: $goalMode, queue: $queueNext, showQueue: false).disabled(busy)
            ApprovalReviewPicker(selection: $approvalReview, reviewer: preparedID.flatMap { library.execution.tasks[$0]?.approvalReviewer }, policy: preparedID.flatMap { library.execution.tasks[$0]?.approvalPolicy } ?? .null, sandbox: preparedID.flatMap { library.execution.tasks[$0]?.sandbox } ?? .null).disabled(busy)
            if let id = preparedID, let task = library.execution.tasks[id] {
                WorkflowControls(controller: library.execution, task: task, mode: $mode, capabilities: $capabilities, queueNext: $queueNext)
                Text("Ready to send · effective settings").font(.headline)
                ScrollView { Text(task.settings).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 130)
                Text("Codex’s current permissions apply. Your review choice takes effect when you send; global settings are unchanged.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = error ?? library.execution.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !library.execution.connected { Button("Connect to Codex") { Task { await library.execution.connect() } }.disabled(library.execution.connecting) }
            HStack {
                Button("Cancel") { dismiss() }.disabled(busy)
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
                                let id = try await library.execution.prepare(folder: folder, title: prompt, model: model)
                                preparedID = id; library.selectOwned(id)
                            }
                        } catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent)
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
                PermissionReviewCard(request: request, connected: controller.connected, respond: respond)
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
                        }
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
                }.disabled(request.params["questions"].array.contains { answers[$0["id"].string ?? "", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            } else if request.method == "item/permissions/requestApproval" {
                Text(request.params["permissions"].pretty).font(.caption.monospaced()).textSelection(.enabled)
                HStack {
                    Button("Allow for this turn") { respond(.object(["permissions": request.params["permissions"], "scope": .string("turn")])) }
                    Button("Deny") { respond(.object(["permissions": .object([:]), "scope": .string("turn")])) }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(request.approvalDecisions) { decision in
                        VStack(alignment: .leading, spacing: 4) {
                            if let scope = decision.scope { Text(scope).font(.caption.monospaced()).textSelection(.enabled) }
                            Button(decision.title) { respond(.object(["decision": decision.value])) }
                        }
                    }
                }
                if request.approvalDecisions.isEmpty { Text("This approval requires an unsupported decision type. Use the square Stop button in the composer to cancel.").foregroundStyle(.orange) }
            }
            DisclosureGroup("Request details") { Text(request.params.pretty).font(.caption.monospaced()).textSelection(.enabled) }
            if request.responding { Text("Response sent · awaiting provider resolution").font(.caption) }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).disabled(request.responding || !controller.connected)
    }
    private func respond(_ result: WireValue) {
        Task { do { try await controller.answer(id: request.id, result: result) } catch { self.error = error.localizedDescription } }
    }
}

struct ExecutionControls: View {
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
        if let task = library.execution.tasks[session.sessionID], task.attached, task.phase != .disconnected {
            VStack(alignment: .leading, spacing: 10) {
                if let error = error ?? task.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if !model.isEmpty, model.hasPrefix("claude/") != (session.provider == .claude) { Text("Your next message continues here with the selected provider. Files and branch stay unchanged.").font(.caption).foregroundStyle(.secondary) }
                if let notice = task.reviewNotice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if let notice = task.canvasNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
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
                                Button("Resume") { Task { do { try await library.resumeCarriedQueue(conversationID: record.id, submissionID: item.id) } catch { self.error = error.localizedDescription } } }
                                    .disabled(task.phase.active || sending || library.conversations.queueOperations.contains(record.id))
                                Button { Task { do { try await library.removeCarriedQueue(conversationID: record.id, submissionID: item.id) } catch { self.error = error.localizedDescription } } } label: { Image(systemName: "xmark") }
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
                DisclosureGroup("Your message") {
                    Text(prompt).textSelection(.enabled)
                    AttachmentPicker(attachments: $attachments, disabled: sending)
                }.font(.caption)
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
                        }.disabled(library.execution.resuming.contains(session.sessionID))
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
                    }.disabled(library.execution.resuming.contains(session.sessionID))
                } else {
                    ConversationComposer(controller: library.execution, model: $model, effort: $effort, prompt: $prompt, attachments: $attachments, approvalReview: $approvalReview,
                                         effectiveModel: session.provider == .claude ? "claude/default" : "", sending: sending, active: false, queued: queueNext, capabilities: $capabilities, folder: session.project, threadID: nil, mode: $mode, goalMode: $goalMode, queueMode: $queueNext) { submit() }
                }
                if library.execution.resumeErrors[session.sessionID]?.contains("active goal") == true {
                    Button("Pause goal and reconnect") { Task { do { try await library.execution.pauseGoalAndResume(session: session) } catch { self.error = error.localizedDescription } } }
                }
                if let message = error ?? library.execution.resumeErrors[session.sessionID] {
                    Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }.padding(16)
        }
        }
        .task(id: session.id) {
            recoveredGoal = session.provider == .claude ? ClaudeExecutionTransport.savedGoal(sessionID: session.sessionID) : .null
        }
        .onAppear {
            if session.provider == .claude { model = library.execution.tasks[session.sessionID]?.model ?? "claude/default" }
            if let draft = library.drafts[session.id] {
                prompt = draft.text
                attachments = draft.attachments.compactMap { try? ConversationAttachment(url: URL(fileURLWithPath: $0)) }
            }
        }
        .onChange(of: library.drafts[session.id]?.text) { if let text = library.drafts[session.id]?.text, text != prompt { prompt = text } }
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
            library.scrollPositions[session.id] = message.id
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
                    let previousTask = library.execution.tasks[session.sessionID]
                    let review = submittedReview == .inherit ? (ApprovalReviewChoice.reported(reviewer: previousTask?.approvalReviewer, policy: previousTask?.approvalPolicy ?? .null, sandbox: previousTask?.sandbox ?? .null) ?? .user) : submittedReview
                    let target = try await library.switchProvider(from: session, model: submittedModel)
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
            }.buttonStyle(.plain).disabled(checking).accessibilityLabel(checking ? "Checking conversation availability" : "Retry continuation")
        }
        .padding(.horizontal, 22).padding(.vertical, 22)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .contextMenu { Button("Show connection details") { showingDetails = true } }
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
    let send: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var pasteError: String?
    @State private var stoppingTurn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .background(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.97), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }.modifier(AttachmentDropTarget(attachments: $attachments, disabled: sending))
        .onChange(of: model) {
            if model.hasPrefix("claude/") { effort = ""; capabilities.wrappedValue = [] }
        }

    }
    private var leadingControls: some View {
        HStack(spacing: 12) {
                    ComposerAddMenu(controller: controller, folder: folder, threadID: threadID, attachments: $attachments, capabilities: capabilities, disabled: sending, claude: (model.isEmpty ? effectiveModel : model).hasPrefix("claude/"))
                    ApprovalReviewPicker(selection: $approvalReview, reviewer: reviewer, policy: policy, sandbox: sandbox, iconOnly: true, claude: (model.isEmpty ? effectiveModel : model).hasPrefix("claude/")).disabled(sending || active)
                    ComposerModeToggles(mode: mode, goal: goalMode, queue: queueMode, modeDisabled: sending || active, queueDisabled: sending || !queueAvailable)
        }
    }
    private var trailingControls: some View {
        HStack(spacing: 12) {
                    ComposerModelMenu(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel, effectiveEffort: effectiveEffort).disabled(sending || active)
                    if active && !queued && (model.isEmpty ? effectiveModel : model).hasPrefix("claude/") && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Interrupt & steer", action: send).font(.caption).disabled(sending || !canSteer)
                    }
                    if active && queued {
                        Button("Queue message", action: send).font(.caption)
                            .disabled(sending || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    }
                    Button {
                        if active { stopTurn() } else { send() }
                    } label: {
                        Image(systemName: active ? "stop.fill" : "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 36, height: 36)
                            .background(Color(red: 0.16, green: 0.39, blue: 0.79), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(active ? "Stop task" : queued ? "Queue message" : "Send message")
                    .help(active ? "Stop the current task" : "Send message (⌘Return)")
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
        Button { showing.toggle() } label: { Image(systemName: "info.circle") }
            .popover(isPresented: $showing) { Text(text).padding(20).frame(width: 340) }
    }
}

@MainActor
final class DioramaApplicationDelegate: NSObject, NSApplicationDelegate {
    var execution: ExecutionController?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        ))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.caption)
        .fixedSize()
        .help("Plan before implementing. Applies when you send your next message. Turn off to return to normal mode.")
    }
}

struct ComposerModeToggles: View {
    @Binding var mode: String
    @Binding var goal: Bool
    @Binding var queue: Bool
    var showQueue = true
    var showGoal = true
    var modeDisabled = false
    var queueDisabled = false
    var body: some View {
        HStack(spacing: 10) {
            Toggle("Plan Mode", isOn: Binding(get: { mode == "plan" }, set: { enabled in
                mode = enabled ? "plan" : "default"
                if enabled { goal = false }
            })).disabled(modeDisabled)
            if showGoal { Toggle("Goal", isOn: Binding(get: { goal }, set: { enabled in
                goal = enabled
                if enabled { mode = "default"; queue = false }
            })).disabled(modeDisabled).help("Use your next message as a goal to keep pursuing. Applies when sent.")
            }
            if showQueue {
                Toggle("Queue", isOn: Binding(get: { queue }, set: { enabled in
                    queue = enabled
                    if enabled { goal = false }
                })).disabled(queueDisabled).help("Queue your message for the next run")
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

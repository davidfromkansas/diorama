import DioramaCore
import SwiftUI

/// What a pending request asks, for its band and the sidebar's words.
enum RequestKind: Equatable {
    case approval, permissions, question, connector
    init(_ request: ExecutionRequest) {
        if request.isInput { self = .question }
        else if request.isElicitation { self = .connector }
        else if request.method == "item/permissions/requestApproval" { self = .permissions }
        else { self = .approval }
    }
    var status: String {
        switch self { case .approval, .permissions: "Needs approval"; case .question: "Needs an answer"; case .connector: "Connector request" }
    }
    func band(blocking: Bool) -> (title: String, detail: String) {
        switch self {
        case .approval, .permissions: ("Approval requested", blocking ? "work paused" : "work continues")
        case .question: ("Question", blocking ? "work paused until you answer" : "work continues")
        case .connector: ("Connector request", blocking ? "work paused" : "work continues")
        }
    }
}

/// The buttons an approval offers, in footer order (quiet ones first, the main one last); the
/// rest (cancel the turn, save a rule) sit under More options. Payloads are exactly what the
/// provider expects, as before.
struct RequestDecisions: Equatable {
    struct Choice: Equatable, Identifiable {
        let id: String
        let title: String
        let scope: String?
        let result: WireValue
        let primary: Bool
    }
    var footer: [Choice] = []
    var more: [Choice] = []
    init(_ request: ExecutionRequest) {
        if request.method == "item/permissions/requestApproval" {
            footer = [Choice(id: "deny", title: "Deny", scope: nil, result: .object(["permissions": .object([:]), "scope": .string("turn")]), primary: false),
                      Choice(id: "allow", title: "Allow for this turn", scope: nil, result: .object(["permissions": request.params["permissions"], "scope": .string("turn")]), primary: true)]
            return
        }
        let rank = ["decline": 0, "acceptForSession": 1, "accept": 2]
        for decision in request.approvalDecisions {
            let key = decision.value.string ?? ""
            let choice = Choice(id: decision.id, title: decision.title, scope: decision.scope, result: .object(["decision": decision.value]), primary: key == "accept")
            if rank[key] != nil && decision.scope == nil { footer.append(choice) } else { more.append(choice) }
        }
        footer.sort { (rank[$0.result["decision"].string ?? ""] ?? 9) < (rank[$1.result["decision"].string ?? ""] ?? 9) }
    }
}

/// A request's body and actions in the agent-sidebar style: shared by the modal and the
/// conversation panel's card, so the two always match.
struct RequestReviewContent<Leading: View>: View {
    let request: ExecutionRequest
    let controller: ExecutionController
    /// "1 of 2" when several wait.
    var position: String? = nil
    /// The conversation panel's card: a status line instead of the band, tighter spacing, and
    /// request details behind a footer link, so the composer below keeps its room.
    var compact = false
    /// Desktop modal: a single question's own answer moves to a right-hand column.
    var wide = false
    @ViewBuilder var leading: Leading
    var skip: (() -> Void)? = nil
    @State private var answers: [String: String] = [:]
    @State private var error: String?
    @State private var details = false
    private var kind: RequestKind { RequestKind(request) }
    private var unavailable: Bool { request.responding || !controller.connected }

    var body: some View {
        let band = kind.band(blocking: request.isBlocking)
        VStack(spacing: 0) {
            if !compact { ModalBand(group: .needsYou, title: band.title, detail: band.detail, trailing: position) }
            if let wideQuestion {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        questionText(wideQuestion.question)
                        options(wideQuestion.question, id: wideQuestion.id)
                        statusLines
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    ownAnswer(wideQuestion.question, id: wideQuestion.id, tall: true)
                        .padding(16).frame(width: 280).frame(maxHeight: .infinity, alignment: .top)
                        .background(Color(red: 0.976, green: 0.965, blue: 0.945))
                        .overlay(alignment: .leading) { Rectangle().fill(SidebarStyle.divider).frame(width: 1) }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                if compact {
                    HStack(spacing: 6) {
                        Circle().fill(SidebarStyle.tint(.needsYou).dot).frame(width: 7, height: 7)
                        Text(band.title + " · " + band.detail).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(SidebarStyle.tint(.needsYou).text)
                }
                switch kind {
                case .question: questions
                case .connector: ElicitationFormView(request: request, respond: respond)
                case .approval, .permissions: approval
                }
                statusLines
            }
            .padding(compact ? 12 : 16).frame(maxWidth: .infinity, alignment: .leading)
            }
            ModalFooter {
                leading
                if compact, kind == .approval || kind == .permissions {
                    Button(details ? "Hide details" : "Details") { details.toggle() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SidebarStyle.accent).pointingHand()
                }
            } actions: { actions }
        }
        .foregroundStyle(SidebarStyle.title)
    }

    @ViewBuilder private var statusLines: some View {
        if unavailable {
            Text(request.responding ? "Sending… waiting for the agent" : "Connection lost · reconnect to respond")
                .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
        }
        if let error { Text(error).font(.system(size: 12)).foregroundStyle(ModalStyle.red).textSelection(.enabled) }
    }

    // MARK: Approval
    private var presentation: PermissionPresentation {
        PermissionPresentation(request: request, relatedItem: controller.tasks[request.threadID]?.transcript.entries.last(where: {
            $0.tool?.item["id"] == request.params["itemId"] && $0.turnID == request.params["turnId"].string
        })?.tool?.item ?? .null)
    }
    private var approval: some View {
        let presentation = presentation
        let decisions = RequestDecisions(request)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title).font(.system(size: 13, weight: .semibold))
                if let reason = presentation.reason {
                    Text(reason).font(.system(size: 13)).foregroundStyle(Color(red: 0.23, green: 0.23, blue: 0.24)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(presentation.target).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                .lineLimit(compact ? 2 : 6).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(ModalStyle.field))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ModalStyle.border))
            VStack(spacing: 0) {
                if !compact {
                    ModalDivider()
                    if let cwd = request.params["cwd"].string, !cwd.isEmpty {
                        row("Runs in") { Text((cwd as NSString).lastPathComponent).font(.system(size: 11.5, design: .monospaced)) }
                    }
                    row("Scope") { Text(presentation.scope).font(.system(size: 12)) }
                    Button { details.toggle() } label: {
                        row("Request details") { Text(details ? "Hide" : "Show ›").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary) }
                    }
                    .buttonStyle(.plain).pointingHand().accessibilityValue(details ? "expanded" : "collapsed")
                }
                if details {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(decisions.more) { choice in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if let scope = choice.scope { Text(scope).font(ModalStyle.mono).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                else { Spacer() }
                                Button(choice.title) { respond(choice.result) }.buttonStyle(ModalSecondaryButtonStyle(height: 26)).disabled(unavailable)
                            }
                        }
                        ScrollView { Text(presentation.details).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 160)
                    }
                    .padding(.vertical, 10)
                }
            }
            if decisions.footer.isEmpty && decisions.more.isEmpty {
                Text("This approval needs a decision Diorama can't send. Use Stop in the composer to cancel.").font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
    }
    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            Spacer()
            value()
        }
        .frame(height: 32).contentShape(Rectangle())
        .overlay(alignment: .bottom) { ModalDivider() }
    }

    // MARK: Question
    /// On desktop a single question with options goes side by side: the options on the left,
    /// your own answer in a taller box on the right (a wider, shorter modal).
    private var wideQuestion: (question: WireValue, id: String)? {
        guard wide, RequestReviewModal.sideBySide(request) else { return nil }
        let question = request.params["questions"].array[0]
        return (question, question["id"].string ?? "")
    }
    private var questions: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(request.params["questions"].array, id: \.pretty) { question in
                let id = question["id"].string ?? ""
                VStack(alignment: .leading, spacing: 10) {
                    questionText(question)
                    options(question, id: id)
                    ownAnswer(question, id: id, tall: false)
                }
            }
        }
    }
    private func questionText(_ question: WireValue) -> some View {
        Text(question["question"].string ?? "Question").font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func options(_ question: WireValue, id: String) -> some View {
        let options = question["options"].array
        if !options.isEmpty {
            VStack(spacing: 0) {
                ModalDivider()
                ForEach(options, id: \.pretty) { option in
                    let label = option["label"].string ?? "Option"
                    let chosen = answers[id] == label
                    Button { answers[id] = label } label: {
                        HStack(spacing: 10) {
                            Image(systemName: chosen ? "largecircle.fill.circle" : "circle").font(.system(size: 14))
                                .foregroundStyle(chosen ? SidebarStyle.accent : SidebarStyle.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label).font(.system(size: 13, weight: .semibold))
                                if let description = option["description"].string, !description.isEmpty {
                                    Text(description).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 52)
                        .background(chosen ? SidebarStyle.selected : Color.clear)
                        .overlay(alignment: .leading) { if chosen { Rectangle().fill(SidebarStyle.accent).frame(width: 3) } }
                        .overlay(alignment: .bottom) { ModalDivider() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).pointingHand()
                    .accessibilityAddTraits(chosen ? [.isSelected] : [])
                }
            }
        }
    }
    private func ownAnswer(_ question: WireValue, id: String, tall: Bool) -> some View {
        let hasOptions = !question["options"].array.isEmpty
        let binding = Binding(get: { answers[id, default: ""] }, set: { answers[id] = $0 })
        return VStack(alignment: .leading, spacing: tall ? 8 : 6) {
            Text(hasOptions ? "Or write your own answer" : "Your answer")
                .font(.system(size: tall ? 13 : 12, weight: tall ? .semibold : .regular))
                .foregroundStyle(tall ? SidebarStyle.title : SidebarStyle.secondary)
            if tall {
                Text("Typing here replaces the option you picked.").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                TextField("Something else…", text: binding, axis: .vertical).lineLimit(5...9)
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ModalStyle.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ModalStyle.border))
            } else {
                Group {
                    if question["isSecret"].bool { SecureField("Answer", text: binding) } else { TextField("Something else…", text: binding) }
                }
                .textFieldStyle(.plain).font(.system(size: 13)).padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(ModalStyle.field))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ModalStyle.border))
            }
        }
    }
    private var questionsAnswered: Bool {
        !request.params["questions"].array.contains { answers[$0["id"].string ?? "", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Actions
    @ViewBuilder private var actions: some View {
        switch kind {
        case .question:
            if let skip { Button("Skip", action: skip).buttonStyle(ModalSecondaryButtonStyle()) }
            Button(request.responding ? "Sending…" : "Send answer") {
                let values = answers.mapValues { WireValue.object(["answers": .array([.string($0)])]) }
                respond(.object(["answers": .object(values)]))
            }
            .buttonStyle(ModalPrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(unavailable || !questionsAnswered)
        case .connector:
            EmptyView()
        case .approval, .permissions:
            ForEach(RequestDecisions(request).footer) { choice in
                if choice.primary {
                    Button(choice.title) { respond(choice.result) }.buttonStyle(ModalPrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(unavailable)
                } else {
                    Button(choice.title) { respond(choice.result) }.buttonStyle(ModalSecondaryButtonStyle()).disabled(unavailable)
                }
            }
        }
    }
    private func respond(_ result: WireValue) {
        error = nil
        Task { do { try await controller.answer(id: request.id, result: result, expectedInstance: request.instanceID) } catch { self.error = error.localizedDescription } }
    }
}

/// Review request: the conversation's pending requests one at a time, oldest first. Answering
/// one shows the next; the modal closes when none are left. Nothing is approved by opening it.
struct RequestReviewModal: View {
    let agent: SpatialAgent
    let session: Session
    @Bindable var library: LibraryModel
    let openConversation: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// The chat question shown, held so it stays while the reply is sent.
    @State private var chat: (question: String, context: String)?
    /// One question with options and a plain answer: laid out side by side, 720 pt wide.
    static func sideBySide(_ request: ExecutionRequest) -> Bool {
        let list = request.params["questions"].array
        return RequestKind(request) == .question && list.count == 1 && !list[0]["options"].array.isEmpty && !list[0]["isSecret"].bool
    }
    static func pending(_ controller: ExecutionController, thread: String) -> [ExecutionRequest] {
        controller.requests.values.filter { $0.threadID == thread }.sorted { $0.receivedAt < $1.receivedAt }
    }
    /// A question the agent asked in its last message (not through a request), still unanswered.
    static func chatQuestion(_ controller: ExecutionController, thread: String) -> (question: String, context: String)? {
        guard let entries = controller.tasks[thread]?.transcript.entries else { return nil }
        let start = entries.lastIndex { $0.kind == "You" }.map { $0 + 1 } ?? 0
        guard let last = entries[start...].last(where: { $0.kind == "Assistant" }), case let .question(question)? = TurnQuestion.asking(last.text) else { return nil }
        // What led up to it: the rest of the message, without the question itself.
        let context = last.text.replacingOccurrences(of: question, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (question, context)
    }
    var body: some View {
        let execution = library.execution
        let pending = Self.pending(execution, thread: session.sessionID)
        VStack(spacing: 0) {
            if let request = pending.first {
                let kind = RequestKind(request)
                ModalHeader(group: .needsYou, title: TaskTitle.full(session.displayTitle), status: kind.status,
                            model: AgentSidebar.modelName(execution.tasks[session.sessionID].flatMap { $0.model.isEmpty ? nil : $0.model } ?? agent.value.reportedModel,
                                                          provider: agent.value.provider, catalog: execution.models),
                            question: kind == .question) { dismiss() }
                RequestReviewContent(request: request, controller: execution, position: pending.count > 1 ? "1 of \(pending.count)" : nil, wide: true) {
                    Button("Open conversation") { openConversation(); dismiss() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SidebarStyle.accent).pointingHand()
                } skip: { dismiss() }
                .id(request.id)
            } else if let asked = chat ?? Self.chatQuestion(execution, thread: session.sessionID) {
                // Asked in the chat rather than through a request: answer it here as a reply.
                ModalHeader(group: .needsYou, title: TaskTitle.full(session.displayTitle), status: "Needs an answer",
                            model: AgentSidebar.modelName(execution.tasks[session.sessionID].flatMap { $0.model.isEmpty ? nil : $0.model } ?? agent.value.reportedModel,
                                                          provider: agent.value.provider, catalog: execution.models),
                            question: true) { dismiss() }
                ChatQuestionContent(question: asked.question, context: asked.context, session: session, library: library) {
                    Button("Open conversation") { openConversation(); dismiss() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SidebarStyle.accent).pointingHand()
                } done: { dismiss() }
                .onAppear { if chat == nil { chat = asked } }
            }
        }
        .reviewModalSurface(width: pending.first.map(Self.sideBySide) == true ? 720 : ModalStyle.width)
        .onChange(of: pending.isEmpty, initial: true) { _, empty in
            if empty, chat == nil, Self.chatQuestion(execution, thread: session.sessionID) == nil { dismiss() }
        }
    }
}

/// A question the agent asked in its message: what led to it, the question, and an answer that
/// is sent to the conversation as your reply.
struct ChatQuestionContent<Leading: View>: View {
    let question: String
    let context: String
    let session: Session
    @Bindable var library: LibraryModel
    @ViewBuilder var leading: Leading
    let done: () -> Void
    @State private var answer = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ModalBand(group: .needsYou, title: "Question", detail: "work paused until you answer")
            VStack(alignment: .leading, spacing: 12) {
                if !context.isEmpty {
                    Text(context).font(.system(size: 12.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Text(question).font(.system(size: 14, weight: .semibold)).foregroundStyle(SidebarStyle.title)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your answer").font(.system(size: 12, weight: .semibold)).foregroundStyle(SidebarStyle.secondary)
                    TextEditor(text: $answer).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .focused($focused)
                        .padding(6).frame(minHeight: 70, maxHeight: 140)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? SidebarStyle.accent.opacity(0.7) : Color.black.opacity(0.12), lineWidth: focused ? 2 : 1))
                        .accessibilityLabel("Your answer")
                }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(16)
            ModalFooter {
                leading
            } actions: {
                Button("Skip", action: done).buttonStyle(ModalSecondaryButtonStyle())
                Button(sending ? "Sending…" : "Send answer") { send() }
                    .buttonStyle(ModalPrimaryButtonStyle())
                    .disabled(sending || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear { focused = true }
    }
    private func send() {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true; error = nil
        Task {
            do { try await library.execution.send(in: session, prompt: text); done() }
            catch { self.error = error.localizedDescription; sending = false }
        }
    }
}

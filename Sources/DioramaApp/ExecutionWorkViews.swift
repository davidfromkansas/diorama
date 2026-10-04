import SwiftUI
import DioramaCore

struct ExecutionPlanView: View {
    let work: ExecutionWork
    @State private var expanded = true
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let explanation = work.explanation { Text(explanation).foregroundStyle(.secondary) }
                ForEach(work.plan) { step in
                    Label {
                        Text(step.text) + Text(" · " + step.label).foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: step.status == "completed" ? "checkmark.circle.fill" : step.status == "inProgress" ? "circle.lefthalf.filled" : "circle")
                    }
                }
                Text("Reported by Codex. Finishing a turn does not complete the plan.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).textSelection(.enabled)
        } label: { Text("Plan · \(work.plan.filter { $0.status == "completed" }.count) of \(work.plan.count) steps done").disclosurePointingHand() }.font(.callout).padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ExecutionChangesView: View {
    let work: ExecutionWork
    @State private var selectedPath: String?
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes · Last turn").font(.headline)
            Text("Reported changes for this turn, not all working-tree changes.").font(.caption).foregroundStyle(.secondary)
            if work.files.isEmpty {
                ContentUnavailableView("No reported changes", systemImage: "doc.text.magnifyingglass")
            } else {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(work.files) { file in
                                Button { selectedPath = file.path } label: {
                                    VStack(alignment: .leading) {
                                        Text(file.path).lineLimit(3)
                                        Text("+\(file.additions) −\(file.deletions)").font(.caption.monospaced())
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                        .background(selectedFile?.id == file.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }.pointingHand().buttonStyle(.plain).accessibilityLabel("Show diff for " + file.path)
                            }
                        }
                    }.frame(minWidth: 110, idealWidth: 150, maxWidth: 220)
                    ScrollView([.horizontal, .vertical]) {
                        if let file = selectedFile {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(file.diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                                    Text(line.isEmpty ? " " : line).font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(line.hasPrefix("+") ? additionColor : line.hasPrefix("-") ? deletionColor : Color.primary)
                                }
                            }.textSelection(.enabled).padding(8)
                        }
                    }.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var additionColor: Color { colorScheme == .dark ? Color(red: 0.5, green: 0.85, blue: 0.6) : Color(red: 0.08, green: 0.42, blue: 0.2) }
    private var deletionColor: Color { colorScheme == .dark ? Color(red: 1, green: 0.58, blue: 0.58) : Color(red: 0.7, green: 0.12, blue: 0.15) }
    private var selectedFile: ExecutionDiffFile? { work.files.first { $0.path == selectedPath } ?? work.files.first }
}

struct ElicitationFormView: View {
    let request: ExecutionRequest
    let respond: (WireValue) -> Void
    @State private var values: [String: WireValue] = [:]
    @State private var numberText: [String: String] = [:]
    @State private var error: String?
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.params["serverName"].string ?? "Connector").font(.subheadline.bold())
            Text(request.params["message"].string ?? "Information requested")
            if request.params["mode"].string == "url" {
                Text(request.params["url"].string ?? "URL unavailable").font(.caption).textSelection(.enabled)
                if let url = safeURL {
                    Button("Open connector page in browser") { openURL(url) }.pointingHand()
                    Text("Opening the page does not submit a response. Complete the browser flow, then acknowledge here.").font(.caption).foregroundStyle(.secondary)
                    Button("I completed the browser step") { respond(.object(["action": .string("accept"), "content": .null])) }.pointingHand()
                } else { Text("This connector URL cannot be opened safely. You can decline or cancel.").foregroundStyle(.orange) }
            } else if request.supportsElicitationForm {
                ForEach(request.elicitationFields) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(field.title + (field.required ? " · Required" : " · Optional"))
                        if let description = field.schema["description"].string { Text(description).font(.caption).foregroundStyle(.secondary) }
                        fieldControl(field)
                        if !field.required, values[field.id] != nil { Button("Omit this field") { values[field.id] = nil; numberText[field.id] = nil }.pointingHand().font(.caption) }
                    }
                }
                Button("Submit to connector") { submit() }.pointingHand()
            } else {
                Text("This connector requests a form shape Diorama cannot render. Review the details, then decline or cancel.").foregroundStyle(.orange)
            }
            HStack {
                Button("Decline") { respond(.object(["action": .string("decline"), "content": .null])) }.pointingHand()
                Button("Cancel request") { respond(.object(["action": .string("cancel"), "content": .null])) }.pointingHand()
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.onAppear {
            for field in request.elicitationFields where values[field.id] == nil && field.schema["default"] != .null {
                values[field.id] = field.schema["default"]
                if case .number(let n) = values[field.id] { numberText[field.id] = String(n) }
            }
        }
    }
    private var safeURL: URL? {
        guard let s = request.params["url"].string, let url = URL(string: s), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    @ViewBuilder private func fieldControl(_ field: ElicitationField) -> some View {
        if field.type == "boolean" {
            Picker(field.title, selection: Binding(get: { values[field.id]?.pretty ?? "" }, set: { values[field.id] = $0.isEmpty ? nil : .bool($0 == "true") })) {
                Text("Choose…").tag(""); Text("Yes").tag("true"); Text("No").tag("false")
            }.pointingHand().labelsHidden()
        } else if field.type == "array" {
            ForEach(field.choices, id: \.value) { choice in
                Toggle(choice.title, isOn: Binding(get: { values[field.id]?.array.contains(.string(choice.value)) == true }, set: { enabled in
                    var selected = values[field.id]?.array ?? []
                    selected.removeAll { $0 == .string(choice.value) }
                    if enabled { selected.append(.string(choice.value)) }
                    values[field.id] = .array(selected)
                })).pointingHand()
            }
            if values[field.id] == nil { Button("Use an empty selection") { values[field.id] = .array([]) }.pointingHand().font(.caption) }
        } else if !field.choices.isEmpty {
            Picker(field.title, selection: Binding(get: { values[field.id]?.string }, set: { values[field.id] = $0.map(WireValue.string) })) {
                Text("Choose…").tag(String?.none)
                ForEach(field.choices, id: \.value) { choice in Text(choice.title).tag(Optional(choice.value)) }
            }.pointingHand().labelsHidden()
        } else if field.type == "number" || field.type == "integer" {
            TextField(field.title, text: Binding(get: { numberText[field.id] ?? "" }, set: { numberText[field.id] = $0; values[field.id] = Double($0).map(WireValue.number) ?? .string($0) }))
        } else {
            TextField(field.title, text: Binding(get: { values[field.id]?.string ?? "" }, set: { values[field.id] = .string($0) }))
        }
    }
    private func submit() {
        let result: WireValue = .object(["action": .string("accept"), "content": .object(values)])
        do { try request.validateElicitation(result); error = nil; respond(result) } catch { self.error = error.localizedDescription }
    }
}

import SwiftUI
import PDFKit
import DioramaCore

struct ClaudeEntryView: View {
    let entry: Entry
    let presentation: ClaudePresentation
    @State private var inputExpanded = false
    @State private var outputExpanded = false
    @State private var selected: ClaudeOutput?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let name = presentation.toolName, name.hasPrefix("mcp__") { ConnectorMark(server: name.components(separatedBy: "__").dropFirst().first) }
                Label(presentation.title, systemImage: presentation.callID == nil ? "doc.richtext" : "terminal").fontWeight(.medium)
                Spacer()
                Text(presentation.status).font(.caption).foregroundStyle(presentation.status == "Failed" ? .orange : .secondary)
            }
            if presentation.category == "usage", let evidence = presentation.evidence { ClaudeUsageView(evidence: evidence) }
            if presentation.category == "sessionUsage", let evidence = presentation.evidence { ClaudeSessionUsageView(evidence: evidence) }
            if ["search", "fetch"].contains(presentation.category ?? ""), let evidence = presentation.evidence {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RECORDED CLAUDE " + (presentation.category == "fetch" ? "FETCH" : "SEARCH")).font(.caption2).foregroundStyle(.secondary)
                    if let query = evidence["query"].string ?? evidence["url"].string { Label(query, systemImage: "magnifyingglass").font(.callout).textSelection(.enabled) }
                    Text("The source result is preserved below.").font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            }
            if presentation.category == "delegation", let evidence = presentation.evidence {
                VStack(alignment: .leading, spacing: 8) {
                    Label(evidence["description"].string ?? "Delegated task", systemImage: "person.2").font(.headline)
                    if let role = evidence["subagent_type"].string { Text("Agent type · " + role).font(.caption).foregroundStyle(.secondary) }
                    if let result = presentation.resultEvidence, let agent = result["agentId"].string ?? result["agent_id"].string { Text("Reported agent · " + agent).font(.caption).textSelection(.enabled) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            if presentation.category == "task", let evidence = presentation.evidence {
                VStack(alignment: .leading, spacing: 8) {
                    if let description = evidence["description"].string { Text(description).font(.headline) }
                    if let summary = evidence["summary"].string { Text(summary).font(.callout).textSelection(.enabled) }
                    if let task = evidence["task_id"].string { Text("Task · " + task).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if presentation.category == "unknown" { Text("This Claude record has no specialized view yet. Inspect the available source details below.").font(.caption).foregroundStyle(.secondary) }
            if presentation.status == "Waiting for input" || presentation.status == "Awaiting approval" {
                Text("Respond in Claude").font(.callout.weight(.medium)).foregroundStyle(.orange)
            }
            if let checklist = presentation.checklist, !checklist.isEmpty {
                Text(presentation.status == "Completed" ? "Reported tasks" : "Requested task changes").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(checklist.enumerated()), id: \.offset) { _, item in
                    Label(item.title + " · " + item.status, systemImage: item.status == "completed" ? "checkmark.circle" : "circle")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let evidence = presentation.evidence, ["progress", "task", "event", "unknown"].contains(presentation.category ?? "") {
                DisclosureGroup("Reported Claude details") { Text(evidence.pretty).font(.caption.monospaced()).textSelection(.enabled) }
            }
            if !presentation.detail.isEmpty {
                DisclosureGroup(entry.kind == "Proposed plan" ? "View plan" : "Details") {
                    TranscriptContent(text: presentation.detail, literal: entry.kind != "Proposed plan")
                }
            }
            if !presentation.input.isEmpty {
                DisclosureGroup("Inputs", isExpanded: $inputExpanded) { TranscriptContent(text: presentation.input, literal: true) }
            }
            if !entry.text.isEmpty {
                DisclosureGroup(presentation.callID == nil ? "Details" : "View tool output", isExpanded: $outputExpanded) { TranscriptContent(text: entry.text).textSelection(.enabled) }
            }
            ForEach(presentation.outputs) { output in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(output.name, systemImage: output.kind == "image" ? "photo" : "doc")
                        Spacer()
                        if presentation.status == "Running" { Text("Pending").font(.caption) }
                        else if output.kind != "unsupported" {
                            Button("Preview") { selected = output }.disabled(output.location == nil && output.encoded == nil)
                            if let url = ClaudeOutputPreview.externalURL(output) {
                                Button("Open externally") { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                    if let note = output.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    if let location = output.location { Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled) }
                }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(12).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $selected) { ClaudeOutputPreviewView(output: $0) }
    }
}

struct ClaudeOutputPreviewView: View {
    let output: ClaudeOutput
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ClaudePreview?
    @State private var image: NSImage?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(output.name).font(.headline); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let error { ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text(error)) }
            else if let preview {
                if let notice = preview.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                switch preview.kind {
                case "html": CanvasWebView(html: String(decoding: preview.data, as: UTF8.self), statusLabel: "Artifact preview")
                case "image":
                    if let image { ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 900) } }
                    else { Text("Image could not be decoded.") }
                case "pdf": ClaudePDFPreview(data: preview.data)
                default: ScrollView { TranscriptContent(text: String(decoding: preview.data, as: UTF8.self), literal: preview.kind == "text").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else { ProgressView("Loading preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let url = ClaudeOutputPreview.externalURL(output) { Button("Open externally") { NSWorkspace.shared.open(url) } }
        }.padding(20).frame(minWidth: 480, idealWidth: 800, minHeight: 400, idealHeight: 650)
        .task(id: output.id) {
            do {
                let loaded = try await ClaudeOutputPreview.load(output)
                guard !Task.isCancelled else { return }
                preview = loaded
                if loaded.kind == "image" { image = NSImage(data: loaded.data) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct ClaudePDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view }
    func updateNSView(_ view: PDFView, context: Context) {}
}

/// Shared provider-neutral output controls; previews are explicit and reuse the isolated renderer.
struct ConversationOutputCards: View {
    let outputs: [ClaudeOutput]
    @State private var selected: ClaudeOutput?
    var body: some View {
        ForEach(outputs) { output in
            VStack(alignment: .leading, spacing: 5) {
                Label(output.name, systemImage: output.kind == "image" ? "photo" : "doc")
                HStack {
                    if output.kind != "unsupported" && (output.encoded != nil || ClaudeOutputPreview.externalURL(output)?.isFileURL == true) {
                        Button("Preview") { selected = output }.accessibilityLabel("Preview " + output.name)
                    }
                    if let url = ClaudeOutputPreview.externalURL(output) { Button("Open externally") { NSWorkspace.shared.open(url) }.accessibilityLabel("Open " + output.name + " externally") }
                }
                if let note = output.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                if output.location == nil && output.encoded == nil && output.note == nil { Text("No readable output location was provided.").font(.caption).foregroundStyle(.secondary) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .sheet(item: $selected) { ClaudeOutputPreviewView(output: $0) }
    }
}


/// Claude metrics retain their native cache/cost semantics; no Codex metric mapping.
struct ClaudeUsageView: View {
    let evidence: WireValue
    private var usage: WireValue { evidence["usage"] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(evidence["scope"].string == "message" ? "Message usage · do not add to turn totals" : "Reported turn usage").font(.caption).foregroundStyle(.secondary)
            if let input = usage["input_tokens"].number, let output = usage["output_tokens"].number, input >= 0, output >= 0 {
                UsageSegments(input: input, output: output)
            }
            if let read = usage["cache_read_input_tokens"].number { LabeledContent("Cache read", value: read.formatted()) }
            if let write = usage["cache_creation_input_tokens"].number { LabeledContent("Cache creation", value: write.formatted()) }
            if let cost = evidence["total_cost_usd"].number { LabeledContent("Reported cost", value: cost.formatted(.currency(code: "USD"))) }
            if let duration = evidence["duration_ms"].number { LabeledContent("Reported duration", value: (duration / 1000).formatted() + " s") }
            DisclosureGroup("Usage source fields") { Text(evidence.pretty).font(.caption.monospaced()).textSelection(.enabled) }
        }.font(.callout).padding(14).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Saved cost-state records are cumulative session snapshots, never turn deltas.
struct ClaudeSessionUsageView: View {
    let evidence: WireValue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative session snapshot · do not add to other usage records").font(.caption).foregroundStyle(.secondary)
            if let cost = evidence["totalCostUSD"].number { LabeledContent("Reported session cost", value: cost.formatted(.currency(code: "USD"))) }
            if evidence["hasUnknownModelCost"].bool == true { Text("The source reports unknown model costs; this total may be incomplete.").font(.caption).foregroundStyle(.orange) }
            if let duration = evidence["totalDuration"].number { LabeledContent("Reported total duration", value: (duration / 1000).formatted() + " s") }
            ForEach(evidence["modelUsage"].object.keys.sorted(), id: \.self) { model in
                let usage = evidence["modelUsage"][model]
                DisclosureGroup(model) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let input = usage["inputTokens"].number, let output = usage["outputTokens"].number, input >= 0, output >= 0 {
                            UsageSegments(input: input, output: output)
                        }
                        if let read = usage["cacheReadInputTokens"].number { LabeledContent("Cache read", value: read.formatted()) }
                        if let write = usage["cacheCreationInputTokens"].number { LabeledContent("Cache creation", value: write.formatted()) }
                    }
                }
            }
            DisclosureGroup("Session usage source fields") { Text(evidence.pretty).font(.caption.monospaced()).textSelection(.enabled) }
        }.font(.callout).padding(14).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

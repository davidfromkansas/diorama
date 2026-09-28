import SwiftUI
import DioramaCore

/// Codex dispatch deliberately owns its native item semantics.
struct CodexEntryView: View {
    let entry: Entry
    let presentation: CodexPresentation
    var selectWorker: ((String) -> Void)?
    var progress: String?
    var body: some View {
        if let tool = entry.tool {
            RichToolResultView(result: tool, selectWorker: selectWorker, progress: progress)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label(presentation.title, systemImage: presentation.category.hasPrefix("usage") ? "chart.bar.fill" : "info.circle").font(.headline); Spacer(); Text(presentation.status).font(.caption).foregroundStyle(.secondary) }
                if presentation.category.hasPrefix("usage") {
                    CodexUsageView(presentation: presentation)
                } else if presentation.category == "unknown" {
                    Text("This Codex event has no specialized view yet. Its available source details remain inspectable.").font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("Reported details") { TranscriptContent(text: presentation.evidence.pretty, literal: true).textSelection(.enabled) }
            }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct CodexUsageView: View {
    let presentation: CodexPresentation
    private var usage: WireValue { presentation.usage }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.category == "usageRecord" ? "Reported response usage" : "Last reported model usage").font(.caption).foregroundStyle(.secondary)
            if let input = usage["input_tokens"].number, let output = usage["output_tokens"].number, input >= 0, output >= 0 {
                Text((input + output).formatted()).font(.system(size: 32, weight: .semibold, design: .rounded)) + Text(" tokens").font(.caption)
                UsageSegments(input: input, output: output)
                if let cached = usage["cached_input_tokens"].number { Text("Cached input: \(cached.formatted()) · included in input").font(.caption).foregroundStyle(.secondary) }
            } else { Text("A compatible input/output breakdown was not supplied.").font(.caption) }
            if presentation.cumulativeUsage != .null {
                DisclosureGroup("Cumulative usage · not added to the figures above") { Text(presentation.cumulativeUsage.pretty).font(.caption.monospaced()).textSelection(.enabled) }
            }
        }
    }
}

/// Pure chart geometry only; each provider selects and labels its own metrics.
struct UsageSegments: View {
    let input: Double
    let output: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    Rectangle().fill(Color(red: 0.725, green: 0.608, blue: 0.91)).frame(width: max(0, geometry.size.width - 3) * (input / max(1, input + output)))
                    Rectangle().fill(Color(red: 0.608, green: 0.765, blue: 0.651))
                }.clipShape(RoundedRectangle(cornerRadius: 5))
            }.frame(height: 16).accessibilityHidden(true)
            HStack { Text("Input · \(input.formatted())"); Spacer(); Text("Output · \(output.formatted())") }.font(.caption)
        }.accessibilityElement(children: .combine)
    }
}

struct CodexSearchView: View {
    let item: WireValue
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECORDED SEARCH · NOT A LIVE PAGE").font(.caption2).foregroundStyle(.secondary)
            if let query = item["query"].string ?? item["action"]["query"].string {
                Label(query, systemImage: "magnifyingglass").font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(Array(item["results"].array.prefix(5).enumerated()), id: \.offset) { _, result in
                if let address = result["url"].string, let url = URL(string: address), ["https", "http"].contains(url.scheme) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(url.host ?? address).font(.caption).foregroundStyle(.secondary)
                        Button { NSWorkspace.shared.open(url) } label: { Text(result["title"].string ?? address).font(.callout.weight(.medium)).foregroundStyle(Color.accentColor).multilineTextAlignment(.leading) }.buttonStyle(.plain).accessibilityLabel("Open source: " + (result["title"].string ?? address))
                        if let snippet = result["snippet"].string ?? result["description"].string { Text(snippet).font(.callout).lineLimit(3) }
                    }
                }
            }
            if item["results"].array.isEmpty { Text("No result list was included in this record.").font(.caption).foregroundStyle(.secondary) }
            if item["results"].array.count > 5 { Text("Showing 5 results. All recorded results are in tool details.").font(.caption) }
        }.padding(16).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SourceRecordDetails: View {
    let records: [TranscriptSource]
    @State private var selected = 0
    @State private var text: String?
    @State private var error: String?
    @State private var limit = 64 * 1024
    @State private var expanded = false
    @State private var busy = false
    var body: some View {
        DisclosureGroup("Source input / output", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if records.count > 1 {
                    Picker("Record", selection: $selected) { ForEach(records.indices, id: \.self) { Text("Record \($0 + 1)").tag($0) } }
                }
                if busy { ProgressView("Reading source…") }
                if let error { Text(error).foregroundStyle(.orange) }
                if let text {
                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    HStack {
                        Button("Copy loaded source") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                        if text.hasSuffix("[More source content available]"), limit < 16 * 1024 * 1024 { Button("Load more of this record") { limit = min(limit * 2, 16 * 1024 * 1024) } }
                    }
                }
            }
        }.font(.caption)
        .task(id: "\(expanded)-\(selected)-\(limit)-\(records.count)") {
            guard expanded, records.indices.contains(selected) else { return }
            busy = true; error = nil; text = nil
            do {
                let loaded = try await records[selected].load(characterLimit: limit)
                guard !Task.isCancelled else { return }; text = loaded
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { busy = false }
        }
    }
}

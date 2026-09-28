import SwiftUI
import MarkdownUI

/// Shared by every transcript category. Raw records remain available alongside the preview.
struct MarkdownText: View {
    let text: String
    var literal = false

    var body: some View {
        Markdown {
            if literal {
                CodeBlock(content: text)
            } else {
                MarkdownContent(text)
            }
        }
            .markdownTheme(Self.transcriptTheme)
            .markdownImageProvider(TranscriptImageProvider())
            .markdownInlineImageProvider(TranscriptInlineImageProvider())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                // Imported text must not dispatch arbitrary application commands.
                guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
                return .systemAction
            })
    }

    private static var transcriptTheme: Theme {
        Theme.gitHub
            .text {
                FontSize(14)
                ForegroundColor(.primary)
                BackgroundColor(nil)
            }
            .link { ForegroundColor(.mint) }
            .codeBlock { configuration in
                VStack(alignment: .leading, spacing: 8) {
                    if let language = configuration.language, !language.isEmpty {
                        Text(language).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(verbatim: configuration.content)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 0, bottom: 16)
            }
    }
}

// Do not contact third-party image hosts just because a transcript was selected.
private struct TranscriptImageProvider: ImageProvider {
    nonisolated func makeImage(url: URL?) -> some View {
        Label("Image attachment · \(url?.lastPathComponent ?? "unavailable")", systemImage: "photo")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct TranscriptInlineImageProvider: InlineImageProvider {
    nonisolated func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "photo")
    }
}

struct TranscriptContent: View {
    let text: String
    var literal = false
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownText(text: text, literal: literal || isStructuredRecord(text))
        }
        .contextMenu {
            Button("Copy message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
            Button("Show raw text") { showSource = true }
        }
        .sheet(isPresented: $showSource) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Raw message").font(.headline); Spacer(); Button("Done") { showSource = false }.keyboardShortcut(.cancelAction) }
                ScrollView { Text(verbatim: text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(minWidth: 520, idealWidth: 640, minHeight: 360)

        }
    }
}

/// JSON payloads are data, even when their string values contain Markdown characters.
func isStructuredRecord(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
}

/// Compact titles use the readable text, without block layout or active links in list rows.
private let sidebarTitleCache: NSCache<NSString, NSString> = {
    let cache = NSCache<NSString, NSString>()
    cache.countLimit = 1024; cache.totalCostLimit = 2 * 1024 * 1024
    return cache
}()
func markdownTitle(_ source: String) -> String {
    // App Server can derive a title from all text inputs, including canvas context.
    let visible = source.components(separatedBy: "<diorama_").first ?? source
    if let cached = sidebarTitleCache.object(forKey: visible as NSString) { return cached as String }
    let title = MarkdownContent(visible).renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
    sidebarTitleCache.setObject(title as NSString, forKey: visible as NSString, cost: visible.utf8.count + title.utf8.count)
    return title
}

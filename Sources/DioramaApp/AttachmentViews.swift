import SwiftUI
import DioramaCore

@MainActor
private func addAttachments(_ urls: [URL], to attachments: inout [ConversationAttachment]) throws {
    var result = attachments
    for url in urls {
        let attachment = try ConversationAttachment(url: url)
        if !result.contains(where: { $0.id == attachment.id }) { result.append(attachment) }
    }
    guard result.count <= 20 else { throw AppServerFailure("Attach up to 20 files per message.") }
    attachments = result
}

struct AttachmentPicker: View {
    @Binding var attachments: [ConversationAttachment]
    let disabled: Bool
    var showsButton = true
    var showsAttachments = true
    var iconOnly = false
    var menuRow = false
    var showIntegrations: (() -> Void)? = nil
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsButton { HStack {
                if menuRow {
                    Button(action: chooseFiles) { ComposerOptionLabel(title: "Add attachment", icon: "paperclip") }.pointingHand()
                        .buttonStyle(HoverButtonStyle(inset: 0)).disabled(disabled)
                } else if let showIntegrations {
                    Menu {
                        Button("Files…", systemImage: "paperclip", action: chooseFiles).pointingHand()
                        Divider()
                        Button("Skills & connectors…", systemImage: "square.stack.3d.up", action: showIntegrations).pointingHand()
                    } label: {
                        Image(systemName: "plus").font(.system(size: 20)).frame(width: 30, height: 30)
                    }.pointingHand()
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Add attachments, skills, or connectors")
                    .help("Add files, skills, or connectors").disabled(disabled)
                } else {
                    Button(action: chooseFiles) {
                        if iconOnly { Image(systemName: "plus").font(.system(size: 20)).frame(width: 30, height: 30) }
                        else { Label("Attach files", systemImage: "paperclip") }
                    }.pointingHand()
                    .accessibilityLabel("Attach files")
                    .buttonStyle(.borderless).disabled(disabled)
                    .help("Attach images or local file references. You can also drop files into the message box.")
                }
                if !iconOnly && !attachments.isEmpty { Text("\(attachments.count)/20").foregroundStyle(.secondary) }
            }.font(.caption) }
            if showsAttachments && !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 8) {
                                Image(systemName: attachment.kind == .image ? "photo" : "doc")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.name).lineLimit(1)
                                    Text(attachment.kind == .image ? "Image" : "Local file reference").font(.caption2).foregroundStyle(.secondary)
                                }
                                Button { attachments.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill") }.pointingHand()
                                    .buttonStyle(.plain).disabled(disabled).accessibilityLabel("Remove \(attachment.name)")
                            }.font(.caption).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).help(attachment.url.path)
                        }
                    }
                }
                .frame(height: 54)
                if attachments.contains(where: { $0.kind == .file }) {
                    Text("Files are shared by path. The agent reads them using its existing tools and permissions.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.prompt = "Attach"
        let parent = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        panel.begin { response in
            defer { parent?.makeKeyAndOrderFront(nil) }
            guard response == .OK else { return }
            do { try addAttachments(panel.urls, to: &attachments); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }

}

struct AttachmentDropTarget: ViewModifier {
    @Binding var attachments: [ConversationAttachment]
    let disabled: Bool
    @State private var targeted = false
    @State private var error: String?
    func body(content: Content) -> some View {
        content
            .overlay { if targeted && !disabled { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6])).allowsHitTesting(false) } }
            .dropDestination(for: URL.self) { urls, _ in
                guard !disabled, !urls.isEmpty else { return false }
                do { try addAttachments(urls, to: &attachments); return true }
                catch { self.error = error.localizedDescription; return false }
            } isTargeted: { targeted = $0 }
            .alert("Couldn’t attach files", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }.pointingHand()
            } message: { Text(error ?? "") }
    }
}

/// Shared add menu for existing conversations and the new-task sheet.
struct ComposerAddMenu: View {
    let controller: ExecutionController
    let folder: String
    let threadID: String?
    @Binding var attachments: [ConversationAttachment]
    @Binding var capabilities: [CapabilityInput]
    let disabled: Bool
    var showsAttachments = false
    var claude = false
    @State private var showingIntegrations = false

    var body: some View {
        AttachmentPicker(attachments: $attachments, disabled: disabled,
                         showsAttachments: showsAttachments, iconOnly: true,
                         showIntegrations: claude ? nil : { showingIntegrations = true })
            .sheet(isPresented: $showingIntegrations) {
                IntegrationPicker(controller: controller, folder: folder,
                                  threadID: threadID, selection: $capabilities)
            }
    }
}

import SwiftUI
import AppKit
import ImageIO
import DioramaCore

/// Owns a copy of clipboard images so later clipboard changes cannot invalidate a draft.
enum ClipboardImageStore {
    static func attachment(from pasteboard: NSPasteboard, directory: URL? = nil) throws -> ConversationAttachment? {
        // Finder copies expose both a file URL and an icon; never mistake the icon for the file.
        if pasteboard.types?.contains(.fileURL) == true { return nil }
        guard let type = pasteboard.availableType(from: [.png, .tiff]) else { return nil }
        guard let data = pasteboard.data(forType: type), data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 40_000_000,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]), png.count <= 20 * 1024 * 1024 else {
            throw AppServerFailure("Couldn’t paste this image. Use an image under 20 MiB and 40 megapixels.")
        }
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/Pasted Images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("Pasted image \(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        do { return try ConversationAttachment(url: url) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}

final class ComposerNSTextView: NSTextView {
    static func focusVisible() {
        func editor(in view: NSView) -> ComposerNSTextView? {
            guard !view.isHiddenOrHasHiddenAncestor else { return nil }
            if let editor = view as? ComposerNSTextView { return editor }
            for child in view.subviews { if let match = editor(in: child) { return match } }
            return nil
        }
        if let window = NSApp.keyWindow, let content = window.contentView, let text = editor(in: content) { window.makeFirstResponder(text) }
    }

    var clipboard: () -> NSPasteboard = { .general }
    var pasteImage: (NSPasteboard) -> Bool = { _ in false }
    var sendMessage: (() -> Void)?
    var hasSendableContent: () -> Bool = { false }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)),
           clipboard().availableType(from: [.fileURL, .png, .tiff]) != nil { return isEditable }
        return super.validateUserInterfaceItem(item)
    }
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if !pasteImage(clipboard()) { super.paste(sender) }
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if [36, 76].contains(event.keyCode), isEditable, !hasMarkedText(),
           modifiers.isEmpty || modifiers == .command,
           hasSendableContent(), let sendMessage {
            sendMessage(); return
        }
        super.keyDown(with: event)
    }
}

struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var attachments: [ConversationAttachment]
    @Binding var error: String?
    let disabled: Bool
    var measuredHeight: Binding<CGFloat>? = nil
    var send: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = ComposerNSTextView(frame: .zero)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.drawsBackground = false; editor.font = .systemFont(ofSize: 16); editor.textColor = .labelColor
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.setAccessibilityLabel("Message")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        configure(editor, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerNSTextView else { return }
        configure(editor, context: context)
        if let measuredHeight {
            DispatchQueue.main.async { [weak editor] in
                guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
                layout.ensureLayout(for: container)
                let height = min(128, max(28, ceil(layout.usedRect(for: container).height + 8)))
                if measuredHeight.wrappedValue != height { measuredHeight.wrappedValue = height }
            }
        }
    }
    private func configure(_ editor: ComposerNSTextView, context: Context) {
        if editor.string != text { editor.string = text }
        editor.isEditable = !disabled
        editor.pasteImage = { [weak coordinator = context.coordinator] pasteboard in coordinator?.pasteImage(pasteboard) ?? false }
        editor.sendMessage = send
        editor.hasSendableContent = { [weak editor] in
            !(editor?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !attachments.isEmpty
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        init(_ parent: ComposerTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
        func pasteImage(_ pasteboard: NSPasteboard) -> Bool {
            guard !parent.disabled else { return true }
            if pasteboard.types?.contains(.fileURL) == true {
                let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                guard !urls.isEmpty else { return false }
                do { try addAttachments(urls, to: &parent.attachments); parent.error = nil }
                catch { parent.error = error.localizedDescription }
                return true
            }
            guard pasteboard.availableType(from: [.png, .tiff]) != nil else { return false }
            do {
                guard parent.attachments.count < 20 else { throw AppServerFailure("Attach up to 20 files per message.") }
                if let attachment = try ClipboardImageStore.attachment(from: pasteboard) { parent.attachments.append(attachment) }
                parent.error = nil
            } catch { parent.error = error.localizedDescription }
            return true
        }
    }
}

import AppKit
import DioramaCore
import SwiftUI

/// Colours for reading a diff: soft rows, stronger marks on the changed words.
enum DiffPalette {
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let secondary = Color(red: 0.42, green: 0.42, blue: 0.44)
    static let line = Color.black.opacity(0.08)
    static let background = Color(red: 0.988, green: 0.982, blue: 0.970)
    static let panel = Color(red: 0.969, green: 0.957, blue: 0.937)
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.93)
    static let selected = Color(red: 0.90, green: 0.94, blue: 1.0)
    static let green = Color(red: 0.12, green: 0.48, blue: 0.23)
    static let red = Color(red: 0.70, green: 0.15, blue: 0.12)
    static let addedRow = Color(red: 0.918, green: 0.969, blue: 0.933)
    static let removedRow = Color(red: 0.992, green: 0.925, blue: 0.922)
    static let addedGutter = Color(red: 0.847, green: 0.941, blue: 0.878)
    static let removedGutter = Color(red: 0.980, green: 0.863, blue: 0.851)
    static let addedMark = Color(red: 0.725, green: 0.898, blue: 0.776)
    static let removedMark = Color(red: 0.965, green: 0.741, blue: 0.718)
    static let gutter = Color(red: 0.984, green: 0.980, blue: 0.973)
    static let number = Color(red: 0.65, green: 0.64, blue: 0.61)
    static let hunk = Color(red: 0.949, green: 0.961, blue: 0.984)
    static let hunkInk = Color(red: 0.29, green: 0.35, blue: 0.47)
    static let mono = Font.system(size: 12.5, design: .monospaced)

    /// The M / A / D badge for a file's status: letter, ink and fill.
    static func badge(_ file: ChangedFile) -> (letter: String, ink: Color, fill: Color) {
        switch file.untracked ? "Added" : file.status {
        case "Added", "Copied": ("A", green, Color(red: 0.89, green: 0.957, blue: 0.91))
        case "Deleted": ("D", red, Color(red: 0.984, green: 0.894, blue: 0.886))
        case "Renamed": ("R", accent, selected)
        default: ("M", Color(red: 0.54, green: 0.35, blue: 0), Color(red: 0.992, green: 0.945, blue: 0.847))
        }
    }
}

/// Every file a task changed, one at a time: the files grouped by folder on the left, the open
/// file's diff on the right (unified or side by side), stepping through them with ↑ ↓ or ⌘[ ⌘].
struct ChangesBrowser: View {
    let browsing: ChangesBrowsing
    @Environment(\.dismiss) private var dismiss
    @AppStorage("changesBrowser.split") private var split = false
    @State private var snapshot: ChangesSnapshot?
    @State private var selected: String?
    @State private var filter = ""
    @State private var document = DiffDocument()
    @State private var loadingDiff = false
    @State private var error: String?
    /// The open file's current text, for showing unchanged lines between hunks.
    @State private var lines: [String]?
    /// Gaps opened (by the index of the hunk after them; the end gap is `Int.max`).
    @State private var expanded: Set<Int> = []
    @State private var sizes: (old: Int?, new: Int?) = (nil, nil)
    @FocusState private var listFocused: Bool

    private var files: [ChangedFile] {
        let all = snapshot?.files ?? []
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }
    private var file: ChangedFile? { snapshot?.files.first { $0.path == selected } }
    private var index: Int? { files.firstIndex { $0.path == selected } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DiffPalette.line)
            if let error {
                ContentUnavailableView("Changes unavailable", systemImage: "folder.badge.questionmark", description: Text(error)).frame(maxHeight: .infinity)
            } else if snapshot == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot?.files.isEmpty == true {
                ContentUnavailableView("No changes", systemImage: "checkmark", description: Text("This task hasn't changed any files.")).frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 320)
                    Divider().overlay(DiffPalette.line)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(DiffPalette.background)
        .environment(\.colorScheme, .light)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 600, idealHeight: 780)
        .task { await load() }
        .task(id: selected) { await loadFile() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Changes").font(.system(size: 17, weight: .semibold))
                    if let snapshot {
                        Text("\(snapshot.files.count) file\(snapshot.files.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(DiffPalette.secondary)
                        Text("+\(snapshot.added)").font(.system(size: 13, design: .monospaced)).foregroundStyle(DiffPalette.green)
                        Text("−\(snapshot.removed)").font(.system(size: 13, design: .monospaced)).foregroundStyle(DiffPalette.red)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                    Text(snapshot?.branch ?? browsing.workspace.branch).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Text("· since the task began, committed or not")
                }
                .font(.system(size: 12)).foregroundStyle(DiffPalette.secondary)
            }
            .foregroundStyle(DiffPalette.ink)
            Spacer(minLength: 12)
            Picker("Diff layout", selection: $split) {
                Text("Unified").tag(false)
                Text("Split").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150).pointingHand()
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 30).background(RoundedRectangle(cornerRadius: 8).fill(DiffPalette.accent))
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).pointingHand()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: File list

    private struct Group: Identifiable { var id: String { folder }; let folder: String; let files: [ChangedFile] }
    private var groups: [Group] {
        var order: [String] = [], members: [String: [ChangedFile]] = [:]
        for file in files {
            let folder = (file.path as NSString).deletingLastPathComponent
            if members[folder] == nil { order.append(folder) }
            members[folder, default: []].append(file)
        }
        return order.map { Group(folder: $0, files: members[$0] ?? []) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(DiffPalette.secondary)
                TextField("Filter files", text: $filter).textFieldStyle(.plain).font(.system(size: 12.5))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1)))
            .padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(groups) { group in
                            Text(group.folder.isEmpty ? "Project root" : group.folder)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(DiffPalette.secondary)
                                .lineLimit(1).truncationMode(.head).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
                            ForEach(group.files) { file in
                                FileListRow(file: file, selected: file.path == selected).id(file.path)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = file.path; listFocused = true }
                                    .pointingHand()
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 12)
                }
                .onChange(of: selected) { _, path in
                    guard let path else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(path, anchor: nil) }
                }
            }
            .focusable().focused($listFocused).focusEffectDisabled()
            .onKeyPress(.upArrow) { step(-1); return .handled }
            .onKeyPress(.downArrow) { step(1); return .handled }
            Divider().overlay(DiffPalette.line)
            Text("↑ ↓ files · ⌘[ ⌘] previous / next · Esc closes")
                .font(.system(size: 11)).foregroundStyle(DiffPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(DiffPalette.panel)
    }

    // MARK: Diff

    private var detail: some View {
        VStack(spacing: 0) {
            if let file { fileBar(file) }
            Divider().overlay(DiffPalette.line)
            if let file {
                if document.binary || (lines == nil && !loadingDiff && document.hunks.isEmpty && document.message == nil && file.added + file.removed == 0) {
                    BinaryFileCard(file: file, folder: browsing.workspace.folder, sizes: sizes)
                } else if let message = document.message {
                    ContentUnavailableView("No line diff", systemImage: "doc.text.magnifyingglass", description: Text(message)).frame(maxHeight: .infinity)
                } else if loadingDiff && document.hunks.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if document.hunks.isEmpty {
                    ContentUnavailableView("No line changes", systemImage: "equal", description: Text("Only the file's mode or name changed.")).frame(maxHeight: .infinity)
                } else {
                    DiffBody(document: document, lines: lines, expanded: $expanded, split: split)
                }
            } else {
                ContentUnavailableView("No file selected", systemImage: "doc").frame(maxHeight: .infinity)
            }
        }
        .background(Color.white)
    }

    private func fileBar(_ file: ChangedFile) -> some View {
        let badge = DiffPalette.badge(file)
        let folder = (file.path as NSString).deletingLastPathComponent
        let url = URL(fileURLWithPath: browsing.workspace.folder).appendingPathComponent(file.path)
        return HStack(spacing: 10) {
            Text(file.untracked ? "Added" : file.status).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(badge.ink).padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(badge.fill))
            (Text(folder.isEmpty ? "" : folder + "/").foregroundColor(DiffPalette.secondary)
             + Text((file.path as NSString).lastPathComponent).fontWeight(.semibold).foregroundColor(DiffPalette.ink))
                .font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.head)
                .help(file.oldPath.map { "Renamed from \($0)" } ?? file.path)
            if !document.binary {
                (Text("+\(file.added)").foregroundColor(DiffPalette.green) + Text(" ") + Text("−\(file.removed)").foregroundColor(DiffPalette.red))
                    .font(.system(size: 12, design: .monospaced))
            }
            Spacer(minLength: 8)
            if let index { Text("\(index + 1) of \(files.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(DiffPalette.secondary) }
            Button { step(-1) } label: { Image(systemName: "chevron.up").frame(width: 14) }
                .keyboardShortcut("[", modifiers: .command).disabled((index ?? 0) == 0).help("Previous file (⌘[)").pointingHand()
            Button { step(1) } label: { Image(systemName: "chevron.down").frame(width: 14) }
                .keyboardShortcut("]", modifiers: .command).disabled((index ?? files.count) >= files.count - 1).help("Next file (⌘])").pointingHand()
            Button("Open in Editor") { NSWorkspace.shared.open(url) }
                .disabled(!FileManager.default.fileExists(atPath: url.path)).pointingHand()
        }
        .controlSize(.regular)
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    // MARK: Loading

    private func step(_ by: Int) {
        guard !files.isEmpty else { return }
        let next = max(0, min(files.count - 1, (index ?? -by) + by))
        selected = files[next].path
    }
    private func load() async {
        if let given = browsing.snapshot { snapshot = given; pickStart() }
        do {
            let fresh = try await SessionChanges.snapshot(browsing.workspace, scope: .session)
            snapshot = fresh; error = nil
            SessionChangeCounts.shared.record(browsing.workspace, fresh)
        } catch { if snapshot == nil { self.error = error.localizedDescription } }
        pickStart()
        listFocused = true
    }
    private func pickStart() {
        guard selected == nil || !(snapshot?.files.contains { $0.path == selected } ?? false) else { return }
        selected = snapshot?.files.first { $0.path == browsing.start }?.path ?? snapshot?.files.first?.path
    }
    private func loadFile() async {
        expanded = []; lines = nil; sizes = (nil, nil)
        guard let file else { document = DiffDocument(); return }
        loadingDiff = true; defer { loadingDiff = false }
        let patch: String
        do { patch = try await SessionChanges.diff(file, workspace: browsing.workspace, scope: .session) }
        catch { if selected == file.path { document = DiffDocument(message: error.localizedDescription) }; return }
        guard selected == file.path else { return }
        var parsed = DiffDocument.parse(patch)
        if patch.hasPrefix("Binary file") { parsed.binary = true; parsed.message = nil }
        document = parsed
        if parsed.binary || (parsed.hunks.isEmpty && file.added + file.removed == 0) {
            sizes = await SessionChanges.sizes(file, workspace: browsing.workspace, scope: .session)
        } else if file.status != "Deleted" {
            // The current text, for unchanged lines around the hunks (small text files only).
            let url = URL(fileURLWithPath: browsing.workspace.folder).appendingPathComponent(file.path)
            if let data = try? Data(contentsOf: url), data.count <= 1_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8) {
                var all = text.components(separatedBy: "\n")
                if text.hasSuffix("\n") { all.removeLast() }
                if selected == file.path { lines = all }
            }
        }
    }
}


/// One file in the list: status badge, name, counts and a five-block bar of how much changed.
private struct FileListRow: View {
    let file: ChangedFile
    let selected: Bool
    var body: some View {
        let badge = DiffPalette.badge(file)
        HStack(spacing: 8) {
            Text(badge.letter).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(badge.ink)
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(badge.fill))
            Text((file.path as NSString).lastPathComponent)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium, design: .monospaced)).foregroundStyle(DiffPalette.ink)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(file.added + file.removed == 0 ? "" : "+\(file.added) −\(file.removed)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(DiffPalette.secondary).lineLimit(1).fixedSize()
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { block in
                    RoundedRectangle(cornerRadius: 1.5).fill(color(block)).frame(width: 6, height: 6)
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? DiffPalette.selected : .clear))
        .overlay(alignment: .leading) { if selected { Rectangle().fill(DiffPalette.accent).frame(width: 2).padding(.vertical, 5) } }
        .help(file.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.status) \(file.path), \(file.added) added, \(file.removed) removed")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func color(_ block: Int) -> Color {
        let total = file.added + file.removed
        guard total > 0 else { return Color(red: 0.85, green: 0.84, blue: 0.82) }
        let greens = Int((5 * Double(file.added) / Double(total)).rounded())
        let reds = min(5 - greens, Int((5 * Double(file.removed) / Double(total)).rounded()))
        return block < greens ? DiffPalette.green : block < greens + reds ? DiffPalette.red : Color(red: 0.89, green: 0.875, blue: 0.85)
    }
}

/// The open file's hunks, with the unchanged stretches between them folded until you open them.
private struct DiffBody: View {
    let document: DiffDocument
    let lines: [String]?
    @Binding var expanded: Set<Int>
    let split: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView(split ? [.vertical] : [.vertical, .horizontal]) {
                // One lazy item per hunk (with the fold before it): its rows lay out together.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            gap(document.gap(before: hunk.id), key: hunk.id, shift: hunk.id == 0 ? 0 : document.hunks[hunk.id - 1].shiftAfter)
                            HunkHeader(hunk: hunk, context: enclosing(hunk))
                            if split {
                                ForEach(DiffDocument.split(hunk)) { row in SplitDiffRow(row: row) }
                            } else {
                                ForEach(hunk.lines) { line in UnifiedDiffRow(line: line) }
                            }
                        }
                    }
                    if let lines, let last = document.hunks.last {
                        VStack(alignment: .leading, spacing: 0) { gap(document.gapAfterLast(lineCount: lines.count), key: .max, shift: last.shiftAfter) }
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                .font(DiffPalette.mono)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }

    /// The declaration a hunk sits in, read from the file (nearest line above it that starts a
    /// function, type or block); git's own guess when the file isn't at hand.
    private func enclosing(_ hunk: DiffDocument.Hunk) -> String {
        guard let lines, hunk.newStart > 1 else { return hunk.context }
        let firstChanged = hunk.lines.first { $0.kind != .context }?.new ?? hunk.newStart
        // From the line above the first change: an added declaration isn't what the hunk sits in.
        for number in stride(from: min(firstChanged - 1, lines.count), through: 1, by: -1) {
            let line = lines[number - 1]
            if line.range(of: #"^\s*(@\w+\s+)*((public|private|internal|fileprivate|open|static|final|override|async|export|default|abstract|mutating|nonisolated)\s+)*(func|class|struct|enum|extension|protocol|actor|init|function|def|interface|impl|fn|type|const \w+ = \(|describe\(|it\(|test\()"#, options: .regularExpression) != nil {
                let text = line.trimmingCharacters(in: .whitespaces)
                return text.count > 90 ? String(text.prefix(89)) + "…" : text
            }
        }
        return hunk.context
    }

    /// Unchanged lines (new-side numbers): a fold you can open, when the file's text is at hand.
    @ViewBuilder private func gap(_ range: ClosedRange<Int>?, key: Int, shift: Int) -> some View {
        if let range, let lines, range.upperBound <= lines.count {
            if expanded.contains(key) {
                ForEach(Array(range), id: \.self) { number in
                    let line = DiffDocument.Line(id: -number, kind: .context, old: number + shift, new: number, text: lines[number - 1])
                    if split { SplitDiffRow(row: .init(id: -number, left: line, right: line)) } else { UnifiedDiffRow(line: line) }
                }
            } else {
                Button { expanded.insert(key) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.and.down").font(.system(size: 10, weight: .semibold))
                        Text("Show \(range.count) unchanged line\(range.count == 1 ? "" : "s")").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(DiffPalette.accent).padding(.leading, 100).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .background(DiffPalette.gutter).contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointingHand()
            }
        }
    }
}

private struct HunkHeader: View {
    let hunk: DiffDocument.Hunk
    let context: String
    var body: some View {
        HStack(spacing: 10) {
            Text("Lines \(hunk.newStart)–\(hunk.newStart + max(0, hunk.newCount - 1))").font(.system(size: 11.5, design: .monospaced))
            if !context.isEmpty { Text(context).font(.system(size: 12, design: .monospaced)).foregroundStyle(DiffPalette.secondary).lineLimit(1) }
        }
        .foregroundStyle(DiffPalette.hunkInk)
        .padding(.leading, 100).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(DiffPalette.hunk)
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.89, green: 0.91, blue: 0.95)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.89, green: 0.91, blue: 0.95)).frame(height: 1) }
    }
}

/// A line's text with its changed span marked.
private func marked(_ line: DiffDocument.Line) -> AttributedString {
    var text = AttributedString(line.text.isEmpty ? " " : line.text)
    guard let range = line.changed, line.kind != .context else { return text }
    let characters = text.characters
    guard range.upperBound <= characters.count else { return text }
    let start = characters.index(characters.startIndex, offsetBy: range.lowerBound)
    let end = characters.index(characters.startIndex, offsetBy: range.upperBound)
    text[start..<end].backgroundColor = line.kind == .added ? DiffPalette.addedMark : DiffPalette.removedMark
    return text
}
private func rowColors(_ kind: DiffDocument.Kind) -> (row: Color, gutter: Color) {
    switch kind {
    case .added: (DiffPalette.addedRow, DiffPalette.addedGutter)
    case .removed: (DiffPalette.removedRow, DiffPalette.removedGutter)
    case .context: (.white, DiffPalette.gutter)
    }
}

private struct UnifiedDiffRow: View {
    let line: DiffDocument.Line
    var body: some View {
        let colors = rowColors(line.kind)
        HStack(alignment: .top, spacing: 0) {
            number(line.old, colors.gutter)
            number(line.new, colors.gutter)
            Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : "")
                .fontWeight(.semibold).foregroundStyle(line.kind == .added ? DiffPalette.green : DiffPalette.red).frame(width: 20)
            Text(marked(line)).foregroundStyle(DiffPalette.ink).fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .background(colors.row)
    }
    private func number(_ value: Int?, _ fill: Color) -> some View {
        Text(value.map(String.init) ?? "").foregroundStyle(DiffPalette.number)
            .frame(width: 40, alignment: .trailing).padding(.trailing, 8).frame(maxHeight: .infinity).background(fill)
    }
}

/// Side by side: the old line on the left, the new on the right; long lines wrap.
private struct SplitDiffRow: View {
    let row: DiffDocument.SplitRow
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            side(row.left, number: row.left?.old)
            Rectangle().fill(DiffPalette.line).frame(width: 1)
            side(row.right, number: row.right?.new)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func side(_ line: DiffDocument.Line?, number: Int?) -> some View {
        let blank = Color(red: 0.97, green: 0.965, blue: 0.955)
        let colors: (row: Color, gutter: Color) = line.map { rowColors($0.kind) } ?? (blank, blank)
        return HStack(alignment: .top, spacing: 0) {
            Text(number.map(String.init) ?? "").foregroundStyle(DiffPalette.number)
                .frame(width: 40, alignment: .trailing).padding(.trailing, 8).frame(maxHeight: .infinity).background(colors.gutter)
            Text(line.map { $0.kind == .added ? "+" : $0.kind == .removed ? "−" : "" } ?? "")
                .fontWeight(.semibold).foregroundStyle(line?.kind == .added ? DiffPalette.green : DiffPalette.red).frame(width: 18)
            Text(line.map(marked) ?? AttributedString(" ")).foregroundStyle(DiffPalette.ink).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .topLeading)
        .background(colors.row)
    }
}

/// A file with no text to compare: what it is, how its size changed, and where to open it.
private struct BinaryFileCard: View {
    let file: ChangedFile
    let folder: String
    let sizes: (old: Int?, new: Int?)
    private var url: URL { URL(fileURLWithPath: folder).appendingPathComponent(file.path) }
    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    /// The app that opens it ("Blender"), when there is one.
    private var app: String? {
        guard exists, let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }
    private var sizeText: String {
        func format(_ bytes: Int?) -> String? { bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } }
        switch (format(sizes.old), format(sizes.new)) {
        case let (old?, new?): return "\(old) → \(new)"
        case let (nil, new?): return "new · \(new)"
        case let (old?, nil): return "deleted · was \(old)"
        default: return ""
        }
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.gearshape").font(.system(size: 24)).foregroundStyle(DiffPalette.secondary)
                .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.945, green: 0.933, blue: 0.91)))
            Text(file.status == "Deleted" ? "Binary file deleted" : "Binary file changed").font(.system(size: 15, weight: .semibold)).foregroundStyle(DiffPalette.ink)
            Text(((file.path as NSString).lastPathComponent) + (sizeText.isEmpty ? "" : " · " + sizeText))
                .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(DiffPalette.secondary)
            Text("This file isn't text, so there's no line-by-line diff. Open it in its app to see what changed.")
                .font(.system(size: 13)).foregroundStyle(DiffPalette.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if exists {
                HStack(spacing: 8) {
                    Button(app.map { "Open in \($0)" } ?? "Open") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent).pointingHand()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.pointingHand()
                }
                .padding(.top, 4)
            }
        }
        .padding(32).frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DiffPalette.line))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiffPalette.gutter)
    }
}

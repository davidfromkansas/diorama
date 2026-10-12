import Foundation

/// A file's patch, read for people: git's header lines dropped, hunks with the function they're
/// in, each line numbered on both sides, and the changed part of an edited line marked.
public struct DiffDocument: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, added, removed }
    public struct Line: Equatable, Sendable, Identifiable {
        public var id: Int
        public var kind: Kind
        public var old: Int?
        public var new: Int?
        public var text: String
        /// The changed span of an edited line (character offsets), when it's only part of it.
        public var changed: Range<Int>?
        public init(id: Int, kind: Kind, old: Int?, new: Int?, text: String, changed: Range<Int>? = nil) {
            self.id = id; self.kind = kind; self.old = old; self.new = new; self.text = text; self.changed = changed
        }
    }
    public struct Hunk: Equatable, Sendable, Identifiable {
        public var id: Int
        public var oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
        /// The function or block git found the hunk in ("export class ChefAvatar").
        public var context: String
        public var lines: [Line]
        /// Old-side line number minus new-side, just after this hunk.
        public var shiftAfter: Int { (oldStart + oldCount) - (newStart + newCount) }
    }
    /// One row of the side-by-side view.
    public struct SplitRow: Equatable, Sendable, Identifiable {
        public var id: Int
        public var left: Line?
        public var right: Line?
        public init(id: Int, left: Line?, right: Line?) { self.id = id; self.left = left; self.right = right }
    }

    public var hunks: [Hunk] = []
    /// A binary file: no lines to show.
    public var binary = false
    /// Something other than a patch (too large, a symbolic link, an error), to show as it is.
    public var message: String?
    public init(message: String? = nil) { self.message = message }

    public static func parse(_ patch: String) -> DiffDocument {
        var document = DiffDocument()
        var hunk: Hunk?
        var old = 0, new = 0, next = 0
        func close() { if let done = hunk { document.hunks.append(markChanges(in: done)) }; hunk = nil }
        for text in patch.components(separatedBy: "\n") {
            if text.hasPrefix("@@ ") {
                close()
                // @@ -18,9 +18,13 @@ export class ChefAvatar
                let parts = text.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                func range(_ value: Substring) -> (Int, Int) {
                    let numbers = value.dropFirst().split(separator: ",").map { Int($0) ?? 0 }
                    return (numbers.first ?? 0, numbers.count > 1 ? numbers[1] : 1)
                }
                let (oldStart, oldCount) = range(parts[1]), (newStart, newCount) = range(parts[2])
                var context = parts.count > 3 ? String(parts[3]) : ""
                if context.hasPrefix("@@") { context = String(context.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                hunk = Hunk(id: document.hunks.count, oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, context: context, lines: [])
                old = oldStart; new = newStart
                continue
            }
            if hunk == nil {
                if text.hasPrefix("Binary files ") || text.hasPrefix("GIT binary patch") || text.hasPrefix("Binary file") { document.binary = true }
                continue
            }
            guard let first = text.first else { continue }
            switch first {
            case "+": hunk?.lines.append(Line(id: next, kind: .added, old: nil, new: new, text: String(text.dropFirst()))); new += 1
            case "-": hunk?.lines.append(Line(id: next, kind: .removed, old: old, new: nil, text: String(text.dropFirst()))); old += 1
            case " ": hunk?.lines.append(Line(id: next, kind: .context, old: old, new: new, text: String(text.dropFirst()))); old += 1; new += 1
            default: continue // "\ No newline at end of file"
            }
            next += 1
        }
        close()
        if document.hunks.isEmpty, !document.binary {
            let trimmed = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("diff --git") { document.message = trimmed }
        }
        return document
    }

    /// Pairs each run of removed lines with the added lines after it, and marks the part of each
    /// pair that differs (what's left after their shared start and end).
    static func markChanges(in hunk: Hunk) -> Hunk {
        var hunk = hunk
        var index = 0
        while index < hunk.lines.count {
            guard hunk.lines[index].kind == .removed else { index += 1; continue }
            var removedEnd = index
            while removedEnd < hunk.lines.count, hunk.lines[removedEnd].kind == .removed { removedEnd += 1 }
            var addedEnd = removedEnd
            while addedEnd < hunk.lines.count, hunk.lines[addedEnd].kind == .added { addedEnd += 1 }
            for pair in 0..<min(removedEnd - index, addedEnd - removedEnd) {
                let a = Array(hunk.lines[index + pair].text), b = Array(hunk.lines[removedEnd + pair].text)
                var prefix = 0
                while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
                var suffix = 0
                while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
                // Only worth marking when the lines share something.
                guard prefix + suffix > 0 else { continue }
                if a.count - suffix > prefix { hunk.lines[index + pair].changed = prefix..<(a.count - suffix) }
                if b.count - suffix > prefix { hunk.lines[removedEnd + pair].changed = prefix..<(b.count - suffix) }
            }
            index = max(addedEnd, index + 1)
        }
        return hunk
    }

    /// Unchanged lines (new-side numbers) before a hunk, back to the previous one or the top.
    public func gap(before index: Int) -> ClosedRange<Int>? {
        guard hunks.indices.contains(index) else { return nil }
        let start = index == 0 ? 1 : hunks[index - 1].newStart + hunks[index - 1].newCount
        let end = hunks[index].newStart - 1
        return end >= start ? start...end : nil
    }
    /// Unchanged lines after the last hunk, given the new file's length.
    public func gapAfterLast(lineCount: Int) -> ClosedRange<Int>? {
        guard let last = hunks.last else { return nil }
        let start = last.newStart + last.newCount
        return lineCount >= start ? start...lineCount : nil
    }

    /// The hunk's lines side by side: context on both sides, removals beside the additions that
    /// replaced them.
    public static func split(_ hunk: Hunk) -> [SplitRow] {
        var rows: [SplitRow] = []
        var removed: [Line] = [], added: [Line] = []
        func flush() {
            for i in 0..<max(removed.count, added.count) {
                rows.append(SplitRow(id: rows.count, left: i < removed.count ? removed[i] : nil, right: i < added.count ? added[i] : nil))
            }
            removed = []; added = []
        }
        for line in hunk.lines {
            switch line.kind {
            case .removed:
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added: added.append(line)
            case .context: flush(); rows.append(SplitRow(id: rows.count, left: line, right: line))
            }
        }
        flush()
        return rows
    }
}

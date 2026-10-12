import Testing
@testable import DioramaCore

struct DiffDocumentTests {
    let patch = """
    diff --git a/app/src/avatar/ChefAvatar.ts b/app/src/avatar/ChefAvatar.ts
    index 6a464e7..3043440 100644
    --- a/app/src/avatar/ChefAvatar.ts
    +++ b/app/src/avatar/ChefAvatar.ts
    @@ -18,4 +18,5 @@ export class ChefAvatar
       private mixer: AnimationMixer;
    -  private idle = "idle_breathe";
    +  private idle = "idle_jump";
    +  private jumpHeight = 0.18;
     }
    @@ -40,2 +41,2 @@ play(name: string)
    -    action?.reset().play();
    +    action?.reset().fadeIn(0.2).play();
    \\ No newline at end of file
    """

    @Test func readsHunksWithoutGitsHeaderLines() {
        let document = DiffDocument.parse(patch)
        #expect(!document.binary && document.message == nil && document.hunks.count == 2)
        let first = document.hunks[0]
        #expect(first.oldStart == 18 && first.newCount == 5 && first.context == "export class ChefAvatar")
        #expect(first.lines.map(\.kind) == [.context, .removed, .added, .added, .context])
        // Numbered on both sides: removals carry the old number, additions the new.
        #expect(first.lines[1].old == 19 && first.lines[1].new == nil && first.lines[2].new == 19 && first.lines[3].new == 20 && first.lines[4].old == 20 && first.lines[4].new == 21)
        #expect(!document.hunks.flatMap(\.lines).contains { $0.text.contains("No newline") || $0.text.hasPrefix("index") })
    }

    @Test func marksOnlyThePartOfAnEditedLineThatChanged() {
        let first = DiffDocument.parse(patch).hunks[0]
        let removed = first.lines[1], added = first.lines[2]
        #expect(Array(removed.text)[removed.changed!].map(String.init).joined() == "breathe")
        #expect(Array(added.text)[added.changed!].map(String.init).joined() == "jump")
        // An added line with no partner is just added.
        #expect(first.lines[3].changed == nil)
    }

    @Test func foldsTheUnchangedLinesBetweenHunks() {
        let document = DiffDocument.parse(patch)
        #expect(document.gap(before: 0) == 1...17)
        #expect(document.gap(before: 1) == 23...40)
        #expect(document.gapAfterLast(lineCount: 60) == 43...60)
        #expect(document.hunks[0].shiftAfter == -1)
    }

    @Test func sideBySidePairsRemovalsWithTheirReplacements() {
        let rows = DiffDocument.split(DiffDocument.parse(patch).hunks[0])
        #expect(rows.count == 4)
        #expect(rows[1].left?.kind == .removed && rows[1].right?.kind == .added)
        #expect(rows[2].left == nil && rows[2].right?.text == "  private jumpHeight = 0.18;")
    }

    @Test func binaryAndMessagesAreNotPatches() {
        #expect(DiffDocument.parse("diff --git a/x.blend b/x.blend\nindex 1..2 100644\nBinary files a/x.blend and b/x.blend differ").binary)
        #expect(DiffDocument.parse("Diff is too large to preview. Open externally to inspect it.").message?.hasPrefix("Diff is too large") == true)
    }
}

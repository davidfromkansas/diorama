import Testing
@testable import DioramaCore

struct TurnQuestionTests {
    @Test func aQuestionFollowedByAShortTailStillAsks() {
        let pia = "This local repository is named `kitchen-demo`, but has no Git remote configured, and the GitHub connector found no matching repository.\n\nWhat GitHub repository URL or `owner/name` should I use? Nothing was changed."
        #expect(TurnQuestion.asking(pia) == .question("What GitHub repository URL or `owner/name` should I use?"))
        #expect(TurnQuestion.asking("Which theme should the dashboard use? Let me know.") == .question("Which theme should the dashboard use?"))
        #expect(TurnQuestion.asking("Should I use Postgres or SQLite?") == .question("Should I use Postgres or SQLite?"))
    }

    @Test func offersAndBuriedOrQuotedQuestionsAreTold() {
        #expect(TurnQuestion.asking("Done: 4 files changed and tests pass. Want me to open a PR?") == .offer("Want me to open a PR?"))
        #expect(TurnQuestion.asking("Would you like me to add tests as well?")?.text == "Would you like me to add tests as well?")
        // A question early on, then a long summary: the turn finished its work.
        let buried = "Should this use the new API? I went with the new API. It handles retries, streams results and keeps the old callers working through a small shim that maps their arguments."
        #expect(TurnQuestion.asking(buried) == nil)
        #expect(TurnQuestion.asking("Here is the fix:\n```\nif ready? { go() }\n```\nAll tests pass.") == nil)
        #expect(TurnQuestion.asking("> Why does this fail?\n\nIt failed on a missing key; fixed.") == nil)
        #expect(TurnQuestion.asking("All done.") == nil)
    }
}

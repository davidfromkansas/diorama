import Foundation
import Testing
@testable import DioramaCore

/// Deterministic randomness for the picking tests.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct ChefCharacterTests {
    private let all = ["classic", "capybara", "cat", "pig", "monkey", "tiger", "bunny", "mouse", "little", "puppy"]

    @Test func noCharacterRepeatsUntilEveryOneIsInUse() {
        var registry = ChefCharacters(), random = Seeded(state: 7)
        var scene: [String] = []
        for i in 0..<10 {
            scene.append(registry.character(for: "agent\(i)", project: "p", available: all, inScene: scene, using: &random))
        }
        #expect(Set(scene).count == 10)
        // The eleventh and twelfth repeat, each a character worn the fewest times.
        let eleventh = registry.character(for: "agent10", project: "p", available: all, inScene: scene, using: &random)
        scene.append(eleventh)
        let twelfth = registry.character(for: "agent11", project: "p", available: all, inScene: scene, using: &random)
        #expect(all.contains(eleventh) && all.contains(twelfth) && eleventh != twelfth)
    }

    @Test func eachKitchenPicksOnItsOwn() {
        var registry = ChefCharacters(), random = Seeded(state: 3)
        let first = registry.character(for: "a", project: "one", available: all, inScene: [], using: &random)
        // Another project's kitchen may wear what this one does: only its own chefs count.
        var picks = Set<String>()
        for i in 0..<40 { picks.insert(registry.character(for: "b\(i)", project: "two", available: all, inScene: [], using: &random)) }
        #expect(picks.contains(first))
    }

    @Test func anAgentKeepsItsCharacterAcrossVisitsAndRelaunches() throws {
        var registry = ChefCharacters(), random = Seeded(state: 11)
        let worn = registry.character(for: "a", project: "p", available: all, inScene: [], using: &random)
        // Back in the kitchen later, even when another chef now wears the same character.
        #expect(registry.character(for: "a", project: "p", available: all, inScene: [worn], using: &random) == worn)
        let restored = try JSONDecoder().decode(ChefCharacters.self, from: JSONEncoder().encode(registry))
        var again = restored
        #expect(again.character(for: "a", project: "p", available: all, inScene: [], using: &random) == worn)
        // A character that's gone (no longer bundled) is replaced.
        #expect(again.character(for: "a", project: "p", available: all.filter { $0 != worn }, inScene: [], using: &random) != worn)
    }

    @Test func picksAreRandomNotFixed() {
        var firsts = Set<String>()
        for seed in 0..<30 as Range<UInt64> {
            var registry = ChefCharacters(), random = Seeded(state: seed &* 7919 &+ 1)
            firsts.insert(registry.character(for: "a", project: "p", available: all, inScene: [], using: &random))
        }
        #expect(firsts.count >= 5)
    }
}

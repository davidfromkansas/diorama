import Testing
@testable import DioramaCore

struct OnboardingModelsTests {
    let codex = ExecutionModel(id: "gpt-test", name: "OpenAI test", efforts: [], defaultEffort: "", isDefault: true)
    let claude = ExecutionModel(id: "claude/sonnet", name: "Sonnet", efforts: [], defaultEffort: "", isDefault: false)
    func info(_ c: Bool, _ a: Bool) -> WireValue { .object(["codex": .bool(c), "claude": .bool(a)]) }
    @Test func firstRunMatrix() {
        #expect(OnboardingModels.initialSelection(models: [claude], connections: info(false,true)) == "claude/sonnet")
        #expect(OnboardingModels.initialSelection(models: [codex], connections: info(true,false)) == "")
        #expect(OnboardingModels.initialSelection(models: [codex,claude], connections: info(true,true)) == "")
        #expect(OnboardingModels.initialSelection(models: [], connections: info(false,false)) == nil)
    }
    @Test func unavailableDefaultsCannotFinishOrUseStaleCatalog() {
        #expect(!OnboardingModels.isAvailable("", models: [claude], connections: info(false,true)))
        #expect(!OnboardingModels.isAvailable("claude/sonnet", models: [codex,claude], connections: info(true,false)))
        #expect(!OnboardingModels.isAvailable("gpt-deleted", models: [codex], connections: info(true,false)))
        #expect(!OnboardingModels.isAvailable("", models: [], connections: info(true,false)))
        #expect(OnboardingModels.isAvailable("claude/sonnet", models: [claude], connections: info(false,true)))
    }
}

import SwiftUI
import DioramaCore

/// The model and effort chosen for a conversation's next message: the composer sends with them
/// and the conversation header's model menu shows and changes them.
@Observable final class ComposerChoices {
    var model = ""
    var effort = ""
}

extension LibraryModel {
    func composerChoices(_ session: Session) -> ComposerChoices {
        if let choices = composerChoiceStore[session.id] { return choices }
        let choices = ComposerChoices(); composerChoiceStore[session.id] = choices; return choices
    }
}

struct ComposerModelMenu: View {
    let controller: ExecutionController
    @Binding var model: String
    @Binding var effort: String
    let effectiveModel: String
    let effectiveEffort: String
    @State private var showing = false
    @FocusState private var popoverFocused: Bool
    private var selected: ExecutionModel? {
        controller.models.first { $0.id == (model.isEmpty ? effectiveModel : model) } ?? (model.isEmpty && effectiveModel.isEmpty ? controller.models.first { $0.isDefault } : nil)
    }
    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 5) {
                Text(selected?.name ?? (model.isEmpty ? (effectiveModel.isEmpty ? "Model" : effectiveModel) : model)).lineLimit(1).truncationMode(.middle)
                Text((effort.isEmpty ? (effectiveEffort.isEmpty ? "Default" : effectiveEffort) : effort).capitalized).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }.font(.system(size: 14)).padding(.vertical, 7)
        }.pointingHand().buttonStyle(HoverButtonStyle()).accessibilityLabel("Model and reasoning effort").help("Choose model and reasoning effort")

            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model and reasoning").font(.headline)
                    ExecutionModelPicker(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel)
                    if controller.models.isEmpty { Text("Connect an account in Settings to see its models.").font(.caption).foregroundStyle(.secondary) }
                }.padding(18).frame(width: 420).task { await controller.connect() }
                    .focusable().focused($popoverFocused).onAppear { popoverFocused = true }
                    .avatarPopoverDismissal(isPresented: $showing)
            }
    }
}

/// The header's model capsule ("Opus 5.5", "GPT-6-Astra · High"): opens the model menu. The
/// models load when the header appears, so the menu opens at once with what's already known.
struct HeaderModelMenu: View {
    let controller: ExecutionController
    @Bindable var choices: ComposerChoices
    let effectiveModel: String
    let effectiveEffort: String
    @State private var showing = false
    @FocusState private var focused: Bool
    private var current: String { choices.model.isEmpty ? effectiveModel : choices.model }
    private var selected: ExecutionModel? {
        controller.models.first { $0.id == current } ?? (current.isEmpty ? controller.models.first { $0.isDefault } : nil)
    }
    /// The model's name, with its effort when the model has effort levels.
    var label: String {
        let name = selected?.name ?? (current.isEmpty ? "Model" : current)
        guard let selected, !selected.efforts.isEmpty else { return name }
        let level = choices.effort.isEmpty ? (effectiveEffort.isEmpty ? "Default" : effectiveEffort) : choices.effort
        return name + " · " + level.capitalized
    }
    var body: some View {
        Button { showing.toggle() } label: {
            Label {
                HStack(spacing: 4) {
                    Text(label).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            } icon: { Image(systemName: "sparkle").font(.system(size: 10)) }
            .labelStyle(AvatarCapsuleLabelStyle()).font(.system(size: 11.5, weight: .medium))
            .avatarCapsule(highlighted: showing)
        }
        .buttonStyle(.plain).pointingHand().help("Choose model and reasoning effort").accessibilityLabel("Model: \(label)")
        .task { await controller.connect() }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            // Scrolls rather than growing past the window, so it always opens below the capsule.
            ScrollView {
                AvatarModelPicker(controller: controller, model: $choices.model, effort: $choices.effort, effectiveModel: effectiveModel)
                    .padding(8).frame(width: 300, alignment: .leading)
            }.frame(maxHeight: 420)
                .environment(\.colorScheme, .light).tint(.blue)
                .focusable().focused($focused).onAppear { focused = true }
                .avatarPopoverDismissal(isPresented: $showing)
        }
    }
}

/// The model menu, iMessage style: each connected provider's models (a provider that isn't
/// connected isn't mentioned), the current one checked, effort only for models that have it.
struct AvatarModelPicker: View {
    let controller: ExecutionController
    @Binding var model: String
    @Binding var effort: String
    let effectiveModel: String
    private var current: String { model.isEmpty ? effectiveModel : model }
    private var selected: ExecutionModel? {
        controller.models.first { $0.id == current } ?? (current.isEmpty ? controller.models.first { $0.isDefault } : nil)
    }
    /// The next message would go to the other provider (the conversation continues there).
    private var switchesProvider: Bool { !model.isEmpty && !effectiveModel.isEmpty && model.hasPrefix("claude/") != effectiveModel.hasPrefix("claude/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if controller.models.isEmpty {
                Text(controller.connecting ? "Checking available models…" : "Connect an account in Settings to see its models.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
            }
            // The current model's provider first, so its checked row is in view when the menu opens.
            ForEach(current.isEmpty || current.hasPrefix("claude/") ? [true, false] : [false, true], id: \.self) { claude in
                let choices = controller.models.filter { $0.id.hasPrefix("claude/") == claude }
                if !choices.isEmpty {
                    provider(claude ? "Anthropic" : "OpenAI", mark: claude ? Color(red: 0.79, green: 0.39, blue: 0.26) : Color(white: 0.13))
                    ForEach(choices) { choice in row(choice) }
                }
            }
            if let levels = selected?.efforts, !levels.isEmpty {
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                Text("Reasoning effort").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10)
                // Segments when they fit; a pop-up for models with many levels.
                ViewThatFits(in: .horizontal) {
                    effortPicker(levels).pickerStyle(.segmented).fixedSize()
                    effortPicker(levels).pickerStyle(.menu).fixedSize()
                }
                .labelsHidden().controlSize(.small).padding(.horizontal, 8).padding(.vertical, 4).pointingHand()
            }
            if switchesProvider {
                Label("Your next message continues with the other provider. Permissions reset, so review them before sending.", systemImage: "shield")
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.23))
                    .padding(8).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 6).padding(.top, 4)
            }
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            HStack {
                Spacer()
                Button(controller.connecting ? "Refreshing models…" : "Refresh models") { Task { await controller.refreshModels() } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor)
                    .pointingHand().disabled(controller.connecting)
            }.padding(.horizontal, 10).padding(.bottom, 4)
        }
    }

    private func effortPicker(_ levels: [String]) -> some View {
        Picker("Reasoning effort", selection: $effort) {
            Text("Default").tag("")
            ForEach(levels, id: \.self) { Text($0.capitalized).tag($0) }
        }
    }
    private func provider(_ name: String, mark: Color) -> some View {
        HStack(spacing: 7) {
            Text(String(name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(mark, in: RoundedRectangle(cornerRadius: 4))
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }
    private func row(_ choice: ExecutionModel) -> some View {
        let checked = choice.id == (selected?.id ?? "")
        return Button { model = choice.id; effort = "" } label: {
            HStack(spacing: 6) {
                Text(choice.name).font(.system(size: 14))
                if choice.isDefault {
                    Text("Default").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer(minLength: 8)
                if checked { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(checked ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).pointingHand().accessibilityAddTraits(checked ? .isSelected : [])
    }
}

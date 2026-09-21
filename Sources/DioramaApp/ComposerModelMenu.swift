import SwiftUI
import DioramaCore

struct ComposerModelMenu: View {
    let controller: ExecutionController
    @Binding var model: String
    @Binding var effort: String
    let effectiveModel: String
    let effectiveEffort: String
    @State private var showing = false
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
        }.buttonStyle(.plain).accessibilityLabel("Model and reasoning effort").help("Choose model and reasoning effort")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model and reasoning").font(.headline)
                    ExecutionModelPicker(controller: controller, model: $model, effort: $effort, effectiveModel: effectiveModel)
                    if controller.models.isEmpty { Text("Connect an account in Settings to see its models.").font(.caption).foregroundStyle(.secondary) }
                }.padding(18).frame(width: 420).task { await controller.connect() }
            }
    }
}

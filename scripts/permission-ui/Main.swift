import SwiftUI
import DioramaCore

@main struct PermissionPreviewApp: App {
    var body: some Scene { WindowGroup("Permission review verification") { Preview().frame(minWidth: 500, minHeight: 440) } }
}
struct Preview: View {
    @State var scenario = "Read"
    @State var result = "No decision sent"
    @State var draft = "Keep my draft intact"
    @State var connected = true
    var request: ExecutionRequest {
        var p: [String: WireValue] = ["availableDecisions": .array([.string("accept"), .string("decline")])]
        switch scenario {
        case "Read": p["toolName"] = .string("Read"); p["toolInput"] = .object(["file_path": .string("/Users/example/Projects/Diorama/Package.swift")])
        case "Long command": p["command"] = .string(String(repeating: "echo example command\n", count: 60)); p["cwd"] = .string("/tmp/example")
        default: p["permissions"] = .object(["network": .object(["enabled": .bool(true)])])
        }
        return ExecutionRequest(wireID: .string(scenario), method: scenario == "Network" ? "item/permissions/requestApproval" : "item/commandExecution/requestApproval", params: .object(p))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Isolated UI test · no actual permissions granted").font(.caption)
            Picker("Example", selection: $scenario) { ForEach(["Read", "Long command", "Network"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            Toggle("Connected", isOn: $connected)
            PermissionReviewCard(request: request, connected: connected) { result = $0.pretty }.id(scenario)
            TextField("Draft", text: $draft)
            Text(result).font(.caption).textSelection(.enabled)
        }.padding(20)
    }
}

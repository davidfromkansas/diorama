import SwiftUI
import DioramaCore

/// The Devin API key: cloud sessions billed as API usage to a Devin organization, next to the
/// Devin CLI, which uses the person's own subscription. The key is kept in the login Keychain.
struct DevinAPISettingsView: View {
    let info: WireValue
    let changed: () -> Void
    @State private var apiKey = ""
    @State private var organization = ""
    @State private var saved = DevinCloudCredentials.load()
    @State private var editing = false
    @State private var working = false
    @State private var problem: String?

    private var connected: Bool { info["devinAPI"].bool }
    private var checking: Bool { info == .null || info["devinAPIChecking"].bool }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Devin API").font(.headline)
                if !connected && saved == nil { Text("Optional").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if checking || working { ProgressView().controlSize(.small) }
                Label(connected ? "Connected" : saved == nil ? "Not set up" : checking ? "Checking…" : "Couldn’t verify key",
                      systemImage: connected ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(connected ? Color.green : Color.secondary)
            }
            Text("Runs Devin in its own cloud machine, billed as API usage to your Devin organization. Pick “Devin · Cloud (API)” as the model. Devin works on the folder’s GitHub repository and opens pull requests there.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if saved != nil, !connected, let error = info["devinAPIError"].string, !checking {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if saved == nil || editing {
                SecureField("API key (cog_…)", text: $apiKey).textFieldStyle(.roundedBorder)
                TextField("Organization ID", text: $organization).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save and check", action: save).pointingHand()
                        .disabled(working || apiKey.trimmingCharacters(in: .whitespaces).isEmpty || organization.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing { Button("Cancel") { editing = false; apiKey = ""; problem = nil }.pointingHand() }
                    Spacer()
                    Link("Get a key", destination: URL(string: "https://app.devin.ai/settings")!).pointingHand()
                }
                Text("Create a service user under Settings › Devin API in the Devin app. Its organization ID is shown there too.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    if let saved { Text("Organization " + saved.organization).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Change key…") { editing = true; organization = saved?.organization ?? "" }.pointingHand()
                    Button("Remove", role: .destructive, action: remove).pointingHand()
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func save() {
        let credentials = DevinCloudCredentials(apiKey: apiKey, organization: organization)
        working = true; problem = nil
        Task {
            defer { working = false }
            do {
                // Checked before saving, so a mistyped key never replaces a working one.
                try await DevinCloudAPI(credentials: credentials).verify()
                try credentials.save()
                saved = credentials; editing = false; apiKey = ""
                changed()
            } catch { problem = error.localizedDescription }
        }
    }
    private func remove() {
        do { try DevinCloudCredentials.remove(); saved = nil; editing = false; changed() }
        catch { problem = error.localizedDescription }
    }
}

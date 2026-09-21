import SwiftUI
import DioramaCore

struct PermissionReviewCard: View {
    let request: ExecutionRequest
    let connected: Bool
    let respond: (WireValue) -> Void
    @State private var reviewing = false
    private var presentation: PermissionPresentation { PermissionPresentation(request: request) }
    private var unavailable: Bool { request.responding || !connected }
    private var extras: [ApprovalDecision] { request.approvalDecisions.filter { !["accept", "decline"].contains($0.value.string ?? "") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(request.responding ? "Decision sent · awaiting response" : connected ? "Permission needed" : "Connection lost · reconnect to respond", systemImage: "hand.raised")
                .font(.caption).foregroundStyle(.secondary)
            Text(presentation.title).font(.title3.weight(.semibold))
            if let reason = presentation.reason { Text("Agent’s reason: " + reason).font(.body).lineLimit(2).textSelection(.enabled) }
            Text(presentation.target).font(.system(size: 13, design: .monospaced))
                .lineLimit(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { reviewButton; Spacer(); decisions }
                VStack(alignment: .leading, spacing: 12) { reviewButton; HStack { Spacer(); decisions } }
            }
            Text(presentation.scope).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))
        .sheet(isPresented: $reviewing) { reviewSheet }
    }
    private var reviewButton: some View { Button("Review details…") { reviewing = true } }
    private var decisions: some View {
        HStack(spacing: 10) {
            if request.method == "item/permissions/requestApproval" {
                Button("Deny") { grant(.object([:])) }
                Button("Allow for this turn") { grant(request.params["permissions"]) }.buttonStyle(.borderedProminent)
            } else {
                if request.decisions.contains("decline") { Button("Deny") { decide(.string("decline")) } }
                if request.decisions.contains("accept") { Button("Allow once") { decide(.string("accept")) }.buttonStyle(.borderedProminent) }
                if !extras.isEmpty { Button("More options…") { reviewing = true } }
                if request.approvalDecisions.isEmpty { Text("Unsupported request · use Stop to cancel").font(.caption) }
            }
        }.controlSize(.large).disabled(unavailable)
    }
    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(presentation.title).font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(presentation.details).font(.system(size: 14, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if request.method != "item/permissions/requestApproval", !extras.isEmpty {
                        Divider()
                        Text("Additional options").font(.headline)
                        ForEach(extras) { decision in
                            VStack(alignment: .leading, spacing: 8) {
                                if let scope = decision.scope { Text(scope).font(.body.monospaced()).textSelection(.enabled) }
                                else if decision.value.string == "acceptForSession" { Text("Allows the provider’s requested action scope for this session.").foregroundStyle(.secondary) }
                                Button(decision.title) { decide(decision.value) }.disabled(unavailable)
                            }
                        }
                    }
                    DisclosureGroup("Raw request") { Text(request.params.pretty).font(.system(size: 13, design: .monospaced)).textSelection(.enabled) }
                }.padding(.trailing, 8)
            }.frame(minHeight: 180, idealHeight: 320, maxHeight: 420)
            Divider()
            HStack { Button("Back") { reviewing = false }.keyboardShortcut(.cancelAction); Spacer(); decisions }
        }.padding(24).frame(minWidth: 460, idealWidth: 680, maxWidth: 800)
    }
    private func grant(_ permissions: WireValue) { reviewing = false; respond(.object(["permissions": permissions, "scope": .string("turn")])) }
    private func decide(_ value: WireValue) { reviewing = false; respond(.object(["decision": value])) }
}

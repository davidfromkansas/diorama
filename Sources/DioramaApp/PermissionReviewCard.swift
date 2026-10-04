import SwiftUI
import DioramaCore

struct PermissionReviewCard: View {
    let request: ExecutionRequest
    var relatedItem: WireValue = .null
    let connected: Bool
    let respond: (WireValue) -> Void
    @State private var reviewing = false
    private var presentation: PermissionPresentation { PermissionPresentation(request: request, relatedItem: relatedItem) }
    private var unavailable: Bool { request.responding || !connected }
    private var extras: [ApprovalDecision] { request.approvalDecisions.filter { !["accept", "decline"].contains($0.value.string ?? "") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.title, systemImage: "hand.raised").font(.headline)
            if request.responding || !connected {
                Text(request.responding ? "Decision sent · awaiting response" : "Connection lost · reconnect to respond")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let reason = presentation.reason { Text("Agent’s reason: " + reason).font(.callout).lineLimit(1).textSelection(.enabled) }
            Text(presentation.target).font(.system(size: 13, design: .monospaced))
                .lineLimit(2).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { reviewButton; Spacer(); decisions }
                VStack(alignment: .leading, spacing: 8) { reviewButton; HStack { Spacer(); decisions } }
            }
            Text(presentation.scope).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))
        .sheet(isPresented: $reviewing) { reviewSheet }
    }
    private var reviewButton: some View { Button("Review details…") { reviewing = true }.pointingHand() }
    private var decisions: some View {
        HStack(spacing: 10) {
            if request.method == "item/permissions/requestApproval" {
                Button("Deny") { grant(.object([:])) }.pointingHand()
                Button("Allow for this turn") { grant(request.params["permissions"]) }.pointingHand().buttonStyle(.borderedProminent)
            } else {
                if request.decisions.contains("decline") { Button("Deny") { decide(.string("decline")) }.pointingHand() }
                if request.decisions.contains("accept") { Button("Allow once") { decide(.string("accept")) }.pointingHand().buttonStyle(.borderedProminent) }
                if request.approvalDecisions.isEmpty { Text("Unsupported request · use Stop to cancel").font(.caption) }
            }
        }.disabled(unavailable)
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
                                Button(decision.title) { decide(decision.value) }.pointingHand().disabled(unavailable)
                            }
                        }
                    }
                    DisclosureGroup { Text(request.params.pretty).font(.system(size: 13, design: .monospaced)).textSelection(.enabled) } label: { Text("Raw request").disclosurePointingHand() }
                }.padding(.trailing, 8)
            }.frame(minHeight: 180, idealHeight: 320, maxHeight: 420)
            Divider()
            HStack { Button("Back") { reviewing = false }.pointingHand().keyboardShortcut(.cancelAction); Spacer(); decisions }
        }.padding(24).frame(minWidth: 460, idealWidth: 680, maxWidth: 800)
    }
    private func grant(_ permissions: WireValue) { reviewing = false; respond(.object(["permissions": permissions, "scope": .string("turn")])) }
    private func decide(_ value: WireValue) { reviewing = false; respond(.object(["decision": value])) }
}

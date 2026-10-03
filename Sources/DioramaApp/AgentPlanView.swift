import SwiftUI
import SceneKit
import DioramaCore

enum AgentInspectionKind: String, CaseIterable, Hashable {
    case proposal, tasks
    var title: String { self == .proposal ? "Plan" : "Tasks" }
    func available(in plan: AgentPlan?) -> Bool {
        self == .proposal ? plan?.hasProposal == true : plan?.hasTasks == true
    }
    func label(for plan: AgentPlan?) -> String {
        self == .proposal ? "View plan" : "View tasks · " + (plan?.taskProgress ?? "0/0")
    }
}

struct AgentInspectionDestination: Hashable {
    let agentID: String
    let kind: AgentInspectionKind
    var nodeName: String { kind.rawValue + ":" + agentID }
    init(agentID: String, kind: AgentInspectionKind) { self.agentID = agentID; self.kind = kind }
    init?(nodeName: String) {
        guard let separator = nodeName.firstIndex(of: ":"),
              let kind = AgentInspectionKind(rawValue: String(nodeName[..<separator])) else { return nil }
        self.init(agentID: String(nodeName[nodeName.index(after: separator)...]), kind: kind)
    }
}

/// A shared billboard anchor keeps the two controls aligned while orbiting.
enum AgentPlanButton {
    static func geometry(_ title: String, width: Double) -> SCNPlane {
        let size = NSSize(width: width * 400, height: 90)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), xRadius: 24, yRadius: 24).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 32, weight: .medium), .foregroundColor: NSColor.darkGray]
        let text = title as NSString
        text.draw(at: NSPoint(x: (size.width - text.size(withAttributes: attributes).width) / 2, y: 24), withAttributes: attributes)
        image.unlockFocus()
        let material = SCNMaterial(); material.diffuse.contents = image; material.lightingModel = .constant
        material.isDoubleSided = true
        let plane = SCNPlane(width: width, height: 0.225); plane.materials = [material]; plane.name = title
        return plane
    }
    static let proposalGeometry = geometry("View plan", width: 0.85)
    static func update(root: SCNNode, id: String, plan: AgentPlan?, height: Double, scale: Double = 1) {
        let anchor = root.childNode(withName: "inspection-controls", recursively: false) ?? SCNNode()
        if anchor.parent == nil {
            anchor.name = "inspection-controls"; anchor.position.y = height
            anchor.scale = SCNVector3(scale, scale, scale)
            anchor.constraints = [SCNBillboardConstraint()]; root.addChildNode(anchor)
        }
        let both = plan?.hasProposal == true && plan?.hasTasks == true
        for kind in AgentInspectionKind.allCases {
            let destination = AgentInspectionDestination(agentID: id, kind: kind)
            let available = kind.available(in: plan)
            let existing = anchor.childNode(withName: destination.nodeName, recursively: false)
            guard available else { existing?.isHidden = true; continue }
            let node = existing ?? SCNNode()
            let label = kind.label(for: plan)
            // Rebuild only the changed count texture, never during camera movement.
            if node.geometry?.name != label {
                node.geometry = kind == .proposal ? proposalGeometry : geometry(label, width: 1.3)
            }
            node.name = destination.nodeName; node.isHidden = false; node.castsShadow = false
            node.position.x = both ? (kind == .proposal ? -0.69 : 0.465) : 0
            if node.parent == nil { anchor.addChildNode(node) }
        }
    }
}

struct AgentPlanModal: View {
    let agent: WorkspaceAgent
    let kind: AgentInspectionKind
    let paused: Bool
    let close: () -> Void
    @FocusState private var closeFocused: Bool
    @State private var scroll: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name).font(.headline)
                    Text(agent.provider).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.pointingHand()
                    .buttonStyle(.plain).accessibilityLabel("Close " + kind.title.lowercased()).focusable().focused($closeFocused)
                    .onKeyPress(.space) { close(); return .handled }
                    .onKeyPress(.return) { close(); return .handled }
            }
            Text("Latest reported " + kind.title.lowercased() + (previousTurn ? " · Previous turn" : ""))
                .font(.caption).foregroundStyle(.secondary)
            if let time = updatedAt {
                Text("Last updated \(time.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            Text(paused ? "Observation paused" : agent.planUnavailable ? "Unavailable · showing last known " + kind.title.lowercased() : agent.freshness.rawValue)
                .font(.caption).foregroundStyle(.secondary)
            if agent.plan?.truncated == true { Text("Available history is truncated.").font(.caption).foregroundStyle(.secondary) }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let plan = agent.plan, kind.available(in: plan) {
                        if kind == .tasks {
                            Text("Task checklist · " + plan.taskProgress + " reported completed").font(.headline).id("checklist")
                            ForEach(rows(plan.checklist)) { row in
                                let step = row.step
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: icon(step.status)).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                        Text(status(step.status)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.id(row.id)
                            }
                        }
                        if kind == .proposal, let proposal = plan.proposal {
                            Text(proposal.status == "draft" ? "Proposed plan · Draft" : "Proposed plan").font(.headline).id("proposal")
                            TranscriptContent(text: proposal.detail)
                        }
                    } else { Text(kind == .proposal ? "No plan currently reported" : "No tasks currently reported").foregroundStyle(.secondary).id("empty") }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).scrollTargetLayout()
            }.scrollPosition(id: $scroll)
        }
        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.2)))
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
        .environment(\.colorScheme, .light)
        .task {
            // Let an invoking popover finish dismissing before claiming keyboard focus.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            closeFocused = true
        }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title + " for " + agent.name)
    }
    private var updatedAt: Date? { kind == .proposal ? agent.plan?.proposalUpdatedAt : agent.plan?.taskUpdatedAt }
    private var previousTurn: Bool { (kind == .proposal ? agent.plan?.proposalPreviousTurn : agent.plan?.tasksPreviousTurn) == true }
    private struct Row: Identifiable {
        let id: String
        let step: SessionActivityRecord
    }
    private func rows(_ steps: [SessionActivityRecord]) -> [Row] {
        steps.enumerated().map { index, step in
            // Full-checklist revisions have no durable task IDs; keep their viewport slots stable.
            let revision = step.nativeID.split(separator: ":").contains { $0.count == 64 }
            return Row(id: revision ? "checklist-slot-\(index)" : step.id, step: step)
        }
    }
    private func icon(_ value: String) -> String {
        switch value {
        case "completed": "checkmark.circle"
        case "inProgress", "in_progress": "circle.lefthalf.filled"
        default: "circle"
        }
    }
    private func status(_ value: String) -> String {
        switch value {
        case "inProgress", "in_progress": "In progress"
        case "completed": "Completed"
        case "pending": "Pending"
        case "", "unknown": "Unknown"
        default: value
        }
    }
}

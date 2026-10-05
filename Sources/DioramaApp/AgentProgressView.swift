import DioramaCore
import SwiftUI

/// An agent's progress: its reported checklist when it keeps one, then what it has actually done
/// this turn (files edited, commands run, tests). Shared by the kitchen's progress panel and the
/// serving window.
struct AgentProgressSections: View {
    let agent: WorkspaceAgent
    /// Show at most this many edited files before summarizing the rest.
    var fileLimit = 8
    /// Smaller type and spacing for the kitchen's command bar.
    var compact = false
    private var heading: Font { compact ? .caption.weight(.semibold) : .headline }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 14) {
            if let plan = agent.plan, plan.hasTasks {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checklist · \(plan.completedTaskCount) of \(plan.checklist.count) done" + (plan.tasksPreviousTurn ? " · previous turn" : ""))
                        .font(heading)
                    ForEach(Array(plan.checklist.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: Self.icon(step.status)).foregroundStyle(step.status == "completed" ? .green : .secondary)
                                .accessibilityLabel(Self.status(step.status))
                            Text(step.title).strikethrough(step.status == "completed", color: .secondary)
                                .foregroundStyle(step.status == "completed" ? .secondary : .primary)
                        }
                    }
                    if !compact { Text("Reported by the agent").font(.caption).foregroundStyle(.secondary) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(agent.status == .working ? "This turn so far" : "This turn").font(heading)
                let work = agent.turnWork
                if work.isEmpty {
                    Text(agent.status == .working ? "No file edits, commands or tests yet." : "No file edits, commands or tests in this turn.")
                        .foregroundStyle(.secondary)
                } else {
                    if !work.files.isEmpty {
                        Label("Edited \(work.files.count) file\(work.files.count == 1 ? "" : "s")", systemImage: "pencil")
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(work.files.prefix(fileLimit), id: \.self) { path in
                                Text(display(path)).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.head)
                            }
                            if work.files.count > fileLimit {
                                Text("and \(work.files.count - fileLimit) more").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.leading, compact ? 20 : 26)
                    }
                    if work.commands > 0 {
                        Label("Ran \(work.commands) command\(work.commands == 1 ? "" : "s")" + (work.failedCommands > 0 ? " · \(work.failedCommands) failed" : ""),
                              systemImage: "terminal")
                    }
                    ForEach(Array(work.tests.enumerated()), id: \.offset) { _, test in
                        Label {
                            Text(Self.outcome(test.outcome) + " · ") + Text(test.command).font(.system(compact ? .caption : .callout, design: .monospaced))
                        } icon: {
                            Image(systemName: Self.testIcon(test.outcome)).foregroundStyle(test.outcome == .failed ? .red : test.outcome == .passed ? .green : .secondary)
                        }.lineLimit(1)
                    }
                }
                if !compact { Text("Observed from the agent's tool calls").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .font(compact ? .caption : nil)
        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }

    /// Paths inside the agent's worktree are shown relative to it.
    private func display(_ path: String) -> String {
        guard let root = agent.worktree, !root.isEmpty, path.hasPrefix(root) else { return path }
        let relative = path.dropFirst(root.count).drop { $0 == "/" }
        return relative.isEmpty ? path : String(relative)
    }
    static func icon(_ status: String) -> String {
        switch status {
        case "completed": "checkmark.circle.fill"
        case "inProgress", "in_progress": "circle.lefthalf.filled"
        default: "circle"
        }
    }
    static func status(_ status: String) -> String {
        switch status {
        case "completed": "Done"
        case "inProgress", "in_progress": "In progress"
        default: "To do"
        }
    }
    static func testIcon(_ outcome: TurnWork.Outcome) -> String {
        switch outcome {
        case .running: "hourglass"
        case .passed: "checkmark.seal.fill"
        case .failed: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }
    static func outcome(_ outcome: TurnWork.Outcome) -> String {
        switch outcome {
        case .running: "Testing"
        case .passed: "Tests passed"
        case .failed: "Tests failed"
        case .unknown: "Test result not reported"
        }
    }
}

/// The kitchen's progress panel, opened from a chef's name tag.
struct AgentProgressModal: View {
    let agent: WorkspaceAgent
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name + " · Progress").font(.headline)
                    Text(TaskTitle.full(agent.task)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.pointingHand().buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction).accessibilityLabel("Close progress")
            }
            Divider()
            ScrollView { AgentProgressSections(agent: agent) }
        }
        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.2)))
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
        .environment(\.colorScheme, .light)
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Progress for " + agent.name)
    }
}

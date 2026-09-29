import SwiftUI
import DioramaCore

/// Mounted once by WorkspaceShell, including while conventional tools are open.
struct SpatialWorkspaceView: View {
    @Bindable var library: LibraryModel
    var visible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var explore = false
    @State private var attention = false
    @State private var allConversations = false
    @State private var screenAnchor = CGPoint(x: 0.5, y: 0.5)
    @State private var screenActivity = false
    @State private var cachedWorld: SpatialWorld?
    private var state: SpatialWorkspaceState { library.spatial }
    private var world: SpatialWorld { cachedWorld ?? library.spatialWorld(showArchived: state.showArchived) }

    var body: some View {
        let snapshot = world
        let focus = snapshot.resolved(state.focus)
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                SpatialSceneSurface(world: snapshot, focus: focus, active: visible && scenePhase == .active && focus != .portfolio,
                    reducedMotion: reduced, reset: state.resetGeneration, page: state.page, select: go,
                    screenAnchor: { screenAnchor = $0 })
                    .opacity(focus == .portfolio ? 0 : 1)
                    .allowsHitTesting(focus != .portfolio).accessibilityHidden(focus == .portfolio)
                PortfolioHomeView(library: library, projects: snapshot.projects,
                    active: visible && scenePhase == .active && focus == .portfolio, select: go)
                    .opacity(focus == .portfolio ? 1 : 0)
                    .accessibilityElement(children: focus == .portfolio ? .contain : .ignore)
                    .allowsHitTesting(focus == .portfolio).accessibilityHidden(focus != .portfolio)
                if focus != .portfolio && !ScenePerformance.disabled("OVERLAYS") {
                    VStack(alignment: .leading, spacing: 12) {
                        toolbar(snapshot, focus: focus)
                        if let notice = state.notice {
                            HStack { Text(notice); Button("Dismiss") { state.notice = nil } }
                                .font(.caption).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        Spacer()
                        if !focus.expanded { scopeCard(snapshot, focus: focus) }
                        HStack {
                            Text("Click to focus · Drag to orbit · Scroll to frame").font(.caption)
                            Spacer()
                            Text(library.paused ? "Observation paused" : "Live connections · reported state").font(.caption)
                        }.foregroundStyle(.secondary)
                    }.padding(16).environment(\.colorScheme, .light).tint(.blue)
                }
                if visible && focus.expanded, let agent = snapshot.agent(focus), let team = snapshot.team(focus) {
                    workScreen(agent, team: team)
                        .frame(width: geometry.size.width < 850 ? max(280, geometry.size.width - 24) : geometry.size.width * 0.70,
                               height: max(240, geometry.size.height - 88))
                        .background(DioramaStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.3)))
                        .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.top, 58).padding(.trailing, 12).padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: reduced ? 1 : 0.12,
                            anchor: UnitPoint(x: min(1, max(0, screenAnchor.x)), y: min(1, max(0, screenAnchor.y))))))
                }
            }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.18), value: focus == .portfolio)
        .onChange(of: state.showArchived) { _, _ in refreshWorld() }
        .onChange(of: snapshot) { _, new in
            guard !library.isScanning else { return }
            let resolved = new.resolved(state.focus)
            if resolved != state.focus {
                go(resolved)
                state.notice = "The selected item is no longer available in this view. Showing its nearest available parent."
            }
        }
        .task(id: "\(visible)-\(scenePhase == .active)-\(state.focus.conversationID ?? "")") {
            guard visible, scenePhase == .active else { return }
            while !Task.isCancelled {
                library.observationClock = Date()
                refreshWorld()
                if !library.paused, let id = state.focus.conversationID, library.selectedID == id {
                    if let session = library.selected, library.execution.tasks[session.sessionID]?.attached == true {
                        await library.execution.refreshAgents(session)
                    }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    /// Camera/monitor updates may arrive every frame. Project the library once per observation
    /// tick instead of repeating provider and membership lookups during those view updates.
    private func refreshWorld() {
        let next = library.spatialWorld(showArchived: state.showArchived)
        if cachedWorld != next { cachedWorld = next }
    }

    private func toolbar(_ world: SpatialWorld, focus: SpatialFocus) -> some View {
        HStack(spacing: 8) {
            Button { go(focus.officeReturn) } label: { Image(systemName: "chevron.left") }.disabled(focus == .portfolio || !visible).help("Up one layer (Escape)")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Button("Portfolio") { go(.portfolio) }
                    if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(project.name) { go(.project(id)) }
                    }
                    if let team = world.team(focus) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(team.title) { go(team.focus) }.lineLimit(1)
                    }
                    if let agent = world.agent(focus) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(agent.value.name) { go(agent.focus) }.lineLimit(1)
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            let count = world.team(focus)?.agents.count ?? world.projects.first(where: { $0.id == focus.projectID })?.teams.count ?? 0
            let size = focus.conversationID == nil ? 12 : 24
            if focus.projectID == nil && focus.agentID == nil && focus != .portfolio && count > size {
                Button { state.page = max(0, state.page - 1) } label: { Image(systemName: "arrow.left") }.disabled(state.page == 0).help("Previous group")
                Text("\(state.page + 1)/\(max(1, (count + size - 1) / size))").font(.caption.monospacedDigit())
                Button { state.page += 1 } label: { Image(systemName: "arrow.right") }.disabled((state.page + 1) * size >= count).help("Next group")
            }
            Button("Agents", systemImage: "list.bullet") { explore.toggle() }
                .popover(isPresented: $explore) { entityList(world, focus: focus).frame(width: 350, height: 440) }
            if let project = world.projects.first(where: { $0.id == focus.projectID }) {
                Button("All conversations") { allConversations.toggle() }
                    .popover(isPresented: $allConversations) {
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(project.teams) { team in
                                    entityRow(team.title, detail: team.summary.text, icon: "bubble.left", focus: team.focus)
                                }
                            }.padding(8)
                        }.frame(width: 350, height: 440)
                    }
            }
            Button("Attention", systemImage: "bell") { attention.toggle() }
                .popover(isPresented: $attention) { attentionList(world).frame(width: 350, height: 380) }
            Menu {
                Toggle("Show archived conversations", isOn: Binding(get: { state.showArchived }, set: { state.showArchived = $0 }))
                Button("Reset View") { state.resetGeneration += 1 }
                if focus.projectID != nil {
                    Button("Project tools") { openTools(.context) }
                }
                if focus.conversationID != nil {
                    Button("Conversation") { openTools(.conversation) }
                    Button("Activity") { openTools(.activity) }
                    Button("HTML view") { openTools(.html) }
                }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
        }.buttonStyle(.borderless).font(.system(size: 13, weight: .medium))
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func entityList(_ world: SpatialWorld, focus: SpatialFocus) -> some View {
        VStack(alignment: .leading) {
            Text("Explore · " + focus.layer).font(.headline).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let team = world.team(focus) {
                        ForEach(team.agents) { agent in
                            entityRow(agent.value.name, detail: agent.value.statusLabel, icon: "person", focus: OfficeOccupant(agent: agent, assignment: team.title).destination)
                        }
                    } else if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                        let roster = OfficeRoster(teams: project.teams, now: library.observationClock)
                        ForEach(roster.occupants) { occupant in
                            entityRow(occupant.assignment, detail: occupant.agent.value.name + " · " + occupant.agent.value.statusLabel,
                                      icon: "person", focus: occupant.destination)
                        }
                        if roster.occupants.isEmpty { Text("No agents on the floor. Older work is in All conversations.").padding(12) }
                        if project.teams.isEmpty { Text("No conversations in this project.").padding(12) }
                    } else {
                        ForEach(world.projects) { project in entityRow(project.name, detail: project.summary.text, icon: "building.2", focus: .project(project.id)) }
                        if world.projects.isEmpty { Text("Connect a project using the sidebar to populate the campus.").padding(12) }
                    }
                }.padding(8)
            }
        }
    }
    private func entityRow(_ title: String, detail: String, icon: String, focus: SpatialFocus) -> some View {
        Button {
            explore = false; attention = false; allConversations = false; go(focus)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).frame(width: 22)
                VStack(alignment: .leading, spacing: 5) { Text(title).lineLimit(2); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func attentionList(_ world: SpatialWorld) -> some View {
        let agents = world.teams.flatMap(\.agents).filter { (state.focus.projectID == nil || $0.projectID == state.focus.projectID) && ($0.needsAttention || $0.value.status == .failed) }
        return VStack(alignment: .leading) {
            Text("Needs your attention").font(.headline).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(agents) { agent in
                        entityRow(world.team(agent.focus)?.title ?? agent.value.name,
                            detail: agent.value.name + " · " + agent.value.statusLabel,
                            icon: "exclamationmark.bubble", focus: .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                    }
                    if agents.isEmpty { Text("No reported requests. Last-known or unavailable observations may be incomplete.").font(.callout).foregroundStyle(.secondary).padding(12) }
                }
            }
        }
    }
    private func scopeCard(_ world: SpatialWorld, focus: SpatialFocus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focus.layer.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            if let agent = world.agent(focus) {
                Text(agent.value.name).font(.title2.bold())
                Text(agent.value.statusLabel).font(.callout.weight(.medium))
                Text(agent.value.task).font(.callout).lineLimit(3)
                Text(agent.value.action).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Open work screen", systemImage: "desktopcomputer") {
                    go(.agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                }.buttonStyle(.borderedProminent)
            } else if let team = world.team(focus) {
                Text(team.title).font(.title2.bold()).lineLimit(2)
                Text(team.summary.text).font(.callout)
                Text("\(team.agents.count) agents · Select a desk to inspect its assignment").font(.caption).foregroundStyle(.secondary)
                if team.projectID == nil && team.agents.count > 24 { Text("Use Explore to reach every agent; detailed desks load in groups of 24.").font(.caption) }
                Button("Open conversation") { openTools(.conversation) }
            } else if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                Text(project.name).font(.title2.bold())
                Text(project.summary.text).font(.callout)
                Text("\(OfficeRoster(teams: project.teams, now: library.observationClock).occupants.count) agents on the shared floor").font(.caption).foregroundStyle(.secondary)
                Text("Finished turns remain for 30 minutes. Desk proximity does not imply collaboration.").font(.caption).foregroundStyle(.secondary)
                Button("New session", systemImage: "plus") { newSession(id) }
            } else {
                Text("Your project campus").font(.title2.bold())
                Text("\(world.projects.count) connected projects · \(world.projects.flatMap(\.teams).count) teams").font(.callout)
                Text(world.projects.isEmpty ? "Add a project from the sidebar to begin." : "Choose a building to enter its office.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    private func workScreen(_ agent: SpatialAgent, team: SpatialTeam) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "desktopcomputer")
                Text(agent.value.name).fontWeight(.semibold)
                Text(team.session.observationOnly ? "Observation only" : agent.value.freshness.rawValue).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { screenActivity = false; go(agent.focus.projectID.map(SpatialFocus.project) ?? agent.focus) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.help("Return to office")
            }.padding(14)
            Divider()
            if agent.value.isMain {
                if screenActivity {
                    SessionActivityPanel(session: team.session, library: library, state: library.activityState(team.session), close: { screenActivity = false })
                } else {
                    SessionView(session: team.session, model: library, hasLocalReview: true,
                        activityAction: { section in library.activityState(team.session).section = section; screenActivity = true },
                        shellContent: true, embeddedWorkScreen: true)
                }
            } else {
                SpatialChildWorkScreen(library: library, session: team.session, agent: agent.value)
            }
        }.id(agent.id)
    }
    private func go(_ focus: SpatialFocus) {
        state.page = 0
        if focus.projectID != state.focus.projectID || focus.conversationID != state.focus.conversationID {
            let destination: WorkspaceDestination = focus.projectID.map { .project($0, focus.conversationID) }
                ?? focus.conversationID.map { .imported($0) } ?? .home
            library.navigate(destination)
        }
        screenActivity = false
        withAnimation(reduced ? nil : .easeInOut(duration: focus == .portfolio || state.focus == .portfolio ? 0.18 : 0.4)) { state.focus = focus }
    }
    private func openTools(_ tab: WorkspaceTab) {
        if let project = library.projects.selected {
            if tab == .context { library.projects.update(project.id) { $0.section = "Context" } }
            library.navigation.tabs[project.id + ":" + (project.selectedSession ?? "draft")] = tab
        }
        switch tab { case .activity: library.viewMode = .activity; case .html: library.viewMode = .html; default: library.viewMode = .conversation }
    }
    private func newSession(_ projectID: String) {
        library.navigate(.project(projectID, nil))
        library.navigation.tabs[projectID + ":draft"] = .conversation
        library.viewMode = .conversation
    }
}

/// Child content is read with its provider identity; parent execution controls are never shown here.
private struct SpatialChildWorkScreen: View {
    @Bindable var library: LibraryModel
    let session: Session
    let agent: WorkspaceAgent
    @Environment(\.scenePhase) private var phase
    @State private var transcript: Transcript?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(agent.task).font(.headline)
                Text(agent.statusLabel + " · " + agent.action).foregroundStyle(.secondary)
                Text("Observed subagent work · controls remain with the parent conversation").font(.caption)
                if let error { Text(error).foregroundStyle(.orange) }
                if let transcript {
                    ForEach(transcript.entries) { entry in EntryView(entry: entry) }
                    if let error = transcript.error { Text(error).foregroundStyle(.orange) }
                } else if error == nil { ProgressView("Reading agent work…") }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(agent.activityRecordID ?? "")-\(phase == .active)") {
            guard phase == .active else { return }
            guard let record = library.activitySnapshot(session).records.first(where: { $0.id == agent.activityRecordID }) else {
                error = "No detailed activity record is available for this agent."; return
            }
            while !Task.isCancelled {
                if !library.paused {
                    do {
                        let observed = try await library.execution.inspectChild(provider: Provider(rawValue: record.provider) ?? session.provider,
                            parentID: record.sessionID, childID: record.nativeID, folder: session.project)
                        guard !Task.isCancelled else { return }
                        transcript = observed; error = nil
                    } catch { self.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
}

import SwiftUI
import DioramaCore

/// Mounted once by WorkspaceShell, including while conventional tools are open.
struct SpatialWorkspaceView: View {
    @Bindable var library: LibraryModel
    var visible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var panelDrag: Double?
    @State private var rosterDrag: Double?
    @State private var editStatus: String?
    @State private var inspection: AgentInspectionDestination?
    @State private var avatarPopovers = AvatarPopoverDismissals()
    @State private var returnToAgentList = false
    @FocusState private var planFocus: AgentInspectionDestination?
    private var inboxExpanded: Bool { get { state.inboxExpanded } nonmutating set { state.inboxExpanded = newValue } }
    private var serversExpanded: Bool { get { state.serversExpanded } nonmutating set { state.serversExpanded = newValue } }
    private var inboxSelection: InboxThread? { get { state.inboxSelection } nonmutating set { state.inboxSelection = newValue } }
    @State private var creationProject: AgentCreationDestination?
    @State private var reviewing: SpatialAgent?
    /// The kitchen chef whose progress panel is open.
    @State private var progressAgent: String?
    /// The chef whose command bar is shown. Clearing waits a moment, like the kitchen camera, so
    /// switching chefs (which passes through "no agent" while the conversation changes) keeps it up.
    @State private var commandBarAgent: String?
    /// The pantry card (skills, plugins, MCP) floating under the agents card.
    @State private var pantryOpen = false
    /// The kitchen camera left its home view (zoomed or turned), and a request to send it back.
    @State private var kitchenCameraAway = false
    @State private var kitchenCameraResets = 0
    @State private var explore = false
    @State private var attention = false
    @State private var allConversations = false
    @State private var screenAnchor = CGPoint(x: 0.5, y: 0.5)
    @State private var screenActivity = false
    @State private var cachedWorld: SpatialWorld?
    @State private var cachedProject: String?
    @State private var projectWorlds: [String: SpatialWorld] = [:]
    @State private var projectRecency: [String] = []
    private var kitchenSelected: Bool { state.sceneKind == .kitchen }
    /// Agent state keeps refreshing while the window is active, and also in the kitchen whenever
    /// it is on screen, so chefs keep working while you use another app beside it.
    private var liveRefresh: Bool { (scenePhase == .active && library.windowIsActive) || kitchenSelected }
    private var state: SpatialWorkspaceState { library.spatial }
    private var world: SpatialWorld {
        if !visible { return cachedWorld ?? SpatialWorld() }
        if cachedProject == state.focus.projectID, let cachedWorld { return cachedWorld }
        if let id = state.focus.projectID {
            return projectWorlds[id] ?? SpatialWorld(projects: library.projects.projects.map { SpatialProject(id: $0.id, name: $0.name, teams: []) })
        }
        return cachedWorld ?? SpatialWorld()
    }

    var body: some View {
        let snapshot = world
        let focus = snapshot.resolved(state.focus)
        let roster = state.roster(for: focus.projectID ?? focus.conversationID ?? "portfolio")
        GeometryReader { geometry in
            let officeWidth = geometry.size.width - (state.conversationPanelVisible ? resolvedPanelWidth(available: geometry.size.width) : 0)
            let narrow = officeWidth < 760
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                if visible, focus != .portfolio, !roster.collapsed, !narrow, !kitchenSelected {
                    rosterPanel(snapshot, focus: focus, model: roster, narrow: false).frame(width: library.navigation.layout.sidebarWidth)
                        .disabled(inspection != nil).accessibilityHidden(inspection != nil)
                    Rectangle().fill(DioramaStyle.border).frame(width: 1).overlay {
                        Color.clear.frame(width: 7).contentShape(Rectangle()).gesture(DragGesture().onChanged { value in
                            if rosterDrag == nil { rosterDrag = library.navigation.layout.sidebarWidth }
                            library.navigation.layout.sidebarWidth = min(360, max(190, (rosterDrag ?? 240) + value.translation.width))
                        }.onEnded { _ in rosterDrag = nil })
                    }.accessibilityLabel("Resize agent panel")
                }
                ZStack(alignment: .topLeading) {
                SpatialSceneSurface(world: snapshot, focus: focus, active: !kitchenSelected && visible && (scenePhase == .active && library.windowIsActive) && focus != .portfolio,
                    reducedMotion: reduced, reset: state.resetGeneration, page: state.page, select: go,
                    screenAnchor: { screenAnchor = $0 }, openInspection: { showPlan($0) },
                    dismissPlan: inspection == nil ? nil : { closePlan() }, editStatus: { editStatus = $0 }, cameraStore: library.navigation.projectTabs, presented: !kitchenSelected)
                    .opacity(focus == .portfolio || kitchenSelected ? 0 : 1)
                    .allowsHitTesting(!kitchenSelected && focus != .portfolio && inspection == nil).accessibilityHidden(kitchenSelected || focus == .portfolio || inspection != nil)
                if kitchenSelected {
                    let cooks = kitchenAgents(snapshot, focus: focus)
                    let _ = KitchenReviews.shared.observe(cooks)
                    VStack(spacing: 0) {
                        KitchenSceneSurface(agents: cooks, scope: focus == .portfolio ? nil : focus.projectID ?? focus.conversationID,
                                            reviews: KitchenReviews.shared.states, active: visible,
                                            reducedMotion: reduced, select: go, review: { reviewing = $0 }, progress: { progressAgent = $0.id },
                                            selectedAgentID: focus.agentID, deselect: { deselectAgent(focus) }, openPantry: { pantryOpen = true },
                                            cameraMoved: { away in DispatchQueue.main.async { kitchenCameraAway = away } }, resetCamera: kitchenCameraResets)
                            .overlay(alignment: .bottomLeading) {
                                if visible, focus.agentID == nil {
                                    HStack(spacing: 10) {
                                        if kitchenCameraAway {
                                            Button("Reset View") { kitchenCameraResets += 1 }.controlSize(.small).pointingHand().help("Back to the whole kitchen (R)")
                                        }
                                        Text(KitchenSceneView.controlsHint).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(.regularMaterial)).padding(12)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if visible, focus != .portfolio {
                                    GeometryReader { scene in kitchenHUD(snapshot, focus: focus, model: roster, height: scene.size.height - 24) }
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                // Inbox and live servers, docked top right above the kitchen.
                                if visible, let project = focus.projectID, inspection == nil {
                                    GeometryReader { scene in
                                        HStack {
                                            Spacer(minLength: 0)
                                            ProjectOfficeInbox(library: library, project: project, height: max(120, scene.size.height * 0.55),
                                                active: liveRefresh && !library.paused,
                                                inboxExpanded: Binding(get: { inboxExpanded }, set: { inboxExpanded = $0 }), serversExpanded: Binding(get: { serversExpanded }, set: { serversExpanded = $0 }), selected: Binding(get: { inboxSelection }, set: { inboxSelection = $0 }),
                                                reply: { thread in openInboxConversation(thread, world: snapshot) },
                                                canReply: { thread in snapshot.teams.first { $0.session.id == thread.conversation }?.session.observationOnly == false })
                                                .id(project)
                                                .frame(width: max(100, min(400, scene.size.width - library.navigation.layout.sidebarWidth - 48)))
                                        }.padding(12)
                                    }
                                }
                            }
                        // The selected chef's command bar sits under the kitchen, down to the window's edge.
                        if let selected = cooks.first(where: { $0.id == (focus.agentID ?? commandBarAgent) }) {
                            AgentCommandBar(agent: selected, library: library, review: { reviewing = selected }) { deselectAgent(focus) }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(reduced ? nil : .easeOut(duration: 0.22), value: commandBarAgent)
                    .task(id: focus.agentID) {
                        if let id = focus.agentID { commandBarAgent = id; return }
                        do { try await Task.sleep(for: .seconds(KitchenSceneView.deselectGrace)) } catch { return }
                        commandBarAgent = nil
                    }
                }
                if !kitchenSelected && focus != .portfolio && !ScenePerformance.disabled("OVERLAYS") {
                    VStack(alignment: .leading, spacing: 12) {
                        toolbar(snapshot, focus: focus)
                        if let notice = state.notice {
                            HStack { Text(notice); Button("Dismiss") { state.notice = nil }.pointingHand() }
                                .font(.caption).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        Spacer()
                        if editStatus == nil && !focus.expanded && !inboxExpanded && !serversExpanded { scopeCard(snapshot, focus: focus).padding(.bottom, 46) }
                        HStack {
                            Text(editStatus ?? "Click to focus · Drag to orbit · Scroll to frame · E to edit furniture").font(.caption)
                            Spacer()
                            if editStatus == nil { Text(library.paused ? "Observation paused" : "Live connections · reported state").font(.caption) }
                        }.foregroundStyle(.secondary)
                    }.padding(16).environment(\.colorScheme, .light).tint(.blue)
                        .disabled(inspection != nil).accessibilityHidden(inspection != nil)
                }
                if !kitchenSelected, visible, focus != .portfolio, let project = focus.projectID, inspection == nil {
                    GeometryReader { office in
                        VStack {
                            Spacer()
                            HStack {
                                Spacer(minLength: 0)
                                ProjectOfficeInbox(library: library, project: project, height: max(120, office.size.height * 0.6),
                                    active: (scenePhase == .active && library.windowIsActive) && !library.paused,
                                    inboxExpanded: Binding(get: { inboxExpanded }, set: { inboxExpanded = $0 }), serversExpanded: Binding(get: { serversExpanded }, set: { serversExpanded = $0 }), selected: Binding(get: { inboxSelection }, set: { inboxSelection = $0 }),
                                    reply: { thread in openInboxConversation(thread, world: snapshot) },
                                    canReply: { thread in snapshot.teams.first { $0.session.id == thread.conversation }?.session.observationOnly == false })
                                    .id(project)
                                    .frame(width: max(100, min(400, office.size.width - 32)))
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 40)
                    }
                }
                if visible, focus != .portfolio, !roster.collapsed, narrow, inspection == nil, !kitchenSelected {
                    rosterPanel(snapshot, focus: focus, model: roster, narrow: true)
                        .frame(width: max(180, min(300, officeWidth - 32)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.1)))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(.top, 76).padding(.bottom, 16).padding(.leading, 16)
                }
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).clipped()
                if visible && state.conversationPanelVisible {
                    Rectangle().fill(.black.opacity(0.12)).frame(width: 1).overlay {
                        Color.clear.frame(width: 7).contentShape(Rectangle()).gesture(DragGesture().onChanged { value in
                            if panelDrag == nil { panelDrag = resolvedPanelWidth(available: geometry.size.width) }
                            state.conversationWidth = min(700, max(340, (panelDrag ?? 500) - value.translation.width))
                        }.onEnded { _ in panelDrag = nil })
                    }.accessibilityLabel("Resize conversation panel")
                    conversationPanel(snapshot, focus: focus)
                        .frame(width: resolvedPanelWidth(available: geometry.size.width))
                        .frame(maxHeight: .infinity)
                        .background(Color.white)
                        .environment(\.colorScheme, .light).environment(\.avatarMessages, true).tint(.blue)
                        .disabled(inspection != nil).accessibilityHidden(inspection != nil)
                }
                }
                if visible, let id = progressAgent, let agent = snapshot.teams.flatMap(\.agents).first(where: { $0.id == id }) {
                    ZStack {
                        Color.black.opacity(0.12).contentShape(Rectangle()).onTapGesture { progressAgent = nil }
                        AgentProgressModal(agent: agent.value) { progressAgent = nil }
                            .frame(width: min(460, max(180, geometry.size.width - 32)), height: max(180, geometry.size.height * 0.7))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if visible, let selection = inspection, let agent = snapshot.teams.flatMap(\.agents).first(where: { $0.id == selection.agentID }) {
                    ZStack {
                        Color.black.opacity(0.12).contentShape(Rectangle()).onTapGesture { closePlan() }
                        AgentPlanModal(agent: agent.value, kind: selection.kind, paused: library.paused, close: closePlan).id(selection)
                            .frame(width: min(440, max(180, geometry.size.width - 32)), height: max(160, geometry.size.height * 0.7))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: state.conversationPanelVisible) { _, shown in
                if shown && narrow { roster.collapsed = true }
            }
        }
        .sheet(item: $creationProject) { destination in
            NewAgentModal(library: library, projectID: destination.id)
        }
        .sheet(item: $reviewing) { agent in
            if let session = world.team(.team(project: agent.projectID, conversation: agent.conversationID))?.session {
                ServingWindowView(agent: agent, session: session, library: library)
            }
        }
        .environment(\.avatarPopoverDismissals, avatarPopovers)
        // Let native menus and popovers consume Escape before spatial navigation.
        .onExitCommand {
            guard visible else { return }
            if avatarPopovers.dismissTop() { return }
            // A selected chef is let go first, closing its conversation and command bar.
            if kitchenSelected, state.focus.agentID != nil, inspection == nil { deselectAgent(state.focus); return }
            if inspection != nil { closePlan() }
            else if serversExpanded { serversExpanded = false }
            else if inboxExpanded && inboxSelection != nil { inboxSelection = nil }
            else if inboxExpanded { inboxExpanded = false }
            else if state.conversationPanelVisible { state.conversationPanelVisible = false }
            else if !roster.collapsed && focus != .portfolio { roster.collapsed = true }
            else if focus != .portfolio { go(focus.officeReturn) }
        }
        .onChange(of: state.focus) { _, new in
            inspection = nil
            if new.expanded { state.conversationPanelVisible = true }
        }
        .onChange(of: visible) { _, new in if !new { inspection = nil } }
        .task(id: "projection-\(visible)-\(state.focus.projectID ?? "")") {
            guard visible, state.focus != .portfolio else { return }
            // Cached presentation paints before fresh observation data is reconciled.
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            refreshWorld()
        }
        .onChange(of: state.showArchived) { _, _ in refreshWorld() }
        .onChange(of: snapshot) { _, new in
            guard visible, cachedProject == state.focus.projectID, !library.isScanning, library.scannedAt != nil else { return }
            if let selection = inspection, !new.teams.flatMap(\.agents).contains(where: { $0.id == selection.agentID }) { inspection = nil }
            let resolved = new.resolved(state.focus)
            if resolved != state.focus {
                go(resolved)
                state.notice = "The selected item is no longer available in this view. Showing its nearest available parent."
            }
        }
        .task(id: "plans-\(visible)-\(liveRefresh)-\(library.paused)-\(state.focus)-\(inspection?.nodeName ?? "")") {
            guard visible, liveRefresh, !library.paused, state.focus != .portfolio else { return }
            while !Task.isCancelled {
                let current = world
                var teams = current.teams.filter { state.focus.projectID != nil ? $0.projectID == state.focus.projectID : $0.session.id == state.focus.conversationID }
                if state.focus.projectID != nil {
                    let roster = OfficeRoster(teams: teams, now: library.observationClock, including: state.focus.agentID, conversation: state.focus.conversationID)
                    let visibleConversations = Set(roster.occupants.map { $0.agent.conversationID })
                    teams = teams.filter { visibleConversations.contains($0.session.id) }
                }
                let prioritized = teams.sorted { $0.agents.contains { $0.id == inspection?.agentID } && !$1.agents.contains { $0.id == inspection?.agentID } }
                await library.planDiscovery.refresh(prioritized.flatMap { library.planSources($0.session) })
                guard !Task.isCancelled else { return }
                refreshWorld()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .task(id: "\(visible)-\(liveRefresh)-\(state.focus.conversationID ?? "")") {
            guard visible, liveRefresh else { return }
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

    private func rosterPanel(_ snapshot: SpatialWorld, focus: SpatialFocus, model: LiveAgentRosterModel, narrow: Bool, floating: Bool = false) -> some View {
        let teams = focus.projectID.flatMap { id in snapshot.projects.first { $0.id == id }?.teams } ?? snapshot.team(focus).map { [$0] } ?? []
        return LiveAgentRosterPanel(model: model, agents: teams.flatMap(\.agents),
            // The roster sits beside both the office and the kitchen, so it stays live in either scene.
            active: visible && liveRefresh && inspection == nil, paused: library.paused,
            open: { destination in
                if narrow { model.collapsed = true }
                go(destination)
            }, archive: { row in
                if let session = library.sessions.first(where: { $0.id == row.agent.conversationID }), session.classification != .internalReview {
                    library.archiveSession = session
                }
            }, create: {
                creationProject = AgentCreationDestination(id: focus.projectID ?? "")
            }, floating: floating, collapse: floating ? { model.collapsed = true } : nil)
    }
    /// The kitchen's floating HUD, top left: the agents card (or its working/blocked summary when
    /// collapsed) and, below it, the pantry.
    private func kitchenHUD(_ snapshot: SpatialWorld, focus: SpatialFocus, model: LiveAgentRosterModel, height: CGFloat) -> some View {
        let teams = focus.projectID.flatMap { id in snapshot.projects.first { $0.id == id }?.teams } ?? snapshot.team(focus).map { [$0] } ?? []
        let width = library.navigation.layout.sidebarWidth
        let project = focus.projectID.flatMap { id in library.projects.projects.first { $0.id == id } }
        var sessions: [Provider: String] = [:]
        for team in teams where sessions[team.session.provider] == nil { sessions[team.session.provider] = team.session.sessionID }
        let selected = focus.agentID.flatMap { id in teams.flatMap(\.agents).first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 10) {
            if model.collapsed {
                KitchenAgentSummary(agents: teams.flatMap(\.agents), expand: { model.collapsed = false }, openPantry: { pantryOpen = true })
            } else {
                rosterPanel(snapshot, focus: focus, model: model, narrow: false, floating: true)
                    .frame(width: width, height: max(160, height * (pantryOpen ? 0.45 : 0.62)))
                    .floatingCard()
            }
            if pantryOpen, let folder = project?.folder ?? teams.first?.session.project {
                PantryCard(library: library, folder: folder, sessions: sessions, preferred: teams.first?.session.provider ?? .codex,
                           armFor: selected.map { ($0.conversationID, $0.value.name) }) { pantryOpen = false }
                    .frame(width: width, height: max(200, height * (model.collapsed ? 0.6 : 0.42)))
            }
        }
        .padding(12)
        .disabled(inspection != nil).accessibilityHidden(inspection != nil)
    }

    /// Camera/monitor updates may arrive every frame. Project the library once per observation
    /// tick instead of repeating provider and membership lookups during those view updates.
    private func refreshWorld() {
        guard visible, state.focus != .portfolio else { return }
        let next = library.spatialWorld(showArchived: state.showArchived, projectScope: state.focus.projectID)
        cachedProject = state.focus.projectID
        if let id = cachedProject {
            projectWorlds[id] = next
            projectRecency.removeAll { $0 == id }; projectRecency.append(id)
            while projectRecency.count > 24 { projectWorlds.removeValue(forKey: projectRecency.removeFirst()) }
        }
        if cachedWorld != next { cachedWorld = next }
    }

    private func toolbar(_ world: SpatialWorld, focus: SpatialFocus) -> some View {
        HStack(spacing: 8) {
            Button { go(focus.officeReturn) } label: { Image(systemName: "chevron.left") }.pointingHand().disabled(focus == .portfolio || !visible).help("Up one layer (Escape)")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Button("Portfolio") { go(.portfolio) }.pointingHand()
                    if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(project.name) { go(.project(id)) }.pointingHand()
                    }
                    if let team = world.team(focus) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(team.title) { go(team.focus) }.pointingHand().lineLimit(1).help(TaskTitle.full(team.session.title)).accessibilityLabel(TaskTitle.full(team.session.title))
                    }
                    if let agent = world.agent(focus) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Button(agent.value.name) { go(agent.focus) }.pointingHand().lineLimit(1)
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            let count = world.team(focus)?.agents.count ?? world.projects.first(where: { $0.id == focus.projectID })?.teams.count ?? 0
            let size = focus.conversationID == nil ? 12 : 24
            if focus.projectID == nil && focus.agentID == nil && focus != .portfolio && count > size {
                Button { state.page = max(0, state.page - 1) } label: { Image(systemName: "arrow.left") }.pointingHand().disabled(state.page == 0).help("Previous group")
                Text("\(state.page + 1)/\(max(1, (count + size - 1) / size))").font(.caption.monospacedDigit())
                Button { state.page += 1 } label: { Image(systemName: "arrow.right") }.pointingHand().disabled((state.page + 1) * size >= count).help("Next group")
            }
            Button("Agents", systemImage: "person.2") {
                state.roster(for: focus.projectID ?? focus.conversationID ?? "portfolio").collapsed.toggle()
            }.pointingHand().help("Show or hide live agent panel")
            Button("Explore", systemImage: "list.bullet") { explore.toggle() }.pointingHand()
                .popover(isPresented: $explore) { entityList(world, focus: focus).frame(width: 350, height: 440) }
            if let project = world.projects.first(where: { $0.id == focus.projectID }) {
                Button("All conversations") { allConversations.toggle() }.pointingHand()
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
            Button("Attention", systemImage: "bell") { attention.toggle() }.pointingHand()
                .popover(isPresented: $attention) { attentionList(world).frame(width: 350, height: 380) }
            Menu {
                Toggle("Show archived conversations", isOn: Binding(get: { state.showArchived }, set: { state.showArchived = $0 })).pointingHand()
                Button("Reset View") { state.resetGeneration += 1 }.pointingHand()
                if focus.projectID != nil {
                    Button("Project tools") { openTools(.context) }.pointingHand()
                }
                if focus.conversationID != nil {
                    Button("Conversation") { openTools(.conversation) }.pointingHand()
                    Button("Activity") { openTools(.activity) }.pointingHand()
                    Button("HTML view") { openTools(.html) }.pointingHand()
                }
            } label: { Image(systemName: "ellipsis.circle") }.pointingHand().menuStyle(.borderlessButton).fixedSize()
        }.buttonStyle(.borderless).font(.system(size: 13, weight: .medium)).lineLimit(1)
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func entityList(_ world: SpatialWorld, focus: SpatialFocus) -> some View {
        VStack(alignment: .leading) {
            Text("Explore · " + focus.layer).font(.headline).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let team = world.team(focus) {
                        ForEach(team.agents) { agent in
                            agentRow(agent, title: agent.value.name, destination: OfficeOccupant(agent: agent, assignment: team.title).destination)
                        }
                    } else if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                        let roster = OfficeRoster(teams: project.teams, now: library.observationClock)
                        ForEach(roster.occupants) { occupant in
                            agentRow(occupant.agent, title: occupant.assignment, destination: occupant.destination)
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
    private func showPlan(_ id: AgentInspectionDestination, fromList: Bool = false) {
        returnToAgentList = fromList; explore = false; inspection = id
    }
    private func closePlan() {
        let id = inspection; inspection = nil
        if returnToAgentList {
            explore = true
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                planFocus = id
            }
        }
    }
    private func agentRow(_ agent: SpatialAgent, title: String, destination: SpatialFocus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            entityRow(title, detail: agent.value.statusLabel, icon: "person", focus: destination)
            HStack {
                ForEach(AgentInspectionKind.allCases, id: \.self) { kind in
                    if kind.available(in: agent.value.plan) {
                        let selection = AgentInspectionDestination(agentID: agent.id, kind: kind)
                        Button(kind.label(for: agent.value.plan)) { showPlan(selection, fromList: true) }.pointingHand()
                            .focusable().focused($planFocus, equals: selection)
                            .onKeyPress(.space) { showPlan(selection, fromList: true); return .handled }
                            .onKeyPress(.return) { showPlan(selection, fromList: true); return .handled }
                            .accessibilityLabel(kind.label(for: agent.value.plan) + " for " + agent.value.name)
                    }
                }
            }.padding(.leading, 42)
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
        }.pointingHand().buttonStyle(.plain)
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
                Text(TaskTitle.compact(agent.value.task)).help(TaskTitle.full(agent.value.task)).accessibilityLabel(TaskTitle.full(agent.value.task)).font(.callout).lineLimit(3)
                Text(agent.value.action).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Open work screen", systemImage: "desktopcomputer") {
                    go(.agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                }.pointingHand().buttonStyle(.borderedProminent)
            } else if let team = world.team(focus) {
                Text(team.title).help(TaskTitle.full(team.session.title)).accessibilityLabel(TaskTitle.full(team.session.title)).font(.title2.bold()).lineLimit(2)
                Text(team.summary.text).font(.callout)
                Text("\(team.agents.count) agents · Select a desk to inspect its assignment").font(.caption).foregroundStyle(.secondary)
                if team.projectID == nil && team.agents.count > 24 { Text("Use Explore to reach every agent; detailed desks load in groups of 24.").font(.caption) }
                Button("Open conversation") { openTools(.conversation) }.pointingHand()
            } else if let id = focus.projectID, let project = world.projects.first(where: { $0.id == id }) {
                Text(project.name).font(.title2.bold())
                Text(project.summary.text).font(.callout)
                Text("\(OfficeRoster(teams: project.teams, now: library.observationClock).occupants.count) agents on the shared floor").font(.caption).foregroundStyle(.secondary)
                Text("Up to 16 desk agents and 18 leisure agents are shown. All agents remain available in the agent panel.").font(.caption).foregroundStyle(.secondary)
                Button("New session", systemImage: "plus") { newSession(id) }.pointingHand()
            } else {
                Text("Your project campus").font(.title2.bold())
                Text("\(world.projects.count) connected projects · \(world.projects.flatMap(\.teams).count) teams").font(.callout)
                Text(world.projects.isEmpty ? "Add a project from the sidebar to begin." : "Choose a building to enter its office.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    private func resolvedPanelWidth(available: CGFloat) -> CGFloat {
        min(available, state.conversationWidth.map { min(max(340, $0), max(340, available - 260)) } ?? Self.conversationPanelWidth(available: available))
    }
    static func conversationPanelWidth(available: CGFloat) -> CGFloat {
        min(max(0, available), min(600, max(340, available * 0.46)))
    }
    @ViewBuilder private func conversationPanel(_ snapshot: SpatialWorld, focus: SpatialFocus) -> some View {
        if let team = snapshot.team(focus), let agent = snapshot.agent(focus) ?? team.agents.first(where: { $0.value.isMain }) {
            workScreen(agent, team: team)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Conversation").font(.headline)
                    Spacer()
                    Button { state.conversationPanelVisible = false } label: { Image(systemName: "xmark") }.pointingHand()
                        .buttonStyle(.plain).accessibilityLabel("Close conversation")
                }.padding(20)
                Divider()
                ContentUnavailableView("Select an agent", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Click an avatar to open its conversation here."))
                    .frame(maxHeight: .infinity)
            }
        }
    }
    private func workScreen(_ agent: SpatialAgent, team: SpatialTeam) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.value.name).font(.headline).foregroundStyle(.primary)
                    Text(agent.value.isMain ? team.title : TaskTitle.compact(agent.value.task))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        .help(TaskTitle.full(agent.value.isMain ? team.session.title : agent.value.task))
                        .accessibilityLabel(TaskTitle.full(agent.value.isMain ? team.session.title : agent.value.task))
                    let workspaces = library.projects.projects.first(where: { $0.id == team.projectID })?.workspaces ?? []
                    Label(AvatarMessagePresentation.branch(session: team.session, workspaces: workspaces), systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button { screenActivity = false; state.conversationPanelVisible = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.06), in: Circle())
                }.pointingHand().buttonStyle(.plain).help("Close conversation").accessibilityLabel("Close conversation")
            }.padding(.horizontal, 20).padding(.vertical, 12).background(Color(white: 0.97))
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
    private func openInboxConversation(_ thread: InboxThread, world: SpatialWorld) {
        let available = library.spatialWorld(showArchived: true)
        guard let team = available.teams.first(where: { $0.session.id == thread.conversation }),
              let agent = team.agents.first(where: { $0.value.isMain }) else {
            state.notice = "The originating conversation is not currently available."; return
        }
        if team.session.archived { state.showArchived = true }
        go(.agent(project: team.projectID, conversation: team.session.id, agent: agent.id, expanded: true))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ComposerNSTextView.focusVisible() }
    }
    /// The focused project's agents (or the focused standalone conversation's); none at portfolio.
    private func kitchenAgents(_ world: SpatialWorld, focus: SpatialFocus) -> [SpatialAgent] {
        guard focus != .portfolio else { return [] }
        if let project = focus.projectID { return world.projects.first { $0.id == project }?.teams.flatMap(\.agents) ?? [] }
        return world.team(focus)?.agents ?? []
    }
    /// Back to the whole kitchen: the camera returns to the overview and the command bar closes.
    private func deselectAgent(_ focus: SpatialFocus) {
        go(focus.projectID.map { .project($0) } ?? focus.officeReturn)
        // Letting go of a chef closes its conversation along with the command bar.
        state.conversationPanelVisible = false
    }
    private func go(_ focus: SpatialFocus) {
        if focus.expanded { state.conversationPanelVisible = true }
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
    @State private var loadedCompletionKey: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(agent.task).font(.headline)
                Text(agent.statusLabel + " · " + agent.action).foregroundStyle(.secondary)
                Text("Observed subagent work · controls remain with the parent conversation").font(.caption)
                if let error { Text(error).foregroundStyle(.orange) }
                if let transcript {
                    let finalEntry = transcript.entries.last { $0.kind == "Assistant" || ConversationHistory.needsAttention($0) || $0.image != nil || !($0.tool?.outputs.isEmpty ?? true) }?.id
                    ForEach(Array(transcript.entries.enumerated()), id: \.element.id) { index, entry in
                        if let date = AvatarMessagePresentation.separator(before: index, entries: transcript.entries) {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        EntryView(entry: entry).environment(\.avatarBubbleTail, AvatarMessagePresentation.tail(after: index, entries: transcript.entries))
                            .background(AgentCompletionVisibility(key: entry.id == finalEntry && [.done, .failed, .stopped].contains(agent.status) ? loadedCompletionKey : nil, active: library.windowIsActive))
                    }
                    if let error = transcript.error { Text(error).foregroundStyle(.orange) }
                } else if error == nil { ProgressView("Reading agent work…") }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(agent.activityRecordID ?? "")-\(agent.completionKey ?? "")-\(phase == .active)") {
            guard phase == .active else { return }
            loadedCompletionKey = nil
            guard let record = library.activitySnapshot(session).records.first(where: { $0.id == agent.activityRecordID }) else {
                error = "No detailed activity record is available for this agent."; return
            }
            while !Task.isCancelled {
                if !library.paused {
                    do {
                        let observed = try await library.execution.inspectChild(provider: Provider(rawValue: record.provider) ?? session.provider,
                            parentID: record.sessionID, childID: record.nativeID, folder: session.project)
                        guard !Task.isCancelled else { return }
                        transcript = observed; loadedCompletionKey = agent.completionKey; error = nil
                    } catch { self.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
}

private struct AgentCreationDestination: Identifiable { let id: String }

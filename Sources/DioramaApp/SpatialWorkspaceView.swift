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
    /// The conversation whose pending request is open in the Review request modal.
    @State private var requestReview: SpatialAgent?
    /// The kitchen chef whose progress panel is open.
    @State private var progressAgent: String?
    /// The chef whose command bar is shown. Clearing waits a moment, like the kitchen camera, so
    /// switching chefs (which passes through "no agent" while the conversation changes) keeps it up.
    @State private var commandBarAgent: String?
    /// The pantry card (skills, plugins, MCP) floating under the agents card.
    @State private var pantryOpen = false
    /// The group to show when the agent card opens from a count on the collapsed pill.
    @State private var sidebarReveal: AgentSidebarGroup?
    /// The docked agents panel's width in the kitchen (drag its right edge).
    @AppStorage("kitchenAgentsWidth") private var kitchenAgentsWidth: Double = 300
    @State private var kitchenAgentsDrag: Double?
    /// Every MCP server, app, plugin and skill, opened from the live tools bar.
    @State private var allToolsOpen = false
    /// What the project's agents can use, for the bar's counts and the All palette.
    @State private var toolInventory = ToolInventory()
    /// The kitchen camera left its home view (zoomed or turned), and a request to send it back.
    @State private var kitchenCameraAway = false
    @State private var kitchenCameraResets = 0
    /// A chef held by the pointer: the kitchen's overlays give way to the trash can.
    @State private var kitchenHold: KitchenHold?
    @State private var trashFrame: CGRect = .zero
    /// "Archived Lena · Undo" after a chef went in the trash (or why it couldn't be archived).
    @State private var kitchenBanner: (id: UUID, text: String, undo: (() -> Void)?)?
    /// Chef foley in the kitchen (`KitchenAudio`).
    @AppStorage(KitchenAudio.enabledKey) private var kitchenSounds = true
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
                    kitchenStage(snapshot, focus: focus, roster: roster)
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
                // The agents at their largest: the task board over the middle of the window.
                if visible, kitchenSelected, focus != .portfolio, !roster.collapsed, roster.board, inspection == nil {
                    ZStack {
                        Color(red: 0.08, green: 0.05, blue: 0.04).opacity(0.42).contentShape(Rectangle())
                            .onTapGesture { setBoard(false, roster) }
                            .accessibilityHidden(true)
                        agentBoard(snapshot, focus: focus, model: roster)
                            .frame(width: min(1240, max(320, geometry.size.width - 64)), height: min(780, max(300, geometry.size.height - 64)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
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
        .sheet(item: $requestReview) { agent in
            if let session = world.team(.team(project: agent.projectID, conversation: agent.conversationID))?.session {
                RequestReviewModal(agent: agent, session: session, library: library) { go(conversationFocus(agent)) }
            }
        }
        .environment(\.avatarPopoverDismissals, avatarPopovers)
        // ⇧⌘K: every tool the agents can use.
        .background {
            Button("All tools") { if visible, kitchenSelected, state.focus != .portfolio { allToolsOpen.toggle() } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        // ⇧⌘B: the task board, from the panel or the pill, and back to the panel.
        .background {
            Button("Task board") {
                guard visible, kitchenSelected, state.focus != .portfolio else { return }
                let roster = state.roster(for: state.focus.projectID ?? state.focus.conversationID ?? "portfolio")
                if roster.collapsed { roster.collapsed = false; setBoard(true, roster) } else { setBoard(!roster.board, roster) }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        // Let native menus and popovers consume Escape before spatial navigation.
        .onExitCommand {
            guard visible else { return }
            if avatarPopovers.dismissTop() { return }
            // The task board steps back down to the side panel first.
            if kitchenSelected, !roster.collapsed, roster.board { setBoard(false, roster); return }
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
    /// The kitchen with its overlays, and the selected chef's command bar beneath it.
    @ViewBuilder private func kitchenStage(_ snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel) -> some View {
        let cooks = kitchenAgents(snapshot, focus: focus)
        let _ = KitchenReviews.shared.observe(cooks)
        HStack(spacing: 0) {
            // The agents panel docks full height at the kitchen's left; collapsed, it's the pill
            // floating in the kitchen's top left (kitchenHUD).
            if visible, focus != .portfolio, !roster.collapsed, !roster.board {
                dockedAgents(snapshot, focus: focus, model: roster)
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                    // Faded out, its space shows the kitchen's backdrop rather than the window behind.
                    .background(Color(nsColor: KitchenSceneView.backdrop))
                    .transition(reduced ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }
            VStack(spacing: 0) {
                kitchenScene(snapshot, focus: focus, roster: roster, cooks: cooks)
                // The selected chef's command bar sits under the kitchen, down to the window's edge.
                if let selected = cooks.first(where: { $0.id == (focus.agentID ?? commandBarAgent) }) {
                    AgentCommandBar(agent: selected, library: library, review: { reviewing = selected }, requestReview: { openRequest(selected) }) { deselectAgent(focus) }
                        .holdHidden(kitchenHold != nil, reduced: reduced)
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
    }

    /// The kitchen scene and everything floating over it: camera reset, sound, agents, live
    /// tools, inbox, trash can and the undo banner.
    private func kitchenScene(_ snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel, cooks: [SpatialAgent]) -> some View {
        KitchenSceneSurface(agents: cooks, scope: focus == .portfolio ? nil : focus.projectID ?? focus.conversationID,
                            reviews: KitchenReviews.shared.states, active: visible,
                            reducedMotion: reduced, select: go, review: { reviewing = $0 }, requestReview: { openRequest($0) }, progress: { progressAgent = $0.id },
                            selectedAgentID: focus.agentID, deselect: { deselectAgent(focus) }, openPantry: { pantryOpen = true },
                            cameraMoved: { away in DispatchQueue.main.async { kitchenCameraAway = away } }, resetCamera: kitchenCameraResets,
                            holding: { hold in DispatchQueue.main.async { kitchenHold = hold } },
                            archiveBlocker: { library.archiveBlocker($0) }, archive: { archiveFromKitchen($0) }, trashFrame: trashFrame)
            .overlay(alignment: .bottomLeading) {
                // Only once the camera has moved; the controls stay in the kitchen's accessibility help.
                if visible, focus.agentID == nil, kitchenCameraAway {
                    Button("Reset View") { kitchenCameraResets += 1 }.controlSize(.small).pointingHand().help("Back to the whole kitchen (R)")
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial)).padding(12)
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    Button { kitchenSounds.toggle() } label: {
                        Image(systemName: kitchenSounds ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).background(Circle().fill(.regularMaterial)).padding(12)
                    .pointingHand().help(kitchenSounds ? "Mute kitchen sounds" : "Play kitchen sounds")
                    .accessibilityLabel(kitchenSounds ? "Mute kitchen sounds" : "Play kitchen sounds")
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            .overlay(alignment: .topLeading) {
                if visible, focus != .portfolio {
                    GeometryReader { scene in kitchenHUD(snapshot, focus: focus, model: roster, height: scene.size.height - 24) }
                        .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            .overlay(alignment: .top) {
                // What the chefs are reaching for, live, between the agents and the inbox.
                if visible, focus != .portfolio, inspection == nil {
                    GeometryReader { scene in
                        liveTools(snapshot, focus: focus, cooks: cooks, width: scene.size.width, height: scene.size.height)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
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
                                canReply: { thread in snapshot.teams.first { $0.session.id == thread.conversation }?.session.observationOnly == false }, dockedTop: true)
                                .id(project)
                                .frame(width: max(100, min(400, scene.size.width - library.navigation.layout.sidebarWidth - 48)))
                        }.padding(12)
                    }
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            .overlay(alignment: .topTrailing) {
                // Held chefs can be thrown away here.
                if visible, let hold = kitchenHold {
                    KitchenTrashCan(hold: hold)
                        .background(GeometryReader { can in
                            Color.clear
                                .onAppear { trashFrame = can.frame(in: .global) }
                                .onChange(of: can.frame(in: .global)) { _, frame in trashFrame = frame }
                        })
                        .padding(24)
                        .transition(reduced ? .opacity : .scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if visible, let banner = kitchenBanner {
                    KitchenUndoBanner(text: banner.text, undo: banner.undo.map { undo in { undo(); kitchenBanner = nil } }) { kitchenBanner = nil }
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: banner.id) {
                            do { try await Task.sleep(for: .seconds(6)) } catch { return }
                            if kitchenBanner?.id == banner.id { kitchenBanner = nil }
                        }
                }
            }
            .animation(reduced ? nil : .spring(duration: 0.25), value: kitchenHold == nil)
            .animation(reduced ? nil : .easeOut(duration: 0.2), value: kitchenBanner?.id)
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
            // Open, the agents are docked beside the kitchen (dockedAgents); collapsed, this pill
            // stands in for them.
            if model.collapsed {
                AgentSidebarPill(summary: AgentSidebar.summary(sidebarItems(teams))) { group in
                    sidebarReveal = group
                    withAnimation(reduced ? nil : .spring(duration: 0.25)) { model.collapsed = false }
                }
                .transition(reduced ? .opacity : .scale(scale: 0.2, anchor: .topLeading).combined(with: .opacity))
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

    /// The live tools bar, centred at the top of the kitchen when there's room beside the agents
    /// and inbox pills, and the All palette under it.
    @ViewBuilder private func liveTools(_ snapshot: SpatialWorld, focus: SpatialFocus, cooks: [SpatialAgent], width: CGFloat, height: CGFloat) -> some View {
        let teams = focus.projectID.flatMap { id in snapshot.projects.first { $0.id == id }?.teams } ?? snapshot.team(focus).map { [$0] } ?? []
        let project = focus.projectID.flatMap { id in library.projects.projects.first { $0.id == id } }
        VStack(spacing: 12) {
            if width >= 900 {
                LiveToolsBar(agents: cooks, inventory: toolInventory, openAll: { allToolsOpen.toggle() }, chefPoint: { ChefLocator.head($0) })
                    .padding(.top, 12)
            }
            if allToolsOpen, let folder = project?.folder ?? teams.first?.session.project {
                let sessions = Dictionary(teams.map { ($0.session.provider, $0.session.sessionID) }) { first, _ in first }
                let selected = focus.agentID.flatMap { id in teams.flatMap(\.agents).first { $0.id == id } }
                AllResourcesPalette(library: library, folder: folder, sessions: sessions,
                                    armFor: selected.map { ($0.conversationID, $0.value.name) }, inventory: toolInventory) { allToolsOpen = false }
                    .frame(width: min(1220, width - 32), height: min(620, max(320, height - 90)))
                    .padding(.top, width >= 900 ? 0 : 12)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .animation(reduced ? nil : .easeOut(duration: 0.18), value: allToolsOpen)
        .task(id: (project?.folder ?? teams.first?.session.project ?? "") + teams.map(\.session.sessionID).sorted().joined()) {
            guard let folder = project?.folder ?? teams.first?.session.project else { return }
            let sessions = Dictionary(teams.map { ($0.session.provider, $0.session.sessionID) }) { first, _ in first }
            await toolInventory.load(library, folder: folder, sessions: sessions)
        }
        // The kitchen view's own space, so a chef's head and the bar's slots line up for sparks.
        .frame(width: width, height: height, alignment: .top)
        .coordinateSpace(name: "kitchenTools")
    }
    /// The agents panel docked at the kitchen's left edge, full height beside the kitchen and its
    /// command bar. The corner button straddles its edge; the edge itself resizes it.
    private func dockedAgents(_ snapshot: SpatialWorld, focus: SpatialFocus, model: LiveAgentRosterModel) -> some View {
        let teams = focus.projectID.flatMap { id in snapshot.projects.first { $0.id == id }?.teams } ?? snapshot.team(focus).map { [$0] } ?? []
        return agentSidebar(teams, focus: focus, reveal: sidebarReveal, openBoard: { setBoard(true, model) })
            .frame(width: kitchenAgentsWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.black.opacity(0.14)).frame(width: 1)
                    .overlay {
                        Color.clear.frame(width: 7).contentShape(Rectangle())
                            .gesture(DragGesture().onChanged { value in
                                if kitchenAgentsDrag == nil { kitchenAgentsDrag = kitchenAgentsWidth }
                                kitchenAgentsWidth = min(420, max(260, (kitchenAgentsDrag ?? 300) + value.translation.width))
                            }.onEnded { _ in kitchenAgentsDrag = nil })
                            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    }
                    .accessibilityLabel("Resize agents panel")
            }
            .overlay(alignment: .topTrailing) {
                SidebarCornerButton(grow: false) {
                    sidebarReveal = nil
                    withAnimation(reduced ? nil : .spring(duration: 0.25)) { model.collapsed = true }
                }
                .offset(x: 14, y: 11)
            }
            .disabled(inspection != nil).accessibilityHidden(inspection != nil)
    }
    /// The agent card: one row per conversation in this project, grouped by what it needs, from
    /// the same state the kitchen uses (status, pending requests, serving-window reviews).
    private func sidebarItems(_ teams: [SpatialTeam]) -> [AgentSidebarItem] {
        let execution = library.execution
        let workspaces = Dictionary(library.projects.projects.flatMap(\.workspaces).compactMap { w in w.threadID.map { ($0, w) } }) { first, _ in first }
        let inputs = teams.map { team in
            AgentSidebar.Input(session: team.session, agents: team.agents,
                               review: team.agents.first { $0.value.isMain }.flatMap { KitchenReviews.shared.state($0.conversationID) },
                               reviewNote: team.agents.first { $0.value.isMain }.flatMap { KitchenReviews.shared.note($0.conversationID) },
                               model: execution.tasks[team.session.sessionID].flatMap { $0.model.isEmpty ? nil : $0.model },
                               requests: execution.requests.values.filter { $0.threadID == team.session.sessionID }.count,
                               question: pendingQuestion(team),
                               workspaceBranch: workspaces[team.session.sessionID]?.branch,
                               pullRequest: workspaces[team.session.sessionID]?.pullRequest)
        }
        return AgentSidebar.items(inputs, catalog: execution.models, order: AgentSidebarOrder.shared.order)
    }
    /// What a conversation is waiting on you for, in a line: the oldest pending request's question
    /// or command, else (a question asked in chat) the agent's last message.
    private func pendingQuestion(_ team: SpatialTeam) -> String? {
        let execution = library.execution
        if let request = RequestReviewModal.pending(execution, thread: team.session.sessionID).first {
            if let question = request.params["questions"].array.first?["question"].string { return question }
            if let command = request.params["command"].string { return "Wants to run " + command }
            return request.params["reason"].string
        }
        guard team.agents.contains(where: { $0.value.isMain && $0.value.attentionReason == .input && $0.value.status == .waiting }),
              let asked = execution.tasks[team.session.sessionID]?.transcript.entries.last(where: { $0.kind == "Assistant" })?.text else { return nil }
        // The question itself: the message's last sentence that asks something.
        if let question = TurnQuestion.asking(asked) { return question.text }
        let sentences = asked.split(whereSeparator: { ".!\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return sentences.last { $0.hasSuffix("?") } ?? sentences.last
    }
    private func agentSidebar(_ teams: [SpatialTeam], focus: SpatialFocus, reveal: AgentSidebarGroup? = nil, openBoard: (() -> Void)? = nil) -> some View {
        let items = sidebarItems(teams)
        let mains = Dictionary(teams.compactMap { team in team.agents.first { $0.value.isMain }.map { ($0.id, $0) } }) { first, _ in first }
        let selected = focus.agentID.flatMap { id in teams.flatMap(\.agents).first { $0.id == id }?.conversationID }
        return AgentSidebarCard(items: items, projectID: focus.projectID ?? "", selectedConversation: selected,
            // Like clicking the chef in the kitchen: selects it and opens its conversation.
            select: { item in if let agent = mains[item.id] { go(conversationFocus(agent)) } },
            // Opens the conversation, where the pending request waits; nothing is approved here.
            reviewRequest: { item in if let agent = mains[item.id] { openRequest(agent) } },
            // Opens the serving-window review; only its explicit actions take the dish off Done.
            reviewChanges: { item in if let agent = mains[item.id] { reviewing = agent } },
            create: { creationProject = AgentCreationDestination(id: focus.projectID ?? "") }, reveal: reveal, openBoard: openBoard)
    }
    /// Review request: the modal when a request is waiting; otherwise (a question asked in chat)
    /// the conversation, where the agent asked it.
    private func openRequest(_ agent: SpatialAgent) {
        // A pull request that needs a fix is handled at the serving window.
        if KitchenReviews.shared.state(agent.conversationID) == .needsFix { reviewing = agent; return }
        let thread = world.team(.team(project: agent.projectID, conversation: agent.conversationID))?.session.sessionID
        // A pending request, or a question asked in the chat, opens the modal to answer it.
        if let thread, !RequestReviewModal.pending(library.execution, thread: thread).isEmpty || RequestReviewModal.chatQuestion(library.execution, thread: thread) != nil { requestReview = agent } else { go(conversationFocus(agent)) }
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
    /// A chef dropped in the trash: archive its conversation, with a few seconds to undo.
    private func archiveFromKitchen(_ agent: SpatialAgent) {
        guard let session = library.sessions.first(where: { $0.id == agent.conversationID }) else { return }
        let name = agent.value.name
        Task {
            do {
                try await library.setArchived(session, archived: true)
                kitchenBanner = (UUID(), "Archived \(name)", {
                    Task {
                        do { try await library.setArchived(session.updated(archived: true), archived: false) }
                        catch { kitchenBanner = (UUID(), "Couldn't restore \(name): \(error.localizedDescription)", nil) }
                    }
                })
            } catch {
                kitchenBanner = (UUID(), "Couldn't archive \(name): \(error.localizedDescription)", nil)
            }
        }
    }
    private func kitchenAgents(_ world: SpatialWorld, focus: SpatialFocus) -> [SpatialAgent] {
        guard focus != .portfolio else { return [] }
        if let project = focus.projectID { return world.projects.first { $0.id == project }?.teams.flatMap(\.agents) ?? [] }
        return world.team(focus)?.agents ?? []
    }
    /// Back to the whole kitchen: the camera returns to the overview and the command bar closes.
    /// The task board: the agent panel's items as columns of cards. Picking a card steps back
    /// to the side panel, so the conversation it opens isn't hidden behind the board.
    private func agentBoard(_ snapshot: SpatialWorld, focus: SpatialFocus, model: LiveAgentRosterModel) -> some View {
        let teams = focus.projectID.flatMap { id in snapshot.projects.first { $0.id == id }?.teams } ?? snapshot.team(focus).map { [$0] } ?? []
        let mains = Dictionary(teams.compactMap { team in team.agents.first { $0.value.isMain }.map { ($0.id, $0) } }) { first, _ in first }
        let selected = focus.agentID.flatMap { id in teams.flatMap(\.agents).first { $0.id == id }?.conversationID }
        return AgentTaskBoard(items: sidebarItems(teams), selectedConversation: selected,
            select: { item in if let agent = mains[item.id] { setBoard(false, model); go(conversationFocus(agent)) } },
            reviewRequest: { item in if let agent = mains[item.id] { openRequest(agent) } },
            reviewChanges: { item in if let agent = mains[item.id] { reviewing = agent } },
            create: { creationProject = AgentCreationDestination(id: focus.projectID ?? "") },
            mergeAllGreen: { items in await PRWatcher.shared.mergeAllGreen(items, library: library) },
            dock: { setBoard(false, model) })
    }
    private func setBoard(_ open: Bool, _ model: LiveAgentRosterModel) {
        withAnimation(reduced ? nil : .spring(duration: 0.28)) { model.board = open }
    }
    /// An agent selected with its conversation panel open.
    private func conversationFocus(_ agent: SpatialAgent) -> SpatialFocus {
        .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
    }
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

private extension View {
    /// Overlays fade away while a chef is held, without leaving the layout (the kitchen keeps its size).
    func holdHidden(_ hidden: Bool, reduced: Bool) -> some View {
        opacity(hidden ? 0 : 1).allowsHitTesting(!hidden).accessibilityHidden(hidden)
            .animation(reduced ? nil : .easeOut(duration: 0.2), value: hidden)
    }
}

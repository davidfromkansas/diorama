import SwiftUI
import DioramaCore

/// Mounted once by WorkspaceShell, including while conventional tools are open.
struct SpatialWorkspaceView: View {
    @Bindable var library: LibraryModel
    var visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var panelDrag: Double?
    @State private var inspection: AgentInspectionDestination?
    @State private var avatarPopovers = AvatarPopoverDismissals()
    private var inboxExpanded: Bool { get { state.inboxExpanded } nonmutating set { state.inboxExpanded = newValue } }
    private var serversExpanded: Bool { get { state.serversExpanded } nonmutating set { state.serversExpanded = newValue } }
    private var inboxSelection: InboxThread? { get { state.inboxSelection } nonmutating set { state.inboxSelection = newValue } }
    @State private var creationProject: AgentCreationDestination?
    /// A task just created here: its agent is selected (as a click on its row would) once it appears.
    @State private var createdConversation: String?
    @State private var createdAt = Date.distantPast
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
    /// The project settings popover (the gear in the scene's corner).
    @State private var sceneSettingsOpen = false
    private var theme: any SceneTheme { SceneThemes.theme(state.sceneKind) }
    @State private var screenActivity = false
    @State private var cachedWorld: SpatialWorld?
    @State private var cachedProject: String?
    @State private var projectWorlds: [String: SpatialWorld] = [:]
    @State private var projectRecency: [String] = []
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
        // Built in named pieces: as one expression it is too much for the release compiler.
        let content = GeometryReader { geometry in workspace(snapshot, focus: focus, roster: roster, geometry: geometry) }
            .environment(\.sceneVocabulary, theme.vocabulary)
        lifecycle(presentations(content, focus: focus, roster: roster), snapshot: snapshot, focus: focus, roster: roster)
    }

    /// The office or kitchen, with the agent panel beside it, the conversation panel at the right,
    /// and the task board and plan modals over everything.
    private func workspace(_ snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel, geometry: GeometryProxy) -> some View {
        let officeWidth = geometry.size.width - (state.conversationPanelVisible ? resolvedPanelWidth(available: geometry.size.width) : 0)
        let narrow = officeWidth < 760
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                kitchenStage(snapshot, focus: focus, roster: roster)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).clipped()
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
            modalLayers(snapshot, focus: focus, roster: roster, geometry: geometry)
        }
        .onChange(of: state.conversationPanelVisible) { _, shown in
            if shown && narrow { roster.collapsed = true }
        }
    }

    /// The task board, progress and plan modals, over the whole workspace.
    @ViewBuilder private func modalLayers(_ snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel, geometry: GeometryProxy) -> some View {
        // The agents at their largest: the task board over the middle of the window.
        if visible, focus != .portfolio, !roster.collapsed, roster.board, inspection == nil {
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

    /// Sheets, the popover environment and the hidden keyboard-shortcut buttons.
    private func presentations<Content: View>(_ content: Content, focus: SpatialFocus, roster: LiveAgentRosterModel) -> some View {
        content
            .sheet(item: $creationProject) { destination in
                NewAgentModal(library: library, projectID: destination.id, created: { conversation in
                    createdConversation = conversation; createdAt = Date(); selectCreated(world)
                }, failed: { project, message in
                    // Starting it failed after the modal closed: back to the modal, draft and error.
                    createdConversation = nil
                    DispatchQueue.main.async { creationProject = AgentCreationDestination(id: project, error: message) }
                }, initialError: destination.error)
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
            .onChange(of: [library.spatial.pendingCreation ?? "", visible ? "visible" : ""], initial: true) { openPendingCreation() }
            // The pantry card belongs to the project it was opened in.
            .onChange(of: library.projects.selectedID) { pantryOpen = false }
            // ⇧⌘K: every tool the agents can use.
            .background {
                Button("All tools") { if visible, state.focus != .portfolio { allToolsOpen.toggle() } }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
            // ⇧⌘B: the task board, from the panel or the pill, and back to the panel.
            .background {
                Button("Task board") {
                    guard visible, state.focus != .portfolio else { return }
                    let roster = state.roster(for: state.focus.projectID ?? state.focus.conversationID ?? "portfolio")
                    if roster.collapsed { roster.collapsed = false; setBoard(true, roster) } else { setBoard(!roster.board, roster) }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
    }

    /// Escape handling, focus changes and the refresh loops.
    private func lifecycle<Content: View>(_ content: Content, snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel) -> some View {
        content
            // Let native menus and popovers consume Escape before spatial navigation.
            .onExitCommand {
                guard visible else { return }
                if avatarPopovers.dismissTop() { return }
                // The task board steps back down to the side panel first.
                if !roster.collapsed, roster.board { setBoard(false, roster); return }
                // A selected chef is let go first, closing its conversation and command bar.
                if state.focus.agentID != nil, inspection == nil { deselectAgent(state.focus); return }
                if inspection != nil { closePlan() }
                else if serversExpanded { serversExpanded = false }
                else if inboxExpanded && inboxSelection != nil { inboxSelection = nil }
                else if inboxExpanded { inboxExpanded = false }
                else if state.conversationPanelVisible { state.conversationPanelVisible = false }
                else if !roster.collapsed && focus != .portfolio { roster.collapsed = true }
                else if focus != .portfolio { go(focus.panelReturn) }
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
                // A task just created here is selected as soon as it appears, scanning or not.
                selectCreated(new)
                guard visible, cachedProject == state.focus.projectID, !library.isScanning, library.scannedAt != nil else { return }
                if let selection = inspection, !new.teams.flatMap(\.agents).contains(where: { $0.id == selection.agentID }) { inspection = nil }
                // A task just created here takes a moment to join the view: wait for it rather
                // than falling back to the project (which would also drop its selection).
                if let created = createdConversation, state.focus.conversationID == created,
                   !new.teams.contains(where: { $0.session.id == created }), Date().timeIntervalSince(createdAt) < 20 { return }
                let resolved = new.resolved(state.focus)
                if resolved != state.focus {
                    go(resolved)
                    state.notice = "The selected item is no longer available in this view. Showing its nearest available parent."
                }
                selectCreated(new)
            }
            .task(id: "plans-\(visible)-\(library.paused)-\(state.focus)-\(inspection?.nodeName ?? "")") {
                guard visible, !library.paused, state.focus != .portfolio else { return }
                while !Task.isCancelled {
                    let current = world
                    var teams = current.teams.filter { state.focus.projectID != nil ? $0.projectID == state.focus.projectID : $0.session.id == state.focus.conversationID }
                    if state.focus.projectID != nil {
                        let roster = ProjectRoster(teams: teams, now: library.observationClock, including: state.focus.agentID, conversation: state.focus.conversationID)
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
            .onChange(of: library.demoRevision) { library.observationClock = Date(); refreshWorld() }
            // Agent state keeps refreshing whenever the scene is on screen, so chefs keep working while
            // you use another app beside it.
            .task(id: "\(visible)-\(state.focus.conversationID ?? "")") {
                guard visible else { return }
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
            active: visible && inspection == nil, paused: library.paused,
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
                    .background(Color(nsColor: theme.backdrop))
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
                do { try await Task.sleep(for: .seconds(DioramaSceneView.deselectGrace)) } catch { return }
                commandBarAgent = nil
            }
        }
    }

    /// The kitchen scene and everything floating over it: camera reset, sound, agents, live
    /// tools, inbox, trash can and the undo banner.
    private func kitchenScene(_ snapshot: SpatialWorld, focus: SpatialFocus, roster: LiveAgentRosterModel, cooks: [SpatialAgent]) -> some View {
        SceneSurface(kind: state.sceneKind, agents: cooks, scope: focus == .portfolio ? nil : focus.projectID ?? focus.conversationID,
                            reviews: KitchenReviews.shared.states, active: visible,
                            reducedMotion: reduced, select: go, review: { reviewing = $0 }, requestReview: { openRequest($0) }, progress: { progressAgent = $0.id },
                            selectedAgentID: focus.agentID, deselect: { deselectAgent(focus) }, openPantry: { pantryOpen = true },
                            cameraMoved: { away in DispatchQueue.main.async { kitchenCameraAway = away } }, resetCamera: kitchenCameraResets,
                            holding: { hold in DispatchQueue.main.async { kitchenHold = hold } },
                            archiveBlocker: { library.archiveBlocker($0) }, archive: { archiveFromKitchen($0) }, trashFrame: trashFrame,
                            changedFiles: { changedFiles($0) }, modelName: { modelName($0) })
            .overlay(alignment: .bottomLeading) {
                // Only once the camera has moved; the controls stay in the kitchen's accessibility help.
                if visible, focus.agentID == nil, kitchenCameraAway {
                    Button("Reset View") { kitchenCameraResets += 1 }.controlSize(.small).pointingHand().help("Back to the whole \(theme.vocabulary.place) (R)")
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial)).padding(12)
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    HStack(spacing: 8) {
                        // The project's settings: which scene its agents work in.
                        if let project = focus.projectID {
                            Button { sceneSettingsOpen.toggle() } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(Circle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary).background(Circle().fill(.regularMaterial))
                            .pointingHand().help("Project settings").accessibilityLabel("Project settings")
                            .popover(isPresented: $sceneSettingsOpen, arrowEdge: .top) {
                                ProjectSceneSettings(scene: Binding(get: { library.projectScenes.kind(for: project) },
                                                                    set: { library.setScene($0, project: project) }),
                                                     sounds: $kitchenSounds)
                            }
                        }
                        Button { kitchenSounds.toggle() } label: {
                            Image(systemName: kitchenSounds ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(Circle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).background(Circle().fill(.regularMaterial))
                        .pointingHand().help(kitchenSounds ? "Mute \(theme.vocabulary.place) sounds" : "Play \(theme.vocabulary.place) sounds")
                        .accessibilityLabel(kitchenSounds ? "Mute \(theme.vocabulary.place) sounds" : "Play \(theme.vocabulary.place) sounds")
                    }
                    .padding(12)
                    .holdHidden(kitchenHold != nil, reduced: reduced)
                }
            }
            // A new scene starts at its home view.
            .onChange(of: state.sceneKind) { kitchenCameraAway = false; sceneSettingsOpen = false }
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
                            ProjectInboxDock(library: library, project: project, height: max(120, scene.size.height * 0.55),
                                active: !library.paused,
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
    private func sidebarItems(_ teams: [SpatialTeam]) -> [AgentSidebarItem] { library.agentSidebarItems(teams) }
    /// Home's New task opens this project with its Create modal, once the workspace is showing.
    private func openPendingCreation() {
        guard visible, let project = library.spatial.pendingCreation, library.projects.selectedID == project else { return }
        library.spatial.pendingCreation = nil
        creationProject = AgentCreationDestination(id: project)
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
        if let thread, !RequestReviewModal.pending(library.execution, thread: thread).isEmpty || RequestReviewModal.chatQuestion(library.execution, thread: thread) != nil
            || library.demo?.questions[agent.conversationID] != nil { requestReview = agent } else { go(conversationFocus(agent)) }
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
        selectCreated(next)
    }


    private func closePlan() { inspection = nil }
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
        let header = headerInfo(agent, team: team)
        return VStack(spacing: 0) {
            if agent.value.isMain && !screenActivity {
                // The conversation draws the header itself: it holds the model and the tools.
                SessionView(session: team.session, model: library, hasLocalReview: true,
                    activityAction: { section in library.activityState(team.session).section = section; screenActivity = true },
                    shellContent: true, embeddedWorkScreen: true)
                    .environment(\.avatarHeader, header)
            } else {
                AvatarConversationHeader(info: header)
                Divider()
                if agent.value.isMain {
                    SessionActivityPanel(session: team.session, library: library, state: library.activityState(team.session), close: { screenActivity = false })
                } else {
                    SpatialChildWorkScreen(library: library, session: team.session, agent: agent.value)
                }
            }
        }.id(agent.id)
    }
    /// The header's who and what: the agent, its task as its tag and agent-panel row name it
    /// (updated each turn), and its branch.
    private func headerInfo(_ agent: SpatialAgent, team: SpatialTeam) -> AvatarHeaderInfo {
        _ = TaskLabels.shared.revision
        let label = agent.value.isMain ? TaskLabels.shared.title(agent) : ""
        let fallback = agent.value.isMain ? team.title : TaskTitle.compact(agent.value.task)
        let workspaces = library.projects.projects.first(where: { $0.id == team.projectID })?.workspaces ?? []
        return AvatarHeaderInfo(name: agent.value.name, task: label.isEmpty ? fallback : label,
                                taskDetail: TaskTitle.full(agent.value.isMain ? team.session.title : agent.value.task),
                                branch: AvatarMessagePresentation.branch(session: team.session, workspaces: workspaces),
                                close: { screenActivity = false; state.conversationPanelVisible = false })
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
    /// The model an agent runs on, named as the agent panel names it.
    private func modelName(_ agent: SpatialAgent) -> String {
        let session = library.sessions.first { $0.id == agent.conversationID }
        let running = session.flatMap { library.execution.tasks[$0.sessionID] }.flatMap(\.namedModel)
        return AgentSidebar.modelName(running ?? agent.value.reportedModel, provider: agent.value.provider, catalog: library.execution.models)
    }
    /// How many files an agent's task changed since it began (git, as its Changes panel counts).
    private func changedFiles(_ agent: SpatialAgent) -> Int? {
        guard let session = library.sessions.first(where: { $0.id == agent.conversationID }),
              let workspace = library.projects.projects.first(where: { $0.id == agent.projectID })?.workspaces.first(where: { $0.threadID == session.sessionID })
        else { return nil }
        return SessionChangeCounts.shared.count(workspace)
    }
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
    /// Selects a just-created task's agent the way clicking its row in the agent panel does, once
    /// it's in the view; only while its conversation is still the one on screen.
    private func selectCreated(_ snapshot: SpatialWorld) {
        guard let conversation = createdConversation else { return }
        guard state.focus.conversationID == conversation else { createdConversation = nil; return }
        guard let main = snapshot.teams.first(where: { $0.session.id == conversation })?.agents.first(where: { $0.value.isMain }) else { return }
        createdConversation = nil
        go(conversationFocus(main))
    }
    private func conversationFocus(_ agent: SpatialAgent) -> SpatialFocus {
        .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
    }
    private func deselectAgent(_ focus: SpatialFocus) {
        go(focus.projectID.map { .project($0) } ?? focus.panelReturn)
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

private struct AgentCreationDestination: Identifiable {
    let id: String
    /// Why the last start failed, shown when the modal reopens.
    var error: String? = nil
}

private extension View {
    /// Overlays fade away while a chef is held, without leaving the layout (the kitchen keeps its size).
    func holdHidden(_ hidden: Bool, reduced: Bool) -> some View {
        opacity(hidden ? 0 : 1).allowsHitTesting(!hidden).accessibilityHidden(hidden)
            .animation(reduced ? nil : .easeOut(duration: 0.2), value: hidden)
    }
}

import SwiftUI
import DioramaCore

/// Home's palette: a light page whatever the system appearance, like the kitchen's cards.
enum HomeStyle {
    static let ink = Color(red: 0.14, green: 0.09, blue: 0.21)
    static let secondary = Color(red: 0.29, green: 0.27, blue: 0.32)
    static let muted = Color(red: 0.48, green: 0.45, blue: 0.51)
    static let card = Color(red: 0.98, green: 0.973, blue: 0.957)
    static let border = Color(red: 0.894, green: 0.871, blue: 0.827)
    static let rule = Color(red: 0.937, green: 0.922, blue: 0.894)
    static let purple = Color(red: 0.54, green: 0.31, blue: 0.84)
    static let orange = Color(red: 0.94, green: 0.54, blue: 0.14)
    static let orangeInk = Color(red: 0.60, green: 0.29, blue: 0.03)
    static let orangeWash = Color(red: 1.0, green: 0.97, blue: 0.93)
    static let orangeBorder = Color(red: 0.95, green: 0.79, blue: 0.61)
    static let green = Color(red: 0.18, green: 0.62, blue: 0.30)
    static let greenInk = Color(red: 0.12, green: 0.48, blue: 0.23)
    static let blue = Color(red: 0.14, green: 0.34, blue: 0.90)
    static func cardShadow<V: View>(_ view: V) -> some View {
        view.shadow(color: Color(red: 0.16, green: 0.08, blue: 0.27).opacity(0.07), radius: 8, y: 6)
    }
}

/// The company marks Diorama ships, tinted for a light page.
enum HomeMark {
    case claude, openAI, github
    private var file: String { switch self { case .claude: "Claude"; case .openAI: "OpenAI"; case .github: "GitHub" } }
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openAI: .black
        case .github: Color(red: 0.14, green: 0.16, blue: 0.18)
        }
    }
    func image(size: CGFloat) -> some View {
        Group {
            if let url = Bundle.dioramaResources?.url(forResource: file, withExtension: "svg", subdirectory: "ConnectorBrand"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: { image.isTemplate = true; return image }()).resizable().scaledToFit().foregroundStyle(tint)
            } else {
                Image(systemName: "circle.fill").resizable().foregroundStyle(tint)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    static func provider(_ provider: Provider) -> Self { provider == .claude ? .claude : .openAI }
}

/// The sections like the Xbox dashboard's: the current one large and pinned just above the cards,
/// the ones before it stacked above, smaller and fainter the further back. The list wraps, so ↓
/// rolls the next section (the faintest, at the top) down into the pinned spot.
struct HomeSectionMenu: View {
    let current: HomeSectionKind
    let badges: [HomeSectionKind: Int]
    let select: (HomeSectionKind) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Size and opacity by distance from the current section.
    static let steps: [(size: CGFloat, opacity: Double)] = [(40, 1), (24, 0.62), (19, 0.40), (16, 0.24)]
    static let full: CGFloat = 40
    /// Furthest back first, the current section last.
    static func order(_ current: HomeSectionKind) -> [HomeSectionKind] {
        let all = HomeSectionKind.allCases
        return (0..<all.count).reversed().map { all[(current.rawValue - $0 + all.count) % all.count] }
    }
    var body: some View {
        let all = HomeSectionKind.allCases
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.order(current)) { section in
                let distance = (current.rawValue - section.rawValue + all.count) % all.count
                let step = Self.steps[min(distance, Self.steps.count - 1)]
                let selected = distance == 0
                Button { select(section) } label: {
                    // Every title is set at full size and scaled, so moving between sections
                    // animates smoothly on the GPU instead of snapping between font sizes.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(section.title).font(.system(size: Self.full, weight: .semibold)).tracking(-0.8)
                        count(section, size: Self.full)
                        if selected && section == .active { LevelBars(animate: !reduceMotion).alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
                    }
                    .foregroundStyle(HomeStyle.ink)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(HomeStyle.purple).frame(width: 9, height: 9).offset(x: -20).opacity(selected ? 1 : 0)
                    }
                    .fixedSize()
                    .scaleEffect(step.size / Self.full, anchor: .bottomLeading)
                    .opacity(step.opacity)
                    .frame(height: step.size * 1.2, alignment: .bottomLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointingHand()
                .accessibilityLabel(section.title + (badges[section].flatMap { $0 > 0 ? ", \($0)" : nil } ?? ""))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12), value: current)
    }
    /// Zero says nothing, so it's hidden; Needs you's count is a badge because it's waiting on you.
    @ViewBuilder private func count(_ section: HomeSectionKind, size: CGFloat) -> some View {
        if let badge = badges[section], badge > 0 {
            if section == .needsYou {
                Text("\(badge)").font(.system(size: max(11, size * 0.34), weight: .bold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, size * 0.18).frame(minWidth: size * 0.56, minHeight: size * 0.56)
                    .background(HomeStyle.orange, in: Capsule())
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + size * 0.02 }
            } else {
                Text("\(badge)").font(.system(size: max(11, size * 0.42), weight: .semibold)).monospacedDigit()
                    .baselineOffset(size * 0.32)
            }
        }
    }
}

/// Three bars bouncing like a level meter: work is happening.
private struct LevelBars: View {
    let animate: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animate)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let period = [1.0, 0.8, 1.15][index], phase = [0, 0.3, 0.6][index]
                    let level = animate ? 0.3 + 0.7 * (0.5 + 0.5 * sin((t + phase) / period * 2 * .pi)) : 0.6
                    RoundedRectangle(cornerRadius: 2).fill(HomeStyle.purple).frame(width: 4, height: 20 * level)
                }
            }.frame(height: 20, alignment: .bottom)
        }.accessibilityHidden(true)
    }
}

/// A round status button with its name and one line under it, like a console's home screen.
struct HomeOrb<Glyph: View>: View {
    let title: String
    var detail = ""
    var detailTint = HomeStyle.muted
    var fill = Color.white
    /// A ring inside the disc; it fills with what's left of a limit (0...1), empty when not reported.
    var showsMeter = false
    var meter: Double?
    var meterTint = HomeStyle.purple
    var alert = false
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph
    var body: some View {
        Button { HomeSound.shared.select(); action() } label: {
            VStack(spacing: 9) {
                ZStack {
                    // The shadow comes from the plain circle, not the glyph and ring on it.
                    Circle().fill(fill).shadow(color: Color(red: 0.14, green: 0.09, blue: 0.21).opacity(fill == .clear ? 0 : 0.14), radius: 8, y: 6)
                    if showsMeter {
                        Circle().inset(by: 6.5).stroke(Color(red: 0.93, green: 0.91, blue: 0.88), lineWidth: 3)
                        if let left = meter, left > 0 {
                            Circle().inset(by: 6.5).trim(from: 0, to: min(1, left))
                                .stroke(meterTint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                    }
                    glyph()
                }
                .frame(width: 56, height: 56)
                .overlay(alignment: .topTrailing) {
                    if alert { Circle().fill(HomeStyle.orange).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white, lineWidth: 2)) }
                }
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(HomeStyle.ink)
                    if !detail.isEmpty { Text(detail).font(.system(size: 11.5)).foregroundStyle(detailTint).monospacedDigit() }
                }.lineLimit(1).fixedSize()
            }
            .frame(minWidth: 96).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
    }
}

/// Claude Code or Codex: what's left of this week's limit as a ring, signed out as an alert.
struct HomeProviderOrb: View {
    let provider: Provider
    let window: LimitWindow?
    let state: AgentConnectionState
    let signingIn: Bool
    /// Opens the connections panel.
    let open: () -> Void
    let signIn: () -> Void
    private var name: String { provider == .claude ? "Claude Code" : "Codex" }
    private var signedOut: Bool { state == .signedOut || state == .missing || state == .unavailable }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let current = window.flatMap { $0.expired(now: context.date) ? nil : $0 }
            let left = current?.usedPercent.map { max(0, 100 - $0) }
            let reached = current?.status == .exhausted
            HomeOrb(title: name, detail: signedOut ? statusText : Self.detail(current, now: context.date),
                    detailTint: signedOut || reached ? HomeStyle.orangeInk : HomeStyle.muted,
                    showsMeter: !signedOut, meter: left.map { $0 / 100 }, meterTint: provider == .claude ? HomeMark.claude.tint : HomeStyle.secondary,
                    alert: signedOut && state != .missing, action: signedOut && state != .missing ? signIn : open) {
                HomeMark.provider(provider).image(size: 20)
            }
            .accessibilityLabel(signedOut ? "\(name), \(statusText)" : Self.accessibility(name: name, window: current, now: context.date))
            .accessibilityHint(signedOut && state != .missing ? "Signs in" : "Shows connections")
        }
    }
    private var statusText: String {
        switch state {
        case .missing: "Not installed"
        case .unavailable: "Couldn't verify"
        default: signingIn ? "Waiting…" : "Sign in"
        }
    }
    /// "45% left · refills Sun", or why there's no number.
    static func detail(_ window: LimitWindow?, now: Date) -> String {
        guard let window else { return "Not reported yet" }
        if window.status == .exhausted { return "Limit reached" }
        guard let used = window.usedPercent else { return limitText(window) }
        let left = "\(Int(max(0, 100 - used).rounded()))% left"
        guard let reset = window.resetsAt, reset > now else { return left }
        return left + " · refills " + reset.formatted(.dateTime.weekday(.abbreviated))
    }
    static func limitText(_ window: LimitWindow?) -> String {
        guard let window else { return "Not reported yet" }
        return switch window.status {
        case .exhausted: "Limit reached"
        case .warning: "Near limit"
        default: "Within limit"
        }
    }
    static func accessibility(name: String, window: LimitWindow?, now: Date) -> String {
        guard let window else { return "\(name) weekly limit not reported yet" }
        var parts = ["\(name) weekly limit"]
        if let used = window.usedPercent { parts.append("\(Int(used.rounded())) percent used") } else { parts.append(limitText(window)) }
        if let reset = window.resetsAt, reset > now { parts.append("resets " + reset.formatted(.dateTime.weekday(.wide).hour().minute())) }
        return parts.joined(separator: ", ")
    }
}

/// The GitHub connection: the account when connected, an alert when it needs you. Opens the GitHub modal.
struct HomeGitHubOrb: View {
    let open: () -> Void
    @State private var connection = GitHubConnection.shared
    var body: some View {
        HomeOrb(title: "GitHub", detail: status, detailTint: attention ? HomeStyle.orangeInk : HomeStyle.muted, alert: attention, action: open) {
            HomeMark.github.image(size: 20)
        }
        .accessibilityLabel("GitHub, " + status)
    }
    private var attention: Bool {
        switch connection.state { case .needsAttention, .needsKeychain, .notConnected: true; default: false }
    }
    private var status: String {
        switch connection.state {
        case .checking: "Checking…"
        case .notConnected: "Connect"
        case .signingIn: "Signing in…"
        case .connected(let login, _): login
        case .needsAttention(.unreachable): "Offline"
        case .needsAttention: "Reconnect"
        case .needsKeychain: "Allow access"
        }
    }
}

struct CardShadow: ViewModifier {
    func body(content: Content) -> some View { HomeStyle.cardShadow(content) }
}

/// The gear's panel: sign in to, manage, or check each connection.
struct HomeConnectionsPanel: View {
    let library: LibraryModel
    let openGitHub: () -> Void
    let openSettings: () -> Void
    let openImported: (() -> Void)?
    @State private var connections = AgentConnections.shared
    @State private var github = GitHubConnection.shared
    @State private var defaults = ProviderDefaultsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Connections").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("Used by every project on this Mac").font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
            }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            ForEach([Provider.claude, .codex], id: \.self) { provider in providerRow(provider) }
            row(mark: .github, name: "GitHub", status: githubStatus, connected: github.login != nil,
                detail: github.login == nil ? "Import repositories, publish and open pull requests" : "Repositories, pull requests and checks") {
                Button(github.login == nil ? "Connect" : "Manage", action: openGitHub).buttonStyle(HomePanelButton(prominent: github.login == nil))
            }
            if let openImported {
                Divider().overlay(HomeStyle.rule)
                Button(action: openImported) {
                    HStack { Label("Imported activity", systemImage: "tray.full"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .font(.system(size: 13)).foregroundStyle(HomeStyle.secondary).padding(.horizontal, 18).padding(.vertical, 11).contentShape(Rectangle())
                }.buttonStyle(.plain).pointingHand()
            }
            Divider().overlay(HomeStyle.rule)
            Text("Signing in and out only affects this Mac.").font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 400).foregroundStyle(HomeStyle.ink).background(.white)
        .task { await connections.refresh(library.execution, force: true) }
    }
    private var githubStatus: String {
        switch github.state {
        case .connected(let login, _): "Connected as @\(login)"
        case .notConnected: "Not connected"
        case .signingIn: "Signing in…"
        case .checking: "Checking…"
        case .needsAttention(let problem): problem.message
        case .needsKeychain: "Needs permission for the saved login"
        }
    }
    @ViewBuilder private func providerRow(_ provider: Provider) -> some View {
        let state = connections.state(provider)
        let name = provider == .claude ? "Claude Code" : "Codex"
        let window = library.portfolio.home.weekly[provider]
        let detail: String = switch state {
        case .connected: library.portfolio.home.planName(provider) + (window?.usedPercent.map { " · \(Int($0.rounded()))% used this week" } ?? "")
        case .missing: "\(name) isn't installed on this Mac"
        case .checking: "Checking the connection"
        default: "Agents on \(name) can't start until you sign in"
        }
        row(mark: HomeMark.provider(provider), name: name, status: Self.status(state), connected: state == .connected, detail: detail,
            footer: AnyView(defaultPermissions(provider))) {
            if state == .connected || state == .missing {
                Button("Manage…", action: openSettings).buttonStyle(HomePanelButton(prominent: false))
            } else if state != .checking {
                Button(connections.pendingLogin == provider ? "Waiting…" : "Sign in") { connections.signIn(provider, execution: library.execution) }
                    .buttonStyle(HomePanelButton(prominent: true)).disabled(connections.pendingLogin == provider)
            }
        }
    }
    static func status(_ state: AgentConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .checking: "Checking…"
        case .missing: "Not installed"
        case .signedOut: "Signed out"
        case .unavailable: "Couldn't verify"
        }
    }
    /// The mode new chats start in, here and in the Codex/Claude apps and terminal; changing it
    /// writes the provider's own settings file.
    private func defaultPermissions(_ provider: Provider) -> some View {
        HStack(spacing: 6) {
            Text("New chats start in").foregroundStyle(HomeStyle.muted)
            Menu {
                ForEach(ProviderDefaultsStore.choices(provider), id: \.self) { choice in
                    Button { defaults.set(choice, for: provider) } label: {
                        let title = provider == .claude && choice == .fullAccess ? "Bypass permissions" : choice.title
                        if defaults.choice(provider) == choice { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: {
                Text(defaults.label(provider)).foregroundStyle(HomeStyle.ink)
            }
            .menuStyle(.borderlessButton).fixedSize().pointingHand()
            .help("Also used by the \(provider == .claude ? "Claude" : "Codex") app and terminal")
        }
        .font(.system(size: 12))
        .onAppear { defaults.reload() }
    }
    private func row<Action: View>(mark: HomeMark, name: String, status: String, connected: Bool, detail: String, footer: AnyView? = nil, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark.image(size: 18).frame(width: 36, height: 36).background(HomeStyle.rule, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 14, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(connected ? HomeStyle.green : HomeStyle.orange).frame(width: 7, height: 7)
                    Text(status).foregroundStyle(connected ? HomeStyle.greenInk : HomeStyle.orangeInk)
                }.font(.system(size: 12.5))
                Text(detail).font(.system(size: 12)).foregroundStyle(HomeStyle.muted).fixedSize(horizontal: false, vertical: true)
                if let footer { footer.padding(.top, 2) }
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(connected ? Color.white : HomeStyle.orangeWash)
        .overlay(alignment: .top) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
    }
}

struct HomePanelButton: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(prominent ? .white : HomeStyle.ink)
            .padding(.horizontal, 12).frame(height: 28)
            .background(prominent ? HomeStyle.orange : .white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? HomeStyle.orange : Color(red: 0.85, green: 0.83, blue: 0.80)))
            .opacity(configuration.isPressed ? 0.7 : 1).pointingHand()
    }
}

/// Add project: find or connect a folder, open a GitHub repository, or start a new project.
struct HomeAddProjectButton: View {
    let choose: (String) -> Void
    @State private var open = false
    var body: some View {
        HomeOrb(title: "Add project", fill: HomeStyle.purple, action: { open.toggle() }) {
            Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
        }
        .accessibilityLabel("Add project").accessibilityHint("Shows ways to add a project")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                option("Find or connect a project", "Choose a folder already on this Mac", request: "Connect Project") {
                    Image(systemName: "folder").font(.system(size: 16)).foregroundStyle(HomeStyle.purple)
                } tile: { Color(red: 0.937, green: 0.906, blue: 0.98) }
                option("Open a GitHub project", "Clone one of your repositories", request: "Open GitHub project") {
                    GitHubSymbol.icon.foregroundStyle(.white)
                } tile: { Color(red: 0.14, green: 0.16, blue: 0.18) }
                option("New project", "Start an empty project, optionally on GitHub", request: "New Project") {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                } tile: { HomeStyle.purple }
            }
            .padding(6).frame(width: 360).background(.white).environment(\.colorScheme, .light)
        }
    }
    private func option<Icon: View, Tile: View>(_ title: String, _ detail: String, request: String,
                                                @ViewBuilder icon: () -> Icon, @ViewBuilder tile: () -> Tile) -> some View {
        HomeMenuRow(title: title, detail: detail, icon: icon(), tile: tile()) { open = false; choose(request) }
    }
}

private struct HomeMenuRow<Icon: View, Tile: View>: View {
    let title: String
    let detail: String
    let icon: Icon
    let tile: Tile
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon.frame(width: 38, height: 38).background(tile).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(HomeStyle.ink)
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(HomeStyle.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(hovered ? Color(red: 0.96, green: 0.945, blue: 0.984) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().onHover { hovered = $0 }
        .accessibilityLabel(title).accessibilityHint(detail)
    }
}

/// A controller-style hint under the cards: round keycaps, then what they do.
struct HomeKeyHint: View {
    /// SF Symbol names, or "space" for the space bar.
    let keys: [String]
    let label: String
    var tint: Color? = nil
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) { ForEach(keys, id: \.self) { cap($0) } }
            Text(label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(HomeStyle.ink.opacity(0.75))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(keys.map { $0.replacingOccurrences(of: "arrow.", with: "") }.joined(separator: " or ")): \(label)")
    }
    @ViewBuilder private func cap(_ key: String) -> some View {
        let fill = tint ?? .white
        let ink = tint == nil ? HomeStyle.ink : .white
        Group {
            if key == "space" {
                Text("space").font(.system(size: 11.5, weight: .bold)).padding(.horizontal, 12)
            } else {
                Image(systemName: key).font(.system(size: 11, weight: .bold)).frame(width: 26)
            }
        }
        .foregroundStyle(ink).frame(height: 26)
        .background(Capsule().fill(fill.gradient))
        .overlay(Capsule().strokeBorder(tint == nil ? HomeStyle.border : .black.opacity(0.12)))
        .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
    }
}

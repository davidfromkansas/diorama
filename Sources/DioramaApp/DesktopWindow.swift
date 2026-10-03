import SwiftUI

struct DesktopWindow: View {
    let services: LibraryModel
    @State private var library: LibraryModel?
    var body: some View {
        Group {
            if let library { ProjectsRootView(library: library).focusedSceneValue(\.desktopLibrary, library) }
            else { Color.clear }
        }.onAppear { if library == nil { library = services.makeWindowModel() } }
    }
}
private struct DesktopLibraryFocus: FocusedValueKey { typealias Value = LibraryModel }
extension FocusedValues {
    var desktopLibrary: LibraryModel? {
        get { self[DesktopLibraryFocus.self] }
        set { self[DesktopLibraryFocus.self] = newValue }
    }
}
struct DesktopCommands: Commands {
    @FocusedValue(\.desktopLibrary) private var library
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open project…") { library?.navigation.projectTabs.pickerPresented = true }.pointingHand().keyboardShortcut("t").disabled(library == nil)
            Button("New session") { library?.showNewTask = true }.pointingHand().keyboardShortcut("n").disabled(library == nil)
            Button("Toggle agents") { if let library, let id = library.spatial.focus.projectID { library.spatial.roster(for: id).collapsed.toggle() } }.pointingHand().keyboardShortcut("b")
            Button("Toggle right panel") { library?.toggleWorkspaceInspector() }.pointingHand().keyboardShortcut("b", modifiers: [.command, .option])
            Button("Find session") { library?.navigation.searchPresented = true }.pointingHand().keyboardShortcut("k")
            Button("Focus composer") { library?.focusWorkspaceComposer() }.pointingHand().keyboardShortcut("l")
            Button("Back") { if let library, let destination = library.navigation.back() { library.navigate(destination, record: false) } }.pointingHand().keyboardShortcut("[")
            Button("Forward") { if let library, let destination = library.navigation.forward() { library.navigate(destination, record: false) } }.pointingHand().keyboardShortcut("]")
            Button("Home") { library?.selectDesktopTab(.home) }.pointingHand().keyboardShortcut("h", modifiers: [.command, .shift])
            ForEach(1...9, id: \.self) { number in
                Button(number == 1 ? "Select Home" : "Select project tab \(number - 1)") {
                    if let library, let tab = library.navigation.projectTabs.tab(at: number - 1) { library.selectDesktopTab(tab, userOpened: true) }
                }.pointingHand().keyboardShortcut(KeyEquivalent(Character(String(number))))
            }
        }
    }
}
/// Window-scoped key monitor leaves Home's ⌘W, Escape and text editing to AppKit.
struct DesktopKeyboardMonitor: NSViewRepresentable {
    let library: LibraryModel
    func makeNSView(context: Context) -> DesktopKeyView { DesktopKeyView(library: library) }
    func updateNSView(_ view: DesktopKeyView, context: Context) { view.library = library }
    static func dismantleNSView(_ view: DesktopKeyView, coordinator: ()) { view.stop() }
}
final class DesktopKeyView: NSView {
    var library: LibraryModel
    private var monitor: Any?
    init(library: LibraryModel) { self.library = library; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowActivityChanged), name: name, object: window)
        }
        DispatchQueue.main.async { [weak self] in self?.windowActivityChanged() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow, event.window === window, window.attachedSheet == nil else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            if library.navigation.projectTabs.pickerPresented, event.keyCode == 53 || (modifiers == .command && event.charactersIgnoringModifiers == "w") {
                library.navigation.projectTabs.pickerPresented = false; return nil
            }
            if modifiers == .command, event.charactersIgnoringModifiers == "w", case .project(let id) = library.navigation.projectTabs.selected {
                library.closeProjectTab(id); return nil
            }
            if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift] {
                library.selectDesktopTab(library.navigation.projectTabs.adjacent(modifiers.contains(.shift) ? -1 : 1), userOpened: true); return nil
            }
            return event
        }
    }
    @objc private func windowActivityChanged() {
        library.windowIsActive = window?.isKeyWindow == true && window?.occlusionState.contains(.visible) == true
    }
    func stop() { NotificationCenter.default.removeObserver(self); if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

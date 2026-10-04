import SwiftUI
import DioramaCore

/// A presentation of the existing project draft, without owning execution lifetime.
struct NewAgentModal: View {
    @Bindable var library: LibraryModel
    @State var projectID: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectingProject = false
    @State private var search = ""
    @State private var popovers = AvatarPopoverDismissals()
    private var project: DioramaProject? { library.projects.projects.first { $0.id == projectID } }
    private var busy: Bool { library.projects.busy.contains(projectID) }

    var body: some View {
        VStack(spacing: 0) {
            if let project, project.isGitBacked {
                ProjectDraftView(projectID: projectID, projects: library.projects, library: library, compact: true, creationProjectPicker: AnyView(projectPicker), creationClose: AnyView(closeButton)) { id, conversation in
                    library.navigate(.project(id, conversation))
                    library.spatial.conversationPanelVisible = true
                    dismiss()
                }.id(projectID)
            } else {
                HStack { projectPicker; Spacer(); closeButton }.padding(20)
                ContentUnavailableView("Choose a Git project", systemImage: "folder", description: Text("Starting an agent requires a Git repository with at least one commit."))
                    .frame(height: 260)
            }
        }
        .frame(width: 640).background(.white).environment(\.colorScheme, .light).tint(.blue)
        .environment(\.avatarPopoverDismissals, popovers)
        .environment(\.opaqueMessagesPopovers, true)
        .presentationBackground(Color.white).preferredColorScheme(.light)
        .background(NewAgentOutsideDismissal { dismiss() })
        .onExitCommand { if !popovers.dismissTop() { dismiss() } }
    }
    private var projectPicker: some View {
                Button { selectingProject.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text(project?.name ?? "Choose project").lineLimit(1).truncationMode(.middle)
                            .help(project?.name ?? "Choose project")
                        Image(systemName: "chevron.down").font(.caption)
                    }.font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: 180, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }.pointingHand().buttonStyle(HoverButtonStyle()).disabled(busy)
                    .popover(isPresented: $selectingProject) {
                        VStack(spacing: 12) {
                            TextField("Search projects", text: $search).textFieldStyle(.roundedBorder)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(library.projects.projects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                                        Button {
                                            projectID = item.id; selectingProject = false
                                        } label: {
                                            HStack {
                                                Label(item.name, systemImage: "folder")
                                                Spacer()
                                                if projectID == item.id { Image(systemName: "checkmark") }
                                            }.padding(8).contentShape(Rectangle())
                                        }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0))
                                    }
                                }
                            }.frame(maxHeight: 260)
                        }.padding(14).frame(width: 320).environment(\.colorScheme, .light)
                            .avatarPopoverDismissal(isPresented: $selectingProject)
                    }

    }
    private var closeButton: some View {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.05), in: Circle())
                }.pointingHand().buttonStyle(HoverButtonStyle(inset: 0, radius: 14)).accessibilityLabel("Close new conversation")
    }
}

/// Sheets do not dismiss on backdrop clicks by default. Consume the click so
/// dismissing this sheet cannot also activate the workspace underneath it.
struct NewAgentOutsideDismissal: NSViewRepresentable {
    var dismiss: () -> Void
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.dismiss = dismiss }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }

    final class Probe: NSView {
        var dismiss: () -> Void = {}
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let sheet = self.window, let parent = sheet.sheetParent,
                      event.window === parent, sheet.attachedSheet == nil,
                      !(sheet.childWindows ?? []).contains(where: { $0.isVisible }),
                      !sheet.frame.contains(parent.convertPoint(toScreen: event.locationInWindow)) else { return event }
                self.dismiss()
                return nil
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}

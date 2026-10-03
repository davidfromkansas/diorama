import SwiftUI

struct BranchSelectionPopover: View {
    let branches: [String]
    let selected: String
    @Binding var search: String
    let select: (String) -> Void
    @State private var hovered: String?
    @FocusState private var searchFocused: Bool
    private var matches: [String] {
        branches.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Select target branch…", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search target branches")
                    .onSubmit { if matches.count == 1, let branch = matches.first { select(branch) } }
            }.font(.system(size: 14)).padding(.horizontal, 16).frame(height: 48)
            Divider()
            if matches.isEmpty {
                Text("No matching branches").font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches, id: \.self) { branch in
                            Button { select(branch) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                                        .opacity(selected == branch ? 1 : 0).frame(width: 18)
                                    Text(branch == "HEAD" ? "Current revision" : branch)
                                        .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).frame(height: 34)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(selected == branch ? 0.07 : hovered == branch ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }.pointingHand().buttonStyle(.plain).help(branch)
                                .accessibilityLabel(branch == "HEAD" ? "Current revision" : branch)
                                .accessibilityAddTraits(selected == branch ? .isSelected : [])
                                .onHover { hovered = $0 ? branch : nil }
                        }
                    }.padding(6)
                }.frame(height: min(300, CGFloat(matches.count) * 36 + 10))
            }
        }.frame(width: 350)
            .onAppear { searchFocused = true }
    }
}

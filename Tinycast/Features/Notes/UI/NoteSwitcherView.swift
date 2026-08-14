import SwiftUI

struct NoteSwitcherView: View {
    @Environment(NotesCoordinator.self) private var notes
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.Colors.separator)
            sectionLabel
            results
        }
        .onAppear(perform: focusSearch)
        .onChange(of: notes.switcherFocusRevision) { _, _ in focusSearch() }
        .onChange(of: notes.visibleNotes) { _, _ in
            notes.reconcileSwitcherSelection()
        }
        .onKeyPress(.downArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.selectSwitcherNote()
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("", text: notes.searchQueryBinding)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .background(alignment: .leading) {
                    if notes.searchQueryBinding.wrappedValue.isEmpty {
                        Text("Search notes…")
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .allowsHitTesting(false)
                    }
                }
                .onExitCommand { notes.closeSwitcher() }
                .accessibilityLabel("Search Notes")
            Button {
                notes.closeSwitcher()
            } label: {
                SymbolImage(name: "xmark", size: Theme.Size.noteStatus)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Note Switcher")
            .accessibilityLabel("Close Note Switcher")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.noteSwitcherHeaderHeight)
    }

    private var sectionLabel: some View {
        Text("Notes")
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.sectionSpacing)
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }

    @ViewBuilder
    private var results: some View {
        if notes.visibleNotes.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                SymbolImage(
                    name: notes.isSearching ? "clock" : "text.page",
                    size: Theme.Size.noteStatus)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(notes.isSearching ? "Searching notes…" : "No notes found")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let activeID = notes.activeID
                        let activeCharacterCount = notes.editorInput.source.count
                        ForEach(notes.visibleNotes) { summary in
                            NoteSwitcherRow(
                                summary: summary,
                                selected: notes.switcherSelection == summary.id,
                                current: activeID == summary.id,
                                currentCharacterCount: activeCharacterCount,
                                editing: notes.switcherEditingID == summary.id,
                                titleDraft: notes.switcherTitleDraftBinding,
                                onActivate: { notes.activateSwitcherNote(summary.id) },
                                onBeginRename: {
                                    notes.beginSwitcherRename(summary)
                                    searchFocused = false
                                },
                                onCommitRename: notes.commitSwitcherRename,
                                onCancelRename: notes.cancelSwitcherRename,
                                onTrash: { notes.trash(summary.id) })
                                .id(summary.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
                }
                .modifier(NoteSwitcherEdgeDissolve())
                .thinScrollbar()
                .onChange(of: notes.switcherSelection) { _, selected in
                    if let selected { proxy.scrollTo(selected, anchor: .center) }
                }
                .onAppear {
                    guard let selected = notes.switcherSelection else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
        }
    }

    private func focusSearch() {
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

}

private struct NoteSwitcherEdgeDissolve: ViewModifier {
    // The compact card has no overlapping footer, so it needs less fade than the palette list.
    private let fade: CGFloat = Theme.Size.noteSwitcherHeaderHeight
    private let minimumAlpha: CGFloat = 0.25

    @State private var topDistance: CGFloat = 0
    @State private var bottomDistance: CGFloat = 0
    @State private var canScroll = false

    private struct ScrollState: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var canScroll: Bool
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                let visibleHeight = geometry.containerSize.height
                    - geometry.contentInsets.top - geometry.contentInsets.bottom
                return ScrollState(
                    top: geometry.contentOffset.y + geometry.contentInsets.top,
                    bottom: geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.containerSize.height - geometry.contentOffset.y,
                    canScroll: geometry.contentSize.height > visibleHeight
                )
            } action: { _, state in
                topDistance = max(0, state.top)
                bottomDistance = max(0, state.bottom)
                canScroll = state.canScroll
            }
            .mask {
                GeometryReader { geometry in
                    LinearGradient(
                        stops: stops(height: geometry.size.height),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard canScroll, height > 0 else { return [.init(color: .black, location: 0)] }
        let topAlpha = edgeAlpha(distance: topDistance)
        let bottomAlpha = edgeAlpha(distance: bottomDistance)
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(topAlpha), location: fade / 2 / height),
            .init(color: .black, location: fade / height),
            .init(color: .black, location: 1 - fade / height),
            .init(color: .black.opacity(bottomAlpha), location: 1 - fade / 2 / height),
            .init(color: .black.opacity(0), location: 1)
        ]
    }

    private func edgeAlpha(distance: CGFloat) -> CGFloat {
        1 - (1 - minimumAlpha) * min(distance / fade, 1)
    }
}

private struct NoteSwitcherRow: View {
    @Environment(NotesCoordinator.self) private var notes
    let summary: NoteSummary
    let selected: Bool
    let current: Bool
    let currentCharacterCount: Int
    let editing: Bool
    @Binding var titleDraft: String
    let onActivate: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onTrash: () -> Void
    @State private var hovered = false
    @FocusState private var titleFocused: Bool

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if editing {
                    TextField("Note title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit(onCommitRename)
                        .onExitCommand(perform: onCancelRename)
                } else {
                    Text(summary.title)
                        .font(Theme.Typography.rowTitle)
                        .lineLimit(1)
                }
                metadata
                    .font(Theme.Typography.noteMetadata)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            if !editing, selected || hovered {
                rowButton(title: "Rename \(summary.title)", symbol: "pencil", action: onBeginRename)
                rowButton(title: "Move \(summary.title) to Trash", symbol: "trash", action: onTrash)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            onActivate()
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active:
                hovered = notes.switcherHoverHighlightArmed
            case .ended:
                hovered = false
            }
        }
        .onChange(of: notes.switcherHoverDisarmRevision) { _, _ in hovered = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(summary.title), \(metadataLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction {
            guard !editing else { return }
            onActivate()
        }
        .accessibilityAction(named: "Rename (summary.title)") {
            guard !editing else { return }
            onBeginRename()
        }
        .accessibilityAction(named: "Move (summary.title) to Trash") {
            guard !editing else { return }
            onTrash()
        }
        .onChange(of: editing) { _, editing in
            if editing {
                Task { @MainActor in
                    await Task.yield()
                    titleFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if current {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(Theme.Colors.noteCurrent)
                    .frame(width: Theme.Spacing.xs, height: Theme.Spacing.xs)
                Text("Current")
                Text("•")
                Text(characterCountLabel)
            }
        } else {
            Text(metadataLabel)
        }
    }

    private var metadataLabel: String {
        guard !current else { return "Current, \(characterCountLabel)" }
        let modified = Self.relativeFormatter.localizedString(
            for: summary.modifiedAt,
            relativeTo: .now)
        let size = Int64(summary.byteCount).formatted(.byteCount(style: .file))
        return "Modified \(modified) • \(size)"
    }

    private var characterCountLabel: String {
        "\(currentCharacterCount.formatted()) "
            + (currentCharacterCount == 1 ? "character" : "characters")
    }

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func rowButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

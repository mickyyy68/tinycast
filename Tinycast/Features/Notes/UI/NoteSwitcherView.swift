import SwiftUI

struct NoteSwitcherView: View {
    @Environment(NotesCoordinator.self) private var notes
    @FocusState private var searchFocused: Bool
    @State private var editingID: NoteID?
    @State private var titleDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.Colors.separator)
            sectionLabel
            results
        }
        .onAppear(perform: focusSearch)
        .onChange(of: notes.switcherFocusRevision) { _, _ in focusSearch() }
        .onChange(of: notes.visibleNotes.map(\.id)) { _, _ in
            notes.reconcileSwitcherSelection()
        }
        .onKeyPress(.downArrow) {
            notes.moveSwitcherSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            notes.moveSwitcherSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard editingID == nil else { return .ignored }
            notes.selectSwitcherNote()
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("Search notes…", text: notes.searchQueryBinding)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search Notes")
            if !notes.searchQueryBinding.wrappedValue.isEmpty {
                Button {
                    notes.searchQueryBinding.wrappedValue = ""
                } label: {
                    SymbolImage(name: "xmark.circle.fill", size: Theme.Size.noteStatus)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.noteHeaderHeight)
    }

    private var sectionLabel: some View {
        Text("Notes")
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.md)
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
                                editing: editingID == summary.id,
                                titleDraft: $titleDraft,
                                onActivate: { notes.select(summary.id) },
                                onBeginRename: { beginRename(summary) },
                                onCommitRename: { commitRename(summary.id) },
                                onCancelRename: cancelRename,
                                onTrash: { notes.trash(summary.id) })
                                .id(summary.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
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

    private func beginRename(_ summary: NoteSummary) {
        editingID = summary.id
        titleDraft = summary.title
        searchFocused = false
    }

    private func commitRename(_ id: NoteID) {
        let title = titleDraft
        editingID = nil
        notes.rename(id, to: title)
        focusSearch()
    }

    private func cancelRename() {
        editingID = nil
        focusSearch()
    }
}

private struct NoteSwitcherRow: View {
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
                    .font(.caption)
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
        .onHover { hovered = $0 }
        .accessibilityElement(children: editing ? .contain : .combine)
        .accessibilityLabel("\(summary.title), \(metadataLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

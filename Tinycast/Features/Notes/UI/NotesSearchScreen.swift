import SwiftUI

struct NotesSearchScreen: PaletteScreen {
    private struct PreviewRequest: Equatable {
        let id: NoteID?
        let resultsRevision: Int
    }

    let session: NotesSearchSession
    let store: NotesStore
    let notes: NotesCoordinator
    let vm: PaletteState

    var rows: [NoteSummary] { session.visibleNotes }
    var primaryActionTitle: String { "Open Note" }

    private func note(at selection: Int) -> NoteSummary? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        note(at: selection) != nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? { nil }

    func activate(at selection: Int) {
        guard let note = note(at: selection) else { return }
        notes.openSearchResult(note.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let selected = note(at: selection)
        return AnyView(
            content(selected: selected, scroll: scroll)
                .onAppear { session.requestPreview(selected?.id) }
                .onChange(of: PreviewRequest(
                    id: selected?.id,
                    resultsRevision: session.resultsRevision)
                ) { previous, current in
                    if previous.id == current.id {
                        session.refreshPreview(current.id)
                    } else {
                        session.requestPreview(current.id)
                    }
                }
                .onChange(of: store.summaries) { _, _ in session.synchronizeSummaries() }
                .onChange(of: store.source) { _, _ in session.refreshActivePreview() }
        )
    }

    @ViewBuilder
    private func content(selected: NoteSummary?, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: session.isSearching ? "Searching notes…" : "No notes found")
        } else {
            HStack(spacing: 0) {
                NotesSearchList(
                    results: rows,
                    grouped: NoteSearch.Query(session.query).isEmpty,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { note in vm.selection = rows.firstIndex(of: note) ?? 0 },
                    onActivate: { note in notes.openSearchResult(note.id) }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
                NotesSearchPreview(session: session)
            }
        }
    }
}

private struct NotesSearchList: View {
    let results: [NoteSummary]
    let grouped: Bool
    let selectedID: NoteID?
    let scroll: ScrollIntent
    let onSelect: (NoteSummary) -> Void
    let onActivate: (NoteSummary) -> Void

    private enum Row: Identifiable {
        case header(String)
        case note(NoteSummary)

        var id: String {
            switch self {
            case .header(let title): "header-" + title
            case .note(let note): note.id.rawValue
            }
        }
    }

    private var rows: [Row] {
        guard grouped else { return results.map(Row.note) }
        var rows: [Row] = []
        var currentTitle: String?
        for note in results {
            let title = DateBucket(for: note.modifiedAt).title
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            rows.append(.note(note))
        }
        return rows
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .note(let note):
                            NotesSearchRow(note: note, selected: note.id == selectedID)
                                .selectionFrame(note.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(note) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded { onActivate(note) }
                                )
                                .id(note.id.rawValue)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll,
                row: selectedID?.rawValue,
                atOrigin: firstRowSelected,
                proxy: proxy)
        }
    }
}

private struct NotesSearchRow: View {
    let note: NoteSummary
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "text.page", size: Theme.Size.noteStatus)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(note.title)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NotesSearchPreview: View {
    let session: NotesSearchSession

    var body: some View {
        Group {
            switch session.previewState {
            case .idle:
                Color.clear
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                NotePreviewView(source: session.previewSource ?? "")
            case .unavailable:
                VStack(spacing: Theme.Spacing.md) {
                    SymbolImage(name: "exclamationmark.triangle", size: Theme.Size.rowIcon)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("Preview unavailable")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

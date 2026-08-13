import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes
    @State private var headerHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Theme.Size.noteHeaderHeight)
            if notes.isSwitcherPresented {
                NoteSwitcherView()
            } else {
                NoteEditorView(
                    input: notes.editorInput,
                    onSourceChange: notes.updateSource,
                    onContentHeightChange: notes.updateEditorHeight,
                    onReady: notes.editorReady,
                    onOpenLink: notes.openLink)
            }
            footer
                .frame(height: Theme.Size.noteFooterHeight, alignment: .bottom)
                .zIndex(notes.isFormattingPresented ? 1 : 0)
        }
        .coordinateSpace(name: "notes-window")
        .animation(.easeOut(duration: 0.12), value: notes.isFormattingPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.note, style: .continuous))
        .onChange(of: notes.noteSummaries) { _, _ in
            notes.synchronizeSearch()
        }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: Theme.Spacing.md) {
                statusView
                    .opacity(showsStatus ? 1 : 0)
                    .allowsHitTesting(status.actionable && showsStatus)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .windowDraggable(
                        true,
                        onBegan: {},
                        onEnded: notes.dragEnded)
                HStack(spacing: Theme.Spacing.md) {
                    headerButton(
                        title: "Create Note",
                        symbol: "plus",
                        action: notes.createNote)
                    headerButton(
                        title: "Reveal in Finder",
                        symbol: "folder",
                        action: notes.revealInFinder)
                    headerButton(
                        title: "Hide Notes",
                        symbol: "xmark",
                        action: notes.hide)
                }
                .opacity(headerHovered ? 1 : 0)
                .allowsHitTesting(headerHovered)
            }
            Button(action: notes.openSwitcher) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(notes.activeTitle)
                        .font(Theme.Typography.noteTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: Theme.Size.noteWidth / 2 - Theme.Spacing.xxl * 2)
            .accessibilityLabel("Choose Note")
        }
        .padding(.leading, Theme.Spacing.xl)
        .padding(.trailing, Theme.Spacing.md)
        .animation(.easeOut(duration: Theme.Duration.exit), value: headerHovered)
        .onHover { headerHovered = $0 }
    }

    private var footer: some View {
        ZStack(alignment: .bottom) {
            if notes.isFormattingPresented, !notes.isSwitcherPresented {
                NoteFormattingMenu(
                    selectedCommands: notes.activeFormattingCommands,
                    onSelect: notes.applyFormatting,
                    onDismiss: notes.toggleFormatting)
                    .fixedSize()
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("notes-window"))
                    } action: { frame in
                        notes.updateFormattingFrame(frame)
                    }
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                Text(characterCountLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                HStack {
                    Spacer()
                    if !notes.isSwitcherPresented {
                        headerButton(
                            title: "Show Format Buttons",
                            symbol: "textformat",
                            action: notes.toggleFormatting)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    private var characterCountLabel: String {
        let count = notes.editorInput.source.count
        return "\(count.formatted()) \(count == 1 ? "character" : "characters")"
    }

    private var showsStatus: Bool {
        headerHovered || status.actionable || notes.state != .ready || notes.isDirty
    }

    @ViewBuilder
    private var statusView: some View {
        if status.actionable {
            Button(action: notes.showCurrentIssue) {
                statusSymbol
            }
            .buttonStyle(.plain)
        } else {
            statusSymbol
        }
    }

    private var statusSymbol: some View {
        SymbolImage(name: status.symbol, size: Theme.Size.noteStatus)
            .foregroundStyle(status.color)
            .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
            .accessibilityLabel(status.label)
    }

    private func headerButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Circle())
                .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
        .frosted(in: Circle())
    }

    private var status: NoteStatus {
        switch notes.state {
        case .idle, .loading:
            return NoteStatus(symbol: "clock", label: "Loading", color: Theme.Colors.textSecondary)
        case .ready:
            if notes.isDirty {
                return NoteStatus(
                    symbol: "circle.dotted",
                    label: "Waiting to Save",
                    color: Theme.Colors.textSecondary)
            }
            return NoteStatus(
                symbol: "checkmark.circle",
                label: "Saved",
                color: Theme.Colors.textSecondary)
        case .saving:
            return NoteStatus(
                symbol: "arrow.triangle.2.circlepath",
                label: "Saving",
                color: Theme.Colors.textSecondary)
        case .conflict:
            return NoteStatus(
                symbol: "exclamationmark.triangle.fill",
                label: "Save Conflict",
                color: Theme.Colors.destructive,
                actionable: true)
        case .failed:
            return NoteStatus(
                symbol: "exclamationmark.circle.fill",
                label: "Note Error",
                color: Theme.Colors.destructive,
                actionable: true)
        }
    }
}

private struct NoteStatus {
    let symbol: String
    let label: String
    let color: Color
    var actionable = false
}

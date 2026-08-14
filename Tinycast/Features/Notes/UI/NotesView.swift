import SwiftUI

struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes
    @State private var panelHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Theme.Size.noteHeaderHeight)
            editorRegion
            footer
                .frame(height: Theme.Size.noteFooterHeight, alignment: .bottom)
                .zIndex(notes.isFormattingExpanded ? 2 : 0)
        }
        .animation(.easeOut(duration: Theme.Duration.exit), value: notes.isFormattingExpanded)
        .animation(.easeOut(duration: Theme.Duration.exit), value: chromeEmphasized)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.note, style: .continuous))
        .onHover { panelHovered = $0 }
        .onChange(of: notes.noteSummaries) { _, _ in
            notes.synchronizeSearch()
        }
    }

    private var editorRegion: some View {
        ZStack {
            NoteEditorView(
                input: notes.editorInput,
                onSourceChange: notes.updateSource,
                onContentHeightChange: notes.updateEditorHeight,
                onFormattingStateChange: notes.updateFormattingState,
                onReady: notes.editorReady,
                onOpenLink: notes.openLink)
                .allowsHitTesting(!notes.isSwitcherPresented)
                .accessibilityHidden(notes.isSwitcherPresented)

            if notes.isSwitcherPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { notes.closeSwitcher() }
                    .accessibilityHidden(true)
                NoteSwitcherView()
                    .frame(width: Theme.Size.noteSwitcherWidth)
                    .frame(maxHeight: Theme.Size.noteSwitcherMaximumHeight)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(
                            cornerRadius: Theme.Radius.menuPanel,
                            style: .continuous))
                    .padding(Theme.Spacing.xl)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: Theme.Duration.exit), value: notes.isSwitcherPresented)
    }

    private var header: some View {
        ZStack {
            Color.clear
                .windowDraggable(
                    true,
                    onBegan: {},
                    onEnded: notes.dragEnded)

            HStack {
                hideControl
                Spacer()
                trailingActions
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .opacity(chromeOpacity)

            Text(notes.activeTitle)
                .font(Theme.Typography.noteTitle)
                .lineLimit(1)
                .opacity(chromeOpacity)
                .overlay(alignment: .trailing) {
                    statusView
                        .offset(x: Theme.Size.noteStatus + Theme.Spacing.xs)
                        .opacity(status.actionable ? 1 : chromeOpacity)
                }
                .frame(
                    maxWidth: Theme.Size.noteWidth / 2
                        - Theme.Size.noteStatus
                        - Theme.Spacing.xxl)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var hideControl: some View {
        Button(action: notes.hide) {
            Circle()
                .fill(chromeEmphasized ? Theme.Colors.destructive : Theme.Colors.textTertiary)
                .frame(
                    width: Theme.Size.noteCloseIndicator,
                    height: Theme.Size.noteCloseIndicator)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hide Notes")
        .accessibilityLabel("Hide Notes")
    }

    private var trailingActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            actionButton(
                title: "Reveal in Finder",
                symbol: "folder",
                action: notes.revealInFinder)
            actionButton(
                title: "Choose Note",
                symbol: "rectangle.stack",
                action: notes.openSwitcher)
            actionButton(
                title: "Create Note",
                symbol: "plus",
                action: notes.createNote)
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private var footer: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .accessibilityHidden(true)

            if notes.isFormattingExpanded {
                NoteFormattingMenu(
                    selectedCommands: notes.activeFormattingCommands,
                    isInteractive: notes.isFormattingInteractive,
                    onSelect: notes.applyFormatting)
                    .fixedSize()
                    .opacity(notes.isFormattingInteractive ? chromeOpacity : 1)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .bottom)))
                    .padding(.bottom, Theme.Spacing.md)

                HStack {
                    Spacer()
                    circularButton(
                        title: "Hide Format Buttons",
                        symbol: "xmark",
                        enabled: notes.isFormattingInteractive,
                        action: notes.dismissFormatting)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            } else {
                Text(characterCountLabel)
                    .font(Theme.Typography.noteMetadata)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(chromeOpacity)
                HStack {
                    Spacer()
                    circularButton(
                        title: "Show Format Buttons",
                        symbol: "textformat",
                        enabled: !notes.isSwitcherPresented,
                        action: notes.toggleFormatting)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    private var characterCountLabel: String {
        let count = notes.editorInput.source.count
        return "\(count.formatted()) \(count == 1 ? "character" : "characters")"
    }

    private var chromeEmphasized: Bool {
        panelHovered || notes.isWindowKey
    }

    private var chromeOpacity: CGFloat {
        chromeEmphasized ? 1 : Theme.Opacity.noteInactiveChrome
    }

    private var showsStatus: Bool {
        status.actionable || notes.state != .ready || notes.isDirty
    }

    @ViewBuilder
    private var statusView: some View {
        if showsStatus {
            if status.actionable {
                Button(action: notes.showCurrentIssue) {
                    statusSymbol
                }
                .buttonStyle(.plain)
            } else {
                statusSymbol
            }
        }
    }

    private var statusSymbol: some View {
        SymbolImage(name: status.symbol, size: Theme.Size.noteStatus)
            .foregroundStyle(status.color)
            .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
            .accessibilityLabel(status.label)
    }

    private func actionButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func circularButton(
        title: String,
        symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frosted(in: Circle())
        .disabled(!enabled)
        .opacity(enabled ? chromeOpacity : Theme.Opacity.noteDisabledControl)
        .help(title)
        .accessibilityLabel(title)
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

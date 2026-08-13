import AppKit
import SwiftUI

@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    enum ResizeAnchor {
        case top
        case center
    }

    enum HeightBehavior: Equatable {
        case fitContent
        case trackContent
        case preserve
    }

    private static let frameAutosaveName = "Tinycast Floating Note"

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private weak var editor: NoteTextView?
    private var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?
    private var editorHeight: CGFloat = 0
    private var editorGrowthPadding: CGFloat = 0
    private(set) var isSuspended = false
    private var suspendedVisibleFrame: CGRect?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        initialEditorHeight: CGFloat,
        focusEditor: Bool,
        activate: Bool = true,
        resizeAnchor: ResizeAnchor = .top,
        heightBehavior: HeightBehavior = .fitContent
    ) {
        let wasVisible = panel?.isVisible == true
        if !wasVisible, !isSuspended { captureFocusTarget() }
        let preferredVisibleFrame = isSuspended ? suspendedVisibleFrame : nil
        isSuspended = false
        suspendedVisibleFrame = nil
        editorHeight = initialEditorHeight
        if heightBehavior == .fitContent { editorGrowthPadding = 0 }
        let panel = ensurePanel()
        position(
            panel,
            restoreSavedFrame: panel.frame.origin == .zero,
            preferredVisibleFrame: preferredVisibleFrame,
            resizeAnchor: resizeAnchor,
            heightBehavior: heightBehavior)
        if heightBehavior == .fitContent {
            editorGrowthPadding = NoteWindowLayout.editorGrowthPadding(
                initialEditorContentHeight: initialEditorHeight,
                initialPanelHeight: panel.frame.height,
                metrics: Self.metrics)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        if activate {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            if focusEditor { self.focusEditor(in: panel) }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func suspend() {
        guard let panel, panel.isVisible else { return }
        suspendedVisibleFrame = panel.screen?.visibleFrame
        isSuspended = true
        setFormattingInteractionActive(false)
        panel.orderOut(nil)
        coordinator.setWindowKey(false)
    }

    func abandonSuspension() {
        isSuspended = false
        suspendedVisibleFrame = nil
    }

    func hide(restoreFocus: Bool) {
        abandonSuspension()
        setFormattingInteractionActive(false)
        panel?.orderOut(nil)
        coordinator.setWindowKey(false)
        guard restoreFocus else { return }
        if let previousOwnWindow, previousOwnWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            previousOwnWindow.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    func updateEditorHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        editorHeight = height
        guard let panel else { return }
        position(panel, restoreSavedFrame: false, heightBehavior: .trackContent)
    }

    func editorReady(_ textView: NoteTextView) {
        editor = textView
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    func focusEditor() {
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    func perform(_ command: NoteMarkdownCommand) {
        guard let editor else { return }
        editor.editorActions?.noteTextView(editor, perform: command)
        focusEditor()
    }

    func formattingState() -> Set<NoteMarkdownCommand> {
        guard let editor else { return [.normal] }
        return editor.editorActions?.noteTextViewFormattingState(editor) ?? [.normal]
    }

    func setFormattingInteractionActive(_ active: Bool) {
        editor?.keepsProjectionOnFocusLoss = active
        guard !active, let editor, panel?.firstResponder !== editor else { return }
        editor.editorActions?.noteTextViewFocusChanged(editor, isFocused: false)
    }

    func saveFrame() {
        guard let panel else { return }
        position(panel, restoreSavedFrame: false, heightBehavior: .preserve)
        panel.saveFrame(usingName: Self.frameAutosaveName)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        coordinator.setWindowKey(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        coordinator.setWindowKey(false)
    }

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NotesView().environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(content: hosting)
        panel.onHide = { [weak coordinator] in coordinator?.hide() }
        panel.onEscape = { [weak coordinator] in coordinator?.handleEscape() }
        panel.onCreate = { [weak coordinator] in coordinator?.createNote() }
        panel.onSearch = { [weak coordinator] in coordinator?.openSwitcher() }
        panel.onDelete = { [weak coordinator] in coordinator?.trashSwitcherSelection() }
        panel.delegate = self
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        self.panel = panel
        return panel
    }

    private func position(
        _ panel: NotesPanel,
        restoreSavedFrame: Bool,
        preferredVisibleFrame: CGRect? = nil,
        resizeAnchor: ResizeAnchor = .top,
        heightBehavior: HeightBehavior = .fitContent
    ) {
        let restored = restoreSavedFrame && panel.setFrameUsingName(Self.frameAutosaveName)
        let visibleFrame = preferredVisibleFrame
            ?? panel.screen?.visibleFrame
            ?? screenContaining(panel.frame)?.visibleFrame
            ?? NSScreen.underCursor?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }
        let constrainedVisibleFrame = NoteWindowLayout.constrainedVisibleFrame(
            visibleFrame,
            metrics: Self.metrics)
        let height: CGFloat = switch heightBehavior {
        case .fitContent:
            NoteWindowLayout.panelHeight(
                editorContentHeight: editorHeight,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        case .trackContent:
            NoteWindowLayout.contentTrackingPanelHeight(
                editorContentHeight: editorHeight,
                editorGrowthPadding: editorGrowthPadding,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        case .preserve:
            NoteWindowLayout.preservedPanelHeight(
                panel.frame.height,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        }
        let frame: CGRect
        if restored || panel.frame.origin != .zero {
            switch resizeAnchor {
            case .top:
                frame = NoteWindowLayout.resizedFrame(
                    currentFrame: panel.frame,
                    height: height,
                    visibleFrame: constrainedVisibleFrame,
                    width: Theme.Size.noteWidth)
            case .center:
                frame = NoteWindowLayout.centeredFrame(
                    currentFrame: panel.frame,
                    height: height,
                    visibleFrame: constrainedVisibleFrame,
                    width: Theme.Size.noteWidth)
            }
        } else {
            frame = NoteWindowLayout.initialFrame(
                visibleFrame: constrainedVisibleFrame,
                height: height,
                width: Theme.Size.noteWidth,
                centerLiftFraction: Theme.Size.noteCenterLiftFraction)
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible, animate: false)
        }
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func captureFocusTarget() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApp = nil
            if let keyWindow = NSApp.keyWindow, keyWindow !== panel {
                previousOwnWindow = keyWindow
            }
        } else {
            previousApp = frontmost
            previousOwnWindow = nil
        }
    }

    private func focusEditor(in panel: NotesPanel) {
        guard let editor else { return }
        panel.makeFirstResponder(editor)
        Task { @MainActor [weak panel, weak editor] in
            await Task.yield()
            guard let panel, panel.isVisible, let editor else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(editor)
        }
    }

    private static let metrics = NoteWindowLayout.Metrics(
        width: Theme.Size.noteWidth,
        minimumHeight: Theme.Size.noteMinimumHeight,
        maximumHeight: Theme.Size.noteMaximumHeight,
        screenMargin: Theme.Size.noteScreenMargin,
        fixedContentHeight: Theme.Size.noteHeaderHeight + Theme.Size.noteFooterHeight)
}

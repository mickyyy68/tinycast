import AppKit
import SwiftUI

@MainActor
final class NotesWindowController: NSObject {
    enum ResizeAnchor {
        case top
        case center
    }

    enum HeightBehavior {
        case fitContent
        case growOnly
        case preserve
    }

    private static let frameAutosaveName = "Tinycast Floating Note"

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private weak var editor: NoteTextView?
    private var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?
    private var editorHeight: CGFloat = 0
    private var formattingFrame: CGRect?
    private var formattingMonitor: Any?
    private(set) var isSuspended = false
    private var suspendedVisibleFrame: CGRect?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    isolated deinit {
        if let formattingMonitor { NSEvent.removeMonitor(formattingMonitor) }
    }

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
        let panel = ensurePanel()
        position(
            panel,
            restoreSavedFrame: panel.frame.origin == .zero,
            preferredVisibleFrame: preferredVisibleFrame,
            resizeAnchor: resizeAnchor,
            heightBehavior: heightBehavior)
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
        panel.orderOut(nil)
    }

    func abandonSuspension() {
        isSuspended = false
        suspendedVisibleFrame = nil
    }

    func hide(restoreFocus: Bool) {
        abandonSuspension()
        panel?.orderOut(nil)
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
        position(panel, restoreSavedFrame: false, heightBehavior: .growOnly)
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

    func updateFormattingFrame(_ frame: CGRect) {
        formattingFrame = frame
    }

    func setFormattingPresented(_ presented: Bool) {
        editor?.keepsProjectionOnFocusLoss = presented
        if !presented {
            if let formattingMonitor { NSEvent.removeMonitor(formattingMonitor) }
            formattingMonitor = nil
            formattingFrame = nil
            if let editor, panel?.firstResponder !== editor {
                editor.editorActions?.noteTextViewFocusChanged(editor, isFocused: false)
            }
            return
        }
        guard formattingMonitor == nil else { return }
        formattingMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            let insideMenu: Bool
            if event.window === panel, let panel, let formattingFrame {
                let appKitFrame = CGRect(
                    x: formattingFrame.minX,
                    y: (panel.contentView?.bounds.height ?? 0) - formattingFrame.maxY,
                    width: formattingFrame.width,
                    height: formattingFrame.height)
                insideMenu = appKitFrame.contains(event.locationInWindow)
            } else {
                insideMenu = false
            }
            if !insideMenu {
                Task { @MainActor [weak coordinator] in coordinator?.dismissFormatting() }
            }
            return event
        }
    }

    func saveFrame() {
        panel?.saveFrame(usingName: Self.frameAutosaveName)
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
        let height: CGFloat = switch heightBehavior {
        case .fitContent:
            NoteWindowLayout.panelHeight(
                editorContentHeight: editorHeight,
                visibleScreenHeight: visibleFrame.height,
                metrics: Self.metrics)
        case .growOnly:
            NoteWindowLayout.growOnlyPanelHeight(
                editorContentHeight: editorHeight,
                currentPanelHeight: panel.frame.height,
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
                    visibleFrame: visibleFrame,
                    width: Theme.Size.noteWidth)
            case .center:
                frame = NoteWindowLayout.centeredFrame(
                    currentFrame: panel.frame,
                    height: height,
                    visibleFrame: visibleFrame,
                    width: Theme.Size.noteWidth)
            }
        } else {
            frame = CGRect(
                x: visibleFrame.midX - Theme.Size.noteWidth / 2,
                y: visibleFrame.midY
                    + visibleFrame.height * Theme.Size.noteCenterLiftFraction - height / 2,
                width: Theme.Size.noteWidth,
                height: height)
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
        maximumScreenFraction: Theme.Size.noteMaximumScreenFraction,
        fixedContentHeight: Theme.Size.noteHeaderHeight)
}

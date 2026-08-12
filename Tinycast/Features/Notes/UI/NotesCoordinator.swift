import AppKit
import SwiftUI

@MainActor
@Observable
final class NotesCoordinator {
    typealias FailureReporter = (
        _ title: String,
        _ message: String,
        _ symbol: String,
        _ recovery: String?
    ) async -> Bool
    typealias TrashConfirmer = (_ title: String) async -> Bool

    private enum Presentation: Equatable {
        case editor
        case create
        case searchPalette
    }

    private let store: NotesStore
    private let search: NotesSearchSession
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let reportFailure: FailureReporter
    private let confirmTrash: TrashConfirmer
    private let showMessage: (_ message: String, _ tone: DialogTone) -> Void
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var isSwitcherPresented = false
    private(set) var isFormattingPresented = false {
        didSet {
            guard oldValue != isFormattingPresented else { return }
            windowController.setFormattingPresented(isFormattingPresented)
        }
    }
    private(set) var activeFormattingCommands: Set<NoteMarkdownCommand> = [.normal]
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0
    private var restoresEditorAfterSearch = false

    init(
        store: NotesStore,
        search: NotesSearchSession,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        reportFailure: @escaping FailureReporter,
        confirmTrash: @escaping TrashConfirmer,
        showMessage: @escaping (_ message: String, _ tone: DialogTone) -> Void
    ) {
        self.store = store
        self.search = search
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.reportFailure = reportFailure
        self.confirmTrash = confirmTrash
        self.showMessage = showMessage
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.search.query ?? "" },
            set: { [weak self] in self?.search.updateQuery($0) })
    }

    var state: NotesStore.State { store.state }
    var isDirty: Bool { store.isDirty }
    var activeTitle: String { store.activeTitle }
    var activeID: NoteID? { store.activeID }
    var isSearching: Bool { search.isSearching }
    var visibleNotes: [NoteSummary] { search.visibleNotes }
    var noteSummaries: [NoteSummary] { store.summaries }

    func synchronizeSearch() {
        search.updateSummaries()
    }

    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setNotesCommandsVisible(settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        isFormattingPresented = false
        pendingPresentation = nil
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        restoresEditorAfterSearch = false
        search.cancel()
        if palette.mode == .notesSearch { palette.prepare(mode: .launcher) }
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: false)
        Task { [weak self] in
            guard let self else { return }
            _ = await store.flush()
            guard generation == enablementGeneration, !settings.notesEnabled else { return }
            store.stop()
        }
    }

    func show() {
        request(.editor)
    }

    func createNote() {
        request(.create)
    }

    func searchNotes() {
        request(.searchPalette)
    }

    func openSwitcher() {
        guard settings.notesEnabled, store.hasLoadedDocument else { return }
        isFormattingPresented = false
        isSwitcherPresented = true
        search.begin()
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !search.query.isEmpty else { return }
        isSwitcherPresented = false
        switcherSelection = nil
        search.cancel()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        pendingPresentation = nil
        isFormattingPresented = false
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    func handleEscape() {
        if isFormattingPresented {
            isFormattingPresented = false
            windowController.focusEditor()
        } else if isSwitcherPresented {
            closeSwitcher()
        } else {
            hide()
        }
    }

    func updateSwitcherSelection(_ id: NoteID?) {
        switcherSelection = id
    }

    func reconcileSwitcherSelection() {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        if let switcherSelection, notes.contains(where: { $0.id == switcherSelection }) { return }
        switcherSelection = notes.first?.id
    }

    func moveSwitcherSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        guard let current = switcherSelection,
            let index = notes.firstIndex(where: { $0.id == current })
        else {
            switcherSelection = notes[offset < 0 ? notes.count - 1 : 0].id
            return
        }
        switcherSelection = notes[(index + offset + notes.count) % notes.count].id
    }

    func selectSwitcherNote() {
        guard let switcherSelection else { return }
        select(switcherSelection)
    }

    func select(_ id: NoteID) {
        guard operationTask == nil else { return }
        isFormattingPresented = false
        operationTask = Task { [weak self] in
            guard let self else { return }
            let selected = await store.select(id)
            operationTask = nil
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        }
    }

    func openSearchResult(_ id: NoteID) {
        guard settings.notesEnabled, operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            let selected = await store.select(id)
            operationTask = nil
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            restoresEditorAfterSearch = false
            search.cancel()
            paletteCoordinator.hidePalette(restoreFocus: false)
            showLoadedNote(focusEditor: true, resizeAnchor: .center)
        }
    }

    func paletteDidDismiss(_ mode: PaletteMode, restoreFocus: Bool) -> Bool {
        guard mode == .notesSearch else { return false }
        search.cancel()
        guard restoresEditorAfterSearch, settings.notesEnabled, store.hasLoadedDocument else {
            restoresEditorAfterSearch = false
            return false
        }
        restoresEditorAfterSearch = false
        showLoadedNote(focusEditor: restoreFocus, activate: restoreFocus)
        return true
    }

    func leaveSearchPalette() {
        restoresEditorAfterSearch = false
        search.cancel()
    }

    func rename(_ id: NoteID, to title: String) {
        guard operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            operationTask = nil
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            search.synchronize()
            if renamedID == store.activeID { showLoadedNote(focusEditor: false) }
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func trash(_ id: NoteID) {
        guard operationTask == nil,
            let title = store.summaries.first(where: { $0.id == id })?.title
        else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            let confirmed = await confirmTrash(title)
            guard confirmed, settings.notesEnabled, !Task.isCancelled else {
                operationTask = nil
                return
            }
            let removed = await store.trash(id)
            operationTask = nil
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = store.activeID ?? store.summaries.first?.id
            search.synchronize()
            showLoadedNote(focusEditor: !isSwitcherPresented)
        }
    }

    func revealInFinder() {
        guard let fileURL = store.activeFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func toggleFormatting() {
        guard settings.notesEnabled, store.hasLoadedDocument, !isSwitcherPresented else { return }
        if !isFormattingPresented {
            activeFormattingCommands = windowController.formattingState()
        }
        isFormattingPresented.toggle()
    }

    func dismissFormatting() {
        isFormattingPresented = false
    }

    func updateFormattingFrame(_ frame: CGRect) {
        windowController.updateFormattingFrame(frame)
    }

    func applyFormatting(_ command: NoteMarkdownCommand) {
        guard isFormattingPresented else { return }
        windowController.perform(command)
        isFormattingPresented = false
    }

    func updateSource(_ source: String) {
        store.updateSource(source)
    }

    func openLink(_ raw: String) {
        guard let directory = store.activeFileURL?.deletingLastPathComponent(),
            let destination = NoteLinkDestination.resolve(raw, relativeTo: directory)
        else { return }
        Task { [weak self] in
            do {
                try await NoteLinkLauncher.open(destination)
            } catch {
                guard let self else { return }
                _ = await reportFailure(
                    "Couldn't Open Link",
                    error.localizedDescription,
                    "link",
                    nil)
            }
        }
    }

    func updateEditorHeight(_ height: CGFloat) {
        windowController.updateEditorHeight(height)
    }

    func editorReady(_ textView: NoteTextView) {
        windowController.editorReady(textView)
    }

    func dragEnded() {
        windowController.saveFrame()
    }

    func showCurrentIssue() {
        guard let issue = store.currentIssue else { return }
        present(issue)
    }

    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        if presentation != .searchPalette, paletteCoordinator.isVisible,
            palette.mode == .notesSearch
        {
            restoresEditorAfterSearch = false
            search.cancel()
            paletteCoordinator.hidePalette(restoreFocus: false)
        }
        isFormattingPresented = false
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            if presentation == .create {
                let created = await store.create()
                guard generation == enablementGeneration else {
                    if !settings.notesEnabled { store.stop() }
                    return
                }
                loadTask = nil
                guard created, settings.notesEnabled, !Task.isCancelled else { return }
                let next = pendingPresentation
                pendingPresentation = nil
                await present(next == .create ? .editor : next ?? .editor)
                return
            }
            let loaded = await store.start()
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled,
                let presentation = pendingPresentation
            else { return }
            pendingPresentation = nil
            await present(presentation)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        case .create:
            guard await store.create() else { return }
            closeSwitcher()
            showLoadedNote(focusEditor: true)
        case .searchPalette:
            closeSwitcher(focusEditor: false)
            restoresEditorAfterSearch = windowController.isVisible
            if restoresEditorAfterSearch { windowController.suspend() }
            search.begin()
            if paletteCoordinator.isVisible {
                palette.prepare(mode: .notesSearch)
            } else {
                paletteCoordinator.showPalette(mode: .notesSearch)
            }
        }
    }

    private func showLoadedNote(
        focusEditor: Bool,
        activate: Bool = true,
        resizeAnchor: NotesWindowController.ResizeAnchor = .top
    ) {
        let editorHeight = NoteEditorView.contentHeight(
            for: store.source,
            width: Theme.Size.noteWidth)
        windowController.show(
            initialEditorHeight: editorHeight,
            focusEditor: focusEditor,
            activate: activate,
            resizeAnchor: resizeAnchor)
    }

    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await reportFailure(
                    "Couldn't Open Note",
                    failure.localizedDescription,
                    "text.page",
                    "Retry")
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await reportFailure(
                    "Couldn't Save Note",
                    failure.localizedDescription,
                    "text.page",
                    "Retry")
                if retry { store.retry() }
            case .conflict(let failure):
                let recover = await reportFailure(
                    "Note Changed on Disk",
                    failure.localizedDescription,
                    "exclamationmark.triangle",
                    "Save Copy & Reload")
                if recover { await recoverConflict() }
            case .operation(let failure):
                _ = await reportFailure(
                    "Couldn't Update Note",
                    failure.localizedDescription,
                    "text.page",
                    nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }

    private func recoverConflict() async {
        switch await store.saveConflictCopyAndReload() {
        case .success(let fileURL):
            showMessage("Draft Saved as \(fileURL.lastPathComponent)", .success)
        case .failure(let failure):
            _ = await reportFailure(
                "Couldn't Preserve Note",
                failure.localizedDescription,
                "exclamationmark.triangle",
                nil)
        }
    }
}

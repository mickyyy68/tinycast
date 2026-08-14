import Foundation

@MainActor
@Observable
final class NotesSearchSession {
    private struct SearchInput: Equatable {
        let summaries: [NoteSummary]
        let activeID: NoteID?
        let activeSource: String
    }

    enum State: Sendable, Equatable {
        case idle
        case searching
        case ready
    }

    enum PreviewState: Sendable, Equatable {
        case idle
        case loading
        case ready
        case unavailable
    }

    private(set) var query = ""
    private(set) var results: [NoteSearchResult] = []
    private(set) var resultsRevision = 0
    private(set) var state: State = .idle
    private(set) var previewID: NoteID?
    private(set) var previewSource: String?
    private(set) var previewState: PreviewState = .idle

    var visibleNotes: [NoteSummary] {
        NoteSearch.Query(query).isEmpty ? store.summaries : results.map(\.summary)
    }

    var isSearching: Bool { state == .searching }

    private unowned let store: NotesStore
    private let repository: NotesRepository
    private let debounce: Duration
    private let summaryDebounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var previewGeneration = 0
    private var synchronizedInput: SearchInput?

    init(
        store: NotesStore,
        repository: NotesRepository,
        debounce: Duration = .milliseconds(120),
        summaryDebounce: Duration = .milliseconds(400)
    ) {
        self.store = store
        self.repository = repository
        self.debounce = debounce
        self.summaryDebounce = summaryDebounce
    }

    isolated deinit {
        searchTask?.cancel()
        searchWorker?.cancel()
        previewTask?.cancel()
    }

    func begin() {
        cancel()
    }

    func updateQuery(_ updated: String) {
        let previous = NoteSearch.Query(query)
        query = updated
        let next = NoteSearch.Query(updated)
        guard previous.terms != next.terms else { return }
        synchronizedInput = currentInput()
        startSearch(next, delay: debounce)
    }

    func synchronizeSummaries() {
        let input = currentInput()
        guard input != synchronizedInput else { return }
        synchronizedInput = input
        let parsed = NoteSearch.Query(query)
        if parsed.isEmpty {
            schedulePreviewSynchronization()
            return
        }
        startSearch(parsed, delay: summaryDebounce)
    }

    func reconcileMutation() {
        let input = currentInput()
        synchronizedInput = input
        let parsed = NoteSearch.Query(query)
        if parsed.isEmpty {
            reconcilePreview(with: input)
            return
        }
        let summaries = Dictionary(uniqueKeysWithValues: store.summaries.map { ($0.id, $0) })
        results = results.compactMap { result in
            guard let summary = summaries[result.id] else { return nil }
            return NoteSearchResult(summary: summary, score: result.score, excerpt: result.excerpt)
        }
        startSearch(parsed, delay: .zero, input: input)
    }

    func requestPreview(_ id: NoteID?) {
        guard let id else {
            clearPreview()
            return
        }
        loadPreview(id, force: false)
    }

    func refreshPreview(_ id: NoteID?) {
        guard let id else {
            clearPreview()
            return
        }
        loadPreview(id, force: true)
    }

    private func loadPreview(_ id: NoteID, force: Bool) {
        if id == store.activeID {
            previewTask?.cancel()
            previewTask = nil
            previewGeneration &+= 1
            previewID = id
            previewSource = store.source
            previewState = .ready
            return
        }
        guard force || id != previewID || previewState != .ready else { return }
        previewTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration
        previewID = id
        previewSource = nil
        previewState = .loading
        let repository = repository
        previewTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try repository.load(id).source }
            }.value
            guard let self, !Task.isCancelled, generation == previewGeneration,
                previewID == id
            else { return }
            switch result {
            case .success(let source):
                previewSource = source
                previewState = .ready
            case .failure:
                previewSource = nil
                previewState = .unavailable
            }
            previewTask = nil
        }
    }

    func refreshActivePreview() {
        guard previewID == store.activeID else { return }
        previewSource = store.source
        previewState = .ready
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        searchWorker?.cancel()
        searchWorker = nil
        searchGeneration &+= 1
        synchronizedInput = nil
        query = ""
        results = []
        state = .idle
        clearPreview()
    }

    private func startSearch(
        _ parsed: NoteSearch.Query,
        delay: Duration,
        input: SearchInput? = nil
    ) {
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        guard !parsed.isEmpty else {
            results = []
            resultsRevision &+= 1
            state = .idle
            return
        }
        state = .searching
        let repository = repository
        let fixedInput = input
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let input = fixedInput ?? currentInput()
            synchronizedInput = input
            let worker = Task.detached(priority: .userInitiated) {
                Signposts.interval("Notes.search") {
                    repository.search(
                        parsed,
                        summaries: input.summaries,
                        activeID: input.activeID,
                        activeSource: input.activeSource)
                }
            }
            searchWorker = worker
            let found = await worker.value
            guard !Task.isCancelled, generation == searchGeneration else { return }
            results = found
            resultsRevision &+= 1
            state = .ready
            searchWorker = nil
            searchTask = nil
        }
    }

    private func schedulePreviewSynchronization() {
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let delay = summaryDebounce
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, generation == searchGeneration else { return }
            let input = currentInput()
            synchronizedInput = input
            reconcilePreview(with: input)
            searchTask = nil
        }
    }

    private func reconcilePreview(with input: SearchInput) {
        guard let previewID else { return }
        if input.summaries.contains(where: { $0.id == previewID }) {
            loadPreview(previewID, force: true)
        } else {
            clearPreview()
        }
    }

    private func currentInput() -> SearchInput {
        SearchInput(
            summaries: store.summaries,
            activeID: store.activeID,
            activeSource: store.source)
    }

    private func clearPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewGeneration &+= 1
        previewID = nil
        previewSource = nil
        previewState = .idle
    }
}

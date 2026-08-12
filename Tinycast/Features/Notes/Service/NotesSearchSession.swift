import Foundation

@MainActor
@Observable
final class NotesSearchSession {
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
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var previewGeneration = 0

    init(
        store: NotesStore,
        repository: NotesRepository,
        debounce: Duration = .milliseconds(120)
    ) {
        self.store = store
        self.repository = repository
        self.debounce = debounce
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
        startSearch(next)
    }

    func synchronize() {
        guard !NoteSearch.Query(query).isEmpty else {
            if let previewID, !store.summaries.contains(where: { $0.id == previewID }) {
                clearPreview()
            }
            return
        }
        startSearch(NoteSearch.Query(query))
    }

    func updateSummaries() {
        if NoteSearch.Query(query).isEmpty {
            guard let previewID else { return }
            if store.summaries.contains(where: { $0.id == previewID }) {
                loadPreview(previewID, force: true)
            } else {
                clearPreview()
            }
        } else {
            startSearch(NoteSearch.Query(query))
        }
    }

    func requestPreview(_ id: NoteID?) {
        guard let id else {
            clearPreview()
            return
        }
        loadPreview(id, force: false)
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
        query = ""
        results = []
        state = .idle
        clearPreview()
    }

    private func startSearch(_ parsed: NoteSearch.Query) {
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        results = []
        clearPreview()
        guard !parsed.isEmpty else {
            state = .idle
            return
        }
        state = .searching
        let repository = repository
        let summaries = store.summaries
        let activeID = store.activeID
        let activeSource = store.source
        let debounce = debounce
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                Signposts.interval("Notes.search") {
                    repository.search(
                        parsed,
                        summaries: summaries,
                        activeID: activeID,
                        activeSource: activeSource)
                }
            }
            searchWorker = worker
            let found = await worker.value
            guard !Task.isCancelled, generation == searchGeneration else { return }
            results = found
            state = .ready
            searchWorker = nil
            searchTask = nil
        }
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

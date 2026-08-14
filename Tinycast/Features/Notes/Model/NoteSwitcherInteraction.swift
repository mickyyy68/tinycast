import Foundation

struct NoteSwitcherRenameState: Sendable, Equatable {
    private(set) var id: NoteID?
    private(set) var draft = ""

    var isActive: Bool { id != nil }

    mutating func begin(id: NoteID, title: String) {
        self.id = id
        draft = title
    }

    mutating func updateDraft(_ updated: String) {
        guard isActive else { return }
        draft = updated
    }

    mutating func cancel() {
        id = nil
        draft = ""
    }

    mutating func commit() -> (id: NoteID, title: String)? {
        guard let id else { return nil }
        let committed = (id, draft)
        cancel()
        return committed
    }
}

enum NoteShortcutPolicy {
    static func handlesDelete(switcherPresented: Bool, renameActive: Bool) -> Bool {
        switcherPresented && !renameActive
    }
}

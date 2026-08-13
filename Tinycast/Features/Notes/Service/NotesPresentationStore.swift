import Foundation

@MainActor
@Observable
final class NotesPresentationStore {
    private static let formattingExpandedKey = "notesFormattingExpanded"

    private let defaults: UserDefaults
    private(set) var isFormattingExpanded: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isFormattingExpanded = defaults.bool(forKey: Self.formattingExpandedKey)
    }

    func toggleFormatting() {
        setFormattingExpanded(!isFormattingExpanded)
    }

    func collapseFormatting() {
        setFormattingExpanded(false)
    }

    private func setFormattingExpanded(_ expanded: Bool) {
        guard expanded != isFormattingExpanded else { return }
        isFormattingExpanded = expanded
        defaults.set(expanded, forKey: Self.formattingExpandedKey)
    }
}

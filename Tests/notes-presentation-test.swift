import Foundation

@main
@MainActor
struct NotesPresentationTests {
    private static var failures = 0

    static func main() {
        let firstSuite = "com.tinycast.tests.notes-presentation.\(UUID().uuidString)"
        let secondSuite = "com.tinycast.tests.notes-presentation.\(UUID().uuidString)"
        guard let firstDefaults = UserDefaults(suiteName: firstSuite),
            let secondDefaults = UserDefaults(suiteName: secondSuite)
        else {
            print("Could not create isolated UserDefaults suites")
            exit(1)
        }
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }

        let first = NotesPresentationStore(defaults: firstDefaults)
        check("formatting starts collapsed when the key is absent", !first.isFormattingExpanded)

        first.toggleFormatting()
        check("toggling expands formatting", first.isFormattingExpanded)

        let restored = NotesPresentationStore(defaults: firstDefaults)
        check("a reconstructed store restores expansion", restored.isFormattingExpanded)

        let isolated = NotesPresentationStore(defaults: secondDefaults)
        check("another defaults domain remains collapsed", !isolated.isFormattingExpanded)

        restored.collapseFormatting()
        check("collapsing persists the new choice", !restored.isFormattingExpanded)
        check(
            "a later reconstruction sees the collapsed choice",
            !NotesPresentationStore(defaults: firstDefaults).isFormattingExpanded)

        print(failures == 0 ? "Notes presentation tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard !condition() else { return }
        failures += 1
        print("FAIL: \(message)")
    }
}

import AppKit
import SwiftUI

struct NotePreviewView: NSViewRepresentable {
    let source: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(usingTextLayoutManager: true)
        NoteTextStyler.configure(textView, editable: false)
        textView.setAccessibilityLabel("Note preview")
        scrollView.documentView = textView
        context.coordinator.source = source
        apply(source, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard source != context.coordinator.source,
            let textView = scrollView.documentView as? NSTextView
        else { return }
        context.coordinator.source = source
        apply(source, to: textView)
        textView.scrollToBeginningOfDocument(nil)
    }

    @MainActor
    final class Coordinator {
        var source = ""
    }

    private func apply(_ source: String, to textView: NSTextView) {
        let presentation = NoteMarkdownParser.parse(source)
        let projection = NoteDisplayProjection.build(
            source: source,
            presentation: presentation,
            activeSourceLocation: nil)
        NoteTextStyler.apply(projection, to: textView)
    }
}

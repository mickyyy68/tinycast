import AppKit

@MainActor
final class NotesMenuBarController: NSObject {
    private let onShow: () -> Void
    private var statusItem: NSStatusItem?

    init(onShow: @escaping () -> Void) {
        self.onShow = onShow
    }

    func apply(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "text.page",
                accessibilityDescription: "Show Notes")
            button.imagePosition = .imageOnly
            button.toolTip = "Show Notes"
            button.setAccessibilityLabel("Show Notes")
            button.target = self
            button.action = #selector(showNotes)
            button.sendAction(on: .leftMouseUp)
        }
        statusItem = item
    }

    @objc private func showNotes() {
        onShow()
    }
}

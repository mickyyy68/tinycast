import SwiftUI

struct NoteFormattingMenu: View {
    let selectedCommands: Set<NoteMarkdownCommand>
    let onSelect: (NoteMarkdownCommand) -> Void
    let onDismiss: () -> Void
    @FocusState private var focused: FocusTarget?
    @State private var expandedGroup: FormatGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let expandedGroup {
                groupMenu(expandedGroup)
                    .frame(
                        maxWidth: .infinity,
                        alignment: expandedGroup == .list ? .trailing : .leading)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .bottomLeading)))
            }
            toolbar
        }
        .animation(.easeOut(duration: Theme.Duration.exit), value: expandedGroup)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focused = initialFocus
            }
        }
        .onMoveCommand(perform: moveFocus)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note Formatting")
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            groupButton(.heading)
            groupButton(.style)
            commandButton(Item(.link, "Link", "link"))
            commandButton(
                Item(.inlineCode, "Inline Code", "chevron.left.forwardslash.chevron.right"))
            separator
            commandButton(Item(.codeBlock, "Code Block", "curlybraces"))
            commandButton(Item(.blockquote, "Quote", "text.quote"))
            commandButton(Item(.horizontalRule, "Horizontal Rule", "minus"))
            separator
            groupButton(.list)
            dismissButton
        }
        .padding(Theme.Spacing.xs)
        .glassEffect(.regular, in: Capsule())
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: 1, height: Theme.Size.noteStatus)
    }

    private func groupButton(_ group: FormatGroup) -> some View {
        Button {
            expandedGroup = expandedGroup == group ? nil : group
            focused = .command(group.representative)
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                if let symbol = group.symbol {
                    SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                } else {
                    Text(group.label)
                        .font(.caption.weight(.semibold))
                }
                SymbolImage(name: "chevron.down", size: Theme.Spacing.lg)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(
                width: Theme.Size.noteHeaderButton + Theme.Spacing.lg,
                height: Theme.Size.noteHeaderButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(buttonBackground(group.isSelected(in: selectedCommands)))
        .overlay(focusBorder(.command(group.representative)))
        .focused($focused, equals: .command(group.representative))
        .help(group.title)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(group.isSelected(in: selectedCommands) ? .isSelected : [])
    }

    private func commandButton(_ item: Item) -> some View {
        Button {
            expandedGroup = nil
            focused = .command(item.command)
            onSelect(item.command)
        } label: {
            SymbolImage(name: item.symbol ?? "textformat", size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(buttonBackground(selectedCommands.contains(item.command)))
        .overlay(focusBorder(.command(item.command)))
        .focused($focused, equals: .command(item.command))
        .help(item.label)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selectedCommands.contains(item.command) ? .isSelected : [])
    }

    private var dismissButton: some View {
        Button {
            expandedGroup = nil
            onDismiss()
        } label: {
            SymbolImage(name: "textformat", size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(buttonBackground(true))
        .overlay(focusBorder(.dismiss))
        .focused($focused, equals: .dismiss)
        .help("Hide Format Buttons")
        .accessibilityLabel("Hide Format Buttons")
        .accessibilityAddTraits(.isSelected)
    }

    private func groupMenu(_ group: FormatGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(group.items) { item in
                Button {
                    focused = .command(item.command)
                    expandedGroup = nil
                    onSelect(item.command)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if let symbol = item.symbol {
                            SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                                .frame(width: Theme.Size.noteStatus)
                        } else {
                            Color.clear
                                .frame(width: Theme.Size.noteStatus, height: Theme.Size.noteStatus)
                        }
                        Text(item.label)
                        Spacer(minLength: Theme.Spacing.md)
                        if selectedCommands.contains(item.command) {
                            SymbolImage(name: "checkmark", size: Theme.Size.noteStatus)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(buttonBackground(selectedCommands.contains(item.command)))
                .overlay(focusBorder(.command(item.command)))
                .focused($focused, equals: .command(item.command))
                .accessibilityAddTraits(
                    selectedCommands.contains(item.command) ? .isSelected : [])
            }
        }
        .frame(width: Theme.Size.noteFormattingMenuWidth)
        .padding(Theme.Spacing.xs)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
    }

    private func buttonBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
            .fill(selected ? Theme.Colors.selection : .clear)
    }

    private func focusBorder(_ target: FocusTarget) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
            .stroke(focused == target ? Theme.Colors.border : .clear, lineWidth: 1)
    }

    private var initialFocus: FocusTarget {
        for group in FormatGroup.allCases where group.isSelected(in: selectedCommands) {
            return .command(group.representative)
        }
        return toolbarTargets.first {
            guard case .command(let command) = $0 else { return false }
            return selectedCommands.contains(command)
        } ?? .command(.normal)
    }

    private var toolbarTargets: [FocusTarget] {
        [
            .command(.normal), .command(.bold), .command(.link), .command(.inlineCode),
            .command(.codeBlock), .command(.blockquote), .command(.horizontalRule),
            .command(.unorderedList), .dismiss
        ]
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard let focused else {
            self.focused = .command(.normal)
            return
        }
        if case .command(let command) = focused, let expandedGroup,
            let index = expandedGroup.items.map(\.command).firstIndex(of: command)
        {
            moveInsideGroup(expandedGroup, index: index, direction: direction)
            return
        }
        let normalized = normalizedToolbarTarget(focused)
        guard let index = toolbarTargets.firstIndex(of: normalized) else {
            self.focused = .command(.normal)
            return
        }
        switch direction {
        case .left:
            self.focused = toolbarTargets[max(0, index - 1)]
        case .right:
            self.focused = toolbarTargets[min(toolbarTargets.count - 1, index + 1)]
        case .up:
            guard case .command(let command) = normalized,
                let group = FormatGroup.allCases.first(where: { $0.representative == command })
            else { return }
            expandedGroup = group
            self.focused = .command(
                group.items.first(where: { selectedCommands.contains($0.command) })?.command
                    ?? group.items[0].command)
        case .down:
            break
        @unknown default:
            break
        }
    }

    private func moveInsideGroup(
        _ group: FormatGroup,
        index: Int,
        direction: MoveCommandDirection
    ) {
        switch direction {
        case .up:
            focused = .command(group.items[max(0, index - 1)].command)
        case .down:
            if index == group.items.count - 1 {
                expandedGroup = nil
                focused = .command(group.representative)
            } else {
                focused = .command(group.items[index + 1].command)
            }
        case .left, .right:
            expandedGroup = nil
            focused = .command(group.representative)
        @unknown default:
            break
        }
    }

    private func normalizedToolbarTarget(_ target: FocusTarget) -> FocusTarget {
        guard case .command(let command) = target else { return target }
        let group = FormatGroup.allCases.first { group in
            group.items.contains { $0.command == command }
        }
        return .command(group?.representative ?? command)
    }
}

private enum FocusTarget: Hashable {
    case command(NoteMarkdownCommand)
    case dismiss
}

private enum FormatGroup: CaseIterable {
    case heading
    case style
    case list

    var representative: NoteMarkdownCommand {
        switch self {
        case .heading: .normal
        case .style: .bold
        case .list: .unorderedList
        }
    }

    var label: String {
        switch self {
        case .heading: "H"
        case .style, .list: ""
        }
    }

    var symbol: String? {
        switch self {
        case .heading: nil
        case .style: "italic"
        case .list: "list.bullet"
        }
    }

    var title: String {
        switch self {
        case .heading: "Text Style"
        case .style: "Inline Style"
        case .list: "List Style"
        }
    }

    var items: [Item] {
        switch self {
        case .heading:
            [
                Item(.normal, "Normal", "textformat"),
                Item(.heading1, "H1", nil),
                Item(.heading2, "H2", nil),
                Item(.heading3, "H3", nil)
            ]
        case .style:
            [
                Item(.bold, "Bold", "bold"),
                Item(.italic, "Italic", "italic"),
                Item(.strikethrough, "Strikethrough", "strikethrough")
            ]
        case .list:
            [
                Item(.unorderedList, "Bullets", "list.bullet"),
                Item(.orderedList, "Numbering", "list.number"),
                Item(.taskList, "Tasks", "checklist")
            ]
        }
    }

    func isSelected(in commands: Set<NoteMarkdownCommand>) -> Bool {
        items.contains { commands.contains($0.command) }
    }
}

private struct Item: Identifiable {
    var id: NoteMarkdownCommand { command }
    let command: NoteMarkdownCommand
    let label: String
    let symbol: String?

    init(_ command: NoteMarkdownCommand, _ label: String, _ symbol: String?) {
        self.command = command
        self.label = label
        self.symbol = symbol
    }
}

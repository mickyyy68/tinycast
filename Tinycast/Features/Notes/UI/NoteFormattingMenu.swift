import SwiftUI

struct NoteFormattingMenu: View {
    let selectedCommands: Set<NoteMarkdownCommand>
    let isInteractive: Bool
    let onSelect: (NoteMarkdownCommand) -> Void
    @FocusState private var focused: FocusTarget?
    @State private var expandedGroup: FormatGroup?
    @State private var hoveredCommand: NoteMarkdownCommand?

    var body: some View {
        toolbar
            .onChange(of: isInteractive) { _, interactive in
                guard interactive else {
                    withoutAnimation {
                        expandedGroup = nil
                        focused = nil
                        hoveredCommand = nil
                    }
                    return
                }
            }
            .onChange(of: expandedGroup) { _, _ in hoveredCommand = nil }
            .onMoveCommand(perform: moveFocus)
            .disabled(!isInteractive)
            .opacity(isInteractive ? 1 : Theme.Opacity.noteDisabledControl)
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
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: 1, height: Theme.Size.noteStatus)
    }

    private func groupButton(_ group: FormatGroup) -> some View {
        Button {
            withoutAnimation {
                expandedGroup = expandedGroup == group ? nil : group
                focused = .command(group.representative)
            }
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                if let symbol = group.symbol {
                    SymbolImage(name: symbol, size: Theme.Size.noteStatus)
                } else {
                    Text(group.label)
                        .font(.caption.weight(.semibold))
                }
                SymbolImage(name: "chevron.down", size: Theme.Spacing.md)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(
                width: Theme.Size.noteHeaderButton + Theme.Spacing.lg,
                height: Theme.Size.noteHeaderButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            toolbarButtonBackground(
                expandedGroup == group || group.isSelected(in: selectedCommands)))
        .overlay(groupFocusBorder(group))
        .overlay(alignment: group == .list ? .bottomTrailing : .bottomLeading) {
            if expandedGroup == group {
                groupMenu(group)
                    .fixedSize()
                    .offset(y: -Theme.Size.noteHeaderButton - Theme.Spacing.md)
            }
        }
        .focused($focused, equals: .command(group.representative))
        .help(group.title)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(group.isSelected(in: selectedCommands) ? .isSelected : [])
    }

    private func commandButton(_ item: Item) -> some View {
        Button {
            withoutAnimation {
                expandedGroup = nil
                focused = .command(item.command)
            }
            onSelect(item.command)
        } label: {
            SymbolImage(name: item.symbol ?? "textformat", size: Theme.Size.noteStatus)
                .frame(
                    width: Theme.Size.noteHeaderButton,
                    height: Theme.Size.noteHeaderButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(toolbarButtonBackground(selectedCommands.contains(item.command)))
        .overlay(toolbarFocusBorder(.command(item.command)))
        .focused($focused, equals: .command(item.command))
        .help(item.label)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selectedCommands.contains(item.command) ? .isSelected : [])
    }

    private func groupMenu(_ group: FormatGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(group.items) { item in
                Button {
                    withoutAnimation {
                        focused = .command(item.command)
                        expandedGroup = nil
                    }
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
                            .font(Theme.Typography.menuRow)
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
                .background(
                    menuRowBackground(
                        selected: selectedCommands.contains(item.command),
                        hovered: hoveredCommand == item.command))
                .overlay(menuRowFocusBorder(.command(item.command)))
                .focused($focused, equals: .command(item.command))
                .onHover { hovered in
                    if hovered {
                        hoveredCommand = item.command
                    } else if hoveredCommand == item.command {
                        hoveredCommand = nil
                    }
                }
                .accessibilityLabel(item.label)
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

    private func toolbarButtonBackground(_ selected: Bool) -> some View {
        Capsule()
            .fill(selected ? Theme.Colors.selection : .clear)
    }

    private func groupFocusBorder(_ group: FormatGroup) -> some View {
        Capsule()
            .stroke(
                expandedGroup != group && focused == .command(group.representative)
                    ? Theme.Colors.border : .clear,
                lineWidth: 1)
    }

    private func toolbarFocusBorder(_ target: FocusTarget) -> some View {
        Capsule()
            .stroke(focused == target ? Theme.Colors.border : .clear, lineWidth: 1)
    }

    private func menuRowBackground(selected: Bool, hovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
            .fill(
                selected
                    ? Theme.Colors.selection
                    : hovered ? Theme.Colors.menuHover : .clear)
    }

    private func menuRowFocusBorder(_ target: FocusTarget) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
            .stroke(focused == target ? Theme.Colors.border : .clear, lineWidth: 1)
    }

    private func withoutAnimation(_ update: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private var toolbarTargets: [FocusTarget] {
        [
            .command(.normal), .command(.bold), .command(.link), .command(.inlineCode),
            .command(.codeBlock), .command(.blockquote), .command(.horizontalRule),
            .command(.unorderedList)
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
        case .up, .down:
            guard case .command(let command) = normalized,
                let group = FormatGroup.allCases.first(where: { $0.representative == command })
            else { return }
            withoutAnimation {
                expandedGroup = group
                let item = direction == .up ? group.items.last : group.items.first
                self.focused = item.map { .command($0.command) }
            }
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
                withoutAnimation {
                    expandedGroup = nil
                    focused = .command(group.representative)
                }
            } else {
                focused = .command(group.items[index + 1].command)
            }
        case .left, .right:
            withoutAnimation {
                expandedGroup = nil
                focused = .command(group.representative)
            }
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

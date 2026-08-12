import AppKit
import SwiftUI

@MainActor
enum NoteTextStyler {
    static func configure(_ textView: NSTextView, editable: Bool) {
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(
            width: Theme.Size.noteEditorInset,
            height: Theme.Size.noteEditorInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = NSColor(Theme.Colors.noteText)
        textView.insertionPointColor = NSColor(Theme.Colors.noteText)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.Colors.selection),
            .foregroundColor: NSColor(Theme.Colors.noteText)
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = false
        textView.typingAttributes = baseAttributes
    }

    static func apply(_ projection: NoteDisplayProjection, to textView: NSTextView) {
        textView.string = projection.string
        applyAttributes(projection, to: textView, changedDisplayRange: nil)
    }

    static func applyAttributes(
        _ projection: NoteDisplayProjection,
        to textView: NSTextView,
        changedDisplayRange: NSRange?
    ) {
        guard let storage = textView.textStorage else { return }
        let range: NSRange
        if let changedDisplayRange, storage.length > 0 {
            let location = min(changedDisplayRange.location, storage.length - 1)
            let length = min(changedDisplayRange.length, storage.length - location)
            range = (storage.string as NSString).lineRange(
                for: NSRange(location: location, length: length))
        } else {
            range = NSRange(location: 0, length: storage.length)
        }
        storage.setAttributes(baseAttributes, range: range)
        for span in projection.styles {
            let intersection = NSIntersectionRange(span.range, range)
            guard intersection.length > 0, NSMaxRange(intersection) <= storage.length else { continue }
            apply(span.style, to: storage, range: intersection)
        }
    }

    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .body),
        .foregroundColor: NSColor(Theme.Colors.noteText)
    ]

    private static func apply(
        _ style: NoteDisplayProjection.Style,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        switch style {
        case .heading(let level):
            let textStyle: NSFont.TextStyle = switch level {
            case 1: .title1
            case 2: .title2
            case 3: .title3
            case 4: .headline
            case 5: .subheadline
            default: .caption1
            }
            let font = NSFont.preferredFont(forTextStyle: textStyle)
            storage.addAttribute(
                .font,
                value: level >= 5
                    ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    : font,
                range: range)
            applyParagraphStyle(to: storage, range: range) { paragraph in
                paragraph.paragraphSpacingBefore = Theme.Spacing.sm
                paragraph.paragraphSpacing = Theme.Spacing.xs
            }
        case .strong:
            applyFontTrait(.boldFontMask, to: storage, range: range)
        case .emphasis:
            applyFontTrait(.italicFontMask, to: storage, range: range)
        case .strongEmphasis:
            applyFontTrait([.boldFontMask, .italicFontMask], to: storage, range: range)
        case .strikethrough:
            storage.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range)
        case .inlineCode:
            applyMonospacedFont(to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteCode),
                range: range)
        case .codeBlock:
            applyMonospacedFont(to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteCode),
                range: range)
            applyTextBlock(codeBlock(), to: storage, range: range)
        case .link:
            storage.addAttributes(
                [
                    .foregroundColor: NSColor(Theme.Colors.noteLink),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range)
        case .image, .markup:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteMarkup),
                range: range)
        case .listMarker, .taskMarker:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteMarkup),
                range: range)
            applyParagraphStyle(to: storage, range: range) { paragraph in
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = Theme.Spacing.xxl
            }
        case .horizontalRule:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: range)
            applyTextBlock(horizontalRuleBlock(), to: storage, range: range)
        case .blockquote:
            applyFontTrait(.italicFontMask, to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteQuote),
                range: range)
            applyTextBlock(blockquoteBlock(), to: storage, range: range)
        }
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
            let font = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(font, toHaveTrait: trait),
                range: effectiveRange)
        }
    }

    private static func applyMonospacedFont(to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
            let font = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
                range: effectiveRange)
        }
    }

    private static func applyParagraphStyle(
        to storage: NSTextStorage,
        range: NSRange,
        update: (NSMutableParagraphStyle) -> Void
    ) {
        let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
        var runs: [(NSRange, NSMutableParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, effectiveRange, _ in
            let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            update(paragraph)
            runs.append((effectiveRange, paragraph))
        }
        if runs.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            update(paragraph)
            runs.append((paragraphRange, paragraph))
        }
        for (effectiveRange, paragraph) in runs {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: effectiveRange)
        }
    }

    private static func applyTextBlock(
        _ block: NSTextBlock,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        applyParagraphStyle(to: storage, range: range) { paragraph in
            paragraph.textBlocks.append(block)
        }
    }

    private static func blockquoteBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(
            Theme.Spacing.xxs,
            type: .absoluteValueType,
            for: .border,
            edge: .minX)
        block.setBorderColor(NSColor(Theme.Colors.noteQuote), for: .minX)
        block.setWidth(
            Theme.Spacing.lg,
            type: .absoluteValueType,
            for: .padding,
            edge: .minX)
        return block
    }

    private static func codeBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = NSColor(Theme.Colors.cardFill)
        block.setWidth(Theme.Spacing.md, type: .absoluteValueType, for: .padding)
        block.setWidth(Theme.Spacing.xs, type: .absoluteValueType, for: .margin)
        return block
    }

    private static func horizontalRuleBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(
            1,
            type: .absoluteValueType,
            for: .border,
            edge: .minY)
        block.setBorderColor(NSColor(Theme.Colors.noteMarkup), for: .minY)
        block.setWidth(
            Theme.Spacing.md,
            type: .absoluteValueType,
            for: .padding,
            edge: .minY)
        block.setWidth(
            Theme.Spacing.md,
            type: .absoluteValueType,
            for: .padding,
            edge: .maxY)
        return block
    }
}

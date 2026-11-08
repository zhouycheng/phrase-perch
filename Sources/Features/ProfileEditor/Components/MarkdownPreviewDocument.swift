import AppKit

@MainActor
struct MarkdownPreviewDocument {
    let text: NSAttributedString
    private let sourceOffsets: [Int]

    init(source: String) {
        var builder = Builder(source: source)
        if let parsed = try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .full, appliesSourcePositionAttributes: true)) {
            builder.render(parsed)
        } else {
            builder.append(source, attributes: Builder.bodyAttributes, offsets: Array(0...source.utf16.count))
        }
        text = builder.output
        sourceOffsets = builder.offsets
    }

    func sourceOffset(at renderedOffset: Int) -> Int {
        sourceOffsets[min(max(0, renderedOffset), sourceOffsets.count - 1)]
    }

    @MainActor private struct Builder {
        let source: String
        let output = NSMutableAttributedString(string: "")
        var offsets = [0]
        var tables: [Int: NSTextTable] = [:]
        var listItems: Set<Int> = []
        var decodedEntities: [String: String] = [:]

        static var bodyAttributes: [NSAttributedString.Key: Any] {
            var attributes = EditorStyle.bodyTextAttributes
            let paragraph = (attributes[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            paragraph.paragraphSpacing = 10
            attributes[.paragraphStyle] = paragraph
            return attributes
        }

        mutating func render(_ parsed: AttributedString) {
            var blockID: Int?
            var attributes = Self.bodyAttributes
            for run in parsed.runs {
                let components = run.presentationIntent?.components ?? []
                let range = run.markdownSourcePosition.flatMap { Range<String.Index>($0, in: source) }
                    .map { NSRange($0, in: source) }
                let anchor = range?.location ?? offsets.last ?? 0
                if blockID != components.first?.identity {
                    if output.length > 0, !output.string.hasSuffix("\n") {
                        append("\n", attributes: attributes, offsets: [offsets.last ?? anchor, anchor])
                    }
                    blockID = components.first?.identity
                    attributes = blockAttributes(components)
                    if let prefix = listPrefix(components) {
                        append(prefix, attributes: attributes, offsets: Array(repeating: anchor, count: prefix.utf16.count + 1))
                    }
                }
                var inline = attributes
                var font = inline[.font] as? NSFont ?? .systemFont(ofSize: 14)
                let intent = run.inlinePresentationIntent ?? []
                if intent.contains(.code) {
                    font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                    inline[.backgroundColor] = NSColor.white.withAlphaComponent(0.07)
                }
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.strikethrough) { inline[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                inline[.font] = font
                if let link = run.link {
                    inline[.link] = link
                    inline[.foregroundColor] = NSColor.controlAccentColor
                }
                let fragment = String(parsed[run.range].characters)
                let codeBlock = components.contains { if case .codeBlock = $0.kind { return true }; return false }
                append(fragment, attributes: inline,
                    offsets: mappedOffsets(fragment, range: range, codeBlock: codeBlock, inlineCode: intent.contains(.code)))
            }
        }

        mutating func append(_ text: String, attributes: [NSAttributedString.Key: Any], offsets mapping: [Int]) {
            guard !text.isEmpty else { return }
            output.append(NSAttributedString(string: text, attributes: attributes))
            offsets.removeLast()
            offsets.append(contentsOf: mapping)
        }

        mutating func listPrefix(_ components: [PresentationIntent.IntentType]) -> String? {
            for component in components {
                if case .listItem(let ordinal) = component.kind {
                    guard listItems.insert(component.identity).inserted else { return nil }
                    let nearestList = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }
                    return nearestList?.kind == .orderedList ? "\(ordinal).\t" : "•\t"
                }
            }
            return nil
        }

        mutating func blockAttributes(_ components: [PresentationIntent.IntentType]) -> [NSAttributedString.Key: Any] {
            var attributes = Self.bodyAttributes
            let paragraph = (attributes[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            let depth = components.filter { if case .listItem = $0.kind { return true }; return false }.count
            paragraph.headIndent = CGFloat(depth) * 20
            paragraph.firstLineHeadIndent = max(0, paragraph.headIndent - 20)
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
            for component in components {
                switch component.kind {
                case .header(let level):
                    let sizes: [CGFloat] = [24, 21, 18, 16, 14, 14]
                    attributes[.font] = NSFont.systemFont(ofSize: sizes[min(5, max(0, level - 1))], weight: .semibold)
                    paragraph.paragraphSpacingBefore = 6
                    paragraph.paragraphSpacing = 12
                case .codeBlock:
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    let block = NSTextBlock()
                    block.backgroundColor = NSColor.white.withAlphaComponent(0.045)
                    block.setWidth(8, type: .absoluteValueType, for: .padding)
                    paragraph.textBlocks = [block]
                    paragraph.lineBreakMode = .byCharWrapping
                case .blockQuote:
                    paragraph.headIndent += 12
                    paragraph.firstLineHeadIndent += 12
                    let block = NSTextBlock()
                    block.backgroundColor = NSColor.white.withAlphaComponent(0.035)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    paragraph.textBlocks.append(block)
                case .table(let columns):
                    let table: NSTextTable
                    if let existing = tables[component.identity] { table = existing }
                    else {
                        table = NSTextTable()
                        table.numberOfColumns = max(1, columns.count)
                        table.layoutAlgorithm = .fixedLayoutAlgorithm
                        table.collapsesBorders = true
                        table.setValue(100, type: .percentageValueType, for: .width)
                        tables[component.identity] = table
                    }
                    let column = components.compactMap { if case .tableCell(let index) = $0.kind { return index }; return nil }.first ?? 0
                    let row = components.compactMap { if case .tableRow(let index) = $0.kind { return index }; return nil }.first ?? 0
                    let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    cell.setValue(100 / CGFloat(table.numberOfColumns), type: .percentageValueType, for: .width)
                    cell.setWidth(6, type: .absoluteValueType, for: .padding)
                    cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                    cell.setBorderColor(NSColor.separatorColor)
                    if row == 0 {
                        cell.backgroundColor = NSColor.white.withAlphaComponent(0.055)
                        attributes[.font] = NSFont.systemFont(ofSize: 14, weight: .semibold)
                    }
                    if columns.indices.contains(column) {
                        switch columns[column].alignment {
                        case .left: paragraph.alignment = .left
                        case .center: paragraph.alignment = .center
                        case .right: paragraph.alignment = .right
                        @unknown default: break
                        }
                    }
                    paragraph.textBlocks = [cell]
                    paragraph.paragraphSpacing = 0
                default: break
                }
            }
            attributes[.paragraphStyle] = paragraph
            return attributes
        }

        mutating func mappedOffsets(_ text: String, range: NSRange?, codeBlock: Bool, inlineCode: Bool) -> [Int] {
            guard var range else { return Array(repeating: offsets.last ?? 0, count: text.utf16.count + 1) }
            let original = source as NSString
            if codeBlock {
                let block = original.substring(with: range) as NSString
                let firstBreak = block.range(of: "\n")
                if firstBreak.location != NSNotFound {
                    let opening = block.substring(to: firstBreak.location).trimmingCharacters(in: .whitespaces)
                    if opening.hasPrefix("```") || opening.hasPrefix("~~~") {
                        let start = NSMaxRange(firstBreak)
                        let lastBreak = block.range(of: "\n", options: .backwards)
                        let lastLine = block.substring(from: NSMaxRange(lastBreak)).trimmingCharacters(in: .whitespaces)
                        let fence = opening.prefix { $0 == opening.first }
                        let closed = lastLine.hasPrefix(fence) && lastLine.dropFirst(fence.count).allSatisfy(\.isWhitespace)
                        let end = closed ? NSMaxRange(lastBreak) : block.length
                        range = NSRange(location: range.location + start, length: end - start)
                    }
                }
            }
            let raw = original.substring(with: range)
            if raw == text { return Array(range.location...NSMaxRange(range)) }
            let input = Array(raw.utf16)
            let visible = Array(text.utf16)
            var result: [Int] = []
            var i = 0
            var j = 0
            while j < visible.count {
                if i < input.count, !codeBlock, !inlineCode {
                    if input[i] == 92, i + 1 < input.count, input[i + 1] == visible[j] { i += 1 }
                    if input[i] == 38,
                        let end = input[i..<min(input.count, i + 34)].firstIndex(of: 59) {
                        let entity = String(decoding: input[i...end], as: UTF16.self)
                        let decoded: String
                        if let cached = decodedEntities[entity] { decoded = cached }
                        else {
                            decoded = (try? AttributedString(markdown: entity,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                .map { String($0.characters) } ?? entity
                            decodedEntities[entity] = decoded
                        }
                        let units = Array(decoded.utf16)
                        if !units.isEmpty, visible[j...].starts(with: units) {
                            result.append(contentsOf: repeatElement(range.location + i, count: units.count))
                            i = end + 1
                            j += units.count
                            continue
                        }
                    }
                }
                if i < input.count, input[i] != visible[j] {
                    // Soft breaks normalize source newlines to a visible space.
                    if visible[j] == 32, input[i] == 10 || input[i] == 13 {
                        result.append(range.location + i)
                        if input[i] == 13, i + 1 < input.count, input[i + 1] == 10 { i += 1 }
                        i += 1
                        j += 1
                        continue
                    }
                    i = input[i...].firstIndex(of: visible[j]) ?? input.count
                }
                result.append(range.location + i)
                if i < input.count { i += 1 }
                j += 1
            }
            result.append(range.location + i)
            return result
        }
    }
}

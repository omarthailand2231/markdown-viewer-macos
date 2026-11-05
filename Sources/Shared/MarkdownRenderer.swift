import Foundation
import UniformTypeIdentifiers

enum MarkdownFile {
    static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}

enum MarkdownRenderer {
    static func mermaidSources(in markdown: String) -> [String] {
        MathExtractor.extract(splitFrontMatter(markdown).1).1.filter(\.diagram).map(\.tex)
    }

    static func document(markdown: String, title: String, fileURL: URL?, diagrams: [String: String] = [:]) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title><style>\(stylesheet)</style></head>
        <body><article class="markdown-body">
        \(body(markdown: markdown, fileURL: fileURL, diagrams: diagrams))</article></body></html>

        """
    }

    static func body(markdown: String, fileURL: URL?, diagrams: [String: String] = [:]) -> String {
        let (frontMatter, content) = splitFrontMatter(markdown)
        var html = ""
        if let frontMatter {
            html += "<pre class=\"front-matter\"><code>\(escape(frontMatter))</code></pre>\n"
        }
        let (withoutFootnotes, footnotes) = extractFootnotes(content)
        let (source, math) = MathExtractor.extract(withoutFootnotes)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options, baseURL: nil) else {
            return html + "<pre><code>\(escape(content))</code></pre>\n"
        }
        var context = Context()
        html += MathExtractor.restore(render(buildTree(parsed, fileURL: fileURL), &context), math, diagrams: diagrams)
        return html + footnoteSection(footnotes, fileURL: fileURL)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }

    private final class Block {
        let kind: PresentationIntent.Kind?
        let identity: Int
        var children: [Node] = []

        init(kind: PresentationIntent.Kind?, identity: Int) {
            self.kind = kind
            self.identity = identity
        }

        var plainText: String {
            children.map { node in
                switch node {
                case .block(let block): return block.plainText
                case .inline(_, let text): return text
                }
            }.joined()
        }

        var firstOrdinal: Int {
            for case .block(let child) in children {
                if case .listItem(let ordinal)? = child.kind { return ordinal }
            }
            return 1
        }
    }

    private enum Node {
        case block(Block)
        case inline(html: String, text: String)
    }

    private struct Context {
        var usedSlugs: [String: Int] = [:]
        var columns: [PresentationIntent.TableColumn] = []
    }

    private struct Footnote {
        let label: String
        let text: String
        var number = 0
    }

    private static let alertTitles = [
        ("NOTE", "Note"), ("TIP", "Tip"), ("IMPORTANT", "Important"), ("WARNING", "Warning"), ("CAUTION", "Caution"),
    ]

    private static func buildTree(_ parsed: AttributedString, fileURL: URL?) -> Block {
        let root = Block(kind: nil, identity: -1)
        var stack = [root]
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let path = Array((run.presentationIntent?.components ?? []).reversed())
            var depth = 0
            while depth < path.count, depth + 1 < stack.count, stack[depth + 1].identity == path[depth].identity {
                depth += 1
            }
            stack.removeLast(stack.count - depth - 1)
            for component in path[depth...] {
                let block = Block(kind: component.kind, identity: component.identity)
                stack[stack.count - 1].children.append(.block(block))
                stack.append(block)
            }
            stack[stack.count - 1].children.append(.inline(html: inlineHTML(run, text, fileURL), text: text))
        }
        return root
    }

    private static func inlineHTML(_ run: AttributedString.Runs.Run, _ text: String, _ fileURL: URL?) -> String {
        let flags = run.inlinePresentationIntent ?? []
        if flags.contains(.blockHTML) || flags.contains(.inlineHTML) { return embedHTMLImages(text, fileURL) }
        if flags.contains(.lineBreak) { return "<br>\n" }
        if flags.contains(.softBreak) { return "\n" }
        var html: String
        if let image = run.imageURL {
            html = "<img src=\"\(escape(imageSource(image, fileURL)))\" alt=\"\(escape(text))\">"
        } else {
            html = escape(text)
            if flags.contains(.code) { html = "<code>\(html)</code>" }
            if flags.contains(.strikethrough) { html = "<del>\(html)</del>" }
            if flags.contains(.emphasized) { html = "<em>\(html)</em>" }
            if flags.contains(.stronglyEmphasized) { html = "<strong>\(html)</strong>" }
        }
        if let link = run.link {
            html = "<a href=\"\(escape(link.absoluteString))\">\(html)</a>"
        }
        return html
    }

    private static let htmlImageSource = try? NSRegularExpression(
        pattern: "(<img\\b[^>]*?\\bsrc\\s*=\\s*)([\"'])(.*?)\\2",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static func embedHTMLImages(_ html: String, _ fileURL: URL?) -> String {
        guard fileURL != nil, let pattern = htmlImageSource, html.range(of: "<img", options: .caseInsensitive) != nil else { return html }
        let text = html as NSString
        var result = ""
        var last = 0
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let range = match.range(at: 3)
            result += text.substring(with: NSRange(location: last, length: range.location - last))
            let source = text.substring(with: range)
            let decoded = source.replacingOccurrences(of: "&amp;", with: "&")
            let url = URL(string: decoded) ?? decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: $0) }
            let embedded = url.map { imageSource($0, fileURL) }
            result += embedded.map { $0.hasPrefix("data:") ? $0 : source } ?? source
            last = range.location + range.length
        }
        return result + text.substring(from: last)
    }

    private static func imageSource(_ image: URL, _ fileURL: URL?) -> String {
        let source = image.absoluteString
        guard let fileURL, image.scheme == nil || image.isFileURL,
              let target = URL(string: source, relativeTo: fileURL)?.absoluteURL,
              target.isFileURL,
              let data = try? Data(contentsOf: target), data.count < 20_000_000
        else { return source }
        let mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func render(_ block: Block, _ context: inout Context) -> String {
        switch block.kind {
        case nil:
            return renderChildren(block, &context)
        case .paragraph?:
            return "<p>\(renderChildren(block, &context))</p>\n"
        case .header(let level)?:
            let id = slug(block.plainText, &context.usedSlugs)
            return "<h\(level) id=\"\(escape(id))\">\(renderChildren(block, &context))</h\(level)>\n"
        case .unorderedList?:
            return "<ul>\n\(renderChildren(block, &context))</ul>\n"
        case .orderedList?:
            let start = block.firstOrdinal
            let open = start == 1 ? "<ol>" : "<ol start=\"\(start)\">"
            return "\(open)\n\(renderChildren(block, &context))</ol>\n"
        case .listItem?:
            return listItem(renderChildren(block, &context))
        case .codeBlock(let hint)?:
            var code = block.plainText
            if code.hasSuffix("\n") { code.removeLast() }
            if let hint, ["diff", "patch"].contains(hint.lowercased()) {
                return diffBlock(code)
            }
            let language = hint.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre><code\(language)>\(escape(code))</code></pre>\n"
        case .blockQuote?:
            return blockQuote(renderChildren(block, &context))
        case .thematicBreak?:
            return "<hr>\n"
        case .table(let columns)?:
            return table(block, columns, &context)
        case .tableHeaderRow?:
            return tableRow(block, tag: "th", &context)
        case .tableRow?:
            return tableRow(block, tag: "td", &context)
        default:
            return renderChildren(block, &context)
        }
    }

    private static func renderChildren(_ block: Block, _ context: inout Context) -> String {
        var html = ""
        for child in block.children {
            switch child {
            case .block(let inner): html += render(inner, &context)
            case .inline(let inlineHTML, _): html += inlineHTML
            }
        }
        return html
    }

    private static func listItem(_ html: String) -> String {
        for (marker, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where html.hasPrefix("<p>\(marker)") {
            let rest = html.dropFirst(3 + marker.count)
            let box = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")>"
            return "<li class=\"task\"><p>\(box) \(rest)</li>\n"
        }
        return "<li>\(html)</li>\n"
    }

    private static func table(_ block: Block, _ columns: [PresentationIntent.TableColumn], _ context: inout Context) -> String {
        let saved = context.columns
        context.columns = columns
        defer { context.columns = saved }
        var head = ""
        var body = ""
        for case .block(let row) in block.children {
            if case .tableHeaderRow? = row.kind {
                head += render(row, &context)
            } else {
                body += render(row, &context)
            }
        }
        let tbody = body.isEmpty ? "" : "<tbody>\n\(body)</tbody>\n"
        return "<div class=\"table-wrap\"><table>\n<thead>\n\(head)</thead>\n\(tbody)</table></div>\n"
    }

    private static func diffBlock(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n").map { line -> String in
            let kind: String
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                kind = "meta"
            } else if line.hasPrefix("@@") {
                kind = "hunk"
            } else if line.hasPrefix("+") {
                kind = "add"
            } else if line.hasPrefix("-") {
                kind = "del"
            } else {
                kind = "context"
            }
            return "<span class=\"diff-\(kind)\">\(escape(line))</span>"
        }
        return "<pre class=\"diff\"><code class=\"language-diff\">\(lines.joined())</code></pre>\n"
    }

    private static func tableRow(_ block: Block, tag: String, _ context: inout Context) -> String {
        var cells: [Int: String] = [:]
        for case .block(let cell) in block.children {
            if case .tableCell(let column)? = cell.kind { cells[column] = renderChildren(cell, &context) }
        }
        let count = max(context.columns.count, (cells.keys.max() ?? -1) + 1)
        let row = (0..<count).map { column -> String in
            let alignment = column < context.columns.count ? context.columns[column].alignment : .left
            let style: String
            switch alignment {
            case .center: style = " style=\"text-align:center\""
            case .right: style = " style=\"text-align:right\""
            default: style = ""
            }
            return "<\(tag)\(style)>\(cells[column] ?? "")</\(tag)>"
        }
        return "<tr>\(row.joined())</tr>\n"
    }

    private static func blockQuote(_ inner: String) -> String {
        for (marker, title) in alertTitles where inner.hasPrefix("<p>[!\(marker)]") {
            var rest = String(inner.dropFirst("<p>[!\(marker)]".count))
            if rest.hasPrefix("\n") { rest.removeFirst() }
            rest = rest.hasPrefix("</p>\n") ? String(rest.dropFirst(5)) : "<p>" + rest
            return "<div class=\"alert alert-\(marker.lowercased())\"><p class=\"alert-title\">\(title)</p>\n\(rest)</div>\n"
        }
        return "<blockquote>\n\(inner)</blockquote>\n"
    }

    private static func extractFootnotes(_ text: String) -> (String, [Footnote]) {
        let lines = text.components(separatedBy: "\n")
        var kept: [String] = []
        var footnotes: [Footnote] = []
        var inFence = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, line.hasPrefix("[^"), let close = line.range(of: "]:"),
               case let label = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound]),
               !label.isEmpty, !label.contains(where: { $0 == " " || $0 == "]" }) {
                var body = String(line[close.upperBound...]).trimmingCharacters(in: .whitespaces)
                while index + 1 < lines.count, lines[index + 1].hasPrefix("    ") || lines[index + 1].hasPrefix("\t") {
                    index += 1
                    body += "\n" + lines[index].trimmingCharacters(in: .whitespaces)
                }
                footnotes.append(Footnote(label: label, text: body))
            } else {
                kept.append(line)
            }
            index += 1
        }
        guard !footnotes.isEmpty else { return (text, []) }

        var next = 1
        inFence = false
        let replaced = kept.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            guard !inFence, line.contains("[^") else { return line }
            var line = line
            for position in footnotes.indices where line.contains("[^\(footnotes[position].label)]") {
                if footnotes[position].number == 0 {
                    footnotes[position].number = next
                    next += 1
                }
                let id = escape(footnotes[position].label)
                let link = "<sup class=\"footnote-ref\"><a href=\"#fn-\(id)\" id=\"fnref-\(id)\">\(footnotes[position].number)</a></sup>"
                line = line.replacingOccurrences(of: "[^\(footnotes[position].label)]", with: link)
            }
            return line
        }
        for position in footnotes.indices where footnotes[position].number == 0 {
            footnotes[position].number = next
            next += 1
        }
        return (replaced.joined(separator: "\n"), footnotes.sorted { $0.number < $1.number })
    }

    private static func footnoteSection(_ footnotes: [Footnote], fileURL: URL?) -> String {
        guard !footnotes.isEmpty else { return "" }
        let items = footnotes.map { note -> String in
            let id = escape(note.label)
            let back = " <a href=\"#fnref-\(id)\" class=\"footnote-back\">↩</a>"
            var content = body(markdown: note.text, fileURL: fileURL)
            if content.hasSuffix("</p>\n") {
                content = String(content.dropLast(5)) + back + "</p>\n"
            } else {
                content += back
            }
            return "<li id=\"fn-\(id)\">\(content)</li>\n"
        }
        return "<section class=\"footnotes\">\n<ol>\n\(items.joined())</ol>\n</section>\n"
    }

    private static func slug(_ text: String, _ used: inout [String: Int]) -> String {
        let allowed = CharacterSet.alphanumerics.union(.nonBaseCharacters).union(CharacterSet(charactersIn: " -_"))
        let kept = String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter { allowed.contains($0) }))
        let base = kept.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        let count = used[base, default: 0]
        used[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    private static func splitFrontMatter(_ text: String) -> (String?, String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return (nil, text) }
        let lines = text.components(separatedBy: "\n")
        for index in 1..<min(lines.count, 300) {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line == "---" || line == "..." else { continue }
            let frontMatter = lines[1..<index].joined(separator: "\n")
            guard frontMatter.contains(":") else { return (nil, text) }
            return (frontMatter, lines[(index + 1)...].joined(separator: "\n"))
        }
        return (nil, text)
    }

    static let stylesheet = """
    :root {
      --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0; --soft-border: #d1d9e0b3;
      --code-bg: #818b981f; --pre-bg: #f6f8fa; --link: #0969da; --row: #f6f8fa; --mark: #fff8c5;
      --diff-add: #116329; --diff-del: #82071e; --diff-hunk: #6639ba;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117; --fg: #f0f6fc; --muted: #9198a1; --border: #3d444d; --soft-border: #3d444db3;
        --code-bg: #656c7633; --pre-bg: #151b23; --link: #4493f8; --row: #151b23; --mark: #bb800926;
        --diff-add: #7ee787; --diff-del: #ffa198; --diff-hunk: #d2a8ff;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; background: var(--bg); color: var(--fg);
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", "Thonburi", sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    .markdown-body { max-width: 880px; margin: 0 auto; padding: 32px 40px 72px; }
    .markdown-body > :first-child { margin-top: 0 !important; }
    h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 .6em; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--soft-border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--soft-border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, blockquote, ul, ol, pre, .table-wrap { margin: 0 0 1em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 600; }
    hr { height: 4px; margin: 1.5em 0; padding: 0; border: 0; background: var(--border); border-radius: 2px; }
    blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    blockquote > :last-child { margin-bottom: 0; }
    ul, ol { padding-left: 2em; }
    li > p { margin: 0; }
    li + li { margin-top: .25em; }
    li > ul, li > ol { margin: .25em 0 0; }
    li.task { list-style: none; }
    li.task input {
      -webkit-appearance: none; appearance: none; width: 1em; height: 1em; margin: 0 .5em 0 -1.5em;
      vertical-align: -.15em; border: 1.5px solid var(--muted); border-radius: 4px; background: var(--bg);
    }
    li.task input:checked {
      border-color: var(--link); background: var(--link) center / 80% no-repeat
        url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3.5 8.5l3 3 6-7' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
    }
    kbd {
      display: inline-block; padding: .15em .4em; font: 11px ui-monospace, "SF Mono", Menlo, monospace; line-height: 1;
      vertical-align: middle; border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 6px; background: var(--pre-bg);
    }
    details { margin: 0 0 1em; }
    summary { cursor: pointer; }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 85%; }
    code { padding: .2em .4em; border-radius: 6px; background: var(--code-bg); white-space: break-spaces; }
    pre { padding: 16px; overflow: auto; line-height: 1.45; border-radius: 6px; background: var(--pre-bg); }
    pre code { padding: 0; font-size: 100%; background: transparent; white-space: pre; }
    pre.front-matter { color: var(--muted); }
    .table-wrap { overflow-x: auto; }
    table { border-collapse: collapse; border-spacing: 0; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tbody tr:nth-child(2n) { background: var(--row); }
    img { max-width: 100%; }
    .alert { margin: 0 0 1em; padding: .5em 1em; border-left: .25em solid var(--alert); }
    .alert > :last-child { margin-bottom: 0; }
    .alert-title { margin: 0 0 .25em; font-weight: 600; color: var(--alert); }
    .alert-note { --alert: #0969da; } .alert-tip { --alert: #1a7f37; } .alert-important { --alert: #8250df; }
    .alert-warning { --alert: #9a6700; } .alert-caution { --alert: #cf222e; }
    @media (prefers-color-scheme: dark) {
      .alert-note { --alert: #4493f8; } .alert-tip { --alert: #3fb950; } .alert-important { --alert: #ab7df8; }
      .alert-warning { --alert: #d29922; } .alert-caution { --alert: #f85149; }
    }
    math[display="block"] { margin: .25em 0 1em; padding: .25em 0; overflow-x: auto; overflow-y: hidden; }
    math { font-family: "STIX Two Math", "Latin Modern Math", math; font-size: 1.15em; }
    .math-fallback, .katex-error { color: #cf222e !important; }
    @media (prefers-color-scheme: dark) { .math-fallback, .katex-error { color: #f85149 !important; } }
    pre.diff { padding: 12px 0; }
    pre.diff span { display: block; min-height: 1.45em; padding: 0 16px; }
    .diff-add { color: var(--diff-add); background: #2ea04326; }
    .diff-del { color: var(--diff-del); background: #f8514926; }
    .diff-hunk { color: var(--diff-hunk); background: #54aeff1a; }
    .diff-meta { color: var(--muted); font-weight: 600; }
    .mermaid-diagram { margin: 0 0 1em; overflow-x: auto; text-align: center; }
    .mermaid-diagram svg { max-width: 100%; height: auto; }
    .mermaid-dark { display: none; }
    @media (prefers-color-scheme: dark) { .mermaid-light { display: none; } .mermaid-dark { display: block; } }
    .footnotes { margin-top: 2em; padding-top: 1em; border-top: 1px solid var(--soft-border); color: var(--muted); font-size: .875em; }
    .footnotes ol { padding-left: 1.5em; }
    sup.footnote-ref { font-size: .75em; line-height: 0; }
    mark { background: var(--mark); color: inherit; }
    """
}

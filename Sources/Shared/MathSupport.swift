import Foundation
import JavaScriptCore

struct MathSpan {
    let tex: String
    let display: Bool
    var diagram = false
}

enum MathExtractor {
    static func token(_ index: Int) -> String { "\u{E000}\(index)\u{E001}" }

    static func extract(_ text: String) -> (String, [MathSpan]) {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var spans: [MathSpan] = []
        var fence: String?
        var index = 0

        func add(_ tex: String, display: Bool, diagram: Bool = false) -> String {
            spans.append(MathSpan(tex: tex.trimmingCharacters(in: .whitespacesAndNewlines), display: display, diagram: diagram))
            return token(spans.count - 1)
        }

        while index < lines.count {
            let line = lines[index]
            let prefix = String(line.prefix { $0 == " " || $0 == "\t" || $0 == ">" })
            let content = String(line.dropFirst(prefix.count))

            if let open = fence {
                output.append(line)
                if content.hasPrefix(open) && content.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == open.first }) {
                    fence = nil
                }
                index += 1
                continue
            }

            if content.hasPrefix("```") || content.hasPrefix("~~~") {
                let marker = String(content.prefix { $0 == content.first })
                let info = content.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).lowercased()
                if info == "math" || info == "mermaid" {
                    var body: [String] = []
                    index += 1
                    while index < lines.count {
                        let inner = String(lines[index].dropFirst(prefix.count))
                        if inner.hasPrefix(marker) && inner.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == marker.first }) { break }
                        body.append(inner)
                        index += 1
                    }
                    output.append(prefix + add(body.joined(separator: "\n"), display: true, diagram: info == "mermaid"))
                    index += 1
                    continue
                }
                fence = marker
                output.append(line)
                index += 1
                continue
            }

            if let (open, close) = [("$$", "$$"), ("\\[", "\\]")].first(where: { content.hasPrefix($0.0) }) {
                let afterOpen = String(content.dropFirst(open.count))
                if let end = afterOpen.range(of: close) {
                    let rest = String(afterOpen[end.upperBound...])
                    if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        output.append(prefix + add(String(afterOpen[..<end.lowerBound]), display: true))
                        index += 1
                        continue
                    }
                } else if let closing = (index + 1..<lines.count).first(where: { lines[$0].contains(close) }) {
                    var body = [afterOpen]
                    for inner in index + 1..<closing {
                        body.append(String(lines[inner].dropFirst(prefix.count)))
                    }
                    let last = String(lines[closing].dropFirst(prefix.count))
                    let closeRange = last.range(of: close)!
                    body.append(String(last[..<closeRange.lowerBound]))
                    output.append(prefix + add(body.joined(separator: "\n"), display: true))
                    let trailing = String(last[closeRange.upperBound...])
                    if !trailing.trimmingCharacters(in: .whitespaces).isEmpty { output.append(prefix + trailing) }
                    index = closing + 1
                    continue
                }
            }

            output.append(inline(line) { add($0, display: $1) })
            index += 1
        }
        return (output.joined(separator: "\n"), spans)
    }

    private static func inline(_ line: String, _ add: (String, Bool) -> String) -> String {
        guard line.contains("$") || line.contains("\\(") || line.contains("\\[") else { return line }
        let chars = Array(line)
        var result = ""
        var i = 0

        func find(_ needle: String, from start: Int) -> Int? {
            let target = Array(needle)
            var j = start
            while j + target.count <= chars.count {
                if chars[j] == "\\" && target.first != "\\" { j += 2; continue }
                if Array(chars[j..<j + target.count]) == target { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if c == "`" {
                var run = 0
                while i + run < chars.count && chars[i + run] == "`" { run += 1 }
                var j = i + run
                var closed: Int?
                while j < chars.count {
                    if chars[j] == "`" {
                        var count = 0
                        while j + count < chars.count && chars[j + count] == "`" { count += 1 }
                        if count == run { closed = j + count; break }
                        j += count
                    } else {
                        j += 1
                    }
                }
                let end = closed ?? i + run
                result += String(chars[i..<end])
                i = end
                continue
            }

            if c == "\\", let next, next == "(" || next == "[" {
                let close = next == "(" ? "\\)" : "\\]"
                if let end = find(close, from: i + 2) {
                    result += add(String(chars[(i + 2)..<end]), next == "[")
                    i = end + 2
                    continue
                }
            }

            if c == "\\", let next {
                result.append(c)
                result.append(next)
                i += 2
                continue
            }

            if c == "$", next == "$", let end = find("$$", from: i + 2), end > i + 2 {
                result += add(String(chars[(i + 2)..<end]), true)
                i = end + 2
                continue
            }

            if c == "$", let next, !next.isWhitespace, next != "$" {
                var j = i + 1
                var closing: Int?
                while j < chars.count {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == "$" {
                        let before = chars[j - 1]
                        let after: Character? = j + 1 < chars.count ? chars[j + 1] : nil
                        if !before.isWhitespace && !(after?.isNumber ?? false) && after != "$" { closing = j }
                        break
                    }
                    j += 1
                }
                if let closing {
                    result += add(String(chars[(i + 1)..<closing]), false)
                    i = closing + 1
                    continue
                }
            }

            result.append(c)
            i += 1
        }
        return result
    }

    static func restore(_ html: String, _ spans: [MathSpan], diagrams: [String: String]) -> String {
        guard !spans.isEmpty else { return html }
        var output = html
        for (index, span) in spans.enumerated() {
            let rendered = span.diagram
                ? diagrams[span.tex] ?? "<pre><code class=\"language-mermaid\">\(MarkdownRenderer.escape(span.tex))</code></pre>"
                : MathRenderer.shared.html(span.tex, display: span.display)
            let placeholder = token(index)
            if span.display {
                output = output.replacingOccurrences(of: "<p>\(placeholder)</p>", with: rendered)
            }
            output = output.replacingOccurrences(of: placeholder, with: rendered)
        }
        return output
    }
}

final class MathRenderer {
    static let shared = MathRenderer()

    private let lock = NSLock()
    private var context: JSContext?
    private var renderFunction: JSValue?
    private var loaded = false

    func html(_ tex: String, display: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        load()
        if let value = renderFunction?.call(withArguments: [tex, display]), value.isString, let markup = value.toString() {
            return markup
        }
        let escaped = MarkdownRenderer.escape(tex)
        return display
            ? "<pre class=\"math-fallback\"><code>\(escaped)</code></pre>"
            : "<code class=\"math-fallback\">\(escaped)</code>"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let environment = ProcessInfo.processInfo.environment["MDVIEWER_KATEX"].map { URL(fileURLWithPath: $0) }
        guard let url = environment ?? Bundle.main.url(forResource: "katex.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext()
        else { return }
        context.evaluateScript(source)
        renderFunction = context.evaluateScript("""
        (function (tex, display) {
          try {
            return katex.renderToString(tex, { displayMode: display, output: "mathml", throwOnError: false, strict: "ignore", trust: false });
          } catch (error) {
            return null;
          }
        })
        """)
        self.context = context
    }
}

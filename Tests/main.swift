import AppKit
import Foundation

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
var failures = 0
var passes = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func render(_ name: String) -> String {
    let url = fixtures.appendingPathComponent(name)
    return MarkdownRenderer.body(markdown: (try? MarkdownFile.read(url)) ?? "", fileURL: url)
}

let html = render("everything.md")

let expectations: [(String, String)] = [
    ("front matter", "<pre class=\"front-matter\"><code>title: Everything\ntags: [markdown, test]</code></pre>"),
    ("h1", "<h1 id=\"heading-1\">Heading 1</h1>"),
    ("h2", "<h2 id=\"heading-2\">Heading 2</h2>"),
    ("h3", "<h3 id=\"heading-3\">Heading 3</h3>"),
    ("h4", "<h4 id=\"heading-4\">Heading 4</h4>"),
    ("h5", "<h5 id=\"heading-5\">Heading 5</h5>"),
    ("h6", "<h6 id=\"heading-6\">Heading 6</h6>"),
    ("setext h1", "<h1 id=\"setext-heading\">Setext Heading</h1>"),
    ("setext h2", "<h2 id=\"setext-two\">Setext Two</h2>"),
    ("duplicate heading slug", "<h2 id=\"heading-2-1\">Heading 2</h2>"),
    ("emphasis", "Plain <em>em</em>, <em>em</em>, <strong>strong</strong>, <strong>strong</strong>"),
    ("strong + em", "<strong><em>both</em></strong>"),
    ("strikethrough", "<del>strike</del>"),
    ("inline code", "<code>code</code>"),
    ("backtick inside code", "<code>a`b</code>"),
    ("backslash escapes", "*not em* and # not heading"),
    ("entities", "entities © &amp; &lt;tag&gt;"),
    ("hard break", "Backslash hard break<br>\nnext line."),
    ("inline link", "<a href=\"https://example.com\">inline</a>"),
    ("reference link", "<a href=\"https://reference.example\">ref link</a>"),
    ("angle autolink", "<a href=\"https://autolink.example\">https://autolink.example</a>"),
    ("bare url", "<a href=\"https://bare.example.com\">https://bare.example.com</a>"),
    ("www url", "<a href=\"http://www.example.org\">www.example.org</a>"),
    ("relative md link", "<a href=\"other.md\">other doc</a>"),
    ("anchor link", "<a href=\"#heading-2\">anchor</a>"),
    ("local image embedded", "<img src=\"data:image/png;base64,"),
    ("remote image kept", "<img src=\"https://example.com/remote.png\" alt=\"remote\">"),
    ("nested quote", "<blockquote>\n<p>Quote level 1</p>\n<blockquote>\n<p>Nested quote</p>\n</blockquote>"),
    ("code in quote", "<pre><code>code in quote</code></pre>\n</blockquote>"),
    ("nested list x3", "<li><p>Item one</p>\n<ul>\n<li><p>Nested two</p>\n<ul>\n<li><p>Nested three</p>"),
    ("ordered list start", "<ol start=\"3\">\n<li><p>Start at three</p>"),
    ("task open", "<li class=\"task\"><p><input type=\"checkbox\" disabled> open task</p>"),
    ("task done", "<li class=\"task\"><p><input type=\"checkbox\" disabled checked> done task</p>"),
    ("task done upper X", "<input type=\"checkbox\" disabled checked> done upper"),
    ("nested task", "<li class=\"task\"><p><input type=\"checkbox\" disabled> nested task</p>"),
    ("table header + alignment", "<tr><th>Left</th><th style=\"text-align:center\">Center</th><th style=\"text-align:right\">Right</th><th>None</th></tr>"),
    ("table inline formatting + escaped pipe", "<tr><td><strong>b</strong></td><td style=\"text-align:center\"><code>c</code></td><td style=\"text-align:right\"><a href=\"https://x.y\">l</a></td><td>a | pipe</td></tr>"),
    ("table empty cells kept", "<tr><td></td><td style=\"text-align:center\">empty first</td><td style=\"text-align:right\">3</td><td></td></tr>"),
    ("header-only table", "<tr><th>Only</th><th>Header</th></tr>\n</thead>\n</table>"),
    ("fenced code with language", "<pre><code class=\"language-swift\">let html = &quot;&lt;b&gt;&quot; + &quot;&amp;&quot; // escaped</code></pre>"),
    ("tilde fence", "<pre><code>tilde fence</code></pre>"),
    ("indented code", "<pre><code>indented code &lt;x&gt;</code></pre>"),
    ("raw html block", "<details>\n<summary>Raw HTML block</summary>"),
    ("inline html", "Inline <kbd>Ctrl</kbd> + <kbd>C</kbd>."),
    ("raw html local image embedded", "<img src=\"data:image/png;base64,"),
    ("raw html remote image untouched", "<img src=\"https://example.com/x.png?a=1&amp;b=2\" alt=\"remote raw\">"),
    ("thai + emoji", "ภาษาไทย สวัสดีครับ 🎉 emoji"),
    ("footnote ref", "Footnote ref<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">1</a></sup>."),
    ("second footnote numbered", "<a href=\"#fn-long\" id=\"fnref-long\">2</a>"),
    ("footnote section", "<li id=\"fn-1\"><p>The footnote. <a href=\"#fnref-1\" class=\"footnote-back\">↩</a></p>"),
    ("multi-line footnote", "Long note with <strong>bold</strong>\nand a continued line."),
    ("footnote syntax in fence untouched", "<pre><code>[^1] inside a fence stays literal</code></pre>"),
    ("note callout", "<div class=\"alert alert-note\"><p class=\"alert-title\">Note</p>\n<p>A note callout.</p>"),
    ("warning callout", "<div class=\"alert alert-warning\"><p class=\"alert-title\">Warning</p>\n<p>Careful.</p>"),
]
for (name, snippet) in expectations {
    check(name, html.contains(snippet))
}
check("both local images embedded", html.components(separatedBy: "src=\"data:image/png;base64,").count - 1 == 2)
check("two thematic breaks", html.components(separatedBy: "<hr>").count - 1 == 2)
check("no leftover footnote markers outside code", !html.replacingOccurrences(of: "[^1] inside a fence", with: "").contains("[^"))

let math = render("math.md")
let inlineMath = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><semantics>"
let blockMath = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\">"
check("inline $ math", math.contains("<p>Inline <span class=\"katex\">\(inlineMath)"))
check("inline \\( math", math.components(separatedBy: inlineMath).count - 1 >= 4)
check("display math count ($$, \\[, ```math, one-line $$)", math.components(separatedBy: blockMath).count - 1 == 4)
check("tex kept as annotation", math.contains("<annotation encoding=\"application/x-tex\">E = mc^2</annotation>"))
check("fraction rendered", math.contains("<mfrac>"))
check("matrix rendered", math.contains("<mtable"))
check("currency is not math", math.contains("<p>Money: it costs $5 and $10, plus an escaped $ sign.</p>"))
check("math in inline code untouched", math.contains("<code>$not math$</code>"))
check("math in fenced code untouched", math.contains("<pre><code>$$ also not math $$</code></pre>"))
check("math inside quote", math.contains("<p>Quote with <span class=\"katex\">"))
check("broken tex shown, no crash", math.contains("class=\"katex-error\"") && math.contains("stays readable."))
check("no placeholder leaks", !math.contains("\u{E000}") && !math.contains("\u{E001}"))

let diagramsURL = fixtures.appendingPathComponent("diagrams.md")
let diagramsMarkdown = (try? MarkdownFile.read(diagramsURL)) ?? ""
let plain = MarkdownRenderer.body(markdown: diagramsMarkdown, fileURL: diagramsURL)
check("mermaid sources found", MarkdownRenderer.mermaidSources(in: diagramsMarkdown).count == 3)
check("mermaid falls back to code without renderer", plain.contains("<pre><code class=\"language-mermaid\">flowchart LR"))
check("diff block", plain.contains("<pre class=\"diff\"><code class=\"language-diff\">"))
check("diff added line", plain.contains("<span class=\"diff-add\">+    return &quot;Hello, \\(name)!&quot;</span>"))
check("diff removed line", plain.contains("<span class=\"diff-del\">-    return &quot;Hello &quot; + name</span>"))
check("diff hunk", plain.contains("<span class=\"diff-hunk\">@@ -1,4 +1,4 @@</span>"))
check("diff file headers", plain.contains("<span class=\"diff-meta\">--- a/greeting.swift</span>") && plain.contains("<span class=\"diff-meta\">+++ b/greeting.swift</span>"))
check("diff context line", plain.contains("<span class=\"diff-context\"> func greet(_ name: String) -&gt; String {</span>"))

let crlf = render("crlf.md")
check("crlf heading", crlf.contains("<h1 id=\"crlf-title\">CRLF Title</h1>"))
check("crlf list", crlf.contains("<li><p>a</p>\n</li>\n<li><p>b</p>"))

check("empty file", render("empty.md").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
check("missing file renders empty", render("does-not-exist.md").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

let page = MarkdownRenderer.document(markdown: "# Hi", title: "a<b>.md", fileURL: nil)
check("page title escaped", page.contains("<title>a&lt;b&gt;.md</title>"))
check("page follows system appearance", page.contains("name=\"color-scheme\" content=\"light dark\"") && page.contains("@media (prefers-color-scheme: dark)"))

let big = String(repeating: (try? MarkdownFile.read(fixtures.appendingPathComponent("everything.md")).dropFirst(60).description) ?? "", count: 150)
let start = Date()
_ = MarkdownRenderer.body(markdown: big, fileURL: nil)
let seconds = Date().timeIntervalSince(start)
check("large file (\(big.count / 1000)k chars) renders under 3s (took \(String(format: "%.2f", seconds))s)", seconds < 3)

_ = NSApplication.shared
var diagramsDone = false
Task { @MainActor in
    let started = Date()
    let page = await MarkdownRenderer.documentRenderingDiagrams(markdown: diagramsMarkdown, title: "diagrams.md", fileURL: diagramsURL)
    let elapsed = Date().timeIntervalSince(started)
    check("mermaid diagrams rendered to SVG (\(String(format: "%.2f", elapsed))s)", page.components(separatedBy: "<div class=\"mermaid-diagram\"><div class=\"mermaid-light\"><svg").count - 1 == 2)
    check("mermaid light and dark variants", page.components(separatedBy: "<div class=\"mermaid-dark\"><svg").count - 1 == 2)
    check("mermaid flowchart labels present", page.contains("Parser") && page.contains("Window"))
    check("invalid mermaid falls back to code", page.contains("<pre><code class=\"language-mermaid\">this is not a valid diagram"))
    let again = Date()
    _ = await MarkdownRenderer.documentRenderingDiagrams(markdown: diagramsMarkdown, title: "diagrams.md", fileURL: diagramsURL)
    check("re-render uses cache", Date().timeIntervalSince(again) < 0.5)
    diagramsDone = true
}
let deadline = Date().addingTimeInterval(60)
while !diagramsDone && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
check("mermaid rendering finished", diagramsDone)

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)

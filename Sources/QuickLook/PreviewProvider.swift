import Foundation
import QuickLookUI
import UniformTypeIdentifiers

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let markdown = try MarkdownFile.read(url)
        let html = await MarkdownRenderer.documentRenderingDiagrams(markdown: markdown, title: url.lastPathComponent, fileURL: url)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
    }
}

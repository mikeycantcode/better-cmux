import Foundation

/// Detects standalone mermaid diagram files and adapts their contents for the
/// shared markdown render pipeline.
///
/// A `.mmd` file is raw mermaid source with no fence. The markdown shell only
/// renders mermaid when it sees a ```` ```mermaid ```` fence, so we wrap the
/// source rather than teaching the shell a second input format. That keeps a
/// single render path for both `.md` fences and `.mmd` files.
enum MermaidDiagramFileResolver {
    /// Extensions that open directly as a diagram surface.
    private static let diagramExtensions: Set<String> = ["mmd", "mermaid"]

    static func isDiagramPathLike(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Mirror MarkdownPanelFileLinkResolver: path-like only, never remote URLs.
        if let url = URL(string: trimmed), url.scheme != nil, url.scheme != "file" {
            return false
        }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        return diagramExtensions.contains(ext)
    }

    /// Wraps raw mermaid source in a fence the markdown shell already knows how
    /// to render. Trailing blank lines are trimmed so the closing fence is not
    /// separated from the diagram body by empty lines.
    static func wrapAsMermaidFence(_ source: String) -> String {
        let body = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return "```mermaid\n\(body)\n```"
    }
}

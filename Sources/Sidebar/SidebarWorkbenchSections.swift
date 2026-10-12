import AppKit
import SwiftUI

/// The left sidebar's lower half: the VS Code explorer above the Source Control
/// Graph, split by a draggable divider.
///
/// Does not observe the explorer store (``SidebarFileExplorerPanel`` does); it
/// only follows `rootPath` so the graph tracks the active workspace.
struct SidebarWorkbenchSections: View {
    let explorerStore: FileExplorerStore
    @ObservedObject var explorerState: FileExplorerState
    let onOpenFile: (String) -> Void

    @StateObject private var graphModel = GitCommitGraphModel()
    @AppStorage("sidebar.scmGraph.expanded") private var isGraphExpanded = true
    @State private var rootPath = ""
    @State private var dragStartFraction: CGFloat?
    @State private var isDragging = false

    private static let headerHeight: CGFloat = 22
    private static let dividerHeight: CGFloat = 7
    private static let resizeCursor = NSCursor(
        image: NSCursor.resizeUpDown.image,
        hotSpot: NSCursor.resizeUpDown.hotSpot
    )

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.height
            VStack(spacing: 0) {
                explorer
                    .frame(height: explorerHeight(total: total))
                if explorerState.isVisible && isGraphExpanded {
                    divider(availableHeight: total - Self.dividerHeight)
                } else {
                    hairline
                }
                graph
                    .frame(maxHeight: isGraphExpanded ? .infinity : Self.headerHeight)
                if !isGraphExpanded {
                    Spacer(minLength: 0)
                }
            }
        }
        .onReceive(explorerStore.$rootPath.removeDuplicates()) { path in
            rootPath = path
            graphModel.setRootPath(path)
        }
    }

    private var explorer: some View {
        SidebarFileExplorerPanel(
            store: explorerStore,
            state: explorerState,
            onOpenFile: onOpenFile
        )
    }

    private var graph: some View {
        SidebarSourceControlGraphPanel(
            model: graphModel,
            repoName: (rootPath as NSString).lastPathComponent,
            isExpanded: $isGraphExpanded
        )
    }

    private func explorerHeight(total: CGFloat) -> CGFloat? {
        guard explorerState.isVisible else { return Self.headerHeight }
        guard isGraphExpanded else {
            return max(Self.headerHeight, total - Self.headerHeight - 1)
        }
        let available = total - Self.dividerHeight
        let fraction = SidebarExplorerSplit.clampedSessionFraction(
            explorerState.dividerPosition,
            availableHeight: available
        )
        return max(Self.headerHeight, available * fraction)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func divider(availableHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: Self.dividerHeight)
            .contentShape(Rectangle())
            .overlay(hairline)
            .onHover { hovering in
                if hovering {
                    Self.resizeCursor.set()
                } else if !isDragging {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartFraction = explorerState.dividerPosition
                        }
                        let start = dragStartFraction ?? explorerState.dividerPosition
                        let next = SidebarExplorerSplit.clampedSessionFraction(
                            start + value.translation.height / max(1, availableHeight),
                            availableHeight: availableHeight
                        )
                        withTransaction(Transaction(animation: nil)) {
                            explorerState.dividerPosition = next
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStartFraction = nil
                        NSCursor.arrow.set()
                    }
            )
    }
}

import Foundation

enum ExpandedAutoCollapsePolicy {
    static let hoverExitCollapseDelay: TimeInterval = 0.5

    static func shouldCollapseOnMouseExit(
        isPointerInside: Bool,
        state: IslandState,
        expandedByHover: Bool,
        visibleSessionCount: Int,
        elapsedSinceExpand: TimeInterval
    ) -> Bool {
        guard !isPointerInside, state == .expanded else { return false }
        guard expandedByHover || visibleSessionCount == 0 else { return false }
        return elapsedSinceExpand > hoverExitCollapseDelay
    }
}

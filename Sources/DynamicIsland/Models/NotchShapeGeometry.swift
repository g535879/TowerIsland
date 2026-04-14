import CoreGraphics

enum NotchShapeGeometry {
    static let collapsedShapeHeight: CGFloat = 32
    static let expandedCornerRadius: CGFloat = 22
    static let collapsedBottomCornerRadius: CGFloat = 17

    static func openProgress(shapeHeight: CGFloat, cachedExpandedShapeHeight: CGFloat) -> CGFloat {
        let lo = collapsedShapeHeight
        let hi = max(cachedExpandedShapeHeight, lo + 1)
        return min(1, max(0, (shapeHeight - lo) / (hi - lo)))
    }

    static func topCornerRadius(state: IslandState) -> CGFloat {
        switch state {
        case .collapsed:
            return 0
        case .expanded, .permission, .question, .planReview:
            return 0
        }
    }

    static func bottomCornerRadius(openProgress: CGFloat) -> CGFloat {
        collapsedBottomCornerRadius
            + (expandedCornerRadius - collapsedBottomCornerRadius) * openProgress
    }
}

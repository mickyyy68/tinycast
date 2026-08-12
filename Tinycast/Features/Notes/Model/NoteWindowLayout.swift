import CoreGraphics
import Foundation

enum NoteWindowLayout {
    struct Metrics: Sendable, Equatable {
        let width: CGFloat
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        let maximumScreenFraction: CGFloat
        let fixedContentHeight: CGFloat
    }

    static func panelHeight(
        editorContentHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let desired = metrics.fixedContentHeight + max(0, editorContentHeight)
        return clampedPanelHeight(
            desired,
            visibleScreenHeight: visibleScreenHeight,
            metrics: metrics)
    }

    static func growOnlyPanelHeight(
        editorContentHeight: CGFloat,
        currentPanelHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let desired = metrics.fixedContentHeight + max(0, editorContentHeight)
        return clampedPanelHeight(
            max(currentPanelHeight, desired),
            visibleScreenHeight: visibleScreenHeight,
            metrics: metrics)
    }

    static func preservedPanelHeight(
        _ currentPanelHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        clampedPanelHeight(
            currentPanelHeight,
            visibleScreenHeight: visibleScreenHeight,
            metrics: metrics)
    }

    static func resizedFrame(
        currentFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect,
        width: CGFloat
    ) -> CGRect {
        constrainedFrame(
            CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - height,
                width: width,
                height: height),
            to: visibleFrame)
    }

    static func centeredFrame(
        currentFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect,
        width: CGFloat
    ) -> CGRect {
        constrainedFrame(
            CGRect(
                x: currentFrame.midX - width / 2,
                y: currentFrame.midY - height / 2,
                width: width,
                height: height),
            to: visibleFrame)
    }

    private static func constrainedFrame(_ proposedFrame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var frame = proposedFrame
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        return frame
    }

    private static func clampedPanelHeight(
        _ proposedHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let maximum = min(
            metrics.maximumHeight,
            visibleScreenHeight * metrics.maximumScreenFraction)
        return min(
            max(proposedHeight, metrics.minimumHeight),
            max(metrics.minimumHeight, maximum))
    }
}

import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

public enum ViewportProjectedGrid {
    public typealias Axis = ViewportCoordinateAxis
    static let maximumGridLineCount = 360
    private static let minimumScaleLabelSpacingPixels: CGFloat = 72.0
    private static let readableStepMultipliers = [1.0, 2.0, 5.0, 10.0]

    public typealias VisualSpacingMode = ViewportGridVisualSpacingMode

    public struct ScaleReadout: Equatable, Sendable {
        public struct Length: Equatable, Sendable {
            public var meters: Double
            public var displayValue: Double
            public var displayUnit: LengthDisplayUnit
            public var text: String

            public init(
                meters: Double,
                displayValue: Double,
                displayUnit: LengthDisplayUnit,
                text: String
            ) {
                self.meters = meters
                self.displayValue = displayValue
                self.displayUnit = displayUnit
                self.text = text
            }
        }

        public var minorStep: Length
        public var majorStep: Length
        public var snapStep: Length
        public var visibleSpan: Length
        public var workspaceSpan: Length
        public var minorStepPixels: CGFloat
        public var visualSpacingMode: VisualSpacingMode
        public var isVisualStepCapped: Bool

        public init(
            minorStep: Length,
            majorStep: Length,
            snapStep: Length,
            visibleSpan: Length,
            workspaceSpan: Length,
            minorStepPixels: CGFloat,
            visualSpacingMode: VisualSpacingMode,
            isVisualStepCapped: Bool
        ) {
            self.minorStep = minorStep
            self.majorStep = majorStep
            self.snapStep = snapStep
            self.visibleSpan = visibleSpan
            self.workspaceSpan = workspaceSpan
            self.minorStepPixels = minorStepPixels
            self.visualSpacingMode = visualSpacingMode
            self.isVisualStepCapped = isVisualStepCapped
        }

        /// The one sentence this module composes: what a reader of the grid
        /// hears. Sighted presentation of the scale belongs to the host, which
        /// reads the steps and spans above and writes its own text.
        public var accessibilityText: String {
            var components = [
                "Grid \(minorStep.text)",
                "mode \(visualSpacingMode.rawValue)",
                "snap \(snapStep.text)",
                "major \(majorStep.text)",
                "visible span \(visibleSpan.text)",
                "workspace span \(workspaceSpan.text)",
            ]
            if isVisualStepCapped {
                components.append("visual grid capped by line budget")
            }
            return components.joined(separator: ", ")
        }
    }

    /// Inputs for the camera-owned grid frame. The closures are evaluated only
    /// while the frame is being built; no source or camera authority crosses
    /// this boundary.
    struct NativeFrameInput {
        var ruler: RulerConfiguration
        var basis: ViewportProjectionBasis
        var viewportSize: CGSize
        var projectedScale: CGFloat
        var project: (Point3D) -> CGPoint?
        /// Returns `nil` when the native camera ray does not intersect the
        /// supplied grid plane. All-nil bounded samples produce a hidden
        /// native frame; non-finite returned points are a typed failure.
        var unproject: (CGPoint, ViewportCanvasPlane) -> Point3D?
        var chromeExclusionRects: [CGRect]
        var labelRect: (CGPoint, String) -> CGRect
        var isChromeExcluded: ((CGRect) -> Bool)?
        var visualSpacingMode: VisualSpacingMode

        init(
            ruler: RulerConfiguration,
            basis: ViewportProjectionBasis,
            viewportSize: CGSize,
            projectedScale: CGFloat,
            project: @escaping (Point3D) -> CGPoint?,
            unproject: @escaping (CGPoint, ViewportCanvasPlane) -> Point3D?,
            chromeExclusionRects: [CGRect] = [],
            labelRect: @escaping (CGPoint, String) -> CGRect = ViewportProjectedGrid.defaultNativeLabelRect,
            isChromeExcluded: ((CGRect) -> Bool)? = nil,
            visualSpacingMode: VisualSpacingMode = .adaptive
        ) {
            self.ruler = ruler
            self.basis = basis
            self.viewportSize = viewportSize
            self.projectedScale = projectedScale
            self.project = project
            self.unproject = unproject
            self.chromeExclusionRects = chromeExclusionRects
            self.labelRect = labelRect
            self.isChromeExcluded = isChromeExcluded
            self.visualSpacingMode = visualSpacingMode
        }
    }

    enum NativeFrameError: Error, Equatable {
        case invalidRuler
        case invalidViewport
        case invalidBasis
        case invalidProjectedScale
        case invalidStep
        case invalidCoverage
        case unprojectionFailed
        case projectionFailed
        case indexBoundsOverflow
        case lineBudgetExceeded
        case labelBudgetExceeded
        case invalidLabelPlacement
    }

    struct NativeFrame: Equatable, Sendable {
        struct WorldLine: Equatable, Sendable {
            let axis: Axis
            let start: Point3D
            let end: Point3D
            let isMajor: Bool
            let isOrigin: Bool
        }

        struct ScreenLabel: Equatable, Sendable {
            let axis: Axis
            let valueMeters: Double
            let displayValue: Double
            let displayUnit: LengthDisplayUnit
            let position: CGPoint
            let text: String
        }

        let basis: ViewportProjectionBasis
        let plane: ViewportCanvasPlane
        let worldBounds: CGRect
        let minorStepMeters: Double
        let majorStepMeters: Double
        let minorStepPixels: CGFloat
        let worldLines: [WorldLine]
        let screenLabels: [ScreenLabel]
        let scaleReadout: ScaleReadout
    }

    /// Builds the complete camera-owned grid frame used by the RealityKit path.
    /// Returns `nil` when the current camera has no bounded intersection with
    /// the displayed grid plane. This is a valid hidden-grid state, not an
    /// invalid input or a request to fabricate coverage.
    static func makeNativeFrame(_ input: NativeFrameInput) throws -> NativeFrame? {
        guard input.ruler.minorTickMeters.isFinite,
              input.ruler.majorTickMeters.isFinite,
              input.ruler.visibleSpanMeters.isFinite,
              input.ruler.minorTickMeters > 0.0,
              input.ruler.majorTickMeters > input.ruler.minorTickMeters,
              input.ruler.visibleSpanMeters >= input.ruler.majorTickMeters,
              RulerConfiguration.minorTickMetersRange.contains(input.ruler.minorTickMeters),
              RulerConfiguration.majorTickMetersRange.contains(input.ruler.majorTickMeters),
              RulerConfiguration.visibleSpanMetersRange.contains(input.ruler.visibleSpanMeters) else {
            throw NativeFrameError.invalidRuler
        }
        guard input.viewportSize.width.isFinite,
              input.viewportSize.height.isFinite,
              input.viewportSize.width > 0.0,
              input.viewportSize.height > 0.0 else {
            throw NativeFrameError.invalidViewport
        }
        guard input.basis.isRigidOrientation else {
            throw NativeFrameError.invalidBasis
        }
        guard input.projectedScale.isFinite,
              input.projectedScale > 0.0 else {
            throw NativeFrameError.invalidProjectedScale
        }
        guard input.chromeExclusionRects.allSatisfy({ rect in
            Self.isFiniteRect(rect) && rect.width >= 0.0 && rect.height >= 0.0
        }) else {
            throw NativeFrameError.invalidLabelPlacement
        }

        let ruler = input.ruler.normalizedForWorkspaceScale()
        let plane = gridPlane(for: input.basis)
        let requestedMinorStepMeters = requestedVisualMinorStep(
            ruler: ruler,
            scale: input.projectedScale,
            mode: input.visualSpacingMode
        )
        guard let modelBounds = try nativeVisibleModelBounds(
            viewportSize: input.viewportSize,
            plane: plane,
            step: max(requestedMinorStepMeters, 1.0e-12),
            unproject: input.unproject
        ) else {
            return nil
        }
        let minorStepMeters = try nativeStepForLineBudget(
            requestedMinorStepMeters,
            modelBounds: modelBounds,
            maximumLineCount: maximumGridLineCount
        )
        let isVisualStepCapped = isCappedStep(
            resolvedStepMeters: minorStepMeters,
            requestedStepMeters: requestedMinorStepMeters
        )
        let requestedMajorStepMeters = adjustedStep(
            max(ruler.majorTickMeters, minorStepMeters),
            scale: input.projectedScale,
            minimumPixels: 48.0
        )
        let majorEvery = majorLineInterval(
            minorStepMeters: minorStepMeters,
            requestedMajorStepMeters: requestedMajorStepMeters
        )
        let majorStepMeters = minorStepMeters * Double(majorEvery)
        guard majorStepMeters.isFinite, majorStepMeters > 0.0 else {
            throw NativeFrameError.invalidStep
        }
        let minorStepPixels = max(
            CGFloat(minorStepMeters) * input.projectedScale,
            8.0
        )
        let ranges = try nativeIndexRanges(
            modelBounds: modelBounds,
            step: minorStepMeters
        )
        guard ranges.totalCount <= maximumGridLineCount else {
            throw NativeFrameError.lineBudgetExceeded
        }
        let worldLines = try makeNativeLines(
            plane: plane,
            modelBounds: modelBounds,
            ranges: ranges,
            minorStepMeters: minorStepMeters,
            majorEvery: majorEvery
        )
        let screenLabels = try makeNativeLabels(
            plane: plane,
            basis: input.basis,
            modelBounds: modelBounds,
            majorStepMeters: majorStepMeters,
            projectedScale: input.projectedScale,
            viewportSize: input.viewportSize,
            unit: ruler.displayUnit,
            project: input.project,
            labelRect: input.labelRect,
            chromeExclusionRects: input.chromeExclusionRects,
            isChromeExcluded: input.isChromeExcluded
        )
        let scaleReadout = makeScaleReadout(
            minorStepMeters: minorStepMeters,
            majorStepMeters: majorStepMeters,
            snapStepMeters: ruler.minorTickMeters,
            visibleSpanMeters: max(Double(modelBounds.width), Double(modelBounds.height)),
            workspaceSpanMeters: ruler.visibleSpanMeters,
            minorStepPixels: minorStepPixels,
            unit: ruler.displayUnit,
            visualSpacingMode: input.visualSpacingMode,
            isVisualStepCapped: isVisualStepCapped
        )
        return NativeFrame(
            basis: input.basis,
            plane: plane,
            worldBounds: modelBounds,
            minorStepMeters: minorStepMeters,
            majorStepMeters: majorStepMeters,
            minorStepPixels: minorStepPixels,
            worldLines: worldLines,
            screenLabels: screenLabels,
            scaleReadout: scaleReadout
        )
    }

    private struct NativeIndexRanges {
        var first: ClosedRange<Int>
        var second: ClosedRange<Int>

        var totalCount: Int {
            first.count + second.count
        }
    }

    private static let maximumNativeLabelCount = 360

    private static func nativeVisibleModelBounds(
        viewportSize: CGSize,
        plane: ViewportCanvasPlane,
        step: Double,
        unproject: (CGPoint, ViewportCanvasPlane) -> Point3D?
    ) throws -> CGRect? {
        guard step.isFinite, step > 0.0 else {
            throw NativeFrameError.invalidStep
        }
        let viewportCorners = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: viewportSize.width, y: 0.0),
            CGPoint(x: 0.0, y: viewportSize.height),
            CGPoint(x: viewportSize.width, y: viewportSize.height),
        ]
        var modelCorners: [CGPoint] = []
        modelCorners.reserveCapacity(viewportCorners.count)
        for point in viewportCorners {
            guard let worldPoint = unproject(point, plane) else {
                continue
            }
            guard worldPoint.isFinite else {
                throw NativeFrameError.unprojectionFailed
            }
            let modelPoint = plane.coordinates(of: worldPoint)
            guard modelPoint.x.isFinite, modelPoint.y.isFinite else {
                throw NativeFrameError.invalidCoverage
            }
            modelCorners.append(modelPoint)
        }
        // Perspective views can place the grid-plane horizon inside the
        // viewport, leaving only a subset of corner rays intersecting the
        // plane. Finite intersections still define the bounded coverage;
        // only the absence of every intersection disables the grid.
        guard !modelCorners.isEmpty else {
            return nil
        }
        guard let minX = modelCorners.map(\.x).min(),
              let maxX = modelCorners.map(\.x).max(),
              let minY = modelCorners.map(\.y).min(),
              let maxY = modelCorners.map(\.y).max() else {
            throw NativeFrameError.invalidCoverage
        }
        let width = Double(maxX - minX)
        let height = Double(maxY - minY)
        let span = max(width, height, step)
        let padding = span * 0.25 + step * 4.0
        let bounds = CGRect(
            x: minX - CGFloat(padding),
            y: minY - CGFloat(padding),
            width: CGFloat(width + padding * 2.0),
            height: CGFloat(height + padding * 2.0)
        )
        guard isFiniteRect(bounds), bounds.width > 0.0, bounds.height > 0.0 else {
            throw NativeFrameError.invalidCoverage
        }
        return bounds
    }

    private static func nativeStepForLineBudget(
        _ baseStep: Double,
        modelBounds: CGRect,
        maximumLineCount: Int
    ) throws -> Double {
        guard baseStep.isFinite, baseStep > 0.0,
              maximumLineCount > 0 else {
            throw NativeFrameError.invalidStep
        }
        guard isFiniteRect(modelBounds), modelBounds.width > 0.0,
              modelBounds.height > 0.0 else {
            throw NativeFrameError.invalidCoverage
        }
        var step = max(baseStep, 1.0e-12)
        for _ in 0..<512 {
            let firstCount = nativeAxisLineCount(
                minimum: Double(modelBounds.minX),
                maximum: Double(modelBounds.maxX),
                step: step
            )
            let secondCount = nativeAxisLineCount(
                minimum: Double(modelBounds.minY),
                maximum: Double(modelBounds.maxY),
                step: step
            )
            let total = firstCount + secondCount
            if total.isFinite, total <= Double(maximumLineCount) {
                return step
            }

            let next: Double
            if total.isFinite {
                next = nextReadableStep(after: step)
            } else {
                let required = max(
                    Double(modelBounds.width),
                    Double(modelBounds.height)
                ) / Double(max(maximumLineCount / 2, 1))
                next = readableStep(atLeast: required)
            }
            guard next.isFinite, next > step else {
                throw NativeFrameError.lineBudgetExceeded
            }
            step = next
        }
        throw NativeFrameError.lineBudgetExceeded
    }

    private static func nativeAxisLineCount(
        minimum: Double,
        maximum: Double,
        step: Double
    ) -> Double {
        guard minimum.isFinite, maximum.isFinite,
              minimum <= maximum,
              step.isFinite, step > 0.0 else {
            return .infinity
        }
        let lower = floor(minimum / step)
        let upper = ceil(maximum / step)
        guard lower.isFinite, upper.isFinite, upper >= lower else {
            return .infinity
        }
        return upper - lower + 1.0
    }

    private static func nativeIndexRanges(
        modelBounds: CGRect,
        step: Double
    ) throws -> NativeIndexRanges {
        guard isFiniteRect(modelBounds), modelBounds.width > 0.0,
              modelBounds.height > 0.0,
              step.isFinite, step > 0.0 else {
            throw NativeFrameError.invalidCoverage
        }
        let first = try nativeIndexRange(
            minimum: Double(modelBounds.minX),
            maximum: Double(modelBounds.maxX),
            step: step
        )
        let second = try nativeIndexRange(
            minimum: Double(modelBounds.minY),
            maximum: Double(modelBounds.maxY),
            step: step
        )
        guard first.count <= maximumGridLineCount,
              second.count <= maximumGridLineCount,
              first.count <= Int.max - second.count else {
            throw NativeFrameError.indexBoundsOverflow
        }
        return NativeIndexRanges(first: first, second: second)
    }

    private static func nativeIndexRange(
        minimum: Double,
        maximum: Double,
        step: Double
    ) throws -> ClosedRange<Int> {
        guard minimum.isFinite, maximum.isFinite,
              minimum <= maximum,
              step.isFinite, step > 0.0 else {
            throw NativeFrameError.invalidCoverage
        }
        let lowerRatio = floor(minimum / step)
        let upperRatio = ceil(maximum / step)
        // Keep conversion well inside the exact integer range. A Double near
        // Int.max rounds to 2^63, which is not representable as an Int even
        // when a subtraction of a few units appears to leave headroom.
        let safeIntegerLimit = Double(Int.max / 4)
        guard lowerRatio.isFinite, upperRatio.isFinite,
              abs(lowerRatio) <= safeIntegerLimit,
              abs(upperRatio) <= safeIntegerLimit,
              upperRatio >= lowerRatio else {
            throw NativeFrameError.indexBoundsOverflow
        }
        let lower = Int(lowerRatio)
        let upper = Int(upperRatio)
        guard upper >= lower, upper - lower < Int.max else {
            throw NativeFrameError.indexBoundsOverflow
        }
        return lower ... upper
    }

    private static func makeNativeLines(
        plane: ViewportCanvasPlane,
        modelBounds: CGRect,
        ranges: NativeIndexRanges,
        minorStepMeters: Double,
        majorEvery: Int
    ) throws -> [NativeFrame.WorldLine] {
        guard majorEvery > 0, minorStepMeters.isFinite, minorStepMeters > 0.0 else {
            throw NativeFrameError.invalidStep
        }
        var lines: [NativeFrame.WorldLine] = []
        lines.reserveCapacity(ranges.totalCount)
        for index in ranges.second {
            let second = Double(index) * minorStepMeters
            let start = plane.worldPoint(first: Double(modelBounds.minX), second: second)
            let end = plane.worldPoint(first: Double(modelBounds.maxX), second: second)
            guard start.isFinite, end.isFinite else {
                throw NativeFrameError.projectionFailed
            }
            lines.append(
                NativeFrame.WorldLine(
                    axis: plane.firstAxis,
                    start: start,
                    end: end,
                    isMajor: index.isMultiple(of: majorEvery),
                    isOrigin: index == 0
                )
            )
        }
        for index in ranges.first {
            let first = Double(index) * minorStepMeters
            let start = plane.worldPoint(first: first, second: Double(modelBounds.minY))
            let end = plane.worldPoint(first: first, second: Double(modelBounds.maxY))
            guard start.isFinite, end.isFinite else {
                throw NativeFrameError.projectionFailed
            }
            lines.append(
                NativeFrame.WorldLine(
                    axis: plane.secondAxis,
                    start: start,
                    end: end,
                    isMajor: index.isMultiple(of: majorEvery),
                    isOrigin: index == 0
                )
            )
        }
        guard lines.count <= maximumGridLineCount else {
            throw NativeFrameError.lineBudgetExceeded
        }
        return lines
    }

    private static func makeNativeLabels(
        plane: ViewportCanvasPlane,
        basis: ViewportProjectionBasis,
        modelBounds: CGRect,
        majorStepMeters: Double,
        projectedScale: CGFloat,
        viewportSize: CGSize,
        unit: LengthDisplayUnit,
        project: (Point3D) -> CGPoint?,
        labelRect: (CGPoint, String) -> CGRect,
        chromeExclusionRects: [CGRect],
        isChromeExcluded: ((CGRect) -> Bool)?
    ) throws -> [NativeFrame.ScreenLabel] {
        let firstRange = try nativeIndexRange(
            minimum: Double(modelBounds.minX),
            maximum: Double(modelBounds.maxX),
            step: majorStepMeters
        )
        let secondRange = try nativeIndexRange(
            minimum: Double(modelBounds.minY),
            maximum: Double(modelBounds.maxY),
            step: majorStepMeters
        )
        let labelStride = try nativeScaleLabelStride(
            step: majorStepMeters,
            basis: basis,
            plane: plane,
            projectedScale: projectedScale
        )
        let firstCandidateCount = stridedCount(firstRange.count, by: labelStride)
        let secondCandidateCount = stridedCount(secondRange.count, by: labelStride)
        guard firstCandidateCount <= maximumNativeLabelCount,
              secondCandidateCount <= maximumNativeLabelCount,
              firstCandidateCount <= Int.max - secondCandidateCount else {
            throw NativeFrameError.labelBudgetExceeded
        }
        let candidateCount = firstCandidateCount + secondCandidateCount
        guard candidateCount <= maximumNativeLabelCount else {
            throw NativeFrameError.labelBudgetExceeded
        }

        let visibleRect = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: -32.0, dy: -24.0)
        var labels: [NativeFrame.ScreenLabel] = []
        labels.reserveCapacity(candidateCount)
        for index in firstRange where index != 0 && index.isMultiple(of: labelStride) {
            let value = Double(index) * majorStepMeters
            let label = try makeNativeLabel(
                axis: plane.firstAxis,
                valueMeters: value,
                worldPoint: plane.worldPoint(first: value, second: 0.0),
                basis: basis,
                unit: unit,
                project: project,
                visibleRect: visibleRect,
                labelRect: labelRect,
                chromeExclusionRects: chromeExclusionRects,
                isChromeExcluded: isChromeExcluded
            )
            if let label {
                labels.append(label)
            }
        }
        for index in secondRange where index != 0 && index.isMultiple(of: labelStride) {
            let value = Double(index) * majorStepMeters
            let label = try makeNativeLabel(
                axis: plane.secondAxis,
                valueMeters: value,
                worldPoint: plane.worldPoint(first: 0.0, second: value),
                basis: basis,
                unit: unit,
                project: project,
                visibleRect: visibleRect,
                labelRect: labelRect,
                chromeExclusionRects: chromeExclusionRects,
                isChromeExcluded: isChromeExcluded
            )
            if let label {
                labels.append(label)
            }
        }
        guard labels.count <= maximumNativeLabelCount else {
            throw NativeFrameError.labelBudgetExceeded
        }
        return labels
    }

    private static func makeNativeLabel(
        axis: Axis,
        valueMeters: Double,
        worldPoint: Point3D,
        basis: ViewportProjectionBasis,
        unit: LengthDisplayUnit,
        project: (Point3D) -> CGPoint?,
        visibleRect: CGRect,
        labelRect: (CGPoint, String) -> CGRect,
        chromeExclusionRects: [CGRect],
        isChromeExcluded: ((CGRect) -> Bool)?
    ) throws -> NativeFrame.ScreenLabel? {
        guard valueMeters.isFinite else {
            throw NativeFrameError.projectionFailed
        }
        guard abs(valueMeters) <= RulerConfiguration.visibleSpanMetersRange.upperBound + 1.0e-9 else {
            return nil
        }
        guard worldPoint.isFinite else {
            throw NativeFrameError.projectionFailed
        }
        guard let projected = project(worldPoint) else {
            return nil
        }
        guard projected.x.isFinite, projected.y.isFinite else {
            throw NativeFrameError.projectionFailed
        }
        let position = offsetLabelPosition(projected, axis: axis, basis: basis)
        let display = lengthDisplay(valueMeters: valueMeters, preferredUnit: unit)
        let rect = labelRect(position, display.text)
        guard isFiniteRect(rect), rect.width >= 0.0, rect.height >= 0.0 else {
            throw NativeFrameError.invalidLabelPlacement
        }
        guard visibleRect.intersects(rect) else {
            return nil
        }
        let intersectsRect = chromeExclusionRects.contains { $0.intersects(rect) }
        guard !intersectsRect, !(isChromeExcluded?(rect) ?? false) else {
            return nil
        }
        return NativeFrame.ScreenLabel(
            axis: axis,
            valueMeters: valueMeters,
            displayValue: display.value,
            displayUnit: display.unit,
            position: position,
            text: display.text
        )
    }

    private static func stridedCount(_ count: Int, by stride: Int) -> Int {
        guard count > 0 else { return 0 }
        let safeStride = max(stride, 1)
        return count / safeStride + (count % safeStride == 0 ? 0 : 1)
    }

    private static func nativeScaleLabelStride(
        step: Double,
        basis: ViewportProjectionBasis,
        plane: ViewportCanvasPlane,
        projectedScale: CGFloat
    ) throws -> Int {
        guard step.isFinite, step > 0.0,
              projectedScale.isFinite, projectedScale > 0.0 else {
            throw NativeFrameError.invalidStep
        }
        let firstDirection = basis.direction(for: plane.firstAxis)
        let secondDirection = basis.direction(for: plane.secondAxis)
        let firstPixels = hypot(firstDirection.dx, firstDirection.dy)
            * CGFloat(step) * projectedScale
        let secondPixels = hypot(secondDirection.dx, secondDirection.dy)
            * CGFloat(step) * projectedScale
        let majorStepPixels = max(min(firstPixels, secondPixels), 1.0e-9)
        let rawStride = ceil(Double(minimumScaleLabelSpacingPixels / majorStepPixels))
        guard rawStride.isFinite,
              rawStride >= 1.0,
              rawStride <= Double(Int.max - 2) else {
            throw NativeFrameError.indexBoundsOverflow
        }
        return max(1, Int(rawStride))
    }

    private static func offsetLabelPosition(
        _ position: CGPoint,
        axis: Axis,
        basis: ViewportProjectionBasis
    ) -> CGPoint {
        let direction = basis.direction(for: axis)
        let length = max(hypot(direction.dx, direction.dy), 1.0e-9)
        var normal = CGVector(dx: -direction.dy / length, dy: direction.dx / length)
        if normal.dy > 0.0 {
            normal = CGVector(dx: -normal.dx, dy: -normal.dy)
        }
        return CGPoint(
            x: position.x + normal.dx * 12.0,
            y: position.y + normal.dy * 12.0
        )
    }

    static func defaultNativeLabelRect(position: CGPoint, text: String) -> CGRect {
        let width = max(CGFloat(text.count) * 6.2 + 10.0, 28.0)
        return CGRect(
            x: position.x - width / 2.0,
            y: position.y - 8.0,
            width: width,
            height: 16.0
        )
    }

    private static func isFiniteRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    private static func adjustedStep(
        _ baseStep: Double,
        scale: CGFloat,
        minimumPixels: CGFloat
    ) -> Double {
        let safeScale = max(scale, 1.0e-12)
        let requiredMeters = max(
            baseStep,
            Double(minimumPixels / safeScale),
            1.0e-12
        )
        return readableStep(atLeast: requiredMeters)
    }

    private static func requestedVisualMinorStep(
        ruler: RulerConfiguration,
        scale: CGFloat,
        mode: VisualSpacingMode
    ) -> Double {
        let minorStepMeters = max(
            ruler.normalizedForWorkspaceScale().minorTickMeters,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        switch mode {
        case .adaptive:
            return adjustedStep(
                minorStepMeters,
                scale: scale,
                minimumPixels: 24.0
            )
        case .fixed:
            return minorStepMeters
        }
    }

    private static func isCappedStep(
        resolvedStepMeters: Double,
        requestedStepMeters: Double
    ) -> Bool {
        resolvedStepMeters > requestedStepMeters + max(abs(requestedStepMeters) * 1.0e-9, 1.0e-12)
    }

    static func readableStep(atLeast meters: Double) -> Double {
        guard meters.isFinite,
              meters > 0.0 else {
            return 1.0e-12
        }
        let exponent = floor(log10(meters))
        let scale = pow(10.0, exponent)
        let tolerance = meters * 1.0e-12
        for multiplier in readableStepMultipliers {
            let candidate = multiplier * scale
            if candidate + tolerance >= meters {
                return candidate
            }
        }
        return 10.0 * scale
    }

    static func nextReadableStep(after meters: Double) -> Double {
        guard meters.isFinite,
              meters > 0.0 else {
            return 1.0e-12
        }
        return readableStep(atLeast: meters * (1.0 + 1.0e-9))
    }

    private static func majorLineInterval(
        minorStepMeters: Double,
        requestedMajorStepMeters: Double
    ) -> Int {
        guard minorStepMeters.isFinite,
              requestedMajorStepMeters.isFinite,
              minorStepMeters > 0.0,
              requestedMajorStepMeters > 0.0 else {
            return 2
        }
        let ratio = max(2.0, requestedMajorStepMeters / minorStepMeters)
        return max(2, Int(readableStep(atLeast: ratio).rounded(.up)))
    }

    private static func makeScaleReadout(
        minorStepMeters: Double,
        majorStepMeters: Double,
        snapStepMeters: Double,
        visibleSpanMeters: Double,
        workspaceSpanMeters: Double,
        minorStepPixels: CGFloat,
        unit: LengthDisplayUnit,
        visualSpacingMode: VisualSpacingMode,
        isVisualStepCapped: Bool
    ) -> ScaleReadout {
        let minor = lengthDisplay(valueMeters: minorStepMeters, preferredUnit: unit)
        let major = lengthDisplay(valueMeters: majorStepMeters, preferredUnit: unit)
        let snap = lengthDisplay(valueMeters: snapStepMeters, preferredUnit: unit)
        let span = lengthDisplay(valueMeters: visibleSpanMeters, preferredUnit: unit)
        let workspaceSpan = lengthDisplay(valueMeters: workspaceSpanMeters, preferredUnit: unit)
        return ScaleReadout(
            minorStep: ScaleReadout.Length(
                meters: minorStepMeters,
                displayValue: minor.value,
                displayUnit: minor.unit,
                text: minor.text
            ),
            majorStep: ScaleReadout.Length(
                meters: majorStepMeters,
                displayValue: major.value,
                displayUnit: major.unit,
                text: major.text
            ),
            snapStep: ScaleReadout.Length(
                meters: snapStepMeters,
                displayValue: snap.value,
                displayUnit: snap.unit,
                text: snap.text
            ),
            visibleSpan: ScaleReadout.Length(
                meters: visibleSpanMeters,
                displayValue: span.value,
                displayUnit: span.unit,
                text: span.text
            ),
            workspaceSpan: ScaleReadout.Length(
                meters: workspaceSpanMeters,
                displayValue: workspaceSpan.value,
                displayUnit: workspaceSpan.unit,
                text: workspaceSpan.text
            ),
            minorStepPixels: minorStepPixels,
            visualSpacingMode: visualSpacingMode,
            isVisualStepCapped: isVisualStepCapped
        )
    }

    private static func lengthDisplay(
        valueMeters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> (value: Double, unit: LengthDisplayUnit, text: String) {
        let unit = preferredUnit.readableUnit(forMeters: valueMeters)
        let value = unit.value(fromMeters: valueMeters)
        let magnitude = abs(value)
        let maxFractionDigits: Int
        if magnitude >= 100.0 {
            maxFractionDigits = 0
        } else if magnitude >= 10.0 {
            maxFractionDigits = 1
        } else {
            maxFractionDigits = 3
        }
        let formatted = value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...maxFractionDigits))
        )
        return (value, unit, "\(formatted)\(unit.symbol)")
    }

    private static func gridPlane(for basis: ViewportProjectionBasis) -> ViewportCanvasPlane {
        ViewportCanvasPlane.displayed(for: basis)
    }
}

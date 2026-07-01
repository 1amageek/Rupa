import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

public struct ViewportProjectedGrid: Equatable {
    public typealias Axis = ViewportCoordinateAxis
    private static let maximumGridLineCount = 360

    public struct Line: Equatable {
        public var axis: Axis
        public var start: CGPoint
        public var end: CGPoint
        public var isMajor: Bool
        public var isOrigin: Bool

        public init(
            axis: Axis,
            start: CGPoint,
            end: CGPoint,
            isMajor: Bool,
            isOrigin: Bool = false
        ) {
            self.axis = axis
            self.start = start
            self.end = end
            self.isMajor = isMajor
            self.isOrigin = isOrigin
        }
    }

    public struct ScaleLabel: Equatable {
        public var axis: Axis
        public var valueMeters: Double
        public var position: CGPoint
        public var text: String

        public init(
            axis: Axis,
            valueMeters: Double,
            position: CGPoint,
            text: String
        ) {
            self.axis = axis
            self.valueMeters = valueMeters
            self.position = position
            self.text = text
        }
    }

    public var basis: ViewportProjectionBasis
    public var minorStepMeters: Double
    public var majorStepMeters: Double
    public var minorStepPixels: CGFloat
    public var lines: [Line]
    public var scaleLabels: [ScaleLabel]

    public init(
        document: DesignDocument,
        size: CGSize,
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric
    ) {
        let layout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            camera: camera,
            basis: basis
        ).layout
        let baseMinorStepMeters = Self.adjustedStep(
            document.ruler.minorTickMeters,
            scale: layout.scale,
            minimumPixels: 8.0
        )
        let basis = layout.basis
        let plane = Self.gridPlane(for: basis)
        let initialModelBounds = Self.visibleModelBounds(
            layout: layout,
            size: size,
            plane: plane,
            step: max(CGFloat(baseMinorStepMeters), 1.0e-12)
        )
        let minorStepMeters = Self.adjustedStepForLineBudget(
            baseMinorStepMeters,
            modelBounds: initialModelBounds,
            maximumLineCount: Self.maximumGridLineCount
        )
        let majorStepMeters = Self.adjustedStep(
            max(document.ruler.majorTickMeters, minorStepMeters),
            scale: layout.scale,
            minimumPixels: 48.0
        )
        let minorStepPixels = max(CGFloat(minorStepMeters) * layout.scale, 8.0)
        let majorEvery = max(1, Int((majorStepMeters / minorStepMeters).rounded()))
        let resolvedMajorStepMeters = minorStepMeters * Double(majorEvery)
        let modelBounds = Self.visibleModelBounds(
            layout: layout,
            size: size,
            plane: plane,
            step: max(CGFloat(minorStepMeters), 1.0e-12)
        )

        self.basis = basis
        self.minorStepMeters = minorStepMeters
        self.majorStepMeters = resolvedMajorStepMeters
        self.minorStepPixels = minorStepPixels
        self.lines = Self.makeLines(
            layout: layout,
            size: size,
            plane: plane,
            modelBounds: modelBounds,
            minorStepMeters: minorStepMeters,
            majorEvery: majorEvery
        )
        self.scaleLabels = Self.makeScaleLabels(
            layout: layout,
            size: size,
            plane: plane,
            modelBounds: modelBounds,
            majorStepMeters: resolvedMajorStepMeters,
            unit: document.displayUnit
        )
    }

    public func lines(for axis: Axis) -> [Line] {
        lines.filter { $0.axis == axis }
    }

    private static func adjustedStep(
        _ baseStep: Double,
        scale: CGFloat,
        minimumPixels: CGFloat
    ) -> Double {
        var step = max(baseStep, 1.0e-12)
        while CGFloat(step) * scale < minimumPixels {
            step *= 2.0
        }
        return step
    }

    private static func adjustedStepForLineBudget(
        _ baseStep: Double,
        modelBounds: CGRect,
        maximumLineCount: Int
    ) -> Double {
        var step = max(baseStep, 1.0e-12)
        while estimatedLineCount(modelBounds: modelBounds, step: step) > maximumLineCount {
            step *= 2.0
        }
        return step
    }

    private static func estimatedLineCount(
        modelBounds: CGRect,
        step: Double
    ) -> Int {
        let safeStep = max(CGFloat(step), 1.0e-12)
        let firstAxisCount = Int(ceil(modelBounds.width / safeStep)) + 5
        let secondAxisCount = Int(ceil(modelBounds.height / safeStep)) + 5
        return max(0, firstAxisCount) + max(0, secondAxisCount)
    }

    private static func makeLines(
        layout: ViewportLayout,
        size: CGSize,
        plane: GridPlane,
        modelBounds: CGRect,
        minorStepMeters: Double,
        majorEvery: Int
    ) -> [Line] {
        let step = max(CGFloat(minorStepMeters), 1.0e-12)
        let minFirstIndex = Int(floor(modelBounds.minX / step)) - 2
        let maxFirstIndex = Int(ceil(modelBounds.maxX / step)) + 2
        let minSecondIndex = Int(floor(modelBounds.minY / step)) - 2
        let maxSecondIndex = Int(ceil(modelBounds.maxY / step)) + 2
        var lines: [Line] = []
        lines.reserveCapacity(maxFirstIndex - minFirstIndex + maxSecondIndex - minSecondIndex + 2)

        for index in minSecondIndex ... maxSecondIndex {
            let second = CGFloat(index) * step
            let isMajor = index.isMultiple(of: majorEvery)
            lines.append(
                Line(
                    axis: plane.firstAxis,
                    start: project(first: modelBounds.minX, second: second, layout: layout, plane: plane),
                    end: project(first: modelBounds.maxX, second: second, layout: layout, plane: plane),
                    isMajor: isMajor,
                    isOrigin: index == 0
                )
            )
        }

        for index in minFirstIndex ... maxFirstIndex {
            let first = CGFloat(index) * step
            let isMajor = index.isMultiple(of: majorEvery)
            lines.append(
                Line(
                    axis: plane.secondAxis,
                    start: project(first: first, second: modelBounds.minY, layout: layout, plane: plane),
                    end: project(first: first, second: modelBounds.maxY, layout: layout, plane: plane),
                    isMajor: isMajor,
                    isOrigin: index == 0
                )
            )
        }

        return lines
    }

    private static func makeScaleLabels(
        layout: ViewportLayout,
        size: CGSize,
        plane: GridPlane,
        modelBounds: CGRect,
        majorStepMeters: Double,
        unit: LengthDisplayUnit
    ) -> [ScaleLabel] {
        let step = max(CGFloat(majorStepMeters), 1.0e-12)
        let minFirstIndex = Int(floor(modelBounds.minX / step))
        let maxFirstIndex = Int(ceil(modelBounds.maxX / step))
        let minSecondIndex = Int(floor(modelBounds.minY / step))
        let maxSecondIndex = Int(ceil(modelBounds.maxY / step))
        let visibleRect = CGRect(
            x: -32.0,
            y: -24.0,
            width: size.width + 64.0,
            height: size.height + 48.0
        )
        var labels: [ScaleLabel] = []
        labels.reserveCapacity(maxFirstIndex - minFirstIndex + maxSecondIndex - minSecondIndex)

        for index in minFirstIndex ... maxFirstIndex where index != 0 {
            let value = CGFloat(index) * step
            let basePosition = project(first: value, second: 0.0, layout: layout, plane: plane)
            guard visibleRect.contains(basePosition) else {
                continue
            }
            let position = offsetLabelPosition(basePosition, axis: plane.firstAxis, layout: layout)
            labels.append(
                ScaleLabel(
                    axis: plane.firstAxis,
                    valueMeters: Double(value),
                    position: position,
                    text: formattedScaleLabel(valueMeters: Double(value), unit: unit)
                )
            )
        }

        for index in minSecondIndex ... maxSecondIndex where index != 0 {
            let value = CGFloat(index) * step
            let basePosition = project(first: 0.0, second: value, layout: layout, plane: plane)
            guard visibleRect.contains(basePosition) else {
                continue
            }
            let position = offsetLabelPosition(basePosition, axis: plane.secondAxis, layout: layout)
            labels.append(
                ScaleLabel(
                    axis: plane.secondAxis,
                    valueMeters: Double(value),
                    position: position,
                    text: formattedScaleLabel(valueMeters: Double(value), unit: unit)
                )
            )
        }

        return labels
    }

    private static func offsetLabelPosition(
        _ position: CGPoint,
        axis: Axis,
        layout: ViewportLayout
    ) -> CGPoint {
        let direction = layout.basis.direction(for: axis)
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

    private static func formattedScaleLabel(
        valueMeters: Double,
        unit: LengthDisplayUnit
    ) -> String {
        let value = abs(unit.value(fromMeters: valueMeters))
        let maxFractionDigits: Int
        if value >= 100.0 {
            maxFractionDigits = 0
        } else if value >= 10.0 {
            maxFractionDigits = 1
        } else {
            maxFractionDigits = 3
        }
        let formatted = value.formatted(
            .number.precision(.fractionLength(0...maxFractionDigits))
        )
        return "\(formatted)\(unit.symbol)"
    }

    private static func visibleModelBounds(
        layout: ViewportLayout,
        size: CGSize,
        plane: GridPlane,
        step: CGFloat
    ) -> CGRect {
        let viewportCorners = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: size.width, y: 0.0),
            CGPoint(x: 0.0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        let modelCorners = viewportCorners.compactMap { unproject($0, layout: layout, plane: plane) }
        guard !modelCorners.isEmpty else {
            return CGRect(
                x: -step * 10.0,
                y: -step * 10.0,
                width: step * 20.0,
                height: step * 20.0
            )
        }
        let minX = modelCorners.map(\.x).min() ?? 0.0
        let maxX = modelCorners.map(\.x).max() ?? 0.0
        let minY = modelCorners.map(\.y).min() ?? 0.0
        let maxY = modelCorners.map(\.y).max() ?? 0.0
        let span = max(maxX - minX, maxY - minY, step)
        let padding = span * 0.25 + step * 4.0

        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2.0,
            height: maxY - minY + padding * 2.0
        )
    }

    private static func gridPlane(for basis: ViewportProjectionBasis) -> GridPlane {
        switch basis.mode {
        case .isometric:
            return GridPlane(firstAxis: .x, secondAxis: .z)
        case .axisFront(.x):
            return GridPlane(firstAxis: .z, secondAxis: .y)
        case .axisFront(.y):
            return GridPlane(firstAxis: .x, secondAxis: .z)
        case .axisFront(.z):
            return GridPlane(firstAxis: .x, secondAxis: .y)
        case .orbit:
            return GridPlane(firstAxis: .x, secondAxis: .z)
        }
    }

    private static func project(
        first: CGFloat,
        second: CGFloat,
        layout: ViewportLayout,
        plane: GridPlane
    ) -> CGPoint {
        let origin = layout.project(.zero)
        let firstDirection = layout.basis.direction(for: plane.firstAxis)
        let secondDirection = layout.basis.direction(for: plane.secondAxis)
        return CGPoint(
            x: origin.x + (firstDirection.dx * first + secondDirection.dx * second) * layout.scale,
            y: origin.y + (firstDirection.dy * first + secondDirection.dy * second) * layout.scale
        )
    }

    private static func unproject(
        _ point: CGPoint,
        layout: ViewportLayout,
        plane: GridPlane
    ) -> CGPoint? {
        let origin = layout.project(.zero)
        let firstDirection = layout.basis.direction(for: plane.firstAxis)
        let secondDirection = layout.basis.direction(for: plane.secondAxis)
        let viewportX = (point.x - origin.x) / layout.scale
        let viewportY = (point.y - origin.y) / layout.scale
        let determinant = firstDirection.dx * secondDirection.dy - secondDirection.dx * firstDirection.dy
        guard abs(determinant) > 1.0e-9 else {
            return nil
        }
        return CGPoint(
            x: (viewportX * secondDirection.dy - secondDirection.dx * viewportY) / determinant,
            y: (firstDirection.dx * viewportY - viewportX * firstDirection.dy) / determinant
        )
    }

    private struct GridPlane: Equatable {
        var firstAxis: Axis
        var secondAxis: Axis
    }
}

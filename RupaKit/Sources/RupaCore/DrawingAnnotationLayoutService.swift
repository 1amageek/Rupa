import Foundation
import SwiftCAD

public struct DrawingAnnotationLayoutService: Sendable {
    public struct Options: Equatable, Sendable {
        public var labelHeightToViewHeight: Double
        public var glyphWidthToLabelHeight: Double
        public var horizontalPaddingToLabelHeight: Double
        public var verticalPaddingToLabelHeight: Double
        public var searchRingCount: Int

        public init(
            labelHeightToViewHeight: Double = 0.018,
            glyphWidthToLabelHeight: Double = 0.56,
            horizontalPaddingToLabelHeight: Double = 0.75,
            verticalPaddingToLabelHeight: Double = 0.32,
            searchRingCount: Int = 5
        ) {
            self.labelHeightToViewHeight = labelHeightToViewHeight
            self.glyphWidthToLabelHeight = glyphWidthToLabelHeight
            self.horizontalPaddingToLabelHeight = horizontalPaddingToLabelHeight
            self.verticalPaddingToLabelHeight = verticalPaddingToLabelHeight
            self.searchRingCount = max(0, searchRingCount)
        }
    }

    private struct LabelSize {
        var width: Double
        var height: Double
        var padding: Double
    }

    private struct LabelBox: Equatable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var bounds2D: DrawingProjectionResult.Bounds2D {
            DrawingProjectionResult.Bounds2D(
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY
            )
        }

        var center: Point2D {
            Point2D(
                x: (minX + maxX) * 0.5,
                y: (minY + maxY) * 0.5
            )
        }

        func padded(by distance: Double) -> LabelBox {
            LabelBox(
                minX: minX - distance,
                minY: minY - distance,
                maxX: maxX + distance,
                maxY: maxY + distance
            )
        }

        func intersects(_ other: LabelBox) -> Bool {
            minX < other.maxX
                && maxX > other.minX
                && minY < other.maxY
                && maxY > other.minY
        }

        func overlapArea(with other: LabelBox) -> Double {
            let width = min(maxX, other.maxX) - max(minX, other.minX)
            let height = min(maxY, other.maxY) - max(minY, other.minY)
            guard width > 0.0, height > 0.0 else {
                return 0.0
            }
            return width * height
        }
    }

    private struct Candidate {
        var point: Point2D
        var box: LabelBox
        var searchIndex: Int
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func layout(
        annotations: [DrawingProjectionResult.Annotation],
        viewFrame: DrawingProjectionResult.ViewFrame
    ) -> [DrawingProjectionResult.Annotation] {
        guard annotations.isEmpty == false else {
            return []
        }

        var reservedLabelBoxes: [LabelBox] = []
        var laidOutAnnotations: [DrawingProjectionResult.Annotation] = []
        laidOutAnnotations.reserveCapacity(annotations.count)

        for (index, annotation) in annotations.enumerated() {
            let size = labelSize(for: annotation, viewFrame: viewFrame)
            let anchorCenter = centroid(annotation.anchors.map(\.point2D))
            let anchorBoxes = annotation.anchors.map {
                labelBox(centeredAt: $0.point2D, size: size)
                    .padded(by: -min(size.width, size.height) * 0.35)
            }
            let isManual = annotation.labelWorldPoint != nil
            let chosenPoint: Point2D
            let placement: DrawingProjectionResult.AnnotationLabelPlacement

            if isManual {
                chosenPoint = annotation.labelPoint2D
                placement = .manual
            } else {
                let candidate = bestAutomaticCandidate(
                    initialPoint: annotation.labelPoint2D,
                    anchorCenter: anchorCenter,
                    size: size,
                    reservedLabelBoxes: reservedLabelBoxes,
                    anchorBoxes: anchorBoxes
                )
                chosenPoint = candidate.point
                placement = distance(chosenPoint, annotation.labelPoint2D) <= size.padding * 0.25
                    ? .automatic
                    : .adjusted
            }

            let labelBox = labelBox(centeredAt: chosenPoint, size: size)
            let leader = leader(
                from: anchorCenter,
                to: labelBox,
                size: size,
                isManual: isManual
            )

            var laidOutAnnotation = annotation
            laidOutAnnotation.labelPoint2D = chosenPoint
            laidOutAnnotation.labelLayout = DrawingProjectionResult.AnnotationLabelLayout(
                placement: placement,
                bounds2D: labelBox.bounds2D,
                leaderStart2D: leader?.start,
                leaderEnd2D: leader?.end,
                priorityIndex: index
            )
            laidOutAnnotations.append(laidOutAnnotation)
            reservedLabelBoxes.append(labelBox.padded(by: size.padding))
        }

        return laidOutAnnotations
    }

    private func labelSize(
        for annotation: DrawingProjectionResult.Annotation,
        viewFrame: DrawingProjectionResult.ViewFrame
    ) -> LabelSize {
        let viewHeight = finitePositive(viewFrame.visibleHeightMeters, fallback: 1.0)
        let scaleBar = finitePositive(viewFrame.scaleBarLengthMeters, fallback: viewHeight * 0.2)
        let height = max(viewHeight * options.labelHeightToViewHeight, scaleBar * 0.055)
        let glyphWidth = height * options.glyphWidthToLabelHeight
        let horizontalPadding = height * options.horizontalPaddingToLabelHeight
        let verticalPadding = height * options.verticalPaddingToLabelHeight
        let width = max(
            height * 2.0,
            Double(annotation.displayText.count) * glyphWidth + horizontalPadding * 2.0
        )
        return LabelSize(
            width: width,
            height: height + verticalPadding * 2.0,
            padding: max(horizontalPadding, verticalPadding)
        )
    }

    private func bestAutomaticCandidate(
        initialPoint: Point2D,
        anchorCenter: Point2D,
        size: LabelSize,
        reservedLabelBoxes: [LabelBox],
        anchorBoxes: [LabelBox]
    ) -> Candidate {
        let candidates = automaticCandidates(
            initialPoint: initialPoint,
            anchorCenter: anchorCenter,
            size: size
        )
        let occupiedBoxes = reservedLabelBoxes + anchorBoxes
        if let clearCandidate = candidates.first(where: { candidate in
            occupiedBoxes.allSatisfy { $0.intersects(candidate.box) == false }
        }) {
            return clearCandidate
        }
        return candidates.min { left, right in
            let leftOverlap = totalOverlapArea(left.box, with: occupiedBoxes)
            let rightOverlap = totalOverlapArea(right.box, with: occupiedBoxes)
            if leftOverlap != rightOverlap {
                return leftOverlap < rightOverlap
            }
            let leftDistance = distance(left.point, initialPoint)
            let rightDistance = distance(right.point, initialPoint)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return left.searchIndex < right.searchIndex
        } ?? Candidate(
            point: initialPoint,
            box: labelBox(centeredAt: initialPoint, size: size),
            searchIndex: 0
        )
    }

    private func automaticCandidates(
        initialPoint: Point2D,
        anchorCenter: Point2D,
        size: LabelSize
    ) -> [Candidate] {
        let baseDirection = normalized(
            Point2D(
                x: initialPoint.x - anchorCenter.x,
                y: initialPoint.y - anchorCenter.y
            )
        ) ?? Point2D(x: 0.0, y: 1.0)
        var directions = [
            baseDirection,
            Point2D(x: 0.0, y: 1.0),
            Point2D(x: 1.0, y: 0.0),
            Point2D(x: 0.0, y: -1.0),
            Point2D(x: -1.0, y: 0.0),
            normalized(Point2D(x: 1.0, y: 1.0)) ?? Point2D(x: 1.0, y: 0.0),
            normalized(Point2D(x: -1.0, y: 1.0)) ?? Point2D(x: -1.0, y: 0.0),
            normalized(Point2D(x: 1.0, y: -1.0)) ?? Point2D(x: 1.0, y: 0.0),
            normalized(Point2D(x: -1.0, y: -1.0)) ?? Point2D(x: -1.0, y: 0.0),
        ]
        directions = uniqueDirections(directions)

        var candidates = [
            Candidate(
                point: initialPoint,
                box: labelBox(centeredAt: initialPoint, size: size),
                searchIndex: 0
            ),
        ]
        var index = 1
        let baseRadius = max(size.width, size.height) * 0.72 + size.padding
        let ringStep = max(size.height, size.padding * 2.0)
        for ring in 0..<options.searchRingCount {
            let radius = baseRadius + Double(ring) * ringStep
            for direction in directions {
                let point = Point2D(
                    x: anchorCenter.x + direction.x * radius,
                    y: anchorCenter.y + direction.y * radius
                )
                candidates.append(Candidate(
                    point: point,
                    box: labelBox(centeredAt: point, size: size),
                    searchIndex: index
                ))
                index += 1
            }
        }
        return candidates
    }

    private func labelBox(
        centeredAt point: Point2D,
        size: LabelSize
    ) -> LabelBox {
        LabelBox(
            minX: point.x - size.width * 0.5,
            minY: point.y - size.height * 0.5,
            maxX: point.x + size.width * 0.5,
            maxY: point.y + size.height * 0.5
        )
    }

    private func totalOverlapArea(
        _ box: LabelBox,
        with boxes: [LabelBox]
    ) -> Double {
        boxes.reduce(0.0) { total, other in
            total + box.overlapArea(with: other)
        }
    }

    private func leader(
        from anchorCenter: Point2D,
        to box: LabelBox,
        size: LabelSize,
        isManual: Bool
    ) -> (start: Point2D, end: Point2D)? {
        let labelCenter = box.center
        let labelDistance = distance(anchorCenter, labelCenter)
        guard labelDistance > max(size.width, size.height) * (isManual ? 0.85 : 0.45),
              let direction = normalized(Point2D(
                  x: anchorCenter.x - labelCenter.x,
                  y: anchorCenter.y - labelCenter.y
              )) else {
            return nil
        }
        let halfWidth = (box.maxX - box.minX) * 0.5
        let halfHeight = (box.maxY - box.minY) * 0.5
        let scaleX = abs(direction.x) > 1.0e-12 ? halfWidth / abs(direction.x) : Double.infinity
        let scaleY = abs(direction.y) > 1.0e-12 ? halfHeight / abs(direction.y) : Double.infinity
        let edgeScale = min(scaleX, scaleY)
        let edge = Point2D(
            x: labelCenter.x + direction.x * edgeScale,
            y: labelCenter.y + direction.y * edgeScale
        )
        return (anchorCenter, edge)
    }

    private func centroid(_ points: [Point2D]) -> Point2D {
        guard points.isEmpty == false else {
            return Point2D(x: 0.0, y: 0.0)
        }
        let sum = points.reduce(Point2D(x: 0.0, y: 0.0)) { partial, point in
            Point2D(
                x: partial.x + point.x,
                y: partial.y + point.y
            )
        }
        let count = Double(points.count)
        return Point2D(x: sum.x / count, y: sum.y / count)
    }

    private func normalized(_ point: Point2D) -> Point2D? {
        let length = hypot(point.x, point.y)
        guard length > 1.0e-12 else {
            return nil
        }
        return Point2D(x: point.x / length, y: point.y / length)
    }

    private func uniqueDirections(_ directions: [Point2D]) -> [Point2D] {
        var result: [Point2D] = []
        for direction in directions {
            guard result.contains(where: { distance($0, direction) < 1.0e-9 }) == false else {
                continue
            }
            result.append(direction)
        }
        return result
    }

    private func finitePositive(
        _ value: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite, value > 0.0 else {
            return fallback
        }
        return value
    }

    private func distance(
        _ first: Point2D,
        _ second: Point2D
    ) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }
}

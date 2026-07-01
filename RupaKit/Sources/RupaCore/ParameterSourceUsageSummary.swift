import Foundation
import SwiftCAD

public struct ParameterSourceUsageSummary: Codable, Equatable, Hashable, Sendable {
    public var featureID: String
    public var featureName: String?
    public var operation: String
    public var expressionPath: String

    public init(
        featureID: String,
        featureName: String?,
        operation: String,
        expressionPath: String
    ) {
        self.featureID = featureID
        self.featureName = featureName
        self.operation = operation
        self.expressionPath = expressionPath
    }
}

struct CADExpressionParameterReferenceCollector {
    static func parameterIDs(in expression: CADExpression) -> Set<ParameterID> {
        switch expression {
        case .constant, .variable:
            []
        case .reference(let id):
            [id]
        case .add(let left, let right),
             .subtract(let left, let right),
             .multiply(let left, let right),
             .divide(let left, let right):
            parameterIDs(in: left).union(parameterIDs(in: right))
        case .sin(let argument),
             .cos(let argument),
             .tan(let argument):
            parameterIDs(in: argument)
        }
    }
}

public struct ParameterSourceUsageService: Sendable {
    public init() {}

    public func usageMap(
        in document: CADDocument
    ) -> [ParameterID: [ParameterSourceUsageSummary]] {
        var usages: [ParameterID: [ParameterSourceUsageSummary]] = [:]
        var seen: [ParameterID: Set<ParameterSourceUsageSummary>] = [:]

        for featureID in document.designGraph.order {
            guard let node = document.designGraph.nodes[featureID] else {
                continue
            }
            collectFeatureUsages(
                node: node,
                into: &usages,
                seen: &seen
            )
        }

        return usages
    }

    private func collectFeatureUsages(
        node: FeatureNode,
        into usages: inout [ParameterID: [ParameterSourceUsageSummary]],
        seen: inout [ParameterID: Set<ParameterSourceUsageSummary>]
    ) {
        let operation = operationName(node.operation)

        func record(_ expression: CADExpression, path: String) {
            let ids = CADExpressionParameterReferenceCollector.parameterIDs(in: expression)
            guard ids.isEmpty == false else {
                return
            }
            let usage = ParameterSourceUsageSummary(
                featureID: node.id.description,
                featureName: node.name,
                operation: operation,
                expressionPath: path
            )
            for id in ids {
                if seen[id, default: []].insert(usage).inserted {
                    usages[id, default: []].append(usage)
                }
            }
        }

        switch node.operation {
        case .sketch(let sketch):
            collectSketchUsages(sketch, record: record)
        case .extrude(let feature):
            record(feature.distance, path: "extrude.distance")
        case .revolve(let feature):
            record(feature.angle, path: "revolve.angle")
        case .sweep(let feature):
            record(feature.options.twistAngle, path: "sweep.options.twistAngle")
            record(feature.options.endScale, path: "sweep.options.endScale")
            record(feature.options.distanceFraction, path: "sweep.options.distanceFraction")
        case .loft,
             .boolean,
             .polySpline,
             .bSplineSurface,
             .faceKnife,
             .faceDelete,
             .bridgeCurve,
             .curveEdit,
             .curveTrim:
            break
        case .faceLoopOffset(let feature):
            record(feature.distance, path: "faceLoopOffset.distance")
        case .edgeOffset(let feature):
            record(feature.distance, path: "edgeOffset.distance")
        case .faceDraft(let feature):
            record(feature.angle, path: "faceDraft.angle")
        case .curveOffset(let feature):
            record(feature.distance, path: "curveOffset.distance")
        }
    }

    private func collectSketchUsages(
        _ sketch: Sketch,
        record: (CADExpression, String) -> Void
    ) {
        let entities = sketch.entities.sorted { lhs, rhs in
            lhs.key.description < rhs.key.description
        }
        for (entityID, entity) in entities {
            collectSketchEntityUsages(
                entity,
                prefix: "sketch.entities[\(entityID.description)]",
                record: record
            )
        }
        for (index, dimension) in sketch.dimensions.enumerated() {
            collectSketchDimensionUsages(
                dimension,
                prefix: "sketch.dimensions[\(index)]",
                record: record
            )
        }
    }

    private func collectSketchEntityUsages(
        _ entity: SketchEntity,
        prefix: String,
        record: (CADExpression, String) -> Void
    ) {
        switch entity {
        case .point(let point):
            collectSketchPointUsages(point, prefix: "\(prefix).point", record: record)
        case .line(let line):
            collectSketchPointUsages(line.start, prefix: "\(prefix).line.start", record: record)
            collectSketchPointUsages(line.end, prefix: "\(prefix).line.end", record: record)
        case .circle(let circle):
            collectSketchPointUsages(circle.center, prefix: "\(prefix).circle.center", record: record)
            record(circle.radius, "\(prefix).circle.radius")
        case .arc(let arc):
            collectSketchPointUsages(arc.center, prefix: "\(prefix).arc.center", record: record)
            record(arc.radius, "\(prefix).arc.radius")
            record(arc.startAngle, "\(prefix).arc.startAngle")
            record(arc.endAngle, "\(prefix).arc.endAngle")
        case .spline(let spline):
            for (index, point) in spline.controlPoints.enumerated() {
                collectSketchPointUsages(
                    point,
                    prefix: "\(prefix).spline.controlPoints[\(index)]",
                    record: record
                )
            }
        }
    }

    private func collectSketchPointUsages(
        _ point: SketchPoint,
        prefix: String,
        record: (CADExpression, String) -> Void
    ) {
        record(point.x, "\(prefix).x")
        record(point.y, "\(prefix).y")
    }

    private func collectSketchDimensionUsages(
        _ dimension: SketchDimension,
        prefix: String,
        record: (CADExpression, String) -> Void
    ) {
        switch dimension {
        case .distance(_, _, let value):
            record(value, "\(prefix).distance.value")
        case .angle(_, _, let value):
            record(value, "\(prefix).angle.value")
        case .radius(_, let value):
            record(value, "\(prefix).radius.value")
        case .diameter(_, let value):
            record(value, "\(prefix).diameter.value")
        }
    }

    private func operationName(_ operation: FeatureOperation) -> String {
        switch operation {
        case .sketch:
            "sketch"
        case .extrude:
            "extrude"
        case .revolve:
            "revolve"
        case .sweep:
            "sweep"
        case .loft:
            "loft"
        case .boolean:
            "boolean"
        case .polySpline:
            "polySpline"
        case .bSplineSurface:
            "bSplineSurface"
        case .faceLoopOffset:
            "faceLoopOffset"
        case .edgeOffset:
            "edgeOffset"
        case .faceKnife:
            "faceKnife"
        case .faceDelete:
            "faceDelete"
        case .faceDraft:
            "faceDraft"
        case .bridgeCurve:
            "bridgeCurve"
        case .curveEdit:
            "curveEdit"
        case .curveOffset:
            "curveOffset"
        case .curveTrim:
            "curveTrim"
        }
    }
}

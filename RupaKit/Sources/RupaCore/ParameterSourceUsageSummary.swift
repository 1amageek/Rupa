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
        case .primitive(let feature):
            collectPrimitiveUsages(feature.definition, record: record)
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
             .patchSurface,
             .faceKnife,
             .faceDelete,
             .bridgeCurve,
             .curveDrivenPattern,
             .bridgeSurface,
             .curveMatch,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch,
             .curveEdit,
             .curveTrim:
            break
        case .faceLoopOffset(let feature):
            record(feature.distance, path: "faceLoopOffset.distance")
        case .edgeOffset(let feature):
            record(feature.distance, path: "edgeOffset.distance")
        case .faceDraft(let feature):
            record(feature.angle, path: "faceDraft.angle")
        case .faceOffset(let feature):
            record(feature.distance, path: "faceOffset.distance")
        case .faceMove(let feature):
            record(feature.translation.distance, path: "faceMove.translation.distance")
        case .edgeMove(let feature):
            record(feature.translation.distance, path: "edgeMove.translation.distance")
        case .vertexMove(let feature):
            record(feature.translation.distance, path: "vertexMove.translation.distance")
        case .linearPattern(let feature):
            record(feature.spacing, path: "linearPattern.spacing")
        case .radialPattern(let feature):
            record(feature.angularSpacing, path: "radialPattern.angularSpacing")
        case .gridPattern(let feature):
            record(feature.firstSpacing, path: "gridPattern.firstSpacing")
            record(feature.secondSpacing, path: "gridPattern.secondSpacing")
        case .chamfer(let feature):
            record(feature.distance, path: "chamfer.distance")
        case .fillet(let feature):
            record(feature.radius, path: "fillet.radius")
        case .g2Blend(let feature):
            record(feature.distance, path: "g2Blend.distance")
        case .setbackCorner(let feature):
            record(feature.radius, path: "setbackCorner.radius")
        case .shell(let feature):
            record(feature.thickness, path: "shell.thickness")
        case .thicken(let feature):
            record(feature.thickness, path: "thicken.thickness")
        case .curveExtend(let feature):
            record(feature.distance, path: "curveExtend.distance")
        case .surfaceOffset(let feature):
            record(feature.distance, path: "surfaceOffset.distance")
        case .curveOffset(let feature):
            record(feature.distance, path: "curveOffset.distance")
        }
    }

    private func collectPrimitiveUsages(
        _ definition: PrimitiveDefinition,
        record: (CADExpression, String) -> Void
    ) {
        switch definition {
        case .box(let primitive):
            record(primitive.width, "primitive.box.width")
            record(primitive.depth, "primitive.box.depth")
            record(primitive.height, "primitive.box.height")
        case .cylinder(let primitive):
            record(primitive.radius, "primitive.cylinder.radius")
            record(primitive.height, "primitive.cylinder.height")
        case .cone(let primitive):
            record(primitive.baseRadius, "primitive.cone.baseRadius")
            record(primitive.height, "primitive.cone.height")
        case .sphere(let primitive):
            record(primitive.radius, "primitive.sphere.radius")
        case .torus(let primitive):
            record(primitive.majorRadius, "primitive.torus.majorRadius")
            record(primitive.minorRadius, "primitive.torus.minorRadius")
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
        case .primitive:
            "primitive"
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
        case .patchSurface:
            "patchSurface"
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
        case .faceOffset:
            "faceOffset"
        case .faceMove:
            "faceMove"
        case .edgeMove:
            "edgeMove"
        case .vertexMove:
            "vertexMove"
        case .linearPattern:
            "linearPattern"
        case .radialPattern:
            "radialPattern"
        case .gridPattern:
            "gridPattern"
        case .curveDrivenPattern:
            "curveDrivenPattern"
        case .chamfer:
            "chamfer"
        case .fillet:
            "fillet"
        case .g2Blend:
            "g2Blend"
        case .setbackCorner:
            "setbackCorner"
        case .shell:
            "shell"
        case .thicken:
            "thicken"
        case .bridgeSurface:
            "bridgeSurface"
        case .bridgeCurve:
            "bridgeCurve"
        case .curveEdit:
            "curveEdit"
        case .curveOffset:
            "curveOffset"
        case .curveTrim:
            "curveTrim"
        case .curveExtend:
            "curveExtend"
        case .curveMatch:
            "curveMatch"
        case .surfaceOffset:
            "surfaceOffset"
        case .surfaceTrim:
            "surfaceTrim"
        case .surfaceExtend:
            "surfaceExtend"
        case .surfaceMatch:
            "surfaceMatch"
        }
    }
}

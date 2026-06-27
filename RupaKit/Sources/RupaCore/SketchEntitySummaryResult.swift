import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SketchEntitySummaryResult: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var sketchCount: Int
        public var entityCount: Int
        public var regionCount: Int
        public var constraintCount: Int
        public var dimensionCount: Int

        public init(
            sketchCount: Int = 0,
            entityCount: Int = 0,
            regionCount: Int = 0,
            constraintCount: Int = 0,
            dimensionCount: Int = 0
        ) {
            self.sketchCount = sketchCount
            self.entityCount = entityCount
            self.regionCount = regionCount
            self.constraintCount = constraintCount
            self.dimensionCount = dimensionCount
        }
    }

    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct ExpressionPoint: Codable, Equatable, Sendable {
        public var x: CADExpression
        public var y: CADExpression

        public init(x: CADExpression, y: CADExpression) {
            self.x = x
            self.y = y
        }
    }

    public struct PointHandleEntry: Codable, Equatable, Sendable {
        public var handle: SketchEntityPointHandle
        public var selectionComponentID: String

        public init(
            handle: SketchEntityPointHandle,
            selectionComponentID: String
        ) {
            self.handle = handle
            self.selectionComponentID = selectionComponentID
        }
    }

    public struct ControlPointEntry: Codable, Equatable, Sendable {
        public var index: Int
        public var selectionComponentID: String

        public init(
            index: Int,
            selectionComponentID: String
        ) {
            self.index = index
            self.selectionComponentID = selectionComponentID
        }
    }

    public struct SketchEntry: Codable, Equatable, Sendable {
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var sceneNodeID: String?
        public var plane: SketchPlane
        public var entityCount: Int
        public var constraintCount: Int
        public var dimensionCount: Int

        public init(
            sourceFeatureID: String,
            sourceFeatureName: String?,
            sceneNodeID: String?,
            plane: SketchPlane,
            entityCount: Int,
            constraintCount: Int,
            dimensionCount: Int
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.sceneNodeID = sceneNodeID
            self.plane = plane
            self.entityCount = entityCount
            self.constraintCount = constraintCount
            self.dimensionCount = dimensionCount
        }
    }

    public struct ConstraintEntry: Codable, Equatable, Sendable {
        public var kind: String
        public var references: [String]

        public init(kind: String, references: [String]) {
            self.kind = kind
            self.references = references
        }
    }

    public struct DimensionEntry: Codable, Equatable, Sendable {
        public var kind: String
        public var references: [String]
        public var expression: CADExpression
        public var resolvedValue: Double

        public init(
            kind: String,
            references: [String],
            expression: CADExpression,
            resolvedValue: Double
        ) {
            self.kind = kind
            self.references = references
            self.expression = expression
            self.resolvedValue = resolvedValue
        }
    }

    public struct EntityEntry: Codable, Equatable, Sendable {
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var sceneNodeID: String?
        public var entityID: String
        public var entityKind: String
        public var selectionComponentID: String?
        public var pointHandles: [PointHandleEntry]
        public var controlPointTargets: [ControlPointEntry]
        public var start: Point?
        public var end: Point?
        public var center: Point?
        public var controlPoints: [Point]
        public var radius: Double?
        public var startAngle: Double?
        public var endAngle: Double?
        public var startExpression: ExpressionPoint?
        public var endExpression: ExpressionPoint?
        public var centerExpression: ExpressionPoint?
        public var controlPointExpressions: [ExpressionPoint]
        public var radiusExpression: CADExpression?
        public var startAngleExpression: CADExpression?
        public var endAngleExpression: CADExpression?
        public var constraints: [ConstraintEntry]
        public var dimensions: [DimensionEntry]

        public init(
            sourceFeatureID: String,
            sourceFeatureName: String?,
            sceneNodeID: String?,
            entityID: String,
            entityKind: String,
            selectionComponentID: String?,
            pointHandles: [PointHandleEntry] = [],
            controlPointTargets: [ControlPointEntry] = [],
            start: Point? = nil,
            end: Point? = nil,
            center: Point? = nil,
            controlPoints: [Point] = [],
            radius: Double? = nil,
            startAngle: Double? = nil,
            endAngle: Double? = nil,
            startExpression: ExpressionPoint? = nil,
            endExpression: ExpressionPoint? = nil,
            centerExpression: ExpressionPoint? = nil,
            controlPointExpressions: [ExpressionPoint] = [],
            radiusExpression: CADExpression? = nil,
            startAngleExpression: CADExpression? = nil,
            endAngleExpression: CADExpression? = nil,
            constraints: [ConstraintEntry] = [],
            dimensions: [DimensionEntry] = []
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.sceneNodeID = sceneNodeID
            self.entityID = entityID
            self.entityKind = entityKind
            self.selectionComponentID = selectionComponentID
            self.pointHandles = pointHandles
            self.controlPointTargets = controlPointTargets
            self.start = start
            self.end = end
            self.center = center
            self.controlPoints = controlPoints
            self.radius = radius
            self.startAngle = startAngle
            self.endAngle = endAngle
            self.startExpression = startExpression
            self.endExpression = endExpression
            self.centerExpression = centerExpression
            self.controlPointExpressions = controlPointExpressions
            self.radiusExpression = radiusExpression
            self.startAngleExpression = startAngleExpression
            self.endAngleExpression = endAngleExpression
            self.constraints = constraints
            self.dimensions = dimensions
        }

        public func selectionTarget() -> SelectionTarget? {
            guard let sceneNodeID,
                  let sceneNodeUUID = UUID(uuidString: sceneNodeID),
                  let selectionComponentID else {
                return nil
            }
            return SelectionTarget(
                sceneNodeID: SceneNodeID(sceneNodeUUID),
                component: .sketchEntity(SelectionComponentID(rawValue: selectionComponentID))
            )
        }
    }

    public struct RegionEntry: Codable, Equatable, Sendable {
        public var sourceFeatureID: String
        public var sourceFeatureName: String?
        public var sceneNodeID: String?
        public var profileIndex: Int
        public var selectionComponentID: String?
        public var plane: SketchPlane
        public var center: Point
        public var areaSquareMeters: Double
        public var boundaryPointCount: Int
        public var boundarySegmentCount: Int
        public var boundaryPoints: [Point]

        public init(
            sourceFeatureID: String,
            sourceFeatureName: String?,
            sceneNodeID: String?,
            profileIndex: Int,
            selectionComponentID: String?,
            plane: SketchPlane,
            center: Point,
            areaSquareMeters: Double,
            boundaryPointCount: Int,
            boundarySegmentCount: Int,
            boundaryPoints: [Point]
        ) {
            self.sourceFeatureID = sourceFeatureID
            self.sourceFeatureName = sourceFeatureName
            self.sceneNodeID = sceneNodeID
            self.profileIndex = profileIndex
            self.selectionComponentID = selectionComponentID
            self.plane = plane
            self.center = center
            self.areaSquareMeters = areaSquareMeters
            self.boundaryPointCount = boundaryPointCount
            self.boundarySegmentCount = boundarySegmentCount
            self.boundaryPoints = boundaryPoints
        }

        public func selectionTarget() -> SelectionTarget? {
            guard let sceneNodeID,
                  let sceneNodeUUID = UUID(uuidString: sceneNodeID),
                  let selectionComponentID else {
                return nil
            }
            return SelectionTarget(
                sceneNodeID: SceneNodeID(sceneNodeUUID),
                component: .region(SelectionComponentID(rawValue: selectionComponentID))
            )
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var counts: Counts
    public var sketches: [SketchEntry]
    public var entries: [EntityEntry]
    public var regions: [RegionEntry]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        counts: Counts = Counts(),
        sketches: [SketchEntry] = [],
        entries: [EntityEntry] = [],
        regions: [RegionEntry] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.displayUnit = displayUnit
        self.counts = counts
        self.sketches = sketches
        self.entries = entries
        self.regions = regions
        self.diagnostics = diagnostics
    }
}

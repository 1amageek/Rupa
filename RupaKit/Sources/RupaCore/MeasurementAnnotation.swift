import Foundation
import SwiftCAD

public struct MeasurementAnnotation: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case distance
        case radius
        case diameter
        case angle
        case perimeter
        case area
        case edgeLength
    }

    public var id: MeasurementAnnotationID
    public var sceneNodeID: SceneNodeID?
    public var name: String
    public var kind: Kind
    public var anchors: [MeasurementAnchor]
    public var labelPosition: Point3D?
    public var placementAxis: Vector3D?

    public init(
        id: MeasurementAnnotationID = MeasurementAnnotationID(),
        sceneNodeID: SceneNodeID? = nil,
        name: String,
        kind: Kind,
        anchors: [MeasurementAnchor],
        labelPosition: Point3D? = nil,
        placementAxis: Vector3D? = nil
    ) {
        self.id = id
        self.sceneNodeID = sceneNodeID
        self.name = name
        self.kind = kind
        self.anchors = anchors
        self.labelPosition = labelPosition
        self.placementAxis = placementAxis
    }

    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata(
                "Measurement annotation names must not be empty."
            )
        }
        switch kind {
        case .distance, .angle:
            guard anchors.count >= 2 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Distance and angle measurement annotations require at least two anchors."
                )
            }
        case .perimeter:
            guard anchors.count >= 3 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Perimeter measurement annotations require at least three anchors."
                )
            }
        case .area:
            let hasSingleTopologyFaceAnchor = anchors.count == 1
                && anchors.first?.referencesTopology(kind: .face) == true
            guard anchors.count >= 3 || hasSingleTopologyFaceAnchor else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Area measurement annotations require at least three boundary anchors or one generated face anchor."
                )
            }
        case .edgeLength:
            guard anchors.count == 1,
                  anchors.first?.referencesTopology(kind: .edge) == true else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Edge-length measurement annotations require one generated edge anchor."
                )
            }
        case .radius, .diameter:
            guard anchors.isEmpty == false else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Radius and diameter measurement annotations require at least one anchor."
                )
            }
        }
        for anchor in anchors {
            try anchor.validate()
        }
        try labelPosition?.validate()
        if let placementAxis {
            try placementAxis.validate()
            guard placementAxis.length > 1.0e-12 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Measurement annotation placement axes must not be zero length."
                )
            }
        }
    }
}

public struct MeasurementAnchor: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case worldPoint
        case sketchReference
        case topologyReference
        case sketchCurveParameter
        case topologyEdgeParameter
    }

    public enum Role: String, Codable, Hashable, Sendable {
        case point
        case start
        case end
        case center
    }

    public var kind: Kind
    public var role: Role
    public var worldPoint: Point3D?
    public var sketchReference: MeasurementSketchAnchor?
    public var topologyReference: MeasurementTopologyAnchor?
    public var sketchCurveParameter: MeasurementSketchCurveAnchor?
    public var topologyEdgeParameter: MeasurementTopologyEdgeAnchor?

    public init(
        kind: Kind = .worldPoint,
        role: Role = .point,
        worldPoint: Point3D? = nil,
        sketchReference: MeasurementSketchAnchor? = nil,
        topologyReference: MeasurementTopologyAnchor? = nil,
        sketchCurveParameter: MeasurementSketchCurveAnchor? = nil,
        topologyEdgeParameter: MeasurementTopologyEdgeAnchor? = nil
    ) {
        self.kind = kind
        self.role = role
        self.worldPoint = worldPoint
        self.sketchReference = sketchReference
        self.topologyReference = topologyReference
        self.sketchCurveParameter = sketchCurveParameter
        self.topologyEdgeParameter = topologyEdgeParameter
    }

    public static func worldPoint(
        _ point: Point3D,
        role: Role = .point
    ) -> MeasurementAnchor {
        MeasurementAnchor(
            kind: .worldPoint,
            role: role,
            worldPoint: point
        )
    }

    public static func sketchReference(
        featureID: FeatureID,
        reference: SketchReference,
        role: Role = .point
    ) -> MeasurementAnchor {
        MeasurementAnchor(
            kind: .sketchReference,
            role: role,
            sketchReference: MeasurementSketchAnchor(
                featureID: featureID,
                reference: reference
            )
        )
    }

    public static func topologyReference(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent,
        kind topologyKind: TopologySummaryResult.Entry.Kind,
        stableReference: StableSubshapeReference,
        referenceID: String? = nil,
        role: Role = .point
    ) -> MeasurementAnchor {
        MeasurementAnchor(
            kind: .topologyReference,
            role: role,
            topologyReference: MeasurementTopologyAnchor(
                sceneNodeID: sceneNodeID,
                component: component,
                kind: topologyKind,
                stableReference: stableReference,
                referenceID: referenceID
            )
        )
    }

    public static func sketchCurveParameter(
        featureID: FeatureID,
        entityID: SketchEntityID,
        parameter: Double,
        role: Role = .point
    ) -> MeasurementAnchor {
        MeasurementAnchor(
            kind: .sketchCurveParameter,
            role: role,
            sketchCurveParameter: MeasurementSketchCurveAnchor(
                featureID: featureID,
                entityID: entityID,
                parameter: parameter
            )
        )
    }

    public static func topologyEdgeParameter(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent,
        stableReference: StableSubshapeReference,
        referenceID: String? = nil,
        parameter: Double,
        role: Role = .point
    ) -> MeasurementAnchor {
        MeasurementAnchor(
            kind: .topologyEdgeParameter,
            role: role,
            topologyEdgeParameter: MeasurementTopologyEdgeAnchor(
                sceneNodeID: sceneNodeID,
                component: component,
                stableReference: stableReference,
                referenceID: referenceID,
                parameter: parameter
            )
        )
    }

    public func validate() throws {
        switch kind {
        case .worldPoint:
            guard let worldPoint,
                  sketchReference == nil,
                  topologyReference == nil,
                  sketchCurveParameter == nil,
                  topologyEdgeParameter == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "World-point measurement anchors require only a world point."
                )
            }
            try worldPoint.validate()
        case .sketchReference:
            guard worldPoint == nil,
                  let sketchReference,
                  topologyReference == nil,
                  sketchCurveParameter == nil,
                  topologyEdgeParameter == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch-reference measurement anchors require only a sketch reference."
                )
            }
            try sketchReference.validate()
        case .topologyReference:
            guard worldPoint == nil,
                  sketchReference == nil,
                  let topologyReference,
                  sketchCurveParameter == nil,
                  topologyEdgeParameter == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology-reference measurement anchors require only a topology reference."
                )
            }
            try topologyReference.validate()
        case .sketchCurveParameter:
            guard worldPoint == nil,
                  sketchReference == nil,
                  topologyReference == nil,
                  let sketchCurveParameter,
                  topologyEdgeParameter == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch-curve-parameter measurement anchors require only a sketch curve parameter."
                )
            }
            try sketchCurveParameter.validate()
        case .topologyEdgeParameter:
            guard worldPoint == nil,
                  sketchReference == nil,
                  topologyReference == nil,
                  sketchCurveParameter == nil,
                  let topologyEdgeParameter else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology-edge-parameter measurement anchors require only a topology edge parameter."
                )
            }
            try topologyEdgeParameter.validate()
        }
    }

    fileprivate func referencesTopology(
        kind topologyKind: TopologySummaryResult.Entry.Kind
    ) -> Bool {
        guard kind == .topologyReference,
              let topologyReference else {
            return false
        }
        return topologyReference.kind == topologyKind
    }
}

public struct MeasurementSketchAnchor: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var reference: SketchReference

    public init(
        featureID: FeatureID,
        reference: SketchReference
    ) {
        self.featureID = featureID
        self.reference = reference
    }

    public func validate() throws {}
}

public struct MeasurementSketchCurveAnchor: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var entityID: SketchEntityID
    public var parameter: Double

    public init(
        featureID: FeatureID,
        entityID: SketchEntityID,
        parameter: Double
    ) {
        self.featureID = featureID
        self.entityID = entityID
        self.parameter = parameter
    }

    public func validate() throws {
        try validateNormalizedMeasurementParameter(
            parameter,
            label: "Sketch-curve-parameter measurement anchors"
        )
    }
}

public struct MeasurementTopologyAnchor: Codable, Hashable, Sendable {
    public var sceneNodeID: SceneNodeID
    public var component: SelectionComponent
    public var kind: TopologySummaryResult.Entry.Kind
    public var stableReference: StableSubshapeReference
    public var referenceID: String?

    public init(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent,
        kind: TopologySummaryResult.Entry.Kind,
        stableReference: StableSubshapeReference,
        referenceID: String? = nil
    ) {
        self.sceneNodeID = sceneNodeID
        self.component = component
        self.kind = kind
        self.stableReference = stableReference
        self.referenceID = referenceID
    }

    public func validate() throws {
        try stableReference.validate()
        if let referenceID {
            guard !referenceID.isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology-reference measurement anchors require a non-empty reference ID."
                )
            }
        }
    }
}

public struct MeasurementTopologyEdgeAnchor: Codable, Hashable, Sendable {
    public var sceneNodeID: SceneNodeID
    public var component: SelectionComponent
    public var stableReference: StableSubshapeReference
    public var referenceID: String?
    public var parameter: Double

    public init(
        sceneNodeID: SceneNodeID,
        component: SelectionComponent,
        stableReference: StableSubshapeReference,
        referenceID: String? = nil,
        parameter: Double
    ) {
        self.sceneNodeID = sceneNodeID
        self.component = component
        self.stableReference = stableReference
        self.referenceID = referenceID
        self.parameter = parameter
    }

    public func validate() throws {
        guard case .edge = component else {
            throw DocumentValidationError.invalidProductMetadata(
                "Topology-edge-parameter measurement anchors require an edge selection component."
            )
        }
        try stableReference.validate()
        if let referenceID {
            guard !referenceID.isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Topology-edge-parameter measurement anchors require a non-empty reference ID."
                )
            }
        }
        try validateNormalizedMeasurementParameter(
            parameter,
            label: "Topology-edge-parameter measurement anchors"
        )
    }
}

private func validateNormalizedMeasurementParameter(
    _ parameter: Double,
    label: String
) throws {
    guard parameter.isFinite,
          parameter >= 0.0,
          parameter <= 1.0 else {
        throw DocumentValidationError.invalidProductMetadata(
            "\(label) require a finite normalized parameter in 0...1."
        )
    }
}

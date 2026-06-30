import SwiftCAD

public enum BridgeCurveEndpointHandleRole: String, Codable, Equatable, Hashable, Sendable {
    case first
    case second
}

public struct BridgeCurveEndpointHandle: Codable, Equatable, Hashable, Sendable {
    public var sourceID: BridgeCurveSourceID
    public var featureID: FeatureID
    public var bridgeEntityID: SketchEntityID
    public var role: BridgeCurveEndpointHandleRole
    public var endpoint: BridgeCurveEndpoint
    public var point: Point2D
    public var outgoingTangent: Point2D
    public var referenceDescription: String
    public var pointReference: SketchReference?

    public init(
        sourceID: BridgeCurveSourceID,
        featureID: FeatureID,
        bridgeEntityID: SketchEntityID,
        role: BridgeCurveEndpointHandleRole,
        endpoint: BridgeCurveEndpoint,
        point: Point2D,
        outgoingTangent: Point2D,
        referenceDescription: String,
        pointReference: SketchReference?
    ) {
        self.sourceID = sourceID
        self.featureID = featureID
        self.bridgeEntityID = bridgeEntityID
        self.role = role
        self.endpoint = endpoint
        self.point = point
        self.outgoingTangent = outgoingTangent
        self.referenceDescription = referenceDescription
        self.pointReference = pointReference
    }
}

public struct BridgeCurveEndpointHandleService: Sendable {
    private let resolver: SketchCurveEndpointResolver

    public init() {
        self.resolver = SketchCurveEndpointResolver()
    }

    public func handles(
        for selection: SelectionModel,
        in document: DesignDocument
    ) throws -> [BridgeCurveEndpointHandle] {
        let selectedBridgeKeys = selectedBridgeSourceKeys(
            selection: selection,
            document: document
        )
        guard selectedBridgeKeys.isEmpty == false else {
            return []
        }
        return try selectedBridgeKeys.flatMap { sourceID in
            try handles(for: sourceID, in: document)
        }
    }

    public func handles(
        for sourceID: BridgeCurveSourceID,
        in document: DesignDocument
    ) throws -> [BridgeCurveEndpointHandle] {
        guard let source = document.productMetadata.bridgeCurveSources[sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source could not be resolved."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[source.featureID],
              case .sketch(let sketch) = feature.operation,
              case .spline = sketch.entities[source.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source must point to an editable generated spline."
            )
        }
        return [
            try handle(
                source: source,
                endpoint: source.firstEndpoint,
                role: .first,
                sketch: sketch,
                document: document
            ),
            try handle(
                source: source,
                endpoint: source.secondEndpoint,
                role: .second,
                sketch: sketch,
                document: document
            ),
        ]
    }

    private func handle(
        source: BridgeCurveSource,
        endpoint: BridgeCurveEndpoint,
        role: BridgeCurveEndpointHandleRole,
        sketch: Sketch,
        document: DesignDocument
    ) throws -> BridgeCurveEndpointHandle {
        guard let sample = try resolver.sample(
            for: endpoint,
            sketch: sketch,
            document: document
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoint handle must resolve to a line, arc, or spline curve position."
            )
        }
        return BridgeCurveEndpointHandle(
            sourceID: source.id,
            featureID: source.featureID,
            bridgeEntityID: source.entityID,
            role: role,
            endpoint: endpoint,
            point: sample.sample.point,
            outgoingTangent: sample.outgoingTangent,
            referenceDescription: sample.referenceDescription,
            pointReference: sample.pointReference
        )
    }

    private func selectedBridgeSourceKeys(
        selection: SelectionModel,
        document: DesignDocument
    ) -> [BridgeCurveSourceID] {
        var result: [BridgeCurveSourceID] = []
        for target in selection.selectedTargets {
            guard case .sketchEntity(let componentID) = target.component,
                  let reference = componentID.sketchEntityBaseReference else {
                continue
            }
            for source in document.productMetadata.bridgeCurveSources.values
                where source.featureID == reference.featureID && source.entityID == reference.entityID {
                if result.contains(source.id) == false {
                    result.append(source.id)
                }
            }
        }
        return result.sorted { $0.description < $1.description }
    }
}

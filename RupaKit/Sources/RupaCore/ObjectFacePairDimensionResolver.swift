import Foundation

struct ObjectFacePairDimension: Sendable {
    var target: SelectionTarget
    var kind: ObjectDimensionKind
    var source: ObjectDimensionSource
}

struct ObjectFacePairDimensionResolver: Sendable {
    func resolveIfPresent(
        first: SelectionTarget,
        second: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        topology: TopologySummaryResult? = nil,
        operationName: String = "Object face-pair dimension"
    ) throws -> ObjectFacePairDimension? {
        guard first.sceneNodeID == second.sceneNodeID,
              case .face = first.component,
              case .face = second.component else {
            return nil
        }

        let resolvedTopology: TopologySummaryResult
        if let topology {
            resolvedTopology = topology
        } else {
            resolvedTopology = try TopologySummaryService().summarize(
                document: document,
                objectRegistry: objectRegistry
            )
        }
        let topologyResolver = GeneratedTopologySelectionResolver()
        let firstFace: BodyFace
        let secondFace: BodyFace
        do {
            firstFace = try topologyResolver.bodyFace(
                for: first,
                in: document,
                topology: resolvedTopology,
                operationName: operationName
            )
            secondFace = try topologyResolver.bodyFace(
                for: second,
                in: document,
                topology: resolvedTopology,
                operationName: operationName
            )
        } catch let error as EditorError where error.code == .commandInvalid {
            return nil
        }

        let sourceResolver = ObjectDimensionSourceResolver()
        let firstSource = try sourceResolver.resolve(target: first, in: document)
        let secondSource = try sourceResolver.resolve(target: second, in: document)
        guard firstSource.featureID == secondSource.featureID,
              firstSource.sceneNodeID == secondSource.sceneNodeID,
              firstSource.shape == secondSource.shape else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated faces from one editable source body."
            )
        }

        let kind = try objectDimensionKind(
            firstFace: firstFace,
            secondFace: secondFace,
            sourceShape: firstSource.shape,
            operationName: operationName
        )
        return ObjectFacePairDimension(
            target: first,
            kind: kind,
            source: firstSource
        )
    }

    private func objectDimensionKind(
        firstFace: BodyFace,
        secondFace: BodyFace,
        sourceShape: ObjectDimensionSource.Shape,
        operationName: String
    ) throws -> ObjectDimensionKind {
        let facePair = Set([firstFace, secondFace])
        switch sourceShape {
        case .box:
            if facePair == Set([.left, .right]) {
                return .sizeX
            }
            if facePair == Set([.front, .back]) {
                return .sizeY
            }
            if facePair == Set([.bottom, .top]) {
                return .sizeZ
            }
        case .cylinder:
            if facePair == Set([.front, .back]) {
                return .sizeY
            }
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) requires opposing editable body faces."
        )
    }
}

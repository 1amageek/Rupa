import Foundation
import RupaCoreTypes

struct ObjectFaceDimension: Sendable {
    var target: SelectionTarget
    var kind: ObjectDimensionKind
    var source: ObjectDimensionSource
}

struct ObjectFaceDimensionResolver: Sendable {
    func resolveSingleIfPresent(
        target: SelectionTarget,
        source: ObjectDimensionSource,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        topology: TopologySnapshot? = nil,
        operationName: String = "Object face dimension"
    ) throws -> ObjectFaceDimension? {
        guard let face = try bodyFaceIfPresent(
            for: target,
            in: document,
            objectRegistry: objectRegistry,
            topology: topology,
            operationName: operationName
        ) else {
            return nil
        }
        guard let kind = objectDimensionKind(
            face: face,
            sourceShape: source.shape
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a supported editable body face."
            )
        }
        return ObjectFaceDimension(
            target: target,
            kind: kind,
            source: source
        )
    }

    func resolvePairIfPresent(
        first: SelectionTarget,
        second: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        topology: TopologySnapshot? = nil,
        operationName: String = "Object face-pair dimension"
    ) throws -> ObjectFaceDimension? {
        guard first.sceneNodeID == second.sceneNodeID else {
            return nil
        }
        guard let firstFace = try bodyFaceIfPresent(
            for: first,
            in: document,
            objectRegistry: objectRegistry,
            topology: topology,
            operationName: operationName
        ), let secondFace = try bodyFaceIfPresent(
            for: second,
            in: document,
            objectRegistry: objectRegistry,
            topology: topology,
            operationName: operationName
        ) else {
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
                message: "\(operationName) requires faces from one editable source body."
            )
        }

        let kind = try objectDimensionKind(
            firstFace: firstFace,
            secondFace: secondFace,
            sourceShape: firstSource.shape,
            operationName: operationName
        )
        return ObjectFaceDimension(
            target: first,
            kind: kind,
            source: firstSource
        )
    }

    private func bodyFaceIfPresent(
        for target: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry,
        topology: TopologySnapshot?,
        operationName: String
    ) throws -> BodyFace? {
        guard case .face(let componentID) = target.component else {
            return nil
        }
        if let bodyFace = fixedBodyFace(for: componentID) {
            return bodyFace
        }
        guard componentID.isStableTopology else {
            return nil
        }
        let topologyResolver = GeneratedTopologySelectionResolver()
        if let topology {
            return try topologyResolver.bodyFace(
                for: target,
                in: document,
                topology: topology,
                operationName: operationName
            )
        }
        return try topologyResolver.bodyFace(
            for: target,
            in: document,
            objectRegistry: objectRegistry,
            operationName: operationName
        )
    }

    private func fixedBodyFace(for componentID: SelectionComponentID) -> BodyFace? {
        switch componentID {
        case .bodyFaceFront:
            .front
        case .bodyFaceBack:
            .back
        case .bodyFaceTop:
            .top
        case .bodyFaceBottom:
            .bottom
        case .bodyFaceLeft:
            .left
        case .bodyFaceRight:
            .right
        case .bodyFaceSide:
            .side
        default:
            nil
        }
    }

    private func objectDimensionKind(
        face: BodyFace,
        sourceShape: ObjectDimensionSource.Shape
    ) -> ObjectDimensionKind? {
        switch sourceShape {
        case .box:
            switch face {
            case .left, .right:
                .sizeX
            case .front, .back:
                .sizeY
            case .bottom, .top:
                .sizeZ
            case .side:
                nil
            }
        case .cylinder:
            switch face {
            case .front, .back:
                .sizeY
            case .side:
                .diameter
            case .left, .right, .bottom, .top:
                nil
            }
        }
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

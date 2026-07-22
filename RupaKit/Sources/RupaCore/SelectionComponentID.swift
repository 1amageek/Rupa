import Foundation
import SwiftCAD

public struct SelectionComponentID: Codable, Equatable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension SelectionComponentID {
    static let stableTopologyPrefix = "stableTopology:"
    static let sketchEntityPrefix = "sketchEntity:"
    static let sketchPointHandlePrefix = "sketchPointHandle:"
    static let sketchControlPointPrefix = "sketchControlPoint:"
    static let profileRegionPrefix = "profileRegion:"

    static func stableTopology(
        _ reference: StableSubshapeReference
    ) throws -> SelectionComponentID {
        try reference.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(reference).base64EncodedString()
        return SelectionComponentID(rawValue: "\(stableTopologyPrefix)\(payload)")
    }

    static func sketchEntity(featureID: FeatureID, entityID: SketchEntityID) -> SelectionComponentID {
        SelectionComponentID(rawValue: "\(sketchEntityPrefix)\(featureID.description):\(entityID.description)")
    }

    static func sketchPointHandle(
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle
    ) -> SelectionComponentID {
        SelectionComponentID(
            rawValue: "\(sketchPointHandlePrefix)\(featureID.description):\(entityID.description):\(handle.rawValue)"
        )
    }

    static func sketchControlPoint(
        featureID: FeatureID,
        entityID: SketchEntityID,
        index: Int
    ) -> SelectionComponentID {
        SelectionComponentID(
            rawValue: "\(sketchControlPointPrefix)\(featureID.description):\(entityID.description):\(index)"
        )
    }

    static func profileRegion(featureID: FeatureID, profileIndex: Int) -> SelectionComponentID {
        SelectionComponentID(rawValue: "\(profileRegionPrefix)\(featureID.description):\(profileIndex)")
    }

    var isStableTopology: Bool {
        rawValue.hasPrefix(Self.stableTopologyPrefix)
    }

    func stableTopologyReference(
        operationName: String
    ) throws -> StableSubshapeReference {
        guard isStableTopology else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a stable topology selection component."
            )
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: Self.stableTopologyPrefix.count)
        let payload = String(rawValue[start...])
        guard let data = Data(base64Encoded: payload) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) contains an invalid stable topology payload."
            )
        }
        do {
            let reference = try JSONDecoder().decode(StableSubshapeReference.self, from: data)
            try reference.validate()
            return reference
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) contains an invalid stable topology reference: \(error)."
            )
        }
    }

    var sketchEntityReference: (featureID: FeatureID, entityID: SketchEntityID)? {
        guard rawValue.hasPrefix(Self.sketchEntityPrefix) else {
            return nil
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: Self.sketchEntityPrefix.count)
        let payload = rawValue[start...]
        let components = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let featureUUID = UUID(uuidString: String(components[0])),
              let entityUUID = UUID(uuidString: String(components[1])) else {
            return nil
        }
        return (FeatureID(featureUUID), SketchEntityID(entityUUID))
    }

    var sketchPointHandleReference: (
        featureID: FeatureID,
        entityID: SketchEntityID,
        handle: SketchEntityPointHandle
    )? {
        guard rawValue.hasPrefix(Self.sketchPointHandlePrefix) else {
            return nil
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: Self.sketchPointHandlePrefix.count)
        let payload = rawValue[start...]
        let components = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              let featureUUID = UUID(uuidString: String(components[0])),
              let entityUUID = UUID(uuidString: String(components[1])),
              let handle = SketchEntityPointHandle(rawValue: String(components[2])) else {
            return nil
        }
        return (FeatureID(featureUUID), SketchEntityID(entityUUID), handle)
    }

    var sketchControlPointReference: (
        featureID: FeatureID,
        entityID: SketchEntityID,
        index: Int
    )? {
        guard rawValue.hasPrefix(Self.sketchControlPointPrefix) else {
            return nil
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: Self.sketchControlPointPrefix.count)
        let payload = rawValue[start...]
        let components = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              let featureUUID = UUID(uuidString: String(components[0])),
              let entityUUID = UUID(uuidString: String(components[1])),
              let index = Int(components[2]),
              index >= 0 else {
            return nil
        }
        return (FeatureID(featureUUID), SketchEntityID(entityUUID), index)
    }

    var sketchEntityBaseReference: (featureID: FeatureID, entityID: SketchEntityID)? {
        if let reference = sketchEntityReference {
            return reference
        }
        if let reference = sketchPointHandleReference {
            return (reference.featureID, reference.entityID)
        }
        if let reference = sketchControlPointReference {
            return (reference.featureID, reference.entityID)
        }
        return nil
    }

    var sketchPointReference: (featureID: FeatureID, reference: SketchReference)? {
        if let reference = sketchPointHandleReference {
            return (
                reference.featureID,
                reference.handle.sketchReference(entityID: reference.entityID)
            )
        }
        if let reference = sketchControlPointReference {
            return (
                reference.featureID,
                .splineControlPoint(entity: reference.entityID, index: reference.index)
            )
        }
        return nil
    }

    var profileRegionReference: (featureID: FeatureID, profileIndex: Int)? {
        guard rawValue.hasPrefix(Self.profileRegionPrefix) else {
            return nil
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: Self.profileRegionPrefix.count)
        let payload = rawValue[start...]
        let components = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let featureUUID = UUID(uuidString: String(components[0])),
              let profileIndex = Int(components[1]),
              profileIndex >= 0 else {
            return nil
        }
        return (FeatureID(featureUUID), profileIndex)
    }

    static let bodyFaceFront = SelectionComponentID(rawValue: "body.face.front")
    static let bodyFaceBack = SelectionComponentID(rawValue: "body.face.back")
    static let bodyFaceTop = SelectionComponentID(rawValue: "body.face.top")
    static let bodyFaceBottom = SelectionComponentID(rawValue: "body.face.bottom")
    static let bodyFaceLeft = SelectionComponentID(rawValue: "body.face.left")
    static let bodyFaceRight = SelectionComponentID(rawValue: "body.face.right")
    static let bodyFaceSide = SelectionComponentID(rawValue: "body.face.side")

    static let bodyEdgeLeftBottom = SelectionComponentID(rawValue: "body.edge.leftBottom")
    static let bodyEdgeRightBottom = SelectionComponentID(rawValue: "body.edge.rightBottom")
    static let bodyEdgeRightTop = SelectionComponentID(rawValue: "body.edge.rightTop")
    static let bodyEdgeLeftTop = SelectionComponentID(rawValue: "body.edge.leftTop")
}

private extension SketchEntityPointHandle {
    func sketchReference(entityID: SketchEntityID) -> SketchReference {
        switch self {
        case .point:
            return .entity(entityID)
        case .lineStart:
            return .lineStart(entityID)
        case .lineEnd:
            return .lineEnd(entityID)
        case .circleCenter:
            return .circleCenter(entityID)
        case .arcCenter:
            return .arcCenter(entityID)
        case .arcStart:
            return .arcStart(entityID)
        case .arcEnd:
            return .arcEnd(entityID)
        }
    }
}

import Foundation
import SwiftCAD

extension DesignDocument {
    func circleProfileSegmentCounts(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> [FeatureID: Int] {
        var counts: [FeatureID: Int] = [:]

        for node in productMetadata.sceneNodes.values {
            guard let object = node.object,
                  object.category == .sketch,
                  object.typeID == .circle,
                  let featureID = object.sourceFeatureID ?? node.reference?.featureID,
                  let segmentCount = Self.sideSegmentCount(
                      from: object,
                      objectRegistry: objectRegistry
                  )?.value else {
                continue
            }
            counts[featureID] = segmentCount
        }

        for node in productMetadata.sceneNodes.values {
            guard let object = node.object,
                  object.category == .body,
                  object.typeID == .cylinder,
                  let sourceProfileFeatureID = object.sourceProfileFeatureID,
                  let segmentCount = Self.sideSegmentCount(
                      from: object,
                      objectRegistry: objectRegistry
                  ) else {
                continue
            }
            if segmentCount.value != segmentCount.defaultValue ||
                counts[sourceProfileFeatureID] == nil {
                counts[sourceProfileFeatureID] = segmentCount.value
            }
        }

        return counts
    }

    private static func sideSegmentCount(
        from object: ObjectDescriptor,
        objectRegistry: ObjectTypeRegistry
    ) -> (value: Int, defaultValue: Int)? {
        guard let definition = objectRegistry.definition(for: object.typeID),
              let property = definition.property(for: .sideSegments),
              case .integer(let defaultValue) = property.defaultValue else {
            return nil
        }
        let properties = definition.resolvedProperties(object.properties)
        let value = properties.value(for: property.id, default: property.defaultValue)
        guard case .integer(let segmentCount) = value else {
            return nil
        }
        return (
            value: max(segmentCount, 3),
            defaultValue: max(defaultValue, 3)
        )
    }
}

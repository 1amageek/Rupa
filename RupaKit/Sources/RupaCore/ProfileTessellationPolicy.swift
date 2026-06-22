import Foundation

enum ProfileTessellationPolicy {
    static let arcSegmentsPropertyID = ObjectPropertyID(rawValue: "profile.arc.segments")
    static let minimumArcSegmentCount = 3
    static let maximumArcSegmentCount = 64

    static func clampedArcSegmentCount(_ count: Int) -> Int {
        min(max(count, minimumArcSegmentCount), maximumArcSegmentCount)
    }

    static func arcSegmentCount(from object: ObjectDescriptor) -> Int? {
        guard case .integer(let count) = object.properties[arcSegmentsPropertyID] else {
            return nil
        }
        return clampedArcSegmentCount(count)
    }
}

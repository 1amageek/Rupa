import Foundation
import SwiftCAD

public struct ValidationMeshTriangleSelection: Codable, Equatable, Sendable {
    public var bodyID: BodyID
    public var triangleRanges: [ValidationElementRange]

    public init(
        bodyID: BodyID,
        triangleRanges: [ValidationElementRange]
    ) {
        self.bodyID = bodyID
        self.triangleRanges = triangleRanges
    }

    public func validate() throws {
        guard !triangleRanges.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation mesh selections must contain triangle ranges."
            )
        }

        var previousEndIndex: Int?
        for range in triangleRanges {
            try range.validate()
            guard let endIndex = range.endIndex else {
                throw ReferenceValidationError(
                    code: .invalidShape,
                    message: "Validation mesh triangle ranges must not overflow."
                )
            }
            if let previousEndIndex, range.startIndex < previousEndIndex {
                throw ReferenceValidationError(
                    code: .invalidShape,
                    message: "Validation mesh triangle ranges must be sorted and non-overlapping."
                )
            }
            previousEndIndex = endIndex
        }
    }
}

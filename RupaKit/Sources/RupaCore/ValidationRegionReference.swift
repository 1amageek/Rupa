import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ValidationRegionReference: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var documentID: DocumentID
    public var target: ValidationRegionTarget

    public init(
        id: String,
        documentID: DocumentID,
        target: ValidationRegionTarget
    ) {
        self.id = id
        self.documentID = documentID
        self.target = target
    }

    public var kind: ValidationRegionKind {
        switch target {
        case .body:
            .body
        case .bodyPair:
            .bodyPair
        case .generatedTopology:
            .generatedTopology
        case .meshTriangles:
            .meshTriangles
        case .semanticEntities:
            .semanticEntities
        case .sampledArtifact:
            .sampledArtifact
        case .drawingItems:
            .drawingItems
        }
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation region IDs must not be empty."
            )
        }

        switch target {
        case .body:
            break
        case .bodyPair(let first, let second):
            guard first != second else {
                throw invalidReference("Validation body-pair regions must reference two different bodies.")
            }
        case .generatedTopology(_, let persistentNames):
            try validateStrings(
                persistentNames,
                fieldName: "persistent topology names"
            )
        case .meshTriangles(let artifact, let selections):
            try artifact.validate()
            try requireMatchingDocument(artifact.documentID)
            guard !selections.isEmpty else {
                throw invalidReference("Validation mesh regions must contain triangle selections.")
            }
            for selection in selections {
                try selection.validate()
            }
            guard Set(selections.map(\.bodyID)).count == selections.count else {
                throw invalidReference("Validation mesh regions must reference each body at most once.")
            }
        case .semanticEntities(_, let entityIDs):
            guard !entityIDs.isEmpty,
                  Set(entityIDs).count == entityIDs.count else {
                throw invalidReference("Validation semantic regions must contain unique entity IDs.")
            }
            for entityID in entityIDs {
                try entityID.validate()
            }
        case .sampledArtifact(let artifact, let ranges):
            try requireMatchingDocument(artifact.documentID)
            try validateRanges(ranges)
        case .drawingItems(let artifact, let itemIDs):
            try requireMatchingDocument(artifact.documentID)
            guard artifact.kind == .drawing else {
                throw invalidReference("Validation drawing regions must reference a drawing artifact.")
            }
            try validateStrings(itemIDs, fieldName: "drawing item IDs")
        }
    }

    private func requireMatchingDocument(_ artifactDocumentID: DocumentID) throws {
        guard artifactDocumentID == documentID else {
            throw ReferenceValidationError(
                code: .documentMismatch,
                message: "Validation region and artifact document IDs must match."
            )
        }
    }

    private func validateStrings(
        _ values: [String],
        fieldName: String
    ) throws {
        guard !values.isEmpty,
              Set(values).count == values.count,
              values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw invalidReference(
                "Validation region \(fieldName) must be non-empty and unique."
            )
        }
    }

    private func validateRanges(_ ranges: [ValidationElementRange]) throws {
        guard !ranges.isEmpty else {
            throw invalidReference("Validation sampled regions must contain element ranges.")
        }
        var previousEndIndex: Int?
        for range in ranges {
            try range.validate()
            guard let endIndex = range.endIndex else {
                throw invalidReference("Validation element ranges must not overflow.")
            }
            if let previousEndIndex, range.startIndex < previousEndIndex {
                throw invalidReference(
                    "Validation element ranges must be sorted and non-overlapping."
                )
            }
            previousEndIndex = endIndex
        }
    }

    private func invalidReference(_ message: String) -> ReferenceValidationError {
        ReferenceValidationError(code: .invalidShape, message: message)
    }
}

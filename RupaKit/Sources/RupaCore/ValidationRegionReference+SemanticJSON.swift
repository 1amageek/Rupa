import SwiftCAD
import RupaCoreTypes

public extension ValidationRegionReference {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "id": .string(id),
            "documentID": .string(documentID.description),
            "kind": .string(kind.rawValue),
            "target": target.semanticJSONValue,
        ])
    }
}

private extension ValidationRegionTarget {
    var semanticJSONValue: SemanticJSONValue {
        switch self {
        case .body(let bodyID):
            .object(["bodyID": .string(bodyID.description)])
        case .bodyPair(let first, let second):
            .object([
                "firstBodyID": .string(first.description),
                "secondBodyID": .string(second.description),
            ])
        case .generatedTopology(let bodyID, let persistentNames):
            .object([
                "bodyID": bodyID.map { .string($0.description) } ?? .null,
                "persistentNames": .array(persistentNames.map(SemanticJSONValue.string)),
            ])
        case .meshTriangles(let artifact, let selections):
            .object([
                "artifact": artifact.semanticJSONValue,
                "selections": .array(selections.map(\.semanticJSONValue)),
            ])
        case .semanticEntities(let extensionID, let entityIDs):
            .object([
                "extensionID": .string(extensionID.rawValue.uuidString),
                "entityIDs": .array(entityIDs.map { .string($0.rawValue) }),
            ])
        case .sampledArtifact(let artifact, let ranges):
            .object([
                "artifact": artifact.semanticJSONValue,
                "ranges": .array(ranges.map(\.semanticJSONValue)),
            ])
        case .drawingItems(let artifact, let itemIDs):
            .object([
                "artifact": artifact.semanticJSONValue,
                "itemIDs": .array(itemIDs.map(SemanticJSONValue.string)),
            ])
        }
    }
}

private extension MeshArtifactReference {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "artifact": artifact.semanticJSONValue,
            "kernelVersion": .object([
                "major": .number(Double(kernelVersion.major)),
                "minor": .number(Double(kernelVersion.minor)),
                "patch": .number(Double(kernelVersion.patch)),
            ]),
            "modelingTolerance": .object([
                "distance": .number(modelingTolerance.distance),
                "angle": .number(modelingTolerance.angle),
            ]),
            "tessellation": .object([
                "linearTolerance": .number(tessellationOptions.linearTolerance),
                "angularTolerance": .number(tessellationOptions.angularTolerance),
                "maxEdgeLength": tessellationOptions.maxEdgeLength.map(SemanticJSONValue.number) ?? .null,
            ]),
        ])
    }
}

private extension MaterializedArtifactReference {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "documentID": .string(documentID.description),
            "kind": .string(kind.rawValue),
            "sourceDependencies": .array(
                computation.sourceDependencies.dependencies.map(\.semanticJSONValue)
            ),
            "producer": .object([
                "id": .string(computation.producer.id),
                "version": .string(computation.producer.version),
            ]),
            "configuration": computation.configuration.value,
            "computationFingerprint": computation.fingerprint.semanticJSONValue,
            "contentFingerprint": contentFingerprint.semanticJSONValue,
            "artifactFingerprint": fingerprint.semanticJSONValue,
        ])
    }
}

private extension SourceDependencyIdentity {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "subject": .string(subject.sortKey),
            "contentFingerprint": contentFingerprint.semanticJSONValue,
        ])
    }
}

private extension ContentFingerprint {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "algorithm": .string(algorithm),
            "value": .string(value),
        ])
    }
}

private extension ValidationMeshTriangleSelection {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "bodyID": .string(bodyID.description),
            "triangleRanges": .array(triangleRanges.map(\.semanticJSONValue)),
        ])
    }
}

private extension ValidationElementRange {
    var semanticJSONValue: SemanticJSONValue {
        .object([
            "startIndex": .number(Double(startIndex)),
            "count": .number(Double(count)),
        ])
    }
}

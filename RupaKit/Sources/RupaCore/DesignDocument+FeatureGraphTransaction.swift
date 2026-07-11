import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func appendFeatureGraph(
        _ transaction: FeatureGraphTransaction,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ValidatedDesignDocument {
        let validatedDocument = try validate(objectRegistry: objectRegistry)
        return try appendFeatureGraph(
            transaction,
            validatedDocument: validatedDocument,
            objectRegistry: objectRegistry
        )
    }

    package mutating func appendFeatureGraph(
        _ transaction: FeatureGraphTransaction,
        validatedDocument: ValidatedDesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ValidatedDesignDocument {
        guard validatedDocument.document.modelingSettings == modelingSettings,
              LiveDocumentEvaluationIdentity(
                document: validatedDocument.document.cadDocument
              ).matches(cadDocument) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Feature graph append requires validation for the current document source."
            )
        }
        try transaction.validate()
        try validateFeatureGraphIdentityAvailability(transaction)
        try validatePresentationContracts(transaction)

        let updatedCADDocument = try validatedDocument.validatedCADDocument
            .appendingFeatures(transaction.features)
        cadDocument = updatedCADDocument.document
        try appendPresentations(transaction.presentations, objectRegistry: objectRegistry)
        for presentation in transaction.presentations {
            guard case let .body(_, typeID, _, _) = presentation.kind,
                  typeID != nil,
                  case .extrude = cadDocument.designGraph.nodes[presentation.featureID]?.operation else {
                continue
            }
            try synchronizeObjectPropertiesFromSource(
                featureID: presentation.featureID,
                objectRegistry: objectRegistry
            )
        }
        try productMetadata.validate(
            against: cadDocument,
            objectRegistry: objectRegistry
        )
        return ValidatedDesignDocument(
            document: self,
            validatedCADDocument: updatedCADDocument
        )
    }

    private func validateFeatureGraphIdentityAvailability(
        _ transaction: FeatureGraphTransaction
    ) throws {
        for feature in transaction.features where cadDocument.designGraph.nodes[feature.id] != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Feature ID \(feature.id) already exists in the document."
            )
        }
        for presentation in transaction.presentations
        where productMetadata.sceneNodes[presentation.sceneNodeID] != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene node ID \(presentation.sceneNodeID) already exists in the document."
            )
        }
    }

    private func validatePresentationContracts(
        _ transaction: FeatureGraphTransaction
    ) throws {
        let features = Dictionary(uniqueKeysWithValues: transaction.features.map { ($0.id, $0) })
        for presentation in transaction.presentations {
            guard let feature = features[presentation.featureID] else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Feature presentation references a missing transaction feature."
                )
            }
            guard presentation.parentSceneNodeID != presentation.sceneNodeID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A feature presentation cannot parent itself."
                )
            }
            switch presentation.kind {
            case .feature:
                break
            case .sketch:
                guard case .sketch = feature.operation else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch presentation requires a sketch feature."
                    )
                }
            case .body:
                guard feature.outputs.contains(where: { $0.role == .body || $0.role == .sheet }) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Body presentation requires a body or sheet feature output."
                    )
                }
            }
        }
    }

    private mutating func appendPresentations(
        _ presentations: [FeaturePresentation],
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard !presentations.isEmpty else {
            return
        }
        guard let rootSceneNodeID = productMetadata.rootSceneNodeIDs.first else {
            throw DocumentValidationError.invalidProductMetadata(
                "A document must contain at least one root scene node."
            )
        }

        for presentation in presentations {
            let name = try normalizedMetadataName(presentation.name, owner: "Feature presentation")
            productMetadata.sceneNodes[presentation.sceneNodeID] = SceneNode(
                id: presentation.sceneNodeID,
                name: name,
                reference: presentation.kind.reference(featureID: presentation.featureID),
                object: presentation.kind.object(
                    featureID: presentation.featureID,
                    objectRegistry: objectRegistry
                ),
                isVisible: presentation.isVisible,
                isLocked: presentation.isLocked,
                localTransform: presentation.localTransform,
                materialID: presentation.materialID
            )
        }

        for presentation in presentations {
            let parentID = presentation.parentSceneNodeID ?? rootSceneNodeID
            guard productMetadata.sceneNodes[parentID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Feature presentation parent references a missing scene node."
                )
            }
            productMetadata.sceneNodes[parentID]?.childIDs.append(presentation.sceneNodeID)
        }
    }
}

private extension FeaturePresentationKind {
    func reference(featureID: FeatureID) -> SceneNodeReference {
        switch self {
        case .feature:
            return .feature(featureID)
        case .sketch:
            return .sketch(featureID)
        case .body:
            return .body(featureID)
        }
    }

    func object(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry
    ) -> ObjectDescriptor? {
        switch self {
        case .feature:
            return nil
        case let .sketch(typeID, geometryRole, properties):
            return .sketch(
                featureID: featureID,
                typeID: typeID,
                geometryRole: geometryRole,
                properties: properties,
                objectRegistry: objectRegistry
            )
        case let .body(sourceSection, typeID, geometryRole, properties):
            return .body(
                featureID: featureID,
                sourceSection: sourceSection,
                typeID: typeID,
                geometryRole: geometryRole,
                properties: properties,
                objectRegistry: objectRegistry
            )
        }
    }
}

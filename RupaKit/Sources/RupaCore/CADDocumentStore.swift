import Foundation
import Observation
import SwiftCAD
import RupaCoreTypes

@Observable
public final class CADDocumentStore {
    public private(set) var document: DesignDocument
    public private(set) var generation: DocumentGeneration
    public private(set) var isDirty: Bool
    public private(set) var diagnostics: [EditorDiagnostic]
    public private(set) var evaluationStatus: EvaluationStatus
    public private(set) var evaluatedGeneration: DocumentGeneration?
    public private(set) var renderInvalidation: RenderInvalidation
    public private(set) var evaluatedBodyCount: Int
    public private(set) var evaluationCache: EvaluatedDocumentCache?
    public let objectRegistry: ObjectTypeRegistry
    private let evaluationScheduler: EvaluationScheduler
    @ObservationIgnored private var validatedSource: ValidatedDesignDocument?
    private var evaluationDeferralDepth = 0
    private var hasDeferredEvaluation = false
    package private(set) var completedEvaluationPassCount: UInt64 = 0

    public init(
        document: DesignDocument = .empty(),
        generation: DocumentGeneration = DocumentGeneration(),
        isDirty: Bool = false,
        diagnostics: [EditorDiagnostic] = [],
        evaluationStatus: EvaluationStatus = .notEvaluated,
        evaluatedGeneration: DocumentGeneration? = nil,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        evaluatedBodyCount: Int = 0,
        evaluationCache: EvaluatedDocumentCache? = nil,
        completedEvaluationPassCount: UInt64 = 0,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        evaluationScheduler: EvaluationScheduler = EvaluationScheduler()
    ) {
        self.document = document
        self.generation = generation
        self.isDirty = isDirty
        self.diagnostics = diagnostics
        self.evaluationStatus = evaluationStatus
        self.evaluatedGeneration = evaluatedGeneration
        self.renderInvalidation = renderInvalidation
        self.evaluatedBodyCount = evaluatedBodyCount
        let currentEvaluationCache = Self.currentValidatedEvaluationCache(
            cache: evaluationCache,
            document: document,
            generation: generation,
            evaluationStatus: evaluationStatus,
            evaluatedGeneration: evaluatedGeneration
        )
        self.evaluationCache = currentEvaluationCache
        self.validatedSource = currentEvaluationCache?.validatedDocument
        self.completedEvaluationPassCount = completedEvaluationPassCount
        self.objectRegistry = objectRegistry
        self.evaluationScheduler = evaluationScheduler
    }

    public convenience init(
        transactionSnapshot: CADDocumentStoreTransactionSnapshot,
        objectRegistry: ObjectTypeRegistry
    ) {
        let snapshot = transactionSnapshot.document
        self.init(
            document: snapshot.document,
            generation: snapshot.generation,
            isDirty: snapshot.isDirty,
            diagnostics: snapshot.diagnostics,
            evaluationStatus: snapshot.evaluationStatus,
            evaluatedGeneration: snapshot.evaluatedGeneration,
            renderInvalidation: snapshot.renderInvalidation,
            evaluatedBodyCount: snapshot.evaluatedBodyCount,
            evaluationCache: nil,
            completedEvaluationPassCount: transactionSnapshot.completedEvaluationPassCount,
            objectRegistry: objectRegistry
        )
        evaluationCache = Self.currentTrustedEvaluationCache(
            cache: transactionSnapshot.evaluationCache,
            document: snapshot.document,
            generation: snapshot.generation,
            evaluationStatus: snapshot.evaluationStatus,
            evaluatedGeneration: snapshot.evaluatedGeneration
        )
        validatedSource = evaluationCache?.validatedDocument
    }

    public var currentEvaluationCache: EvaluatedDocumentCache? {
        guard evaluatedGeneration == generation else {
            return nil
        }
        guard case .valid = evaluationStatus else {
            return nil
        }
        guard evaluationCache?.generation == generation else {
            return nil
        }
        return evaluationCache
    }

    public var currentEvaluation: DocumentEvaluationContext? {
        currentEvaluationCache.map(DocumentEvaluationContext.init(cache:))
    }

    public var currentModelingEvaluationMetrics: ModelingEvaluationMetrics? {
        currentEvaluationCache.map {
            ModelingEvaluationMetrics($0.evaluatedDocument.evaluationMetrics)
        }
    }

    public var evaluationSnapshot: EvaluationSnapshot {
        EvaluationSnapshot(
            status: evaluationStatus,
            evaluatedGeneration: evaluatedGeneration,
            renderInvalidation: renderInvalidation,
            bodyCount: evaluatedBodyCount,
            diagnostics: diagnostics
        )
    }

    public func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            document: document,
            generation: generation,
            isDirty: isDirty,
            diagnostics: diagnostics,
            evaluationStatus: evaluationStatus,
            evaluatedGeneration: evaluatedGeneration,
            renderInvalidation: renderInvalidation,
            evaluatedBodyCount: evaluatedBodyCount
        )
    }

    public func restore(_ snapshot: DocumentSnapshot) {
        let cache = currentEvaluationCache
        document = snapshot.document
        generation = snapshot.generation
        isDirty = snapshot.isDirty
        diagnostics = snapshot.diagnostics
        evaluationStatus = snapshot.evaluationStatus
        evaluatedGeneration = snapshot.evaluatedGeneration
        renderInvalidation = snapshot.renderInvalidation
        evaluatedBodyCount = snapshot.evaluatedBodyCount
        evaluationCache = Self.currentValidatedEvaluationCache(
            cache: cache,
            document: snapshot.document,
            generation: snapshot.generation,
            evaluationStatus: snapshot.evaluationStatus,
            evaluatedGeneration: snapshot.evaluatedGeneration
        )
        validatedSource = evaluationCache?.validatedDocument
    }

    public func transactionSnapshot() -> CADDocumentStoreTransactionSnapshot {
        CADDocumentStoreTransactionSnapshot(
            document: snapshot(),
            evaluationCache: currentEvaluationCache,
            completedEvaluationPassCount: completedEvaluationPassCount
        )
    }

    public func restoreTransactionSnapshot(_ snapshot: CADDocumentStoreTransactionSnapshot) {
        let documentSnapshot = snapshot.document
        document = documentSnapshot.document
        generation = documentSnapshot.generation
        isDirty = documentSnapshot.isDirty
        diagnostics = documentSnapshot.diagnostics
        evaluationStatus = documentSnapshot.evaluationStatus
        evaluatedGeneration = documentSnapshot.evaluatedGeneration
        renderInvalidation = documentSnapshot.renderInvalidation
        evaluatedBodyCount = documentSnapshot.evaluatedBodyCount
        evaluationCache = Self.currentTrustedEvaluationCache(
            cache: snapshot.evaluationCache,
            document: documentSnapshot.document,
            generation: documentSnapshot.generation,
            evaluationStatus: documentSnapshot.evaluationStatus,
            evaluatedGeneration: documentSnapshot.evaluatedGeneration
        )
        validatedSource = evaluationCache?.validatedDocument
    }

    public func restoreAsMutation(_ snapshot: DocumentSnapshot) throws {
        let nextGeneration = try generation.advanced()
        document = snapshot.document
        generation = nextGeneration
        isDirty = snapshot.isDirty
        diagnostics = snapshot.diagnostics
        evaluationStatus = snapshot.evaluationStatus
        evaluatedGeneration = snapshot.evaluatedGeneration
        renderInvalidation = snapshot.renderInvalidation
        evaluatedBodyCount = snapshot.evaluatedBodyCount
        evaluationCache = nil
        validatedSource = nil
    }

    public func requireGeneration(_ expectedGeneration: DocumentGeneration?) throws {
        guard let expectedGeneration else {
            return
        }
        guard expectedGeneration == generation else {
            throw EditorError(
                code: .documentGenerationMismatch,
                message: "Expected generation \(expectedGeneration.value), but current generation is \(generation.value)."
            )
        }
    }

    public func apply(_ command: EditorCommand) throws -> CommandExecutionResult {
        let transactionSnapshot = transactionSnapshot()
        let ownsEvaluationBoundary = evaluationDeferralDepth == 0
        do {
            let result = try withDeferredEvaluation {
                try applyCommand(command)
            }
            if ownsEvaluationBoundary, result.didMutate {
                try requireValidCommittedEvaluation()
            }
            return result
        } catch {
            restoreTransactionSnapshot(transactionSnapshot)
            throw error
        }
    }

    // Each case body below runs inside a nested run() so the per-case
    // temporaries do not accumulate into this function's frame; unoptimized
    // builds must stay within 512 KB worker stacks on deep command chains.
    private func applyCommand(_ command: EditorCommand) throws -> CommandExecutionResult {
        var curveRebuildReport: CurveRebuildReport?
        var addedSelectionDimensionID: SelectionDimensionID?
        var createdConstructionPlaneID: ConstructionPlaneSourceID?
        var primaryFeatureID: FeatureID?
        var didMutate = command.mutatesDocument
        let previousFeatureCount = document.cadDocument.designGraph.order.count
        switch command {
        case .createSavedView:
            func run() throws {
                guard case .createSavedView(let savedView) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSavedView."
                    )
                }
                try document.createSavedView(
                    savedView,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .updateSavedView:
            func run() throws {
                guard case .updateSavedView(let savedView) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected updateSavedView."
                    )
                }
                try document.updateSavedView(
                    savedView,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .removeSavedView:
            func run() throws {
                guard case .removeSavedView(let id) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected removeSavedView."
                    )
                }
                try document.removeSavedView(
                    id: id,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .rebaseWorkspaceOrigin:
            func run() throws {
                guard case .rebaseWorkspaceOrigin(let translation) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected rebaseWorkspaceOrigin."
                    )
                }
                try document.rebaseWorkspaceOrigin(
                    translation: translation,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .renameDocument:
            func run() throws {
                guard case .renameDocument(let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected renameDocument."
                    )
                }
                document.rename(name)
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .resetDocument:
            func run() throws {
                guard case .resetDocument(let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected resetDocument."
                    )
                }
                document = .empty(named: name)
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .replaceProductMetadata:
            func run() throws {
                guard case .replaceProductMetadata(let metadata) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected replaceProductMetadata."
                    )
                }
                document.productMetadata = metadata
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .applySemanticExtensionMutations:
            func run() throws {
                guard case .applySemanticExtensionMutations(let mutations) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected applySemanticExtensionMutations."
                    )
                }
                try document.applySemanticExtensionMutations(
                    mutations,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .upsertParameter:
            func run() throws {
                guard case .upsertParameter(let name, let expression, let kind) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected upsertParameter."
                    )
                }
                try document.upsertParameter(
                    name: name,
                    expression: expression,
                    kind: kind,
                    objectRegistry: objectRegistry
                )
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .renameParameter:
            func run() throws {
                guard case .renameParameter(let currentName, let newName) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected renameParameter."
                    )
                }
                var updatedDocument = document
                try updatedDocument.renameParameter(
                    currentName: currentName,
                    newName: newName,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .deleteParameter:
            func run() throws {
                guard case .deleteParameter(let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected deleteParameter."
                    )
                }
                var updatedDocument = document
                try updatedDocument.deleteParameter(name: name, objectRegistry: objectRegistry)
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setFeatureSuppression:
            func run() throws {
                guard case .setFeatureSuppression(let featureID, let isSuppressed) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setFeatureSuppression."
                    )
                }
                var updatedDocument = document
                let changed = try updatedDocument.setFeatureSuppression(
                    featureID: featureID,
                    isSuppressed: isSuppressed,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                primaryFeatureID = featureID
                didMutate = changed
                if changed {
                    try commitMutation()
                    evaluateCurrentDocument()
                }
            }
            try run()
        case .appendFeatureGraph:
            func run() throws {
                guard case .appendFeatureGraph(let transaction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected appendFeatureGraph."
                    )
                }
                var updatedDocument = document
                let sourceValidation = try validatedSource
                    ?? document.validate(objectRegistry: objectRegistry)
                let updatedValidation = try updatedDocument.appendFeatureGraph(
                    transaction,
                    validatedDocument: sourceValidation,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                primaryFeatureID = transaction.primaryFeatureID ?? transaction.features.last?.id
                try commitMutation()
                validatedSource = updatedValidation
                evaluateCurrentDocument()
            }
            try run()
        case .createComponentDefinition:
            func run() throws {
                guard case .createComponentDefinition(let name, let rootSceneNodeIDs) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createComponentDefinition."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createComponentDefinition(
                    name: name,
                    rootSceneNodeIDs: rootSceneNodeIDs,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createComponentInstance:
            func run() throws {
                guard case .createComponentInstance(let name, let definitionID, let localTransform) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createComponentInstance."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createComponentInstance(
                    name: name,
                    definitionID: definitionID,
                    localTransform: localTransform,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createPatternArray:
            func run() throws {
                guard case .createPatternArray(let name, let definitionID, let distribution, let outputMode) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createPatternArray."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createPatternArray(
                    name: name,
                    definitionID: definitionID,
                    distribution: distribution,
                    outputMode: outputMode,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .updatePatternArray:
            func run() throws {
                guard case .updatePatternArray(let id, let name, let definitionID, let distribution, let outputMode) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected updatePatternArray."
                    )
                }
                var updatedDocument = document
                try updatedDocument.updatePatternArray(
                    id: id,
                    name: name,
                    definitionID: definitionID,
                    distribution: distribution,
                    outputMode: outputMode,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .explodePatternArray:
            func run() throws {
                guard case .explodePatternArray(let id) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected explodePatternArray."
                    )
                }
                var updatedDocument = document
                try updatedDocument.explodePatternArray(
                    id: id,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSceneNodeVisibility:
            func run() throws {
                guard case .setSceneNodeVisibility(let id, let isVisible) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSceneNodeVisibility."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSceneNodeVisibility(id: id, isVisible: isVisible, objectRegistry: objectRegistry)
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSceneNodeLock:
            func run() throws {
                guard case .setSceneNodeLock(let id, let isLocked) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSceneNodeLock."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSceneNodeLock(id: id, isLocked: isLocked, objectRegistry: objectRegistry)
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSceneNodeTransform:
            func run() throws {
                guard case .setSceneNodeTransform(let id, let localTransform) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSceneNodeTransform."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSceneNodeTransform(
                    id: id,
                    localTransform: localTransform,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSceneNodeMaterial:
            func run() throws {
                guard case .setSceneNodeMaterial(let id, let materialID) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSceneNodeMaterial."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSceneNodeMaterial(id: id, materialID: materialID, objectRegistry: objectRegistry)
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setTopologyMaterialBinding:
            func run() throws {
                guard case .setTopologyMaterialBinding(let target, let materialID, let process) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setTopologyMaterialBinding."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setTopologyMaterialBinding(
                    target: target,
                    materialID: materialID,
                    process: process,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSceneNodeObjectProperty:
            func run() throws {
                guard case .setSceneNodeObjectProperty(let id, let propertyID, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSceneNodeObjectProperty."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSceneNodeObjectProperty(
                    id: id,
                    propertyID: propertyID,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setComponentInstanceVisibility:
            func run() throws {
                guard case .setComponentInstanceVisibility(let id, let isVisible) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setComponentInstanceVisibility."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setComponentInstanceVisibility(
                    id: id,
                    isVisible: isVisible,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setComponentInstanceLock:
            func run() throws {
                guard case .setComponentInstanceLock(let id, let isLocked) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setComponentInstanceLock."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setComponentInstanceLock(
                    id: id,
                    isLocked: isLocked,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setComponentInstanceTransform:
            func run() throws {
                guard case .setComponentInstanceTransform(let id, let localTransform) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setComponentInstanceTransform."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setComponentInstanceTransform(
                    id: id,
                    localTransform: localTransform,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createSectionPlane:
            func run() throws {
                guard case .createSectionPlane(let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSectionPlane."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createSectionPlane(name: name, objectRegistry: objectRegistry)
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createConstructionPlane:
            func run() throws {
                guard case .createConstructionPlane(let name, let plane) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createConstructionPlane."
                    )
                }
                var updatedDocument = document
                createdConstructionPlaneID = try updatedDocument.createConstructionPlane(
                    name: name,
                    plane: plane,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createConstructionPlaneFromTarget:
            func run() throws {
                guard case .createConstructionPlaneFromTarget(let name, let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createConstructionPlaneFromTarget."
                    )
                }
                var updatedDocument = document
                createdConstructionPlaneID = try updatedDocument.createConstructionPlaneFromTarget(
                    name: name,
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createConstructionPlaneFromTargets:
            func run() throws {
                guard case .createConstructionPlaneFromTargets(let name, let targets, let viewNormal) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createConstructionPlaneFromTargets."
                    )
                }
                var updatedDocument = document
                createdConstructionPlaneID = try updatedDocument.createConstructionPlaneFromTargets(
                    name: name,
                    targets: targets,
                    viewNormal: viewNormal,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createViewAlignedConstructionPlane:
            func run() throws {
                guard case .createViewAlignedConstructionPlane(let name, let origin, let viewNormal) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createViewAlignedConstructionPlane."
                    )
                }
                var updatedDocument = document
                createdConstructionPlaneID = try updatedDocument.createViewAlignedConstructionPlane(
                    name: name,
                    origin: origin,
                    viewNormal: viewNormal,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .renameConstructionPlane:
            func run() throws {
                guard case .renameConstructionPlane(let id, let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected renameConstructionPlane."
                    )
                }
                var updatedDocument = document
                try updatedDocument.renameConstructionPlane(
                    id: id,
                    name: name,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setConstructionPlane:
            func run() throws {
                guard case .setConstructionPlane(let id, let plane) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setConstructionPlane."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setConstructionPlane(
                    id: id,
                    plane: plane,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createSketch:
            func run() throws {
                guard case .createSketch(let name, let sketch, let geometryRole) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createSketch(
                    name: name,
                    sketch: sketch,
                    geometryRole: geometryRole,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createLineSketch:
            func run() throws {
                guard case .createLineSketch(let name, let plane, let start, let end) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createLineSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createLineSketch(
                    name: name,
                    plane: plane,
                    start: start,
                    end: end,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createCircleSketch:
            func run() throws {
                guard case .createCircleSketch(let name, let plane, let center, let radius) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createCircleSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createCircleSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createArcSketch:
            func run() throws {
                guard case .createArcSketch(let name, let plane, let center, let radius, let startAngle, let endAngle) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createArcSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createArcSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createSplineSketch:
            func run() throws {
                guard case .createSplineSketch(let name, let plane, let spline) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSplineSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createSplineSketch(
                    name: name,
                    plane: plane,
                    spline: spline,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createRectangleSketch:
            func run() throws {
                guard case .createRectangleSketch(let name, let plane, let width, let height) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createRectangleSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createRectangleSketch(
                    name: name,
                    plane: plane,
                    width: width,
                    height: height,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createPolygonSketch:
            func run() throws {
                guard case .createPolygonSketch( let name, let plane, let center, let radius, let sides, let sizingMode, let inclinationMode, let rotationAngle ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createPolygonSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createPolygonSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    sides: sides,
                    sizingMode: sizingMode,
                    inclinationMode: inclinationMode,
                    rotationAngle: rotationAngle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createFaceKnife:
            func run() throws {
                guard case .createFaceKnife(let name, let target, let loop) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createFaceKnife."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createFaceKnife(
                    name: name,
                    target: target,
                    loop: loop,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .projectSketchCurvesToConstructionPlane:
            func run() throws {
                guard case .projectSketchCurvesToConstructionPlane(let targets, let plane, let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected projectSketchCurvesToConstructionPlane."
                    )
                }
                var updatedDocument = document
                try updatedDocument.projectSketchCurvesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .projectCurvesToGeneratedFace:
            func run() throws {
                guard case .projectCurvesToGeneratedFace(let targets, let face, let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected projectCurvesToGeneratedFace."
                    )
                }
                var updatedDocument = document
                try updatedDocument.projectCurvesToGeneratedFace(
                    targets: targets,
                    face: face,
                    name: name,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .projectBodyOutlinesToConstructionPlane:
            func run() throws {
                guard case .projectBodyOutlinesToConstructionPlane(let targets, let plane, let name) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected projectBodyOutlinesToConstructionPlane."
                    )
                }
                var updatedDocument = document
                try updatedDocument.projectBodyOutlinesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .addSketchConstraint:
            func run() throws {
                guard case .addSketchConstraint(let featureID, let constraint) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected addSketchConstraint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.addSketchConstraint(
                    featureID: featureID,
                    constraint: constraint,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .removeSketchConstraint:
            func run() throws {
                guard case .removeSketchConstraint(let featureID, let constraint) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected removeSketchConstraint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.removeSketchConstraint(
                    featureID: featureID,
                    constraint: constraint,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createBridgeCurve:
            func run() throws {
                guard case .createBridgeCurve(let featureID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createBridgeCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createBridgeCurve(
                    featureID: featureID,
                    firstEndpoint: firstEndpoint,
                    secondEndpoint: secondEndpoint,
                    continuity: continuity,
                    trimsSourceCurves: trimsSourceCurves,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setBridgeCurveParameters:
            func run() throws {
                guard case .setBridgeCurveParameters(let sourceID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setBridgeCurveParameters."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setBridgeCurveParameters(
                    sourceID: sourceID,
                    firstEndpoint: firstEndpoint,
                    secondEndpoint: secondEndpoint,
                    continuity: continuity,
                    trimsSourceCurves: trimsSourceCurves,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createRectangleSketchFromCorners:
            func run() throws {
                guard case .createRectangleSketchFromCorners(let name, let plane, let firstCorner, let oppositeCorner) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createRectangleSketchFromCorners."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createRectangleSketchFromCorners(
                    name: name,
                    plane: plane,
                    firstCorner: firstCorner,
                    oppositeCorner: oppositeCorner,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setExtrudeDistance:
            func run() throws {
                guard case .setExtrudeDistance(let featureID, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setExtrudeDistance."
                    )
                }
                var updatedDocument = document
                let sourceValidation = try validatedSource
                    ?? document.validate(objectRegistry: objectRegistry)
                let updatedValidation = try updatedDocument.setExtrudeDistance(
                    featureID: featureID,
                    distance: distance,
                    validatedDocument: sourceValidation
                )
                document = updatedDocument
                try commitMutation()
                validatedSource = updatedValidation
                evaluateCurrentDocument()
            }
            try run()
        case .setCubeDimensions:
            func run() throws {
                guard case .setCubeDimensions(let featureID, let sizeX, let sizeY, let sizeZ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setCubeDimensions."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setCubeDimensions(
                    featureID: featureID,
                    sizeX: sizeX,
                    sizeY: sizeY,
                    sizeZ: sizeZ,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setCylinderDimensions:
            func run() throws {
                guard case .setCylinderDimensions(let featureID, let radius, let sizeY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setCylinderDimensions."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setCylinderDimensions(
                    featureID: featureID,
                    radius: radius,
                    sizeY: sizeY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setObjectDimension:
            func run() throws {
                guard case .setObjectDimension(let target, let kind, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setObjectDimension."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setObjectDimension(
                    target: target,
                    kind: kind,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .addSelectionDimension:
            func run() throws {
                guard case .addSelectionDimension(let name, let kind, let first, let second, let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected addSelectionDimension."
                    )
                }
                var updatedDocument = document
                addedSelectionDimensionID = try updatedDocument.addSelectionDimension(
                    name: name,
                    kind: kind,
                    first: first,
                    second: second,
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSelectionDimensionTarget:
            func run() throws {
                guard case .setSelectionDimensionTarget(let id, let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSelectionDimensionTarget."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSelectionDimensionTarget(
                    id: id,
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .applySelectionDimensionTarget:
            func run() throws {
                guard case .applySelectionDimensionTarget(let id) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected applySelectionDimensionTarget."
                    )
                }
                var updatedDocument = document
                try updatedDocument.applySelectionDimensionTarget(
                    id: id,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .removeSelectionDimension:
            func run() throws {
                guard case .removeSelectionDimension(let id) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected removeSelectionDimension."
                    )
                }
                var updatedDocument = document
                try updatedDocument.removeSelectionDimension(
                    id: id,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .offsetCurve:
            func run() throws {
                guard case .offsetCurve(let target, let distance, let options, let vertexHandle) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected offsetCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.offsetCurve(
                    target: target,
                    distance: distance,
                    options: options,
                    vertexHandle: vertexHandle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .offsetRegions:
            func run() throws {
                guard case .offsetRegions(let targets, let distance, let options, let combinesRegions) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected offsetRegions."
                    )
                }
                var updatedDocument = document
                try updatedDocument.offsetRegions(
                    targets: targets,
                    distance: distance,
                    options: options,
                    combinesRegions: combinesRegions,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .offsetSketchVertex:
            func run() throws {
                guard case .offsetSketchVertex(let target, let handle, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected offsetSketchVertex."
                    )
                }
                var updatedDocument = document
                try updatedDocument.offsetSketchVertex(
                    target: target,
                    handle: handle,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .applySketchCornerTreatment:
            func run() throws {
                guard case .applySketchCornerTreatment(let target, let adjacentTarget, let distance, let treatment) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected applySketchCornerTreatment."
                    )
                }
                var updatedDocument = document
                try updatedDocument.applySketchCornerTreatment(
                    target: target,
                    adjacentTarget: adjacentTarget,
                    distance: distance,
                    treatment: treatment,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createSlotSketch:
            func run() throws {
                guard case .createSlotSketch(let target, let width) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSlotSketch."
                    )
                }
                var updatedDocument = document
                try updatedDocument.createSlotSketch(
                    target: target,
                    width: width,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .offsetBodyFace:
            func run() throws {
                guard case .offsetBodyFace(let target, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected offsetBodyFace."
                    )
                }
                var updatedDocument = document
                try updatedDocument.offsetBodyFace(
                    target: target,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .deleteBodyFaces:
            func run() throws {
                guard case .deleteBodyFaces(let targets) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected deleteBodyFaces."
                    )
                }
                var updatedDocument = document
                try updatedDocument.deleteBodyFaces(
                    targets: targets,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .draftBodyFaces:
            func run() throws {
                guard case .draftBodyFaces(let targets, let neutralTarget, let angle) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected draftBodyFaces."
                    )
                }
                var updatedDocument = document
                try updatedDocument.draftBodyFaces(
                    targets: targets,
                    neutralTarget: neutralTarget,
                    angle: angle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .chamferBodyEdges:
            func run() throws {
                guard case .chamferBodyEdges(let targets, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected chamferBodyEdges."
                    )
                }
                var updatedDocument = document
                try updatedDocument.chamferBodyEdges(
                    targets: targets,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .filletBodyEdges:
            func run() throws {
                guard case .filletBodyEdges(let targets, let radius, let segmentCount) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected filletBodyEdges."
                    )
                }
                var updatedDocument = document
                try updatedDocument.filletBodyEdges(
                    targets: targets,
                    radius: radius,
                    segmentCount: segmentCount,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveBody:
            func run() throws {
                guard case .moveBody(let target, let deltaX, let deltaY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveBody."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveBody(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveBodyEdge:
            func run() throws {
                guard case .moveBodyEdge(let target, let deltaX, let deltaY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveBodyEdge."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveBodyEdge(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveBodyVertex:
            func run() throws {
                guard case .moveBodyVertex(let target, let deltaX, let deltaY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveBodyVertex."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveBodyVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSketchEntityPoint:
            func run() throws {
                guard case .moveSketchEntityPoint(let target, let handle, let deltaX, let deltaY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSketchEntityPoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSketchEntityPoint(
                    target: target,
                    handle: handle,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSketchSplineControlPoint:
            func run() throws {
                guard case .moveSketchSplineControlPoint(let target, let controlPointIndex, let deltaX, let deltaY) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSketchSplineControlPoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSketchSplineControlPoint(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .alignSketchVertex:
            func run() throws {
                guard case .alignSketchVertex(let target, let reference, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected alignSketchVertex."
                    )
                }
                var updatedDocument = document
                try updatedDocument.alignSketchVertex(
                    target: target,
                    reference: reference,
                    options: options,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .slideSketchSplineControlPoints:
            func run() throws {
                guard case .slideSketchSplineControlPoints(let target, let controlPointIndexes, let direction, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected slideSketchSplineControlPoints."
                    )
                }
                var updatedDocument = document
                try updatedDocument.slideSketchSplineControlPoints(
                    target: target,
                    controlPointIndexes: controlPointIndexes,
                    direction: direction,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .insertSketchSplineControlPoint:
            func run() throws {
                guard case .insertSketchSplineControlPoint(let target, let fraction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected insertSketchSplineControlPoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.insertSketchSplineControlPoint(
                    target: target,
                    fraction: fraction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSketchCircleParameters:
            func run() throws {
                guard case .setSketchCircleParameters(let target, let center, let radius) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSketchCircleParameters."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSketchCircleParameters(
                    target: target,
                    center: center,
                    radius: radius,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSketchArcParameters:
            func run() throws {
                guard case .setSketchArcParameters(let target, let center, let radius, let startAngle, let endAngle) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSketchArcParameters."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSketchArcParameters(
                    target: target,
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSketchEntityDimension:
            func run() throws {
                guard case .setSketchEntityDimension(let target, let kind, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSketchEntityDimension."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSketchEntityDimension(
                    target: target,
                    kind: kind,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .convertSketchLineToArc:
            func run() throws {
                guard case .convertSketchLineToArc(let target, let sagitta) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected convertSketchLineToArc."
                    )
                }
                var updatedDocument = document
                try updatedDocument.convertSketchLineToArc(
                    target: target,
                    sagitta: sagitta,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .convertSketchLineToSpline:
            func run() throws {
                guard case .convertSketchLineToSpline(let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected convertSketchLineToSpline."
                    )
                }
                var updatedDocument = document
                try updatedDocument.convertSketchLineToSpline(
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .reverseSketchCurve:
            func run() throws {
                guard case .reverseSketchCurve(let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected reverseSketchCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.reverseSketchCurve(
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .rebuildSketchCurve:
            func run() throws {
                guard case .rebuildSketchCurve(let target, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected rebuildSketchCurve."
                    )
                }
                var updatedDocument = document
                let report = try updatedDocument.rebuildSketchCurve(
                    target: target,
                    options: options,
                    objectRegistry: objectRegistry
                )
                curveRebuildReport = report
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .extendSketchCurve:
            func run() throws {
                guard case .extendSketchCurve(let target, let distance, let shape) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected extendSketchCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.extendSketchCurve(
                    target: target,
                    distance: distance,
                    shape: shape,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .joinSketchCurves:
            func run() throws {
                guard case .joinSketchCurves(let target, let adjacentTarget, let continuity) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected joinSketchCurves."
                    )
                }
                var updatedDocument = document
                try updatedDocument.joinSketchCurves(
                    target: target,
                    adjacentTarget: adjacentTarget,
                    continuity: continuity,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .unjoinSketchCurve:
            func run() throws {
                guard case .unjoinSketchCurve(let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected unjoinSketchCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.unjoinSketchCurve(
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .splitSketchCurve:
            func run() throws {
                guard case .splitSketchCurve(let target, let fraction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected splitSketchCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.splitSketchCurve(
                    target: target,
                    fraction: fraction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .trimSketchCurveSegment:
            func run() throws {
                guard case .trimSketchCurveSegment(let target) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected trimSketchCurveSegment."
                    )
                }
                var updatedDocument = document
                try updatedDocument.trimSketchCurveSegment(
                    target: target,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .cutSketchCurve:
            func run() throws {
                guard case .cutSketchCurve(let target, let cutter, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected cutSketchCurve."
                    )
                }
                var updatedDocument = document
                try updatedDocument.cutSketchCurve(
                    target: target,
                    cutter: cutter,
                    options: options,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .extrudeProfile:
            func run() throws {
                guard case .extrudeProfile(let name, let profile, let distance, let direction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected extrudeProfile."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.extrudeProfile(
                    name: name,
                    profile: profile,
                    distance: distance,
                    direction: direction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createRevolve:
            func run() throws {
                guard case .createRevolve(let name, let profile, let axis, let angle) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createRevolve."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createRevolve(
                    name: name,
                    profile: profile,
                    axis: axis,
                    angle: angle,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createSweep:
            func run() throws {
                guard case .createSweep(let name, let sections, let path, let guides, let targets, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createSweep."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createSweep(
                    name: name,
                    sections: sections,
                    path: path,
                    guides: guides,
                    targets: targets,
                    options: options,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createLoft:
            func run() throws {
                guard case .createLoft(let name, let sections, let guides, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createLoft."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createLoft(
                    name: name,
                    sections: sections,
                    guides: guides,
                    options: options,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createBoolean:
            func run() throws {
                guard case .createBoolean(let name, let targets, let tool, let operation, let keepTools) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createBoolean."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createBoolean(
                    name: name,
                    targets: targets,
                    tool: tool,
                    operation: operation,
                    keepTools: keepTools,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createBSplineSurface:
            func run() throws {
                guard case .createBSplineSurface(let name, let surface) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createBSplineSurface."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createBSplineSurface(
                    name: name,
                    surface: surface,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createPolySplineSurface:
            func run() throws {
                guard case .createPolySplineSurface(let name, let sourceMesh, let options) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createPolySplineSurface."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createPolySplineSurface(
                    name: name,
                    sourceMesh: sourceMesh,
                    options: options,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .movePolySplineSurfaceVertex:
            func run() throws {
                guard case .movePolySplineSurfaceVertex(let target, let deltaX, let deltaY, let deltaZ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected movePolySplineSurfaceVertex."
                    )
                }
                var updatedDocument = document
                try updatedDocument.movePolySplineSurfaceVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaZ: deltaZ,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSurfaceControlPoint:
            func run() throws {
                guard case .moveSurfaceControlPoint(let target, let deltaX, let deltaY, let deltaZ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSurfaceControlPoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSurfaceControlPoint(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaZ: deltaZ,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSurfaceControlPointsInFrame:
            func run() throws {
                guard case .moveSurfaceControlPointsInFrame( let targets, let frame, let uDistance, let vDistance, let normalDistance ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSurfaceControlPointsInFrame."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSurfaceControlPointsInFrame(
                    targets: targets,
                    frame: frame,
                    uDistance: uDistance,
                    vDistance: vDistance,
                    normalDistance: normalDistance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceControlPointWeight:
            func run() throws {
                guard case .setSurfaceControlPointWeight(let target, let weight) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceControlPointWeight."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceControlPointWeight(
                    target: target,
                    weight: weight,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceKnotValue:
            func run() throws {
                guard case .setSurfaceKnotValue(let target, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceKnotValue."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceKnotValue(
                    target: target,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .insertSurfaceKnot:
            func run() throws {
                guard case .insertSurfaceKnot(let target, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected insertSurfaceKnot."
                    )
                }
                var updatedDocument = document
                try updatedDocument.insertSurfaceKnot(
                    target: target,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .splitSurfaceSpan:
            func run() throws {
                guard case .splitSurfaceSpan(let target, let fraction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected splitSurfaceSpan."
                    )
                }
                var updatedDocument = document
                try updatedDocument.splitSurfaceSpan(
                    target: target,
                    fraction: fraction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceKnotMultiplicity:
            func run() throws {
                guard case .setSurfaceKnotMultiplicity(let target, let multiplicity) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceKnotMultiplicity."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceKnotMultiplicity(
                    target: target,
                    multiplicity: multiplicity,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceTrimDomain:
            func run() throws {
                guard case .setSurfaceTrimDomain( let target, let uLowerBound, let uUpperBound, let vLowerBound, let vUpperBound ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceTrimDomain."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceTrimDomain(
                    target: target,
                    uLowerBound: uLowerBound,
                    uUpperBound: uUpperBound,
                    vLowerBound: vLowerBound,
                    vUpperBound: vUpperBound,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceTrimLoops:
            func run() throws {
                guard case .setSurfaceTrimLoops(let target, let trimLoops) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceTrimLoops."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceTrimLoops(
                    target: target,
                    trimLoops: trimLoops,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSurfaceTrimEndpoint:
            func run() throws {
                guard case .moveSurfaceTrimEndpoint(let target, let endpoint, let u, let v) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSurfaceTrimEndpoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSurfaceTrimEndpoint(
                    target: target,
                    endpoint: endpoint,
                    u: u,
                    v: v,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .moveSurfaceTrimControlPoint:
            func run() throws {
                guard case .moveSurfaceTrimControlPoint(let target, let controlPointIndex, let u, let v) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected moveSurfaceTrimControlPoint."
                    )
                }
                var updatedDocument = document
                try updatedDocument.moveSurfaceTrimControlPoint(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    u: u,
                    v: v,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceTrimControlPointWeight:
            func run() throws {
                guard case .setSurfaceTrimControlPointWeight(let target, let controlPointIndex, let weight) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceTrimControlPointWeight."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceTrimControlPointWeight(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    weight: weight,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .insertSurfaceTrimKnot:
            func run() throws {
                guard case .insertSurfaceTrimKnot(let target, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected insertSurfaceTrimKnot."
                    )
                }
                var updatedDocument = document
                try updatedDocument.insertSurfaceTrimKnot(
                    target: target,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceTrimKnotValue:
            func run() throws {
                guard case .setSurfaceTrimKnotValue(let target, let knotIndex, let value) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceTrimKnotValue."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceTrimKnotValue(
                    target: target,
                    knotIndex: knotIndex,
                    value: value,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .setSurfaceTrimKnotMultiplicity:
            func run() throws {
                guard case .setSurfaceTrimKnotMultiplicity(let target, let knotIndex, let multiplicity) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected setSurfaceTrimKnotMultiplicity."
                    )
                }
                var updatedDocument = document
                try updatedDocument.setSurfaceTrimKnotMultiplicity(
                    target: target,
                    knotIndex: knotIndex,
                    multiplicity: multiplicity,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .matchSurfaceBoundaryContinuity:
            func run() throws {
                guard case .matchSurfaceBoundaryContinuity( let target, let reference, let level, let matchSide, let referenceDirection ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected matchSurfaceBoundaryContinuity."
                    )
                }
                var updatedDocument = document
                try updatedDocument.matchSurfaceBoundaryContinuity(
                    target: target,
                    reference: reference,
                    level: level,
                    matchSide: matchSide,
                    referenceDirection: referenceDirection,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .slidePolySplineSurfaceVertices:
            func run() throws {
                guard case .slidePolySplineSurfaceVertices(let targets, let direction, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected slidePolySplineSurfaceVertices."
                    )
                }
                var updatedDocument = document
                try updatedDocument.slidePolySplineSurfaceVertices(
                    targets: targets,
                    direction: direction,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .slideSurfaceControlPoints:
            func run() throws {
                guard case .slideSurfaceControlPoints(let targets, let direction, let distance) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected slideSurfaceControlPoints."
                    )
                }
                var updatedDocument = document
                try updatedDocument.slideSurfaceControlPoints(
                    targets: targets,
                    direction: direction,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createExtrudedRectangle:
            func run() throws {
                guard case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createExtrudedRectangle."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createExtrudedRectangle(
                    name: name,
                    plane: plane,
                    width: width,
                    height: height,
                    depth: depth,
                    direction: direction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createExtrudedRectangleFromCorners:
            func run() throws {
                guard case .createExtrudedRectangleFromCorners( let name, let plane, let firstCorner, let oppositeCorner, let depth, let direction ) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createExtrudedRectangleFromCorners."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createExtrudedRectangleFromCorners(
                    name: name,
                    plane: plane,
                    firstCorner: firstCorner,
                    oppositeCorner: oppositeCorner,
                    depth: depth,
                    direction: direction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .createExtrudedCircle:
            func run() throws {
                guard case .createExtrudedCircle(let name, let plane, let center, let radius, let depth, let direction) = command else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Command dispatch expected createExtrudedCircle."
                    )
                }
                var updatedDocument = document
                primaryFeatureID = try updatedDocument.createExtrudedCircle(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    depth: depth,
                    direction: direction,
                    objectRegistry: objectRegistry
                )
                document = updatedDocument
                try commitMutation()
                evaluateCurrentDocument()
            }
            try run()
        case .validateDocument:
            func run() throws {
                evaluateCurrentDocument()
            }
            try run()
        }

        let createdFeatureIDs = Array(
            document.cadDocument.designGraph.order.dropFirst(previousFeatureCount)
        )
        return CommandExecutionResult(
            commandName: command.name,
            generation: generation,
            didMutate: didMutate,
            diagnostics: diagnostics,
            primaryFeatureID: primaryFeatureID,
            createdFeatureIDs: createdFeatureIDs,
            curveRebuildReport: curveRebuildReport,
            addedSelectionDimensionID: addedSelectionDimensionID,
            createdConstructionPlaneID: createdConstructionPlaneID
        )
    }

    public func markClean() {
        isDirty = false
    }

    public func evaluateCurrentDocument() {
        guard evaluationDeferralDepth == 0 else {
            hasDeferredEvaluation = true
            return
        }
        performCurrentDocumentEvaluation()
    }

    package func withDeferredEvaluation<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        evaluationDeferralDepth += 1
        do {
            let value = try operation()
            evaluationDeferralDepth -= 1
            if evaluationDeferralDepth == 0, hasDeferredEvaluation {
                hasDeferredEvaluation = false
                performCurrentDocumentEvaluation()
            }
            return value
        } catch {
            evaluationDeferralDepth -= 1
            if evaluationDeferralDepth == 0 {
                hasDeferredEvaluation = false
            }
            throw error
        }
    }

    private func performCurrentDocumentEvaluation() {
        completedEvaluationPassCount += 1
        let previousEvaluation = evaluationCache?.evaluatedDocument
        let result: DocumentEvaluationResult
        if let validatedSource {
            result = evaluationScheduler.evaluateResult(
                validatedDocument: validatedSource,
                generation: generation,
                objectRegistry: objectRegistry,
                reusing: previousEvaluation
            )
        } else {
            result = evaluationScheduler.evaluateResult(
                document: document,
                generation: generation,
                objectRegistry: objectRegistry,
                reusing: previousEvaluation
            )
        }
        applyEvaluation(result)
    }

    private func requireValidCommittedEvaluation() throws {
        guard evaluatedGeneration == generation else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document evaluation did not reach the proposed generation."
            )
        }
        switch evaluationStatus {
        case .valid:
            return
        case .failed(let message):
            throw EditorError(code: .evaluationFailed, message: message)
        case .notEvaluated:
            throw EditorError(
                code: .evaluationFailed,
                message: "Document mutation did not produce an evaluated document."
            )
        }
    }

    private func commitMutation() throws {
        generation = try generation.advanced()
        isDirty = true
        validatedSource = nil
    }

    private func applyEvaluation(_ result: DocumentEvaluationResult) {
        let snapshot = result.snapshot
        diagnostics = snapshot.diagnostics
        evaluationStatus = snapshot.status
        evaluatedGeneration = snapshot.evaluatedGeneration
        renderInvalidation = snapshot.renderInvalidation
        evaluatedBodyCount = snapshot.bodyCount
        if case .valid = snapshot.status,
           snapshot.evaluatedGeneration == generation {
            evaluationCache = result.evaluationCache
            validatedSource = result.evaluationCache?.validatedDocument
        } else {
            evaluationCache = nil
            validatedSource = nil
        }
    }

    private static func currentValidatedEvaluationCache(
        cache: EvaluatedDocumentCache?,
        document: DesignDocument,
        generation: DocumentGeneration,
        evaluationStatus: EvaluationStatus,
        evaluatedGeneration: DocumentGeneration?
    ) -> EvaluatedDocumentCache? {
        guard evaluatedGeneration == generation else {
            return nil
        }
        guard case .valid = evaluationStatus else {
            return nil
        }
        guard let cache,
              cache.generation == generation else {
            return nil
        }
        guard cache.matches(
            document: document,
            generation: generation
        ) else {
            return nil
        }
        return cache
    }

    private static func currentTrustedEvaluationCache(
        cache: EvaluatedDocumentCache?,
        document: DesignDocument,
        generation: DocumentGeneration,
        evaluationStatus: EvaluationStatus,
        evaluatedGeneration: DocumentGeneration?
    ) -> EvaluatedDocumentCache? {
        guard evaluatedGeneration == generation,
              case .valid = evaluationStatus,
              let cache,
              cache.generation == generation,
              cache.modelingSettings == document.modelingSettings else {
            return nil
        }
        let cachedSource = cache.evaluatedDocument.document
        let source = document.cadDocument
        guard cachedSource.id == source.id,
              cachedSource.schemaVersion == source.schemaVersion,
              cachedSource.units == source.units,
              cachedSource.designGraph.revision == source.designGraph.revision,
              cachedSource.parameters.revision == source.parameters.revision else {
            return nil
        }
        return cache
    }
}

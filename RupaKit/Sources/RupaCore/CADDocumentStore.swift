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

    private func applyCommand(_ command: EditorCommand) throws -> CommandExecutionResult {
        var curveRebuildReport: CurveRebuildReport?
        var addedSelectionDimensionID: SelectionDimensionID?
        var createdConstructionPlaneID: ConstructionPlaneSourceID?
        var primaryFeatureID: FeatureID?
        var didMutate = command.mutatesDocument
        let previousFeatureCount = document.cadDocument.designGraph.order.count
        switch command {
        case .createSavedView(let savedView):
            try document.createSavedView(
                savedView,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .updateSavedView(let savedView):
            try document.updateSavedView(
                savedView,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .removeSavedView(let id):
            try document.removeSavedView(
                id: id,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .rebaseWorkspaceOrigin(let translation):
            try document.rebaseWorkspaceOrigin(
                translation: translation,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .renameDocument(let name):
            document.rename(name)
            try commitMutation()
            evaluateCurrentDocument()
        case .resetDocument(let name):
            document = .empty(named: name)
            try commitMutation()
            evaluateCurrentDocument()
        case .replaceProductMetadata(let metadata):
            document.productMetadata = metadata
            try commitMutation()
            evaluateCurrentDocument()
        case .applySemanticExtensionMutations(let mutations):
            try document.applySemanticExtensionMutations(
                mutations,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .upsertParameter(let name, let expression, let kind):
            try document.upsertParameter(
                name: name,
                expression: expression,
                kind: kind,
                objectRegistry: objectRegistry
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .renameParameter(let currentName, let newName):
            var updatedDocument = document
            try updatedDocument.renameParameter(
                currentName: currentName,
                newName: newName,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .deleteParameter(let name):
            var updatedDocument = document
            try updatedDocument.deleteParameter(name: name, objectRegistry: objectRegistry)
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setFeatureSuppression(let featureID, let isSuppressed):
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
        case .appendFeatureGraph(let transaction):
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
        case .createComponentDefinition(let name, let rootSceneNodeIDs):
            var updatedDocument = document
            try updatedDocument.createComponentDefinition(
                name: name,
                rootSceneNodeIDs: rootSceneNodeIDs,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createComponentInstance(let name, let definitionID, let localTransform):
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
        case .createPatternArray(let name, let definitionID, let distribution, let outputMode):
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
        case .updatePatternArray(let id, let name, let definitionID, let distribution, let outputMode):
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
        case .explodePatternArray(let id):
            var updatedDocument = document
            try updatedDocument.explodePatternArray(
                id: id,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSceneNodeVisibility(let id, let isVisible):
            var updatedDocument = document
            try updatedDocument.setSceneNodeVisibility(id: id, isVisible: isVisible, objectRegistry: objectRegistry)
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSceneNodeLock(let id, let isLocked):
            var updatedDocument = document
            try updatedDocument.setSceneNodeLock(id: id, isLocked: isLocked, objectRegistry: objectRegistry)
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSceneNodeTransform(let id, let localTransform):
            var updatedDocument = document
            try updatedDocument.setSceneNodeTransform(
                id: id,
                localTransform: localTransform,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSceneNodeMaterial(let id, let materialID):
            var updatedDocument = document
            try updatedDocument.setSceneNodeMaterial(id: id, materialID: materialID, objectRegistry: objectRegistry)
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setTopologyMaterialBinding(let target, let materialID, let process):
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
        case .setSceneNodeObjectProperty(let id, let propertyID, let value):
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
        case .setComponentInstanceVisibility(let id, let isVisible):
            var updatedDocument = document
            try updatedDocument.setComponentInstanceVisibility(
                id: id,
                isVisible: isVisible,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setComponentInstanceLock(let id, let isLocked):
            var updatedDocument = document
            try updatedDocument.setComponentInstanceLock(
                id: id,
                isLocked: isLocked,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setComponentInstanceTransform(let id, let localTransform):
            var updatedDocument = document
            try updatedDocument.setComponentInstanceTransform(
                id: id,
                localTransform: localTransform,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createSectionPlane(let name):
            var updatedDocument = document
            try updatedDocument.createSectionPlane(name: name, objectRegistry: objectRegistry)
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createConstructionPlane(let name, let plane):
            var updatedDocument = document
            createdConstructionPlaneID = try updatedDocument.createConstructionPlane(
                name: name,
                plane: plane,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createConstructionPlaneFromTarget(let name, let target):
            var updatedDocument = document
            createdConstructionPlaneID = try updatedDocument.createConstructionPlaneFromTarget(
                name: name,
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createConstructionPlaneFromTargets(let name, let targets, let viewNormal):
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
        case .createViewAlignedConstructionPlane(let name, let origin, let viewNormal):
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
        case .renameConstructionPlane(let id, let name):
            var updatedDocument = document
            try updatedDocument.renameConstructionPlane(
                id: id,
                name: name,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setConstructionPlane(let id, let plane):
            var updatedDocument = document
            try updatedDocument.setConstructionPlane(
                id: id,
                plane: plane,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createSketch(let name, let sketch, let geometryRole):
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
        case .createLineSketch(let name, let plane, let start, let end):
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
        case .createCircleSketch(let name, let plane, let center, let radius):
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
        case .createArcSketch(let name, let plane, let center, let radius, let startAngle, let endAngle):
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
        case .createSplineSketch(let name, let plane, let spline):
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
        case .createRectangleSketch(let name, let plane, let width, let height):
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
        case .createPolygonSketch(
            let name,
            let plane,
            let center,
            let radius,
            let sides,
            let sizingMode,
            let inclinationMode,
            let rotationAngle
        ):
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
        case .createFaceKnife(let name, let target, let loop):
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
        case .projectSketchCurvesToConstructionPlane(let targets, let plane, let name):
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
        case .projectCurvesToGeneratedFace(let targets, let face, let name):
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
        case .projectBodyOutlinesToConstructionPlane(let targets, let plane, let name):
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
        case .addSketchConstraint(let featureID, let constraint):
            var updatedDocument = document
            try updatedDocument.addSketchConstraint(
                featureID: featureID,
                constraint: constraint,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .removeSketchConstraint(let featureID, let constraint):
            var updatedDocument = document
            try updatedDocument.removeSketchConstraint(
                featureID: featureID,
                constraint: constraint,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createBridgeCurve(let featureID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
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
        case .setBridgeCurveParameters(let sourceID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
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
        case .createRectangleSketchFromCorners(let name, let plane, let firstCorner, let oppositeCorner):
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
        case .setExtrudeDistance(let featureID, let distance):
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
        case .setCubeDimensions(let featureID, let sizeX, let sizeY, let sizeZ):
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
        case .setCylinderDimensions(let featureID, let radius, let sizeY):
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
        case .setObjectDimension(let target, let kind, let value):
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
        case .addSelectionDimension(let name, let kind, let first, let second, let target):
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
        case .setSelectionDimensionTarget(let id, let target):
            var updatedDocument = document
            try updatedDocument.setSelectionDimensionTarget(
                id: id,
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .applySelectionDimensionTarget(let id):
            var updatedDocument = document
            try updatedDocument.applySelectionDimensionTarget(
                id: id,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .removeSelectionDimension(let id):
            var updatedDocument = document
            try updatedDocument.removeSelectionDimension(
                id: id,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .offsetCurve(let target, let distance, let options, let vertexHandle):
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
        case .offsetRegions(let targets, let distance, let options, let combinesRegions):
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
        case .offsetSketchVertex(let target, let handle, let distance):
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
        case .applySketchCornerTreatment(let target, let adjacentTarget, let distance, let treatment):
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
        case .createSlotSketch(let target, let width):
            var updatedDocument = document
            try updatedDocument.createSlotSketch(
                target: target,
                width: width,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .offsetBodyFace(let target, let distance):
            var updatedDocument = document
            try updatedDocument.offsetBodyFace(
                target: target,
                distance: distance,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .deleteBodyFaces(let targets):
            var updatedDocument = document
            try updatedDocument.deleteBodyFaces(
                targets: targets,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .draftBodyFaces(let targets, let neutralTarget, let angle):
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
        case .chamferBodyEdges(let targets, let distance):
            var updatedDocument = document
            try updatedDocument.chamferBodyEdges(
                targets: targets,
                distance: distance,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .filletBodyEdges(let targets, let radius, let segmentCount):
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
        case .moveBody(let target, let deltaX, let deltaY):
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
        case .moveBodyEdge(let target, let deltaX, let deltaY):
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
        case .moveBodyVertex(let target, let deltaX, let deltaY):
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
        case .moveSketchEntityPoint(let target, let handle, let deltaX, let deltaY):
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
        case .moveSketchSplineControlPoint(let target, let controlPointIndex, let deltaX, let deltaY):
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
        case .alignSketchVertex(let target, let reference, let options):
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
        case .slideSketchSplineControlPoints(let target, let controlPointIndexes, let direction, let distance):
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
        case .insertSketchSplineControlPoint(let target, let fraction):
            var updatedDocument = document
            try updatedDocument.insertSketchSplineControlPoint(
                target: target,
                fraction: fraction,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSketchCircleParameters(let target, let center, let radius):
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
        case .setSketchArcParameters(let target, let center, let radius, let startAngle, let endAngle):
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
        case .setSketchEntityDimension(let target, let kind, let value):
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
        case .convertSketchLineToArc(let target, let sagitta):
            var updatedDocument = document
            try updatedDocument.convertSketchLineToArc(
                target: target,
                sagitta: sagitta,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .convertSketchLineToSpline(let target):
            var updatedDocument = document
            try updatedDocument.convertSketchLineToSpline(
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .reverseSketchCurve(let target):
            var updatedDocument = document
            try updatedDocument.reverseSketchCurve(
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .rebuildSketchCurve(let target, let options):
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
        case .extendSketchCurve(let target, let distance, let shape):
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
        case .joinSketchCurves(let target, let adjacentTarget, let continuity):
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
        case .unjoinSketchCurve(let target):
            var updatedDocument = document
            try updatedDocument.unjoinSketchCurve(
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .splitSketchCurve(let target, let fraction):
            var updatedDocument = document
            try updatedDocument.splitSketchCurve(
                target: target,
                fraction: fraction,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .trimSketchCurveSegment(let target):
            var updatedDocument = document
            try updatedDocument.trimSketchCurveSegment(
                target: target,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .cutSketchCurve(let target, let cutter, let options):
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
        case .extrudeProfile(let name, let profile, let distance, let direction):
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
        case .createRevolve(let name, let profile, let axis, let angle):
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
        case .createSweep(let name, let sections, let path, let guides, let targets, let options):
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
        case .createLoft(let name, let sections, let guides, let options):
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
        case .createBoolean(let name, let targets, let tool, let operation, let keepTools):
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
        case .createBSplineSurface(let name, let surface):
            var updatedDocument = document
            primaryFeatureID = try updatedDocument.createBSplineSurface(
                name: name,
                surface: surface,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createPolySplineSurface(let name, let sourceMesh, let options):
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
        case .movePolySplineSurfaceVertex(let target, let deltaX, let deltaY, let deltaZ):
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
        case .moveSurfaceControlPoint(let target, let deltaX, let deltaY, let deltaZ):
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
        case .moveSurfaceControlPointsInFrame(
            let targets,
            let frame,
            let uDistance,
            let vDistance,
            let normalDistance
        ):
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
        case .setSurfaceControlPointWeight(let target, let weight):
            var updatedDocument = document
            try updatedDocument.setSurfaceControlPointWeight(
                target: target,
                weight: weight,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSurfaceKnotValue(let target, let value):
            var updatedDocument = document
            try updatedDocument.setSurfaceKnotValue(
                target: target,
                value: value,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .insertSurfaceKnot(let target, let value):
            var updatedDocument = document
            try updatedDocument.insertSurfaceKnot(
                target: target,
                value: value,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .splitSurfaceSpan(let target, let fraction):
            var updatedDocument = document
            try updatedDocument.splitSurfaceSpan(
                target: target,
                fraction: fraction,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSurfaceKnotMultiplicity(let target, let multiplicity):
            var updatedDocument = document
            try updatedDocument.setSurfaceKnotMultiplicity(
                target: target,
                multiplicity: multiplicity,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSurfaceTrimDomain(
            let target,
            let uLowerBound,
            let uUpperBound,
            let vLowerBound,
            let vUpperBound
        ):
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
        case .setSurfaceTrimLoops(let target, let trimLoops):
            var updatedDocument = document
            try updatedDocument.setSurfaceTrimLoops(
                target: target,
                trimLoops: trimLoops,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .moveSurfaceTrimEndpoint(let target, let endpoint, let u, let v):
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
        case .moveSurfaceTrimControlPoint(let target, let controlPointIndex, let u, let v):
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
        case .setSurfaceTrimControlPointWeight(let target, let controlPointIndex, let weight):
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
        case .insertSurfaceTrimKnot(let target, let value):
            var updatedDocument = document
            try updatedDocument.insertSurfaceTrimKnot(
                target: target,
                value: value,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .setSurfaceTrimKnotValue(let target, let knotIndex, let value):
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
        case .setSurfaceTrimKnotMultiplicity(let target, let knotIndex, let multiplicity):
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
        case .matchSurfaceBoundaryContinuity(
            let target,
            let reference,
            let level,
            let matchSide,
            let referenceDirection
        ):
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
        case .slidePolySplineSurfaceVertices(let targets, let direction, let distance):
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
        case .slideSurfaceControlPoints(let targets, let direction, let distance):
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
        case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction):
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
        case .createExtrudedRectangleFromCorners(
            let name,
            let plane,
            let firstCorner,
            let oppositeCorner,
            let depth,
            let direction
        ):
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
        case .createExtrudedCircle(let name, let plane, let center, let radius, let depth, let direction):
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
        case .validateDocument:
            evaluateCurrentDocument()
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

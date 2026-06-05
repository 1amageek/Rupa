import Foundation
import Observation

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
    public let objectRegistry: ObjectTypeRegistry
    private let evaluationScheduler: EvaluationScheduler

    public init(
        document: DesignDocument = .empty(),
        generation: DocumentGeneration = DocumentGeneration(),
        isDirty: Bool = false,
        diagnostics: [EditorDiagnostic] = [],
        evaluationStatus: EvaluationStatus = .notEvaluated,
        evaluatedGeneration: DocumentGeneration? = nil,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        evaluatedBodyCount: Int = 0,
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
        self.objectRegistry = objectRegistry
        self.evaluationScheduler = evaluationScheduler
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
        document = snapshot.document
        generation = snapshot.generation
        isDirty = snapshot.isDirty
        diagnostics = snapshot.diagnostics
        evaluationStatus = snapshot.evaluationStatus
        evaluatedGeneration = snapshot.evaluatedGeneration
        renderInvalidation = snapshot.renderInvalidation
        evaluatedBodyCount = snapshot.evaluatedBodyCount
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
        switch command {
        case .setDisplayUnit(let unit):
            document.setDisplayUnit(unit)
            try commitMutation()
            evaluateCurrentDocument()
        case .setRulerConfiguration(let configuration):
            try document.setRulerConfiguration(configuration)
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
        case .upsertParameter(let name, let expression, let kind):
            document.upsertParameter(
                name: name,
                expression: expression,
                kind: kind
            )
            try commitMutation()
            evaluateCurrentDocument()
        case .deleteParameter(let name):
            var updatedDocument = document
            try updatedDocument.deleteParameter(name: name)
            document = updatedDocument
            try commitMutation()
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
            try updatedDocument.setExtrudeDistance(
                featureID: featureID,
                distance: distance,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
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
        case .extrudeProfile(let name, let profile, let distance, let direction):
            var updatedDocument = document
            try updatedDocument.extrudeProfile(
                name: name,
                profile: profile,
                distance: distance,
                direction: direction,
                objectRegistry: objectRegistry
            )
            document = updatedDocument
            try commitMutation()
            evaluateCurrentDocument()
        case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction):
            var updatedDocument = document
            try updatedDocument.createExtrudedRectangle(
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
            try updatedDocument.createExtrudedRectangleFromCorners(
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
            try updatedDocument.createExtrudedCircle(
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

        return CommandExecutionResult(
            commandName: command.name,
            generation: generation,
            didMutate: command.mutatesDocument,
            diagnostics: diagnostics
        )
    }

    public func markClean() {
        isDirty = false
    }

    public func evaluateCurrentDocument() {
        applyEvaluation(
            evaluationScheduler.evaluate(
                document: document,
                generation: generation,
                objectRegistry: objectRegistry
            )
        )
    }

    private func commitMutation() throws {
        generation = try generation.advanced()
        isDirty = true
    }

    private func applyEvaluation(_ snapshot: EvaluationSnapshot) {
        diagnostics = snapshot.diagnostics
        evaluationStatus = snapshot.status
        evaluatedGeneration = snapshot.evaluatedGeneration
        renderInvalidation = snapshot.renderInvalidation
        evaluatedBodyCount = snapshot.bodyCount
    }
}

import Testing
import RupaCore
import SwiftCAD
@testable import RupaAutomation

@MainActor
@Test func automationCanChangeDisplayUnit() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(.setDisplayUnit(.meter), in: session)

    #expect(session.document.displayUnit == .meter)
    #expect(session.generation == DocumentGeneration(1))
    #expect(result.didMutate)
    #expect(result.message.contains("m"))
}

@MainActor
@Test func automationBatchUsesExpectedGeneration() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let batch = AutomationBatch(
        commands: [
            .renameDocument(name: "Batch"),
            .validateDocument,
        ],
        expectedGeneration: DocumentGeneration(0)
    )

    let results = try runner.executeBatch(batch, in: session)

    #expect(results.count == 2)
    #expect(results[0].didMutate)
    #expect(!results[1].didMutate)
    #expect(session.document.cadDocument.metadata.name == "Batch")
    #expect(session.generation == DocumentGeneration(1))
}

@MainActor
@Test func automationCanSetParameter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(
        .upsertParameter(
            name: "depth",
            expression: .constant(.length(4.0, unit: .centimeter)),
            kind: .length
        ),
        in: session
    )

    let parameter = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "depth" }
    )
    #expect(result.message == "Parameter depth updated.")
    #expect(result.commandName == "upsertParameter")
    #expect(result.didMutate)
    #expect(parameter.kind == .length)
    #expect(session.generation == DocumentGeneration(1))
}

@MainActor
@Test func automationCanDeleteParameter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .upsertParameter(
            name: "depth",
            expression: .constant(.length(4.0, unit: .centimeter)),
            kind: .length
        ),
        in: session
    )

    let result = try runner.execute(
        .deleteParameter(name: "depth"),
        in: session
    )

    #expect(result.message == "Parameter depth deleted.")
    #expect(result.commandName == "deleteParameter")
    #expect(result.didMutate)
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func automationCanCreateExtrudedRectangle() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Box",
            plane: .xy,
            width: .length(30.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )

    #expect(result.message == "Extruded rectangle Automation Box created.")
    #expect(result.commandName == "createExtrudedRectangle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanCreateExtrudedRectangleFromCorners() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(
        .createExtrudedRectangleFromCorners(
            name: "Automation Footprint Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(-2.0, .millimeter),
                y: .length(1.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(7.0, .millimeter)
            ),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )

    #expect(result.message == "Extruded rectangle Automation Footprint Box created.")
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanCreateExtrudedCircle() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(
        .createExtrudedCircle(
            name: "Automation Cylinder",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            depth: .length(8.0, .millimeter),
            direction: .normal
        ),
        in: session
    )

    #expect(result.message == "Extruded circle Automation Cylinder created.")
    #expect(result.commandName == "createExtrudedCircle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanCreateSketchPrimitives() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let lineResult = try runner.execute(
        .createLineSketch(
            name: "Automation Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(8.0, .millimeter)
            )
        ),
        in: session
    )
    let circleResult = try runner.execute(
        .createCircleSketch(
            name: "Automation Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(3.0, .millimeter)
        ),
        in: session
    )

    #expect(lineResult.message == "Line sketch Automation Line created.")
    #expect(lineResult.commandName == "createLineSketch")
    #expect(circleResult.message == "Circle sketch Automation Circle created.")
    #expect(circleResult.commandName == "createCircleSketch")
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddSketchConstraint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createLineSketch(
            name: "Automation Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(automationSingleSketchEntityID(in: session.document, featureID: featureID))

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: featureID))
    #expect(result.message == "Sketch constraint added to \(featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateAndControlComponentInstances() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)

    let definitionResult = try runner.execute(
        .createComponentDefinition(
            name: "Automation Component",
            rootSceneNodeIDs: [rootSceneNodeID]
        ),
        in: session
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let instanceResult = try runner.execute(
        .createComponentInstance(
            name: "Automation Component A",
            definitionID: definition.id,
            localTransform: .identity
        ),
        in: session
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )

    let visibilityResult = try runner.execute(
        .setComponentInstanceVisibility(id: instance.id, isVisible: false),
        in: session
    )
    let lockResult = try runner.execute(
        .setSceneNodeLock(id: sceneNode.id, isLocked: true),
        in: session
    )
    let instanceTransform = try automationTranslationTransform(x: 0.1, y: 0.2, z: 0.3)
    let transformResult = try runner.execute(
        .setComponentInstanceTransform(
            id: instance.id,
            localTransform: instanceTransform
        ),
        in: session
    )

    #expect(definitionResult.commandName == "createComponentDefinition")
    #expect(definitionResult.message == "Component definition Automation Component created.")
    #expect(instanceResult.commandName == "createComponentInstance")
    #expect(instanceResult.message == "Component instance Automation Component A created.")
    #expect(visibilityResult.commandName == "setComponentInstanceVisibility")
    #expect(lockResult.commandName == "setSceneNodeLock")
    #expect(transformResult.commandName == "setComponentInstanceTransform")
    #expect(session.document.productMetadata.componentInstances[instance.id]?.isVisible == false)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.isLocked == true)
    #expect(session.document.productMetadata.componentInstances[instance.id]?.localTransform == instanceTransform)
    #expect(session.generation == DocumentGeneration(5))
}

@MainActor
@Test func automationCanCreateSectionPlane() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let result = try runner.execute(
        .createSectionPlane(name: "Automation Section"),
        in: session
    )

    #expect(result.message == "Section plane Automation Section created.")
    #expect(result.commandName == "createSectionPlane")
    #expect(result.didMutate)
    #expect(session.document.productMetadata.sceneNodes.values.contains { node in
        node.name == "Automation Section" && node.reference == .construction
    })
    #expect(session.generation == DocumentGeneration(1))
}

@MainActor
@Test func automationBatchRejectsGenerationMismatch() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(.setDisplayUnit(.meter), in: session)

    var caught: EditorError?
    do {
        _ = try runner.executeBatch(
            AutomationBatch(
                commands: [.renameDocument(name: "Rejected")],
                expectedGeneration: DocumentGeneration(0)
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

private func automationSketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

private func automationSingleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = automationSketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

private func automationTranslationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(
            values: [
                1.0, 0.0, 0.0, x,
                0.0, 1.0, 0.0, y,
                0.0, 0.0, 1.0, z,
                0.0, 0.0, 0.0, 1.0,
            ]
        )
    )
}

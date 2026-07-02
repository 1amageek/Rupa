import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func workspaceScaleDefaultsMatchMillimeterDocumentScale() async throws {
    let defaults = WorkspaceScaleDefaults(ruler: .standard(for: .millimeter))

    #expect(approximatelyEqual(defaults.baseFeatureMeters, 0.04))
    #expect(approximatelyEqual(defaults.sketchWidthMeters, 0.04))
    #expect(approximatelyEqual(defaults.sketchHeightMeters, 0.02))
    #expect(approximatelyEqual(defaults.sketchDepthMeters, 0.01))
    #expect(approximatelyEqual(defaults.cylinderDepthMeters, 0.02))
    #expect(approximatelyEqual(defaults.curveRadiusMeters, 0.012))
    #expect(approximatelyEqual(defaults.maximumSplineBowMeters, 0.024))
}

@Test func workspaceScaleDefaultsTrackMeterDocumentScale() async throws {
    let defaults = WorkspaceScaleDefaults(ruler: .standard(for: .meter))

    #expect(approximatelyEqual(defaults.baseFeatureMeters, 40.0))
    #expect(approximatelyEqual(defaults.sketchWidthMeters, 40.0))
    #expect(approximatelyEqual(defaults.sketchHeightMeters, 20.0))
    #expect(approximatelyEqual(defaults.sketchDepthMeters, 10.0))
    #expect(approximatelyEqual(defaults.curveRadiusMeters, 12.0))
}

@Test func workspaceScaleDefaultsFollowVisibleSpanWhenDocumentStaysInMillimeters() async throws {
    let ruler = RulerConfiguration(
        displayUnit: .millimeter,
        minorTickMeters: 0.1,
        majorTickMeters: 1.0,
        visibleSpanMeters: 100.0
    )
    let defaults = WorkspaceScaleDefaults(ruler: ruler)

    #expect(approximatelyEqual(defaults.baseFeatureMeters, 4.0))
    #expect(approximatelyEqual(defaults.sketchHeightMeters, 2.0))
    #expect(approximatelyEqual(defaults.sketchDepthMeters, 1.0))
    #expect(approximatelyEqual(defaults.curveRadiusMeters, 1.2))
}

@Test func objectTypeRegistryDefaultPropertiesUseWorkspaceScaleDefinitions() async throws {
    let registry = ObjectTypeRegistry.builtIn
    let siteRuler = WorkspaceScalePreset.sitePlanning.rulerConfiguration

    let rectangle = registry.defaultProperties(for: .rectangle, ruler: siteRuler)
    #expect(approximatelyEqual(rectangle["size.x"]?.lengthValue, 4_000.0))
    #expect(approximatelyEqual(rectangle["size.y"]?.lengthValue, 2_000.0))
    #expect(approximatelyEqual(rectangle["extrusion"]?.lengthValue, 0.0))

    let regionalRuler = WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    let circle = registry.defaultProperties(for: .circle, ruler: regionalRuler)
    #expect(approximatelyEqual(circle["radius"]?.lengthValue, 12_000.0))

    let cube = registry.defaultProperties(for: .cube, ruler: regionalRuler)
    #expect(approximatelyEqual(cube["size.x"]?.lengthValue, 40_000.0))
    #expect(approximatelyEqual(cube["size.y"]?.lengthValue, 40_000.0))
    #expect(approximatelyEqual(cube["size.z"]?.lengthValue, 40_000.0))

    let cylinder = registry.defaultProperties(for: .cylinder, ruler: regionalRuler)
    #expect(approximatelyEqual(cylinder["size.x"]?.lengthValue, 24_000.0))
    #expect(approximatelyEqual(cylinder["size.y"]?.lengthValue, 20_000.0))
    #expect(approximatelyEqual(cylinder["size.z"]?.lengthValue, 24_000.0))
    #expect(approximatelyEqual(cylinder["radius"]?.lengthValue, 12_000.0))
}

@Test func customObjectRegistryCanDeclareWorkspaceScaleDefaults() async throws {
    let typeID: ObjectTypeID = "custom.sitePanel"
    let registry = try ObjectTypeRegistry(
        definitions: [
            ObjectTypeDefinition(
                id: typeID,
                title: "Site Panel",
                systemImage: "rectangle",
                representation: .twoDimensional,
                category: .sketch,
                geometryRole: .sketchProfile,
                properties: [
                    ObjectPropertyDefinition(
                        id: "panel.width",
                        title: "Width",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(1.0),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.width",
                        workspaceScaleDefault: .sketchWidth
                    ),
                    ObjectPropertyDefinition(
                        id: "panel.depth",
                        title: "Depth",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(0.1),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.depth",
                        workspaceScaleDefault: .sketchDepth
                    ),
                ]
            ),
        ]
    )

    let properties = registry.defaultProperties(
        for: typeID,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    #expect(approximatelyEqual(properties["panel.width"]?.lengthValue, 4_000.0))
    #expect(approximatelyEqual(properties["panel.depth"]?.lengthValue, 1_000.0))
}

@Test func sketchObjectTypeDefaultsFollowDocumentWorkspaceScale() async throws {
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    let featureID = try document.createLineSketch(
        name: "Typed Source",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(10.0, .meter), y: .length(0.0, .meter))
    )

    try document.setSketchObjectType(
        featureID: featureID,
        typeID: .rectangle,
        objectRegistry: .builtIn
    )

    let sceneNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.object?.sourceFeatureID == featureID
    })
    #expect(approximatelyEqual(sceneNode.object?.properties["size.x"]?.lengthValue, 4_000.0))
    #expect(approximatelyEqual(sceneNode.object?.properties["size.y"]?.lengthValue, 2_000.0))
    #expect(approximatelyEqual(sceneNode.object?.properties["extrusion"]?.lengthValue, 0.0))
}

@MainActor
@Test func editorSessionDefaultSolidUsesWorkspaceScale() async throws {
    let session = EditorSession()
    _ = try session.execute(.setRulerConfiguration(.standard(for: .meter)))

    _ = try #require(session.createDefaultExtrudedRectangle())
    let sketchNode = try #require(firstSceneNode(with: .sketch, in: session.document))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let extrude) = bodyFeature.operation else {
        Issue.record("Expected default solid creation to create an extrude feature.")
        return
    }

    #expect(approximatelyEqual(sketchNode.object?.properties["size.x"]?.lengthValue, 40.0))
    #expect(approximatelyEqual(sketchNode.object?.properties["size.y"]?.lengthValue, 20.0))
    #expect(approximatelyEqual(try resolvedLength(extrude.distance, in: session.document), 10.0))
}

@MainActor
@Test func editorSessionDefaultSolidUsesSitePlanningWorkspaceScale() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    )

    _ = try #require(session.createDefaultExtrudedRectangle())
    let sketchNode = try #require(firstSceneNode(with: .sketch, in: session.document))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let extrude) = bodyFeature.operation else {
        Issue.record("Expected default solid creation to create an extrude feature.")
        return
    }

    #expect(approximatelyEqual(sketchNode.object?.properties["size.x"]?.lengthValue, 4_000.0))
    #expect(approximatelyEqual(sketchNode.object?.properties["size.y"]?.lengthValue, 2_000.0))
    #expect(approximatelyEqual(try resolvedLength(extrude.distance, in: session.document), 1_000.0))
}

@MainActor
@Test func editorSessionDefaultSolidUsesRegionalPlanningWorkspaceScale() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)
    )

    _ = try #require(session.createDefaultExtrudedRectangle())
    let sketchNode = try #require(firstSceneNode(with: .sketch, in: session.document))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let extrude) = bodyFeature.operation else {
        Issue.record("Expected default solid creation to create an extrude feature.")
        return
    }

    #expect(approximatelyEqual(sketchNode.object?.properties["size.x"]?.lengthValue, 40_000.0))
    #expect(approximatelyEqual(sketchNode.object?.properties["size.y"]?.lengthValue, 20_000.0))
    #expect(approximatelyEqual(try resolvedLength(extrude.distance, in: session.document), 10_000.0))
}

@MainActor
@Test func editorSessionDefaultCircleUsesWorkspaceScale() async throws {
    let session = EditorSession()
    _ = try session.execute(.setRulerConfiguration(.standard(for: .meter)))

    _ = try #require(session.createDefaultCircleSketch())
    let sketchNode = try #require(firstSceneNode(with: .sketch, in: session.document))

    #expect(approximatelyEqual(sketchNode.object?.properties["radius"]?.lengthValue, 12.0))
}

@MainActor
@Test func editorSessionCanvasClickShapesUseWorkspaceScale() async throws {
    let rectangleSession = EditorSession()
    _ = try rectangleSession.execute(.setRulerConfiguration(.standard(for: .meter)))
    _ = try #require(
        rectangleSession.createRectangleSketchFromCanvasClick(
            centerModelPoint: Point2D(x: 0.0, y: 0.0)
        )
    )
    let rectangleNode = try #require(firstSceneNode(with: .sketch, in: rectangleSession.document))
    #expect(approximatelyEqual(rectangleNode.object?.properties["size.x"]?.lengthValue, 40.0))
    #expect(approximatelyEqual(rectangleNode.object?.properties["size.y"]?.lengthValue, 40.0))

    let circleSession = EditorSession()
    _ = try circleSession.execute(.setRulerConfiguration(.standard(for: .meter)))
    _ = try #require(
        circleSession.createCircleSketchFromCanvasClick(
            centerModelPoint: Point2D(x: 0.0, y: 0.0)
        )
    )
    let circleNode = try #require(firstSceneNode(with: .sketch, in: circleSession.document))
    #expect(approximatelyEqual(circleNode.object?.properties["radius"]?.lengthValue, 12.0))
}

@MainActor
@Test func editorSessionCanvasClickShapesUseRegionalPlanningWorkspaceScale() async throws {
    let rectangleSession = EditorSession()
    _ = try rectangleSession.execute(
        .setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)
    )
    _ = try #require(
        rectangleSession.createRectangleSketchFromCanvasClick(
            centerModelPoint: Point2D(x: 0.0, y: 0.0)
        )
    )
    let rectangleNode = try #require(firstSceneNode(with: .sketch, in: rectangleSession.document))
    #expect(approximatelyEqual(rectangleNode.object?.properties["size.x"]?.lengthValue, 40_000.0))
    #expect(approximatelyEqual(rectangleNode.object?.properties["size.y"]?.lengthValue, 40_000.0))

    let circleSession = EditorSession()
    _ = try circleSession.execute(
        .setRulerConfiguration(WorkspaceScalePreset.regionalPlanning.rulerConfiguration)
    )
    _ = try #require(
        circleSession.createCircleSketchFromCanvasClick(
            centerModelPoint: Point2D(x: 0.0, y: 0.0)
        )
    )
    let circleNode = try #require(firstSceneNode(with: .sketch, in: circleSession.document))
    #expect(approximatelyEqual(circleNode.object?.properties["radius"]?.lengthValue, 12_000.0))
}

@Test func canvasCurveDraftsAcceptWorkspaceScaleDefaults() async throws {
    let defaults = WorkspaceScaleDefaults(ruler: .standard(for: .meter))
    let center = Point2D(x: 5.0, y: 7.0)

    let arc = try CanvasSketchCurveDrafts.arc(
        centeredAt: center,
        defaults: defaults
    )
    let spline = try CanvasSketchCurveDrafts.spline(
        centeredAt: center,
        defaults: defaults
    )
    let polygon = try CanvasSketchCurveDrafts.polygon(
        centeredAt: center,
        defaults: defaults
    )

    #expect(approximatelyEqual(arc.radiusMeters, 12.0))
    #expect(approximatelyEqual(polygon.radiusMeters, 12.0))
    #expect(approximatelyEqual(spline.controlPoints.first?.x, -15.0))
    #expect(approximatelyEqual(spline.controlPoints.last?.x, 25.0))
}

private func firstSceneNode(
    with kind: SceneNodeReference.Kind,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference?.kind == kind
    }
}

private func approximatelyEqual(
    _ lhs: Double?,
    _ rhs: Double,
    tolerance: Double = 1.0e-10
) -> Bool {
    guard let lhs else {
        return false
    }
    return approximatelyEqual(lhs, rhs, tolerance: tolerance)
}

private func approximatelyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-10
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func resolvedLength(
    _ expression: CADExpression,
    in document: DesignDocument
) throws -> Double {
    let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private extension ObjectPropertyValue {
    var lengthValue: Double? {
        guard case .length(let value) = self else {
            return nil
        }
        return value
    }
}

import Foundation
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
@Test func automationCanSetExtrudeDistance() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Editable Automation Box",
            plane: .xy,
            width: .length(30.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)

    let result = try runner.execute(
        .setExtrudeDistance(
            featureID: featureID,
            distance: .length(9.0, .millimeter)
        ),
        in: session
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .extrude(let extrude) = feature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let distance = try session.document.cadDocument.parameters.resolvedValue(for: extrude.distance)
    #expect(result.message == "Extrude distance updated.")
    #expect(result.commandName == "setExtrudeDistance")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(distance.kind == .length)
    #expect(abs(distance.value - 0.009) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanSetCubeDimensions() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Editable Automation Cube",
            plane: .xy,
            width: .length(30.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)

    let result = try runner.execute(
        .setCubeDimensions(
            featureID: featureID,
            sizeX: .length(40.0, .millimeter),
            sizeY: .length(9.0, .millimeter),
            sizeZ: .length(14.0, .millimeter)
        ),
        in: session
    )

    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(featureID)
    })
    let sizeX = try #require(bodyNode.object?.properties["size.x"])
    let sizeY = try #require(bodyNode.object?.properties["size.y"])
    let sizeZ = try #require(bodyNode.object?.properties["size.z"])
    guard case .length(let sizeXMeters) = sizeX,
          case .length(let sizeYMeters) = sizeY,
          case .length(let sizeZMeters) = sizeZ else {
        Issue.record("Expected updated cube size properties.")
        return
    }

    #expect(result.message == "Cube dimensions updated.")
    #expect(result.commandName == "setCubeDimensions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(sizeXMeters - 0.040) < 1.0e-12)
    #expect(abs(sizeYMeters - 0.009) < 1.0e-12)
    #expect(abs(sizeZMeters - 0.014) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanSetCylinderDimensions() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedCircle(
            name: "Editable Automation Cylinder",
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
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)

    let result = try runner.execute(
        .setCylinderDimensions(
            featureID: featureID,
            radius: .length(7.0, .millimeter),
            sizeY: .length(11.0, .millimeter)
        ),
        in: session
    )

    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(featureID)
    })
    let radius = try #require(bodyNode.object?.properties["radius"])
    let sizeY = try #require(bodyNode.object?.properties["size.y"])
    guard case .length(let radiusMeters) = radius,
          case .length(let sizeYMeters) = sizeY else {
        Issue.record("Expected updated cylinder size properties.")
        return
    }

    #expect(result.message == "Cylinder dimensions updated.")
    #expect(result.commandName == "setCylinderDimensions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(radiusMeters - 0.007) < 1.0e-12)
    #expect(abs(sizeYMeters - 0.011) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanSetSelectedObjectDimension() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Dimensioned Automation Box",
            plane: .xy,
            width: .length(30.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let result = try runner.execute(
        .setObjectDimension(
            target: SelectionTarget(sceneNodeID: bodyNode.id, component: .face(.bodyFaceTop)),
            kind: .sizeY,
            value: .length(10.0, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Object dimension updated.")
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[bodyNode.id])
    #expect(editedBodyNode.object?.properties["size.y"] == .length(0.01))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanToggleCurveCurvatureDisplay() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createCircleSketch(
            name: "Automation Curvature Display Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let componentID = try #require(automationSketchEntityComponentID(from: target))

    let result = try runner.execute(
        .setCurveCurvatureDisplay(
            target: target,
            isVisible: true,
            combScale: 0.3
        ),
        in: session
    )

    #expect(result.message == "Curve curvature display enabled at comb scale 0.3.")
    #expect(result.commandName == "setCurveCurvatureDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID]?.combScale == 0.3)

    let hideResult = try runner.execute(
        .setCurveCurvatureDisplay(
            target: target,
            isVisible: false,
            combScale: nil
        ),
        in: session
    )
    #expect(hideResult.message == "Curve curvature display disabled.")
    #expect(hideResult.didMutate)
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID] == nil)
}

@MainActor
@Test func automationCanTogglePointDisplay() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Point Display Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                SketchPoint(x: .length(0.002, .meter), y: .length(0.004, .meter)),
                SketchPoint(x: .length(0.006, .meter), y: .length(0.004, .meter)),
                SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let componentID = try #require(automationSketchEntityComponentID(from: target))

    let hideResult = try runner.execute(
        .setPointDisplay(target: target, isVisible: nil),
        in: session
    )

    #expect(hideResult.message == "Point display toggled.")
    #expect(hideResult.commandName == "setPointDisplay")
    #expect(hideResult.didMutate)
    #expect(hideResult.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == false)

    let showResult = try runner.execute(
        .setPointDisplay(target: target, isVisible: nil),
        in: session
    )
    #expect(showResult.message == "Point display toggled.")
    #expect(showResult.didMutate)
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == true)
}

@MainActor
@Test func automationCanToggleSurfaceControlPointDisplay() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createPolySplineSurface(
            name: "Automation Surface CV Display",
            sourceMesh: automationPolySplineQuadMesh(),
            options: PolySplineOptions()
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let displayID = try SurfaceControlPointDisplayID(selectionReference: controlPoint.selectionReference)

    let showResult = try runner.execute(
        .setSurfaceControlPointDisplay(target: controlPoint.selectionReference, isVisible: true),
        in: session
    )

    #expect(showResult.message == "Surface control point display visible.")
    #expect(showResult.commandName == "setSurfaceControlPointDisplay")
    #expect(showResult.didMutate)
    #expect(showResult.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.surfaceControlPointDisplays[displayID]?.isVisible == true)

    let visibleSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let visiblePatch = try #require(visibleSummary.sources.first?.patches.first)
    let visibleControlPoint = try #require(visiblePatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(visibleControlPoint.isPointDisplayVisible)
}

@MainActor
@Test func automationCanToggleSurfaceFrameDisplay() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createPolySplineSurface(
            name: "Automation Surface Frame Display",
            sourceMesh: automationPolySplineQuadMesh(),
            options: PolySplineOptions()
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    let displayID = try SurfaceFrameDisplayID(query: query)

    let showResult = try runner.execute(
        .setSurfaceFrameDisplay(query: query, isVisible: true),
        in: session
    )

    #expect(showResult.message == "Surface frame display visible.")
    #expect(showResult.commandName == "setSurfaceFrameDisplay")
    #expect(showResult.didMutate)
    #expect(showResult.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID]?.isVisible == true)
}

@MainActor
@Test func automationCanMoveSurfaceControlPointsInFrame() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createPolySplineSurface(
            name: "Automation Surface Frame Move",
            sourceMesh: automationPolySplineQuadMesh(),
            options: PolySplineOptions()
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let frameQuery = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    let frameResult = try SurfaceFrameService().resolve(
        document: session.document,
        queries: [frameQuery],
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )
    let frame = try #require(frameResult.frames.first)
    let uDistance = 0.001
    let vDistance = 0.002
    let normalDistance = 0.003

    let moveResult = try runner.execute(
        .moveSurfaceControlPointsInFrame(
            targets: [controlPoint.selectionReference],
            frame: frameQuery,
            uDistance: .length(uDistance, .meter),
            vDistance: .length(vDistance, .meter),
            normalDistance: .length(normalDistance, .meter)
        ),
        in: session
    )

    let movedSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let movedPatch = try #require(movedSummary.sources.first?.patches.first)
    let movedControlPoint = try #require(movedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let expectedX = controlPoint.point.x
        + frame.uAxis.x * uDistance
        + frame.vAxis.x * vDistance
        + frame.normal.x * normalDistance
    let expectedY = controlPoint.point.y
        + frame.uAxis.y * uDistance
        + frame.vAxis.y * vDistance
        + frame.normal.y * normalDistance
    let expectedZ = controlPoint.point.z
        + frame.uAxis.z * uDistance
        + frame.vAxis.z * vDistance
        + frame.normal.z * normalDistance

    #expect(moveResult.message == "Surface control points moved in frame.")
    #expect(moveResult.commandName == "moveSurfaceControlPointsInFrame")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(movedControlPoint.point.x - expectedX) <= 1.0e-12)
    #expect(abs(movedControlPoint.point.y - expectedY) <= 1.0e-12)
    #expect(abs(movedControlPoint.point.z - expectedZ) <= 1.0e-12)
}

@MainActor
@Test func automationCanSetSurfaceKnotMultiplicity() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Explicit Multiplicity Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let knot = try #require(
        summary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    let knotReference = try #require(knot.selectionReference)

    let result = try runner.execute(
        .setSurfaceKnotMultiplicity(
            target: knotReference,
            multiplicity: 2
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    #expect(result.message == "Surface knot multiplicity updated.")
    #expect(result.commandName == "setSurfaceKnotMultiplicity")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vKnots == sourceSurface.vKnots)
    #expect(surfaceFeature.surface.uControlPointCount == sourceSurface.uControlPointCount + 1)
}

@MainActor
@Test func automationCanSetSurfaceTrimDomain() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Trim Domain Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)

    let result = try runner.execute(
        .setSurfaceTrimDomain(
            target: faceReference,
            uLowerBound: .scalar(0.25),
            uUpperBound: .scalar(0.75),
            vLowerBound: .scalar(0.2),
            vUpperBound: .scalar(0.8)
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    let trimDomain = try #require(surfaceFeature.outerTrimDomain)
    #expect(result.message == "Surface trim domain updated.")
    #expect(result.commandName == "setSurfaceTrimDomain")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(trimDomain.uLowerBound == 0.25)
    #expect(trimDomain.uUpperBound == 0.75)
    #expect(trimDomain.vLowerBound == 0.2)
    #expect(trimDomain.vUpperBound == 0.8)
}

@Test func automationCanSetSurfaceTrimLoops() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Trim Loop Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )

    let result = try runner.execute(
        .setSurfaceTrimLoops(
            target: faceReference,
            trimLoops: [trimLoop]
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let updatedTrimLoop = try #require(updatedSummary.sources.first?.patches.first?.trimLoops.first)
    #expect(result.message == "Surface trim loops updated.")
    #expect(result.commandName == "setSurfaceTrimLoops")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(surfaceFeature.outerTrimDomain == nil)
    #expect(surfaceFeature.trimLoops == [trimLoop])
    #expect(updatedTrimLoop.edges.count == 3)
    #expect(updatedTrimLoop.selectionReferences.count == 3)
}

@Test func automationCanMoveSurfaceTrimEndpoint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Trim Endpoint Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    _ = try runner.execute(
        .setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop]),
        in: session
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let trimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )

    let result = try runner.execute(
        .moveSurfaceTrimEndpoint(
            target: trimReference,
            endpoint: .start,
            u: .scalar(0.25),
            v: .scalar(0.3)
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    #expect(result.message == "Surface trim endpoint moved.")
    #expect(result.commandName == "moveSurfaceTrimEndpoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(try movedLoop.edges[0].startParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.25, v: 0.3),
        tolerance: 1.0e-12
    ))
    #expect(try movedLoop.edges[2].endParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.25, v: 0.3),
        tolerance: 1.0e-12
    ))
}

@Test func automationCanMoveSurfaceTrimControlPoint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Trim Control Point Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    _ = try runner.execute(
        .setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop]),
        in: session
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let trimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )

    let result = try runner.execute(
        .moveSurfaceTrimControlPoint(
            target: trimReference,
            controlPointIndex: 1,
            u: .scalar(0.58),
            v: .scalar(0.46)
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    guard case .bSpline(let movedCurve) = movedLoop.edges[0].parameterCurve else {
        Issue.record("Automation must keep the authored B-spline trim curve.")
        return
    }
    #expect(result.message == "Surface trim control point moved.")
    #expect(result.commandName == "moveSurfaceTrimControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(movedCurve.controlPoints[0] == Point2D(x: 0.2, y: 0.2))
    #expect(movedCurve.controlPoints[1] == Point2D(x: 0.58, y: 0.46))
    #expect(movedCurve.controlPoints[2] == Point2D(x: 0.8, y: 0.25))

    let weightResult = try runner.execute(
        .setSurfaceTrimControlPointWeight(
            target: trimReference,
            controlPointIndex: 1,
            weight: .scalar(2.4)
        ),
        in: session
    )
    let weightedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(weightedSurfaceFeature) = weightedFeature.operation,
          let weightedLoop = weightedSurfaceFeature.trimLoops.first,
          case .bSpline(let weightedCurve) = weightedLoop.edges[0].parameterCurve else {
        Issue.record("Automation must keep the weighted authored B-spline trim curve.")
        return
    }
    #expect(weightResult.message == "Surface trim control point weight updated.")
    #expect(weightResult.commandName == "setSurfaceTrimControlPointWeight")
    #expect(weightResult.didMutate)
    #expect(weightResult.generation == DocumentGeneration(4))
    #expect(weightedCurve.weights == [1.0, 2.4, 1.0])

    let knotResult = try runner.execute(
        .insertSurfaceTrimKnot(
            target: trimReference,
            value: .scalar(0.5)
        ),
        in: session
    )
    let refinedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(refinedSurfaceFeature) = refinedFeature.operation,
          let refinedLoop = refinedSurfaceFeature.trimLoops.first,
          case .bSpline(let refinedCurve) = refinedLoop.edges[0].parameterCurve else {
        Issue.record("Automation must keep the refined authored B-spline trim curve.")
        return
    }
    #expect(knotResult.message == "Surface trim p-curve knot inserted.")
    #expect(knotResult.commandName == "insertSurfaceTrimKnot")
    #expect(knotResult.didMutate)
    #expect(knotResult.generation == DocumentGeneration(5))
    #expect(refinedCurve.knots == [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0])
    #expect(refinedCurve.controlPoints.count == 4)

    let knotValueResult = try runner.execute(
        .setSurfaceTrimKnotValue(
            target: trimReference,
            knotIndex: 3,
            value: .scalar(0.4)
        ),
        in: session
    )
    let retimedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(retimedSurfaceFeature) = retimedFeature.operation,
          let retimedLoop = retimedSurfaceFeature.trimLoops.first,
          case .bSpline(let retimedCurve) = retimedLoop.edges[0].parameterCurve else {
        Issue.record("Automation must keep the retimed authored B-spline trim curve.")
        return
    }
    #expect(knotValueResult.message == "Surface trim p-curve knot value updated.")
    #expect(knotValueResult.commandName == "setSurfaceTrimKnotValue")
    #expect(knotValueResult.didMutate)
    #expect(knotValueResult.generation == DocumentGeneration(6))
    #expect(retimedCurve.knots == [0.0, 0.0, 0.0, 0.4, 1.0, 1.0, 1.0])

    let knotMultiplicityResult = try runner.execute(
        .setSurfaceTrimKnotMultiplicity(
            target: trimReference,
            knotIndex: 3,
            multiplicity: 2
        ),
        in: session
    )
    let saturatedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(saturatedSurfaceFeature) = saturatedFeature.operation,
          let saturatedLoop = saturatedSurfaceFeature.trimLoops.first,
          case .bSpline(let saturatedCurve) = saturatedLoop.edges[0].parameterCurve else {
        Issue.record("Automation must keep the saturated authored B-spline trim curve.")
        return
    }
    #expect(knotMultiplicityResult.message == "Surface trim p-curve knot multiplicity updated.")
    #expect(knotMultiplicityResult.commandName == "setSurfaceTrimKnotMultiplicity")
    #expect(knotMultiplicityResult.didMutate)
    #expect(knotMultiplicityResult.generation == DocumentGeneration(7))
    #expect(saturatedCurve.knots == [0.0, 0.0, 0.0, 0.4, 0.4, 1.0, 1.0, 1.0])
}

@MainActor
@Test func automationCanSplitSurfaceSpan() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let sourceSurface = automationDirectBSplineSurfaceWithInteriorKnots()
    _ = try runner.execute(
        .createBSplineSurface(
            name: "Automation Split Span Surface",
            surface: sourceSurface
        ),
        in: session
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let span = try #require(
        summary.sources.first?.patches.first?.basis.vSpans.first { $0.index == 1 }
    )
    let spanReference = try #require(span.selectionReference)

    let result = try runner.execute(
        .splitSurfaceSpan(
            target: spanReference,
            fraction: .scalar(0.25)
        ),
        in: session
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Automation must keep a direct B-spline surface feature.")
        return
    }
    #expect(result.message == "Surface span split.")
    #expect(result.commandName == "splitSurfaceSpan")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(surfaceFeature.surface.uKnots == sourceSurface.uKnots)
    #expect(surfaceFeature.surface.vKnots == [0.0, 0.0, 0.0, 0.5, 0.625, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vControlPointCount == sourceSurface.vControlPointCount + 1)
}

@MainActor
@Test func automationCanMatchSurfaceBoundaryContinuity() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let referenceResult = try runner.execute(
        .createBSplineSurface(
            name: "Automation Reference Surface Boundary",
            surface: automationDirectBSplineSurface()
        ),
        in: session
    )
    let targetResult = try runner.execute(
        .createBSplineSurface(
            name: "Automation Target Surface Boundary",
            surface: automationOffsetDirectBSplineSurface()
        ),
        in: session
    )
    #expect(referenceResult.didMutate)
    #expect(targetResult.didMutate)
    let featureIDs = session.document.cadDocument.designGraph.order
    let referenceFeatureID = try #require(featureIDs.first)
    let targetFeatureID = try #require(featureIDs.last)
    let referenceTrim = try automationSurfaceTrimReference(
        featureID: referenceFeatureID,
        edgeIndex: 2,
        in: session.document
    )
    let targetTrim = try automationSurfaceTrimReference(
        featureID: targetFeatureID,
        edgeIndex: 0,
        in: session.document
    )

    let result = try runner.execute(
        .matchSurfaceBoundaryContinuity(
            target: targetTrim,
            reference: referenceTrim,
            level: .g1,
            matchSide: .opposite,
            referenceDirection: .forward
        ),
        in: session
    )

    let targetFeature = try #require(session.document.cadDocument.designGraph.nodes[targetFeatureID])
    let referenceFeature = try #require(session.document.cadDocument.designGraph.nodes[referenceFeatureID])
    guard case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation,
          case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
        Issue.record("Automation boundary continuity must keep direct B-spline surface features.")
        return
    }
    #expect(result.message == "Surface boundary continuity matched.")
    #expect(result.commandName == "matchSurfaceBoundaryContinuity")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    let referenceBoundary = referenceSurfaceFeature.surface.controlPoints[3][1]
    let referenceInward = referenceSurfaceFeature.surface.controlPoints[2][1] - referenceBoundary
    #expect(targetSurfaceFeature.surface.controlPoints[0][1].isApproximatelyEqual(
        to: referenceBoundary,
        tolerance: 1.0e-12
    ))
    #expect(targetSurfaceFeature.surface.controlPoints[1][1].isApproximatelyEqual(
        to: referenceBoundary + (-referenceInward),
        tolerance: 1.0e-12
    ))
}

@MainActor
@Test func automationCanCreateSweepSourceFeature() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Automation Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Automation Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let session = EditorSession(document: document)
    let runner = AutomationRunner()

    let result = try runner.execute(
        .createSweep(
            name: "Automation Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions()
        ),
        in: session
    )

    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Automation must create a sweep feature.")
        return
    }
    #expect(result.message == "Sweep Automation Sweep source created.")
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileID))])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(feature.inputs == [
        FeatureInput(featureID: profileID, role: .profile),
        FeatureInput(featureID: pathID, role: .path),
    ])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func automationCanMovePolySplineSurfaceVertex() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createPolySplineSurface(
            name: "Automation Editable Surface",
            sourceMesh: automationPolySplineQuadMesh(),
            options: PolySplineOptions()
        ),
        in: session
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let result = try runner.execute(
        .movePolySplineSurfaceVertex(
            target: target,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(0.0, .millimeter),
            deltaZ: .length(1.0, .millimeter)
        ),
        in: session
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Automation must keep a PolySpline feature.")
        return
    }
    #expect(result.message == "PolySpline surface vertex moved.")
    #expect(result.commandName == "movePolySplineSurfaceVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSlidePolySplineSurfaceVertices() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createPolySplineSurface(
            name: "Automation Slide Surface",
            sourceMesh: automationPolySplineQuadMesh(),
            options: PolySplineOptions()
        ),
        in: session
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMin"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let result = try runner.execute(
        .slidePolySplineSurfaceVertices(
            targets: [target],
            direction: .positiveV,
            distance: .length(1.0, .millimeter)
        ),
        in: session
    )

    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Automation must keep a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(result.message == "PolySpline surface vertices slid.")
    #expect(result.commandName == "slidePolySplineSurfaceVertices")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanOffsetBodyFace() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))

    let result = try runner.execute(
        .offsetBodyFace(
            target: SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceRight)),
            distance: .length(2.0, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body face offset applied.")
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateFaceKnifeFromGeneratedFaceTarget() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Knife Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let startFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let target = try #require(startFaceEntry.selectionTarget())

    let result = try runner.execute(
        .createFaceKnife(
            name: "Automation Face Knife",
            target: target,
            loop: [
                Point3D(x: -0.0015, y: -0.0010, z: 0.0),
                Point3D(x: 0.0015, y: -0.0010, z: 0.0),
                Point3D(x: 0.0015, y: 0.0010, z: 0.0),
                Point3D(x: -0.0015, y: 0.0010, z: 0.0),
            ]
        ),
        in: session
    )

    let faceKnifeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let faceKnifeSceneNodeID = try #require(automationSceneNodeID(for: faceKnifeFeatureID, in: session.document))
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let faceKnifeFaces = afterTopology.entries.filter {
        $0.kind == .face && $0.sceneNodeID == faceKnifeSceneNodeID.description
    }

    #expect(result.message == "Face Knife Automation Face Knife applied.")
    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(faceKnifeFaces.count == 7)
    #expect(faceKnifeFaces.contains {
        $0.generatedRole == "faceKnife" && $0.subshapeRole == "centerFace"
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanDeleteGeneratedBodyFace() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Delete Face Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let startFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let target = try #require(startFaceEntry.selectionTarget())

    let result = try runner.execute(
        .deleteBodyFaces(targets: [target]),
        in: session
    )

    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    #expect(result.message == "Body face deletion applied.")
    #expect(result.commandName == "deleteBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(body.kind == .sheet)
    #expect(afterTopology.counts.faceCount == 5)
    #expect(afterTopology.entries.contains { $0.persistentName == startFaceEntry.persistentName } == false)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanDraftGeneratedBodyFace() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Draft Face Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targetEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "sideFace"
        }
    )
    let neutralEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodyNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let target = try #require(targetEntry.selectionTarget())
    let neutralTarget = try #require(neutralEntry.selectionTarget())

    let result = try runner.execute(
        .draftBodyFaces(
            targets: [target],
            neutralTarget: neutralTarget,
            angle: .angle(12.0, .degree)
        ),
        in: session
    )

    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftSceneNodeID = try #require(automationSceneNodeID(for: draftFeatureID, in: session.document))
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftSceneNodeID.description &&
            $0.generatedRole == "faceDraft"
    }

    #expect(result.message == "Body face draft applied.")
    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(body.kind == .solid)
    #expect(afterTopology.counts.faceCount == 6)
    #expect(draftFaces.count == 6)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanOffsetSketchCurveSymmetrically() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
            vertexHandle: nil
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    #expect(result.message == "Sketch curve offset created.")
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 3)
    #expect(lines.contains { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.y ?? -1.0) + 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) + 0.002) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanOffsetSketchVertex() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createRectangleSketch(
            name: "Automation Offset Vertex Rectangle",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.y ?? -1.0) + 0.003) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) + 0.003) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())

    let result = try runner.execute(
        .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(2.0, .millimeter)
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.message == "Sketch vertex offset created.")
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateSymmetricNaturalOffsetRegions() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createRectangleSketch(
            name: "Automation Symmetric Offset Region",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceRegion = try #require(before.regions.first)
    let target = try #require(sourceRegion.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
            vertexHandle: nil
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegions = after.regions.filter { $0.sourceFeatureID != sourceRegion.sourceFeatureID }
    let areas = offsetRegions.map(\.areaSquareMeters).sorted()
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == before.counts.regionCount + 2)
    #expect(abs((areas.first ?? 0.0) - 0.000_032) < 1.0e-12)
    #expect(abs((areas.last ?? 0.0) - 0.000_096) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateCombinedOffsetRegions() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createRectangleSketch(
            name: "Automation Combined Region A",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        ),
        in: session
    )
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Automation Combined Region B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(-3.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(16.0, .millimeter),
                y: .length(3.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }

    let result = try runner.execute(
        .offsetRegions(
            targets: targets,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .natural),
            combinesRegions: true
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.message == "Combined sketch regions offset created.")
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 4)
    #expect(unionRegion.boundarySegmentCount == 4)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_184) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanDispatchOffsetCurveToOffsetVertex() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createRectangleSketch(
            name: "Automation Offset Curve Vertex Rectangle",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.y ?? -1.0) + 0.003) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) + 0.003) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .lineEnd
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.message == "Sketch vertex offset created.")
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanDispatchOffsetCurveArcEndpointToOffsetVertex() async throws {
    let setup = try automationLineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceArc.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .arcStart
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.message == "Sketch vertex offset created.")
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanDispatchOffsetCurveArcArcEndpointToOffsetVertex() async throws {
    let setup = try automationArcArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.upperArcID.description })
    let target = try #require(sourceArc.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(1.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .arcEnd
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.message == "Sketch vertex offset created.")
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateSlotSketchFromSourceLine() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try runner.execute(
        .createSlotSketch(
            target: target,
            width: .length(3.0, .millimeter)
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Automation Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.message == "Slot sketch profile created.")
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCreateSlotSketchFromOpenLineChain() async throws {
    let runner = AutomationRunner()
    let setup = try automationOpenLineChainSlotDocument(name: "Automation Slot Source Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineIDs[0].description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try runner.execute(
        .createSlotSketch(
            target: target,
            width: .length(2.0, .millimeter)
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Automation Slot Source Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.message == "Slot sketch profile created.")
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResult = try runner.execute(
        .extrudeProfile(
            name: "Automation Extruded Slot Chain",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanCreateSlotSketchFromSourceArcAndExtrudeIt() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())

    let result = try runner.execute(
        .createSlotSketch(
            target: target,
            width: .length(1.0, .millimeter)
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Automation Slot Source Arc Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.message == "Slot sketch profile created.")
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResult = try runner.execute(
        .extrudeProfile(
            name: "Automation Extruded Arc Slot",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanCreateSlotSketchFromOpenLineArcChainAndExtrudeIt() async throws {
    let runner = AutomationRunner()
    let setup = try automationOpenLineArcChainSlotDocument(name: "Automation Slot Source Line Arc Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let result = try runner.execute(
        .createSlotSketch(
            target: target,
            width: .length(2.0, .millimeter)
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Automation Slot Source Line Arc Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.message == "Slot sketch profile created.")
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResult = try runner.execute(
        .extrudeProfile(
            name: "Automation Extruded Line Arc Slot",
            profile: ProfileReference(featureID: slotFeature.id),
            distance: .length(3.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func automationCanActivateSlotModeThroughOffsetCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Offset Slot Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())

    let result = try runner.execute(
        .offsetCurve(
            target: target,
            distance: .length(3.0, .millimeter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Automation Offset Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.message == "Slot sketch profile created.")
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanOffsetCylinderSideFaceThroughGeneratedTopology() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedCircle(
            name: "Automation Editable Cylinder",
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
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeRadius = try automationCylinderRadius(forBody: bodyFeatureID, in: session.document)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let sideFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.surfaceKind == "cylinder"
    })
    let target = try #require(sideFaceEntry.selectionTarget())

    let result = try runner.execute(
        .offsetBodyFace(
            target: target,
            distance: .length(1.5, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body face offset applied.")
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(nearlyEqualAutomation(try automationCylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius + 0.0015))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanChamferBodyEdges() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Chamfer Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))

    let result = try runner.execute(
        .chamferBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftBottom)),
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightBottom)),
            ],
            distance: .length(1.0, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body edge chamfer applied.")
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanFilletBodyEdges() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Fillet Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))

    let result = try runner.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        ),
        in: session
    )

    #expect(result.message == "Body edge fillet applied.")
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanFilletGeneratedEdgeAfterPriorChamfer() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Refillet Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .chamferBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            distance: .length(1.0, .millimeter)
        ),
        in: session
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first(where: isAutomationVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let result = try runner.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(0.25, .millimeter),
            segmentCount: 8
        ),
        in: session
    )

    #expect(result.message == "Body edge fillet applied.")
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanFilletSharpGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Curve Loop Refillet Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        ),
        in: session
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isAutomationVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try runner.execute(
        .filletBodyEdges(
            targets: [target],
            radius: .length(0.5, .millimeter),
            segmentCount: 8
        ),
        in: session
    )

    #expect(result.message == "Body edge fillet applied.")
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanChamferArcAdjacentGeneratedEdgeAfterPriorFillet() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Curve Loop Rechamfer Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        ),
        in: session
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edgeEntry = try #require(topology.entries.first {
        isAutomationVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let result = try runner.execute(
        .chamferBodyEdges(
            targets: [target],
            distance: .length(0.25, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body edge chamfer applied.")
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanMoveBodyVertex() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Vertex Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(8.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let result = try runner.execute(
        .moveBodyVertex(
            target: target,
            deltaX: .length(1.0, .millimeter),
            deltaY: .length(1.0, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body vertex moved.")
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanMoveSharpGeneratedVertexAfterPriorFillet() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangle(
            name: "Automation Curve Loop Vertex Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .filletBodyEdges(
            targets: [
                SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            ],
            radius: .length(1.0, .millimeter),
            segmentCount: 8
        ),
        in: session
    )
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertexEntry = try #require(topology.entries.first {
        isAutomationGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    let result = try runner.execute(
        .moveBodyVertex(
            target: target,
            deltaX: .length(1.0, .millimeter),
            deltaY: .length(0.5, .millimeter)
        ),
        in: session
    )

    #expect(result.message == "Body vertex moved.")
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
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
    let arcResult = try runner.execute(
        .createArcSketch(
            name: "Automation Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        ),
        in: session
    )
    let splineResult = try runner.execute(
        .createSplineSketch(
            name: "Automation Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let polygonResult = try runner.execute(
        .createPolygonSketch(
            name: "Automation Polygon",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(6.0, .millimeter),
            sides: 6,
            sizingMode: .inradius,
            inclinationMode: .horizontal,
            rotationAngle: .angle(0.0, .degree)
        ),
        in: session
    )

    #expect(lineResult.message == "Line sketch Automation Line created.")
    #expect(lineResult.commandName == "createLineSketch")
    #expect(circleResult.message == "Circle sketch Automation Circle created.")
    #expect(circleResult.commandName == "createCircleSketch")
    #expect(arcResult.message == "Arc sketch Automation Arc created.")
    #expect(arcResult.commandName == "createArcSketch")
    #expect(splineResult.message == "Spline sketch Automation Spline created.")
    #expect(splineResult.commandName == "createSplineSketch")
    #expect(polygonResult.message == "Polygon sketch Automation Polygon created.")
    #expect(polygonResult.commandName == "createPolygonSketch")
    #expect(session.document.cadDocument.designGraph.order.count == 5)
    #expect(session.generation == DocumentGeneration(5))
    #expect(session.evaluationStatus == .valid)
    let polygonFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let polygonNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == polygonFeatureID
    })
    #expect(polygonNode.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(polygonNode.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.horizontal.rawValue))
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
@Test func automationCanRemoveSketchConstraint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createLineSketch(
            name: "Automation Constraint Removal Source",
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
    _ = try runner.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        ),
        in: session
    )

    let result = try runner.execute(
        .removeSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: featureID))
    #expect(result.message == "Sketch constraint removed from \(featureID.description).")
    #expect(result.commandName == "removeSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(sketch.constraints.isEmpty)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanEditBridgeCurveParameters() async throws {
    let setup = try automationTwoLineUnequalLengthDocument(name: "Automation Bridge Source")
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()

    let createResult = try runner.execute(
        .createBridgeCurve(
            featureID: setup.featureID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .lineEnd(setup.firstLineID)
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .lineStart(setup.secondLineID)
            ),
            continuity: .g1
        ),
        in: session
    )
    let source = try #require(session.document.productMetadata.bridgeCurveSources.values.first)

    let updateResult = try runner.execute(
        .setBridgeCurveParameters(
            sourceID: source.id,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .entity(setup.firstLineID),
                parameter: .scalar(0.5),
                reversesSense: true
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .entity(setup.secondLineID),
                parameter: .scalar(0.25)
            ),
            continuity: .g1,
            trimsSourceCurves: true
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: setup.featureID))
    let updatedSource = try #require(session.document.productMetadata.bridgeCurveSources[source.id])
    let bridgeEntity = try #require(sketch.entities[source.entityID])
    guard case .spline(let spline) = bridgeEntity else {
        Issue.record("Automation bridge source must keep a generated spline entity.")
        return
    }
    let controlPoints = try spline.controlPoints.map {
        try automationResolvedPoint($0, parameters: session.document.cadDocument.parameters)
    }

    #expect(createResult.commandName == "createBridgeCurve")
    #expect(createResult.generation == DocumentGeneration(1))
    #expect(updateResult.commandName == "setBridgeCurveParameters")
    #expect(updateResult.message == "Bridge curve \(source.id.description) updated.")
    #expect(updateResult.didMutate)
    #expect(updateResult.generation == DocumentGeneration(2))
    #expect(updatedSource.entityID == source.entityID)
    #expect(updatedSource.trimsSourceCurves)
    #expect(updatedSource.firstEndpoint.reference == .lineStart(setup.firstLineID))
    #expect(updatedSource.firstEndpoint.parameter == nil)
    #expect(updatedSource.firstEndpoint.reversesSense == false)
    #expect(updatedSource.secondEndpoint.reference == .lineEnd(setup.secondLineID))
    #expect(updatedSource.secondEndpoint.parameter == nil)
    #expect(updatedSource.continuity == .g1)
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: source.entityID, index: 0),
        .lineStart(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: source.entityID, index: 6),
        .lineEnd(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        spline: source.entityID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        spline: source.entityID,
        endpoint: .end,
        line: setup.secondLineID
    )))
    #expect(controlPoints.count == 7)
    #expect(nearlyEqualAutomation(controlPoints[0].x, 0.0025))
    #expect(nearlyEqualAutomation(controlPoints[0].y, 0.0))
    #expect(nearlyEqualAutomation(controlPoints[1].x, 0.001182384266129633))
    #expect(nearlyEqualAutomation(controlPoints[1].y, 0.0))
    #expect(nearlyEqualAutomation(controlPoints[2].x, 0.0016666666666666668))
    #expect(nearlyEqualAutomation(controlPoints[2].y, 0.0025))
    #expect(nearlyEqualAutomation(controlPoints[3].x, 0.00125))
    #expect(nearlyEqualAutomation(controlPoints[3].y, 0.00375))
    #expect(nearlyEqualAutomation(controlPoints[4].x, 0.0008333333333333334))
    #expect(nearlyEqualAutomation(controlPoints[4].y, 0.005))
    #expect(nearlyEqualAutomation(controlPoints[5].x, 0.0))
    #expect(nearlyEqualAutomation(controlPoints[5].y, 0.008817615733870367))
    #expect(nearlyEqualAutomation(controlPoints[6].x, 0.0))
    #expect(nearlyEqualAutomation(controlPoints[6].y, 0.0075))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanInsertSketchSplineControlPoint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Insert CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(0.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try runner.execute(
        .insertSketchSplineControlPoint(
            target: target,
            fraction: .scalar(0.5)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.message == "Sketch spline control point inserted.")
    #expect(result.commandName == "insertSketchSplineControlPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(updatedSpline.controlPoints.count == 7)
    #expect(abs(updatedSpline.controlPoints[3].x - 0.004) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[3].y - 0.003) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSlideSketchSplineControlPoints() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Slide CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try runner.execute(
        .slideSketchSplineControlPoints(
            target: target,
            controlPointIndexes: [1, 2],
            direction: .normal,
            distance: .length(1.0, .millimeter)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.message == "Sketch spline control points slid.")
    #expect(result.commandName == "slideSketchSplineControlPoints")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.001) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.001) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanRebuildSketchCurveByPointCount() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Rebuild Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(-3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(-3.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try runner.execute(
        .rebuildSketchCurve(
            target: target,
            options: .points(controlPointCount: 4)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.message == "Sketch curve rebuilt.")
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let report = try #require(result.curveRebuildReport)
    #expect(report.method == .points)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanRefitSketchCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Refit Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(-1.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(-1.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try runner.execute(
        .rebuildSketchCurve(
            target: target,
            options: .refit(
                tolerance: .length(20.0, .millimeter),
                keepsCorners: false
            )
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.message == "Sketch curve rebuilt.")
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let report = try #require(result.curveRebuildReport)
    #expect(report.method == .refit)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanExplicitlyRebuildSketchCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Explicit Rebuild Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(-3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(-3.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let result = try runner.execute(
        .rebuildSketchCurve(
            target: target,
            options: .explicitControl(
                degree: 3,
                spanCount: 1,
                weight: 0.5
            )
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.message == "Sketch curve rebuilt.")
    #expect(result.commandName == "rebuildSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddFixedSplineControlPointConstraint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createSplineSketch(
            name: "Automation Fixed Spline Point",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
        ),
        in: session
    )

    #expect(result.message == "Sketch constraint added to \(featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)

    do {
        _ = try runner.execute(
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            in: session
        )
        Issue.record("Automation fixed spline control point move must fail before mutation.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    }
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func automationCanAlignSketchVerticesWithPersistentG0Constraint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let referenceLineID = SketchEntityID()
    let targetLineID = SketchEntityID()
    _ = try runner.execute(
        .createSketch(
            name: "Automation Align Vertex",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    referenceLineID: .line(SketchLine(
                        start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                        end: SketchPoint(x: .length(4.0, .millimeter), y: .length(0.0, .millimeter))
                    )),
                    targetLineID: .line(SketchLine(
                        start: SketchPoint(x: .length(8.0, .millimeter), y: .length(2.0, .millimeter)),
                        end: SketchPoint(x: .length(12.0, .millimeter), y: .length(2.0, .millimeter))
                    )),
                ]
            ),
            geometryRole: .curve
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let referenceLine = try #require(summary.entries.first { $0.entityID == referenceLineID.description })
    let targetLine = try #require(summary.entries.first { $0.entityID == targetLineID.description })

    let result = try runner.execute(
        .alignSketchVertex(
            target: try automationPointHandleSelectionTarget(targetLine, handle: .lineStart),
            reference: try automationPointHandleSelectionTarget(referenceLine, handle: .lineEnd),
            options: SketchVertexAlignmentOptions()
        ),
        in: session
    )

    let featureID = try #require(UUID(uuidString: referenceLine.sourceFeatureID)).featureID
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Automation Align Vertex feature must remain a sketch.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedReferenceLine = try #require(updatedSummary.entries.first { $0.entityID == referenceLineID.description })
    let movedTargetLine = try #require(updatedSummary.entries.first { $0.entityID == targetLineID.description })

    #expect(result.message == "Sketch vertex aligned.")
    #expect(result.commandName == "alignSketchVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((movedTargetLine.start?.x ?? -1.0) - (movedReferenceLine.end?.x ?? -2.0)) < 1.0e-12)
    #expect(abs((movedTargetLine.start?.y ?? -1.0) - (movedReferenceLine.end?.y ?? -2.0)) < 1.0e-12)
    #expect(sketch.constraints.contains(.coincident(.lineEnd(referenceLineID), .lineStart(targetLineID))))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanProjectSketchCurvesToConstructionPlane() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let splineID = SketchEntityID()
    _ = try runner.execute(
        .createSketch(
            name: "Automation Projection Source",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    splineID: .spline(SketchSpline(controlPoints: [
                        SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                        SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                        SketchPoint(x: .length(4.0, .millimeter), y: .length(3.0, .millimeter)),
                        SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                    ])),
                ]
            ),
            geometryRole: .curve
        ),
        in: session
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(before.entries.first { $0.entityID == splineID.description })

    let result = try runner.execute(
        .projectSketchCurvesToConstructionPlane(
            targets: [try #require(spline.selectionTarget())],
            plane: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.020),
                normal: .unitZ
            )),
            name: "Automation Projected Spline"
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(after.entries.first { $0.sourceFeatureName == "Automation Projected Spline" })

    #expect(result.message == "Sketch curves projected.")
    #expect(result.commandName == "projectSketchCurvesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projected.entityKind == "spline")
    #expect(projected.controlPoints.count == 4)
    #expect(abs(projected.controlPoints[3].x - 0.006) < 1.0e-12)
    #expect(abs(projected.controlPoints[3].y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanProjectGeneratedEdgesToConstructionPlane() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangleFromCorners(
            name: "Automation Generated Edge Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFace = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFace.center?.z)
    let edge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.curveKind == "line" &&
            automationTopologyPoint($0.start, isOnDepth: supportDepth) &&
            automationTopologyPoint($0.end, isOnDepth: supportDepth) &&
            $0.selectionTarget() != nil
    })
    let target = try #require(edge.selectionTarget())

    let result = try runner.execute(
        .projectSketchCurvesToConstructionPlane(
            targets: [target],
            plane: .xy,
            name: "Automation Projected Generated Edge"
        ),
        in: session
    )

    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(summary.entries.first {
        $0.sourceFeatureName == "Automation Projected Generated Edge"
    })

    #expect(result.message == "Sketch curves projected.")
    #expect(result.commandName == "projectSketchCurvesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanProjectCurvesToGeneratedFace() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let lineID = SketchEntityID()
    _ = try runner.execute(
        .createSketch(
            name: "Automation Face Projection Source",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    lineID: .line(SketchLine(
                        start: SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                        end: SketchPoint(x: .length(5.0, .millimeter), y: .length(4.0, .millimeter))
                    )),
                ]
            ),
            geometryRole: .curve
        ),
        in: session
    )
    _ = try runner.execute(
        .createExtrudedRectangleFromCorners(
            name: "Automation Face Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(summary.entries.first { $0.entityID == lineID.description })
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let face = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "endFace" &&
            $0.selectionTarget() != nil
    })

    let result = try runner.execute(
        .projectCurvesToGeneratedFace(
            targets: [try #require(sourceLine.selectionTarget())],
            face: try #require(face.selectionTarget()),
            name: "Automation Face Projected Line"
        ),
        in: session
    )

    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(after.entries.first {
        $0.sourceFeatureName == "Automation Face Projected Line"
    })

    #expect(result.message == "Curves projected to generated face.")
    #expect(result.commandName == "projectCurvesToGeneratedFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanProjectBodyOutlinesToConstructionPlane() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createExtrudedRectangleFromCorners(
            name: "Automation Body Outline Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))

    let result = try runner.execute(
        .projectBodyOutlinesToConstructionPlane(
            targets: [SelectionTarget(sceneNodeID: bodyNodeID)],
            plane: .xy,
            name: "Automation Projected Body Outline"
        ),
        in: session
    )

    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projectedEntries = summary.entries.filter {
        $0.sourceFeatureName == "Automation Projected Body Outline"
    }

    #expect(result.message == "Body outlines projected.")
    #expect(result.commandName == "projectBodyOutlinesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projectedEntries.count == 4)
    #expect(projectedEntries.allSatisfy { $0.entityKind == "line" })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddCoincidentSplineControlPointConstraint() async throws {
    let setup = try automationSplinePointConstraintDocument(name: "Automation Coincident Spline Point")
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .coincident(
                .splineControlPoint(entity: setup.splineID, index: 0),
                .entity(setup.pointID)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let point = try #require(summary.entries.first { $0.entityID == setup.pointID.description })
    let center = try #require(point.center)

    #expect(result.message == "Sketch constraint added to \(setup.featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(center.x - 0.0) < 1.0e-12)
    #expect(abs(center.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddSmoothSplineControlPointConstraint() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createSplineSketch(
            name: "Automation Smooth Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .smoothSplineControlPoint(entity: entityID, index: 3)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    let outgoingHandle = try #require(updatedSpline.controlPoints.dropFirst(4).first)
    #expect(result.message == "Sketch constraint added to \(featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(outgoingHandle.x - 0.005) < 1.0e-12)
    #expect(abs(outgoingHandle.y - (-0.001)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddEqualLengthSketchConstraint() async throws {
    let setup = try automationTwoLineUnequalLengthDocument(name: "Automation Equal Length Source")
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .equalLength(setup.firstLineID, setup.secondLineID)
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: setup.featureID))
    let first = try #require(automationLine(setup.firstLineID, in: sketch))
    let second = try #require(automationLine(setup.secondLineID, in: sketch))
    let firstLength = try automationLineLength(first, parameters: session.document.cadDocument.parameters)
    let secondLength = try automationLineLength(second, parameters: session.document.cadDocument.parameters)
    #expect(result.message == "Sketch constraint added to \(setup.featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(sketch.constraints == [.equalLength(setup.firstLineID, setup.secondLineID)])
    #expect(abs(firstLength - secondLength) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddTangentSketchConstraint() async throws {
    let setup = try automationLineCircleTangentDocument(name: "Automation Tangent Source")
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()

    let result = try runner.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .tangent(setup.lineID, setup.circleID)
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: setup.featureID))
    let circle = try #require(automationCircle(setup.circleID, in: sketch))
    let center = try automationResolvedPoint(circle.center, parameters: session.document.cadDocument.parameters)
    let radius = try automationLengthValue(circle.radius, parameters: session.document.cadDocument.parameters)
    #expect(result.message == "Sketch constraint added to \(setup.featureID.description).")
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(sketch.constraints == [.tangent(setup.lineID, setup.circleID)])
    #expect(abs(center.x - 0.005) < 1.0e-12)
    #expect(abs(center.y - radius) < 1.0e-12)
    #expect(abs(radius - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanAddCircularSketchConstraints() async throws {
    let setup = try automationTwoCircleDocument(name: "Automation Circular Constraint Source")
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()

    let concentricResult = try runner.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .concentric(setup.firstCircleID, setup.secondCircleID)
        ),
        in: session
    )
    let radiusResult = try runner.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .equalRadius(setup.firstCircleID, setup.secondCircleID)
        ),
        in: session
    )

    let sketch = try #require(automationSketchFeature(in: session.document, featureID: setup.featureID))
    let first = try #require(automationCircle(setup.firstCircleID, in: sketch))
    let second = try #require(automationCircle(setup.secondCircleID, in: sketch))
    let firstCenter = try automationResolvedPoint(first.center, parameters: session.document.cadDocument.parameters)
    let secondCenter = try automationResolvedPoint(second.center, parameters: session.document.cadDocument.parameters)
    let firstRadius = try automationLengthValue(first.radius, parameters: session.document.cadDocument.parameters)
    let secondRadius = try automationLengthValue(second.radius, parameters: session.document.cadDocument.parameters)
    #expect(concentricResult.commandName == "addSketchConstraint")
    #expect(radiusResult.commandName == "addSketchConstraint")
    #expect(concentricResult.didMutate)
    #expect(radiusResult.didMutate)
    #expect(abs(firstCenter.x - secondCenter.x) < 1.0e-12)
    #expect(abs(firstCenter.y - secondCenter.y) < 1.0e-12)
    #expect(abs(firstRadius - secondRadius) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanEditSketchEntityParameters() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Editable Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let result = try runner.execute(
        .setSketchArcParameters(
            target: target,
            center: nil,
            radius: .length(6.0, .millimeter),
            startAngle: nil,
            endAngle: .angle(135.0, .degree)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityKind == "arc" })
    #expect(result.message == "Sketch arc parameters updated.")
    #expect(result.commandName == "setSketchArcParameters")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi * 0.75)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSetSketchEntityDimension() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Dimensioned Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .length,
            value: .length(25.0, .millimeter)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.message == "Sketch entity dimension updated.")
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSetSketchArcAngleDimension() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Angle Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let result = try runner.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(120.0, .degree)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.message == "Sketch entity dimension updated.")
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (130.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSetFixedEndSketchArcAngleDimension() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Fixed End Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())
    let featureID = try #require(UUID(uuidString: arc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: arc.entityID)).sketchEntityID
    _ = try runner.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        ),
        in: session
    )

    let result = try runner.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(120.0, .degree)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.message == "Sketch entity dimension updated.")
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (-40.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSetSketchLineAngleDimension() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Angled Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .setSketchEntityDimension(
            target: target,
            kind: .angle,
            value: .angle(90.0, .degree)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.message == "Sketch entity dimension updated.")
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanConvertSketchLineToArc() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .convertSketchLineToArc(
            target: target,
            sagitta: .length(2.0, .millimeter)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.message == "Sketch line converted to an arc.")
    #expect(result.commandName == "convertSketchLineToArc")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arc.entityKind == "arc")
    #expect(abs((arc.radius ?? -1.0) - 0.00725) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanConvertSketchLineToSpline() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Spline Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .convertSketchLineToSpline(target: target),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.message == "Sketch line converted to a spline.")
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(spline.entityKind == "spline")
    #expect(spline.controlPoints.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanReverseSketchCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Reverse Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .reverseSketchCurve(target: target),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.message == "Sketch curve direction reversed.")
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((reversedLine.start?.x ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanExtendSketchCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Extend Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try automationPointHandleSelectionTarget(line, handle: .lineEnd)

    let result = try runner.execute(
        .extendSketchCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            shape: .natural
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.message == "Sketch curve extended.")
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((extendedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((extendedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanApplySketchCornerTreatment() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Automation Source Fillet Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(automationBottomRectangleLine(in: summary))
    let target = try automationPointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let result = try runner.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(2.0, .millimeter),
            treatment: .fillet
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc" }
    let filletArc = try #require(arcs.first)
    #expect(result.message == "Sketch corner fillet applied.")
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 1)
    #expect(abs((filletArc.center?.x ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((filletArc.center?.y ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((filletArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanApplySketchCornerTreatmentToLineArcCorner() async throws {
    let setup = try automationLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try automationPointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let result = try runner.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: nil,
            distance: .length(0.001, .meter),
            treatment: .fillet
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArc = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.message == "Sketch corner fillet applied.")
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArc.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanApplySketchCornerTreatmentToCurvePair() async throws {
    let setup = try automationLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    let runner = AutomationRunner()
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceLine.selectionTarget())
    let adjacentTarget = try #require(sourceArc.selectionTarget())

    let result = try runner.execute(
        .applySketchCornerTreatment(
            target: target,
            adjacentTarget: adjacentTarget,
            distance: .length(0.001, .meter),
            treatment: .fillet
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.message == "Sketch corner fillet applied.")
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArcAfter.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArcAfter.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSplitSketchCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let result = try runner.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.25)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.message == "Sketch curve segment split.")
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.008) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanSplitSketchArcCurve() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Split Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(120.0, .degree)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let result = try runner.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.5)
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter { $0.entityKind == "arc" }
    #expect(result.message == "Sketch curve segment split.")
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanTrimSketchCurveSegment() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Trim Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    _ = try runner.execute(
        .splitSketchCurve(
            target: target,
            fraction: .scalar(0.25)
        ),
        in: session
    )
    let splitSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let trimmedLine = try #require(splitSummary.entries.first { entry in
        entry.entityKind == "line" && entry.entityID != line.entityID
    })
    let trimmedTarget = try #require(trimmedLine.selectionTarget())

    let result = try runner.execute(
        .trimSketchCurveSegment(target: trimmedTarget),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.message == "Sketch curve segment trimmed.")
    #expect(result.commandName == "trimSketchCurveSegment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(lines.count == 1)
    #expect(lines.first?.entityID == line.entityID)
    #expect(abs((lines.first?.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((lines.first?.end?.x ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCutSketchCurveWithLineCutter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try runner.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Automation Cut Target" }
    #expect(result.message == "Cut Curve applied.")
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.008) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCutSketchCurveWithCircleCutter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Circle Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        ),
        in: session
    )
    _ = try runner.execute(
        .createCircleSketch(
            name: "Automation Circle Cut Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(4.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(1.0, .millimeter)
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Circle Cut Target" })
    let cutterCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Circle Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let result = try runner.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Automation Circle Cut Target" }
    #expect(result.message == "Cut Curve applied.")
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 3)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.005) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.005) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.008) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCutSketchCircleTargetWithLineCutter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createCircleSketch(
            name: "Automation Circle Target Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        ),
        in: session
    )
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Circle Target Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Circle Target Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Circle Target Cut Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try runner.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Automation Circle Target Cut Target" }
    #expect(result.message == "Cut Curve applied.")
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func automationCanCutSketchArcCurveWithLineCutter() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try runner.execute(
        .createArcSketch(
            name: "Automation Arc Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        ),
        in: session
    )
    _ = try runner.execute(
        .createLineSketch(
            name: "Automation Arc Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        ),
        in: session
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetArc = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Arc Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Automation Arc Cut Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let result = try runner.execute(
        .cutSketchCurve(
            target: target,
            cutter: cutter,
            options: CutCurveOptions()
        ),
        in: session
    )

    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Automation Arc Cut Target" }
    #expect(result.message == "Cut Curve applied.")
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi) < 1.0e-12
    })
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
@Test func automationCanCreateRectangularPatternArray() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .createComponentDefinition(
            name: "Automation Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        ),
        in: session
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try runner.execute(
        .createPatternArray(
            name: "Automation Rectangular Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(5.0, .millimeter),
                    copyCount: 2,
                    distanceMode: .spacing
                )
            )),
            outputMode: .componentInstance
        ),
        in: session
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first)

    #expect(result.commandName == "createPatternArray")
    #expect(result.message == "Pattern array Automation Rectangular Array created.")
    #expect(result.didMutate)
    #expect(source.outputInstanceIDs.count == 2)
    #expect(session.document.productMetadata.componentInstances.count == 2)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func automationCanCreateRadialPatternArray() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .createComponentDefinition(
            name: "Automation Radial Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        ),
        in: session
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try runner.execute(
        .createPatternArray(
            name: "Automation Radial Array",
            definitionID: definition.id,
            distribution: .radial(
                RadialPatternArray(
                    angularAxis: PatternArrayAngularAxis(
                        center: .origin,
                        axis: .unitZ,
                        angle: .angle(120.0, .degree),
                        copyCount: 2,
                        angleMode: .spacing
                    )
                )
            ),
            outputMode: .componentInstance
        ),
        in: session
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Automation Radial Array"
    })

    #expect(result.commandName == "createPatternArray")
    #expect(result.message == "Pattern array Automation Radial Array created.")
    #expect(result.didMutate)
    #expect(source.outputInstanceIDs.count == 2)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func automationCanCreateCurvePatternArray() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .createComponentDefinition(
            name: "Automation Curve Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        ),
        in: session
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try runner.execute(
        .createPatternArray(
            name: "Automation Curve Array",
            definitionID: definition.id,
            distribution: .curve(
                CurvePatternArray(
                    path: .polyline(
                        points: [
                            .origin,
                            Point3D(x: 0.03, y: 0.0, z: 0.0),
                        ],
                        normal: .unitZ
                    ),
                    copyCount: 3,
                    alignment: .parallel
                )
            ),
            outputMode: .componentInstance
        ),
        in: session
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Automation Curve Array"
    })

    #expect(result.commandName == "createPatternArray")
    #expect(result.message == "Pattern array Automation Curve Array created.")
    #expect(result.didMutate)
    #expect(source.outputInstanceIDs.count == 3)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func automationCanUpdateAndExplodePatternArray() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(automationSceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try runner.execute(
        .createComponentDefinition(
            name: "Automation Lifecycle Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        ),
        in: session
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    _ = try runner.execute(
        .createPatternArray(
            name: "Automation Lifecycle Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(5.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        ),
        in: session
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Automation Lifecycle Array"
    })
    let firstOutputID = try #require(source.outputInstanceIDs.first)

    let updateResult = try runner.execute(
        .updatePatternArray(
            id: source.id,
            name: "Automation Updated Array",
            definitionID: nil,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: nil
        ),
        in: session
    )
    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])

    let explodeResult = try runner.execute(
        .explodePatternArray(id: source.id),
        in: session
    )
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let outputFeatureID = try #require(
        automationFeatureID(
            inSceneSubtreeRootedAt: outputSceneNodeID,
            document: session.document
        )
    )

    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updateResult.message == "Pattern array updated.")
    #expect(updatedSource.name == "Automation Updated Array")
    #expect(updatedSource.outputInstanceIDs == [firstOutputID])
    #expect(explodeResult.commandName == "explodePatternArray")
    #expect(explodeResult.message == "Pattern array exploded.")
    #expect(session.document.productMetadata.patternArrays[source.id] == nil)
    #expect(session.document.productMetadata.componentInstances[firstOutputID] == nil)
    #expect(session.document.cadDocument.designGraph.nodes[outputFeatureID] != nil)
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
@Test func automationCanCreateDescribeAndActivateConstructionPlanes() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()

    let createResult = try runner.execute(
        .createConstructionPlane(
            name: "Automation CPlane",
            plane: .zx,
            activates: true
        ),
        in: session
    )
    let activeID = try #require(session.document.productMetadata.activeConstructionPlaneID)
    let renameResult = try runner.execute(
        .renameConstructionPlane(
            id: activeID,
            name: "Renamed CPlane"
        ),
        in: session
    )
    let summaryResult = try runner.execute(.describeConstructionPlanes, in: session)
    let clearResult = try runner.execute(
        .setActiveConstructionPlane(id: nil),
        in: session
    )

    #expect(createResult.message == "Construction plane Automation CPlane created.")
    #expect(createResult.commandName == "createConstructionPlane")
    #expect(createResult.didMutate)
    #expect(renameResult.message == "Construction plane renamed to Renamed CPlane.")
    #expect(renameResult.commandName == "renameConstructionPlane")
    #expect(renameResult.didMutate)
    #expect(summaryResult.message == "1 construction plane(s). Active: Renamed CPlane.")
    #expect(summaryResult.commandName == nil)
    #expect(!summaryResult.didMutate)
    #expect(session.document.productMetadata.constructionPlanes[activeID]?.plane == .zx)
    #expect(session.document.productMetadata.constructionPlanes[activeID]?.name == "Renamed CPlane")
    #expect(session.document.productMetadata.activeConstructionPlaneID == nil)
    #expect(clearResult.message == "Active construction plane set to none.")
    #expect(clearResult.commandName == "setActiveConstructionPlane")
    #expect(clearResult.didMutate)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func automationCreatesViewAlignedConstructionPlane() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    let origin = Point3D(x: 0.010, y: 0.020, z: 0.030)

    let result = try runner.execute(
        .createViewAlignedConstructionPlane(
            name: "Automation View Plane",
            origin: origin,
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 2.0),
            activates: true
        ),
        in: session
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.message == "View-aligned construction plane Automation View Plane created.")
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    guard case .plane(let plane) = source.plane else {
        Issue.record("View-aligned construction plane should create a custom plane.")
        return
    }
    #expect(plane.origin == origin)
    #expect(plane.normal == .unitZ)
}

@MainActor
@Test func automationCreatesConstructionPlaneFromGeneratedFaceTarget() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceTarget = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil
    }?.selectionTarget())

    let result = try runner.execute(
        .createConstructionPlaneFromTarget(
            name: "Automation Face CPlane",
            target: faceTarget,
            activates: true
        ),
        in: session
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.message.contains("Automation Face CPlane"))
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)
    #expect(source.name == "Automation Face CPlane")
    guard case .plane = source.plane else {
        Issue.record("Generated face target should create a custom construction plane.")
        return
    }
}

@MainActor
@Test func automationCreatesMidplaneConstructionPlaneFromGeneratedFaceTargets() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try automationParallelFaceTargets(in: topology)

    let result = try runner.execute(
        .createConstructionPlaneFromTargets(
            name: "Automation Midplane",
            targets: targets,
            viewNormal: nil,
            activates: true
        ),
        in: session
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.message == "Construction plane Automation Midplane created from 2 targets.")
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    #expect(source.name == "Automation Midplane")
    guard case .plane = source.plane else {
        Issue.record("Parallel generated face targets should create a custom midplane.")
        return
    }
}

@MainActor
@Test func automationCreatesTwoPointConstructionPlaneFromGeneratedVertexTargets() async throws {
    let session = EditorSession()
    let runner = AutomationRunner()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try automationTwoPointVertexTargets(in: topology, viewNormal: .unitZ)

    let result = try runner.execute(
        .createConstructionPlaneFromTargets(
            name: "Automation Two Point Plane",
            targets: targets,
            viewNormal: .unitZ,
            activates: true
        ),
        in: session
    )

    let source = try #require(session.activeConstructionPlane)
    #expect(result.message == "Construction plane Automation Two Point Plane created from 2 targets.")
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    #expect(source.name == "Automation Two Point Plane")
}

@MainActor
@Test func automationCreatesTwoPointConstructionPlaneFromSourcePointTargets() async throws {
    let runner = AutomationRunner()
    let setup = try automationSourcePointSession()

    let result = try runner.execute(
        .createConstructionPlaneFromTargets(
            name: "Automation Source Point Plane",
            targets: setup.targets,
            viewNormal: .unitZ,
            activates: true
        ),
        in: setup.session
    )

    let source = try #require(setup.session.activeConstructionPlane)
    #expect(result.message == "Construction plane Automation Source Point Plane created from 2 targets.")
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)
    #expect(source.name == "Automation Source Point Plane")
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

private func automationParallelFaceTargets(
    in topology: TopologySummaryResult
) throws -> [SelectionTarget] {
    let faces = topology.entries.filter { $0.kind == .face }
    for firstIndex in faces.indices {
        let first = faces[firstIndex]
        guard let firstCenter = first.center,
              let firstNormal = first.normal,
              let firstTarget = first.selectionTarget() else {
            continue
        }
        let firstNormalVector = try automationVector(firstNormal).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormal = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormalVector = try automationVector(secondNormal).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormalVector.dot(secondNormalVector)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let centerDelta = automationPoint3D(secondCenter) - automationPoint3D(firstCenter)
            guard abs(centerDelta.dot(firstNormalVector)) > 1.0e-9 else {
                continue
            }
            return [firstTarget, secondTarget]
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Automation construction-plane test requires parallel generated faces."
    )
}

private func automationTwoPointVertexTargets(
    in topology: TopologySummaryResult,
    viewNormal: Vector3D
) throws -> [SelectionTarget] {
    let vertices = topology.entries.compactMap { entry -> (target: SelectionTarget, point: Point3D)? in
        guard entry.kind == .vertex,
              let target = entry.selectionTarget(),
              let point = entry.start else {
            return nil
        }
        return (target, automationPoint3D(point))
    }
    let unitViewNormal = try viewNormal.normalized(tolerance: 1.0e-12)
    for firstIndex in vertices.indices {
        for second in vertices.dropFirst(firstIndex + 1) {
            let first = vertices[firstIndex]
            do {
                let direction = try (second.point - first.point).normalized(tolerance: 1.0e-12)
                let projectedNormal = unitViewNormal - direction * unitViewNormal.dot(direction)
                _ = try projectedNormal.normalized(tolerance: 1.0e-12)
                return [first.target, second.target]
            } catch {
                continue
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Automation construction-plane test requires two generated vertex targets compatible with the view normal."
    )
}

private func automationSourcePointSession() throws -> (
    session: EditorSession,
    targets: [SelectionTarget]
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Automation Source Point CPlane Seeds",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    let firstID = SketchEntityID()
    let secondID = SketchEntityID()
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation source point construction-plane test requires a sketch feature."
        )
    }
    sketch.entities = [
        firstID: .point(SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter))),
        secondID: .point(SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entries = summary.entries.filter { $0.entityKind == "point" }
    #expect(entries.count == 2)
    let targets = try entries.map { entry in
        try #require(entry.selectionTarget())
    }
    return (EditorSession(document: document), targets)
}

private func automationVector(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
}

private func automationPoint3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
}

private func automationTwoLineUnequalLengthDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.005, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation two line setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.005, .meter)
            ),
            end: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.015, .meter)
            )
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func automationOpenLineChainSlotDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineIDs: [SketchEntityID]
) {
    let points = [
        SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter)),
        SketchPoint(x: .length(0.010, .meter), y: .length(0.006, .meter)),
    ]
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation line-chain Slot setup requires a source line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    let lineIDs = [firstLineID, secondLineID]
    sketch.entities = [
        firstLineID: .line(SketchLine(start: points[0], end: points[1])),
        secondLineID: .line(SketchLine(start: points[1], end: points[2])),
    ]
    sketch.constraints = [
        .coincident(.lineEnd(firstLineID), .lineStart(secondLineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineIDs)
}

private func automationOpenLineArcChainSlotDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation line-arc Slot setup requires a source line sketch."
        )
    }
    let arcID = SketchEntityID()
    sketch.entities = [
        lineID: .line(SketchLine(
            start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            end: SketchPoint(x: .length(0.010, .meter), y: .length(0.0, .meter))
        )),
        arcID: .arc(SketchArc(
            center: SketchPoint(x: .length(0.010, .meter), y: .length(0.005, .meter)),
            radius: .length(0.005, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )),
    ]
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID)
}

private func automationLineArcCornerTreatmentSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID,
    diagonalID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Automation Corner Treatment Line Arc Profile",
        plane: .xy,
        start: automationSketchPoint(x: 0.0, y: 0.0),
        end: automationSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation line arc corner treatment setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: automationSketchPoint(x: 0.005, y: 0.0),
            radius: .length(0.005, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    sketch.entities[diagonalID] = .line(
        SketchLine(
            start: automationSketchPoint(x: 0.005, y: 0.005),
            end: automationSketchPoint(x: 0.0, y: 0.0025)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: automationSketchPoint(x: 0.0, y: 0.0025),
            end: automationSketchPoint(x: 0.0, y: 0.0)
        )
    )
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
        .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
        .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
        .coincident(.lineEnd(leftID), .lineStart(lineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID, diagonalID)
}

private func automationLine(
    _ entityID: SketchEntityID,
    in sketch: Sketch
) -> SketchLine? {
    guard case let .line(line) = sketch.entities[entityID] else {
        return nil
    }
    return line
}

private func automationCircle(
    _ entityID: SketchEntityID,
    in sketch: Sketch
) -> SketchCircle? {
    guard case let .circle(circle) = sketch.entities[entityID] else {
        return nil
    }
    return circle
}

private func automationLineArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Automation Offset Vertex Line Arc Profile",
        plane: .xy,
        start: automationSketchPoint(x: 0.0, y: 0.0),
        end: automationSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation line arc offset vertex setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: automationSketchPoint(x: 0.010, y: 0.002),
            radius: .length(0.002, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )
    )
    sketch.entities[topID] = .line(
        SketchLine(
            start: automationSketchPoint(x: 0.012, y: 0.002),
            end: automationSketchPoint(x: 0.0, y: 0.002)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: automationSketchPoint(x: 0.0, y: 0.002),
            end: automationSketchPoint(x: 0.0, y: 0.0)
        )
    )
    sketch.constraints = [
        .coincident(.lineEnd(lineID), .arcStart(arcID)),
        .coincident(.arcEnd(arcID), .lineStart(topID)),
        .coincident(.lineEnd(topID), .lineStart(leftID)),
        .coincident(.lineEnd(leftID), .lineStart(lineID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID)
}

private func automationArcArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    upperArcID: SketchEntityID,
    lowerArcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Automation Offset Vertex Arc Arc Profile",
        plane: .xy,
        center: automationSketchPoint(x: 0.005, y: 0.005),
        radius: .length(0.002, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi, .radian)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let upperArcID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation arc arc offset vertex setup requires an arc sketch."
        )
    }
    let lowerArcID = SketchEntityID()
    sketch.entities[lowerArcID] = .arc(
        SketchArc(
            center: automationSketchPoint(x: 0.005, y: 0.005),
            radius: .length(0.002, .meter),
            startAngle: .angle(Double.pi, .radian),
            endAngle: .angle(Double.pi * 2.0, .radian)
        )
    )
    sketch.constraints = [
        .coincident(.arcEnd(upperArcID), .arcStart(lowerArcID)),
        .coincident(.arcEnd(lowerArcID), .arcStart(upperArcID)),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, upperArcID, lowerArcID)
}

private func automationSketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func automationLineCircleTangentDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    circleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.010, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation line circle tangent setup requires a line sketch."
        )
    }
    let circleID = SketchEntityID()
    sketch.entities[circleID] = .circle(
        SketchCircle(
            center: SketchPoint(
                x: .length(0.005, .meter),
                y: .length(0.006, .meter)
            ),
            radius: .length(0.002, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, circleID)
}

private func automationSplinePointConstraintDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    splineID: SketchEntityID,
    pointID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            SketchPoint(x: .length(0.002, .meter), y: .length(0.003, .meter)),
            SketchPoint(x: .length(0.006, .meter), y: .length(0.003, .meter)),
            SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation spline point constraint setup requires a spline sketch."
        )
    }
    let pointID = SketchEntityID()
    sketch.entities[pointID] = .point(
        SketchPoint(x: .length(0.004, .meter), y: .length(0.002, .meter))
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, pointID)
}

private func automationTwoCircleDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstCircleID: SketchEntityID,
    secondCircleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: name,
        plane: .xy,
        center: SketchPoint(
            x: .length(0.002, .meter),
            y: .length(0.003, .meter)
        ),
        radius: .length(0.004, .meter)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstCircleID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation two circle setup requires a circle sketch."
        )
    }
    let secondCircleID = SketchEntityID()
    sketch.entities[secondCircleID] = .circle(
        SketchCircle(
            center: SketchPoint(
                x: .length(0.010, .meter),
                y: .length(0.011, .meter)
            ),
            radius: .length(0.001, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstCircleID, secondCircleID)
}

private func automationLineLength(
    _ line: SketchLine,
    parameters: ParameterTable
) throws -> Double {
    let start = try automationResolvedPoint(line.start, parameters: parameters)
    let end = try automationResolvedPoint(line.end, parameters: parameters)
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return (deltaX * deltaX + deltaY * deltaY).squareRoot()
}

private func automationResolvedPoint(
    _ point: SketchPoint,
    parameters: ParameterTable
) throws -> Point2D {
    let x = try automationLengthValue(point.x, parameters: parameters)
    let y = try automationLengthValue(point.y, parameters: parameters)
    return Point2D(x: x, y: y)
}

private func automationLengthValue(
    _ expression: CADExpression,
    parameters: ParameterTable
) throws -> Double {
    let quantity = try parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func automationSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func automationFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> FeatureID? {
    guard let sceneNode = document.productMetadata.sceneNodes[rootSceneNodeID] else {
        return nil
    }
    if let featureID = sceneNode.reference?.featureID {
        return featureID
    }
    for childID in sceneNode.childIDs {
        if let featureID = automationFeatureID(
            inSceneSubtreeRootedAt: childID,
            document: document
        ) {
            return featureID
        }
    }
    return nil
}

private func automationSketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

private func automationPointHandleSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    handle: SketchEntityPointHandle
) throws -> SelectionTarget {
    let sceneNodeID = try #require(entry.sceneNodeID.flatMap(UUID.init(uuidString:)))
    let handleEntry = try #require(entry.pointHandles.first { $0.handle == handle })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeID),
        component: .sketchEntity(SelectionComponentID(rawValue: handleEntry.selectionComponentID))
    )
}

private func automationBottomRectangleLine(
    in summary: SketchEntitySummaryResult
) -> SketchEntitySummaryResult.EntityEntry? {
    summary.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    }
}

private func automationPolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func automationDirectBSplineSurfaceWithInteriorKnots() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: base.controlPoints,
        weights: base.weights
    )
}

private func automationDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func automationOffsetDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.002),
        bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
        topRight: Point3D(x: 0.02, y: 0.06, z: 0.001),
        topLeft: Point3D(x: 0.0, y: 0.06, z: 0.003)
    )
}

private func automationSurfaceTrimReference(
    featureID: FeatureID,
    edgeIndex: Int,
    in document: DesignDocument
) throws -> SelectionReference {
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first { $0.featureID == featureID.description })
    let trimLoop = try #require(source.patches.first?.trimLoops.first)
    guard trimLoop.selectionReferences.indices.contains(edgeIndex) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation surface trim reference is missing."
        )
    }
    return trimLoop.selectionReferences[edgeIndex]
}

private func automationCylinderRadius(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Automation cylinder radius setup requires an extruded circle body."
        )
    }
    for entity in sketch.entities.values {
        guard case .circle(let circle) = entity else {
            continue
        }
        return try automationLengthValue(circle.radius, parameters: document.cadDocument.parameters)
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Automation cylinder radius setup requires a circle profile."
    )
}

private func nearlyEqualAutomation(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func isAutomationVerticalGeneratedEdge(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard entry.kind == .edge,
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(start.x - end.x) <= tolerance
        && abs(start.y - end.y) <= tolerance
        && abs(start.z - end.z) > tolerance
}

private func isAutomationVerticalGeneratedEdge(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard isAutomationVerticalGeneratedEdge(entry),
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(((start.x + end.x) / 2.0) - x) <= tolerance
        && abs(((start.y + end.y) / 2.0) - y) <= tolerance
}

private func automationTopologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

private func isAutomationGeneratedVertex(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard entry.kind == .vertex,
          let point = entry.start else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(point.x - x) <= tolerance
        && abs(point.y - y) <= tolerance
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

private extension UUID {
    var featureID: FeatureID {
        FeatureID(self)
    }

    var sketchEntityID: SketchEntityID {
        SketchEntityID(self)
    }
}

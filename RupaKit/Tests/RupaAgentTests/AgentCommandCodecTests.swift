import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentMessageCodecRoundTripsCommandRequestAndResponse() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .renameDocument(name: "Encoded"),
        expectedGeneration: DocumentGeneration(3)
    )
    let response = AgentResponse.command(
        AutomationResult(
            message: "Encoded",
            commandName: "renameDocument",
            generation: DocumentGeneration(4),
            didMutate: true
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

@Test func agentMessageCodecRoundTripsArcSketchCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createArcSketch(
            name: "Encoded Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            radius: .length(3.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsExtrudeDistanceCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .setExtrudeDistance(
            featureID: FeatureID(),
            distance: .length(11.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsSweepEvaluationPlan() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let request = AgentRequest.sweepEvaluationPlan(
        sessionID: sessionID,
        sections: [.profile(ProfileReference(featureID: profileFeatureID))],
        path: SweepPathReference(featureID: pathFeatureID),
        guides: [],
        targets: [],
        options: SweepOptions(alignment: .parallel),
        expectedGeneration: DocumentGeneration(5)
    )
    let response = AgentResponse.sweepEvaluationPlan(
        SweepEvaluationPlanResult(
            status: .supported,
            sectionCount: 1,
            pathSegmentCount: 1,
            guideCount: 0,
            targetCount: 0,
            pathShape: .straight(profileNormalComponent: 1.0),
            sectionState: .identity,
            evaluationKind: .exactStraightExtrude,
            outputTopologyKind: .exactStraightSolid,
            booleanSupportKind: .newBody,
            guideStrategies: [.none],
            unsupportedCode: nil,
            message: "Sweep can evaluate as a profile-plane-preserving exact straight extrusion.",
            checks: [
                SweepEvaluationPreflightCheck(
                    kind: .capabilityDecision,
                    status: .passed,
                    message: "Sweep can evaluate as a profile-plane-preserving exact straight extrusion."
                ),
            ]
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

@Test func agentMessageCodecRoundTripsDirectBodyDimensionCommands() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let cubeRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setCubeDimensions(
            featureID: FeatureID(),
            sizeX: .length(16.0, .millimeter),
            sizeY: .length(9.0, .millimeter),
            sizeZ: .length(12.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let cylinderRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setCylinderDimensions(
            featureID: FeatureID(),
            radius: .length(7.0, .millimeter),
            sizeY: .length(13.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedCubeRequest = try codec.decodeRequest(from: try codec.encode(cubeRequest))
    let decodedCylinderRequest = try codec.decodeRequest(from: try codec.encode(cylinderRequest))

    #expect(decodedCubeRequest == cubeRequest)
    #expect(decodedCylinderRequest == cylinderRequest)
}

@Test func agentMessageCodecRoundTripsPatternArrayCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createPatternArray(
            name: "Encoded Rectangular Array",
            definitionID: ComponentDefinitionID(),
            distribution: .rectangular(
                RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(8.0, .millimeter),
                        copyCount: 4,
                        distanceMode: .spacing
                    ),
                    secondAxis: PatternArrayLinearAxis(
                        direction: .unitY,
                        distance: .length(40.0, .millimeter),
                        copyCount: 2,
                        distanceMode: .extent
                    )
                )
            ),
            outputMode: .componentInstance
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsPatternArrayLifecycleCommands() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let sourceID = PatternArraySourceID()
    let updateRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .updatePatternArray(
            id: sourceID,
            name: "Encoded Updated Array",
            definitionID: nil,
            distribution: .rectangular(
                RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(12.0, .millimeter),
                        copyCount: 2
                    )
                )
            ),
            outputMode: nil
        ),
        expectedGeneration: DocumentGeneration(6)
    )
    let explodeRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .explodePatternArray(id: sourceID),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedUpdateRequest = try codec.decodeRequest(from: try codec.encode(updateRequest))
    let decodedExplodeRequest = try codec.decodeRequest(from: try codec.encode(explodeRequest))

    #expect(decodedUpdateRequest == updateRequest)
    #expect(decodedExplodeRequest == explodeRequest)
}

@Test func agentMessageCodecRoundTripsOffsetCurveCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(),
            vertexHandle: .lineEnd
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsProjectSketchCurvesCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .projectSketchCurvesToConstructionPlane(
            targets: [target],
            plane: .xy,
            name: "Projected Curves"
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsProjectCurvesToGeneratedFaceCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let face = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .face(
            SelectionComponentID.generatedTopology(
                "face-1"
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .projectCurvesToGeneratedFace(
            targets: [target],
            face: face,
            name: "Projected Face Curves"
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsProjectBodyOutlinesCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(sceneNodeID: SceneNodeID())
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .projectBodyOutlinesToConstructionPlane(
            targets: [target],
            plane: .xy,
            name: "Projected Body Outline"
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsCurveCurvatureDisplayCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .setCurveCurvatureDisplay(
            target: target,
            isVisible: true,
            combScale: 0.2
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsPointDisplayCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .setPointDisplay(
            target: target,
            isVisible: false
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsOffsetCurveSlotModeCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(mode: .slot),
            vertexHandle: nil
        ),
        expectedGeneration: DocumentGeneration(7)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsOffsetSketchVertexCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .offsetSketchVertex(
            target: target,
            handle: .lineEnd,
            distance: .length(2.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(8)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsSketchCornerTreatmentCurvePairCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let featureID = FeatureID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: featureID,
                entityID: SketchEntityID()
            )
        )
    )
    let adjacentTarget = SelectionTarget(
        sceneNodeID: target.sceneNodeID,
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: featureID,
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .applySketchCornerTreatment(
            target: target,
            adjacentTarget: adjacentTarget,
            distance: .length(2.0, .millimeter),
            treatment: .fillet
        ),
        expectedGeneration: DocumentGeneration(8)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsSlotSketchCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(
            SelectionComponentID.sketchEntity(
                featureID: FeatureID(),
                entityID: SketchEntityID()
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createSlotSketch(
            target: target,
            width: .length(4.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(9)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsBridgeCurveCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let featureID = FeatureID()
    let firstLineID = SketchEntityID()
    let secondLineID = SketchEntityID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .entity(firstLineID),
                parameter: .scalar(0.5),
                reversesSense: true
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .entity(secondLineID),
                parameter: .scalar(0.25)
            ),
            continuity: .g0,
            trimsSourceCurves: true
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsSweepCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let profileID = FeatureID()
    let pathID = FeatureID()
    let guideID = FeatureID()
    let targetID = FeatureID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createSweep(
            name: "Encoded Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [SweepGuideReference(featureID: guideID)],
            targets: [SweepTargetReference(featureID: targetID)],
            options: SweepOptions(
                twistAngle: .angle(45.0, .degree),
                endScale: .constant(.scalar(0.75)),
                alignment: .normal,
                distanceFraction: .constant(.scalar(0.8)),
                cornerStyle: .mitre,
                guideMethod: .curve,
                booleanOperation: .union,
                keepTools: false,
                simplify: false,
                resultKind: .solid
            )
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsPolySplineCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createPolySplineSurface(
            name: "Encoded PolySpline",
            sourceMesh: agentPolySplineQuadMesh(),
            options: PolySplineOptions(
                roundedCorners: false,
                mergePatches: true,
                interpolateBoundaryExactly: true
            )
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsDirectBSplineSurfaceCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .createBSplineSurface(
            name: "Encoded B-spline Surface",
            surface: agentDirectBSplineSurface()
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsPolySplineSurfaceVertexMoveCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .vertex(
            .generatedTopology(
                "feature:\(FeatureID().description)/generated:polySpline/subshape:patch:0:vertex:uMax:vMax"
            )
        )
    )
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .movePolySplineSurfaceVertex(
            target: target,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(0.0, .millimeter),
            deltaZ: .length(1.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let slideRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .slidePolySplineSurfaceVertices(
            targets: [target],
            direction: .positiveV,
            distance: .length(1.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceControlPointReference = SelectionReference.surface(
        .controlPoint(
            SurfaceControlPointReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("polySpline"),
                        .subshape("patch:0:face"),
                    ])
                ),
                uIndex: 3,
                vIndex: 3
            )
        )
    )
    let surfaceControlPointMoveRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .moveSurfaceControlPoint(
            target: surfaceControlPointReference,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(0.0, .millimeter),
            deltaZ: .length(1.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceControlPointFrameMoveRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .moveSurfaceControlPointsInFrame(
            targets: [surfaceControlPointReference],
            frame: SurfaceFrameQuery(selectionReference: surfaceControlPointReference),
            uDistance: .length(1.0, .millimeter),
            vDistance: .length(2.0, .millimeter),
            normalDistance: .length(3.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceControlPointWeightRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceControlPointWeight(
            target: surfaceControlPointReference,
            weight: .scalar(2.5)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceControlPointDisplayRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceControlPointDisplay(
            target: surfaceControlPointReference,
            isVisible: true
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceFrameDisplayRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceFrameDisplay(
            query: SurfaceFrameQuery(selectionReference: surfaceControlPointReference),
            isVisible: true
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceControlPointSlideRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .slideSurfaceControlPoints(
            targets: [surfaceControlPointReference],
            direction: .positiveV,
            distance: .length(1.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceKnotReference = SelectionReference.surface(
        .knot(
            SurfaceKnotReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                direction: .u,
                knotIndex: 3
            )
        )
    )
    let surfaceKnotValueRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceKnotValue(
            target: surfaceKnotReference,
            value: .scalar(0.4)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceSpanReference = SelectionReference.surface(
        .span(
            SurfaceSpanReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                direction: .u,
                spanIndex: 0
            )
        )
    )
    let surfaceKnotInsertionRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .insertSurfaceKnot(
            target: surfaceSpanReference,
            value: .scalar(0.25)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceSpanSplitRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .splitSurfaceSpan(
            target: surfaceSpanReference,
            fraction: .scalar(0.5)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceKnotMultiplicityRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceKnotMultiplicity(
            target: surfaceKnotReference,
            multiplicity: 2
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimReference = SelectionReference.surface(
        .trim(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                loopIndex: 0,
                edgeIndex: 0
            )
        )
    )
    let referenceSurfaceTrimReference = SelectionReference.surface(
        .trim(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                loopIndex: 0,
                edgeIndex: 2
            )
        )
    )
    let surfaceBoundaryContinuityRequest = AgentRequest.execute(
        sessionID: sessionID,
            command: .matchSurfaceBoundaryContinuity(
                target: surfaceTrimReference,
                reference: referenceSurfaceTrimReference,
                level: .g1,
                matchSide: .opposite,
                referenceDirection: .reversed
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimDomainRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceTrimDomain(
            target: surfaceTrimReference,
            uLowerBound: .scalar(0.25),
            uUpperBound: .scalar(0.75),
            vLowerBound: .scalar(0.2),
            vUpperBound: .scalar(0.8)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimLoop = BSplineSurfaceTrimLoop(
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
    let surfaceTrimLoopsRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceTrimLoops(
            target: surfaceTrimReference,
            trimLoops: [surfaceTrimLoop]
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimEndpointRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .moveSurfaceTrimEndpoint(
            target: surfaceTrimReference,
            endpoint: .start,
            u: .scalar(0.25),
            v: .scalar(0.3)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimControlPointRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .moveSurfaceTrimControlPoint(
            target: surfaceTrimReference,
            controlPointIndex: 1,
            u: .scalar(0.58),
            v: .scalar(0.46)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimControlPointWeightRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceTrimControlPointWeight(
            target: surfaceTrimReference,
            controlPointIndex: 1,
            weight: .scalar(2.4)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimKnotInsertionRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .insertSurfaceTrimKnot(
            target: surfaceTrimReference,
            value: .scalar(0.5)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimKnotValueRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceTrimKnotValue(
            target: surfaceTrimReference,
            knotIndex: 3,
            value: .scalar(0.4)
        ),
        expectedGeneration: DocumentGeneration(5)
    )
    let surfaceTrimKnotMultiplicityRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .setSurfaceTrimKnotMultiplicity(
            target: surfaceTrimReference,
            knotIndex: 3,
            multiplicity: 2
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedSlideRequest = try codec.decodeRequest(from: try codec.encode(slideRequest))
    let decodedSurfaceControlPointMoveRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointMoveRequest)
    )
    let decodedSurfaceControlPointFrameMoveRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointFrameMoveRequest)
    )
    let decodedSurfaceControlPointWeightRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointWeightRequest)
    )
    let decodedSurfaceControlPointDisplayRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointDisplayRequest)
    )
    let decodedSurfaceFrameDisplayRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceFrameDisplayRequest)
    )
    let decodedSurfaceControlPointSlideRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointSlideRequest)
    )
    let decodedSurfaceKnotValueRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceKnotValueRequest)
    )
    let decodedSurfaceKnotInsertionRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceKnotInsertionRequest)
    )
    let decodedSurfaceSpanSplitRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceSpanSplitRequest)
    )
    let decodedSurfaceKnotMultiplicityRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceKnotMultiplicityRequest)
    )
    let decodedSurfaceTrimDomainRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimDomainRequest)
    )
    let decodedSurfaceTrimLoopsRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimLoopsRequest)
    )
    let decodedSurfaceTrimEndpointRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimEndpointRequest)
    )
    let decodedSurfaceTrimControlPointRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimControlPointRequest)
    )
    let decodedSurfaceTrimControlPointWeightRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimControlPointWeightRequest)
    )
    let decodedSurfaceTrimKnotInsertionRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimKnotInsertionRequest)
    )
    let decodedSurfaceTrimKnotValueRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimKnotValueRequest)
    )
    let decodedSurfaceTrimKnotMultiplicityRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceTrimKnotMultiplicityRequest)
    )
    let decodedSurfaceBoundaryContinuityRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceBoundaryContinuityRequest)
    )

    #expect(decodedRequest == request)
    #expect(decodedSlideRequest == slideRequest)
    #expect(decodedSurfaceControlPointMoveRequest == surfaceControlPointMoveRequest)
    #expect(decodedSurfaceControlPointFrameMoveRequest == surfaceControlPointFrameMoveRequest)
    #expect(decodedSurfaceControlPointWeightRequest == surfaceControlPointWeightRequest)
    #expect(decodedSurfaceControlPointDisplayRequest == surfaceControlPointDisplayRequest)
    #expect(decodedSurfaceFrameDisplayRequest == surfaceFrameDisplayRequest)
    #expect(decodedSurfaceControlPointSlideRequest == surfaceControlPointSlideRequest)
    #expect(decodedSurfaceKnotValueRequest == surfaceKnotValueRequest)
    #expect(decodedSurfaceKnotInsertionRequest == surfaceKnotInsertionRequest)
    #expect(decodedSurfaceSpanSplitRequest == surfaceSpanSplitRequest)
    #expect(decodedSurfaceKnotMultiplicityRequest == surfaceKnotMultiplicityRequest)
    #expect(decodedSurfaceTrimDomainRequest == surfaceTrimDomainRequest)
    #expect(decodedSurfaceTrimLoopsRequest == surfaceTrimLoopsRequest)
    #expect(decodedSurfaceTrimEndpointRequest == surfaceTrimEndpointRequest)
    #expect(decodedSurfaceTrimControlPointRequest == surfaceTrimControlPointRequest)
    #expect(decodedSurfaceTrimControlPointWeightRequest == surfaceTrimControlPointWeightRequest)
    #expect(decodedSurfaceTrimKnotInsertionRequest == surfaceTrimKnotInsertionRequest)
    #expect(decodedSurfaceTrimKnotValueRequest == surfaceTrimKnotValueRequest)
    #expect(decodedSurfaceTrimKnotMultiplicityRequest == surfaceTrimKnotMultiplicityRequest)
    #expect(decodedSurfaceBoundaryContinuityRequest == surfaceBoundaryContinuityRequest)
}

@Test func agentMessageCodecRoundTripsPolySplineMeshAnalysis() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.polySplineMeshAnalysis(
        sessionID: sessionID,
        sourceMesh: agentPolySplineQuadMesh(),
        options: PolySplineOptions(roundedCorners: true),
        expectedGeneration: DocumentGeneration(5)
    )
    let response = AgentResponse.polySplineMeshAnalysis(
        PolySplineMeshAnalysisResult(
            vertexCount: 4,
            usedVertexCount: 4,
            triangleCount: 2,
            indexedElementCount: 6,
            boundaryEdgeCount: 4,
            internalEdgeCount: 1,
            connectedComponentCount: 1,
            supportedPatchCount: 1,
            candidatePatchCount: 1,
            candidateKind: .singleQuad,
            patchGraph: PolySplinePatchGraph(
                triangleCount: 2,
                candidates: [
                    PolySplinePatchGraph.QuadCandidate(
                        id: 0,
                        triangleIndices: [0, 1],
                        boundaryVertexIndices: [0, 1, 2, 3],
                        boundaryEdges: [
                            PolySplinePatchGraph.VertexPair(firstVertexIndex: 0, secondVertexIndex: 1),
                            PolySplinePatchGraph.VertexPair(firstVertexIndex: 1, secondVertexIndex: 2),
                            PolySplinePatchGraph.VertexPair(firstVertexIndex: 2, secondVertexIndex: 3),
                            PolySplinePatchGraph.VertexPair(firstVertexIndex: 0, secondVertexIndex: 3),
                        ],
                        splitEdge: PolySplinePatchGraph.VertexPair(firstVertexIndex: 0, secondVertexIndex: 2)
                    ),
                ],
                partition: PolySplinePatchGraph.Partition(
                    selectedCandidateIDs: [0],
                    rejectedCandidateIDs: [],
                    coveredTriangleIndices: [0, 1],
                    uncoveredTriangleIndices: []
                )
            ),
            isSupported: false,
            diagnostics: [
                PolySplineMeshAnalysisResult.Diagnostic(
                    severity: .error,
                    code: .unsupportedRoundedCorners,
                    message: "Rounded corners are not supported."
                ),
            ]
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

@Test func agentMessageCodecRoundTripsSetBridgeCurveParametersCommand() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let sourceID = BridgeCurveSourceID()
    let firstLineID = SketchEntityID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .setBridgeCurveParameters(
            sourceID: sourceID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .entity(firstLineID),
                parameter: .scalar(0.5),
                reversesSense: true
            ),
            secondEndpoint: nil,
            continuity: BridgeCurveContinuity(first: .g1, second: .g0),
            trimsSourceCurves: true
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))

    #expect(decodedRequest == request)
}

@Test func agentMessageCodecRoundTripsEvaluateAndSaveResponses() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let evaluateRequest = AgentRequest.evaluate(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let evaluateResponse = AgentResponse.evaluation(
        EvaluationSnapshot(
            status: .valid,
            evaluatedGeneration: DocumentGeneration(4),
            bodyCount: 1
        )
    )
    let measureRequest = AgentRequest.measure(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let measureResponse = AgentResponse.measurement(
        MeasurementResult(
            displayUnit: .millimeter,
            counts: MeasurementResult.Counts(sourceFeatures: 2, sketches: 1, profiles: 1, solids: 1),
            totals: MeasurementResult.Totals(
                profileAreaSquareMeters: 0.0001,
                solidVolumeCubicMeters: 0.000001
            )
        )
    )
    let selectionMeasurementFaceName = PersistentName(components: [
        .feature(FeatureID(UUID())),
        .generated("polySpline"),
        .subshape("patch:0:face"),
    ])
    let selectionMeasurementReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
        surface: SurfaceReference(faceName: selectionMeasurementFaceName),
        uIndex: 0,
        vIndex: 0
    )))
    let selectionMeasurementRequest = AgentRequest.selectionMeasurement(
        sessionID: sessionID,
        query: CADAgentMeasurementQuery(kind: .point, first: selectionMeasurementReference),
        expectedGeneration: DocumentGeneration(4)
    )
    let selectionMeasurementResponse = AgentResponse.selectionMeasurement(
        .point(SelectionMeasurementPoint(
            selection: selectionMeasurementReference,
            point: Point3D(x: 0.0, y: 0.0, z: 0.0)
        ))
    )
    let meshRequest = AgentRequest.meshSummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let meshResponse = AgentResponse.meshSummary(
        MeshSummaryResult(
            displayUnit: .millimeter,
            bodyCount: 1,
            vertexCount: 8,
            triangleCount: 12,
            indexedElementCount: 36
        )
    )
    let sketchRequest = AgentRequest.sketchEntitySummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let sketchResponse = AgentResponse.sketchEntitySummary(
        SketchEntitySummaryResult(
            displayUnit: .millimeter,
            counts: SketchEntitySummaryResult.Counts(
                sketchCount: 1,
                entityCount: 1,
                constraintCount: 0,
                dimensionCount: 0
            )
        )
    )
    let curveAnalysisRequest = AgentRequest.curveAnalysis(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let curveAnalysisResponse = AgentResponse.curveAnalysis(
        CurveAnalysisResult(
            displayUnit: .millimeter,
            counts: CurveAnalysisResult.Counts(
                curveCount: 1,
                sampleCount: 1,
                continuityJoinCount: 1
            ),
            curves: [
                CurveAnalysisResult.CurveEntry(
                    sourceFeatureID: UUID().uuidString,
                    sourceFeatureName: "Curve",
                    sceneNodeID: UUID().uuidString,
                    entityID: UUID().uuidString,
                    curveKind: .spline,
                    selectionComponentID: "sketchEntity:encoded",
                    samples: [
                        CurveEvaluationSample(
                            parameter: 0.5,
                            point: CADCore.Point2D(x: 0.1, y: 0.2),
                            tangent: CADCore.Point2D(x: 1.0, y: 0.0),
                            normal: CADCore.Point2D(x: 0.0, y: 1.0),
                            curvature: 12.0
                        ),
                    ],
                    maxAbsCurvature: 12.0,
                    approximateLength: 0.1
                ),
            ],
            continuityJoins: [
                CurveAnalysisResult.ContinuityJoin(
                    sourceFeatureID: UUID().uuidString,
                    joinKind: .constrainedEndpoint,
                    firstEntityID: UUID().uuidString,
                    firstReference: "splineControlPoint:first:3",
                    firstParameter: 0.5,
                    secondEntityID: UUID().uuidString,
                    secondReference: "splineControlPoint:second:0",
                    secondParameter: 0.5,
                    constraintKinds: ["coincident", "smoothSplineEndpoints"],
                    requiredContinuity: .g2,
                    continuity: .g2,
                    positionGap: 0.0,
                    tangentAngle: 0.0,
                    curvatureGap: 0.0
                ),
            ]
        )
    )
    let snapRequest = AgentRequest.resolveSnap(
        sessionID: sessionID,
        point: CADCore.Point2D(x: 0.01031, y: 0.00002),
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: true,
            objectTargetingOverride: .forceEnabled,
            suppressedCandidateKinds: [.lineClosest],
            usesConstructionPlaneProjection: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002,
            maximumCandidateCount: 4
        ),
        expectedGeneration: DocumentGeneration(4)
    )
    let snapCandidate = SnapCandidate(
        kind: .lineEnd,
        point: CADCore.Point2D(x: 0.0103, y: 0.0),
        distanceMeters: 0.000022360679775,
        label: "Line End",
        source: SnapSourceReference(
            sceneNodeID: SceneNodeID(),
            featureID: FeatureID(),
            entityID: SketchEntityID()
        )
    )
    let snapResponse = AgentResponse.snapResolution(
        SnapResolutionResult(
            originalPoint: CADCore.Point2D(x: 0.01031, y: 0.00002),
            resolvedPoint: CADCore.Point2D(x: 0.0103, y: 0.0),
            selectedCandidate: snapCandidate,
            candidates: [snapCandidate]
        )
    )
    let topologyRequest = AgentRequest.topologySummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let topologyResponse = AgentResponse.topologySummary(
        TopologySummaryResult(
            displayUnit: .millimeter,
            counts: TopologySummaryResult.Counts(
                bodyCount: 1,
                faceCount: 6,
                edgeCount: 12,
                vertexCount: 8
            )
        )
    )
    let surfaceSourceRequest = AgentRequest.surfaceSourceSummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let surfaceCodecFeatureID = FeatureID(UUID())
    let surfaceCodecFacePersistentName = "feature:\(surfaceCodecFeatureID.description)/generated:polySpline/subshape:patch:0:face"
    let surfaceCodecEdgePersistentName = "feature:\(surfaceCodecFeatureID.description)/generated:polySpline/subshape:patch:0:edge:vMin"
    let surfaceCodecVertexPersistentName = "feature:\(surfaceCodecFeatureID.description)/generated:polySpline/subshape:patch:0:vertex:uMin:vMin"
    let surfaceCodecFaceName = PersistentName(components: [
        .feature(surfaceCodecFeatureID),
        .generated("polySpline"),
        .subshape("patch:0:face"),
    ])
    let surfaceCodecReference = SurfaceReference(faceName: surfaceCodecFaceName)
    let surfaceCodecControlPointReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
        surface: surfaceCodecReference,
        uIndex: 0,
        vIndex: 0
    )))
    let surfaceSourceResponse = AgentResponse.surfaceSourceSummary(
        SurfaceSourceSummaryResult(
            displayUnit: .millimeter,
            counts: SurfaceSourceSummaryResult.Counts(
                sourceCount: 1,
                patchCount: 1,
                controlVertexCount: 4,
                controlPointCount: 16,
                trimLoopCount: 1,
                adjacencyCount: 0
            ),
            sources: [
                SurfaceSourceSummaryResult.Source(
                    featureID: surfaceCodecFeatureID.description,
                    name: "Codec PolySpline",
                    sceneNodeID: UUID().uuidString,
                    kind: "polySpline",
                    meshCounts: SurfaceSourceSummaryResult.MeshCounts(
                        vertexCount: 4,
                        usedVertexCount: 4,
                        triangleCount: 2,
                        indexedElementCount: 6,
                        boundaryEdgeCount: 4,
                        internalEdgeCount: 1
                    ),
                    options: SurfaceSourceSummaryResult.PolySplineOptionsSummary(
                        roundedCorners: false,
                        mergePatches: false,
                        interpolateBoundaryExactly: true
                    ),
                    support: SurfaceSourceSummaryResult.SupportSummary(
                        isSupported: true,
                        candidateKind: "singleQuad",
                        supportedPatchCount: 1,
                        candidatePatchCount: 1,
                        failureMessage: nil
                    ),
                    patches: [
                        SurfaceSourceSummaryResult.Patch(
                            patchID: 0,
                            facePersistentName: surfaceCodecFacePersistentName,
                            faceSelectionComponentID: SelectionComponentID
                                .generatedTopology(surfaceCodecFacePersistentName)
                                .rawValue,
                            faceSelectionReference: .surface(.whole(surfaceCodecReference)),
                            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                            basis: SurfaceSourceSummaryResult.Basis(
                                kind: "cubicBezierBSpline",
                                uDegree: 3,
                                vDegree: 3,
                                uOrder: 4,
                                vOrder: 4,
                                uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                                vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                                uKnotVector: [
                                    SurfaceSourceSummaryResult.Basis.Knot(
                                        id: "uKnot:0",
                                        index: 0,
                                        value: 0.0,
                                        multiplicity: 4,
                                        isBoundary: true
                                    ),
                                    SurfaceSourceSummaryResult.Basis.Knot(
                                        id: "uKnot:4",
                                        index: 4,
                                        value: 1.0,
                                        multiplicity: 4,
                                        isBoundary: true
                                    ),
                                ],
                                vKnotVector: [
                                    SurfaceSourceSummaryResult.Basis.Knot(
                                        id: "vKnot:0",
                                        index: 0,
                                        value: 0.0,
                                        multiplicity: 4,
                                        isBoundary: true
                                    ),
                                    SurfaceSourceSummaryResult.Basis.Knot(
                                        id: "vKnot:4",
                                        index: 4,
                                        value: 1.0,
                                        multiplicity: 4,
                                        isBoundary: true
                                    ),
                                ],
                                uSpans: [
                                    SurfaceSourceSummaryResult.Basis.Span(
                                        id: "uSpan:0",
                                        index: 0,
                                        lowerBound: 0.0,
                                        upperBound: 1.0,
                                        startKnotIndex: 3,
                                        endKnotIndex: 4
                                    ),
                                ],
                                vSpans: [
                                    SurfaceSourceSummaryResult.Basis.Span(
                                        id: "vSpan:0",
                                        index: 0,
                                        lowerBound: 0.0,
                                        upperBound: 1.0,
                                        startKnotIndex: 3,
                                        endKnotIndex: 4
                                    ),
                                ],
                                uSpanCount: 1,
                                vSpanCount: 1,
                                isRational: false
                            ),
                            controlVertices: [
                                SurfaceSourceSummaryResult.ControlVertex(
                                    id: "feature:a/patch:0/cv:uMin:vMin",
                                    role: "uMin:vMin",
                                    sourceVertexIndex: 0,
                                    point: SurfaceSourceSummaryResult.Point(x: 0.0, y: 0.0, z: 0.0),
                                    generatedVertexPersistentName: surfaceCodecVertexPersistentName,
                                    selectionComponentID: SelectionComponentID
                                        .generatedTopology(
                                            surfaceCodecVertexPersistentName
                                        )
                                        .rawValue,
                                    selectionReference: surfaceCodecControlPointReference
                                ),
                            ],
                            controlPoints: [
                                SurfaceSourceSummaryResult.ControlPoint(
                                    id: "feature:a/patch:0/surfaceControlPoint:u1:v1",
                                    uIndex: 1,
                                    vIndex: 1,
                                    point: SurfaceSourceSummaryResult.Point(x: 0.25, y: 0.25, z: 0.0),
                                    weight: 1.0,
                                    isBoundary: false,
                                    isEditable: true,
                                    selectionReference: .surface(.controlPoint(SurfaceControlPointReference(
                                        surface: surfaceCodecReference,
                                        uIndex: 1,
                                        vIndex: 1
                                    )))
                                ),
                            ],
                            trimLoops: [
                                SurfaceSourceSummaryResult.TrimLoop(
                                    role: "outer",
                                    parameterAddresses: [
                                        SurfaceSourceSummaryResult.ParameterAddress(id: "uMin:vMin", u: 0.0, v: 0.0),
                                    ],
                                    sourceVertexIndices: [0, 1, 2, 3],
                                    edgePersistentNames: [
                                        surfaceCodecEdgePersistentName,
                                    ],
                                    selectionReferences: [
                                        .surface(.trim(SurfaceTrimReference(
                                            surface: surfaceCodecReference,
                                            loopIndex: 0,
                                            edgeIndex: 0
                                        ))),
                                    ]
                                ),
                            ],
                            parameterAddresses: [
                                SurfaceSourceSummaryResult.ParameterAddress(
                                    id: "center",
                                    u: 0.5,
                                    v: 0.5,
                                    selectionReference: .surface(.parameter(SurfaceParameterReference(
                                        surface: surfaceCodecReference,
                                        u: 0.5,
                                        v: 0.5
                                    )))
                                ),
                            ]
                        ),
                    ],
                    adjacencies: [],
                    diagnostics: [
                        SurfaceSourceSummaryResult.Diagnostic(
                            severity: "info",
                            code: "singleQuadPatchSupported",
                            message: "Supported."
                        ),
                    ]
                ),
            ]
        )
    )
    let surfaceAnalysisRequest = AgentRequest.surfaceAnalysis(
        sessionID: sessionID,
        options: SurfaceAnalysisOptions(sampleDensity: .high),
        expectedGeneration: DocumentGeneration(4)
    )
    let surfaceAnalysisResponse = AgentResponse.surfaceAnalysis(
        SurfaceAnalysisResult(
            displayUnit: .millimeter,
            counts: SurfaceAnalysisResult.Counts(
                bSplineFaceCount: 1,
                sampleCount: 1,
                uCurvatureCombCount: 1,
                vCurvatureCombCount: 1,
                trimBoundaryCount: 1,
                innerTrimBoundaryCount: 0,
                openTrimBoundaryCount: 0,
                trimBoundaryEdgeCount: 4
            ),
            faces: [
                SurfaceAnalysisResult.FaceAnalysis(
                    faceID: UUID().uuidString,
                    facePersistentNames: ["feature:a/generated:polySpline/subshape:patch:0:face"],
                    edgePersistentNames: ["feature:a/generated:polySpline/subshape:patch:0:edge:uMax"],
                    trimBoundaries: [
                        SurfaceAnalysisResult.TrimBoundary(
                            loopID: UUID().uuidString,
                            role: .outer,
                            points: [
                                SurfaceAnalysisResult.Point(x: 0.0, y: 0.0, z: 0.0),
                                SurfaceAnalysisResult.Point(x: 1.0, y: 0.0, z: 0.0),
                                SurfaceAnalysisResult.Point(x: 1.0, y: 1.0, z: 0.0),
                                SurfaceAnalysisResult.Point(x: 0.0, y: 1.0, z: 0.0),
                            ],
                            edgePersistentNames: [
                                "feature:a/generated:polySpline/subshape:patch:0:edge:uMax",
                            ],
                            edgeCount: 4,
                            vertexCount: 4,
                            isClosed: true,
                            estimatedLength: 0.04
                        ),
                    ],
                    sourceFeatureID: UUID().uuidString,
                    sceneNodeID: UUID().uuidString,
                    uDegree: 3,
                    vDegree: 3,
                    uControlPointCount: 4,
                    vControlPointCount: 4,
                    uDomain: SurfaceAnalysisResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                    vDomain: SurfaceAnalysisResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                    samples: [
                        SurfaceAnalysisResult.Sample(
                            u: 0.5,
                            v: 0.5,
                            position: SurfaceAnalysisResult.Point(x: 0.1, y: 0.0, z: 0.2),
                            normal: SurfaceAnalysisResult.Vector(x: 0.0, y: 1.0, z: 0.0),
                            tangentU: SurfaceAnalysisResult.Vector(x: 1.0, y: 0.0, z: 0.0),
                            tangentV: SurfaceAnalysisResult.Vector(x: 0.0, y: 0.0, z: 1.0),
                            normalCurvatureU: 0.0,
                            normalCurvatureV: 0.0,
                            meanCurvature: 0.0,
                            gaussianCurvature: 0.0,
                            minimumPrincipalCurvature: 0.0,
                            maximumPrincipalCurvature: 0.0,
                            minimumPrincipalDirection: SurfaceAnalysisResult.Vector(x: 1.0, y: 0.0, z: 0.0),
                            maximumPrincipalDirection: SurfaceAnalysisResult.Vector(x: 0.0, y: 0.0, z: 1.0)
                        ),
                    ],
                    curvatureCombs: [
                        SurfaceAnalysisResult.CurvatureCombSample(
                            direction: .u,
                            u: 0.5,
                            v: 0.5,
                            position: SurfaceAnalysisResult.Point(x: 0.1, y: 0.0, z: 0.2),
                            normal: SurfaceAnalysisResult.Vector(x: 0.0, y: 1.0, z: 0.0),
                            neighborDistance: 0.1,
                            normalAngle: 0.0,
                            normalChangePerLength: 0.0,
                            normalCurvature: 0.0
                        ),
                        SurfaceAnalysisResult.CurvatureCombSample(
                            direction: .v,
                            u: 0.5,
                            v: 0.5,
                            position: SurfaceAnalysisResult.Point(x: 0.1, y: 0.0, z: 0.2),
                            normal: SurfaceAnalysisResult.Vector(x: 0.0, y: 1.0, z: 0.0),
                            neighborDistance: 0.1,
                            normalAngle: 0.0,
                            normalChangePerLength: 0.0,
                            normalCurvature: 0.0
                        ),
                    ],
                    maxUNormalChangePerLength: 0.0,
                    maxVNormalChangePerLength: 0.0,
                    maxNormalAngle: 0.0,
                    maxAbsUNormalCurvature: 0.0,
                    maxAbsVNormalCurvature: 0.0,
                    maxAbsPrincipalCurvature: 0.0,
                    maxAbsGaussianCurvature: 0.0
                ),
            ]
        )
    )
    let surfaceFramesRequest = AgentRequest.surfaceFrames(
        sessionID: sessionID,
        queries: [
            SurfaceFrameQuery(
                facePersistentName: "feature:a/generated:polySpline/subshape:patch:0:face",
                u: 0.5,
                v: 0.5
            ),
        ],
        expectedGeneration: DocumentGeneration(4)
    )
    let surfaceFramesResponse = AgentResponse.surfaceFrames(
        SurfaceFrameResult(
            displayUnit: .millimeter,
            frames: [
                SurfaceFrameResult.Frame(
                    faceID: UUID().uuidString,
                    facePersistentNames: ["feature:a/generated:polySpline/subshape:patch:0:face"],
                    sourceFeatureID: UUID().uuidString,
                    sceneNodeID: UUID().uuidString,
                    u: 0.5,
                    v: 0.5,
                    uDomain: SurfaceAnalysisResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                    vDomain: SurfaceAnalysisResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
                    position: SurfaceAnalysisResult.Point(x: 0.1, y: 0.0, z: 0.2),
                    tangentU: SurfaceAnalysisResult.Vector(x: 1.0, y: 0.0, z: 0.0),
                    tangentV: SurfaceAnalysisResult.Vector(x: 0.0, y: 0.0, z: 1.0),
                    uAxis: SurfaceAnalysisResult.Vector(x: 1.0, y: 0.0, z: 0.0),
                    vAxis: SurfaceAnalysisResult.Vector(x: 0.0, y: 0.0, z: 1.0),
                    normal: SurfaceAnalysisResult.Vector(x: 0.0, y: -1.0, z: 0.0),
                    handedness: 1.0,
                    normalCurvatureU: 0.0,
                    normalCurvatureV: 0.0,
                    meanCurvature: 0.0,
                    gaussianCurvature: 0.0,
                    minimumPrincipalCurvature: 0.0,
                    maximumPrincipalCurvature: 0.0,
                    minimumPrincipalDirection: SurfaceAnalysisResult.Vector(x: 1.0, y: 0.0, z: 0.0),
                    maximumPrincipalDirection: SurfaceAnalysisResult.Vector(x: 0.0, y: 0.0, z: 1.0)
                ),
            ]
        )
    )
    let surfaceContinuityRequest = AgentRequest.surfaceContinuitySummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let surfaceContinuityResponse = AgentResponse.surfaceContinuitySummary(
        RupaCore.SurfaceContinuityResult(
            displayUnit: .millimeter,
            counts: RupaCore.SurfaceContinuityResult.Counts(
                bSplineFaceCount: 2,
                sharedEdgeCount: 1,
                g0AdjacencyCount: 0,
                g1AdjacencyCount: 1,
                g2AdjacencyCount: 0,
                unresolvedG2AdjacencyCount: 0
            ),
            adjacencies: [
                RupaCore.SurfaceContinuityResult.Adjacency(
                    edgeID: UUID().uuidString,
                    edgePersistentNames: ["feature:a/generated:polySpline/subshape:patch:0:edge:uMax"],
                    firstFaceID: UUID().uuidString,
                    secondFaceID: UUID().uuidString,
                    firstFacePersistentName: "feature:a/generated:polySpline/subshape:patch:0:face",
                    secondFacePersistentName: "feature:a/generated:polySpline/subshape:patch:2:face",
                    continuity: .g1,
                    positionGap: 0.0,
                    normalAngle: 0.0,
                    curvatureGap: nil,
                    requiresCurvatureContinuitySolve: false
                ),
            ]
        )
    )
    let surfaceTrimReference = SelectionReference.surface(
        .trim(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                loopIndex: 0,
                edgeIndex: 0
            )
        )
    )
    let referenceSurfaceTrimReference = SelectionReference.surface(
        .trim(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    faceName: PersistentName(components: [
                        .feature(FeatureID()),
                        .generated("bSplineSurface"),
                        .subshape("patch:0:face"),
                    ])
                ),
                loopIndex: 0,
                edgeIndex: 2
            )
        )
    )
    let surfaceBoundaryCompatibilityRequest = AgentRequest.surfaceBoundaryContinuityCompatibility(
        sessionID: sessionID,
        target: surfaceTrimReference,
        reference: referenceSurfaceTrimReference,
        expectedGeneration: DocumentGeneration(4)
    )
    let surfaceBoundaryCompatibilityResult = SurfaceBoundaryContinuityCompatibilityResult(
        status: .compatible,
        target: SurfaceBoundaryContinuityCompatibilityResult.Boundary(
            featureID: FeatureID(),
            selectionReference: surfaceTrimReference,
            role: "vMin",
            boundaryDirection: .u,
            inwardDirection: .v,
            boundaryDegree: 3,
            inwardDegree: 3,
            boundaryControlPointCount: 4,
            inwardControlPointCount: 4,
            isClamped: true,
            supportedContinuityLevels: [.g0, .g1, .g2]
        ),
        reference: SurfaceBoundaryContinuityCompatibilityResult.Boundary(
            featureID: FeatureID(),
            selectionReference: referenceSurfaceTrimReference,
            role: "vMax",
            boundaryDirection: .u,
            inwardDirection: .v,
            boundaryDegree: 3,
            inwardDegree: 3,
            boundaryControlPointCount: 4,
            inwardControlPointCount: 4,
            isClamped: true,
            supportedContinuityLevels: [.g0, .g1, .g2]
        ),
        supportedContinuityLevels: [.g0, .g1, .g2],
        maximumSupportedContinuityLevel: .g2,
        recommendedReferenceDirection: .forward,
        recommendedMatchSide: .opposite,
        diagnostics: [
            SurfaceBoundaryContinuityCompatibilityResult.Diagnostic(
                severity: .info,
                code: "compatibleBoundaryPair",
                message: "Boundary pair supports G0/G1/G2 continuity matching."
            ),
        ]
    )
    let surfaceBoundaryCompatibilityResponse = AgentResponse.surfaceBoundaryContinuityCompatibility(
        surfaceBoundaryCompatibilityResult
    )
    let selectionTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(UUID()),
        component: .vertex(.generatedTopology("feature:body/generated:vertex/index:0"))
    )
    let selectRequest = AgentRequest.selectTargets(
        sessionID: sessionID,
        targets: [selectionTarget],
        expectedGeneration: DocumentGeneration(4)
    )
    let selectResponse = AgentResponse.selection(
        SelectionStateResult(
            message: "1 target selected.",
            generation: DocumentGeneration(4),
            dirty: false,
            selectedTargets: [selectionTarget]
        )
    )
    let selectionReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
        surface: SurfaceReference(
            faceName: PersistentName(components: [
                .feature(FeatureID()),
                .generated("polySpline"),
                .subshape("patch:0:face"),
            ])
        ),
        uIndex: 1,
        vIndex: 1
    )))
    let selectReferenceRequest = AgentRequest.selectReferences(
        sessionID: sessionID,
        references: [selectionReference],
        expectedGeneration: DocumentGeneration(4)
    )
    let selectReferenceResponse = AgentResponse.selection(
        SelectionStateResult(
            message: "1 reference selected.",
            generation: DocumentGeneration(4),
            dirty: false,
            selectedTargets: [],
            selectedReferences: [selectionReference]
        )
    )
    let saveRequest = AgentRequest.save(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let saveResponse = AgentResponse.save(
        SaveResult(
            message: "Saved",
            path: "/tmp/model.swcad",
            generation: DocumentGeneration(4),
            dirty: false,
            diagnostics: []
        )
    )

    #expect(try codec.decodeRequest(from: try codec.encode(evaluateRequest)) == evaluateRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(evaluateResponse)) == evaluateResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(measureRequest)) == measureRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(measureResponse)) == measureResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(selectionMeasurementRequest)) == selectionMeasurementRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(selectionMeasurementResponse)) == selectionMeasurementResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(meshRequest)) == meshRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(meshResponse)) == meshResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(sketchRequest)) == sketchRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(sketchResponse)) == sketchResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(curveAnalysisRequest)) == curveAnalysisRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(curveAnalysisResponse)) == curveAnalysisResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(snapRequest)) == snapRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(snapResponse)) == snapResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(topologyRequest)) == topologyRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(topologyResponse)) == topologyResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(surfaceSourceRequest)) == surfaceSourceRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(surfaceSourceResponse)) == surfaceSourceResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(surfaceAnalysisRequest)) == surfaceAnalysisRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(surfaceAnalysisResponse)) == surfaceAnalysisResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(surfaceFramesRequest)) == surfaceFramesRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(surfaceFramesResponse)) == surfaceFramesResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(surfaceContinuityRequest)) == surfaceContinuityRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(surfaceContinuityResponse)) == surfaceContinuityResponse)
    #expect(
        try codec.decodeRequest(from: try codec.encode(surfaceBoundaryCompatibilityRequest))
            == surfaceBoundaryCompatibilityRequest
    )
    #expect(
        try codec.decodeResponse(from: try codec.encode(surfaceBoundaryCompatibilityResponse))
            == surfaceBoundaryCompatibilityResponse
    )
    #expect(try codec.decodeRequest(from: try codec.encode(selectRequest)) == selectRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(selectResponse)) == selectResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(selectReferenceRequest)) == selectReferenceRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(selectReferenceResponse)) == selectReferenceResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(saveRequest)) == saveRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(saveResponse)) == saveResponse)
}

@Test func agentMessageCodecRoundTripsExportRequestAndResponse() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.export(
        sessionID: sessionID,
        outputPath: "/tmp/model.stl",
        expectedGeneration: DocumentGeneration(3),
        options: ExportOptions(
            presetName: "Print STL",
            destinationPolicy: .versioned
        ),
        dryRun: false
    )
    let response = AgentResponse.export(
        ExportResult(
            message: "Exported",
            format: .stl,
            outputPath: "/tmp/model.stl",
            byteCount: 684,
            generation: DocumentGeneration(3),
            presetName: "Print STL",
            outputUnit: .millimeter,
            destinationPolicy: .versioned,
            diagnostics: []
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

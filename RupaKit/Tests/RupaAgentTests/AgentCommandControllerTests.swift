import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentCapabilitiesExposeAutomationCommands() async throws {
    let server = AgentCommandController()
    let capabilities = server.capabilities()
    let descriptors = server.capabilityDescriptors()
    let descriptorNames = descriptors.map(\.name)

    #expect(capabilities.contains("describeDocument"))
    #expect(capabilities.contains("setDisplayUnit"))
    #expect(capabilities.contains("renameDocument"))
    #expect(capabilities.contains("upsertParameter"))
    #expect(capabilities.contains("deleteParameter"))
    #expect(capabilities.contains("setParameterExpression"))
    #expect(capabilities.contains("listParameters"))
    #expect(capabilities.contains("cadInteractionQualityAssessment"))
    #expect(capabilities.contains("createComponentDefinition"))
    #expect(capabilities.contains("createComponentInstance"))
    #expect(capabilities.contains("createPatternArray"))
    #expect(capabilities.contains("updatePatternArray"))
    #expect(capabilities.contains("explodePatternArray"))
    #expect(capabilities.contains("patternArraySummary"))
    #expect(capabilities.contains("setSceneNodeVisibility"))
    #expect(capabilities.contains("setSceneNodeLock"))
    #expect(capabilities.contains("setSceneNodeTransform"))
    #expect(capabilities.contains("setComponentInstanceVisibility"))
    #expect(capabilities.contains("setComponentInstanceLock"))
    #expect(capabilities.contains("setComponentInstanceTransform"))
    #expect(capabilities.contains("createSectionPlane"))
    #expect(capabilities.contains("describeConstructionPlanes"))
    #expect(capabilities.contains("constructionPlaneSummary"))
    #expect(capabilities.contains("designDisplaySnapshot"))
    #expect(capabilities.contains("createConstructionPlane"))
    #expect(capabilities.contains("createConstructionPlaneFromTarget"))
    #expect(capabilities.contains("createConstructionPlaneFromTargets"))
    #expect(capabilities.contains("createViewAlignedConstructionPlane"))
    #expect(capabilities.contains("setActiveConstructionPlane"))
    #expect(capabilities.contains("renameConstructionPlane"))
    #expect(capabilities.contains("createSketch"))
    #expect(capabilities.contains("createLineSketch"))
    #expect(capabilities.contains("createCircleSketch"))
    #expect(capabilities.contains("createArcSketch"))
    #expect(capabilities.contains("createSplineSketch"))
    #expect(capabilities.contains("createRectangleSketch"))
    #expect(capabilities.contains("createPolygonSketch"))
    #expect(capabilities.contains("createFaceKnife"))
    #expect(capabilities.contains("addSketchConstraint"))
    #expect(capabilities.contains("createBridgeCurve"))
    #expect(capabilities.contains("setBridgeCurveParameters"))
    #expect(capabilities.contains("offsetCurve"))
    #expect(capabilities.contains("offsetRegions"))
    #expect(capabilities.contains("offsetSketchVertex"))
    #expect(capabilities.contains("applySketchCornerTreatment"))
    #expect(capabilities.contains("createSlotSketch"))
    #expect(capabilities.contains("createSweep"))
    #expect(capabilities.contains("createPolySplineSurface"))
    #expect(capabilities.contains("movePolySplineSurfaceVertex"))
    #expect(capabilities.contains("moveSurfaceControlPoint"))
    #expect(capabilities.contains("slidePolySplineSurfaceVertices"))
    #expect(capabilities.contains("slideSurfaceControlPoints"))
    #expect(capabilities.contains("polySplineMeshAnalysis"))
    #expect(capabilities.contains("offsetBodyFace"))
    #expect(capabilities.contains("chamferBodyEdges"))
    #expect(capabilities.contains("filletBodyEdges"))
    #expect(capabilities.contains("moveBodyVertex"))
    #expect(capabilities.contains("moveSketchEntityPoint"))
    #expect(capabilities.contains("moveSketchSplineControlPoint"))
    #expect(capabilities.contains("slideSketchSplineControlPoints"))
    #expect(capabilities.contains("insertSketchSplineControlPoint"))
    #expect(capabilities.contains("setSketchCircleParameters"))
    #expect(capabilities.contains("setSketchArcParameters"))
    #expect(capabilities.contains("setSketchEntityDimension"))
    #expect(capabilities.contains("setObjectDimension"))
    #expect(capabilities.contains("setExtrudeDistance"))
    #expect(capabilities.contains("setCubeDimensions"))
    #expect(capabilities.contains("setCylinderDimensions"))
    #expect(capabilities.contains("addSelectionDimension"))
    #expect(capabilities.contains("objectDimensionSummary"))
    #expect(capabilities.contains("sketchDimensionSummary"))
    #expect(capabilities.contains("selectionDimensionEvaluation"))
    #expect(capabilities.contains("convertSketchLineToArc"))
    #expect(capabilities.contains("convertSketchLineToSpline"))
    #expect(capabilities.contains("reverseSketchCurve"))
    #expect(capabilities.contains("rebuildSketchCurve"))
    #expect(capabilities.contains("extendSketchCurve"))
    #expect(capabilities.contains("splitSketchCurve"))
    #expect(capabilities.contains("trimSketchCurveSegment"))
    #expect(capabilities.contains("cutSketchCurve"))
    #expect(capabilities.contains("setCurveCurvatureDisplay"))
    #expect(capabilities.contains("setPointDisplay"))
    #expect(capabilities.contains("extrudeProfile"))
    #expect(capabilities.contains("createRevolve"))
    #expect(capabilities.contains("createExtrudedRectangle"))
    #expect(capabilities.contains("createExtrudedRectangleFromCorners"))
    #expect(capabilities.contains("createExtrudedCircle"))
    #expect(capabilities.contains("evaluateDocument"))
    #expect(capabilities.contains("measureDocument"))
    #expect(capabilities.contains("selectionMeasurement"))
    #expect(capabilities.contains("resolveSnap"))
    #expect(capabilities.contains("meshSummary"))
    #expect(capabilities.contains("sketchEntitySummary"))
    #expect(capabilities.contains("topologySummary"))
    #expect(capabilities.contains("surfaceSourceSummary"))
    #expect(capabilities.contains("surfaceAnalysis"))
    #expect(capabilities.contains("surfaceFrames"))
    #expect(capabilities.contains("surfaceContinuitySummary"))
    #expect(capabilities.contains("selectTargets"))
    #expect(capabilities.contains("saveDocument"))
    #expect(capabilities.contains("exportDocument"))
    #expect(capabilities.contains("validateDocument"))
    #expect(capabilities == descriptorNames)
    #expect(Set(descriptorNames).count == descriptorNames.count)
}

@Test func agentCapabilityDescriptorsExposeDiscoveryAndMutationContracts() async throws {
    let descriptors = AgentCommandController().capabilityDescriptors()
    let fillet = try #require(descriptors.first { $0.name == "filletBodyEdges" })
    let faceOffset = try #require(descriptors.first { $0.name == "offsetBodyFace" })
    let faceKnife = try #require(descriptors.first { $0.name == "createFaceKnife" })
    let sketchConstraint = try #require(descriptors.first { $0.name == "addSketchConstraint" })
    let bridgeCurve = try #require(descriptors.first { $0.name == "createBridgeCurve" })
    let bridgeCurveUpdate = try #require(descriptors.first { $0.name == "setBridgeCurveParameters" })
    let curveOffset = try #require(descriptors.first { $0.name == "offsetCurve" })
    let regionOffset = try #require(descriptors.first { $0.name == "offsetRegions" })
    let sketchVertexOffset = try #require(descriptors.first { $0.name == "offsetSketchVertex" })
    let sketchCornerTreatment = try #require(descriptors.first { $0.name == "applySketchCornerTreatment" })
    let slotSketch = try #require(descriptors.first { $0.name == "createSlotSketch" })
    let revolve = try #require(descriptors.first { $0.name == "createRevolve" })
    let sweep = try #require(descriptors.first { $0.name == "createSweep" })
    let polySpline = try #require(descriptors.first { $0.name == "createPolySplineSurface" })
    let polySplineVertexMove = try #require(descriptors.first { $0.name == "movePolySplineSurfaceVertex" })
    let surfaceControlPointMove = try #require(descriptors.first { $0.name == "moveSurfaceControlPoint" })
    let polySplineVertexSlide = try #require(descriptors.first { $0.name == "slidePolySplineSurfaceVertices" })
    let surfaceControlPointSlide = try #require(descriptors.first { $0.name == "slideSurfaceControlPoints" })
    let polySplineAnalysis = try #require(descriptors.first { $0.name == "polySplineMeshAnalysis" })
    let splineMove = try #require(descriptors.first { $0.name == "moveSketchSplineControlPoint" })
    let splineSlide = try #require(descriptors.first { $0.name == "slideSketchSplineControlPoints" })
    let splineInsert = try #require(descriptors.first { $0.name == "insertSketchSplineControlPoint" })
    let splineConvert = try #require(descriptors.first { $0.name == "convertSketchLineToSpline" })
    let curveReverse = try #require(descriptors.first { $0.name == "reverseSketchCurve" })
    let curveRebuild = try #require(descriptors.first { $0.name == "rebuildSketchCurve" })
    let curveExtend = try #require(descriptors.first { $0.name == "extendSketchCurve" })
    let curveSplit = try #require(descriptors.first { $0.name == "splitSketchCurve" })
    let curveTrim = try #require(descriptors.first { $0.name == "trimSketchCurveSegment" })
    let curveCut = try #require(descriptors.first { $0.name == "cutSketchCurve" })
    let curveCurvatureDisplay = try #require(descriptors.first { $0.name == "setCurveCurvatureDisplay" })
    let pointDisplay = try #require(descriptors.first { $0.name == "setPointDisplay" })
    let sketchEntityDimension = try #require(descriptors.first { $0.name == "setSketchEntityDimension" })
    let objectDimension = try #require(descriptors.first { $0.name == "setObjectDimension" })
    let extrudeDistance = try #require(descriptors.first { $0.name == "setExtrudeDistance" })
    let cubeDimensions = try #require(descriptors.first { $0.name == "setCubeDimensions" })
    let cylinderDimensions = try #require(descriptors.first { $0.name == "setCylinderDimensions" })
    let selectionDimension = try #require(descriptors.first { $0.name == "addSelectionDimension" })
    let objectDimensionSummary = try #require(descriptors.first { $0.name == "objectDimensionSummary" })
    let sketchDimensionSummary = try #require(descriptors.first { $0.name == "sketchDimensionSummary" })
    let selectionMeasurement = try #require(descriptors.first { $0.name == "selectionMeasurement" })
    let selectionDimensionEvaluation = try #require(
        descriptors.first { $0.name == "selectionDimensionEvaluation" }
    )
    let sketchSummary = try #require(descriptors.first { $0.name == "sketchEntitySummary" })
    let curveAnalysis = try #require(descriptors.first { $0.name == "curveAnalysis" })
    let topology = try #require(descriptors.first { $0.name == "topologySummary" })
    let surfaceSourceSummary = try #require(descriptors.first { $0.name == "surfaceSourceSummary" })
    let surfaceAnalysis = try #require(descriptors.first { $0.name == "surfaceAnalysis" })
    let surfaceFrames = try #require(descriptors.first { $0.name == "surfaceFrames" })
    let surfaceContinuity = try #require(descriptors.first { $0.name == "surfaceContinuitySummary" })
    let snapResolution = try #require(descriptors.first { $0.name == "resolveSnap" })
    let constructionPlaneCreate = try #require(descriptors.first { $0.name == "createConstructionPlane" })
    let constructionPlaneCreateFromTarget = try #require(descriptors.first { $0.name == "createConstructionPlaneFromTarget" })
    let constructionPlaneCreateFromTargets = try #require(descriptors.first { $0.name == "createConstructionPlaneFromTargets" })
    let constructionPlaneCreateFromView = try #require(descriptors.first { $0.name == "createViewAlignedConstructionPlane" })
    let constructionPlaneSetActive = try #require(descriptors.first { $0.name == "setActiveConstructionPlane" })
    let constructionPlaneRename = try #require(descriptors.first { $0.name == "renameConstructionPlane" })
    let constructionPlaneSummary = try #require(descriptors.first { $0.name == "constructionPlaneSummary" })
    let componentInstance = try #require(descriptors.first { $0.name == "createComponentInstance" })
    let componentInstanceVisibility = try #require(
        descriptors.first { $0.name == "setComponentInstanceVisibility" }
    )
    let componentInstanceLock = try #require(
        descriptors.first { $0.name == "setComponentInstanceLock" }
    )
    let componentInstanceTransform = try #require(
        descriptors.first { $0.name == "setComponentInstanceTransform" }
    )
    let patternArray = try #require(descriptors.first { $0.name == "createPatternArray" })
    let patternArrayUpdate = try #require(descriptors.first { $0.name == "updatePatternArray" })
    let patternArrayExplode = try #require(descriptors.first { $0.name == "explodePatternArray" })
    let patternArraySummary = try #require(descriptors.first { $0.name == "patternArraySummary" })
    let designDisplaySnapshot = try #require(descriptors.first { $0.name == "designDisplaySnapshot" })
    let qualityAssessment = try #require(descriptors.first { $0.name == "cadInteractionQualityAssessment" })
    let selection = try #require(descriptors.first { $0.name == "selectTargets" })
    let createSketch = try #require(descriptors.first { $0.name == "createSketch" })

    #expect(fillet.category == .directEditing)
    #expect(fillet.mutatesDocument)
    #expect(fillet.access == .automationCommand)
    #expect(fillet.discovery.contains(.topologySummary))
    #expect(fillet.targets == [.edge])
    #expect(fillet.failureMode.contains("tangent-continuous"))

    #expect(faceOffset.category == .directEditing)
    #expect(faceOffset.discovery.contains(.topologySummary))
    #expect(faceOffset.targets == [.face])

    #expect(faceKnife.category == .directEditing)
    #expect(faceKnife.mutatesDocument)
    #expect(faceKnife.access == .automationCommand)
    #expect(faceKnife.discovery.contains(.topologySummary))
    #expect(faceKnife.discovery.contains(.snapResolution))
    #expect(faceKnife.targets == [.face])
    #expect(faceKnife.failureMode.contains("off-plane"))

    #expect(sketchConstraint.category == .sourceCurveEditing)
    #expect(sketchConstraint.discovery.contains(.sketchEntitySummary))
    #expect(sketchConstraint.targets == [.sketchEntity])
    #expect(sketchConstraint.failureMode.contains("spline control-point"))
    #expect(sketchConstraint.summary.contains("smooth spline"))
    #expect(sketchConstraint.summary.contains("spline endpoint tangency"))
    #expect(sketchConstraint.summary.contains("tangent spline endpoints"))
    #expect(sketchConstraint.summary.contains("smooth spline endpoints"))

    #expect(bridgeCurve.category == .sourceCurveEditing)
    #expect(bridgeCurve.mutatesDocument)
    #expect(bridgeCurve.discovery.contains(.sketchEntitySummary))
    #expect(bridgeCurve.discovery.contains(.curveAnalysis))
    #expect(bridgeCurve.targets == [.sketchEntity])
    #expect(bridgeCurve.summary.contains("bridge source curve"))
    #expect(bridgeCurve.summary.contains("endpoint-specific G0/G1/G2"))
    #expect(bridgeCurve.summary.contains("G3"))

    #expect(bridgeCurveUpdate.category == .sourceCurveEditing)
    #expect(bridgeCurveUpdate.mutatesDocument)
    #expect(bridgeCurveUpdate.discovery.contains(.sketchEntitySummary))
    #expect(bridgeCurveUpdate.discovery.contains(.curveAnalysis))
    #expect(bridgeCurveUpdate.targets == [.sketchEntity])
    #expect(bridgeCurveUpdate.summary.contains("preserving the generated spline entity ID"))
    #expect(bridgeCurveUpdate.summary.contains("endpoint-specific G0/G1/G2"))

    #expect(curveOffset.category == .sourceCurveEditing)
    #expect(curveOffset.mutatesDocument)
    #expect(curveOffset.access == .automationCommand)
    #expect(curveOffset.discovery.contains(.sketchEntitySummary))
    #expect(curveOffset.discovery.contains(.topologySummary))
    #expect(curveOffset.discovery.contains(.snapResolution))
    #expect(curveOffset.targets == [.sketchEntity, .region, .face, .edge, .vertex])
    #expect(curveOffset.summary.contains("Offset Curve"))
    #expect(curveOffset.summary.contains("symmetric"))
    #expect(curveOffset.summary.contains("gap-fill"))
    #expect(curveOffset.summary.contains("region targets"))
    #expect(curveOffset.summary.contains("line-chain"))
    #expect(curveOffset.summary.contains("line/arc chain"))
    #expect(curveOffset.summary.contains("session selection contains the edge target"))
    #expect(curveOffset.summary.contains("selected edge lies on exactly one generated start/end cap face"))
    #expect(curveOffset.failureMode.contains("face-loop"))
    #expect(curveOffset.failureMode.contains("source point"))
    #expect(curveOffset.failureMode.contains("spline"))
    #expect(curveOffset.failureMode.contains("region offsets"))
    #expect(curveOffset.failureMode.contains("vertex dispatch"))
    #expect(curveOffset.failureMode.contains("symmetric circular"))
    #expect(curveOffset.failureMode.contains("branched"))

    #expect(regionOffset.category == .sourceCurveEditing)
    #expect(regionOffset.mutatesDocument)
    #expect(regionOffset.access == .automationCommand)
    #expect(regionOffset.discovery.contains(.sketchEntitySummary))
    #expect(regionOffset.targets == [.region])
    #expect(regionOffset.summary.contains("multiple selected source profile regions"))
    #expect(regionOffset.failureMode.contains("polygon union"))

    #expect(sketchVertexOffset.category == .sourceCurveEditing)
    #expect(sketchVertexOffset.mutatesDocument)
    #expect(sketchVertexOffset.discovery.contains(.sketchEntitySummary))
    #expect(sketchVertexOffset.targets == [.sketchEntity])
    #expect(sketchVertexOffset.summary.contains("line/arc sketch corner"))
    #expect(sketchVertexOffset.failureMode.contains("horizontal/vertical"))

    #expect(sketchCornerTreatment.category == .sourceCurveEditing)
    #expect(sketchCornerTreatment.mutatesDocument)
    #expect(sketchCornerTreatment.access == .automationCommand)
    #expect(sketchCornerTreatment.discovery.contains(.sketchEntitySummary))
    #expect(sketchCornerTreatment.discovery.contains(.snapResolution))
    #expect(sketchCornerTreatment.targets == [.sketchEntity])
    #expect(sketchCornerTreatment.summary.contains("circular arc"))
    #expect(sketchCornerTreatment.summary.contains("line/arc endpoint"))
    #expect(sketchCornerTreatment.failureMode.contains("non-line/arc corners"))

    #expect(slotSketch.category == .sourceCurveEditing)
    #expect(slotSketch.mutatesDocument)
    #expect(slotSketch.discovery.contains(.sketchEntitySummary))
    #expect(slotSketch.discovery.contains(.curveAnalysis))
    #expect(slotSketch.targets == [.sketchEntity])
    #expect(slotSketch.summary.contains("tangent semicircular arcs"))
    #expect(slotSketch.summary.contains("line-chain"))
    #expect(slotSketch.summary.contains("open source arc"))
    #expect(slotSketch.summary.contains("line/arc chain"))
    #expect(slotSketch.failureMode.contains("branched line/arc chain"))
    #expect(slotSketch.failureMode.contains("disconnected line/arc"))
    #expect(slotSketch.failureMode.contains("inner radius"))

    #expect(createSketch.category == .sketch)
    #expect(createSketch.mutatesDocument)
    #expect(createSketch.targets == [.document])
    #expect(createSketch.summary.contains("multi-entity curve chains"))
    #expect(createSketch.failureMode.contains("disconnected"))
    #expect(createSketch.failureMode.contains("branched"))

    #expect(revolve.category == .solid)
    #expect(revolve.mutatesDocument)
    #expect(revolve.access == .automationCommand)
    #expect(revolve.discovery.contains(.sketchEntitySummary))
    #expect(revolve.discovery.contains(.topologySummary))
    #expect(revolve.targets == [.profile])
    #expect(revolve.summary.contains("explicit 3D axis"))
    #expect(revolve.failureMode.contains("over-full-turn angles"))
    #expect(revolve.failureMode.contains("profile plane"))
    #expect(revolve.failureMode.contains("surface-of-revolution"))
    #expect(revolve.optionMatrix.map(\.name) == ["axis", "angle"])
    let revolveAxis = try #require(revolve.optionMatrix.first { $0.name == "axis" })
    #expect(revolveAxis.supportedValues == ["explicit 3D line lying in the profile plane"])
    #expect(revolveAxis.notes.contains { $0.contains("one side") })
    let revolveAngleAxis = try #require(revolve.optionMatrix.first { $0.name == "angle" })
    #expect(revolveAngleAxis.supportedValues == ["nonzero angle up to 360 degrees"])
    #expect(revolveAngleAxis.notes.contains { $0.contains("partial angles") })

    #expect(sweep.category == .solid)
    #expect(sweep.mutatesDocument)
    #expect(sweep.access == .automationCommand)
    #expect(sweep.discovery.contains(.sketchEntitySummary))
    #expect(sweep.targets.contains(.profile))
    #expect(sweep.targets.contains(.sketchEntity))
    #expect(sweep.targets.contains(.body))
    #expect(sweep.failureMode.contains("profile-plane degenerate parallel alignment"))
    #expect(sweep.failureMode.contains("solid output from curve sections"))
    #expect(sweep.failureMode.contains("disconnected or branched open path chains"))
    #expect(sweep.failureMode.contains("round corner style on multi-curve paths"))
    #expect(sweep.failureMode.contains("shared typed sweep evaluation contract"))
    #expect(sweep.failureMode.contains("path-normal section sweep"))
    #expect(sweep.failureMode.contains("profile-plane-preserving exact extrusion"))
    #expect(sweep.failureMode.contains("straight-path parallel transformed or guided sections"))
    #expect(sweep.failureMode.contains("profile-plane parallel section sweep"))
    #expect(sweep.failureMode.contains("curve sections as new-body sheet sweeps"))
    #expect(sweep.failureMode.contains("profile-plane guide projection"))
    #expect(sweep.failureMode.contains("compatible multiple point/chord"))
    #expect(sweep.failureMode.contains("non-uniform affine, signed-axis, convex quadrilateral bilinear, and convex mean-value cage point-guide rail deformation"))
    #expect(sweep.failureMode.contains("conflicting signed-axis rail guides"))
    #expect(sweep.failureMode.contains("flipped or self-intersecting bilinear quadrilateral or mean-value cage rail guides"))
    #expect(sweep.failureMode.contains("curve-guide contact"))
    #expect(sweep.failureMode.contains("exact swept-sheet side surfaces"))
    #expect(sweep.failureMode.contains("connected open curved or multi-curve paths"))
    #expect(sweep.failureMode.contains("polygonal swept-sheet"))
    #expect(sweep.failureMode.contains("targetless boolean"))
    #expect(sweep.failureMode.contains("boolean target operations with sheet output"))
    #expect(sweep.failureMode.contains("z-through rectangular-frame"))
    #expect(sweep.failureMode.contains("overconstrained guide sets"))
    #expect(sweep.failureMode.contains("unsupported evaluation"))
    #expect(sweep.optionMatrix.map(\.name) == [
        "alignment",
        "guideMethod",
        "booleanOperation",
        "resultKind",
        "cornerStyle",
        "simplify",
    ])
    let sweepGuideAxis = try #require(sweep.optionMatrix.first { $0.name == "guideMethod" })
    let sweepBooleanAxis = try #require(sweep.optionMatrix.first { $0.name == "booleanOperation" })
    let sweepResultAxis = try #require(sweep.optionMatrix.first { $0.name == "resultKind" })
    let sweepCornerAxis = try #require(sweep.optionMatrix.first { $0.name == "cornerStyle" })
    let sweepSimplifyAxis = try #require(sweep.optionMatrix.first { $0.name == "simplify" })
    #expect(sweepGuideAxis.supportedValues == ["point", "chord", "curve"])
    #expect(sweepGuideAxis.notes.contains { $0.contains("mean-value cage rail deformation") })
    #expect(sweepGuideAxis.notes.contains { $0.contains("radial point rail deformation") })
    #expect(sweepBooleanAxis.supportedValues == ["newBody", "union", "difference", "intersect", "slice"])
    #expect(sweepBooleanAxis.notes.contains { $0.contains("solid resultKind") })
    #expect(sweepResultAxis.supportedValues == ["solid", "sheet"])
    #expect(sweepResultAxis.notes.contains { $0.contains("new-body outputs only") })
    #expect(sweepCornerAxis.supportedValues == ["mitre", "round"])
    #expect(sweepCornerAxis.notes.contains { $0.contains("multi-curve path chains") })
    #expect(sweepCornerAxis.notes.contains { $0.contains("single-curve paths only") })
    #expect(sweepSimplifyAxis.supportedValues == ["false"])

    #expect(polySpline.category == .solid)
    #expect(polySpline.mutatesDocument)
    #expect(polySpline.access == .automationCommand)
    #expect(polySpline.discovery.contains(.meshSummary))
    #expect(polySpline.discovery.contains(.topologySummary))
    #expect(polySpline.discovery.contains(.surfaceAnalysis))
    #expect(polySpline.discovery.contains(.surfaceContinuitySummary))
    #expect(polySpline.targets == [.document])
    #expect(polySpline.failureMode.contains("planar unmerged quad patch network"))
    #expect(polySpline.failureMode.contains("cubic B-spline sheet topology"))
    #expect(polySpline.failureMode.contains("rounded-corner"))
    #expect(polySpline.discovery.contains(.polySplineMeshAnalysis))

    #expect(polySplineVertexMove.category == .solid)
    #expect(polySplineVertexMove.mutatesDocument)
    #expect(polySplineVertexMove.access == .automationCommand)
    #expect(polySplineVertexMove.discovery.contains(.topologySummary))
    #expect(polySplineVertexMove.discovery.contains(.surfaceAnalysis))
    #expect(polySplineVertexMove.discovery.contains(.surfaceContinuitySummary))
    #expect(polySplineVertexMove.targets == [.vertex])
    #expect(polySplineVertexMove.summary.contains("source mesh vertex"))
    #expect(polySplineVertexMove.failureMode.contains("selected boundary role"))

    #expect(surfaceControlPointMove.category == .solid)
    #expect(surfaceControlPointMove.mutatesDocument)
    #expect(surfaceControlPointMove.access == .automationCommand)
    #expect(surfaceControlPointMove.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceControlPointMove.discovery.contains(.selectionMeasurement))
    #expect(surfaceControlPointMove.discovery.contains(.surfaceAnalysis))
    #expect(surfaceControlPointMove.discovery.contains(.surfaceContinuitySummary))
    #expect(surfaceControlPointMove.targets == [.surfaceControlPoint])
    #expect(surfaceControlPointMove.summary.contains("SelectionReference"))
    #expect(surfaceControlPointMove.failureMode.contains("strict interior B-spline control point"))

    #expect(polySplineVertexSlide.category == .solid)
    #expect(polySplineVertexSlide.mutatesDocument)
    #expect(polySplineVertexSlide.access == .automationCommand)
    #expect(polySplineVertexSlide.discovery.contains(.topologySummary))
    #expect(polySplineVertexSlide.discovery.contains(.surfaceAnalysis))
    #expect(polySplineVertexSlide.discovery.contains(.surfaceContinuitySummary))
    #expect(polySplineVertexSlide.targets == [.vertex])
    #expect(polySplineVertexSlide.summary.contains("local surface hull U, V, or normal"))
    #expect(polySplineVertexSlide.failureMode.contains("duplicate source-vertex targets"))

    #expect(surfaceControlPointSlide.category == .solid)
    #expect(surfaceControlPointSlide.mutatesDocument)
    #expect(surfaceControlPointSlide.access == .automationCommand)
    #expect(surfaceControlPointSlide.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceControlPointSlide.discovery.contains(.selectionMeasurement))
    #expect(surfaceControlPointSlide.discovery.contains(.surfaceAnalysis))
    #expect(surfaceControlPointSlide.discovery.contains(.surfaceContinuitySummary))
    #expect(surfaceControlPointSlide.targets == [.surfaceControlPoint])
    #expect(surfaceControlPointSlide.summary.contains("SelectionReference"))
    #expect(surfaceControlPointSlide.failureMode.contains("duplicate targets"))

    #expect(polySplineAnalysis.category == .read)
    #expect(!polySplineAnalysis.mutatesDocument)
    #expect(polySplineAnalysis.access == .agentRequest)
    #expect(polySplineAnalysis.discovery.contains(.polySplineMeshAnalysis))
    #expect(polySplineAnalysis.targets == [.document])
    #expect(polySplineAnalysis.failureMode.contains("structured diagnostics"))

    #expect(splineMove.category == .sourceCurveEditing)
    #expect(splineMove.discovery.contains(.sketchEntitySummary))
    #expect(splineMove.targets == [.sketchEntity])
    #expect(splineMove.failureMode.contains("out-of-range"))

    #expect(splineSlide.category == .sourceCurveEditing)
    #expect(splineSlide.mutatesDocument)
    #expect(splineSlide.discovery.contains(.sketchEntitySummary))
    #expect(splineSlide.targets == [.sketchEntity])
    #expect(splineSlide.summary.contains("Slide Curve CV"))
    #expect(splineSlide.summary.contains("Positive U"))
    #expect(splineSlide.failureMode.contains("collapsed control-cage"))

    #expect(splineInsert.category == .sourceCurveEditing)
    #expect(splineInsert.mutatesDocument)
    #expect(splineInsert.discovery.contains(.sketchEntitySummary))
    #expect(splineInsert.targets == [.sketchEntity])
    #expect(splineInsert.summary.contains("Insert CV"))
    #expect(splineInsert.failureMode.contains("existing-knot"))
    #expect(splineInsert.failureMode.contains("replaced-handle"))

    #expect(splineConvert.category == .sourceCurveEditing)
    #expect(splineConvert.mutatesDocument)
    #expect(splineConvert.discovery.contains(.sketchEntitySummary))
    #expect(splineConvert.targets == [.sketchEntity])
    #expect(splineConvert.failureMode.contains("endpoint fixed"))
    #expect(splineConvert.failureMode.contains("line-specific"))
    #expect(splineConvert.failureMode.contains("spline endpoint tangent"))

    #expect(curveReverse.category == .sourceCurveEditing)
    #expect(curveReverse.mutatesDocument)
    #expect(curveReverse.access == .automationCommand)
    #expect(curveReverse.discovery.contains(.sketchEntitySummary))
    #expect(curveReverse.targets == [.sketchEntity])
    #expect(curveReverse.summary.contains("Reverse"))
    #expect(curveReverse.failureMode.contains("bridge curve metadata"))
    #expect(curveReverse.failureMode.contains("arc"))

    #expect(curveRebuild.category == .sourceCurveEditing)
    #expect(curveRebuild.mutatesDocument)
    #expect(curveRebuild.access == .automationCommand)
    #expect(curveRebuild.discovery.contains(.sketchEntitySummary))
    #expect(curveRebuild.discovery.contains(.curveAnalysis))
    #expect(curveRebuild.targets == [.sketchEntity])
    #expect(curveRebuild.summary.contains("Rebuild Curve"))
    #expect(curveRebuild.summary.contains("Points"))
    #expect(curveRebuild.summary.contains("Refit"))
    #expect(curveRebuild.summary.contains("degree-3 Explicit Control"))
    #expect(curveRebuild.summary.contains("Keep Corners"))
    #expect(curveRebuild.summary.contains("weighted explicit spans"))
    #expect(curveRebuild.summary.contains("analytic cubic Bezier deviation report"))
    #expect(curveRebuild.failureMode.contains("internal control-point"))
    #expect(curveRebuild.failureMode.contains("non-cubic Explicit Control"))
    #expect(curveRebuild.failureMode.contains("tolerance"))

    #expect(curveExtend.category == .sourceCurveEditing)
    #expect(curveExtend.mutatesDocument)
    #expect(curveExtend.access == .automationCommand)
    #expect(curveExtend.discovery.contains(.sketchEntitySummary))
    #expect(curveExtend.targets == [.sketchEntity])
    #expect(curveExtend.summary.contains("Extend Curve"))
    #expect(curveExtend.summary.contains("endpoint"))
    #expect(curveExtend.failureMode.contains("non-endpoint targets"))
    #expect(curveExtend.failureMode.contains("target-dependent"))

    #expect(curveSplit.category == .sourceCurveEditing)
    #expect(curveSplit.mutatesDocument)
    #expect(curveSplit.access == .automationCommand)
    #expect(curveSplit.discovery.contains(.sketchEntitySummary))
    #expect(curveSplit.targets == [.sketchEntity])
    #expect(curveSplit.summary.contains("Split Segment"))
    #expect(curveSplit.summary.contains("source arc"))
    #expect(curveSplit.failureMode.contains("Bridge Curve"))
    #expect(curveSplit.failureMode.contains("circular constraints"))
    #expect(curveSplit.failureMode.contains("internal control-point"))

    #expect(curveTrim.category == .sourceCurveEditing)
    #expect(curveTrim.mutatesDocument)
    #expect(curveTrim.access == .automationCommand)
    #expect(curveTrim.discovery.contains(.sketchEntitySummary))
    #expect(curveTrim.targets == [.sketchEntity])
    #expect(curveTrim.summary.contains("Trim"))
    #expect(curveTrim.failureMode.contains("Bridge Curve"))
    #expect(curveTrim.failureMode.contains("Cut Curve"))

    #expect(curveCut.category == .sourceCurveEditing)
    #expect(curveCut.mutatesDocument)
    #expect(curveCut.access == .automationCommand)
    #expect(curveCut.discovery.contains(.sketchEntitySummary))
    #expect(curveCut.targets == [.sketchEntity])
    #expect(curveCut.summary.contains("Cut Curve"))
    #expect(curveCut.summary.contains("source line"))
    #expect(curveCut.summary.contains("source arc"))
    #expect(curveCut.summary.contains("source circle"))
    #expect(curveCut.summary.contains("circle"))
    #expect(curveCut.summary.contains("arc"))
    #expect(curveCut.failureMode.contains("extendsCutter"))
    #expect(curveCut.failureMode.contains("non-line/non-arc/non-circle targets"))
    #expect(curveCut.failureMode.contains("arc-cutter extension"))
    #expect(curveCut.failureMode.contains("coincident circular"))
    #expect(curveCut.failureMode.contains("screen-space"))

    #expect(curveCurvatureDisplay.category == .sourceCurveEditing)
    #expect(curveCurvatureDisplay.mutatesDocument)
    #expect(curveCurvatureDisplay.access == .automationCommand)
    #expect(curveCurvatureDisplay.discovery.contains(.sketchEntitySummary))
    #expect(curveCurvatureDisplay.discovery.contains(.curveAnalysis))
    #expect(curveCurvatureDisplay.targets == [.sketchEntity])
    #expect(curveCurvatureDisplay.summary.contains("curvature-comb display"))
    #expect(curveCurvatureDisplay.failureMode.contains("source points"))
    #expect(curveCurvatureDisplay.failureMode.contains("non-positive comb scales"))

    #expect(pointDisplay.category == .sourceCurveEditing)
    #expect(pointDisplay.mutatesDocument)
    #expect(pointDisplay.access == .automationCommand)
    #expect(pointDisplay.discovery.contains(.sketchEntitySummary))
    #expect(pointDisplay.targets == [.sketchEntity])
    #expect(pointDisplay.summary.contains("point display"))
    #expect(pointDisplay.failureMode.contains("standalone point"))

    #expect(sketchEntityDimension.category == .sourceCurveEditing)
    #expect(sketchEntityDimension.mutatesDocument)
    #expect(sketchEntityDimension.discovery.contains(.sketchEntitySummary))
    #expect(sketchEntityDimension.discovery.contains(.sketchDimensionSummary))
    #expect(sketchEntityDimension.targets == [.sketchEntity])

    #expect(objectDimension.category == .solid)
    #expect(objectDimension.mutatesDocument)
    #expect(objectDimension.access == .automationCommand)
    #expect(objectDimension.discovery.contains(.topologySummary))
    #expect(objectDimension.discovery.contains(.objectDimensionSummary))
    #expect(objectDimension.targets == [.body, .face, .edge])

    #expect(extrudeDistance.category == .solid)
    #expect(extrudeDistance.mutatesDocument)
    #expect(extrudeDistance.access == .automationCommand)
    #expect(extrudeDistance.discovery.contains(.patternArraySummary))
    #expect(extrudeDistance.discovery.contains(.designDisplaySnapshot))
    #expect(extrudeDistance.targets == [.body, .sceneNode])
    #expect(extrudeDistance.summary.contains("independent-copy"))
    #expect(extrudeDistance.failureMode.contains("non-extrude"))
    let extrudeFeatureIDAxis = try #require(extrudeDistance.optionMatrix.first { $0.name == "featureIDDiscovery" })
    #expect(extrudeFeatureIDAxis.supportedValues.contains("patternArraySummary.independentCopyOutputs.featureIDs"))
    #expect(extrudeFeatureIDAxis.supportedValues.contains("designDisplaySnapshot.extrudes.featureID"))

    #expect(cubeDimensions.category == .solid)
    #expect(cubeDimensions.mutatesDocument)
    #expect(cubeDimensions.access == .automationCommand)
    #expect(cubeDimensions.discovery.contains(.patternArraySummary))
    #expect(cubeDimensions.discovery.contains(.designDisplaySnapshot))
    #expect(cubeDimensions.discovery.contains(.objectDimensionSummary))
    #expect(cubeDimensions.targets == [.body, .sceneNode])
    #expect(cubeDimensions.summary.contains("independent-copy"))
    #expect(cubeDimensions.failureMode.contains("non-rectangle"))
    let cubeFeatureIDAxis = try #require(cubeDimensions.optionMatrix.first { $0.name == "featureIDDiscovery" })
    #expect(cubeFeatureIDAxis.supportedValues.contains("patternArraySummary.independentCopyOutputs.featureIDs"))
    #expect(cubeFeatureIDAxis.supportedValues.contains("designDisplaySnapshot.extrudes.featureID"))

    #expect(cylinderDimensions.category == .solid)
    #expect(cylinderDimensions.mutatesDocument)
    #expect(cylinderDimensions.access == .automationCommand)
    #expect(cylinderDimensions.discovery.contains(.patternArraySummary))
    #expect(cylinderDimensions.discovery.contains(.designDisplaySnapshot))
    #expect(cylinderDimensions.discovery.contains(.objectDimensionSummary))
    #expect(cylinderDimensions.targets == [.body, .sceneNode])
    #expect(cylinderDimensions.summary.contains("independent-copy"))
    #expect(cylinderDimensions.failureMode.contains("non-circle"))
    let cylinderFeatureIDAxis = try #require(cylinderDimensions.optionMatrix.first { $0.name == "featureIDDiscovery" })
    #expect(cylinderFeatureIDAxis.supportedValues.contains("patternArraySummary.independentCopyOutputs.featureIDs"))
    #expect(cylinderFeatureIDAxis.supportedValues.contains("designDisplaySnapshot.extrudes.featureID"))

    #expect(selectionDimension.category == .solid)
    #expect(selectionDimension.mutatesDocument)
    #expect(selectionDimension.access == .automationCommand)
    #expect(selectionDimension.discovery.contains(.selectionDimensionEvaluation))
    #expect(selectionDimension.discovery.contains(.topologySummary))
    #expect(selectionDimension.discovery.contains(.sketchEntitySummary))
    #expect(selectionDimension.targets == [.face, .edge, .vertex, .sketchEntity, .sketchPointHandle])
    #expect(selectionDimension.summary.contains("SwiftCAD document source") || selectionDimension.summary.contains("CAD selection dimension"))

    #expect(selectionMeasurement.category == .read)
    #expect(!selectionMeasurement.mutatesDocument)
    #expect(selectionMeasurement.access == .agentRequest)
    #expect(selectionMeasurement.discovery.contains(.selectionMeasurement))
    #expect(selectionMeasurement.discovery.contains(.surfaceSourceSummary))
    #expect(selectionMeasurement.discovery.contains(.topologySummary))
    #expect(selectionMeasurement.targets.contains(.surfaceControlPoint))
    #expect(selectionMeasurement.targets.contains(.surfaceTrim))
    #expect(selectionMeasurement.summary.contains("SelectionReference"))

    #expect(objectDimensionSummary.category == .read)
    #expect(!objectDimensionSummary.mutatesDocument)
    #expect(objectDimensionSummary.access == .agentRequest)
    #expect(objectDimensionSummary.discovery.contains(.objectDimensionSummary))
    #expect(objectDimensionSummary.discovery.contains(.topologySummary))
    #expect(objectDimensionSummary.targets == [.body, .face, .edge])
    #expect(objectDimensionSummary.summary.contains("Dimension command candidates"))

    #expect(sketchDimensionSummary.category == .read)
    #expect(!sketchDimensionSummary.mutatesDocument)
    #expect(sketchDimensionSummary.access == .agentRequest)
    #expect(sketchDimensionSummary.discovery.contains(.sketchDimensionSummary))
    #expect(sketchDimensionSummary.discovery.contains(.sketchEntitySummary))
    #expect(sketchDimensionSummary.discovery.contains(.topologySummary))
    #expect(sketchDimensionSummary.targets == [.sketchEntity, .edge])
    #expect(sketchDimensionSummary.summary.contains("Dimension command candidates"))

    #expect(selectionDimensionEvaluation.category == .read)
    #expect(!selectionDimensionEvaluation.mutatesDocument)
    #expect(selectionDimensionEvaluation.access == .agentRequest)
    #expect(selectionDimensionEvaluation.discovery.contains(.selectionDimensionEvaluation))
    #expect(selectionDimensionEvaluation.targets == [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle])

    #expect(topology.category == .read)
    #expect(!topology.mutatesDocument)
    #expect(topology.access == .agentRequest)
    #expect(topology.targets == [.face, .edge, .vertex])

    #expect(surfaceSourceSummary.category == .read)
    #expect(!surfaceSourceSummary.mutatesDocument)
    #expect(surfaceSourceSummary.access == .agentRequest)
    #expect(surfaceSourceSummary.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceSourceSummary.discovery.contains(.polySplineMeshAnalysis))
    #expect(surfaceSourceSummary.discovery.contains(.topologySummary))
    #expect(surfaceSourceSummary.targets == [.document, .body, .face, .edge, .vertex])
    #expect(surfaceSourceSummary.summary.contains("source-owned surface contracts"))
    #expect(surfaceSourceSummary.summary.contains("boundary CV targets"))

    #expect(surfaceAnalysis.category == .read)
    #expect(!surfaceAnalysis.mutatesDocument)
    #expect(surfaceAnalysis.access == .agentRequest)
    #expect(surfaceAnalysis.discovery.contains(.topologySummary))
    #expect(surfaceAnalysis.discovery.contains(.surfaceAnalysis))
    #expect(surfaceAnalysis.targets == [.face, .edge])
    #expect(surfaceAnalysis.summary.contains("curvature comb"))
    #expect(surfaceAnalysis.summary.contains("sample density"))
    #expect(surfaceAnalysis.summary.contains("trim-boundary"))
    #expect(surfaceAnalysis.failureMode.contains("unbounded B-spline"))

    #expect(surfaceFrames.category == .read)
    #expect(!surfaceFrames.mutatesDocument)
    #expect(surfaceFrames.access == .agentRequest)
    #expect(surfaceFrames.discovery.contains(.topologySummary))
    #expect(surfaceFrames.discovery.contains(.surfaceFrames))
    #expect(surfaceFrames.targets == [.face])
    #expect(surfaceFrames.summary.contains("UVN local frames"))
    #expect(surfaceFrames.failureMode.contains("face persistent names"))

    #expect(surfaceContinuity.category == .read)
    #expect(!surfaceContinuity.mutatesDocument)
    #expect(surfaceContinuity.access == .agentRequest)
    #expect(surfaceContinuity.discovery.contains(.topologySummary))
    #expect(surfaceContinuity.discovery.contains(.surfaceContinuitySummary))
    #expect(surfaceContinuity.targets == [.face, .edge])
    #expect(surfaceContinuity.failureMode.contains("unresolved curvature continuity"))

    #expect(snapResolution.category == .read)
    #expect(!snapResolution.mutatesDocument)
    #expect(snapResolution.access == .agentRequest)
    #expect(snapResolution.discovery.contains(.snapResolution))
    #expect(snapResolution.discovery.contains(.sketchEntitySummary))
    #expect(snapResolution.discovery.contains(.topologySummary))
    #expect(snapResolution.targets == [.document, .sceneNode, .profile, .region, .sketchEntity])
    #expect(snapResolution.failureMode.contains("object-targeting force enable"))
    #expect(snapResolution.failureMode.contains("candidate-kind suppression"))
    #expect(snapResolution.summary.contains("curve-axis"))
    #expect(snapResolution.summary.contains("curve-coordinate-plane"))

    #expect(constructionPlaneCreate.category == .sketch)
    #expect(constructionPlaneCreate.mutatesDocument)
    #expect(constructionPlaneCreate.access == .automationCommand)
    #expect(constructionPlaneCreate.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneCreate.targets == [.document])
    #expect(constructionPlaneCreate.failureMode.contains("invalid plane"))

    #expect(constructionPlaneCreateFromTarget.category == .sketch)
    #expect(constructionPlaneCreateFromTarget.mutatesDocument)
    #expect(constructionPlaneCreateFromTarget.access == .automationCommand)
    #expect(constructionPlaneCreateFromTarget.discovery.contains(.topologySummary))
    #expect(constructionPlaneCreateFromTarget.discovery.contains(.sketchEntitySummary))
    #expect(constructionPlaneCreateFromTarget.discovery.contains(.selectionState))
    #expect(constructionPlaneCreateFromTarget.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneCreateFromTarget.targets == [.face, .region, .constructionPlane])
    #expect(constructionPlaneCreateFromTarget.failureMode.contains("non-face/non-region"))

    #expect(constructionPlaneCreateFromTargets.category == .sketch)
    #expect(constructionPlaneCreateFromTargets.mutatesDocument)
    #expect(constructionPlaneCreateFromTargets.access == .automationCommand)
    #expect(constructionPlaneCreateFromTargets.discovery.contains(.topologySummary))
    #expect(constructionPlaneCreateFromTargets.discovery.contains(.sketchEntitySummary))
    #expect(constructionPlaneCreateFromTargets.discovery.contains(.selectionState))
    #expect(constructionPlaneCreateFromTargets.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneCreateFromTargets.targets == [
        .face,
        .edge,
        .vertex,
        .region,
        .sketchEntity,
        .sketchPointHandle,
        .sketchControlPoint,
        .constructionPlane,
    ])
    #expect(constructionPlaneCreateFromTargets.failureMode.contains("nonparallel"))
    #expect(constructionPlaneCreateFromTargets.failureMode.contains("non-opposing"))
    #expect(constructionPlaneCreateFromTargets.failureMode.contains("view normal"))
    #expect(constructionPlaneCreateFromTargets.summary.contains("sketch point handles"))
    #expect(constructionPlaneCreateFromTargets.summary.contains("spline control points"))

    #expect(constructionPlaneCreateFromView.category == .sketch)
    #expect(constructionPlaneCreateFromView.mutatesDocument)
    #expect(constructionPlaneCreateFromView.access == .automationCommand)
    #expect(constructionPlaneCreateFromView.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneCreateFromView.targets == [.document])
    #expect(constructionPlaneCreateFromView.summary.contains("view normal"))
    #expect(constructionPlaneCreateFromView.failureMode.contains("non-finite view normals"))

    #expect(constructionPlaneSetActive.category == .sketch)
    #expect(constructionPlaneSetActive.mutatesDocument)
    #expect(constructionPlaneSetActive.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneSetActive.targets == [.constructionPlane])

    #expect(constructionPlaneRename.category == .sketch)
    #expect(constructionPlaneRename.mutatesDocument)
    #expect(constructionPlaneRename.access == .automationCommand)
    #expect(constructionPlaneRename.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneRename.targets == [.constructionPlane])
    #expect(constructionPlaneRename.failureMode.contains("duplicate names"))

    #expect(constructionPlaneSummary.category == .read)
    #expect(!constructionPlaneSummary.mutatesDocument)
    #expect(constructionPlaneSummary.access == .agentRequest)
    #expect(constructionPlaneSummary.discovery.contains(.constructionPlaneSummary))
    #expect(constructionPlaneSummary.targets == [.constructionPlane])

    #expect(componentInstance.category == .component)
    #expect(componentInstance.mutatesDocument)
    #expect(componentInstance.access == .automationCommand)
    #expect(componentInstance.discovery.contains(.designDisplaySnapshot))
    #expect(componentInstance.targets == [.sceneNode])
    #expect(componentInstance.failureMode.contains("duplicate names"))
    let componentDefinitionAxis = try #require(componentInstance.optionMatrix.first { $0.name == "definitionID" })
    #expect(componentDefinitionAxis.supportedValues == ["designDisplaySnapshot.componentDefinitions"])
    #expect(componentDefinitionAxis.notes.contains {
        $0.contains("designDisplaySnapshot.componentInstances")
    })
    #expect(componentDefinitionAxis.notes.contains {
        $0.contains("ownership.kind")
    })

    for descriptor in [componentInstanceVisibility, componentInstanceLock, componentInstanceTransform] {
        #expect(descriptor.category == .component)
        #expect(descriptor.mutatesDocument)
        #expect(descriptor.access == .automationCommand)
        #expect(descriptor.discovery.contains(.designDisplaySnapshot))
        #expect(descriptor.targets == [.componentInstance])
        #expect(descriptor.summary.contains("document-owned component instance"))
        #expect(descriptor.failureMode.contains("pattern-owned output instances"))
        let componentInstanceAxis = try #require(
            descriptor.optionMatrix.first { $0.name == "componentInstanceID" }
        )
        #expect(componentInstanceAxis.supportedValues == ["designDisplaySnapshot.componentInstances"])
        #expect(componentInstanceAxis.notes.contains {
            $0.contains("ownership.kind is document")
        })
        #expect(componentInstanceAxis.notes.contains {
            $0.contains("explodePatternArray")
        })
    }

    #expect(patternArray.category == .pattern)
    #expect(patternArray.mutatesDocument)
    #expect(patternArray.access == .automationCommand)
    #expect(patternArray.discovery.contains(.designDisplaySnapshot))
    #expect(patternArray.targets == [.sceneNode])
    #expect(patternArray.summary.contains("component instances"))
    #expect(patternArray.summary.contains("rectangular"))
    #expect(patternArray.summary.contains("radial"))
    #expect(patternArray.summary.contains("curve"))
    #expect(patternArray.optionMatrix.map(\.name) == [
        "distribution",
        "spacingMode",
        "axisCount",
        "curveAlignment",
        "outputMode",
    ])
    let distributionMode = try #require(
        patternArray.optionMatrix.first { $0.name == "distribution" }
    )
    let spacingMode = try #require(
        patternArray.optionMatrix.first { $0.name == "spacingMode" }
    )
    let patternOutputMode = try #require(
        patternArray.optionMatrix.first { $0.name == "outputMode" }
    )
    let curveAlignment = try #require(
        patternArray.optionMatrix.first { $0.name == "curveAlignment" }
    )
    #expect(distributionMode.supportedValues == ["rectangular", "radial", "curve"])
    #expect(spacingMode.supportedValues == ["spacing", "extent"])
    #expect(curveAlignment.supportedValues == ["normal", "parallel", "transport"])
    #expect(patternOutputMode.supportedValues == ["componentInstance", "independentCopy"])
    #expect(patternOutputMode.notes.contains {
        $0.contains("designDisplaySnapshot.componentDefinitions")
    })

    #expect(patternArrayUpdate.category == .pattern)
    #expect(patternArrayUpdate.mutatesDocument)
    #expect(patternArrayUpdate.discovery.contains(.designDisplaySnapshot))
    #expect(patternArrayUpdate.targets == [.sceneNode])
    #expect(patternArrayUpdate.optionMatrix.map(\.name) == [
        "editableFields",
        "distribution",
        "spacingMode",
        "axisCount",
        "curveAlignment",
        "outputMode",
    ])
    let updateDistribution = try #require(
        patternArrayUpdate.optionMatrix.first { $0.name == "distribution" }
    )
    let updateCurveAlignment = try #require(
        patternArrayUpdate.optionMatrix.first { $0.name == "curveAlignment" }
    )
    #expect(updateDistribution.supportedValues == ["rectangular", "radial", "curve"])
    #expect(updateCurveAlignment.supportedValues == ["normal", "parallel", "transport"])

    #expect(patternArrayExplode.category == .pattern)
    #expect(patternArrayExplode.mutatesDocument)
    #expect(patternArrayExplode.discovery.contains(.designDisplaySnapshot))
    #expect(patternArrayExplode.targets == [.sceneNode])
    #expect(patternArrayExplode.summary.contains("materialized"))

    #expect(patternArraySummary.category == .read)
    #expect(!patternArraySummary.mutatesDocument)
    #expect(patternArraySummary.access == .agentRequest)
    #expect(patternArraySummary.discovery.contains(.patternArraySummary))
    #expect(patternArraySummary.discovery.contains(.designDisplaySnapshot))
    #expect(patternArraySummary.targets == [.sceneNode, .componentInstance])
    #expect(patternArraySummary.summary.contains("output ownership"))
    #expect(patternArraySummary.failureMode.contains("source-owned component-instance"))

    #expect(designDisplaySnapshot.category == .read)
    #expect(!designDisplaySnapshot.mutatesDocument)
    #expect(designDisplaySnapshot.access == .agentRequest)
    #expect(designDisplaySnapshot.discovery.contains(.designDisplaySnapshot))
    #expect(designDisplaySnapshot.discovery.contains(.sketchEntitySummary))
    #expect(designDisplaySnapshot.discovery.contains(.topologySummary))
    #expect(designDisplaySnapshot.targets == [
        .document,
        .componentInstance,
        .sketchEntity,
        .region,
        .body,
        .face,
        .edge,
        .vertex,
    ])
    #expect(designDisplaySnapshot.summary.contains("UI-visible sketch primitives"))
    #expect(designDisplaySnapshot.summary.contains("component definitions"))
    #expect(designDisplaySnapshot.summary.contains("component instances"))
    #expect(designDisplaySnapshot.summary.contains("generated topology"))
    #expect(designDisplaySnapshot.failureMode.contains("display-ready source snapshots"))
    #expect(designDisplaySnapshot.failureMode.contains("reusable component definitions"))
    #expect(designDisplaySnapshot.failureMode.contains("placed component instances"))

    #expect(qualityAssessment.category == .read)
    #expect(!qualityAssessment.mutatesDocument)
    #expect(!qualityAssessment.requiresSession)
    #expect(!qualityAssessment.requiresExpectedGeneration)
    #expect(qualityAssessment.access == .agentRequest)
    #expect(qualityAssessment.discovery.contains(.cadInteractionQualityAssessment))
    #expect(qualityAssessment.targets == [.document])
    #expect(qualityAssessment.summary.contains("objective CAD interaction quality assessment"))

    #expect(sketchSummary.category == .read)
    #expect(!sketchSummary.mutatesDocument)
    #expect(sketchSummary.access == .agentRequest)
    #expect(sketchSummary.discovery.contains(.sketchEntitySummary))
    #expect(sketchSummary.targets == [.sketchEntity, .region])

    #expect(curveAnalysis.category == .read)
    #expect(!curveAnalysis.mutatesDocument)
    #expect(curveAnalysis.access == .agentRequest)
    #expect(curveAnalysis.discovery.contains(.sketchEntitySummary))
    #expect(curveAnalysis.discovery.contains(.curveAnalysis))
    #expect(curveAnalysis.summary.contains("curvature"))
    #expect(curveAnalysis.summary.contains("continuity"))

    #expect(selection.category == .selection)
    #expect(!selection.mutatesDocument)
    #expect(selection.discovery.contains(.topologySummary))
    #expect(selection.discovery.contains(.sketchEntitySummary))
    #expect(selection.targets == [.sceneNode, .face, .edge, .vertex, .region, .sketchEntity])
}

@Test func agentHandlesCapabilitySchemaRequest() async throws {
    let server = AgentCommandController()

    let response = server.handle(.capabilities)

    guard case .capabilities(let descriptors) = response else {
        #expect(Bool(false))
        return
    }
    #expect(descriptors == server.capabilityDescriptors())
    #expect(descriptors.contains { $0.name == "moveBodyVertex" && $0.targets == [.vertex] })
    #expect(descriptors.contains { $0.name == "cadInteractionQualityAssessment" && !$0.requiresSession })
    #expect(descriptors.contains { $0.name == "designDisplaySnapshot" && $0.discovery.contains(.designDisplaySnapshot) })
    #expect(descriptors.contains { $0.name == "patternArraySummary" && $0.discovery.contains(.patternArraySummary) })
}

@Test func agentMessageCodecWrapsRequestsInJSONRPCEnvelope() async throws {
    let codec = AgentMessageCodec()

    let encoded = try codec.encode(AgentRequest.status, id: "request-1")
    let envelope = try codec.decodeRequestEnvelope(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])

    #expect(envelope == AgentRequestEnvelope(id: "request-1", params: .status))
    #expect(json["jsonrpc"] as? String == "2.0")
    #expect(json["id"] as? String == "request-1")
    #expect(json["method"] as? String == "agent.status")
    #expect(params.isEmpty)
    #expect(params["status"] == nil)
}

@Test func agentMessageCodecUsesMethodSpecificRequestParams() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .renameDocument(name: "Flat Params"),
        expectedGeneration: DocumentGeneration(7)
    )

    let encoded = try codec.encode(request, id: "request-params")
    let decoded = try codec.decodeRequest(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])

    #expect(decoded == request)
    #expect(json["method"] as? String == "command.apply")
    #expect(params["execute"] == nil)
    #expect(params["sessionID"] as? String == sessionID.uuidString)
    #expect(params["command"] != nil)
    #expect(params["expectedGeneration"] != nil)
}

@Test func agentMessageCodecWrapsResponsesInJSONRPCEnvelope() async throws {
    let codec = AgentMessageCodec()
    let response = AgentResponse.status(
        AgentStatus(
            running: true,
            socketPath: "/tmp/rupa.sock",
            sessionCount: 2
        )
    )

    let encoded = try codec.encode(response, id: "request-2")
    let decoded = try codec.decodeResponse(from: encoded, expectedID: "request-2")
    let envelope = try codec.decodeResponseEnvelope(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(decoded == response)
    #expect(envelope.id == "request-2")
    #expect(envelope.method == "agent.status")
    #expect(json["jsonrpc"] as? String == "2.0")
    #expect(json["id"] as? String == "request-2")
    #expect(json["method"] as? String == "agent.status")
    #expect(json["error"] == nil)
    #expect(result["status"] == nil)
    #expect(result["running"] as? Bool == true)
    #expect(result["socketPath"] as? String == "/tmp/rupa.sock")
    #expect(result["sessionCount"] as? Int == 2)
}

@Test func agentMessageCodecWrapsFailuresAsResponseErrors() async throws {
    let codec = AgentMessageCodec()
    let error = EditorError(
        code: .commandInvalid,
        message: "Malformed command."
    )

    let encoded = try codec.encode(
        AgentResponse.failure(error),
        id: "request-3",
        method: "agent.status"
    )
    let decoded = try codec.decodeResponse(
        from: encoded,
        expectedID: "request-3",
        expectedMethod: "agent.status"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let errorJSON = try #require(json["error"] as? [String: Any])

    #expect(decoded == .failure(error))
    #expect(json["method"] as? String == "agent.status")
    #expect(json["result"] == nil)
    #expect(errorJSON["code"] as? String == EditorError.Code.commandInvalid.rawValue)
    #expect(errorJSON["message"] as? String == "Malformed command.")
}

@Test func agentMessageCodecRejectsRequestMethodPayloadMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = Data(
        """
        {
            "jsonrpc": "2.0",
            "id": "request-4",
            "method": "agent.status",
            "params": {
                "sessions": {}
            }
        }
        """.utf8
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeRequestEnvelope(from: encoded)
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func agentMessageCodecRejectsResponseMethodMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 1
            )
        ),
        id: "request-5"
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeResponse(
            from: encoded,
            expectedID: "request-5",
            expectedMethod: "sessions.list"
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .agentConnectionFailed)
}

@Test func agentMessageCodecTreatsParameterExpressionResponseAsCommandResult() async throws {
    let codec = AgentMessageCodec()
    let response = AgentResponse.command(
        AutomationResult(
            message: "Parameter height updated.",
            commandName: "upsertParameter",
            generation: DocumentGeneration(2),
            didMutate: true
        )
    )

    let encoded = try codec.encode(
        response,
        id: "request-parameter-expression",
        method: "parameter.setExpression"
    )
    let decoded = try codec.decodeResponse(
        from: encoded,
        expectedID: "request-parameter-expression",
        expectedMethod: "parameter.setExpression"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(decoded == response)
    #expect(json["method"] as? String == "parameter.setExpression")
    #expect(result["command"] == nil)
    #expect(result["commandName"] as? String == "upsertParameter")
    #expect(result["didMutate"] as? Bool == true)
}

@Test func agentProtocolRawJSONFixturesDecodeRepresentativeRequests() async throws {
    let codec = AgentMessageCodec()
    let sessionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let requestFixtures: [(json: String, validate: (AgentRequestEnvelope) throws -> Void)] = [
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "status-1",
              "method": "agent.status",
              "params": {}
            }
            """,
            { envelope in
                #expect(envelope.id == "status-1")
                #expect(envelope.method == "agent.status")
                #expect(envelope.params == .status)
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "parameters-1",
              "method": "document.parameters",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "expectedGeneration": {
                  "value": 2
                }
              }
            }
            """,
            { envelope in
                guard case .parameters(let decodedSessionID, let expectedGeneration) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(expectedGeneration == DocumentGeneration(2))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "command-1",
              "method": "command.apply",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "command": {
                  "renameDocument": {
                    "name": "Fixture Project"
                  }
                },
                "expectedGeneration": {
                  "value": 3
                }
              }
            }
            """,
            { envelope in
                guard case .execute(let decodedSessionID, let command, let expectedGeneration) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(command == .renameDocument(name: "Fixture Project"))
                #expect(expectedGeneration == DocumentGeneration(3))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "parameter-1",
              "method": "parameter.setExpression",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "name": "height",
                "expression": "width * 2",
                "kind": "length",
                "defaults": {
                  "lengthUnit": "millimeter",
                  "angleUnit": "degree"
                },
                "expectedGeneration": {
                  "value": 4
                }
              }
            }
            """,
            { envelope in
                guard case .setParameterExpression(
                    let decodedSessionID,
                    let name,
                    let expression,
                    let kind,
                    let defaults,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(name == "height")
                #expect(expression == "width * 2")
                #expect(kind == .length)
                #expect(defaults == ParameterExpressionDefaults(lengthUnit: .millimeter, angleUnit: .degree))
                #expect(expectedGeneration == DocumentGeneration(4))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "snap-1",
              "method": "snap.resolve",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "point": {
                  "x": 0.012,
                  "y": 0.024
                },
                "options": {
                  "usesGrid": true,
                  "usesObjects": false,
                  "gridIntervalMeters": 0.001,
                  "objectSearchRadiusMeters": 0.002,
                  "maximumCandidateCount": 8
                },
                "expectedGeneration": {
                  "value": 5
                }
              }
            }
            """,
            { envelope in
                guard case .resolveSnap(
                    let decodedSessionID,
                    let point,
                    let options,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(point == Point2D(x: 0.012, y: 0.024))
                #expect(options.usesGrid)
                #expect(!options.usesObjects)
                #expect(options.maximumCandidateCount == 8)
                #expect(expectedGeneration == DocumentGeneration(5))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "surface-analysis-1",
              "method": "document.surfaceAnalysis",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "options": {
                  "sampleDensity": "high"
                },
                "expectedGeneration": {
                  "value": 6
                }
              }
            }
            """,
            { envelope in
                guard case .surfaceAnalysis(
                    let decodedSessionID,
                    let options,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(options == SurfaceAnalysisOptions(sampleDensity: .high))
                #expect(expectedGeneration == DocumentGeneration(6))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "surface-frames-1",
              "method": "document.surfaceFrames",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "queries": [
                  {
                    "faceID": "face-1",
                    "u": 0.25,
                    "v": 0.75
                  }
                ],
                "expectedGeneration": {
                  "value": 7
                }
              }
            }
            """,
            { envelope in
                guard case .surfaceFrames(
                    let decodedSessionID,
                    let queries,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(queries == [SurfaceFrameQuery(faceID: "face-1", u: 0.25, v: 0.75)])
                #expect(expectedGeneration == DocumentGeneration(7))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "selection-1",
              "method": "selection.selectTargets",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "targets": [],
                "expectedGeneration": {
                  "value": 8
                }
              }
            }
            """,
            { envelope in
                guard case .selectTargets(
                    let decodedSessionID,
                    let targets,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(targets.isEmpty)
                #expect(expectedGeneration == DocumentGeneration(8))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "export-1",
              "method": "document.export",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "outputPath": "/tmp/rupa-fixture.obj",
                "options": {},
                "dryRun": true,
                "expectedGeneration": {
                  "value": 9
                }
              }
            }
            """,
            { envelope in
                guard case .export(
                    let decodedSessionID,
                    let outputPath,
                    let expectedGeneration,
                    let options,
                    let dryRun
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(outputPath == "/tmp/rupa-fixture.obj")
                #expect(expectedGeneration == DocumentGeneration(9))
                #expect(options == ExportOptions())
                #expect(dryRun)
            }
        ),
    ]

    for fixture in requestFixtures {
        let envelope = try codec.decodeRequestEnvelope(from: rawAgentProtocolJSON(fixture.json))
        try fixture.validate(envelope)
    }
}

@Test func agentProtocolRawJSONFixtureDecodesFlatResponses() async throws {
    let codec = AgentMessageCodec()
    let statusResponse = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "status-1",
              "method": "agent.status",
              "result": {
                "running": true,
                "socketPath": "/tmp/rupa.sock",
                "sessionCount": 2
              }
            }
            """
        ),
        expectedID: "status-1",
        expectedMethod: "agent.status"
    )
    let parameterResponse = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "parameter-1",
              "method": "parameter.setExpression",
              "result": {
                "message": "Parameter height updated.",
                "commandName": "upsertParameter",
                "generation": {
                  "value": 10
                },
                "didMutate": true,
                "diagnostics": []
              }
            }
            """
        ),
        expectedID: "parameter-1",
        expectedMethod: "parameter.setExpression"
    )

    #expect(statusResponse == .status(AgentStatus(running: true, socketPath: "/tmp/rupa.sock", sessionCount: 2)))
    guard case .command(let result) = parameterResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "upsertParameter")
    #expect(result.generation == DocumentGeneration(10))
    #expect(result.didMutate)
}

@Test func agentProtocolRawJSONFixtureDecodesErrorResponse() async throws {
    let codec = AgentMessageCodec()
    let response = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "command-1",
              "method": "command.apply",
              "error": {
                "code": "document.generationMismatch",
                "message": "The document has changed since the command was prepared."
              }
            }
            """
        ),
        expectedID: "command-1",
        expectedMethod: "command.apply"
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(error.message == "The document has changed since the command was prepared.")
}

@Test func agentProtocolRejectsUnknownTopLevelParamsFromRawJSON() async throws {
    let codec = AgentMessageCodec()
    var caught: EditorError?

    do {
        _ = try codec.decodeRequestEnvelope(
            from: rawAgentProtocolJSON(
                """
                {
                  "jsonrpc": "2.0",
                  "id": "status-unknown-key",
                  "method": "agent.status",
                  "params": {
                    "status": {}
                  }
                }
                """
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("Unsupported params for agent.status") == true)
}

@Test func agentProtocolEncodesStatusResponseAsFlatResult() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 2
            )
        ),
        id: "status-encoded"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(json["method"] as? String == "agent.status")
    #expect(result["status"] == nil)
    #expect(result["running"] as? Bool == true)
    #expect(result["sessionCount"] as? Int == 2)
}

private func rawAgentProtocolJSON(_ source: String) -> Data {
    Data(source.utf8)
}

@Test func agentMessageCodecRejectsResponseIDMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 1
            )
        ),
        id: "actual-request"
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeResponse(from: encoded, expectedID: "expected-request")
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .agentConnectionFailed)
}

@Test func agentMessageCodecRoundTripsParameterRequestsAndResponses() async throws {
    let codec = AgentMessageCodec()
    let capabilitiesRequest = AgentRequest.capabilities
    let qualityAssessmentRequest = AgentRequest.cadInteractionQualityAssessment
    let capabilitiesResponse = AgentResponse.capabilities([
        AgentCapabilityDescriptor(
            name: "topologySummary",
            category: .read,
            summary: "Discover generated topology.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary],
            targets: [.face, .edge, .vertex],
            failureMode: "Rejects stale generations before reading."
        ),
    ])
    let sessionID = UUID()
    let listRequest = AgentRequest.parameters(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let constructionPlaneRequest = AgentRequest.constructionPlaneSummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let displaySnapshotRequest = AgentRequest.designDisplaySnapshot(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let patternArraySummaryRequest = AgentRequest.patternArraySummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let objectDimensionTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let objectDimensionRequest = AgentRequest.objectDimensionSummary(
        sessionID: sessionID,
        targets: [objectDimensionTarget],
        expectedGeneration: DocumentGeneration(2)
    )
    let sketchDimensionTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(SelectionComponentID(rawValue: "sketchEntity:test"))
    )
    let sketchDimensionRequest = AgentRequest.sketchDimensionSummary(
        sessionID: sessionID,
        targets: [sketchDimensionTarget],
        expectedGeneration: DocumentGeneration(2)
    )
    let selectionDimensionID = SelectionDimensionID()
    let selectionDimensionRequest = AgentRequest.selectionDimensionEvaluation(
        sessionID: sessionID,
        dimensionID: selectionDimensionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let expressionRequest = AgentRequest.setParameterExpression(
        sessionID: sessionID,
        name: "height",
        expression: "width * 2",
        kind: .length,
        defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
        expectedGeneration: DocumentGeneration(2)
    )
    let listResponse = AgentResponse.parameters(
        ParameterListResult(
            message: "0 parameters.",
            generation: DocumentGeneration(2),
            dirty: false,
            parameters: [],
            diagnostics: []
        )
    )
    let constructionPlaneResponse = AgentResponse.constructionPlaneSummary(
        ConstructionPlaneSummaryResult(
            activePlaneID: nil,
            planes: []
        )
    )
    let displaySnapshotResponse = AgentResponse.designDisplaySnapshot(
        DesignDisplaySnapshotResult(
            generation: DocumentGeneration(2),
            dirty: false,
            sketches: [],
            extrudes: [],
            straightPrismSweeps: [],
            bodies: []
        )
    )
    let patternArraySummaryResponse = AgentResponse.patternArraySummary(
        PatternArraySummaryResult(
            generation: DocumentGeneration(2),
            dirty: false,
            patternArrays: []
        )
    )
    let objectDimensionResponse = AgentResponse.objectDimensionSummary(
        ObjectDimensionSummaryResult(
            displayUnit: .millimeter,
            counts: ObjectDimensionSummaryResult.Counts(targetCount: 1, entryCount: 1),
            entries: [
                ObjectDimensionSummaryResult.Entry(
                    target: objectDimensionTarget,
                    sceneNodeID: objectDimensionTarget.sceneNodeID.description,
                    sourceFeatureID: UUID().uuidString,
                    sourceKind: .box,
                    kind: .sizeX,
                    label: "Size X",
                    inputExpression: .length(24.0, .millimeter),
                    resolvedMeters: 0.024,
                    isPrimaryForTarget: true
                ),
            ]
        )
    )
    let sketchDimensionResponse = AgentResponse.sketchDimensionSummary(
        SketchDimensionSummaryResult(
            displayUnit: .millimeter,
            counts: SketchDimensionSummaryResult.Counts(targetCount: 1, entryCount: 1),
            entries: [
                SketchDimensionSummaryResult.Entry(
                    requestedTarget: sketchDimensionTarget,
                    target: sketchDimensionTarget,
                    sceneNodeID: sketchDimensionTarget.sceneNodeID.description,
                    sourceFeatureID: UUID().uuidString,
                    entityID: UUID().uuidString,
                    entityKind: "line",
                    kind: .length,
                    label: "Length",
                    inputExpression: .length(24.0, .millimeter),
                    resolvedValue: 0.024,
                    isPrimaryForTarget: true
                ),
            ]
        )
    )
    let selectionDimensionResponse = AgentResponse.selectionDimensionEvaluation(
        SelectionDimensionEvaluation(measurements: [])
    )
    let qualityAssessmentResponse = AgentResponse.cadInteractionQualityAssessment(
        CADInteractionQualityAssessmentService().assess()
    )

    #expect(try codec.decodeRequest(from: try codec.encode(capabilitiesRequest)) == capabilitiesRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(qualityAssessmentRequest)) == qualityAssessmentRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(capabilitiesResponse)) == capabilitiesResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(listRequest)) == listRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(constructionPlaneRequest)) == constructionPlaneRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(displaySnapshotRequest)) == displaySnapshotRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(patternArraySummaryRequest)) == patternArraySummaryRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(objectDimensionRequest)) == objectDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(sketchDimensionRequest)) == sketchDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(selectionDimensionRequest)) == selectionDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(expressionRequest)) == expressionRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(listResponse)) == listResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(constructionPlaneResponse)) == constructionPlaneResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(displaySnapshotResponse)) == displaySnapshotResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(patternArraySummaryResponse)) == patternArraySummaryResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(objectDimensionResponse)) == objectDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(sketchDimensionResponse)) == sketchDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(selectionDimensionResponse)) == selectionDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(qualityAssessmentResponse)) == qualityAssessmentResponse)
}

@Test func agentReturnsCADInteractionQualityAssessmentWithoutSession() async throws {
    let response = AgentCommandController().handle(.cadInteractionQualityAssessment)

    guard case .cadInteractionQualityAssessment(let assessment) = response else {
        #expect(Bool(false))
        return
    }

    #expect(assessment.counts.entryCount == assessment.entries.count)
    #expect(assessment.entries.contains { $0.area == .dimensions })
    #expect(assessment.entries.contains { $0.area == .agentOperability })
    let productParityAreas: [CADInteractionQualityArea] = [
        .filletingAndBlending,
        .booleanModeling,
        .directModeling,
        .exchangeAndDrawings,
        .patternsAndArrays,
        .sectionAnalysis,
    ]
    for area in productParityAreas {
        let entry = try #require(assessment.entries.first { $0.area == area })
        #expect(entry.currentRating != .missing)
        #expect(!entry.evidence.isEmpty)
        #expect(!entry.openWork.isEmpty)
        #expect(!entry.nextRequiredResult.isEmpty)
    }
    #expect(assessment.entries.allSatisfy { entry in
        entry.gateAssessments.map(\.gate) == CADInteractionQualityGate.allCases
    })
    #expect(Set(assessment.entries.map(\.area)) == Set(CADInteractionQualityArea.allCases))
    #expect(assessment.entries.map(\.area).count == Set(assessment.entries.map(\.area)).count)
}

@MainActor
@Test func agentReturnsDesignDisplaySnapshotForViewportPlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    guard case .designDisplaySnapshot(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(snapshot.sketches.first)
    let extrude = try #require(snapshot.extrudes.first)
    let body = try #require(snapshot.bodies.first)

    #expect(snapshot.generation == session.generation)
    #expect(snapshot.dirty == session.isDirty)
    #expect(snapshot.sketches.count == 1)
    #expect(snapshot.extrudes.count == 1)
    #expect(snapshot.straightPrismSweeps.isEmpty)
    #expect(snapshot.bodies.count == 1)
    #expect(snapshot.componentDefinitions.isEmpty)
    #expect(snapshot.componentInstances.isEmpty)
    #expect(snapshot.patternArrays.isEmpty)
    #expect(sketch.primitives.count == 4)
    #expect(sketch.regions.count == 1)
    #expect(extrude.profileFeatureID == sketch.featureID)
    #expect(extrude.depthMeters > 0.0)
    #expect(body.mesh.positions.isEmpty == false)
    #expect(body.topology.faces.count == 6)
    #expect(body.topology.edges.count == 12)
    #expect(body.topology.vertices.count == 8)
    #expect(decodedResponse == response)
}

@Test func agentDiscoversPlacedComponentInstancesFromDesignDisplaySnapshot() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Placed Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Placed Source"
    })
    _ = try session.execute(
        .createComponentInstance(
            name: "Agent Placed Instance",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .componentInstance(instance.id)
    })
    server.register(session: session, id: sessionID)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(snapshotResponse))
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        #expect(Bool(false))
        return
    }
    let discoveredInstance = try #require(snapshot.componentInstances.first)

    #expect(snapshot.componentDefinitions.count == 1)
    #expect(snapshot.componentInstances.count == 1)
    #expect(discoveredInstance.instanceID == instance.id)
    #expect(discoveredInstance.name == "Agent Placed Instance")
    #expect(discoveredInstance.definitionID == definition.id)
    #expect(discoveredInstance.definitionName == "Agent Placed Source")
    #expect(discoveredInstance.sceneNodeIDs == [sceneNode.id])
    #expect(discoveredInstance.primarySceneNodeID == sceneNode.id)
    #expect(discoveredInstance.ownership == .document)
    #expect(discoveredInstance.ownership.isDirectlyEditable)
    #expect(decodedResponse == snapshotResponse)
}

@Test func agentDiscoversPatternArraySourceFromDesignDisplaySnapshotForLifecycleCommands() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Snapshot Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Snapshot Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Snapshot Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    server.register(session: session, id: sessionID)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(snapshotResponse))
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        #expect(Bool(false))
        return
    }
    let discoveredArray = try #require(snapshot.patternArrays.first)
    let discoveredDefinition = try #require(snapshot.componentDefinitions.first)
    let firstOutput = try #require(discoveredArray.outputs.first)
    let firstOutputInstanceID = try #require(firstOutput.componentInstanceID)
    let discoveredInstance = try #require(snapshot.componentInstances.first {
        $0.instanceID == firstOutputInstanceID
    })

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .updatePatternArray(
                id: discoveredArray.sourceID,
                name: "Agent Snapshot Array Updated",
                definitionID: nil,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(16.0, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: nil
            ),
            expectedGeneration: snapshot.generation
        )
    )
    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSource = try #require(session.document.productMetadata.patternArrays[discoveredArray.sourceID])
    #expect(snapshot.patternArrays.count == 1)
    #expect(snapshot.componentDefinitions.count == 1)
    #expect(snapshot.componentInstances.count == 2)
    #expect(discoveredDefinition.definitionID == definition.id)
    #expect(discoveredDefinition.name == "Agent Snapshot Array Source")
    #expect(discoveredDefinition.bodySceneNodeIDs == [bodySceneNodeID])
    #expect(discoveredDefinition.bodyFeatureIDs.contains(bodyFeatureID))
    #expect(discoveredDefinition.featureIDs.contains(bodyFeatureID))
    #expect(discoveredDefinition.isRenderable)
    #expect(discoveredArray.name == "Agent Snapshot Array")
    #expect(discoveredArray.definitionID == definition.id)
    #expect(discoveredArray.definitionName == "Agent Snapshot Array Source")
    #expect(discoveredArray.outputCount == 2)
    #expect(discoveredArray.outputs.count == 2)
    #expect(discoveredArray.diagnostics.isEmpty)
    #expect(firstOutput.componentInstanceID == discoveredArray.outputs[0].componentInstanceID)
    #expect(discoveredInstance.definitionID == definition.id)
    #expect(discoveredInstance.definitionName == "Agent Snapshot Array Source")
    #expect(discoveredInstance.primarySceneNodeID == firstOutput.sceneNodeID)
    #expect(discoveredInstance.ownership.kind == .patternArrayOutput)
    #expect(discoveredInstance.ownership.patternArraySourceID == discoveredArray.sourceID)
    #expect(discoveredInstance.ownership.patternArraySourceName == "Agent Snapshot Array")
    #expect(discoveredInstance.ownership.patternArrayOutputIndex == 0)
    #expect(!discoveredInstance.ownership.isDirectlyEditable)
    #expect(decodedResponse == snapshotResponse)
    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updatedSource.name == "Agent Snapshot Array Updated")
    #expect(updatedSource.outputInstanceIDs == [firstOutputInstanceID])
}

@Test func agentReportsPatternArraySummaryForLifecyclePlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Summary Array Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Summary Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Summary Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Summary Array"
    })
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(summaryResponse))
    guard case .patternArraySummary(let result) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let summary = try #require(result.patternArrays.first)

    #expect(result.generation == session.generation)
    #expect(result.dirty == session.isDirty)
    #expect(summary.sourceID == source.id)
    #expect(summary.definitionID == definition.id)
    #expect(summary.definitionName == "Agent Summary Array Source")
    #expect(summary.outputMode == .componentInstance)
    #expect(summary.outputCount == source.outputInstanceIDs.count)
    #expect(summary.componentInstanceOutputIDs == source.outputInstanceIDs)
    #expect(summary.outputOwnership.kind == .sourceOwnedComponentInstances)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.sourceEditAction == .updatePatternArray)
    #expect(summary.outputOwnership.detachAction == .explodePatternArray)
    #expect(summary.diagnostics.isEmpty)
    #expect(decodedResponse == summaryResponse)
}

@Test func agentReportsIndependentCopyOutputStatesForLifecyclePlanning() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Independent Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Independent Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        agentFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: .length(7.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    let codec = AgentMessageCodec()
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(summaryResponse))
    guard case .patternArraySummary(let result) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let summary = try #require(result.patternArrays.first)
    let firstOutput = try #require(summary.independentCopyOutputs.first)
    let secondOutput = try #require(summary.independentCopyOutputs.dropFirst().first)

    #expect(summary.sourceID == source.id)
    #expect(summary.outputMode == .independentCopy)
    #expect(summary.outputOwnership.kind == .sourceOwnedIndependentCopies)
    #expect(!summary.outputOwnership.directOutputEditingAllowed)
    #expect(summary.outputOwnership.directFeatureEditingAllowed)
    #expect(firstOutput.sceneNodeID == firstOutputSceneNodeID)
    #expect(firstOutput.featureIDs.contains(firstCloneBodyFeatureID))
    #expect(firstOutput.state == .divergedFromSourceDefinition)
    #expect(firstOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(secondOutput.state == .matchesSourceDefinition)
    #expect(secondOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
    #expect(decodedResponse == summaryResponse)
}

@MainActor
@Test func agentSetsIndependentCopyCloneExtrudeDistanceThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Edit Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Edit Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Edit Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Edit Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )
    )
    guard case .patternArraySummary(let summaryResult) = summaryResponse else {
        Issue.record("Agent must return a pattern array summary.")
        return
    }
    let summary = try #require(summaryResult.patternArrays.first { $0.sourceID == source.id })
    let firstOutput = try #require(summary.independentCopyOutputs.first)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        Issue.record("Agent must return a display snapshot.")
        return
    }
    let extrudeFeatureIDs = Set(snapshot.extrudes.map(\.featureID))
    let cloneExtrudeFeatureID = try #require(firstOutput.featureIDs.first { extrudeFeatureIDs.contains($0) })

    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setExtrudeDistance(
                featureID: cloneExtrudeFeatureID,
                distance: .length(11.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let expectedEditedGeneration = try initialGeneration.advanced()

    let updatedSnapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .designDisplaySnapshot(let updatedSnapshot) = updatedSnapshotResponse else {
        Issue.record("Agent must return an updated display snapshot.")
        return
    }
    let editedExtrude = try #require(updatedSnapshot.extrudes.first { $0.featureID == cloneExtrudeFeatureID })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedFirstOutput = try #require(updatedSummary.independentCopyOutputs.first)

    #expect(commandResult.message == "Extrude distance updated.")
    #expect(commandResult.commandName == "setExtrudeDistance")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(abs(editedExtrude.depthMeters - 0.011) < 1.0e-12)
    #expect(updatedFirstOutput.featureIDs.contains(cloneExtrudeFeatureID))
    #expect(updatedFirstOutput.state == .divergedFromSourceDefinition)
    #expect(updatedFirstOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

@MainActor
@Test func agentSetsIndependentCopyCloneCubeDimensionsThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Cube Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Cube Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Cube Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Cube Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let clone = try agentIndependentCopyCloneExtrudeFeature(
        server: server,
        sessionID: sessionID,
        sourceID: source.id,
        expectedGeneration: initialGeneration
    )
    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCubeDimensions(
                featureID: clone.featureID,
                sizeX: .length(16.0, .millimeter),
                sizeY: .length(9.0, .millimeter),
                sizeZ: .length(12.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }

    let dimensionResponse = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [SelectionTarget(sceneNodeID: clone.output.sceneNodeID)],
            expectedGeneration: commandResult.generation
        )
    )
    guard case .objectDimensionSummary(let dimensionSummary) = dimensionResponse else {
        Issue.record("Agent must return an object dimension summary.")
        return
    }
    let sizeX = try #require(dimensionSummary.entries.first { $0.kind == .sizeX })
    let sizeY = try #require(dimensionSummary.entries.first { $0.kind == .sizeY })
    let sizeZ = try #require(dimensionSummary.entries.first { $0.kind == .sizeZ })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedOutput = try #require(updatedSummary.independentCopyOutputs.first)
    let expectedEditedGeneration = try initialGeneration.advanced()

    #expect(commandResult.message == "Cube dimensions updated.")
    #expect(commandResult.commandName == "setCubeDimensions")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(sizeX.sourceKind == .box)
    #expect(abs(sizeX.resolvedMeters - 0.016) < 1.0e-12)
    #expect(abs(sizeY.resolvedMeters - 0.009) < 1.0e-12)
    #expect(abs(sizeZ.resolvedMeters - 0.012) < 1.0e-12)
    #expect(updatedOutput.featureIDs.contains(clone.featureID))
    #expect(updatedOutput.state == .divergedFromSourceDefinition)
    #expect(updatedOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

@MainActor
@Test func agentSetsIndependentCopyCloneCylinderDimensionsThroughDiscoveredFeatureID() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Agent Clone Cylinder",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            depth: .length(8.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        agentPatternArrayBodySceneNodeID(for: bodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Agent Clone Cylinder Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Clone Cylinder Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Agent Clone Cylinder Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Clone Cylinder Array"
    })
    let initialGeneration = session.generation
    server.register(session: session, id: sessionID)

    let clone = try agentIndependentCopyCloneExtrudeFeature(
        server: server,
        sessionID: sessionID,
        sourceID: source.id,
        expectedGeneration: initialGeneration
    )
    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCylinderDimensions(
                featureID: clone.featureID,
                radius: .length(7.0, .millimeter),
                sizeY: .length(13.0, .millimeter)
            ),
            expectedGeneration: initialGeneration
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must return a command result.")
        return
    }

    let dimensionResponse = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [SelectionTarget(sceneNodeID: clone.output.sceneNodeID)],
            expectedGeneration: commandResult.generation
        )
    )
    guard case .objectDimensionSummary(let dimensionSummary) = dimensionResponse else {
        Issue.record("Agent must return an object dimension summary.")
        return
    }
    let radius = try #require(dimensionSummary.entries.first { $0.kind == .radius })
    let sizeY = try #require(dimensionSummary.entries.first { $0.kind == .sizeY })

    let updatedSummaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .patternArraySummary(let updatedSummaryResult) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated pattern array summary.")
        return
    }
    let updatedSummary = try #require(updatedSummaryResult.patternArrays.first { $0.sourceID == source.id })
    let updatedOutput = try #require(updatedSummary.independentCopyOutputs.first)
    let expectedEditedGeneration = try initialGeneration.advanced()

    #expect(commandResult.message == "Cylinder dimensions updated.")
    #expect(commandResult.commandName == "setCylinderDimensions")
    #expect(commandResult.didMutate)
    #expect(commandResult.generation == expectedEditedGeneration)
    #expect(radius.sourceKind == .cylinder)
    #expect(abs(radius.resolvedMeters - 0.007) < 1.0e-12)
    #expect(abs(sizeY.resolvedMeters - 0.013) < 1.0e-12)
    #expect(updatedOutput.featureIDs.contains(clone.featureID))
    #expect(updatedOutput.state == .divergedFromSourceDefinition)
    #expect(updatedOutput.regenerationPolicy == .reuseUntilDefinitionIdentityChanges)
}

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
    let surfaceControlPointSlideRequest = AgentRequest.execute(
        sessionID: sessionID,
        command: .slideSurfaceControlPoints(
            targets: [surfaceControlPointReference],
            direction: .positiveV,
            distance: .length(1.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(5)
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedSlideRequest = try codec.decodeRequest(from: try codec.encode(slideRequest))
    let decodedSurfaceControlPointMoveRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointMoveRequest)
    )
    let decodedSurfaceControlPointSlideRequest = try codec.decodeRequest(
        from: try codec.encode(surfaceControlPointSlideRequest)
    )

    #expect(decodedRequest == request)
    #expect(decodedSlideRequest == slideRequest)
    #expect(decodedSurfaceControlPointMoveRequest == surfaceControlPointMoveRequest)
    #expect(decodedSurfaceControlPointSlideRequest == surfaceControlPointSlideRequest)
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
    #expect(try codec.decodeRequest(from: try codec.encode(selectRequest)) == selectRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(selectResponse)) == selectResponse)
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

@Test func agentListsRegisteredSessions() async throws {
    let server = AgentCommandController(socketPath: "/tmp/rupa.sock")
    let sessionID = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open Document")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: sessionID
    )

    let response = server.handle(.sessions)

    guard case .sessions(let sessions) = response else {
        #expect(Bool(false))
        return
    }
    #expect(sessions.count == 1)
    #expect(sessions[0].id == sessionID)
    #expect(sessions[0].displayName == "Open Document")
    #expect(sessions[0].generation == DocumentGeneration(0))
}

@Test func agentDispatchesCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Live")
}

@MainActor
@Test func agentAddsAndEvaluatesPersistentSelectionDimension() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(16.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try agentLineEndpointTargets(in: document, featureID: featureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Length",
                kind: .distance,
                first: targets.start,
                second: targets.end,
                target: .length(16.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(measurement.measured == .length(0.016, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAddsAndEvaluatesGeneratedFacePairSelectionDimension() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let facePair = try agentParallelFaceDimensionTargets(in: topology)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Face Distance",
                kind: .distance,
                first: facePair.first,
                second: facePair.second,
                target: .length(facePair.distance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: session.generation
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(abs(measurement.measured.value - facePair.distance) <= 1.0e-12)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@Test func agentCreatesReadsAndActivatesConstructionPlanes() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlane(
                name: "Agent CPlane",
                plane: .yz,
                activates: true
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        #expect(Bool(false))
        return
    }
    #expect(createResult.commandName == "createConstructionPlane")
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first)
    #expect(entry.name == "Agent CPlane")
    #expect(entry.plane == .yz)
    #expect(entry.isActive)
    #expect(summary.activePlaneID == entry.id)
    #expect(entry.sceneNodeID != nil)

    let renameResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameConstructionPlane(
                id: entry.id,
                name: "Agent Renamed CPlane"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let renameResult) = renameResponse else {
        #expect(Bool(false))
        return
    }
    #expect(renameResult.commandName == "renameConstructionPlane")
    #expect(renameResult.didMutate)

    let renamedSummaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .constructionPlaneSummary(let renamedSummary) = renamedSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let renamedEntry = try #require(renamedSummary.planes.first)
    #expect(renamedEntry.name == "Agent Renamed CPlane")
    let renamedSceneNodeID = try #require(renamedEntry.sceneNodeID)
    #expect(session.document.productMetadata.sceneNodes[renamedSceneNodeID]?.name == "Agent Renamed CPlane")

    let clearResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setActiveConstructionPlane(id: nil),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let clearResult) = clearResponse else {
        #expect(Bool(false))
        return
    }
    #expect(clearResult.commandName == "setActiveConstructionPlane")
    #expect(clearResult.didMutate)
    #expect(session.activeConstructionPlane == nil)
}

@Test func agentCreatesViewAlignedConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createViewAlignedConstructionPlane(
                name: "Agent View Plane",
                origin: Point3D(x: 0.010, y: 0.020, z: 0.030),
                viewNormal: Vector3D(x: 0.0, y: 3.0, z: 0.0),
                activates: true
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    #expect(source.name == "Agent View Plane")
    guard case .plane(let plane) = source.plane else {
        Issue.record("Agent view-aligned construction plane should create a custom plane.")
        return
    }
    #expect(plane.normal == .unitY)
}

@Test func agentCreatesConstructionPlaneFromGeneratedFaceTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceTarget = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil
    }?.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTarget(
                name: "Agent Face CPlane",
                target: faceTarget,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Face CPlane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Generated face target should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesMidplaneConstructionPlaneFromGeneratedFaceTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentParallelFaceTargets(in: topology)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Midplane",
                targets: targets,
                viewNormal: nil,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Midplane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Parallel generated face targets should create a custom midplane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromGeneratedVertexTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentTwoPointVertexTargets(in: topology, viewNormal: .unitZ)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Two Point Plane",
                targets: targets,
                viewNormal: .unitZ,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Two Point Plane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two generated vertex targets should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromSourcePointTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSourcePointSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Source Point Plane",
                targets: setup.targets,
                viewNormal: .unitZ,
                activates: true
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Source Point Plane" })
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two source point targets should create a custom construction plane.")
        return
    }
}

@Test func agentDispatchesModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesSelectedObjectDimensionCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let dimensionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setObjectDimension(
                target: SelectionTarget(sceneNodeID: bodyNode.id),
                kind: .sizeX,
                value: .length(36.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = dimensionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[bodyNode.id])
    guard case .length(let sizeX)? = editedBodyNode.object?.properties["size.x"] else {
        Issue.record("Expected a body size X property.")
        return
    }
    #expect(abs(sizeX - 0.036) < 0.000_000_000_001)
}

@Test func agentDispatchesObjectDimensionCommandFromGeneratedDepthEdge() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let depthEdge = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let edgeTarget = try #require(depthEdge.selectionTarget())

    let dimensionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setObjectDimension(
                target: edgeTarget,
                kind: .sizeY,
                value: .length(10.0, .millimeter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = dimensionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[edgeTarget.sceneNodeID])
    let sizeYValue = editedBodyNode.object?.properties["size.y"]
    guard case .length(let sizeY) = sizeYValue else {
        Issue.record("Expected a body size Y property.")
        return
    }
    #expect(abs(sizeY - 0.010) < 0.000_000_000_001)
}

@Test func agentReturnsSelectedObjectDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedCircle(
                name: "Agent Dimension Cylinder",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                radius: .length(12.0, .millimeter),
                depth: .length(24.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [
                SelectionTarget(
                    sceneNodeID: bodyNode.id,
                    component: .face(.bodyFaceSide)
                ),
            ],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .sizeY])
    let diameter = try #require(summary.entries.first { $0.kind == .diameter })
    #expect(diameter.isPrimaryForTarget)
    #expect(abs(diameter.resolvedMeters - 0.024) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentReturnsObjectDimensionSummaryFromGeneratedDepthEdgeWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Summary Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let depthEdge = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let edgeTarget = try #require(depthEdge.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .objectDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: generation
        )
    )

    guard case .objectDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 3)
    let kinds: [ObjectDimensionKind] = summary.entries.map(\.kind)
    #expect(kinds == [.sizeX, .sizeY, .sizeZ])
    let depth = try #require(summary.entries.first { $0.kind == ObjectDimensionKind.sizeY })
    #expect(depth.isPrimaryForTarget)
    #expect(depth.target == edgeTarget)
    #expect(abs(depth.resolvedMeters - 0.006) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentReturnsSelectedSketchDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLineSketch(
                name: "Agent Dimension Line",
                plane: .xy,
                start: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                end: SketchPoint(
                    x: .length(24.0, .millimeter),
                    y: .length(0.0, .meter)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let sketchSummaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let sketchSummary) = sketchSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let line = try #require(sketchSummary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: generation
        )
    )

    guard case .sketchDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    let length = try #require(summary.entries.first { $0.kind == .length })
    #expect(length.isPrimaryForTarget)
    #expect(abs(length.resolvedValue - 0.024) < 0.000_000_000_001)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentMapsGeneratedEdgeToSketchDimensionSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Dimension Edge Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(8.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let capEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "line" &&
            ($0.index ?? Int.max) < 4
    })
    let edgeTarget = try #require(capEdge.selectionTarget())
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .sketchDimensionSummary(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: generation
        )
    )

    guard case .sketchDimensionSummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.entryCount == 2)
    #expect(summary.entries.map(\.kind) == [.length, .angle])
    #expect(summary.entries.allSatisfy { $0.requestedTarget == edgeTarget })
    guard case .sketchEntity = summary.entries[0].target.component else {
        Issue.record("Agent sketch dimension summary must return an editable sketch entity target.")
        return
    }
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentDispatchesPolySplineCommandAndExposesBSplineTopology() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent PolySpline",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createPolySplineSurface")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    #expect(topology.counts.bodyCount == 1)
    #expect(topology.counts.faceCount == 1)
    #expect(topology.counts.edgeCount == 4)
    #expect(topology.counts.vertexCount == 4)
    let face = try #require(topology.entries.first {
        $0.kind == .face
            && $0.surfaceKind == "bSpline"
            && $0.generatedRole == "polySpline"
            && $0.subshapeRole == "patch:0:face"
    })
    #expect(face.surfaceUDegree == 3)
    #expect(face.surfaceVDegree == 3)
    #expect(face.surfaceUControlPointCount == 4)
    #expect(face.surfaceVControlPointCount == 4)
    #expect(face.selectionTarget() != nil)
    #expect(topology.entries.contains {
        $0.kind == .edge
            && $0.subshapeRole == "patch:0:edge:uMax"
            && $0.selectionTarget() != nil
    })
    #expect(topology.entries.contains {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
            && $0.selectionTarget() != nil
    })
}

@MainActor
@Test func agentMovesPolySplineSurfaceVertexThroughGeneratedTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Editable Surface",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .movePolySplineSurfaceVertex(
                target: target,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move a PolySpline surface vertex.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    #expect(moveResult.commandName == "movePolySplineSurfaceVertex")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesSurfaceControlPointThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Reference Move",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMax" })

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceControlPoint(
                target: controlVertex.selectionReference,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move a surface control point from a surface source reference.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesInteriorSurfaceControlPointThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Interior Surface Reference Move",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceControlPoint(
                target: controlPoint.selectionReference,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move an interior surface control point from a surface source reference.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(moveResult.commandName == "moveSurfaceControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(override.uIndex == 1)
    #expect(override.vIndex == 1)
    #expect(abs(override.point.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSlidesPolySplineSurfaceVerticesThroughGeneratedTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Slide Surface",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMin"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let slideResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slidePolySplineSurfaceVertices(
                targets: [target],
                direction: .positiveV,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let slideResult) = slideResponse else {
        Issue.record("Agent must slide PolySpline surface vertices.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(slideResult.commandName == "slidePolySplineSurfaceVertices")
    #expect(slideResult.didMutate)
    #expect(slideResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSlidesSurfaceControlPointsThroughSurfaceSourceReferences() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Reference Slide",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMin" })

    let slideResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSurfaceControlPoints(
                targets: [controlVertex.selectionReference],
                direction: .positiveV,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let slideResult) = slideResponse else {
        Issue.record("Agent must slide surface control points from surface source references.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(slideResult.commandName == "slideSurfaceControlPoints")
    #expect(slideResult.didMutate)
    #expect(slideResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentPreflightsPolySplineMeshWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplineQuadMesh(),
            options: PolySplineOptions(roundedCorners: true),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(!result.isSupported)
    #expect(result.candidateKind == .singleQuad)
    #expect(result.supportedPatchCount == 1)
    #expect(result.candidatePatchCount == 1)
    #expect(result.patchGraph?.candidates.count == 1)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0])
    #expect(result.errors.contains { $0.code == .unsupportedRoundedCorners })
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func agentPreflightsPolySplinePatchGraphWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplinePatchNetworkMesh(),
            options: PolySplineOptions(),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(!result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 0)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.ambiguousTriangleIndices == [0, 3])
    #expect(result.patchGraph?.partition?.isComplete == true)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.partition?.rejectedCandidateIDs == [1])
    let adjacency = try #require(result.patchGraph?.selectedAdjacencies.first)
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(adjacency.firstCandidateID == 0)
    #expect(adjacency.secondCandidateID == 2)
    #expect(adjacency.sharedVertexIndices == [1, 4])
    #expect(adjacency.continuityLevel == .positional)
    #expect(adjacency.requiresCurvatureContinuitySolve)
    #expect(result.diagnostics.contains { $0.code == .patchGraphIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchGraphPartitioned })
    #expect(result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
    #expect(result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
    #expect(result.errors.contains { $0.code == .unsupportedPatchNetwork })
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@Test func agentPreflightsPlanarUnmergedPolySplinePatchGraphWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
            options: PolySplineOptions(mergePatches: false),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 2)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.partition?.isComplete == true)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(result.patchGraph?.selectedAdjacencies.first?.continuityLevel == .tangentPlane)
    #expect(result.patchGraph?.selectedAdjacencies.first?.requiresCurvatureContinuitySolve == false)
    #expect(result.diagnostics.contains { $0.code == .planarPatchNetworkSupported })
    #expect(!result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
    #expect(result.errors.isEmpty)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func agentReportsPolySplineSurfaceSourceSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Source Summary",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )

    guard case .surfaceSourceSummary(let summary) = response else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    #expect(summary.counts.sourceCount == 1)
    #expect(summary.counts.patchCount == 2)
    #expect(summary.counts.controlVertexCount == 8)
    #expect(summary.counts.trimLoopCount == 2)
    #expect(summary.counts.adjacencyCount == 1)
    let source = try #require(summary.sources.first)
    #expect(source.kind == "polySpline")
    #expect(source.support.isSupported)
    #expect(source.support.candidateKind == "quadPatchGraph")
    #expect(source.patches.map(\.patchID) == [0, 2])
    let patch = try #require(source.patches.first)
    #expect(patch.facePersistentName?.contains("subshape:patch:0:face") == true)
    #expect(patch.faceSelectionComponentID?.hasPrefix(SelectionComponentID.generatedTopologyPrefix) == true)
    #expect(patch.basis.kind == "cubicBezierBSpline")
    #expect(patch.controlVertices.count == 4)
    #expect(patch.controlVertices.allSatisfy {
        $0.selectionComponentID.hasPrefix(SelectionComponentID.generatedTopologyPrefix)
    })
    let firstControlVertex = try #require(patch.controlVertices.first)
    let measurementResponse = server.handle(
        .selectionMeasurement(
            sessionID: sessionID,
            query: CADAgentMeasurementQuery(kind: .point, first: firstControlVertex.selectionReference),
            expectedGeneration: generation
        )
    )
    guard case .selectionMeasurement(.point(let measuredPoint)) = measurementResponse else {
        Issue.record("Agent must measure a discovered surface control-point selection reference.")
        return
    }
    #expect(abs(measuredPoint.point.x - firstControlVertex.point.x) <= 1.0e-12)
    #expect(abs(measuredPoint.point.y - firstControlVertex.point.y) <= 1.0e-12)
    #expect(abs(measuredPoint.point.z - firstControlVertex.point.z) <= 1.0e-12)
    #expect(patch.trimLoops.first?.edgePersistentNames.count == 4)
    #expect(patch.trimLoops.first?.selectionReferences.count == 4)
    let adjacency = try #require(source.adjacencies.first)
    #expect(adjacency.continuityLevel == "tangentPlane")
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentReportsPlanarPolySplineSurfaceAnalysisWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Analysis",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceAnalysis(
            sessionID: sessionID,
            options: SurfaceAnalysisOptions(sampleDensity: .high),
            expectedGeneration: generation
        )
    )

    guard case .surfaceAnalysis(let analysis) = response else {
        Issue.record("Agent must return a surface analysis result.")
        return
    }
    #expect(analysis.counts.bSplineFaceCount == 2)
    #expect(analysis.counts.sampleCount == 162)
    #expect(analysis.counts.uCurvatureCombCount == 162)
    #expect(analysis.counts.vCurvatureCombCount == 162)
    #expect(analysis.counts.trimBoundaryCount == 2)
    #expect(analysis.counts.innerTrimBoundaryCount == 0)
    #expect(analysis.counts.openTrimBoundaryCount == 0)
    #expect(analysis.counts.trimBoundaryEdgeCount == 8)
    let face = try #require(analysis.faces.first)
    #expect(face.facePersistentNames.contains { $0.contains("subshape:patch") })
    #expect(face.edgePersistentNames.contains { $0.contains("subshape:patch") })
    let trimBoundary = try #require(face.trimBoundaries.first)
    #expect(trimBoundary.role == .outer)
    #expect(trimBoundary.edgeCount == 4)
    #expect(trimBoundary.vertexCount == 4)
    #expect(trimBoundary.points.count == 4)
    #expect(trimBoundary.isClosed)
    #expect(trimBoundary.estimatedLength > 0.0)
    #expect(face.maxUNormalChangePerLength <= 1.0e-8)
    #expect(face.maxVNormalChangePerLength <= 1.0e-8)
    #expect(face.maxAbsUNormalCurvature <= 1.0e-8)
    #expect(face.maxAbsVNormalCurvature <= 1.0e-8)
    #expect(face.maxAbsPrincipalCurvature <= 1.0e-8)
    #expect(face.maxAbsGaussianCurvature <= 1.0e-8)
    let sample = try #require(face.samples.first)
    #expect(abs(surfaceVectorLength(sample.minimumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(sample.maximumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentResolvesPlanarPolySplineSurfaceFramesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Frame",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse,
          let faceEntry = topology.entries.first(where: { $0.kind == .face }) else {
        Issue.record("Agent must discover generated face topology before resolving UVN frames.")
        return
    }

    let response = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [
                SurfaceFrameQuery(
                    facePersistentName: faceEntry.persistentName,
                    u: 0.5,
                    v: 0.5
                ),
            ],
            expectedGeneration: generation
        )
    )

    guard case .surfaceFrames(let frames) = response else {
        Issue.record("Agent must return surface frame data.")
        return
    }
    #expect(frames.frames.count == 1)
    let frame = try #require(frames.frames.first)
    #expect(frame.facePersistentNames.contains(faceEntry.persistentName))
    #expect(abs(surfaceVectorLength(frame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(frame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(frame.normal) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorDot(surfaceVectorCross(frame.uAxis, frame.vAxis), frame.normal) - 1.0) <= 1.0e-8)
    #expect(frame.handedness > 0.999_999)
    #expect(abs(frame.normalCurvatureU) <= 1.0e-8)
    #expect(abs(frame.normalCurvatureV) <= 1.0e-8)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentReportsPlanarPolySplineSurfaceContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Planar Patch Network",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceContinuitySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )

    guard case .surfaceContinuitySummary(let summary) = response else {
        Issue.record("Agent must return a surface continuity summary.")
        return
    }
    #expect(summary.counts.bSplineFaceCount == 2)
    #expect(summary.counts.sharedEdgeCount == 1)
    #expect(summary.counts.g1AdjacencyCount == 1)
    #expect(summary.counts.unresolvedG2AdjacencyCount == 0)
    let adjacency = try #require(summary.adjacencies.first)
    #expect(adjacency.continuity == .g1)
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:0:edge:uMax") })
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:2:edge:uMin") })
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@Test func agentDispatchesFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceTop)),
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "sideFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesFaceKnifeCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createFaceKnife(
                name: "Agent Face Knife",
                target: target,
                loop: [
                    Point3D(x: -0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: 0.002, z: 0.0),
                    Point3D(x: -0.004, y: 0.002, z: 0.0),
                ]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let faceKnifeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let faceKnifeSceneNodeID = try #require(agentSceneNodeID(for: faceKnifeFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[faceKnifeFeatureID])
    guard case .faceKnife = feature.operation else {
        Issue.record("Agent Face Knife command must create a FaceKnife feature.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let faceKnifeFaces = afterTopology.entries.filter {
        $0.kind == .face && $0.sceneNodeID == faceKnifeSceneNodeID.description
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(faceKnifeFaces.count == 7)
    #expect(faceKnifeFaces.contains {
        $0.generatedRole == "faceKnife" && $0.subshapeRole == "centerFace"
    })
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(afterTopology.counts.faceCount == 7)
    #expect(afterTopology.counts.edgeCount == 15)
    #expect(afterTopology.counts.vertexCount == 10)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSelectedSupportFaceContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [supportFaceTarget, edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from selection context.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [supportFaceTarget, edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSingleSelectedCapEdgeContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a single edge selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from cap edge context.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.supportFacePersistentName.components == [
        .feature(bodyFeatureID),
        .generated(GeneratedSubshapeRole.startFace.rawValue),
    ])
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentOffsetsGeneratedCylinderSideFaceThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeRadius = try agentCylinderRadius(forBody: bodyFeatureID, in: session.document)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.surfaceKind == "cylinder"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(nearlyEqualAgent(try agentCylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius + 0.001))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeChamferCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightBottom)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsLineArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 2.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsArcArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsGeneratedEdgeAfterPriorChamferThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.25, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsSharpGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let secondFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.5, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let secondFilletResult) = secondFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(secondFilletResult.commandName == "filletBodyEdges")
    #expect(secondFilletResult.didMutate)
    #expect(secondFilletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentChamfersArcAdjacentGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [target],
                distance: .length(0.25, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyVertexMoveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentMovesSharpGeneratedVertexAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first {
        isAgentGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(moveResult.commandName == "moveBodyVertex")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesCornerFootprintModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangleFromCorners(
                name: "Agent Footprint Box",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .millimeter),
                    y: .length(2.0, .millimeter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(5.0, .millimeter),
                    y: .length(8.0, .millimeter)
                ),
                depth: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func agentDispatchesComponentCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Component",
                rootSceneNodeIDs: []
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let definitionResult) = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let instanceResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentInstance(
                name: "Agent Component A",
                definitionID: definition.id,
                localTransform: .identity
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let instanceResult) = instanceResponse else {
        #expect(Bool(false))
        return
    }

    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )
    let sceneNodeTransform = try agentTranslationTransform(x: 0.2, y: 0.0, z: 0.1)
    let transformResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSceneNodeTransform(
                id: sceneNode.id,
                localTransform: sceneNodeTransform
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let transformResult) = transformResponse else {
        #expect(Bool(false))
        return
    }

    #expect(definitionResult.commandName == "createComponentDefinition")
    #expect(instanceResult.commandName == "createComponentInstance")
    #expect(instanceResult.generation == DocumentGeneration(2))
    #expect(transformResult.commandName == "setSceneNodeTransform")
    #expect(transformResult.generation == DocumentGeneration(3))
    #expect(instance.definitionID == definition.id)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.localTransform == sceneNodeTransform)
}

@MainActor
@Test func agentDispatchesRectangularPatternArrayThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Array Source",
                rootSceneNodeIDs: [bodySceneNodeID]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Rectangular Array",
                definitionID: definition.id,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(12.0, .millimeter),
                            copyCount: 3,
                            distanceMode: .spacing
                        ),
                        secondAxis: PatternArrayLinearAxis(
                            direction: .unitZ,
                            distance: .length(30.0, .millimeter),
                            copyCount: 2,
                            distanceMode: .extent
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }

    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let firstInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]]
    )
    let fourthInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[3]]
    )

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 11)
    #expect(firstInstance.localTransform.matrix.values[12] == 0.012)
    #expect(fourthInstance.localTransform.matrix.values[12] == 0.0)
    #expect(fourthInstance.localTransform.matrix.values[14] == 0.015)
}

@Test func agentRejectsDirectEditsToPatternOwnedComponentInstances() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Owned Instance Source",
                rootSceneNodeIDs: [bodySceneNodeID]
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Agent Owned Instance Source"
    })

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Owned Instance Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10.0, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: .componentInstance
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Owned Instance Array"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let generationBeforeRejectedEdits = session.generation
    let rejectedCommands: [(AutomationCommand, String)] = [
        (
            .setComponentInstanceVisibility(id: outputInstanceID, isVisible: false),
            "visibility is controlled by the pattern source"
        ),
        (
            .setComponentInstanceLock(id: outputInstanceID, isLocked: true),
            "locks are controlled by the pattern source"
        ),
        (
            .setComponentInstanceTransform(
                id: outputInstanceID,
                localTransform: try agentTranslationTransform(x: 0.01, y: 0.0, z: 0.0)
            ),
            "transforms are controlled by the pattern source"
        ),
    ]

    for (command, expectedMessageFragment) in rejectedCommands {
        let response = server.handle(
            .execute(
                sessionID: sessionID,
                command: command,
                expectedGeneration: generationBeforeRejectedEdits
            )
        )
        guard case .failure(let error) = response else {
            #expect(Bool(false))
            return
        }
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains(expectedMessageFragment))
        #expect(session.generation == generationBeforeRejectedEdits)
    }
}

@Test func agentDispatchesRadialPatternArrayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Radial Array Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Radial Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Radial Array",
                definitionID: definition.id,
                distribution: .radial(
                    RadialPatternArray(
                        angularAxis: PatternArrayAngularAxis(
                            center: .origin,
                            axis: .unitZ,
                            angle: .angle(90.0, .degree),
                            copyCount: 3,
                            angleMode: .spacing
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Radial Array"
    })

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 3)
}

@Test func agentDispatchesCurvePatternArrayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Curve Array Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Curve Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Curve Array",
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
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let arrayResult) = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Curve Array"
    })

    #expect(arrayResult.commandName == "createPatternArray")
    #expect(arrayResult.generation == DocumentGeneration(3))
    #expect(source.outputInstanceIDs.count == 3)
}

@Test func agentDispatchesPatternArrayLifecycleCommandsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Array Lifecycle Body",
                plane: .xy,
                width: .length(10.0, .millimeter),
                height: .length(6.0, .millimeter),
                depth: .length(4.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = createResponse else {
        #expect(Bool(false))
        return
    }
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Lifecycle Source",
                rootSceneNodeIDs: [bodySceneNode.id]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let arrayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPatternArray(
                name: "Agent Lifecycle Array",
                definitionID: definition.id,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(6.0, .millimeter),
                            copyCount: 2
                        )
                    )
                ),
                outputMode: .componentInstance
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command = arrayResponse else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Agent Lifecycle Array"
    })
    let firstOutputID = try #require(source.outputInstanceIDs.first)

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .updatePatternArray(
                id: source.id,
                name: "Agent Updated Array",
                definitionID: nil,
                distribution: .rectangular(
                    RectangularPatternArray(
                        firstAxis: PatternArrayLinearAxis(
                            direction: .unitX,
                            distance: .length(12.0, .millimeter),
                            copyCount: 1
                        )
                    )
                ),
                outputMode: nil
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])

    let explodeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .explodePatternArray(id: source.id),
            expectedGeneration: DocumentGeneration(4)
        )
    )
    guard case .command(let explodeResult) = explodeResponse else {
        #expect(Bool(false))
        return
    }
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let outputFeatureID = try #require(
        agentFeatureID(
            inSceneSubtreeRootedAt: outputSceneNodeID,
            document: session.document
        )
    )

    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updateResult.generation == DocumentGeneration(4))
    #expect(updatedSource.name == "Agent Updated Array")
    #expect(updatedSource.outputInstanceIDs == [firstOutputID])
    #expect(explodeResult.commandName == "explodePatternArray")
    #expect(explodeResult.generation == DocumentGeneration(5))
    #expect(session.document.productMetadata.patternArrays[source.id] == nil)
    #expect(session.document.productMetadata.componentInstances[firstOutputID] == nil)
    #expect(session.document.cadDocument.designGraph.nodes[outputFeatureID] != nil)
}

@Test func agentDispatchesCircleModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedCircle(
                name: "Agent Cylinder",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(6.0, .millimeter),
                depth: .length(10.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedCircle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesSketchPrimitiveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesCurveCurvatureDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Curvature Display Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(5.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCurveCurvatureDisplay(
                target: target,
                isVisible: true,
                combScale: 0.2
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setCurveCurvatureDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID]?.combScale == 0.2)
}

@Test func agentDispatchesPointDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Point Display Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                    SketchPoint(x: .length(0.002, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.006, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setPointDisplay(
                target: target,
                isVisible: false
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setPointDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == false)
}

@Test func agentDispatchesPolygonSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolygonSketch(
                name: "Agent Polygon",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                sides: 5,
                sizingMode: .inradius,
                inclinationMode: .vertical,
                rotationAngle: .angle(0.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createPolygonSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 5)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    let polygonNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(polygonNode.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(polygonNode.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.vertical.rawValue))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesArcSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createArcSketch(
                name: "Agent Arc",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(135.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .arc = entity else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func agentDispatchesSketchConstraintCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(agentSingleSketchEntityID(in: session.document, featureID: featureID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: featureID))
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityID == lineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesFixedSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Fixed Spline Point",
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
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .failure(let error) = moveResponse else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSlideSketchSplineControlPointsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Slide CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: [1, 2],
                direction: .normal,
                distance: .length(1.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "slideSketchSplineControlPoints")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.0015) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.0015) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesCoincidentSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplinePointConstraintDocument(name: "Agent Coincident Spline Point")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(
                    .splineControlPoint(entity: setup.splineID, index: 0),
                    .entity(setup.pointID)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let point = try #require(summary.entries.first { $0.entityID == setup.pointID.description })
    let center = try #require(point.center)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(center.x - 0.0) < 1.0e-12)
    #expect(abs(center.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Smooth Spline",
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
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .smoothSplineControlPoint(entity: entityID, index: 3)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    let outgoingHandle = try #require(updatedSpline.controlPoints.dropFirst(4).first)
    let constraint = try #require(updatedSpline.constraints.first { $0.kind == "smoothSplineControlPoint" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):3"])
    #expect(abs(outgoingHandle.x - 0.005) < 1.0e-12)
    #expect(abs(outgoingHandle.y - (-0.001)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSplineEndpointTangentConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplineLineTangentSketchDocument(name: "Agent Spline Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .splineEndpointTangent(
                    spline: setup.splineID,
                    endpoint: .start,
                    line: setup.lineID
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityID == setup.splineID.description })
    let alignedHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let constraint = try #require(spline.constraints.first { $0.kind == "splineEndpointTangent" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.splineID.description):start",
        "entity:\(setup.lineID.description)",
    ])
    #expect(abs(alignedHandle.x - 0.005) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesTangentSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangentSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Smoothness")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .smoothSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedEndpoint = try #require(secondSpline.controlPoints.first)
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "smoothSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(alignedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsParallelConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Parallel Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .parallel(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(first, second))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsEqualLengthConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Equal Length Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalLength(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(agentLineEntryLength(first) - agentLineEntryLength(second)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsTangentConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineCircleTangentSketchDocument(name: "Agent Tangent Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangent(setup.lineID, setup.circleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityID == setup.circleID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs((circle.center?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((circle.center?.y ?? -1.0) - (circle.radius ?? -2.0)) < 1.0e-12)
    #expect(abs((circle.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsCircularConstraintsAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoCircleSketchDocument(name: "Agent Circular Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let concentricResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .concentric(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let radiusResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalRadius(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let concentricResult) = concentricResponse,
          case .command(let radiusResult) = radiusResponse else {
        Issue.record("Agent must return command results.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstCircleID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondCircleID.description })
    #expect(concentricResult.commandName == "addSketchConstraint")
    #expect(radiusResult.commandName == "addSketchConstraint")
    #expect(concentricResult.didMutate)
    #expect(radiusResult.didMutate)
    #expect(abs((first.center?.x ?? -1.0) - (second.center?.x ?? -2.0)) < 1.0e-12)
    #expect(abs((first.center?.y ?? -1.0) - (second.center?.y ?? -2.0)) < 1.0e-12)
    #expect(abs((first.radius ?? -1.0) - (second.radius ?? -2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsParameterExpressionAndListsParameters() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let commandResponse = server.handle(
        .setParameterExpression(
            sessionID: sessionID,
            name: "height",
            expression: "width * 2",
            kind: .length,
            defaults: ParameterExpressionDefaults(),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = commandResponse else {
        #expect(Bool(false))
        return
    }

    let listResponse = server.handle(
        .parameters(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .parameters(let parameterList) = listResponse else {
        #expect(Bool(false))
        return
    }
    let height = try #require(parameterList.parameters.first { $0.name == "height" })

    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(parameterList.parameters.count == 2)
    #expect(height.expression == "(width * 2)")
    #expect(abs((height.resolvedValue ?? 0.0) - 0.02) < 0.000_000_000_001)
}

@MainActor
@Test func agentDeletesParameterThroughAutomationCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .deleteParameter(name: "width"),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "deleteParameter")
    #expect(result.message == "Parameter width deleted.")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
}

@MainActor
@Test func agentEvaluatesOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Eval Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .evaluate(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .evaluation(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    #expect(snapshot.status == .valid)
    #expect(snapshot.evaluatedGeneration == DocumentGeneration(1))
    #expect(snapshot.bodyCount == 1)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.profileAreaSquareMeters - 0.0002) < 0.000_000_000_001)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresGeneratedEdgeOffsetDirectEditSolidWithoutDoubleCountingSourceBody() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let measureResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .measurement(let measurement) = measureResponse else {
        #expect(Bool(false))
        return
    }
    let solid = try #require(measurement.solids.first)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(solid.featureID == offsetFeatureID.description)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000008) < 1.0e-12)
    #expect(surfaceArea > 0.0)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentExecutesSymmetricGeneratedEdgeOffsetDirectEditSolid() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    isSymmetric: true,
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent symmetric Offset Edge must create an EdgeOffset feature.")
        return
    }

    let measuredResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .measurement(let measurement) = measuredResponse else {
        #expect(Bool(false))
        return
    }
    let evaluatedTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = evaluatedTopology.entries.filter { entry in
        entry.kind == .edge &&
            entry.sourceFeatureID == offsetFeatureID.description &&
            entry.generatedRole == "edgeOffset" &&
            entry.subshapeRole == "offsetEdge"
    }

    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(edgeOffset.isSymmetric)
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(generatedOffsetEdges.count == 2)
    #expect(evaluatedTopology.counts.faceCount == 8)
    #expect(evaluatedTopology.counts.edgeCount == 18)
    #expect(evaluatedTopology.counts.vertexCount == 12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentMeasuresSelectedOpenSessionBodyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Selected Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    #expect(session.selectSceneNode(bodyNodeID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.scope == .selection)
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionMeshesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Mesh Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .meshSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .meshSummary(let meshSummary) = response else {
        #expect(Bool(false))
        return
    }
    let bounds = try #require(meshSummary.bounds)
    #expect(meshSummary.bodyCount == 1)
    #expect(meshSummary.vertexCount > 0)
    #expect(meshSummary.triangleCount > 0)
    #expect(meshSummary.indexedElementCount == meshSummary.triangleCount * 3)
    #expect(abs(bounds.sizeX - 0.01) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionSketchEntitiesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Guide Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .sketchEntitySummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.sketchCount == 1)
    #expect(summary.counts.entityCount == 1)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    #expect(abs((arc.radius ?? -1.0) - 0.008) < 0.000_000_001)
    #expect(abs((arc.end?.y ?? -1.0) - 0.008) < 0.000_000_001)
    let target = try #require(arc.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(selection.selectedTargets == [target])
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesSelectsAndOffsetsRoundRegionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Selectable Region",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing regions.")
        return
    }
    #expect(summary.counts.regionCount == 1)
    let region = try #require(summary.regions.first)
    #expect(abs(region.areaSquareMeters - 0.000_06) < 1.0e-12)
    let target = try #require(region.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        Issue.record("Agent must select a region target.")
        return
    }
    #expect(selection.selectedTargets == [target])

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a round region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.areaSquareMeters > 0.000_095)
    #expect(offsetRegion.areaSquareMeters < 0.000_096)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSymmetricNaturalRegionOffset() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Round Region Gap Fill",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for symmetric Offset Region.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegions = after.regions.filter { $0.sourceFeatureID != region.sourceFeatureID }
    let areas = offsetRegions.map(\.areaSquareMeters).sorted()
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 3)
    #expect(abs((areas.first ?? 0.0) - 0.000_032) < 1.0e-12)
    #expect(abs((areas.last ?? 0.0) - 0.000_096) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesNaturalOffsetForConcaveSourceRegion() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentConcaveLineLoopDocument())
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing a concave region.")
        return
    }
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a concave region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount == 6)
    #expect(offsetRegion.boundarySegmentCount == 6)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_108) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesCombinedOffsetRegions() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region A",
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
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(11.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(21.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetRegions(
                targets: targets,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                combinesRegions: true
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetRegions command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 4)
    #expect(unionRegion.boundarySegmentCount == 4)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_184) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.3, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01031, y: 0.00002),
            options: SnapResolutionOptions(
                usesGrid: true,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 4
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineEnd)
    #expect(result.selectedCandidate?.source?.selectionTarget != nil)
    #expect(abs(result.resolvedPoint.x - 0.0103) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .grid })
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Measured Gap",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0.002, y: 0.003, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.009, y: 0.003, z: 0.0), role: .end),
            ]
        )
    )
    let measurement = try #require(document.productMetadata.measurements[measurementID])
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00201, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(result.selectedCandidate?.kind == .measurementPoint)
    #expect(candidate.measurementSource?.sceneNodeID == measurement.sceneNodeID)
    #expect(candidate.measurementSource?.name == "Agent Measured Gap")
    #expect(candidate.measurementSource?.role == .start)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchReferenceMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Measurement",
            kind: .distance,
            anchors: [
                .sketchReference(featureID: featureID, reference: .lineEnd(lineEntry.key), role: .end),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01001, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-reference measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchReference)
    #expect(candidate.measurementSource?.sketchReference?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchReference?.reference == .lineEnd(lineEntry.key))
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.010) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchCurveParameterMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Curve Parameter",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Curve Parameter Measurement",
            kind: .distance,
            anchors: [
                .sketchCurveParameter(featureID: featureID, entityID: lineEntry.key, parameter: 0.5, role: .point),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00501, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-curve-parameter measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchCurveParameter)
    #expect(candidate.measurementSource?.sketchCurveParameter?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchCurveParameter?.entityID == lineEntry.key)
    #expect(candidate.measurementSource?.sketchCurveParameter?.parameter == 0.5)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.005) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSnapProjectedOntoActiveConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Projected Snap Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    _ = try #require(
        session.createConstructionPlane(
            name: "Agent Right CPlane",
            plane: .yz
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.006, y: 0.00005),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                usesConstructionPlaneProjection: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a construction-plane projected snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineClosest)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentResolvesGeneratedTopologySnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let midpoint = CADCore.Point2D(
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5
    )
    let edgeTarget = try #require(edge.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: midpoint.x + 0.00001, y: midpoint.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a generated topology snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .edgeMidpoint &&
            candidate.topologySource?.persistentName == edge.persistentName
    })
    #expect(candidate.topologySource?.selectionTarget == edgeTarget)
    #expect(abs(candidate.point.x - midpoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - midpoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesPolySplineSurfaceCVSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Agent Surface CV Snap PolySpline",
        sourceMesh: agentPolySplineQuadMesh()
    ))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertex = try #require(topology.entries.first { entry in
        entry.kind == .vertex
            && PolySplineSurfaceVertexTarget.canParsePersistentName(entry.persistentName)
            && entry.start != nil
            && entry.selectionTarget() != nil
    })
    let point = try #require(vertex.start)
    let vertexTarget = try #require(vertex.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: point.x + 0.00001, y: point.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a PolySpline Surface CV snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceControlVertex
            && candidate.topologySource?.persistentName == vertex.persistentName
    })
    #expect(result.selectedCandidate?.kind == .surfaceControlVertex)
    #expect(candidate.label == "Surface CV")
    #expect(candidate.topologySource?.selectionTarget == vertexTarget)
    #expect(candidate.topologySource?.worldPoint == point)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesRegionCenterSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Region Snap Rectangle",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00002, y: -0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a region snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .regionCenter)
    #expect(result.selectedCandidate?.regionSource?.featureID == featureID)
    #expect(result.selectedCandidate?.regionSource?.sceneNodeID != nil)
    #expect(abs(result.resolvedPoint.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveIntersectionSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Horizontal",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Vertical",
            plane: .xy,
            start: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00604, y: 0.00403),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an intersection snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveIntersection)
    #expect(result.selectedCandidate?.source != nil)
    #expect(result.selectedCandidate?.relatedSource != nil)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesTangentSnapWithReferencePointWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Snap Tangent Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let expected = CADCore.Point2D(
        x: cos(Double.pi / 6.0) * 0.004,
        y: sin(Double.pi / 6.0) * 0.004
    )
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: expected.x + 0.00002, y: expected.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: CADCore.Point2D(x: 0.0, y: 0.008)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a tangent snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveTangent)
    #expect(abs(result.resolvedPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveAxisSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Axis Line",
            plane: .yz,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.0, y: 0.004)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an axis snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "Y")
    #expect(result.selectedCandidate?.axisSource?.kind == .y)
    #expect(result.selectedCandidate?.axisSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveCoordinatePlaneSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap YZ Plane Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.005, y: 0.0)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                suppressedCandidateKinds: [.curveAxis],
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a coordinate-plane snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveCoordinatePlane)
    #expect(result.selectedCandidate?.label == "YZ")
    #expect(result.selectedCandidate?.coordinatePlaneSource?.kind == .yz)
    #expect(result.selectedCandidate?.coordinatePlaneSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesControlVertexSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Snap CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00202, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a CV snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .controlVertex)
    #expect(result.selectedCandidate?.label == "CV")
    #expect(result.selectedCandidate?.source?.controlPointIndex == 1)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentOffsetsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Source Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    let offset = try #require(lines.first { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(offset.sourceFeatureID != sourceLine.sourceFeatureID)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentOffsetsSketchVertexThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Vertex Rectangle",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetSketchVertex(
                target: target,
                handle: .lineEnd,
                distance: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetSketchVertex command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Curve Vertex Rectangle",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .lineEnd
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcStart
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.upperArcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcEnd
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc-arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Slot Source Line",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineChainSlotDocument(name: "Agent Slot Source Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineIDs[0].description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Slot Chain",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-chain Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromSourceArcAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for a source arc.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Arc Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for an arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineArcChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineArcChainSlotDocument(name: "Agent Slot Source Line Arc Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-arc chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Arc Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Line Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentActivatesSlotModeThroughOffsetCurve() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Slot Source Line",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve Slot mode command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Offset Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesOpenSessionCurvesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Analysis Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 1)
    let spline = try #require(analysis.curves.first { $0.curveKind == .spline })
    #expect(spline.samples.count == 17)
    #expect(spline.maxAbsCurvature > 1.0)
    #expect(spline.selectionComponentID?.hasPrefix(SelectionComponentID.sketchEntityPrefix) == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesConstrainedEndpointContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Curve Continuity")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let constraintResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = constraintResponse else {
        #expect(Bool(false))
        return
    }

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 2)
    #expect(analysis.counts.continuityJoinCount == 1)
    let join = try #require(analysis.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident"])
    #expect(join.requiredContinuity == .g0)
    #expect(join.firstReference == "lineEnd:\(setup.firstLineID.description)")
    #expect(join.secondReference == "lineStart:\(setup.secondLineID.description)")
    #expect(join.continuity == .g0)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect((join.tangentAngle ?? 0.0) > 1.0e-4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesBridgeCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Bridge Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBridgeCurve(
                featureID: setup.featureID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: .lineEnd(setup.firstLineID)
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: .lineStart(setup.secondLineID)
                ),
                continuity: .g1
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let bridgeID = try #require(sketch.entities.first { _, entity in
        if case .spline = entity {
            return true
        }
        return false
    }?.key)
    let source = try #require(session.document.productMetadata.bridgeCurveSources.values.first)
    let analysisResponse = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = analysisResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createBridgeCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 3)
    #expect(source.featureID == setup.featureID)
    #expect(source.entityID == bridgeID)
    #expect(source.firstEndpoint.reference == .lineEnd(setup.firstLineID))
    #expect(source.secondEndpoint.reference == .lineStart(setup.secondLineID))
    #expect(source.continuity == .g1)
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineEnd(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineStart(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    let bridgeCurve = try #require(analysis.curves.first { $0.entityID == bridgeID.description })
    #expect(bridgeCurve.curveKind == .spline)
    #expect(analysis.continuityJoins.contains { join in
        join.firstEntityID == bridgeID.description || join.secondEntityID == bridgeID.description
    })

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setBridgeCurveParameters(
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
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let updatedSource = try #require(session.document.productMetadata.bridgeCurveSources[source.id])
    let updatedEntity = try #require(updatedSketch.entities[bridgeID])
    guard case .spline(let updatedSpline) = updatedEntity else {
        #expect(Bool(false))
        return
    }
    let updatedControlPoints = try updatedSpline.controlPoints.map { point in
        try agentResolvedSketchPoint(point, in: session.document)
    }

    #expect(updateResult.commandName == "setBridgeCurveParameters")
    #expect(updateResult.didMutate)
    #expect(updateResult.generation == DocumentGeneration(2))
    #expect(updatedSketch.entities.count == 3)
    #expect(updatedSource.entityID == bridgeID)
    #expect(updatedSource.trimsSourceCurves)
    #expect(updatedSource.firstEndpoint.reference == .lineStart(setup.firstLineID))
    #expect(updatedSource.firstEndpoint.parameter == nil)
    #expect(updatedSource.firstEndpoint.reversesSense == false)
    #expect(updatedSource.secondEndpoint.reference == .lineEnd(setup.secondLineID))
    #expect(updatedSource.secondEndpoint.parameter == nil)
    #expect(updatedSource.continuity == .g1)
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineStart(setup.firstLineID)
    )))
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineEnd(setup.secondLineID)
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .end,
        line: setup.secondLineID
    )))
    #expect(updatedControlPoints.count == 7)
    #expect(nearlyEqualAgent(updatedControlPoints[0].x, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[0].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[1].x, 0.001182384266129633))
    #expect(nearlyEqualAgent(updatedControlPoints[1].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[2].x, 0.0016666666666666668))
    #expect(nearlyEqualAgent(updatedControlPoints[2].y, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[3].x, 0.00125))
    #expect(nearlyEqualAgent(updatedControlPoints[3].y, 0.00375))
    #expect(nearlyEqualAgent(updatedControlPoints[4].x, 0.0008333333333333334))
    #expect(nearlyEqualAgent(updatedControlPoints[4].y, 0.005))
    #expect(nearlyEqualAgent(updatedControlPoints[5].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[5].y, 0.008817615733870367))
    #expect(nearlyEqualAgent(updatedControlPoints[6].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[6].y, 0.0075))
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesSketchEntityEditCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Editable Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchArcParameters(
                target: target,
                center: nil,
                radius: .length(6.0, .millimeter),
                startAngle: nil,
                endAngle: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityKind == "arc" })
    #expect(result.commandName == "setSketchArcParameters")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi * 2.0 / 3.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchEntityDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Dimensioned Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Angle Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (130.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Fixed End Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let createdArc = try #require(createdSummary.entries.first { $0.entityKind == "arc" })
    let featureID = try #require(UUID(uuidString: createdArc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: createdArc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityID == createdArc.entityID })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (-40.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchLineAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Angled Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(90.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndLineDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Fixed End Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(createdSummary.entries.first { $0.entityKind == "line" })
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let fixedLine = try #require(summary.entries.first { $0.entityID == line.entityID })
    let target = try #require(fixedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedLine.start?.x ?? -1.0) - (-0.015)) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCreatesAndMovesSplineControlPointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    #expect(spline.controlPoints.count == 4)

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 1,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a spline edit command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityKind == "spline" })

    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.004) < 1.0e-12)

    let insertResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .insertSketchSplineControlPoint(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let insertResult) = insertResponse else {
        Issue.record("Agent must return a spline control-point insertion command result.")
        return
    }
    let insertedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let insertedSpline = try #require(insertedSummary.entries.first { $0.entityKind == "spline" })
    #expect(insertResult.commandName == "insertSketchSplineControlPoint")
    #expect(insertResult.didMutate)
    #expect(insertResult.generation == DocumentGeneration(3))
    #expect(insertedSpline.controlPoints.count == 7)

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .points(controlPointCount: 4)
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve rebuild command result.")
        return
    }
    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityKind == "spline" })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(4))
    #expect(rebuiltSpline.entityID == insertedSpline.entityID)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentRefitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Refit Spline",
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
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .refit(
                    tolerance: .length(20.0, .millimeter),
                    keepsCorners: false
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve refit command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
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
@Test func agentExplicitlyRebuildsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Explicit Rebuild Spline",
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
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .explicitControl(
                    degree: 3,
                    spanCount: 1,
                    weight: 0.5
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve Explicit Control command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
    #expect(report.method == .explicitControl)
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
@Test func agentExtrudesClosedSplineProfileThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline Profile",
                plane: .xy,
                spline: agentClosedBezierCircleSpline(radius: 0.01)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a closed spline profile.")
        return
    }
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Spline Body",
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .length(0.005, .meter),
                direction: .normal
            ),
            expectedGeneration: createResult.generation
        )
    )
    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must extrude the closed spline profile.")
        return
    }

    #expect(createResult.commandName == "createSplineSketch")
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func agentCreatesSweepSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Sweep Path",
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
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }

    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileID))])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesCurveSectionSheetSweepThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let sectionID = try document.createLineSketch(
        name: "Agent Curve Sheet Section",
        plane: .xy,
        start: agentSketchPoint(x: -0.002, y: 0.0),
        end: agentSketchPoint(x: 0.002, y: 0.0)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Curve Sheet Path",
        plane: .yz,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.0, y: 0.020)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Curve Sheet Sweep",
                sections: [.curve(SweepCurveSectionReference(featureID: sectionID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(resultKind: .sheet)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a curve-section sheet sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    let evaluated = try CADPipeline.modelingDefault(for: session.document).evaluate(
        session.document.cadDocument
    )
    let body = try #require(evaluated.brep.bodies.values.first)

    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.curve(SweepCurveSectionReference(featureID: sectionID))])
    #expect(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepID)
    }?.object?.sourceSection == .curve(sectionID))
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(body.kind == .sheet)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesRevolveSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(14.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createRevolve(
                name: "Agent Revolved Body",
                profile: ProfileReference(featureID: profileID),
                axis: RevolveAxis(origin: .origin, direction: .unitY),
                angle: .angle(180.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a revolve command result.")
        return
    }
    let revolveID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[revolveID])
    guard case .revolve(let revolve) = feature.operation else {
        Issue.record("Agent must create a revolve feature.")
        return
    }

    #expect(result.commandName == "createRevolve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(revolve.profile == ProfileReference(featureID: profileID))
    #expect(revolve.axis == RevolveAxis(origin: .origin, direction: .unitY))
    #expect(revolve.angle == .angle(180.0, .degree))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesConnectedMultiEntitySweepPathAndSweepThroughAutomation() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Connected Sweep Profile",
        plane: .xy,
        width: .length(2.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let pathResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSketch(
                name: "Agent Connected Sweep Path",
                sketch: Sketch(
                    plane: .yz,
                    entities: [
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(0.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            )
                        )),
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(8.0, .millimeter),
                                y: .length(25.0, .millimeter)
                            )
                        )),
                    ]
                ),
                geometryRole: .curve
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let pathResult) = pathResponse else {
        Issue.record("Agent must return a createSketch command result.")
        return
    }
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)

    let sweepResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Connected Multi-Path Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(cornerStyle: .mitre)
            ),
            expectedGeneration: pathResult.generation
        )
    )
    guard case .command(let sweepResult) = sweepResponse else {
        Issue.record("Agent must return a connected sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathFeature = try #require(session.document.cadDocument.designGraph.nodes[pathID])
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])

    guard case .sketch(let pathSketch) = pathFeature.operation,
          case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Agent must create a sketch path and a sweep feature.")
        return
    }
    #expect(pathResult.commandName == "createSketch")
    #expect(pathSketch.entities.count == 2)
    #expect(sweepResult.commandName == "createSweep")
    #expect(sweepResult.generation == DocumentGeneration(2))
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(sweepResult.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentMovesParallelLineAngleThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineConstrainedSketchDocument(
        name: "Agent Parallel Line Pair",
        constraint: { .parallel($0, $1) }
    )
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(0.0, .meter),
                deltaY: .length(0.010, .meter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(updatedSummary.entries.first { $0.entityID == setup.firstLineID.description })
    let movedFollower = try #require(updatedSummary.entries.first { $0.entityID == setup.secondLineID.description })
    let expectedFollowerEndOffset = 0.005 / sqrt(2.0)
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(movedSource, movedFollower))
    #expect(abs((movedFollower.end?.x ?? -1.0) - expectedFollowerEndOffset) < 1.0e-12)
    #expect(abs((movedFollower.end?.y ?? -1.0) - (0.005 + expectedFollowerEndOffset)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesConstrainedRectanglePointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Move Constrained Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(2.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((movedBottom.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsConstrainedRectangleSideDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Dimensioned Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let dimension = try #require(updatedBottom.dimensions.first { $0.kind == "distance" })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentConvertsSketchLineToArcThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToArc(
                target: target,
                sagitta: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "convertSketchLineToArc")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arc.entityKind == "arc")
    #expect(abs((arc.radius ?? -1.0) - 0.00725) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentConvertsSketchLineToSplineThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToSpline(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let firstHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let secondHandle = try #require(spline.controlPoints.dropFirst(2).first)
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(spline.entityKind == "spline")
    #expect(spline.controlPoints.count == 4)
    #expect(abs(firstHandle.x - 0.003) < 1.0e-12)
    #expect(abs(secondHandle.x - 0.006) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentReversesSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Reverse Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .reverseSketchCurve(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((reversedLine.start?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExtendsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Extend Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try agentPointHandleSelectionTarget(line, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extendSketchCurve(
                target: target,
                distance: .length(3.0, .millimeter),
                shape: .natural
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((extendedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((extendedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Source Fillet Rectangle",
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
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(agentBottomRectangleLine(in: summary))
    let target = try agentPointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(2.0, .millimeter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter {
        $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc"
    }
    let filletArc = try #require(arcs.first)
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
@Test func agentAppliesSketchCornerTreatmentToLineArcCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let target = try agentPointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArc = try #require(arcs.first { $0.entityID == setup.arcID.description })
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
@Test func agentAppliesSketchCornerTreatmentToCurvePairThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let sourceArc = try #require(summary.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceLine.selectionTarget())
    let adjacentTarget = try #require(sourceArc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
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
@Test func agentSplitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsSketchArcCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Split Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(120.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter { $0.entityKind == "arc" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentTrimsSketchCurveSegmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Trim Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let splitResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = splitResponse else {
        Issue.record("Agent must split the sketch curve before trimming.")
        return
    }
    let splitSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let trimmedLine = try #require(splitSummary.entries.first { entry in
        entry.entityKind == "line" && entry.entityID != line.entityID
    })
    let trimmedTarget = try #require(trimmedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .trimSketchCurveSegment(target: trimmedTarget),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "trimSketchCurveSegment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(lines.count == 1)
    #expect(lines.first?.entityID == line.entityID)
    #expect(abs((lines.first?.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((lines.first?.end?.x ?? -1.0) - 0.003) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveWithCircleCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Cut Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Target" })
    let cutterCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Cut Target" }
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
            abs((entry.end?.x ?? -1.0) - 0.007) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.007) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCircleTargetWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Target Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Target Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(cutterSegments.count == 1)
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
@Test func agentCutsSketchArcCurveWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Arc Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Arc Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetArc = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
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
@Test func agentSummarizesOpenSessionTopologyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Agent Topology Cylinder",
            plane: .xy,
            center: .init(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(10.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount == 6)
    #expect(topologySummary.counts.edgeCount == 12)
    #expect(topologySummary.counts.vertexCount == 8)
    let cylinderFaces = topologySummary.entries.filter { $0.kind == .face && $0.surfaceKind == "cylinder" }
    let circularEdges = topologySummary.entries.filter { $0.kind == .edge && $0.curveKind == "circle" }
    #expect(cylinderFaces.count == 4)
    #expect(circularEdges.count == 8)
    #expect(cylinderFaces.allSatisfy(hasExpectedAgentCylinderDefinition))
    #expect(circularEdges.allSatisfy(hasExpectedAgentCircularEdgeDefinition))
    #expect(topologySummary.entries.allSatisfy { $0.sceneNodeID != nil })
    let vertexEntry = try #require(topologySummary.entries.first { $0.kind == .vertex })
    let vertexTarget = try #require(vertexEntry.selectionTarget())
    guard case .vertex(let vertexComponentID) = vertexTarget.component else {
        Issue.record("Agent topology summary must expose vertex selection targets.")
        return
    }
    #expect(vertexComponentID.generatedTopologyPersistentName == vertexEntry.persistentName)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesCellUnionBooleanTopologyWithoutMutation() async throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Target Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-20.0, .millimeter),
            y: .length(-20.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let targetBodyID = try document.extrudeProfile(
        name: "Agent Cell Union Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(10.0, .millimeter),
        direction: .normal
    )
    let toolProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Tool Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-5.0, .millimeter),
            y: .length(-5.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25.0, .millimeter),
            y: .length(25.0, .millimeter)
        )
    )
    let pathID = try document.createLineSketch(
        name: "Agent Cell Union Boolean Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    _ = try document.createSweep(
        name: "Agent Cell Union Boolean Result Sweep",
        sections: [.profile(ProfileReference(featureID: toolProfileID))],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .difference)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let face = try #require(topologySummary.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"
    })
    let edge = try #require(topologySummary.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"
    })
    let vertex = try #require(topologySummary.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "cellUnion:component:0:vertex:x:x1:y:y1:z:maxZ"
    })
    #expect(face.selectionTarget() != nil)
    #expect(edge.selectionTarget() != nil)
    #expect(vertex.selectionTarget() != nil)
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount > 6)
    #expect(topologySummary.counts.edgeCount > 12)
    #expect(topologySummary.counts.vertexCount > 8)
    #expect(session.generation == DocumentGeneration(0))
}

private func hasExpectedAgentCylinderDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.surfaceRadius,
          let axis = entry.surfaceAxis else {
        return false
    }
    return abs(radius - 0.01) < 0.000_000_001
        && abs(axis.x) < 0.000_000_001
        && abs(axis.y) < 0.000_000_001
        && abs(abs(axis.z) - 1.0) < 0.000_000_001
}

private func hasExpectedAgentCircularEdgeDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.curveRadius,
          let center = entry.curveCenter,
          let normal = entry.curveNormal,
          let xAxis = entry.curveParameterXAxis,
          let yAxis = entry.curveParameterYAxis,
          let parameterRange = entry.edgeParameterRange else {
        return false
    }
    let span = abs(parameterRange.end - parameterRange.start)
    let xLength = sqrt(xAxis.x * xAxis.x + xAxis.y * xAxis.y + xAxis.z * xAxis.z)
    let yLength = sqrt(yAxis.x * yAxis.x + yAxis.y * yAxis.y + yAxis.z * yAxis.z)
    let xDotY = xAxis.x * yAxis.x + xAxis.y * yAxis.y + xAxis.z * yAxis.z
    let xDotNormal = xAxis.x * normal.x + xAxis.y * normal.y + xAxis.z * normal.z
    let yDotNormal = yAxis.x * normal.x + yAxis.y * normal.y + yAxis.z * normal.z
    return abs(radius - 0.01) < 0.000_000_001
        && abs(center.x) < 0.000_000_001
        && abs(center.y) < 0.000_000_001
        && abs(abs(normal.z) - 1.0) < 0.000_000_001
        && abs(xLength - 1.0) < 0.000_000_001
        && abs(yLength - 1.0) < 0.000_000_001
        && abs(xDotY) < 0.000_000_001
        && abs(xDotNormal) < 0.000_000_001
        && abs(yDotNormal) < 0.000_000_001
        && parameterRange.start.isFinite
        && parameterRange.end.isFinite
        && span > 0.0
        && span < Double.pi * 2.0
}

@MainActor
@Test func agentSelectsGeneratedTopologyVertexTargetWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let dirty = session.isDirty
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: generation
        )
    )

    guard case .selection(let result) = response else {
        Issue.record("Agent must return a selection result.")
        return
    }
    #expect(result.selectedTargets == [target])
    #expect(session.selection.selectedTargets == [target])
    #expect(result.generation == generation)
    #expect(session.generation == generation)
    #expect(result.dirty == dirty)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentSavesOpenFileBackedSessionAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let url = temporaryDirectory.appendingPathComponent("agent-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try DocumentFileService().load(from: url))
    _ = try session.execute(
        .renameDocument(name: "Saved Live"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: url, id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .save(let result) = response else {
        #expect(Bool(false))
        return
    }
    let loaded = try DocumentFileService().load(from: url)
    #expect(result.path == url.path)
    #expect(result.generation == DocumentGeneration(1))
    #expect(!result.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved Live")
}

@Test func agentSaveRejectsPathlessSession() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    server.register(session: EditorSession(document: .empty(named: "Pathless")), id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message.contains("file path"))
}

@MainActor
@Test func agentExportsOpenSessionWithoutMutation() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let outputURL = temporaryDirectory.appendingPathComponent("agent-box.stl")
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Export Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: DocumentGeneration(1),
            options: ExportOptions(),
            dryRun: false
        )
    )

    guard case .export(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(session.generation == DocumentGeneration(1))
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func agentRejectsGenerationMismatchBeforeMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = try AutomationRunner().execute(.setDisplayUnit(.meter), in: session)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Rejected"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

@Test func agentReportsSessionNotFoundForUnknownSession() async throws {
    let server = AgentCommandController()
    let response = server.handle(
        .execute(
            sessionID: UUID(),
            command: .validateDocument,
            expectedGeneration: nil
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .sessionNotFound)
}

@MainActor
@Test func mainActorAgentBridgeRoutesSessionMutations() async throws {
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)

    let response = bridge.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Main Actor Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Main Actor Live")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughMainActorBridge() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let socketPath = AgentSocketPath(socketURL.path)
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)
    let listener = AgentSocketListener(
        mainActorBridge: bridge,
        socketPath: socketPath
    )

    try await listener.start()
    do {
        let request = AgentRequest.execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Socket Main Actor"),
            expectedGeneration: DocumentGeneration(0)
        )
        let response = try await sendThroughDetachedClient(request, socketPath: socketPath)

        guard case .command(let result) = response else {
            #expect(Bool(false))
            await listener.stop()
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))
        #expect(session.document.cadDocument.metadata.name == "Socket Main Actor")
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoundTripsStatusThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let server = AgentCommandController()
    server.register(session: EditorSession(document: .empty(named: "Open")))

    try await withRunningListener(controller: server, socketURL: socketURL) { listener, client in
        let response = try client.send(.status)

        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(await listener.isRunning)
        #expect(status.running)
        #expect(status.socketPath == socketURL.path)
        #expect(status.sessionCount == 1)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentCommandController()
    server.register(session: EditorSession(), id: sessionID)

    try await withRunningListener(controller: server, socketURL: socketURL) { _, client in
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Socket Live"),
                expectedGeneration: DocumentGeneration(0)
            )
        )

        guard case .command(let result) = response else {
            #expect(Bool(false))
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))

        let sessionsResponse = try client.send(.sessions)
        guard case .sessions(let sessions) = sessionsResponse else {
            #expect(Bool(false))
            return
        }
        #expect(sessions.first?.displayName == "Socket Live")
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerStopRemovesSocketAndRejectsClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let listener = AgentSocketListener(
        controller: AgentCommandController(),
        socketPath: AgentSocketPath(socketURL.path)
    )
    let client = AgentClient(socketPath: AgentSocketPath(socketURL.path))

    try await listener.start()
    #expect(FileManager.default.fileExists(atPath: socketURL.path))
    await listener.stop()
    #expect(!FileManager.default.fileExists(atPath: socketURL.path))

    var caught: EditorError?
    do {
        _ = try client.send(.status)
    } catch let error as EditorError {
        caught = error
    }
    #expect(caught?.code == .agentConnectionFailed)
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerReplacesStaleSocketFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try Data("stale".utf8).write(to: socketURL)

    try await withRunningListener(
        controller: AgentCommandController(),
        socketURL: socketURL
    ) { _, client in
        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.socketPath == socketURL.path)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerSurvivesMalformedRequest() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")

    try await withRunningListener(
        controller: AgentCommandController(),
        socketURL: socketURL
    ) { _, client in
        let malformedResponseData = try sendRaw(
            Data("not-json".utf8),
            to: socketURL
        )
        let malformedResponse = try AgentMessageCodec()
            .decodeResponse(from: malformedResponseData)

        guard case .failure(let error) = malformedResponse else {
            #expect(Bool(false))
            return
        }
        #expect(error.code == .commandInvalid)

        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.running)
    }
}

private func withRunningListener<T>(
    controller: sending AgentCommandController,
    socketURL: URL,
    operation: (AgentSocketListener, AgentClient) async throws -> T
) async throws -> T {
    let socketPath = AgentSocketPath(socketURL.path)
    let listener = AgentSocketListener(
        controller: controller,
        socketPath: socketPath
    )
    let client = AgentClient(socketPath: socketPath)

    try await listener.start()
    do {
        let result = try await operation(listener, client)
        await listener.stop()
        return result
    } catch {
        await listener.stop()
        throw error
    }
}

private func sendRaw(_ data: Data, to socketURL: URL) throws -> Data {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw EditorError(
            code: .agentUnavailable,
            message: "Failed to create test socket. errno=\(errno)"
        )
    }
    defer {
        Darwin.close(descriptor)
    }

    try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
        guard Darwin.connect(descriptor, address, length) == 0 else {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Failed to connect test socket. errno=\(errno)"
            )
        }
    }
    try AgentSocketIO.writeAll(data, to: descriptor)
    Darwin.shutdown(descriptor, SHUT_WR)
    return try AgentSocketIO.readAll(from: descriptor)
}

private func sendThroughDetachedClient(
    _ request: AgentRequest,
    socketPath: AgentSocketPath
) async throws -> AgentResponse {
    try await Task.detached {
        let client = AgentClient(socketPath: socketPath)
        return try client.send(request)
    }.value
}

private func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

private func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

private func agentSketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

private func agentSingleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = agentSketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

private func agentSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func agentLineArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Agent Line Arc Profile",
        operation: .sketch(agentLineArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Agent Line Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

private func agentArcArcExtrudedSession() throws -> (session: EditorSession, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Agent Arc Arc Profile",
        operation: .sketch(agentArcArcProfileSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let bodyFeatureID = try document.extrudeProfile(
        name: "Agent Arc Arc Body",
        profile: ProfileReference(featureID: sketchFeatureID),
        distance: .length(500.0, .millimeter),
        direction: .normal
    )
    return (EditorSession(document: document), bodyFeatureID)
}

private func agentLineArcProfileSketch() -> Sketch {
    let arcID = SketchEntityID()
    let bottomID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            arcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: 1.0, y: 0.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            bottomID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 0.0, y: 0.0),
                    end: agentSketchTestPoint(x: 2.0, y: 0.0)
                )
            ),
            diagonalID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 1.0, y: 1.0),
                    end: agentSketchTestPoint(x: 0.0, y: 0.5)
                )
            ),
            leftID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: 0.0, y: 0.5),
                    end: agentSketchTestPoint(x: 0.0, y: 0.0)
                )
            ),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
            .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func agentArcArcProfileSketch() -> Sketch {
    let previousArcID = SketchEntityID()
    let currentArcID = SketchEntityID()
    let lineID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            previousArcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: 0.0, y: 1.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(Double.pi, .radian),
                    endAngle: .angle(Double.pi * 1.5, .radian)
                )
            ),
            currentArcID: .arc(
                SketchArc(
                    center: agentSketchTestPoint(x: -2.0, y: 0.0),
                    radius: .length(2.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 3.0, .radian)
                )
            ),
            lineID: .line(
                SketchLine(
                    start: agentSketchTestPoint(x: -1.0, y: sqrt(3.0)),
                    end: agentSketchTestPoint(x: -1.0, y: 1.0)
                )
            ),
        ],
        constraints: [
            .coincident(.arcEnd(previousArcID), .arcStart(currentArcID)),
            .coincident(.arcEnd(currentArcID), .lineStart(lineID)),
            .coincident(.lineEnd(lineID), .arcStart(previousArcID)),
        ]
    )
}

private func agentBodySceneNode(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNode? {
    document.productMetadata.sceneNodes.values.first { node in
        node.reference == .body(featureID)
    }
}

private func agentIsHorizontalLine(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    y: Double
) -> Bool {
    guard entry.entityKind == "line",
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    return abs(start.y - y) < 1.0e-12 &&
        abs(end.y - y) < 1.0e-12 &&
        abs(start.x - end.x) > 1.0e-12
}

private func agentContainsSketchPoint(
    _ summary: SketchEntitySummaryResult,
    x: Double,
    y: Double
) -> Bool {
    summary.entries.contains { entry in
        guard entry.entityKind == "line" else {
            return false
        }
        return agentPointMatches(entry.start, x: x, y: y) ||
            agentPointMatches(entry.end, x: x, y: y)
    }
}

private func agentPointMatches(
    _ point: SketchEntitySummaryResult.Point?,
    x: Double,
    y: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.x - x) < 1.0e-12 && abs(point.y - y) < 1.0e-12
}

private func agentResolvedSketchPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> SketchEntitySummaryResult.Point {
    let x = try document.cadDocument.parameters.resolvedValue(for: point.x)
    let y = try document.cadDocument.parameters.resolvedValue(for: point.y)
    #expect(x.kind == .length)
    #expect(y.kind == .length)
    return SketchEntitySummaryResult.Point(x: x.value, y: y.value)
}

private func agentTwoLineConstrainedSketchDocument(
    name: String,
    constraint: (SketchEntityID, SketchEntityID) -> SketchConstraint
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two line constrained sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.005),
            end: agentSketchTestPoint(x: 0.005, y: 0.005)
        )
    )
    sketch.constraints.append(constraint(firstLineID, secondLineID))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func agentTwoLineUnconstrainedSketchDocument(
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.005, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two line unconstrained sketch setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.005),
            end: agentSketchTestPoint(x: 0.0, y: 0.015)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func agentOpenLineChainSlotDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineIDs: [SketchEntityID]
) {
    let points = [
        agentSketchTestPoint(x: 0.0, y: 0.0),
        agentSketchTestPoint(x: 0.010, y: 0.0),
        agentSketchTestPoint(x: 0.010, y: 0.006),
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
            message: "Agent line-chain Slot setup requires a source line sketch."
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

private func agentOpenLineArcChainSlotDocument(
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line-arc Slot setup requires a source line sketch."
        )
    }
    let arcID = SketchEntityID()
    sketch.entities = [
        lineID: .line(SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.0),
            end: agentSketchTestPoint(x: 0.010, y: 0.0)
        )),
        arcID: .arc(SketchArc(
            center: agentSketchTestPoint(x: 0.010, y: 0.005),
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

private func agentLineCircleTangentSketchDocument(
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
        start: agentSketchTestPoint(x: 0.0, y: 0.0),
        end: agentSketchTestPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line circle tangent setup requires a line sketch."
        )
    }
    let circleID = SketchEntityID()
    sketch.entities[circleID] = .circle(
        SketchCircle(
            center: agentSketchTestPoint(x: 0.005, y: 0.006),
            radius: .length(0.002, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, circleID)
}

private func agentSplinePointConstraintDocument(
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
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.002, y: 0.003),
            agentSketchTestPoint(x: 0.006, y: 0.003),
            agentSketchTestPoint(x: 0.008, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent spline point constraint setup requires a spline sketch."
        )
    }
    let pointID = SketchEntityID()
    sketch.entities[pointID] = .point(agentSketchTestPoint(x: 0.004, y: 0.002))
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, pointID)
}

private func agentSplineLineTangentSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    splineID: SketchEntityID,
    lineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.003, y: 0.004),
            agentSketchTestPoint(x: 0.006, y: 0.004),
            agentSketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let splineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent spline line tangent setup requires a spline sketch."
        )
    }
    let lineID = SketchEntityID()
    sketch.entities[lineID] = .line(
        SketchLine(
            start: agentSketchTestPoint(x: 0.0, y: 0.006),
            end: agentSketchTestPoint(x: 0.010, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, splineID, lineID)
}

private func agentTwoSplineTangentSketchDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstSplineID: SketchEntityID,
    secondSplineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: name,
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            agentSketchTestPoint(x: 0.0, y: 0.0),
            agentSketchTestPoint(x: 0.003, y: 0.0),
            agentSketchTestPoint(x: 0.006, y: 0.0),
            agentSketchTestPoint(x: 0.009, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstSplineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two-spline tangent setup requires a spline sketch."
        )
    }
    let secondSplineID = SketchEntityID()
    sketch.entities[secondSplineID] = .spline(
        SketchSpline(controlPoints: [
            agentSketchTestPoint(x: 0.009, y: 0.0),
            agentSketchTestPoint(x: 0.0108, y: 0.0024),
            agentSketchTestPoint(x: 0.014, y: 0.002),
            agentSketchTestPoint(x: 0.017, y: 0.0),
        ])
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstSplineID, secondSplineID)
}

private func agentTwoCircleSketchDocument(
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
        center: agentSketchTestPoint(x: 0.002, y: 0.003),
        radius: .length(0.004, .meter)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstCircleID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent two circle setup requires a circle sketch."
        )
    }
    let secondCircleID = SketchEntityID()
    sketch.entities[secondCircleID] = .circle(
        SketchCircle(
            center: agentSketchTestPoint(x: 0.010, y: 0.011),
            radius: .length(0.001, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstCircleID, secondCircleID)
}

private func agentSketchTestPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func agentClosedBezierCircleSpline(radius: Double) -> SketchSpline {
    let kappa = 0.552_284_749_830_793_6
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        agentSketchTestPoint(x: x * radius, y: y * radius)
    }
    return SketchSpline(
        controlPoints: [
            point(1.0, 0.0),
            point(1.0, kappa),
            point(kappa, 1.0),
            point(0.0, 1.0),
            point(-kappa, 1.0),
            point(-1.0, kappa),
            point(-1.0, 0.0),
            point(-1.0, -kappa),
            point(-kappa, -1.0),
            point(0.0, -1.0),
            point(kappa, -1.0),
            point(1.0, -kappa),
            point(1.0, 0.0),
        ],
        isClosed: true
    )
}

private func agentLineEntriesAreParallel(
    _ lhs: SketchEntitySummaryResult.EntityEntry,
    _ rhs: SketchEntitySummaryResult.EntityEntry
) -> Bool {
    guard let lhsStart = lhs.start,
          let lhsEnd = lhs.end,
          let rhsStart = rhs.start,
          let rhsEnd = rhs.end else {
        return false
    }
    let lhsX = lhsEnd.x - lhsStart.x
    let lhsY = lhsEnd.y - lhsStart.y
    let rhsX = rhsEnd.x - rhsStart.x
    let rhsY = rhsEnd.y - rhsStart.y
    return abs(lhsX * rhsY - lhsY * rhsX) < 1.0e-12
}

private func agentLineEntryLength(_ entry: SketchEntitySummaryResult.EntityEntry) -> Double {
    guard let start = entry.start,
          let end = entry.end else {
        return .nan
    }
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}

private func agentCylinderRadius(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> Double {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .extrude(extrude) = feature.operation,
          let profileFeature = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
          case let .sketch(sketch) = profileFeature.operation else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent cylinder radius setup requires an extruded circle body."
        )
    }
    for entity in sketch.entities.values {
        guard case .circle(let circle) = entity else {
            continue
        }
        let quantity = try document.cadDocument.parameters.resolvedValue(for: circle.radius)
        #expect(quantity.kind == .length)
        return quantity.value
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent cylinder radius setup requires a circle profile."
    )
}

private func agentLineArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Offset Vertex Line Arc Profile",
        plane: .xy,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line arc offset vertex setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.010, y: 0.002),
            radius: .length(0.002, .meter),
            startAngle: .angle(-Double.pi / 2.0, .radian),
            endAngle: .angle(0.0, .radian)
        )
    )
    sketch.entities[topID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.012, y: 0.002),
            end: agentSketchPoint(x: 0.0, y: 0.002)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.0, y: 0.002),
            end: agentSketchPoint(x: 0.0, y: 0.0)
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

private func agentLineArcCornerTreatmentSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID,
    diagonalID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Corner Treatment Line Arc Profile",
        plane: .xy,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.010, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent line arc corner treatment setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.005, y: 0.0),
            radius: .length(0.005, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    sketch.entities[diagonalID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.005, y: 0.005),
            end: agentSketchPoint(x: 0.0, y: 0.0025)
        )
    )
    sketch.entities[leftID] = .line(
        SketchLine(
            start: agentSketchPoint(x: 0.0, y: 0.0025),
            end: agentSketchPoint(x: 0.0, y: 0.0)
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

private func agentArcArcOffsetVertexSketchDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    upperArcID: SketchEntityID,
    lowerArcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createArcSketch(
        name: "Agent Offset Vertex Arc Arc Profile",
        plane: .xy,
        center: agentSketchPoint(x: 0.005, y: 0.005),
        radius: .length(0.002, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi, .radian)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let upperArcID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent arc arc offset vertex setup requires an arc sketch."
        )
    }
    let lowerArcID = SketchEntityID()
    sketch.entities[lowerArcID] = .arc(
        SketchArc(
            center: agentSketchPoint(x: 0.005, y: 0.005),
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

private func agentConcaveLineLoopDocument() throws -> DesignDocument {
    var document = DesignDocument.empty()
    let points = [
        agentSketchPoint(x: 0.0, y: 0.0),
        agentSketchPoint(x: 0.010, y: 0.0),
        agentSketchPoint(x: 0.010, y: 0.004),
        agentSketchPoint(x: 0.004, y: 0.004),
        agentSketchPoint(x: 0.004, y: 0.010),
        agentSketchPoint(x: 0.0, y: 0.010),
    ]
    let featureID = try document.createLineSketch(
        name: "Agent Concave Source Region",
        plane: .xy,
        start: points[0],
        end: points[1]
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstEntityID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Agent concave source region setup requires a source line sketch."
        )
    }
    let entityIDs = [firstEntityID] + (1..<points.count).map { _ in SketchEntityID() }
    sketch.constraints.removeAll()
    for index in 1..<points.count {
        let entityID = entityIDs[index]
        sketch.entities[entityID] = .line(SketchLine(
            start: points[index],
            end: points[(index + 1) % points.count]
        ))
    }
    for index in points.indices {
        let entityID = entityIDs[index]
        let nextEntityID = entityIDs[(index + 1) % entityIDs.count]
        sketch.constraints.append(.coincident(
            .lineEnd(entityID),
            .lineStart(nextEntityID)
        ))
    }
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return document
}

private func agentSketchPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func nearlyEqualAgent(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func isAgentVerticalGeneratedEdge(_ entry: TopologySummaryResult.Entry) -> Bool {
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

private func isAgentVerticalGeneratedEdge(
    _ entry: TopologySummaryResult.Entry,
    x: Double,
    y: Double
) -> Bool {
    guard isAgentVerticalGeneratedEdge(entry),
          let start = entry.start,
          let end = entry.end else {
        return false
    }
    let tolerance = 1.0e-9
    return abs(((start.x + end.x) / 2.0) - x) <= tolerance
        && abs(((start.y + end.y) / 2.0) - y) <= tolerance
}

private func isAgentGeneratedVertex(
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

private func agentParallelFaceTargets(
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
        let firstNormalVector = try agentVector(firstNormal).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormal = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormalVector = try agentVector(secondNormal).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormalVector.dot(secondNormalVector)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let centerDelta = agentPoint3D(secondCenter) - agentPoint3D(firstCenter)
            guard abs(centerDelta.dot(firstNormalVector)) > 1.0e-9 else {
                continue
            }
            return [firstTarget, secondTarget]
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent construction-plane test requires parallel generated faces."
    )
}

private func agentParallelFaceDimensionTargets(
    in topology: TopologySummaryResult
) throws -> (first: SelectionTarget, second: SelectionTarget, distance: Double) {
    let faces = topology.entries.filter { $0.kind == .face }
    for firstIndex in faces.indices {
        let first = faces[firstIndex]
        guard let firstCenter = first.center,
              let firstNormal = first.normal,
              let firstTarget = first.selectionTarget() else {
            continue
        }
        let firstPoint = agentPoint3D(firstCenter)
        let firstNormalVector = try agentVector(firstNormal).normalized(tolerance: 1.0e-12)
        for second in faces.dropFirst(firstIndex + 1) {
            guard let secondCenter = second.center,
                  let secondNormal = second.normal,
                  let secondTarget = second.selectionTarget() else {
                continue
            }
            let secondNormalVector = try agentVector(secondNormal).normalized(tolerance: 1.0e-12)
            guard abs(abs(firstNormalVector.dot(secondNormalVector)) - 1.0) <= 1.0e-8 else {
                continue
            }
            let distance = (agentPoint3D(secondCenter) - firstPoint).length
            guard distance > 1.0e-9 else {
                continue
            }
            return (firstTarget, secondTarget, distance)
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Agent selection-dimension test requires parallel generated faces."
    )
}

private func agentTwoPointVertexTargets(
    in topology: TopologySummaryResult,
    viewNormal: Vector3D
) throws -> [SelectionTarget] {
    let vertices = topology.entries.compactMap { entry -> (target: SelectionTarget, point: Point3D)? in
        guard entry.kind == .vertex,
              let target = entry.selectionTarget(),
              let point = entry.start else {
            return nil
        }
        return (target, agentPoint3D(point))
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
        message: "Agent construction-plane test requires two generated vertex targets compatible with the view normal."
    )
}

private func agentSourcePointSession() throws -> (
    session: EditorSession,
    targets: [SelectionTarget]
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Source Point CPlane Seeds",
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
            message: "Agent source point construction-plane test requires a sketch feature."
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

private func agentSketchEntityComponentID(from target: SelectionTarget) -> SelectionComponentID? {
    guard case .sketchEntity(let componentID) = target.component else {
        return nil
    }
    return componentID
}

private func agentPointHandleSelectionTarget(
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

private func agentBottomRectangleLine(
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

private func agentVector(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
    Vector3D(x: point.x, y: point.y, z: point.z)
}

private func agentPoint3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
}

private func agentTopologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

private func agentTranslationTransform(
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

private func agentPolySplineQuadMesh() -> Mesh {
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

private func agentPolySplinePatchNetworkMesh(centerZ: Double = 0.001) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

private func surfaceVectorLength(_ vector: SurfaceAnalysisResult.Vector) -> Double {
    hypot(hypot(vector.x, vector.y), vector.z)
}

private func surfaceVectorDot(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

private func surfaceVectorCross(
    _ lhs: SurfaceAnalysisResult.Vector,
    _ rhs: SurfaceAnalysisResult.Vector
) -> SurfaceAnalysisResult.Vector {
    SurfaceAnalysisResult.Vector(
        x: lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.z * rhs.x - lhs.x * rhs.z,
        z: lhs.x * rhs.y - lhs.y * rhs.x
    )
}

private func agentLineEndpointTargets(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> (start: SelectionTarget, end: SelectionTarget) {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first {
        $0.sourceFeatureID == featureID.description && $0.entityKind == "line"
    })
    let sceneNodeIDString = try #require(entry.sceneNodeID)
    let sceneNodeUUID = try #require(UUID(uuidString: sceneNodeIDString))
    let sceneNodeID = SceneNodeID(sceneNodeUUID)
    let startHandle = try #require(entry.pointHandles.first { $0.handle == .lineStart })
    let endHandle = try #require(entry.pointHandles.first { $0.handle == .lineEnd })
    return (
        start: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: startHandle.selectionComponentID))
        ),
        end: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID(rawValue: endHandle.selectionComponentID))
        )
    )
}

private func agentPatternArrayBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private struct AgentIndependentCopyCloneExtrudeFeature {
    var output: PatternArraySummary.IndependentCopyOutputStatus
    var featureID: FeatureID
}

private func agentIndependentCopyCloneExtrudeFeature(
    server: AgentCommandController,
    sessionID: UUID,
    sourceID: PatternArraySourceID,
    expectedGeneration: DocumentGeneration
) throws -> AgentIndependentCopyCloneExtrudeFeature {
    let summaryResponse = server.handle(
        .patternArraySummary(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .patternArraySummary(let summaryResult) = summaryResponse else {
        Issue.record("Agent must return a pattern array summary.")
        throw EditorError(
            code: .commandFailed,
            message: "Pattern array summary response was not returned."
        )
    }
    let summary = try #require(summaryResult.patternArrays.first { $0.sourceID == sourceID })
    let output = try #require(summary.independentCopyOutputs.first)

    let snapshotResponse = server.handle(
        .designDisplaySnapshot(
            sessionID: sessionID,
            expectedGeneration: expectedGeneration
        )
    )
    guard case .designDisplaySnapshot(let snapshot) = snapshotResponse else {
        Issue.record("Agent must return a design display snapshot.")
        throw EditorError(
            code: .commandFailed,
            message: "Design display snapshot response was not returned."
        )
    }
    let extrudeFeatureIDs = Set(snapshot.extrudes.map(\.featureID))
    let featureID = try #require(output.featureIDs.first { extrudeFeatureIDs.contains($0) })
    return AgentIndependentCopyCloneExtrudeFeature(
        output: output,
        featureID: featureID
    )
}

private func agentFeatureID(
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
        if let featureID = agentFeatureID(
            inSceneSubtreeRootedAt: childID,
            document: document
        ) {
            return featureID
        }
    }
    return nil
}

private extension ObjectPropertyValue {
    var lengthValue: Double? {
        guard case .length(let value) = self else {
            return nil
        }
        return value
    }
}

private extension UUID {
    var featureID: FeatureID {
        FeatureID(self)
    }

    var sketchEntityID: SketchEntityID {
        SketchEntityID(self)
    }
}

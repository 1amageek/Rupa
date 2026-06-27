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
    #expect(capabilities.contains("projectSketchCurvesToConstructionPlane"))
    #expect(capabilities.contains("projectCurvesToGeneratedFace"))
    #expect(capabilities.contains("projectBodyOutlinesToConstructionPlane"))
    #expect(capabilities.contains("addSketchConstraint"))
    #expect(capabilities.contains("removeSketchConstraint"))
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
    #expect(capabilities.contains("setSurfaceControlPointDisplay"))
    #expect(capabilities.contains("setSurfaceFrameDisplay"))
    #expect(capabilities.contains("slidePolySplineSurfaceVertices"))
    #expect(capabilities.contains("slideSurfaceControlPoints"))
    #expect(capabilities.contains("polySplineMeshAnalysis"))
    #expect(capabilities.contains("offsetBodyFace"))
    #expect(capabilities.contains("chamferBodyEdges"))
    #expect(capabilities.contains("filletBodyEdges"))
    #expect(capabilities.contains("moveBodyVertex"))
    #expect(capabilities.contains("moveSketchEntityPoint"))
    #expect(capabilities.contains("moveSketchSplineControlPoint"))
    #expect(capabilities.contains("alignSketchVertex"))
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
    #expect(capabilities.contains("setSelectionDimensionTarget"))
    #expect(capabilities.contains("applySelectionDimensionTarget"))
    #expect(capabilities.contains("removeSelectionDimension"))
    #expect(capabilities.contains("objectDimensionSummary"))
    #expect(capabilities.contains("sketchDimensionSummary"))
    #expect(capabilities.contains("selectionDimensionEvaluation"))
    #expect(capabilities.contains("convertSketchLineToArc"))
    #expect(capabilities.contains("convertSketchLineToSpline"))
    #expect(capabilities.contains("reverseSketchCurve"))
    #expect(capabilities.contains("rebuildSketchCurve"))
    #expect(capabilities.contains("extendSketchCurve"))
    #expect(capabilities.contains("joinSketchCurves"))
    #expect(capabilities.contains("unjoinSketchCurve"))
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
    #expect(capabilities.contains("selectReferences"))
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
    let projectCurves = try #require(
        descriptors.first { $0.name == "projectSketchCurvesToConstructionPlane" }
    )
    let projectCurvesToFace = try #require(
        descriptors.first { $0.name == "projectCurvesToGeneratedFace" }
    )
    let projectOutlines = try #require(
        descriptors.first { $0.name == "projectBodyOutlinesToConstructionPlane" }
    )
    let sketchConstraint = try #require(descriptors.first { $0.name == "addSketchConstraint" })
    let sketchConstraintRemoval = try #require(descriptors.first { $0.name == "removeSketchConstraint" })
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
    let surfaceControlPointDisplay = try #require(descriptors.first { $0.name == "setSurfaceControlPointDisplay" })
    let surfaceFrameDisplay = try #require(descriptors.first { $0.name == "setSurfaceFrameDisplay" })
    let polySplineVertexSlide = try #require(descriptors.first { $0.name == "slidePolySplineSurfaceVertices" })
    let surfaceControlPointSlide = try #require(descriptors.first { $0.name == "slideSurfaceControlPoints" })
    let polySplineAnalysis = try #require(descriptors.first { $0.name == "polySplineMeshAnalysis" })
    let splineMove = try #require(descriptors.first { $0.name == "moveSketchSplineControlPoint" })
    let vertexAlign = try #require(descriptors.first { $0.name == "alignSketchVertex" })
    let splineSlide = try #require(descriptors.first { $0.name == "slideSketchSplineControlPoints" })
    let splineInsert = try #require(descriptors.first { $0.name == "insertSketchSplineControlPoint" })
    let splineConvert = try #require(descriptors.first { $0.name == "convertSketchLineToSpline" })
    let curveReverse = try #require(descriptors.first { $0.name == "reverseSketchCurve" })
    let curveRebuild = try #require(descriptors.first { $0.name == "rebuildSketchCurve" })
    let curveExtend = try #require(descriptors.first { $0.name == "extendSketchCurve" })
    let curveJoin = try #require(descriptors.first { $0.name == "joinSketchCurves" })
    let curveUnjoin = try #require(descriptors.first { $0.name == "unjoinSketchCurve" })
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
    let selectionDimensionTarget = try #require(descriptors.first { $0.name == "setSelectionDimensionTarget" })
    let selectionDimensionApply = try #require(descriptors.first { $0.name == "applySelectionDimensionTarget" })
    let selectionDimensionRemoval = try #require(descriptors.first { $0.name == "removeSelectionDimension" })
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
    let referenceSelection = try #require(descriptors.first { $0.name == "selectReferences" })
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

    #expect(selection.category == .selection)
    #expect(selection.access == .agentRequest)
    #expect(selection.mutatesDocument == false)
    #expect(selection.discovery.contains(.topologySummary))
    #expect(selection.discovery.contains(.sketchEntitySummary))
    #expect(selection.targets.contains(.face))

    #expect(referenceSelection.category == .selection)
    #expect(referenceSelection.access == .agentRequest)
    #expect(referenceSelection.mutatesDocument == false)
    #expect(referenceSelection.discovery.contains(.surfaceSourceSummary))
    #expect(referenceSelection.discovery.contains(.selectionMeasurement))
    #expect(referenceSelection.targets == [.surface, .surfaceControlPoint, .surfaceTrim])
    #expect(referenceSelection.summary.contains("SelectionReference"))
    #expect(referenceSelection.failureMode.contains("references incompatible"))

    #expect(faceKnife.category == .directEditing)
    #expect(faceKnife.mutatesDocument)
    #expect(faceKnife.access == .automationCommand)
    #expect(faceKnife.discovery.contains(.topologySummary))
    #expect(faceKnife.discovery.contains(.snapResolution))
    #expect(faceKnife.targets == [.face])
    #expect(faceKnife.failureMode.contains("off-plane"))

    #expect(projectCurves.category == .sketch)
    #expect(projectCurves.mutatesDocument)
    #expect(projectCurves.access == .automationCommand)
    #expect(projectCurves.discovery.contains(.sketchEntitySummary))
    #expect(projectCurves.discovery.contains(.topologySummary))
    #expect(projectCurves.discovery.contains(.constructionPlaneSummary))
    #expect(projectCurves.targets == [.sketchEntity, .edge, .constructionPlane])
    #expect(projectCurves.summary.contains("Alternative Duplicate"))
    #expect(projectCurves.summary.contains("Duplicate Curve and Project"))
    #expect(projectCurves.summary.contains("source curve sketch"))
    #expect(projectCurves.failureMode.contains("generated edge"))
    #expect(projectCurves.failureMode.contains("nonparallel source or generated circular"))

    #expect(projectCurvesToFace.category == .sketch)
    #expect(projectCurvesToFace.mutatesDocument)
    #expect(projectCurvesToFace.access == .automationCommand)
    #expect(projectCurvesToFace.discovery.contains(.sketchEntitySummary))
    #expect(projectCurvesToFace.discovery.contains(.topologySummary))
    #expect(projectCurvesToFace.targets == [.sketchEntity, .edge, .face])
    #expect(projectCurvesToFace.summary.contains("Project Curve Body"))
    #expect(projectCurvesToFace.summary.contains("generated planar face"))
    #expect(projectCurvesToFace.failureMode.contains("non-planar generated faces"))

    #expect(projectOutlines.category == .sketch)
    #expect(projectOutlines.mutatesDocument)
    #expect(projectOutlines.access == .automationCommand)
    #expect(projectOutlines.discovery.contains(.topologySummary))
    #expect(projectOutlines.discovery.contains(.constructionPlaneSummary))
    #expect(projectOutlines.targets == [.body, .constructionPlane])
    #expect(projectOutlines.summary.contains("Project Outline"))
    #expect(projectOutlines.summary.contains("source curve sketch"))
    #expect(projectOutlines.failureMode.contains("non-body scene nodes"))

    #expect(sketchConstraint.category == .sourceCurveEditing)
    #expect(sketchConstraint.discovery.contains(.sketchEntitySummary))
    #expect(sketchConstraint.targets == [.sketchEntity])
    #expect(sketchConstraint.failureMode.contains("spline control-point"))
    #expect(sketchConstraint.summary.contains("smooth spline"))
    #expect(sketchConstraint.summary.contains("spline endpoint tangency"))
    #expect(sketchConstraint.summary.contains("tangent spline endpoints"))
    #expect(sketchConstraint.summary.contains("smooth spline endpoints"))

    #expect(sketchConstraintRemoval.category == .sourceCurveEditing)
    #expect(sketchConstraintRemoval.mutatesDocument)
    #expect(sketchConstraintRemoval.discovery.contains(.sketchEntitySummary))
    #expect(sketchConstraintRemoval.targets == [.sketchEntity])
    #expect(sketchConstraintRemoval.summary.contains("Remove one existing sketch constraint"))
    #expect(sketchConstraintRemoval.failureMode.contains("nonexistent constraints"))

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
    #expect(slotSketch.summary.contains("open cubic Bezier spline"))
    #expect(slotSketch.failureMode.contains("branched line/arc chain"))
    #expect(slotSketch.failureMode.contains("disconnected line/arc"))
    #expect(slotSketch.failureMode.contains("closed spline"))
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

    #expect(surfaceControlPointDisplay.category == .solid)
    #expect(surfaceControlPointDisplay.mutatesDocument)
    #expect(surfaceControlPointDisplay.access == .automationCommand)
    #expect(surfaceControlPointDisplay.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceControlPointDisplay.discovery.contains(.selectionMeasurement))
    #expect(surfaceControlPointDisplay.discovery.contains(.surfaceAnalysis))
    #expect(surfaceControlPointDisplay.targets == [.surfaceControlPoint])
    #expect(surfaceControlPointDisplay.summary.contains("Surface CV point display"))
    #expect(surfaceControlPointDisplay.failureMode.contains("out-of-range indexes"))

    #expect(surfaceFrameDisplay.category == .solid)
    #expect(surfaceFrameDisplay.mutatesDocument)
    #expect(surfaceFrameDisplay.access == .automationCommand)
    #expect(surfaceFrameDisplay.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceFrameDisplay.discovery.contains(.surfaceFrames))
    #expect(surfaceFrameDisplay.discovery.contains(.surfaceAnalysis))
    #expect(surfaceFrameDisplay.targets == [.face, .surfaceControlPoint])
    #expect(surfaceFrameDisplay.summary.contains("UVN surface frame display"))
    #expect(surfaceFrameDisplay.failureMode.contains("ambiguous UV input"))

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

    #expect(vertexAlign.category == .sourceCurveEditing)
    #expect(vertexAlign.mutatesDocument)
    #expect(vertexAlign.access == .automationCommand)
    #expect(vertexAlign.discovery.contains(.sketchEntitySummary))
    #expect(vertexAlign.discovery.contains(.curveAnalysis))
    #expect(vertexAlign.targets == [.sketchEntity, .sketchPointHandle, .sketchControlPoint])
    #expect(vertexAlign.summary.contains("Align Vertex"))
    #expect(vertexAlign.summary.contains("G0"))
    #expect(vertexAlign.summary.contains("G1"))
    #expect(vertexAlign.summary.contains("G2"))
    #expect(vertexAlign.failureMode.contains("reference parameter"))
    #expect(vertexAlign.failureMode.contains("different sketch"))

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

    #expect(curveJoin.category == .sourceCurveEditing)
    #expect(curveJoin.mutatesDocument)
    #expect(curveJoin.access == .automationCommand)
    #expect(curveJoin.discovery.contains(.sketchEntitySummary))
    #expect(curveJoin.targets == [.sketchEntity])
    #expect(curveJoin.summary.contains("Join Curves"))
    #expect(curveJoin.summary.contains("collinear source lines"))
    #expect(curveJoin.summary.contains("line/arc endpoints"))
    #expect(curveJoin.summary.contains("G0"))
    #expect(curveJoin.summary.contains("G1"))
    #expect(curveJoin.summary.contains("curve-analysis readback"))
    #expect(curveJoin.summary.contains("Unjoin"))
    #expect(curveJoin.failureMode.contains("unsupported G2 continuity"))
    #expect(curveJoin.failureMode.contains("not already tangent"))
    #expect(curveJoin.failureMode.contains("interior endpoint"))
    #expect(curveJoin.failureMode.contains("Bridge Curve"))

    #expect(curveUnjoin.category == .sourceCurveEditing)
    #expect(curveUnjoin.mutatesDocument)
    #expect(curveUnjoin.access == .automationCommand)
    #expect(curveUnjoin.discovery.contains(.sketchEntitySummary))
    #expect(curveUnjoin.targets == [.sketchEntity])
    #expect(curveUnjoin.summary.contains("Unjoin Curve"))
    #expect(curveUnjoin.summary.contains("ownership snapshot"))
    #expect(curveUnjoin.summary.contains("line/arc group"))
    #expect(curveUnjoin.failureMode.contains("joined-curve ownership"))
    #expect(curveUnjoin.failureMode.contains("Bridge Curve"))

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
    #expect(curveCut.summary.contains("open cubic Bezier spline"))
    #expect(curveCut.summary.contains("source circle"))
    #expect(curveCut.summary.contains("circle"))
    #expect(curveCut.summary.contains("arc"))
    #expect(curveCut.summary.contains("cubic Bezier spline cutter"))
    #expect(curveCut.summary.contains("arc cutter's base circle"))
    #expect(curveCut.failureMode.contains("extendsCutter"))
    #expect(curveCut.failureMode.contains("non-line/non-arc/non-spline/non-circle targets"))
    #expect(curveCut.failureMode.contains("non-line/circle/arc/spline cutters"))
    #expect(curveCut.failureMode.contains("closed spline"))
    #expect(curveCut.failureMode.contains("spline-cutter extension"))
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
    #expect(selectionDimension.targets == [.face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint])
    #expect(selectionDimension.summary.contains("SwiftCAD document source") || selectionDimension.summary.contains("CAD selection dimension"))

    #expect(selectionDimensionTarget.category == .solid)
    #expect(selectionDimensionTarget.mutatesDocument)
    #expect(selectionDimensionTarget.access == .automationCommand)
    #expect(selectionDimensionTarget.discovery.contains(.selectionDimensionEvaluation))
    #expect(selectionDimensionTarget.targets == [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint])
    #expect(selectionDimensionTarget.summary.contains("SelectionDimensionID"))
    #expect(selectionDimensionTarget.failureMode.contains("target quantity kinds"))

    #expect(selectionDimensionApply.category == .sourceCurveEditing)
    #expect(selectionDimensionApply.mutatesDocument)
    #expect(selectionDimensionApply.access == .automationCommand)
    #expect(selectionDimensionApply.discovery.contains(.selectionDimensionEvaluation))
    #expect(selectionDimensionApply.discovery.contains(.sketchEntitySummary))
    #expect(selectionDimensionApply.discovery.contains(.topologySummary))
    #expect(selectionDimensionApply.discovery.contains(.objectDimensionSummary))
    #expect(selectionDimensionApply.targets == [.document, .face, .sketchEntity, .sketchPointHandle, .sketchControlPoint])
    #expect(selectionDimensionApply.summary.contains("SelectionDimensionID"))
    #expect(selectionDimensionApply.failureMode.contains("line angle"))

    #expect(selectionDimensionRemoval.category == .solid)
    #expect(selectionDimensionRemoval.mutatesDocument)
    #expect(selectionDimensionRemoval.access == .automationCommand)
    #expect(selectionDimensionRemoval.discovery.contains(.selectionDimensionEvaluation))
    #expect(selectionDimensionRemoval.targets == [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint])
    #expect(selectionDimensionRemoval.summary.contains("SelectionDimensionID"))
    #expect(selectionDimensionRemoval.failureMode.contains("missing selection dimension IDs"))

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
    #expect(selectionDimensionEvaluation.targets == [.document, .face, .edge, .vertex, .sketchEntity, .sketchPointHandle, .sketchControlPoint])

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
    #expect(surfaceFrames.discovery.contains(.surfaceSourceSummary))
    #expect(surfaceFrames.discovery.contains(.surfaceFrames))
    #expect(surfaceFrames.targets == [.face, .surfaceControlPoint])
    #expect(surfaceFrames.summary.contains("UVN local frames"))
    #expect(surfaceFrames.failureMode.contains("surface selection references"))

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
              "id": "selection-reference-1",
              "method": "selection.selectReferences",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "references": [],
                "expectedGeneration": {
                  "value": 9
                }
              }
            }
            """,
            { envelope in
                guard case .selectReferences(
                    let decodedSessionID,
                    let references,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(references.isEmpty)
                #expect(expectedGeneration == DocumentGeneration(9))
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
                  "value": 10
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
                #expect(expectedGeneration == DocumentGeneration(10))
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

import Foundation
import RupaCore
import SwiftCAD

struct WorkspaceCanvasCommandPlanner {
    struct Context {
        let document: DesignDocument
        let selection: SelectionModel
        let workspaceState: WorkspaceState
        let objectRegistry: ObjectTypeRegistry
        let polygonState: PolygonToolState
        let sketchInputState: SketchInputState
    }

    let context: Context

    func clickCommand(
        tool: ModelingTool,
        targetSceneNodeID: SceneNodeID?,
        modelPoint: Point2D,
        modelWorldPoint: Point3D?,
        sketchPlane: SketchPlane,
        placementCellMeters: Double?
    ) throws -> EditorCommand? {
        switch tool {
        case .select, .measure, .mesh:
            return nil
        case .solid:
            if let targetSceneNodeID {
                return try solidCommand(targetSceneNodeID: targetSceneNodeID)
            }
            return try solidClickCommand(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane,
                placementCellMeters: placementCellMeters
            )
        case .sweep:
            return try SweepSelectionPlanningService(
                document: context.document,
                selection: context.selection
            ).command(
                targetSceneNodeID: targetSceneNodeID,
                name: nextFeatureName(prefix: "Sweep")
            )
        case .sketch:
            return try rectangleClickCommand(modelPoint: modelPoint, sketchPlane: sketchPlane)
        case .polygon:
            return try polygonClickCommand(
                modelPoint: modelPoint,
                modelWorldPoint: modelWorldPoint,
                sketchPlane: sketchPlane
            )
        case .arc:
            return try arcClickCommand(modelPoint: modelPoint, sketchPlane: sketchPlane)
        case .spline:
            return try splineClickCommand(modelPoint: modelPoint, sketchPlane: sketchPlane)
        case .surface:
            return try circleClickCommand(modelPoint: modelPoint, sketchPlane: sketchPlane)
        case .section:
            return .createSectionPlane(name: nextSceneNodeName(prefix: "Section Plane"))
        }
    }

    func dragCommand(
        tool: ModelingTool,
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane,
        startWorldPoint: Point3D?,
        endWorldPoint: Point3D?
    ) throws -> EditorCommand? {
        switch tool {
        case .sketch:
            return try rectangleDragCommand(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
        case .polygon:
            return try polygonDragCommand(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                centerWorldPoint: startWorldPoint,
                edgeWorldPoint: endWorldPoint,
                sketchPlane: sketchPlane
            )
        case .surface:
            return try circleDragCommand(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
        case .arc:
            return try arcDragCommand(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
        case .spline:
            return try splineDragCommand(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
        case .solid:
            return try solidDragCommand(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
        case .select, .sweep, .mesh, .measure, .section:
            return nil
        }
    }

    private var scaleDefaults: WorkspaceScaleDefaults {
        WorkspaceScaleDefaults(ruler: context.workspaceState.ruler)
    }

    private var activeLengthMeters: Double? {
        guard context.sketchInputState.dimensionInputFocus == .length,
              let value = context.sketchInputState.dimensionInputLengthMeters,
              value.isFinite,
              value > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(value)
    }

    private var activeAngleRadians: Double? {
        guard context.sketchInputState.dimensionInputFocus == .angle,
              let value = context.sketchInputState.dimensionInputAngleRadians,
              value.isFinite else {
            return nil
        }
        return CADInputValueNormalizer.standard.angleRadians(value)
    }

    private var activeWidthMeters: Double? {
        guard [.width, .height].contains(context.sketchInputState.dimensionInputFocus),
              let value = context.sketchInputState.dimensionInputWidthMeters,
              value.isFinite,
              value > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(value)
    }

    private var activeHeightMeters: Double? {
        guard [.width, .height].contains(context.sketchInputState.dimensionInputFocus),
              let value = context.sketchInputState.dimensionInputHeightMeters,
              value.isFinite,
              value > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(value)
    }

    private func solidCommand(targetSceneNodeID: SceneNodeID) throws -> EditorCommand {
        guard let node = context.document.productMetadata.sceneNodes[targetSceneNodeID],
              node.reference?.kind == .sketch,
              let featureID = node.reference?.featureID else {
            throw commandError("Solid tool requires a sketch profile canvas target.")
        }
        return .extrudeProfile(
            name: nextFeatureName(prefix: "\(node.name) Body"),
            profile: ProfileReference(featureID: featureID),
            distance: length(scaleDefaults.sketchDepthMeters),
            direction: .normal
        )
    }

    private func rectangleClickCommand(
        modelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        try requireFinite(modelPoint, message: "Canvas rectangle placement requires a finite model coordinate.")
        let center = localPoint(modelPoint, on: sketchPlane)
        let width = activeWidthMeters ?? scaleDefaults.placedRectangleWidthMeters
        let height = activeHeightMeters ?? scaleDefaults.placedRectangleHeightMeters
        return rectangleCommand(
            name: nextFeatureName(prefix: "Rectangle Sketch"),
            sketchPlane: sketchPlane,
            first: Point2D(x: center.x - width / 2.0, y: center.y - height / 2.0),
            second: Point2D(x: center.x + width / 2.0, y: center.y + height / 2.0),
            isSolid: false,
            depth: nil
        )
    }

    private func rectangleDragCommand(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        try dragRectangleCommand(
            startModelPoint: startModelPoint,
            endModelPoint: endModelPoint,
            sketchPlane: sketchPlane,
            name: nextFeatureName(prefix: "Rectangle Sketch"),
            isSolid: false,
            depth: nil
        )
    }

    private func solidClickCommand(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane,
        placementCellMeters: Double?
    ) throws -> EditorCommand {
        try requireFinite(centerModelPoint, message: "Canvas solid placement requires a finite model coordinate.")
        let side = placementCellMeters.flatMap { value in
            value.isFinite && value > 0.0 ? value : nil
        } ?? scaleDefaults.placedSolidSideMeters
        let width = activeWidthMeters ?? side
        let height = activeHeightMeters ?? side
        let center = localPoint(centerModelPoint, on: sketchPlane)
        return rectangleCommand(
            name: nextFeatureName(prefix: "Box"),
            sketchPlane: sketchPlane,
            first: Point2D(x: center.x - width / 2.0, y: center.y - height / 2.0),
            second: Point2D(x: center.x + width / 2.0, y: center.y + height / 2.0),
            isSolid: true,
            depth: side
        )
    }

    private func solidDragCommand(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        try dragRectangleCommand(
            startModelPoint: startModelPoint,
            endModelPoint: endModelPoint,
            sketchPlane: sketchPlane,
            name: nextFeatureName(prefix: "Box"),
            isSolid: true,
            depth: scaleDefaults.sketchDepthMeters
        )
    }

    private func dragRectangleCommand(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane,
        name: String,
        isSolid: Bool,
        depth: Double?
    ) throws -> EditorCommand {
        let finiteCoordinateMessage = isSolid
            ? "Canvas solid drag requires finite model coordinates."
            : "Canvas rectangle drag requires finite model coordinates."
        try requireFinite(startModelPoint, message: finiteCoordinateMessage)
        try requireFinite(endModelPoint, message: finiteCoordinateMessage)
        let start = localPoint(startModelPoint, on: sketchPlane)
        let end = localPoint(endModelPoint, on: sketchPlane)
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let endX = normalized(start.x + signed(activeWidthMeters ?? abs(deltaX), following: deltaX))
        let endY = normalized(start.y + signed(activeHeightMeters ?? abs(deltaY), following: deltaY))
        let first = Point2D(x: normalized(min(start.x, endX)), y: normalized(min(start.y, endY)))
        let second = Point2D(x: normalized(max(start.x, endX)), y: normalized(max(start.y, endY)))
        guard second.x > first.x, second.y > first.y else {
            throw commandError(isSolid
                ? "Canvas solid drag requires a non-zero width and height."
                : "Canvas rectangle drag requires a non-zero width and height.")
        }
        return rectangleCommand(
            name: name,
            sketchPlane: sketchPlane,
            first: first,
            second: second,
            isSolid: isSolid,
            depth: depth
        )
    }

    private func rectangleCommand(
        name: String,
        sketchPlane: SketchPlane,
        first: Point2D,
        second: Point2D,
        isSolid: Bool,
        depth: Double?
    ) -> EditorCommand {
        if isSolid {
            return .createExtrudedRectangleFromCorners(
                name: name,
                plane: sketchPlane,
                firstCorner: sketchPoint(first),
                oppositeCorner: sketchPoint(second),
                depth: length(depth ?? scaleDefaults.sketchDepthMeters),
                direction: .normal
            )
        }
        return .createRectangleSketchFromCorners(
            name: name,
            plane: sketchPlane,
            firstCorner: sketchPoint(first),
            oppositeCorner: sketchPoint(second)
        )
    }

    private func circleClickCommand(
        modelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        try requireFinite(modelPoint, message: "Canvas circle placement requires a finite model coordinate.")
        return .createCircleSketch(
            name: nextFeatureName(prefix: "Circle Sketch"),
            plane: sketchPlane,
            center: sketchPoint(localPoint(modelPoint, on: sketchPlane)),
            radius: length(activeLengthMeters ?? scaleDefaults.curveRadiusMeters)
        )
    }

    private func circleDragCommand(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        try requireFinite(centerModelPoint, message: "Canvas circle drag requires finite model coordinates.")
        try requireFinite(edgeModelPoint, message: "Canvas circle drag requires finite model coordinates.")
        let center = localPoint(centerModelPoint, on: sketchPlane)
        let edge = localPoint(edgeModelPoint, on: sketchPlane)
        let deltaX = edge.x - center.x
        let deltaY = edge.y - center.y
        let radius = activeLengthMeters ?? sqrt(deltaX * deltaX + deltaY * deltaY)
        guard radius.isFinite, radius > 0.0 else {
            throw commandError("Canvas circle drag requires a non-zero radius.")
        }
        return .createCircleSketch(
            name: nextFeatureName(prefix: "Circle Sketch"),
            plane: sketchPlane,
            center: sketchPoint(center),
            radius: length(radius)
        )
    }

    private func arcClickCommand(modelPoint: Point2D, sketchPlane: SketchPlane) throws -> EditorCommand {
        let draft = try CanvasSketchCurveDrafts.arc(
            centeredAt: localPoint(modelPoint, on: sketchPlane),
            defaults: scaleDefaults,
            radiusMeters: activeLengthMeters,
            spanAngleRadians: activeAngleRadians
        )
        return arcCommand(draft, sketchPlane: sketchPlane)
    }

    private func arcDragCommand(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        let draft = try CanvasSketchCurveDrafts.arc(
            fromCenter: localPoint(centerModelPoint, on: sketchPlane),
            toRadiusPoint: localPoint(edgeModelPoint, on: sketchPlane),
            radiusMeters: activeLengthMeters,
            spanAngleRadians: activeAngleRadians
        )
        return arcCommand(draft, sketchPlane: sketchPlane)
    }

    private func arcCommand(
        _ draft: CanvasSketchCurveDrafts.Arc,
        sketchPlane: SketchPlane
    ) -> EditorCommand {
        .createArcSketch(
            name: nextFeatureName(prefix: "Arc Sketch"),
            plane: sketchPlane,
            center: sketchPoint(draft.center),
            radius: length(draft.radiusMeters),
            startAngle: .angle(draft.startAngleRadians, .radian),
            endAngle: .angle(draft.endAngleRadians, .radian)
        )
    }

    private func splineClickCommand(modelPoint: Point2D, sketchPlane: SketchPlane) throws -> EditorCommand {
        let draft = try CanvasSketchCurveDrafts.spline(
            centeredAt: localPoint(modelPoint, on: sketchPlane),
            defaults: scaleDefaults
        )
        return splineCommand(draft, sketchPlane: sketchPlane)
    }

    private func splineDragCommand(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        let draft = try CanvasSketchCurveDrafts.spline(
            from: localPoint(startModelPoint, on: sketchPlane),
            to: localPoint(endModelPoint, on: sketchPlane),
            defaults: scaleDefaults
        )
        return splineCommand(draft, sketchPlane: sketchPlane)
    }

    private func splineCommand(
        _ draft: CanvasSketchCurveDrafts.Spline,
        sketchPlane: SketchPlane
    ) -> EditorCommand {
        .createSplineSketch(
            name: nextFeatureName(prefix: "Spline Sketch"),
            plane: sketchPlane,
            spline: SketchSpline(controlPoints: draft.controlPoints.map(sketchPoint))
        )
    }

    private func polygonClickCommand(
        modelPoint: Point2D,
        modelWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        let center = localPoint(modelPoint, on: sketchPlane)
        if context.polygonState.cutsFaces {
            let knife = try faceKnifeContext()
            let localCenter = faceLocalPoint(
                worldPoint: modelWorldPoint,
                fallback: center,
                coordinateSystem: knife.coordinateSystem
            )
            let draft = try CanvasSketchCurveDrafts.polygon(
                centeredAt: localCenter,
                sides: context.polygonState.sideCount,
                sizingMode: context.polygonState.sizingMode,
                inclinationMode: context.polygonState.inclinationMode,
                defaults: scaleDefaults,
                radiusMeters: activeLengthMeters,
                rotationAngleRadians: activeAngleRadians
            )
            return faceKnifeCommand(draft, context: knife)
        }
        let draft = try CanvasSketchCurveDrafts.polygon(
            centeredAt: center,
            sides: context.polygonState.sideCount,
            sizingMode: context.polygonState.sizingMode,
            inclinationMode: context.polygonState.inclinationMode,
            defaults: scaleDefaults,
            radiusMeters: activeLengthMeters,
            rotationAngleRadians: activeAngleRadians
        )
        return polygonCommand(draft, sketchPlane: sketchPlane)
    }

    private func polygonDragCommand(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        centerWorldPoint: Point3D?,
        edgeWorldPoint: Point3D?,
        sketchPlane: SketchPlane
    ) throws -> EditorCommand {
        let center = localPoint(centerModelPoint, on: sketchPlane)
        let edge = localPoint(edgeModelPoint, on: sketchPlane)
        if context.polygonState.cutsFaces {
            let knife = try faceKnifeContext()
            let draft = try CanvasSketchCurveDrafts.polygon(
                fromCenter: faceLocalPoint(
                    worldPoint: centerWorldPoint,
                    fallback: center,
                    coordinateSystem: knife.coordinateSystem
                ),
                toRadiusPoint: faceLocalPoint(
                    worldPoint: edgeWorldPoint,
                    fallback: edge,
                    coordinateSystem: knife.coordinateSystem
                ),
                sides: context.polygonState.sideCount,
                sizingMode: context.polygonState.sizingMode,
                inclinationMode: context.polygonState.inclinationMode,
                radiusMeters: activeLengthMeters,
                rotationAngleRadians: activeAngleRadians
            )
            return faceKnifeCommand(draft, context: knife)
        }
        let draft = try CanvasSketchCurveDrafts.polygon(
            fromCenter: center,
            toRadiusPoint: edge,
            sides: context.polygonState.sideCount,
            sizingMode: context.polygonState.sizingMode,
            inclinationMode: context.polygonState.inclinationMode,
            radiusMeters: activeLengthMeters,
            rotationAngleRadians: activeAngleRadians
        )
        return polygonCommand(draft, sketchPlane: sketchPlane)
    }

    private func polygonCommand(
        _ draft: CanvasSketchCurveDrafts.Polygon,
        sketchPlane: SketchPlane
    ) -> EditorCommand {
        .createPolygonSketch(
            name: nextFeatureName(prefix: "Polygon Sketch"),
            plane: sketchPlane,
            center: sketchPoint(draft.center),
            radius: length(draft.radiusMeters),
            sides: draft.sides,
            sizingMode: draft.sizingMode,
            inclinationMode: draft.inclinationMode,
            rotationAngle: .angle(draft.rotationAngleRadians, .radian)
        )
    }

    private typealias FaceKnifeContext = (
        target: SelectionTarget,
        coordinateSystem: SketchPlaneCoordinateSystem
    )

    private func faceKnifeContext() throws -> FaceKnifeContext {
        guard let target = context.selection.primaryTarget,
              case .face = target.component else {
            throw commandError("Polygon Knife requires a selected generated face target.")
        }
        do {
            let plane = try ConstructionPlaneTargetResolver().plane(
                alignedTo: target,
                in: context.document,
                objectRegistry: context.objectRegistry
            )
            return (target, try SketchPlaneCoordinateSystem(plane: plane))
        } catch {
            throw commandError("Polygon Knife requires a selected generated planar face target: \(error).")
        }
    }

    private func faceKnifeCommand(
        _ draft: CanvasSketchCurveDrafts.Polygon,
        context knife: FaceKnifeContext
    ) -> EditorCommand {
        .createFaceKnife(
            name: nextFeatureName(prefix: "Face Knife"),
            target: knife.target,
            loop: draft.vertices.map { knife.coordinateSystem.point(from: $0) }
        )
    }

    private func faceLocalPoint(
        worldPoint: Point3D?,
        fallback: Point2D,
        coordinateSystem: SketchPlaneCoordinateSystem
    ) -> Point2D {
        guard let worldPoint else {
            return fallback
        }
        let projection = coordinateSystem.project(worldPoint)
        return abs(projection.depth) <= 1.0e-7 ? projection.point : fallback
    }

    private func localPoint(_ point: Point2D, on plane: SketchPlane) -> Point2D {
        CADInputValueNormalizer.standard.point(
            SketchPlaneCanvasMapper(sketchPlane: plane).localPoint(fromCanvas: point)
        )
    }

    private func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(x: length(point.x), y: length(point.y))
    }

    private func length(_ value: Double) -> CADExpression {
        .length(normalized(value), .meter)
    }

    private func normalized(_ value: Double) -> Double {
        CADInputValueNormalizer.standard.lengthMeters(value)
    }

    private func signed(_ value: Double, following delta: Double) -> Double {
        delta < 0.0 ? -value : value
    }

    private func requireFinite(_ point: Point2D, message: String) throws {
        guard point.x.isFinite, point.y.isFinite else {
            throw commandError(message)
        }
    }

    private func commandError(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }

    private func nextFeatureName(prefix: String) -> String {
        let names = Set(context.document.cadDocument.designGraph.nodes.values.compactMap(\.name))
        return nextName(prefix: prefix, existingNames: names)
    }

    private func nextSceneNodeName(prefix: String) -> String {
        nextName(
            prefix: prefix,
            existingNames: Set(context.document.productMetadata.sceneNodes.values.map(\.name))
        )
    }

    private func nextName(prefix: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(prefix) else {
            return prefix
        }
        var index = 2
        while existingNames.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }
}

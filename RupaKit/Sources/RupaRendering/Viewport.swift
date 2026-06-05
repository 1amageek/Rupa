import Foundation
import RupaCore
import SwiftCAD
import SwiftUI

public struct Viewport: View {
    private static let projectionAnimationDuration: TimeInterval = 0.34

    @State private var activeCanvasDrag: ViewportActiveDrag?
    @State private var activeAffordanceDrag: ViewportAffordanceDragState?
    @State private var camera: ViewportCamera = .identity
    @State private var editedBodies: [FeatureID: ViewportObjectEditState] = [:]
    @State private var hoveredAffordance: ViewportAffordanceTarget?
    @State private var pendingAffordance: ViewportAffordanceTarget?
    @State private var orbitBasis: ViewportProjectionBasis?
    @State private var projectionTransition: ViewportProjectionTransition?
    @State private var selectedAxis: ViewportCoordinateAxis?
    @State private var hoveredCanvasHit: ViewportHit?
    @State private var hoveredModelPoint: Point2D?

    private let document: DesignDocument
    private let objectRegistry: ObjectTypeRegistry
    private let evaluationStatus: EvaluationStatus
    private let renderInvalidation: RenderInvalidation
    private let selection: SelectionModel
    private let showsCanvasDragPlaceholder: Bool
    private let showsConstructionPlaneHover: Bool
    private let allowsSelectionRectangle: Bool
    private let onPick: ((ViewportCanvasTarget) -> Void)?
    private let onCanvasDrag: ((ViewportModelDrag) -> Void)?
    private let onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)?
    private let onHover: ((ViewportHit?) -> Void)?

    public init(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        evaluationStatus: EvaluationStatus = .notEvaluated,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        selection: SelectionModel = .empty,
        showsCanvasDragPlaceholder: Bool = true,
        showsConstructionPlaneHover: Bool = false,
        allowsSelectionRectangle: Bool = false,
        onPick: ((ViewportCanvasTarget) -> Void)? = nil,
        onCanvasDrag: ((ViewportModelDrag) -> Void)? = nil,
        onSelectionDrag: ((ViewportSelectionDragTarget) -> Void)? = nil,
        onHover: ((ViewportHit?) -> Void)? = nil
    ) {
        self.document = document
        self.objectRegistry = objectRegistry
        self.evaluationStatus = evaluationStatus
        self.renderInvalidation = renderInvalidation
        self.selection = selection
        self.showsCanvasDragPlaceholder = showsCanvasDragPlaceholder
        self.showsConstructionPlaneHover = showsConstructionPlaneHover
        self.allowsSelectionRectangle = allowsSelectionRectangle
        self.onPick = onPick
        self.onCanvasDrag = onCanvasDrag
        self.onSelectionDrag = onSelectionDrag
        self.onHover = onHover
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let basis = projectionBasis(at: timeline.date)

                Canvas { context, size in
                    drawGrid(in: &context, size: size, camera: camera, basis: basis)
                    drawAxes(in: &context, size: size, camera: camera, basis: basis)
                    drawModel(in: &context, size: size, camera: camera, basis: basis)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .id(renderInvalidation)
                .accessibilityIdentifier("CanvasViewport")
                .accessibilityLabel("Canvas viewport")
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    viewportBadge
                        .padding(12)
                }
                .overlay {
                    canvasDragPlaceholderOverlay(basis: basis)
                }
                .overlay {
                    selectionAffordanceAccessibilityMarker
                }
                .overlay {
                    gridAccessibilityMarkers
                }
                .overlay {
                    ViewportInputSurface(
                        onPress: { point, size, _ in
                            beginViewportPress(at: point, size: size)
                        },
                        onPick: { point, size, intent in
                            pick(at: point, size: size, selectionIntent: intent)
                        },
                        onCanvasDrag: { start, end, size, intent in
                            handleCanvasDrag(
                                from: start,
                                to: end,
                                size: size,
                                selectionIntent: intent
                            )
                        },
                        onDragPreview: { start, current, size in
                            updateCanvasDragPlaceholder(
                                from: start,
                                to: current,
                                size: size
                            )
                        },
                        onHover: { point, size in
                            if let point {
                                hover(at: point, size: size)
                            } else {
                                clearCanvasHover()
                            }
                        },
                        onPan: { delta in
                            panCanvas(by: delta)
                        },
                        onZoom: { factor, anchor, size in
                            zoomCanvas(by: factor, anchor: anchor, size: size)
                        },
                        onOrbit: { delta in
                            orbitViewport(by: delta)
                        }
                    )
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    ViewportAxisTriad(
                        selectedAxis: selectedAxis,
                        basis: basis,
                        onResetView: {
                            resetViewportCamera()
                        },
                        onSelectAxis: { axis in
                            selectProjectionAxis(axis)
                        }
                    )
                    .padding(.trailing, 14)
                    .padding(.bottom, 70)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var gridAccessibilityMarkers: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasCoordinateGrid")
                .accessibilityLabel("Coordinate aligned grid")
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasGridRuler")
                .accessibilityLabel("In-plane grid ruler")
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func canvasDragPlaceholderOverlay(
        basis: ViewportProjectionBasis
    ) -> some View {
        if let activeCanvasDrag {
            ZStack {
                Canvas { context, size in
                    switch activeCanvasDrag.kind {
                    case .creation:
                        drawCanvasDragPlaceholder(activeCanvasDrag, in: &context, size: size, basis: basis)
                    case .selection:
                        drawSelectionDragRectangle(activeCanvasDrag, in: &context)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 1.0, height: 1.0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(activeCanvasDrag.accessibilityIdentifier)
                    .accessibilityLabel(activeCanvasDrag.accessibilityLabel)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var selectionAffordanceAccessibilityMarker: some View {
        if hasSelectedAffordance {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1.0, height: 1.0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("CanvasSelectionAffordance")
                .accessibilityLabel("Selected object transform affordance")
                .allowsHitTesting(false)
        }
    }

    private var hasSelectedAffordance: Bool {
        !selectedFeatureIDs().isEmpty
    }

    private var viewportBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .symbolRenderingMode(.hierarchical)
            Text(document.displayUnit.symbol)
                .font(.system(.caption, design: .monospaced))
            Divider()
                .frame(height: 12)
            Text(statusTitle)
                .font(.caption)
            Divider()
                .frame(height: 12)
            Text("\(Int((camera.zoom * 100.0).rounded()))%")
                .font(.system(.caption, design: .monospaced))
            if featureCount > 0 {
                Divider()
                    .frame(height: 12)
                Text("\(featureCount) features")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var featureCount: Int {
        document.cadDocument.designGraph.order.count
    }

    private var currentProjectionBasis: ViewportProjectionBasis {
        projectionBasis(at: Date())
    }

    private func projectionBasis(at date: Date) -> ViewportProjectionBasis {
        guard let projectionTransition else {
            if let orbitBasis {
                return orbitBasis
            }
            return targetProjectionBasis(for: selectedAxis)
        }
        return projectionTransition.basis(at: date)
    }

    private func targetProjectionBasis(for axis: ViewportCoordinateAxis?) -> ViewportProjectionBasis {
        guard let axis else {
            return .isometric
        }
        return .axisFront(axis)
    }

    private var statusTitle: String {
        switch evaluationStatus {
        case .notEvaluated:
            "Not evaluated"
        case .valid:
            if let generation = renderInvalidation.generation {
                "Gen \(generation.value)"
            } else {
                "Valid"
            }
        case .failed:
            "Invalid"
        }
    }

    private func drawGrid(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        let grid = ViewportProjectedGrid(
            document: document,
            size: size,
            camera: camera,
            basis: basis
        )
        var minorPath = Path()
        var majorPath = Path()

        for line in grid.lines {
            if line.isMajor {
                majorPath.move(to: line.start)
                majorPath.addLine(to: line.end)
            } else {
                minorPath.move(to: line.start)
                minorPath.addLine(to: line.end)
            }
        }

        context.stroke(minorPath, with: .color(Color.secondary.opacity(0.09)), lineWidth: 0.45)
        context.stroke(majorPath, with: .color(Color.secondary.opacity(0.22)), lineWidth: 0.85)
    }

    private func drawAxes(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        let layout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: basis
        ).layout
        let origin = layout.project(.zero)
        let basis = layout.basis
        let planeExtent = hypot(size.width, size.height) * 1.10
        let yExtent = min(size.width, size.height) * 0.34

        drawAxisLine(
            from: basis.endpoint(from: origin, axis: .x, length: -planeExtent),
            to: basis.endpoint(from: origin, axis: .x, length: planeExtent),
            color: ViewportCoordinateAxis.x.color,
            label: ViewportCoordinateAxis.x.label,
            in: &context
        )
        drawAxisLine(
            from: origin,
            to: basis.endpoint(from: origin, axis: .y, length: yExtent),
            color: ViewportCoordinateAxis.y.color,
            label: ViewportCoordinateAxis.y.label,
            in: &context
        )
        drawAxisLine(
            from: basis.endpoint(from: origin, axis: .z, length: -planeExtent),
            to: basis.endpoint(from: origin, axis: .z, length: planeExtent),
            color: ViewportCoordinateAxis.z.color,
            label: ViewportCoordinateAxis.z.label,
            in: &context
        )
    }

    private func drawAxisLine(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        label: String,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(path, with: .color(color.opacity(0.46)), lineWidth: 1.5)
        drawAxisLabel(
            label,
            at: CGPoint(x: end.x + 12.0, y: end.y - 8.0),
            color: color,
            in: &context
        )
    }

    private func drawAxisLabel(
        _ label: String,
        at point: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        context.draw(
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(0.78)),
            at: point
        )
    }

    private func drawModel(
        in context: inout GraphicsContext,
        size: CGSize,
        camera: ViewportCamera,
        basis: ViewportProjectionBasis
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let layout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: basis
        ).layout
        let selectedFeatureIDs = selectedFeatureIDs()
        let hoveredFeatureIDs = hoveredFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        let usesSelectionGroup = selectedBodyItems.count > 1
        let suppressedSketchFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        let showsConstructionHighlight = showsConstructionPlaneHover
            && hoveredAffordance == nil
            && pendingAffordance == nil
            && activeAffordanceDrag == nil
        let constructionHit = showsConstructionHighlight ? hoveredCanvasHit : nil
        let constructionModelPoint = showsConstructionHighlight ? hoveredModelPoint : nil

        if constructionHit?.bodyFace == nil,
           let constructionModelPoint {
            drawZeroCoordinateFieldHighlight(
                around: constructionModelPoint,
                in: &context,
                layout: layout
            )
        }

        for item in scene.items {
            if case .body = item.kind {
                drawBody(
                    item,
                    in: &context,
                    layout: layout,
                    isSelected: selectedFeatureIDs.contains(item.featureID) && !usesSelectionGroup,
                    isHovered: hoveredFeatureIDs.contains(item.featureID)
                )
            }
        }

        for item in scene.items {
            if case .sketch = item.kind,
               !suppressedSketchFeatureIDs.contains(item.featureID) {
                drawSketch(
                    item,
                    in: &context,
                    layout: layout,
                    isSelected: selectedFeatureIDs.contains(item.featureID),
                    isHovered: hoveredFeatureIDs.contains(item.featureID)
                )
            }
        }

        if let constructionHit,
           constructionHit.bodyFace != nil {
            drawConstructionFaceHighlight(
                hit: constructionHit,
                scene: scene,
                layout: layout,
                in: &context
            )
        }

        drawSelectionAffordances(
            in: &context,
            scene: scene,
            layout: layout,
            selectedFeatureIDs: selectedFeatureIDs
        )
    }

    private func suppressedSketchFeatureIDs(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> Set<FeatureID> {
        Set(
            scene.items.compactMap { item -> FeatureID? in
                guard case .body = item.kind,
                      selectedFeatureIDs.contains(item.featureID) || editedBodies[item.featureID] != nil else {
                    return nil
                }
                return item.sourceFeatureID
            }
        )
    }

    private func sceneBySuppressingSketches(
        _ scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> ViewportScene {
        let suppressedFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        guard !suppressedFeatureIDs.isEmpty else {
            return scene
        }
        return ViewportScene(
            items: scene.items.filter { item in
                if case .sketch = item.kind {
                    return !suppressedFeatureIDs.contains(item.featureID)
                }
                return true
            }
        )
    }

    private func drawSketch(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool
    ) {
        guard case .sketch(let primitives) = item.kind else {
            return
        }
        let strokeColor = if isSelected {
            Color.blue
        } else if isHovered {
            Color.cyan
        } else {
            Color.accentColor
        }
        let strokeWidth: CGFloat = if isSelected {
            4.0
        } else if isHovered {
            3.4
        } else {
            2.5
        }

        for primitive in primitives {
            switch primitive {
            case .point(let point):
                let projected = layout.project(point)
                let rect = CGRect(
                    x: projected.x - 3.0,
                    y: projected.y - 3.0,
                    width: 6.0,
                    height: 6.0
                )
                context.fill(Path(ellipseIn: rect), with: .color(strokeColor.opacity(0.92)))
            case .line(let start, let end):
                var path = Path()
                path.move(to: layout.project(start))
                path.addLine(to: layout.project(end))
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
            case .circle(let circleCenter, let radiusMeters):
                let path = projectedCirclePath(
                    center: circleCenter,
                    radiusMeters: radiusMeters,
                    layout: layout
                )
                context.fill(path, with: .color(strokeColor.opacity(isSelected ? 0.16 : 0.10)))
                context.stroke(path, with: .color(strokeColor.opacity(0.92)), lineWidth: strokeWidth)
            }
        }
    }

    private func projectedCirclePath(
        center: CGPoint,
        radiusMeters: Double,
        layout: ViewportLayout
    ) -> Path {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        var path = Path()

        for index in 0 ... 96 {
            let angle = CGFloat(index) / 96.0 * CGFloat.pi * 2.0
            let modelPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let projectedPoint = layout.project(modelPoint)
            if index == 0 {
                path.move(to: projectedPoint)
            } else {
                path.addLine(to: projectedPoint)
            }
        }
        path.closeSubpath()
        return path
    }

    private func drawBody(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        isSelected: Bool,
        isHovered: Bool
    ) {
        guard case .body = item.kind else {
            return
        }
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        let fillColor = isSelected ? Color.blue : Color.orange
        drawProjectedBox(
            edit.projectedBox(layout: layout),
            color: fillColor,
            isHighlighted: isSelected || isHovered,
            fillOpacity: isSelected ? 0.42 : 0.36,
            in: &context
        )
    }

    private func bodyProjection(
        for item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> ViewportBodyProjection? {
        guard case .body = item.kind else {
            return nil
        }
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        return edit.projectedBodyProjection(layout: layout)
    }

    private func drawZeroCoordinateFieldHighlight(
        around modelPoint: Point2D,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        guard modelPoint.x.isFinite,
              modelPoint.y.isFinite else {
            return
        }

        let step = constructionFieldStep(for: layout)
        let minX = floor(CGFloat(modelPoint.x) / step) * step
        let minY = floor(CGFloat(modelPoint.y) / step) * step
        let fieldBounds = CGRect(
            x: minX,
            y: minY,
            width: step,
            height: step
        )
        let footprint = layout.projectedFootprint(fieldBounds)
        let highlightPath = path(for: footprint)

        context.fill(highlightPath, with: .color(Color.cyan.opacity(0.12)))
        context.stroke(highlightPath, with: .color(Color.cyan.opacity(0.62)), lineWidth: 1.6)
    }

    private func constructionFieldStep(for layout: ViewportLayout) -> CGFloat {
        var step = max(CGFloat(document.ruler.majorTickMeters), 1.0e-12)
        while step * layout.scale < 42.0 {
            step *= 2.0
        }
        return step
    }

    private func drawConstructionFaceHighlight(
        hit: ViewportHit,
        scene: ViewportScene,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        guard let face = hit.bodyFace,
              let item = scene.items.first(where: { $0.featureID == hit.featureID }),
              let projection = bodyProjection(for: item, layout: layout) else {
            return
        }

        let footprint = projection.footprint(for: face)
        let highlightPath = path(for: footprint)
        context.fill(highlightPath, with: .color(Color.cyan.opacity(0.22)))
        context.stroke(highlightPath, with: .color(Color.cyan.opacity(0.96)), lineWidth: 2.4)
    }

    private func drawSelectionAffordances(
        in context: inout GraphicsContext,
        scene: ViewportScene,
        layout: ViewportLayout,
        selectedFeatureIDs: Set<FeatureID>
    ) {
        let suppressedFeatureIDs = suppressedSketchFeatureIDs(
            in: scene,
            selectedFeatureIDs: selectedFeatureIDs
        )
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        if selectedBodyItems.count > 1,
           let groupFeatureID = selectionGroupFeatureID(for: selectedBodyItems),
           let groupEdit = selectionGroupEditState(for: selectedBodyItems) {
            drawBodySelectionAffordance(
                edit: groupEdit,
                featureID: groupFeatureID,
                in: &context,
                layout: layout,
                drawsBoundingBox: true
            )
        }
        for item in scene.items where selectedFeatureIDs.contains(item.featureID) {
            if case .sketch = item.kind,
               suppressedFeatureIDs.contains(item.featureID) {
                continue
            }
            switch item.kind {
            case .body:
                guard selectedBodyItems.count <= 1 else {
                    continue
                }
                drawBodySelectionAffordance(item, in: &context, layout: layout)
            case .sketch:
                drawSketchSelectionAffordance(item, in: &context, layout: layout)
            }
        }
    }

    private func drawBodySelectionAffordance(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        drawBodySelectionAffordance(
            edit: edit,
            featureID: item.featureID,
            in: &context,
            layout: layout,
            drawsBoundingBox: false
        )
    }

    private func drawBodySelectionAffordance(
        edit: ViewportObjectEditState,
        featureID: FeatureID,
        in context: inout GraphicsContext,
        layout: ViewportLayout,
        drawsBoundingBox: Bool
    ) {
        let projection = edit.projectedBodyProjection(layout: layout)
        let bodyBounds = projection.hitBounds
        let modelCenter = edit.centerPoint
        let center = edit.projectedPoint(modelCenter, layout: layout)
        let affordanceBasis = edit.projectedAxisBasis(layout: layout)
        let radius = max(28.0, min(72.0, min(bodyBounds.width, bodyBounds.height) * 0.38))

        if drawsBoundingBox {
            drawSelectionBoundingBox(edit, in: &context, layout: layout)
        }

        drawBasisRotationArcs(
            center: center,
            radius: radius,
            basis: affordanceBasis,
            highlightedAxis: highlightedRotationAxis(for: featureID),
            in: &context
        )

        let axisLength = bodyAffordanceAxisLength(for: radius)
        let endScaleLength = bodyAffordanceEndScaleLength(
            axisLength: axisLength,
            rotationRadius: radius
        )
        for axis in ViewportCoordinateAxis.allCases {
            drawProjectedMoveArrow(
                axis: axis,
                from: modelCenter,
                edit: edit,
                viewportLength: axisLength,
                layout: layout,
                color: axis.color,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .translate(axis)
                ),
                in: &context
            )

            drawTransformCube(
                at: modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: endScaleLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                edit: edit,
                style: .axisEndScale(axis),
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .oneSidedScale(axis)
                ),
                layout: layout,
                in: &context
            )

            drawProjectedSphere(
                at: modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: radius,
                        axis: axis,
                        layout: layout
                    )
                ),
                edit: edit,
                color: axis.color,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .centerScale(axis)
                ),
                layout: layout,
                in: &context
            )
        }

        drawPivotCube(at: modelCenter, edit: edit, layout: layout, in: &context)
        for handle in bodyFaceCenterHandles(edit, layout: layout) {
            drawProjectedFaceCircle(
                at: handle.position,
                face: handle.face,
                edit: edit,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .faceMove(handle.face)
                ),
                layout: layout,
                in: &context
            )
        }
        for handle in bodyVertexHandles(edit, layout: layout) {
            drawTransformCube(
                edit.projectedCube(
                    center: handle.position,
                    sideLength: handleSideLength(points: 10.0, layout: layout),
                    layout: layout
                ),
                style: .vertex,
                isHighlighted: isAffordanceHovered(
                    featureID: featureID,
                    action: .vertexMove(handle.vertex)
                ),
                in: &context
            )
        }
    }

    private func drawSelectionBoundingBox(
        _ edit: ViewportObjectEditState,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let box = edit.projectedBox(layout: layout)
        var path = Path()
        for edge in box.edges {
            path.move(to: edge.start)
            path.addLine(to: edge.end)
        }
        context.stroke(path, with: .color(Color.white.opacity(0.70)), lineWidth: 1.3)
        context.stroke(path, with: .color(Color.black.opacity(0.36)), lineWidth: 0.55)
    }

    private func drawSketchSelectionAffordance(
        _ item: ViewportSceneItem,
        in context: inout GraphicsContext,
        layout: ViewportLayout
    ) {
        let footprint = layout.projectedFootprint(item.modelBounds)
        drawPlanarSelectionAffordance(
            for: footprint,
            basis: layout.basis,
            in: &context
        )
    }

    private func drawPlanarSelectionAffordance(
        for footprint: ViewportProjectedRect,
        basis: ViewportProjectionBasis,
        in context: inout GraphicsContext
    ) {
        let bounds = footprint.bounds
        let center = footprint.center
        let radius = max(24.0, min(64.0, min(bounds.width, bounds.height) * 0.58))

        drawBasisRotationArcs(
            center: center,
            radius: radius,
            basis: basis,
            highlightedAxis: nil,
            in: &context
        )
        drawMoveArrow(
            axis: .x,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.x.color,
            isHighlighted: false,
            in: &context
        )
        drawMoveArrow(
            axis: .y,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.y.color,
            isHighlighted: false,
            in: &context
        )
        drawMoveArrow(
            axis: .z,
            from: center,
            length: radius * 1.25,
            basis: basis,
            color: ViewportCoordinateAxis.z.color,
            isHighlighted: false,
            in: &context
        )

        drawPivot(at: center, in: &context)
        for point in footprint.handlePoints {
            drawTransformHandle(at: point, style: .vertex, isHighlighted: false, in: &context)
        }
    }

    private func bodyVertexHandles(
        _ edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> [ViewportVertexHandle] {
        ViewportBodyVertex.allCases.map { vertex in
            let position = edit.position(for: vertex)
            return ViewportVertexHandle(
                vertex: vertex,
                position: position,
                point: edit.projectedPoint(position, layout: layout)
            )
        }
    }

    private func bodyFaceCenterHandles(
        _ edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> [ViewportFaceHandle] {
        ViewportBodyFace.editableCases.map { face in
            let position = edit.position(for: face)
            return ViewportFaceHandle(
                face: face,
                position: position,
                point: edit.projectedPoint(position, layout: layout)
            )
        }
    }

    private func bodyAffordanceAxisLength(for rotationRadius: CGFloat) -> CGFloat {
        max(72.0, min(132.0, rotationRadius * 1.9))
    }

    private func bodyAffordanceEndScaleLength(
        axisLength: CGFloat,
        rotationRadius: CGFloat
    ) -> CGFloat {
        min(axisLength - 14.0, max(rotationRadius + 18.0, axisLength - 24.0))
    }

    private func drawCanvasDragPlaceholder(
        _ activeDrag: ViewportActiveDrag,
        in context: inout GraphicsContext,
        size: CGSize,
        basis: ViewportProjectionBasis
    ) {
        let mapper = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: basis
        )
        let drag = mapper.modelDrag(
            from: activeDrag.startLocation,
            to: activeDrag.currentLocation
        )
        guard let placeholder = ViewportCanvasDragPlaceholder(
            drag: drag,
            layout: mapper.layout
        ) else {
            return
        }

        let placeholderPath = path(for: placeholder.footprint)
        context.fill(placeholderPath, with: .color(Color.black.opacity(0.48)))
        context.stroke(placeholderPath, with: .color(Color.white.opacity(0.36)), lineWidth: 1.2)
        context.stroke(placeholderPath, with: .color(Color.accentColor.opacity(0.36)), lineWidth: 1.0)

        drawPlanarSelectionAffordance(
            for: placeholder.footprint,
            basis: mapper.layout.basis,
            in: &context
        )
    }

    private func drawSelectionDragRectangle(
        _ activeDrag: ViewportActiveDrag,
        in context: inout GraphicsContext
    ) {
        let rect = dragRect(from: activeDrag.startLocation, to: activeDrag.currentLocation)
        guard rect.width > 0.0, rect.height > 0.0 else {
            return
        }

        let path = Path(rect)
        context.fill(path, with: .color(Color.accentColor.opacity(0.12)))
        context.stroke(
            path,
            with: .color(Color.accentColor.opacity(0.88)),
            style: StrokeStyle(lineWidth: 1.0, dash: [4.0, 3.0])
        )
    }

    private func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func path(for footprint: ViewportProjectedRect) -> Path {
        var path = Path()
        path.move(to: footprint.bottomLeft)
        path.addLine(to: footprint.bottomRight)
        path.addLine(to: footprint.topRight)
        path.addLine(to: footprint.topLeft)
        path.closeSubpath()
        return path
    }

    private func drawRotationArc(
        center: CGPoint,
        radius: CGFloat,
        planeStart: CGVector,
        planeEnd: CGVector,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let points = projectedRotationArcPoints(
            center: center,
            radius: radius,
            planeStart: planeStart,
            planeEnd: planeEnd
        )
        guard let firstPoint = points.first else {
            return
        }

        var path = Path()
        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.92)),
            lineWidth: isHighlighted ? 4.2 : 2.6
        )
    }

    private func drawBasisRotationArcs(
        center: CGPoint,
        radius: CGFloat,
        basis: ViewportProjectionBasis,
        highlightedAxis: ViewportCoordinateAxis?,
        in context: inout GraphicsContext
    ) {
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.yDirection,
            to: basis.zDirection,
            color: ViewportCoordinateAxis.x.color,
            isHighlighted: highlightedAxis == .x,
            in: &context
        )
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.zDirection,
            to: basis.xDirection,
            color: ViewportCoordinateAxis.y.color,
            isHighlighted: highlightedAxis == .y,
            in: &context
        )
        drawRotationArc(
            center: center,
            radius: radius,
            from: basis.xDirection,
            to: basis.yDirection,
            color: ViewportCoordinateAxis.z.color,
            isHighlighted: highlightedAxis == .z,
            in: &context
        )
    }

    private func drawRotationArc(
        center: CGPoint,
        radius: CGFloat,
        from startDirection: CGVector,
        to endDirection: CGVector,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        drawRotationArc(
            center: center,
            radius: radius,
            planeStart: startDirection,
            planeEnd: endDirection,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func projectedRotationArcPoints(
        center: CGPoint,
        radius: CGFloat,
        planeStart: CGVector,
        planeEnd: CGVector,
        segmentCount: Int = 36
    ) -> [CGPoint] {
        (0 ... segmentCount).map { index in
            let progress = CGFloat(index) / CGFloat(segmentCount)
            let radians = progress * .pi / 2.0
            let startScale = cos(radians) * radius
            let endScale = sin(radians) * radius
            return CGPoint(
                x: center.x + planeStart.dx * startScale + planeEnd.dx * endScale,
                y: center.y + planeStart.dy * startScale + planeEnd.dy * endScale
            )
        }
    }

    private func drawMoveArrow(
        axis: ViewportCoordinateAxis,
        from start: CGPoint,
        length: CGFloat,
        basis: ViewportProjectionBasis,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        drawArrow(
            from: start,
            to: basis.endpoint(from: start, axis: axis, length: length),
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(
            shaft,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.95)),
            lineWidth: isHighlighted ? 4.6 : 3.2
        )

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1.0)
        let unit = CGVector(dx: dx / length, dy: dy / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let base = CGPoint(x: end.x - unit.dx * 13.0, y: end.y - unit.dy * 13.0)

        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: base.x + normal.dx * 6.0, y: base.y + normal.dy * 6.0))
        head.addLine(to: CGPoint(x: base.x - normal.dx * 6.0, y: base.y - normal.dy * 6.0))
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(0.95)))
    }

    private func drawProjectedMoveArrow(
        axis: ViewportCoordinateAxis,
        from start: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        viewportLength: CGFloat,
        layout: ViewportLayout,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let fullLength = edit.modelLength(forViewportLength: viewportLength, axis: axis, layout: layout)
        let headLength = edit.modelLength(
            forViewportLength: isHighlighted ? 18.0 : 15.0,
            axis: axis,
            layout: layout
        )
        let shaftLength = max(fullLength - headLength * 0.7, 0.0)
        let shaftEnd = start.offset(axis: axis, amount: shaftLength)
        let end = start.offset(
            axis: axis,
            amount: fullLength
        )

        var shaft = Path()
        shaft.move(to: edit.projectedPoint(start, layout: layout))
        shaft.addLine(to: edit.projectedPoint(shaftEnd, layout: layout))
        context.stroke(
            shaft,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.95)),
            lineWidth: isHighlighted ? 4.6 : 3.2
        )

        drawProjectedArrowHeadCone(
            axis: axis,
            tip: end,
            edit: edit,
            headLength: headLength,
            baseRadius: handleSideLength(points: isHighlighted ? 8.4 : 6.8, layout: layout),
            layout: layout,
            color: color,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawProjectedArrowHeadCone(
        axis: ViewportCoordinateAxis,
        tip: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        headLength: CGFloat,
        baseRadius: CGFloat,
        layout: ViewportLayout,
        color: Color,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let baseCenter = tip.offset(axis: axis, amount: -headLength)
        let perpendicularAxes = perpendicularAxes(for: axis)
        let segmentCount = 18
        let baseVertices = (0 ..< segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * 2.0 * CGFloat.pi
            return baseCenter
                .offset(axis: perpendicularAxes.first, amount: cos(angle) * baseRadius)
                .offset(axis: perpendicularAxes.second, amount: sin(angle) * baseRadius)
        }
        let projectedTip = edit.projectedPoint(tip, layout: layout)
        let projectedBase = baseVertices.map { edit.projectedPoint($0, layout: layout) }
        let sideOpacity = isHighlighted ? 0.88 : 0.76
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            context.fill(
                path(for: [projectedTip, projectedBase[index], projectedBase[nextIndex]]),
                with: .color(color.opacity(sideOpacity - Double(index % 3) * 0.05))
            )
        }
        context.fill(
            path(for: Array(projectedBase.reversed())),
            with: .color(color.opacity(isHighlighted ? 0.62 : 0.48))
        )
        for index in 0 ..< segmentCount {
            let nextIndex = (index + 1) % segmentCount
            var path = Path()
            path.move(to: projectedBase[index])
            path.addLine(to: projectedBase[nextIndex])
            context.stroke(
                path,
                with: .color(Color.black.opacity(isHighlighted ? 0.48 : 0.34)),
                lineWidth: isHighlighted ? 1.2 : 0.8
            )
        }
        for index in stride(from: 0, to: segmentCount, by: 6) {
            var path = Path()
            path.move(to: projectedTip)
            path.addLine(to: projectedBase[index])
            context.stroke(
                path,
                with: .color(Color.black.opacity(isHighlighted ? 0.36 : 0.24)),
                lineWidth: isHighlighted ? 1.0 : 0.7
            )
        }
    }

    private func perpendicularAxes(
        for axis: ViewportCoordinateAxis
    ) -> (first: ViewportCoordinateAxis, second: ViewportCoordinateAxis) {
        switch axis {
        case .x:
            return (.y, .z)
        case .y:
            return (.z, .x)
        case .z:
            return (.x, .y)
        }
    }

    private func drawProjectedFaceCircle(
        at center: ViewportModelPoint3D,
        face: ViewportBodyFace,
        edit: ViewportObjectEditState,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let axes = facePlaneAxes(for: face)
        let radius = handleSideLength(points: isHighlighted ? 9.8 : 8.0, layout: layout)
        let points = projectedCirclePoints(
            center: center,
            firstAxis: axes.first,
            secondAxis: axes.second,
            radius: radius,
            edit: edit,
            layout: layout
        )
        let path = path(for: points)
        let color = isHighlighted ? Color.cyan : Color.gray
        context.fill(path, with: .color(color.opacity(isHighlighted ? 0.56 : 0.36)))
        context.stroke(
            path,
            with: .color(color.opacity(isHighlighted ? 1.0 : 0.78)),
            lineWidth: isHighlighted ? 2.0 : 1.2
        )
        context.stroke(
            path,
            with: .color(Color.black.opacity(isHighlighted ? 0.30 : 0.22)),
            lineWidth: 0.7
        )
    }

    private func drawProjectedSphere(
        at center: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        color: Color,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let point = edit.projectedPoint(center, layout: layout)
        let diameter: CGFloat = isHighlighted ? 13.5 : 10.5
        let rect = CGRect(
            x: point.x - diameter / 2.0,
            y: point.y - diameter / 2.0,
            width: diameter,
            height: diameter
        )
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(color.opacity(isHighlighted ? 0.96 : 0.78)))
        context.stroke(
            path,
            with: .color(Color.black.opacity(isHighlighted ? 0.38 : 0.28)),
            lineWidth: isHighlighted ? 1.3 : 0.9
        )
        let highlightDiameter = diameter * 0.34
        let highlightRect = CGRect(
            x: point.x - diameter * 0.22,
            y: point.y - diameter * 0.28,
            width: highlightDiameter,
            height: highlightDiameter
        )
        context.fill(
            Path(ellipseIn: highlightRect),
            with: .color(Color.white.opacity(isHighlighted ? 0.50 : 0.34))
        )
    }

    private func facePlaneAxes(
        for face: ViewportBodyFace
    ) -> (first: ViewportCoordinateAxis, second: ViewportCoordinateAxis) {
        switch face {
        case .front, .back:
            return (.x, .z)
        case .top, .bottom:
            return (.x, .y)
        case .left, .right, .side:
            return (.y, .z)
        }
    }

    private func projectedCirclePoints(
        center: ViewportModelPoint3D,
        firstAxis: ViewportCoordinateAxis,
        secondAxis: ViewportCoordinateAxis,
        radius: CGFloat,
        edit: ViewportObjectEditState,
        layout: ViewportLayout,
        segmentCount: Int = 36
    ) -> [CGPoint] {
        (0 ..< segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * 2.0 * CGFloat.pi
            let point = center
                .offset(axis: firstAxis, amount: cos(angle) * radius)
                .offset(axis: secondAxis, amount: sin(angle) * radius)
            return edit.projectedPoint(point, layout: layout)
        }
    }

    private func drawTransformHandle(
        at point: CGPoint,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        switch style {
        case .vertex:
            let size: CGFloat = isHighlighted ? 12.0 : 9.6
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(roundedRect: rect, cornerRadius: 1.8)
            context.fill(path, with: .color((isHighlighted ? Color.cyan : Color.gray).opacity(0.92)))
            context.stroke(path, with: .color(Color.black.opacity(0.42)), lineWidth: isHighlighted ? 1.4 : 1.0)
        case .faceCenter:
            let size: CGFloat = isHighlighted ? 11.0 : 8.4
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color((isHighlighted ? Color.cyan : Color.gray).opacity(0.76)))
            context.stroke(path, with: .color(Color.white.opacity(0.42)), lineWidth: 0.9)
            context.stroke(path, with: .color(Color.black.opacity(0.26)), lineWidth: 0.7)
        case .axisEndScale(let axis), .axisCenterScale(let axis):
            let size: CGFloat = isHighlighted ? 11.8 : 9.2
            let rect = CGRect(x: point.x - size / 2.0, y: point.y - size / 2.0, width: size, height: size)
            let path = Path(roundedRect: rect, cornerRadius: 2.0)
            context.fill(path, with: .color(axis.color.opacity(isHighlighted ? 1.0 : 0.84)))
            context.stroke(path, with: .color(Color.black.opacity(0.36)), lineWidth: isHighlighted ? 1.4 : 0.9)
        }
    }

    private func drawTransformCube(
        at point: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        let sidePoints: CGFloat = switch style {
        case .vertex:
            isHighlighted ? 12.5 : 10.0
        case .faceCenter:
            isHighlighted ? 11.5 : 9.2
        case .axisEndScale, .axisCenterScale:
            isHighlighted ? 12.4 : 9.8
        }
        drawTransformCube(
            edit.projectedCube(
                center: point,
                sideLength: handleSideLength(points: sidePoints, layout: layout),
                layout: layout
            ),
            style: style,
            isHighlighted: isHighlighted,
            in: &context
        )
    }

    private func drawTransformCube(
        _ cube: ViewportProjectedBox,
        style: TransformHandleStyle,
        isHighlighted: Bool,
        in context: inout GraphicsContext
    ) {
        let color = switch style {
        case .vertex:
            isHighlighted ? Color.cyan : Color.gray
        case .faceCenter:
            isHighlighted ? Color.cyan : Color.gray
        case .axisEndScale(let axis), .axisCenterScale(let axis):
            axis.color
        }
        drawProjectedBox(
            cube,
            color: color,
            isHighlighted: isHighlighted,
            fillOpacity: isHighlighted ? 0.78 : 0.58,
            in: &context
        )
    }

    private func drawPivot(at point: CGPoint, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 7.0, y: point.y - 7.0, width: 14.0, height: 14.0)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(Color.gray.opacity(0.72)))
        context.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 1.0)
    }

    private func drawPivotCube(
        at point: ViewportModelPoint3D,
        edit: ViewportObjectEditState,
        layout: ViewportLayout,
        in context: inout GraphicsContext
    ) {
        drawProjectedBox(
            edit.projectedCube(
                center: point,
                sideLength: handleSideLength(points: 12.0, layout: layout),
                layout: layout
            ),
            color: Color.gray,
            isHighlighted: false,
            fillOpacity: 0.62,
            in: &context
        )
    }

    private func drawProjectedBox(
        _ box: ViewportProjectedBox,
        color: Color,
        isHighlighted: Bool,
        fillOpacity: Double,
        in context: inout GraphicsContext
    ) {
        for (index, face) in box.faces.enumerated() {
            let opacity = fillOpacity * (0.72 + Double(index % 3) * 0.11)
            context.fill(
                path(for: face),
                with: .color(color.opacity(opacity))
            )
        }
        for edge in box.edges {
            var path = Path()
            path.move(to: edge.start)
            path.addLine(to: edge.end)
            context.stroke(
                path,
                with: .color((isHighlighted ? Color.white : Color.black).opacity(isHighlighted ? 0.58 : 0.42)),
                lineWidth: isHighlighted ? 1.35 : 0.85
            )
        }
    }

    private func path(for polygon: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = polygon.first else {
            return path
        }
        path.move(to: firstPoint)
        for point in polygon.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func handleSideLength(points: CGFloat, layout: ViewportLayout) -> CGFloat {
        points / max(layout.scale, 1.0e-9)
    }

    private func selectedFeatureIDs() -> Set<FeatureID> {
        Set(
            selection.selectedSceneNodeReferences(in: document).compactMap(\.featureID)
        )
    }

    private func selectedBodyItems(
        in scene: ViewportScene,
        selectedFeatureIDs: Set<FeatureID>
    ) -> [ViewportSceneItem] {
        scene.items.filter { item in
            guard selectedFeatureIDs.contains(item.featureID),
                  case .body = item.kind else {
                return false
            }
            return true
        }
    }

    private func selectionGroupFeatureID(for bodyItems: [ViewportSceneItem]) -> FeatureID? {
        let bodyFeatureIDs = Set(bodyItems.map(\.featureID))
        return selection.selectedSceneNodeReferences(in: document)
            .compactMap(\.featureID)
            .last(where: { bodyFeatureIDs.contains($0) })
            ?? bodyItems.first?.featureID
    }

    private func selectionGroupEditState(for bodyItems: [ViewportSceneItem]) -> ViewportObjectEditState? {
        let edits = bodyItems.map { item in
            editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        }
        return selectionGroupEditState(for: edits)
    }

    private func selectionGroupEditState(for edits: [ViewportObjectEditState]) -> ViewportObjectEditState? {
        guard let first = edits.first else {
            return nil
        }
        return ViewportObjectEditState(
            xMin: edits.map(\.xMin).min() ?? first.xMin,
            xMax: edits.map(\.xMax).max() ?? first.xMax,
            yMin: edits.map(\.yMin).min() ?? first.yMin,
            yMax: edits.map(\.yMax).max() ?? first.yMax,
            zMin: edits.map(\.zMin).min() ?? first.zMin,
            zMax: edits.map(\.zMax).max() ?? first.zMax
        )
    }

    private func bodyEditStates(for bodyItems: [ViewportSceneItem]) -> [FeatureID: ViewportObjectEditState] {
        Dictionary(
            uniqueKeysWithValues: bodyItems.map { item in
                (
                    item.featureID,
                    editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
                )
            }
        )
    }

    private func hoveredFeatureIDs() -> Set<FeatureID> {
        guard let hoveredSceneNodeID = selection.hoveredSceneNodeID,
              let featureID = document.productMetadata.sceneNodes[hoveredSceneNodeID]?.reference?.featureID else {
            return []
        }
        return [featureID]
    }

    private func isAffordanceHovered(
        featureID: FeatureID,
        action: ViewportAffordanceAction
    ) -> Bool {
        hoveredAffordance == ViewportAffordanceTarget(featureID: featureID, action: action)
    }

    private func highlightedRotationAxis(for featureID: FeatureID) -> ViewportCoordinateAxis? {
        guard let hoveredAffordance,
              hoveredAffordance.featureID == featureID,
              case .rotate(let axis) = hoveredAffordance.action else {
            return nil
        }
        return axis
    }

    private func updateCanvasDragPlaceholder(
        from start: CGPoint?,
        to current: CGPoint?,
        size: CGSize
    ) {
        if let start, let current, let pendingAffordance {
            updateAffordanceDrag(
                target: pendingAffordance,
                start: start,
                current: current,
                size: size
            )
            return
        }
        if activeAffordanceDrag != nil {
            return
        }
        guard let start, let current else {
            activeCanvasDrag = nil
            return
        }

        let dragDistance = hypot(current.x - start.x, current.y - start.y)
        guard dragDistance > 4.0 else {
            activeCanvasDrag = nil
            return
        }

        if allowsSelectionRectangle {
            activeCanvasDrag = ViewportActiveDrag(
                startLocation: start,
                currentLocation: current,
                kind: .selection
            )
            return
        }

        guard showsCanvasDragPlaceholder, onCanvasDrag != nil else {
            activeCanvasDrag = nil
            return
        }

        activeCanvasDrag = ViewportActiveDrag(
            startLocation: start,
            currentLocation: current,
            kind: .creation
        )
    }

    private func beginViewportPress(at point: CGPoint, size: CGSize) {
        pendingAffordance = affordanceTarget(at: point, size: size)
        if pendingAffordance != nil {
            activeCanvasDrag = nil
        }
    }

    private func affordanceTarget(
        at point: CGPoint,
        size: CGSize
    ) -> ViewportAffordanceTarget? {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let layout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        ).layout
        return affordanceTarget(at: point, scene: scene, layout: layout)
    }

    private func affordanceTarget(
        at point: CGPoint,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let selectedFeatureIDs = selectedFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        if selectedBodyItems.count > 1,
           let groupFeatureID = selectionGroupFeatureID(for: selectedBodyItems),
           let groupEdit = selectionGroupEditState(for: selectedBodyItems) {
            return bodyAffordanceTarget(
                point: point,
                featureID: groupFeatureID,
                edit: groupEdit,
                layout: layout
            )
        }

        for item in scene.items.reversed() where selectedFeatureIDs.contains(item.featureID) {
            guard case .body = item.kind else {
                continue
            }
            if let target = bodyAffordanceTarget(
                point: point,
                item: item,
                layout: layout
            ) {
                return target
            }
        }
        return nil
    }

    private func bodyAffordanceTarget(
        point: CGPoint,
        item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let edit = editedBodies[item.featureID] ?? ViewportObjectEditState(item: item)
        return bodyAffordanceTarget(
            point: point,
            featureID: item.featureID,
            edit: edit,
            layout: layout
        )
    }

    private func bodyAffordanceTarget(
        point: CGPoint,
        featureID: FeatureID,
        edit: ViewportObjectEditState,
        layout: ViewportLayout
    ) -> ViewportAffordanceTarget? {
        let bodyBounds = edit.projectedBodyProjection(layout: layout).hitBounds
        let modelCenter = edit.centerPoint
        let center = edit.projectedPoint(modelCenter, layout: layout)
        let affordanceBasis = edit.projectedAxisBasis(layout: layout)
        let radius = max(28.0, min(72.0, min(bodyBounds.width, bodyBounds.height) * 0.38))
        let axisLength = bodyAffordanceAxisLength(for: radius)
        let endScaleLength = bodyAffordanceEndScaleLength(
            axisLength: axisLength,
            rotationRadius: radius
        )
        let handleTolerance: CGFloat = 10.0

        for axis in ViewportCoordinateAxis.allCases {
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: endScaleLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distance(to: endpoint) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .oneSidedScale(axis))
            }

            let centerScalePoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: radius,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distance(to: centerScalePoint) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .centerScale(axis))
            }
        }

        for handle in bodyVertexHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .vertexMove(handle.vertex))
            }
        }

        for handle in bodyFaceCenterHandles(edit, layout: layout) {
            if point.distance(to: handle.point) <= handleTolerance {
                return ViewportAffordanceTarget(featureID: featureID, action: .faceMove(handle.face))
            }
        }

        if let axis = rotationAffordanceAxis(
            point: point,
            center: center,
            radius: radius,
            basis: affordanceBasis
        ) {
            return ViewportAffordanceTarget(featureID: featureID, action: .rotate(axis))
        }

        for axis in ViewportCoordinateAxis.allCases {
            let endpoint = edit.projectedPoint(
                modelCenter.offset(
                    axis: axis,
                    amount: edit.modelLength(
                        forViewportLength: axisLength,
                        axis: axis,
                        layout: layout
                    )
                ),
                layout: layout
            )
            if point.distanceToSegment(start: center, end: endpoint) <= 7.0 {
                return ViewportAffordanceTarget(featureID: featureID, action: .translate(axis))
            }
        }

        return nil
    }

    private func viewportHit(
        point: CGPoint,
        in scene: ViewportScene,
        layout: ViewportLayout
    ) -> ViewportHit? {
        var bestHit: (hit: ViewportHit, score: CGFloat)?
        for item in scene.items {
            guard let candidate = viewportHitCandidate(
                for: item,
                point: point,
                layout: layout
            ) else {
                continue
            }
            if let current = bestHit {
                if candidate.score < current.score {
                    bestHit = candidate
                }
            } else {
                bestHit = candidate
            }
        }
        return bestHit?.hit
    }

    private func viewportHitCandidate(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (hit: ViewportHit, score: CGFloat)? {
        switch item.kind {
        case .sketch(let primitives):
            guard let score = hitScoreForSketch(primitives, point: point, layout: layout) else {
                return nil
            }
            return (
                ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind),
                score
            )
        case .body:
            guard let face = hitBodyFace(for: item, point: point, layout: layout) else {
                return nil
            }
            return (
                ViewportHit(featureID: item.featureID, kind: item.kind.selectableKind, bodyFace: face.face),
                face.score
            )
        }
    }

    private func hitBodyFace(
        for item: ViewportSceneItem,
        point: CGPoint,
        layout: ViewportLayout
    ) -> (face: ViewportBodyFace, score: CGFloat)? {
        guard let projection = bodyProjection(for: item, layout: layout) else {
            return nil
        }
        let faces: [(face: ViewportBodyFace, score: CGFloat)] = [
            (.front, 6.0),
            (.back, 6.1),
            (.top, 6.2),
            (.bottom, 6.3),
            (.left, 6.4),
            (.right, 6.5),
        ]
        for face in faces {
            let footprint = projection.footprint(for: face.face)
            if footprint.contains(point, tolerance: 8.0) {
                return face
            }
        }
        return nil
    }

    private func hitScoreForSketch(
        _ primitives: [ViewportSketchPrimitive],
        point: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat? {
        var bestDistance: CGFloat?
        for primitive in primitives {
            let distance: CGFloat
            switch primitive {
            case .point(let modelPoint):
                distance = point.distance(to: layout.project(modelPoint))
            case .line(let start, let end):
                distance = point.distanceToSegment(
                    start: layout.project(start),
                    end: layout.project(end)
                )
            case .circle(let center, let radiusMeters):
                distance = distanceToProjectedCircle(
                    center: center,
                    radiusMeters: radiusMeters,
                    point: point,
                    layout: layout
                )
            }
            if let current = bestDistance {
                bestDistance = min(current, distance)
            } else {
                bestDistance = distance
            }
        }

        guard let bestDistance, bestDistance <= 8.0 else {
            return nil
        }
        return bestDistance
    }

    private func distanceToProjectedCircle(
        center: CGPoint,
        radiusMeters: Double,
        point: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var previousPoint: CGPoint?

        for index in 0 ... 64 {
            let angle = CGFloat(index) / 64.0 * CGFloat.pi * 2.0
            let modelPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let projectedPoint = layout.project(modelPoint)
            if let previousPoint {
                bestDistance = min(
                    bestDistance,
                    point.distanceToSegment(
                        start: previousPoint,
                        end: projectedPoint
                    )
                )
            }
            previousPoint = projectedPoint
        }

        return bestDistance
    }

    private func rotationAffordanceAxis(
        point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        basis: ViewportProjectionBasis
    ) -> ViewportCoordinateAxis? {
        let candidates: [(axis: ViewportCoordinateAxis, start: CGVector, end: CGVector)] = [
            (.x, basis.yDirection, basis.zDirection),
            (.y, basis.zDirection, basis.xDirection),
            (.z, basis.xDirection, basis.yDirection),
        ]
        var best: (axis: ViewportCoordinateAxis, distance: CGFloat)?
        for candidate in candidates {
            let distance = distanceToRotationArc(
                point: point,
                center: center,
                radius: radius,
                from: candidate.start,
                to: candidate.end
            )
            if let current = best {
                if distance < current.distance {
                    best = (candidate.axis, distance)
                }
            } else {
                best = (candidate.axis, distance)
            }
        }
        guard let best, best.distance <= 8.0 else {
            return nil
        }
        return best.axis
    }

    private func distanceToRotationArc(
        point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        from startDirection: CGVector,
        to endDirection: CGVector
    ) -> CGFloat {
        projectedRotationArcPoints(
            center: center,
            radius: radius,
            planeStart: startDirection,
            planeEnd: endDirection
        )
        .map { point.distance(to: $0) }
        .min() ?? CGFloat.greatestFiniteMagnitude
    }

    private func updateAffordanceDrag(
        target: ViewportAffordanceTarget,
        start: CGPoint,
        current: CGPoint,
        size: CGSize
    ) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let selectedFeatureIDs = selectedFeatureIDs()
        let selectedBodyItems = selectedBodyItems(in: scene, selectedFeatureIDs: selectedFeatureIDs)
        let targetIsSelectionGroup = selectedBodyItems.count > 1
            && selectedBodyItems.contains { $0.featureID == target.featureID }

        let dragState: ViewportAffordanceDragState
        if let activeAffordanceDrag,
           activeAffordanceDrag.target == target {
            dragState = activeAffordanceDrag
        } else {
            let baseEdits: [FeatureID: ViewportObjectEditState]
            let baseGroupEdit: ViewportObjectEditState?
            if targetIsSelectionGroup {
                baseEdits = bodyEditStates(for: selectedBodyItems)
                baseGroupEdit = selectionGroupEditState(for: Array(baseEdits.values))
            } else {
                guard let item = scene.items.first(where: { $0.featureID == target.featureID }),
                      case .body = item.kind else {
                    return
                }
                baseEdits = [
                    target.featureID: editedBodies[target.featureID] ?? ViewportObjectEditState(item: item)
                ]
                baseGroupEdit = nil
            }
            dragState = ViewportAffordanceDragState(
                target: target,
                startPoint: start,
                baseEdits: baseEdits,
                baseGroupEdit: baseGroupEdit
            )
            activeAffordanceDrag = dragState
        }

        let layout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        ).layout
        if let baseGroupEdit = dragState.baseGroupEdit {
            let nextGroupEdit = baseGroupEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            )
            for (featureID, baseEdit) in dragState.baseEdits {
                editedBodies[featureID] = baseEdit.transformedFromGroup(
                    baseGroup: baseGroupEdit,
                    targetGroup: nextGroupEdit
                )
            }
        } else if let baseEdit = dragState.baseEdits[target.featureID] {
            editedBodies[target.featureID] = baseEdit.applying(
                action: target.action,
                start: dragState.startPoint,
                current: current,
                layout: layout
            )
        }
    }

    private func pick(
        at point: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if pendingAffordance != nil {
            pendingAffordance = nil
            activeAffordanceDrag = nil
            return
        }
        guard let onPick else {
            return
        }
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let mapper = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        )
        let hit = viewportHit(
            point: point,
            in: sceneBySuppressingSketches(
                scene,
                selectedFeatureIDs: selectedFeatureIDs()
            ),
            layout: mapper.layout
        )
        let sketchPlane = constructionSketchPlane(for: hit)
        onPick(
            ViewportCanvasTarget(
                hit: hit,
                modelPoint: mapper.modelPoint(for: point),
                sketchPlane: sketchPlane,
                selectionIntent: selectionIntent
            )
        )
    }

    private func handleCanvasDrag(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        if pendingAffordance != nil || activeAffordanceDrag != nil {
            pendingAffordance = nil
            activeAffordanceDrag = nil
            activeCanvasDrag = nil
            return
        }
        defer {
            activeCanvasDrag = nil
        }
        if allowsSelectionRectangle {
            handleSelectionDrag(
                from: start,
                to: end,
                size: size,
                selectionIntent: selectionIntent
            )
            return
        }
        guard let onCanvasDrag else {
            return
        }
        let mapper = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        )
        onCanvasDrag(
            mapper.modelDrag(
                from: start,
                to: end,
                sketchPlane: constructionSketchPlane(for: hoveredCanvasHit)
            )
        )
    }

    private func handleSelectionDrag(
        from start: CGPoint,
        to end: CGPoint,
        size: CGSize,
        selectionIntent: ViewportSelectionIntent
    ) {
        guard let onSelectionDrag else {
            return
        }
        let rect = dragRect(from: start, to: end)
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let mapper = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        )
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedFeatureIDs()
        )
        onSelectionDrag(
            ViewportSelectionDragTarget(
                hits: selectionHits(in: rect, scene: hitScene, layout: mapper.layout),
                selectionIntent: selectionIntent
            )
        )
    }

    private func selectionHits(
        in rect: CGRect,
        scene: ViewportScene,
        layout: ViewportLayout
    ) -> [ViewportHit] {
        var hits: [ViewportHit] = []
        var seenFeatureIDs: Set<FeatureID> = []

        for item in scene.items {
            guard let selectableBounds = selectionBounds(for: item, layout: layout),
                  rect.intersects(selectableBounds),
                  seenFeatureIDs.insert(item.featureID).inserted else {
                continue
            }

            switch item.kind {
            case .sketch:
                hits.append(ViewportHit(featureID: item.featureID, kind: .sketch))
            case .body:
                hits.append(ViewportHit(featureID: item.featureID, kind: .body))
            }
        }

        return hits
    }

    private func selectionBounds(
        for item: ViewportSceneItem,
        layout: ViewportLayout
    ) -> CGRect? {
        switch item.kind {
        case .sketch(let primitives):
            let primitiveBounds = sketchSelectionBounds(primitives, layout: layout)
            if primitiveBounds.isNull {
                return layout.projectedRect(item.modelBounds).insetBy(dx: -8.0, dy: -8.0)
            }
            return primitiveBounds.insetBy(dx: -8.0, dy: -8.0)
        case .body:
            guard let projection = bodyProjection(for: item, layout: layout) else {
                return nil
            }
            return projection.hitBounds.insetBy(dx: -2.0, dy: -2.0)
        }
    }

    private func sketchSelectionBounds(
        _ primitives: [ViewportSketchPrimitive],
        layout: ViewportLayout
    ) -> CGRect {
        var bounds = CGRect.null
        for primitive in primitives {
            switch primitive {
            case .point(let point):
                bounds = bounds.union(pointRect(layout.project(point), radius: 2.0))
            case .line(let start, let end):
                bounds = bounds.union(pointRect(layout.project(start), radius: 2.0))
                bounds = bounds.union(pointRect(layout.project(end), radius: 2.0))
            case .circle(let center, let radiusMeters):
                let radius = max(CGFloat(radiusMeters), 1.0e-12)
                for index in 0 ... 32 {
                    let angle = CGFloat(index) / 32.0 * CGFloat.pi * 2.0
                    let modelPoint = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    bounds = bounds.union(pointRect(layout.project(modelPoint), radius: 2.0))
                }
            }
        }
        return bounds
    }

    private func pointRect(_ point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
    }

    private func hover(at point: CGPoint, size: CGSize) {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(document: document)
        let mapper = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: currentProjectionBasis
        )
        if let affordanceTarget = affordanceTarget(
            at: point,
            scene: scene,
            layout: mapper.layout
        ) {
            hoveredAffordance = affordanceTarget
            hoveredCanvasHit = nil
            hoveredModelPoint = nil
            onHover?(nil)
            return
        }
        hoveredAffordance = nil
        let hitScene = sceneBySuppressingSketches(
            scene,
            selectedFeatureIDs: selectedFeatureIDs()
        )
        let hit = viewportHit(
            point: point,
            in: hitScene,
            layout: mapper.layout
        )
        hoveredCanvasHit = hit
        hoveredModelPoint = mapper.modelPoint(for: point)
        onHover?(hit)
    }

    private func clearCanvasHover() {
        hoveredAffordance = nil
        hoveredCanvasHit = nil
        hoveredModelPoint = nil
        onHover?(nil)
    }

    private func clearProjectionTransition(_ id: UUID) {
        Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64((Self.projectionAnimationDuration + 0.05) * 1_000_000_000.0)
                )
            } catch {
                return
            }

            if projectionTransition?.id == id {
                projectionTransition = nil
            }
        }
    }

    private func selectProjectionAxis(_ axis: ViewportCoordinateAxis?) {
        let now = Date()
        let startBasis = projectionBasis(at: now)
        let targetBasis = targetProjectionBasis(for: axis)
        let transition = ViewportProjectionTransition(
            startBasis: startBasis,
            targetBasis: targetBasis,
            startDate: now,
            duration: Self.projectionAnimationDuration
        )
        selectedAxis = axis
        orbitBasis = nil
        projectionTransition = transition
        activeCanvasDrag = nil
        clearCanvasHover()
        clearProjectionTransition(transition.id)
    }

    private func resetViewportCamera() {
        camera = .identity
        activeCanvasDrag = nil
        clearCanvasHover()
    }

    private func constructionSketchPlane(for hit: ViewportHit?) -> SketchPlane {
        guard showsConstructionPlaneHover else {
            return .xy
        }

        switch hit?.bodyFace {
        case .top, .bottom:
            return .xy
        case .left, .right, .side:
            return .yz
        case .front, .back, .none:
            return .zx
        }
    }

    private func panCanvas(by delta: CGSize) {
        camera = ViewportCamera(
            zoom: camera.zoom,
            pan: CGSize(
                width: camera.pan.width + delta.width,
                height: camera.pan.height + delta.height
            )
        )
    }

    private func orbitViewport(by delta: CGSize) {
        let nextBasis = currentProjectionBasis.orbited(by: delta)
        selectedAxis = nil
        orbitBasis = nextBasis
        projectionTransition = nil
        activeCanvasDrag = nil
        clearCanvasHover()
    }

    private func zoomCanvas(
        by factor: CGFloat,
        anchor: CGPoint,
        size: CGSize
    ) {
        let basis = currentProjectionBasis
        let oldLayout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: camera,
            basis: basis
        ).layout
        let anchoredModelPoint = oldLayout.unproject(anchor)
        let newZoom = min(
            max(camera.zoom * factor, ViewportCamera.minimumZoom),
            ViewportCamera.maximumZoom
        )
        var nextCamera = ViewportCamera(
            zoom: newZoom,
            pan: camera.pan
        )
        let nextLayout = ViewportModelCoordinateMapper(
            document: document,
            size: size,
            objectRegistry: objectRegistry,
            camera: nextCamera,
            basis: basis
        ).layout
        let projectedAnchor = nextLayout.project(anchoredModelPoint)
        nextCamera.pan.width += anchor.x - projectedAnchor.x
        nextCamera.pan.height += anchor.y - projectedAnchor.y
        camera = nextCamera.clamped()
    }
}

private struct ViewportActiveDrag: Equatable {
    var startLocation: CGPoint
    var currentLocation: CGPoint
    var kind: Kind

    enum Kind: Equatable {
        case creation
        case selection
    }

    var accessibilityIdentifier: String {
        switch kind {
        case .creation:
            "CanvasDragPlaceholder"
        case .selection:
            "CanvasSelectionRectangle"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .creation:
            "Canvas drag placeholder"
        case .selection:
            "Canvas selection rectangle"
        }
    }
}

private struct ViewportProjectionTransition: Equatable {
    var id: UUID = UUID()
    var startBasis: ViewportProjectionBasis
    var targetBasis: ViewportProjectionBasis
    var startDate: Date
    var duration: TimeInterval

    func basis(at date: Date) -> ViewportProjectionBasis {
        let elapsed = max(date.timeIntervalSince(startDate), 0.0)
        let rawProgress = CGFloat(elapsed / max(duration, 1.0e-9))
        let progress = min(max(rawProgress, 0.0), 1.0)
        let easedProgress = progress * progress * (3.0 - 2.0 * progress)
        return ViewportProjectionBasis.interpolated(
            from: startBasis,
            to: targetBasis,
            progress: easedProgress
        )
    }
}

private struct ViewportAffordanceDragState: Equatable {
    var target: ViewportAffordanceTarget
    var startPoint: CGPoint
    var baseEdits: [FeatureID: ViewportObjectEditState]
    var baseGroupEdit: ViewportObjectEditState?
}

private struct ViewportAffordanceTarget: Equatable {
    var featureID: FeatureID
    var action: ViewportAffordanceAction
}

private enum ViewportAffordanceAction: Equatable {
    case translate(ViewportCoordinateAxis)
    case oneSidedScale(ViewportCoordinateAxis)
    case centerScale(ViewportCoordinateAxis)
    case rotate(ViewportCoordinateAxis)
    case vertexMove(ViewportBodyVertex)
    case faceMove(ViewportBodyFace)
}

private struct ViewportVertexHandle: Equatable {
    var vertex: ViewportBodyVertex
    var position: ViewportModelPoint3D
    var point: CGPoint
}

private struct ViewportFaceHandle: Equatable {
    var face: ViewportBodyFace
    var position: ViewportModelPoint3D
    var point: CGPoint
}

private enum ViewportBodyVertex: CaseIterable, Equatable {
    case frontBottomLeft
    case frontBottomRight
    case frontTopRight
    case frontTopLeft
    case backBottomLeft
    case backBottomRight
    case backTopRight
    case backTopLeft

    var usesMinX: Bool {
        switch self {
        case .frontBottomLeft, .frontTopLeft, .backBottomLeft, .backTopLeft:
            true
        case .frontBottomRight, .frontTopRight, .backBottomRight, .backTopRight:
            false
        }
    }

    var usesMinY: Bool {
        switch self {
        case .frontBottomLeft, .frontBottomRight, .frontTopRight, .frontTopLeft:
            true
        case .backBottomLeft, .backBottomRight, .backTopRight, .backTopLeft:
            false
        }
    }

    var usesMinZ: Bool {
        switch self {
        case .frontBottomLeft, .frontBottomRight, .backBottomLeft, .backBottomRight:
            true
        case .frontTopRight, .frontTopLeft, .backTopRight, .backTopLeft:
            false
        }
    }
}

private struct ViewportModelPoint3D: Equatable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    func offset(axis: ViewportCoordinateAxis, amount: CGFloat) -> ViewportModelPoint3D {
        switch axis {
        case .x:
            ViewportModelPoint3D(x: x + amount, y: y, z: z)
        case .y:
            ViewportModelPoint3D(x: x, y: y + amount, z: z)
        case .z:
            ViewportModelPoint3D(x: x, y: y, z: z + amount)
        }
    }
}

private struct ViewportModelVector3D: Equatable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static func + (lhs: ViewportModelVector3D, rhs: ViewportModelVector3D) -> ViewportModelVector3D {
        ViewportModelVector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func * (vector: ViewportModelVector3D, scalar: CGFloat) -> ViewportModelVector3D {
        ViewportModelVector3D(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    static func * (scalar: CGFloat, vector: ViewportModelVector3D) -> ViewportModelVector3D {
        vector * scalar
    }
}

private struct ViewportObjectOrientation: Equatable {
    var xAxis: ViewportModelVector3D
    var yAxis: ViewportModelVector3D
    var zAxis: ViewportModelVector3D

    static var identity: ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: ViewportModelVector3D(x: 1.0, y: 0.0, z: 0.0),
            yAxis: ViewportModelVector3D(x: 0.0, y: 1.0, z: 0.0),
            zAxis: ViewportModelVector3D(x: 0.0, y: 0.0, z: 1.0)
        )
    }

    var inverse: ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: ViewportModelVector3D(x: xAxis.x, y: yAxis.x, z: zAxis.x),
            yAxis: ViewportModelVector3D(x: xAxis.y, y: yAxis.y, z: zAxis.y),
            zAxis: ViewportModelVector3D(x: xAxis.z, y: yAxis.z, z: zAxis.z)
        )
    }

    func applied(to vector: ViewportModelVector3D) -> ViewportModelVector3D {
        xAxis * vector.x + yAxis * vector.y + zAxis * vector.z
    }

    func concatenating(_ rhs: ViewportObjectOrientation) -> ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: applied(to: rhs.xAxis),
            yAxis: applied(to: rhs.yAxis),
            zAxis: applied(to: rhs.zAxis)
        )
    }

    mutating func rotate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        let cosine = cos(amount)
        let sine = sin(amount)
        switch axis {
        case .x:
            let baseY = yAxis
            let baseZ = zAxis
            yAxis = baseY * cosine + baseZ * sine
            zAxis = baseY * -sine + baseZ * cosine
        case .y:
            let baseX = xAxis
            let baseZ = zAxis
            xAxis = baseX * cosine + baseZ * -sine
            zAxis = baseX * sine + baseZ * cosine
        case .z:
            let baseX = xAxis
            let baseY = yAxis
            xAxis = baseX * cosine + baseY * sine
            yAxis = baseX * -sine + baseY * cosine
        }
    }
}

private struct ViewportProjectedBox {
    var minXMinYMinZ: CGPoint
    var maxXMinYMinZ: CGPoint
    var minXMaxYMinZ: CGPoint
    var maxXMaxYMinZ: CGPoint
    var minXMinYMaxZ: CGPoint
    var maxXMinYMaxZ: CGPoint
    var minXMaxYMaxZ: CGPoint
    var maxXMaxYMaxZ: CGPoint

    var faces: [[CGPoint]] {
        [
            [minXMinYMinZ, minXMinYMaxZ, minXMaxYMaxZ, minXMaxYMinZ],
            [maxXMinYMinZ, maxXMaxYMinZ, maxXMaxYMaxZ, maxXMinYMaxZ],
            [minXMinYMinZ, maxXMinYMinZ, maxXMinYMaxZ, minXMinYMaxZ],
            [minXMaxYMinZ, minXMaxYMaxZ, maxXMaxYMaxZ, maxXMaxYMinZ],
            [minXMinYMinZ, minXMaxYMinZ, maxXMaxYMinZ, maxXMinYMinZ],
            [minXMinYMaxZ, maxXMinYMaxZ, maxXMaxYMaxZ, minXMaxYMaxZ],
        ]
    }

    var edges: [(start: CGPoint, end: CGPoint)] {
        [
            (minXMinYMinZ, maxXMinYMinZ),
            (minXMinYMinZ, minXMaxYMinZ),
            (maxXMinYMinZ, maxXMaxYMinZ),
            (minXMaxYMinZ, maxXMaxYMinZ),
            (minXMinYMaxZ, maxXMinYMaxZ),
            (minXMinYMaxZ, minXMaxYMaxZ),
            (maxXMinYMaxZ, maxXMaxYMaxZ),
            (minXMaxYMaxZ, maxXMaxYMaxZ),
            (minXMinYMinZ, minXMinYMaxZ),
            (maxXMinYMinZ, maxXMinYMaxZ),
            (minXMaxYMinZ, minXMaxYMaxZ),
            (maxXMaxYMinZ, maxXMaxYMaxZ),
        ]
    }
}

private struct ViewportObjectEditState: Equatable {
    var xMin: CGFloat
    var xMax: CGFloat
    var yMin: CGFloat
    var yMax: CGFloat
    var zMin: CGFloat
    var zMax: CGFloat
    var orientation: ViewportObjectOrientation

    private static let minimumSize: CGFloat = 1.0e-6

    init(item: ViewportSceneItem) {
        let yExtents: (min: CGFloat, max: CGFloat)
        if case .body(let component) = item.kind {
            yExtents = (
                min: CGFloat(component.yMinMeters),
                max: CGFloat(component.yMaxMeters)
            )
        } else {
            yExtents = (0.0, Self.minimumSize)
        }
        self.xMin = item.modelBounds.minX
        self.xMax = item.modelBounds.maxX
        self.yMin = yExtents.min
        self.yMax = max(yExtents.max, yExtents.min + Self.minimumSize)
        self.zMin = item.modelBounds.minY
        self.zMax = item.modelBounds.maxY
        self.orientation = .identity
    }

    init(
        xMin: CGFloat,
        xMax: CGFloat,
        yMin: CGFloat,
        yMax: CGFloat,
        zMin: CGFloat,
        zMax: CGFloat
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.zMin = zMin
        self.zMax = zMax
        self.orientation = .identity
        normalize()
    }

    func projectedBodyProjection(layout: ViewportLayout) -> ViewportBodyProjection {
        let frontFootprint = projectedFootprint(y: yMin, layout: layout)
        let backFootprint = projectedFootprint(y: yMax, layout: layout)
        return ViewportBodyProjection(
            frontFootprint: frontFootprint,
            backFootprint: backFootprint,
            offset: CGSize(
                width: backFootprint.center.x - frontFootprint.center.x,
                height: backFootprint.center.y - frontFootprint.center.y
            )
        )
    }

    func applying(
        action: ViewportAffordanceAction,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> ViewportObjectEditState {
        var next = self
        switch action {
        case .translate(let axis):
            next.translate(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .oneSidedScale(let axis):
            next.resizePositive(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .centerScale(let axis):
            next.resizeFromCenter(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .rotate(let axis):
            next.rotate(axis, by: rotationAmount(axis: axis, start: start, current: current, layout: layout))
        case .vertexMove(let vertex):
            next.moveVertex(vertex, start: start, current: current, layout: layout)
        case .faceMove(let face):
            next.moveFace(face, start: start, current: current, layout: layout)
        }
        next.normalize()
        return next
    }

    func transformedFromGroup(
        baseGroup: ViewportObjectEditState,
        targetGroup: ViewportObjectEditState
    ) -> ViewportObjectEditState {
        var next = self
        next.xMin = Self.map(
            xMin,
            fromMin: baseGroup.xMin,
            fromMax: baseGroup.xMax,
            toMin: targetGroup.xMin,
            toMax: targetGroup.xMax
        )
        next.xMax = Self.map(
            xMax,
            fromMin: baseGroup.xMin,
            fromMax: baseGroup.xMax,
            toMin: targetGroup.xMin,
            toMax: targetGroup.xMax
        )
        next.yMin = Self.map(
            yMin,
            fromMin: baseGroup.yMin,
            fromMax: baseGroup.yMax,
            toMin: targetGroup.yMin,
            toMax: targetGroup.yMax
        )
        next.yMax = Self.map(
            yMax,
            fromMin: baseGroup.yMin,
            fromMax: baseGroup.yMax,
            toMin: targetGroup.yMin,
            toMax: targetGroup.yMax
        )
        next.zMin = Self.map(
            zMin,
            fromMin: baseGroup.zMin,
            fromMax: baseGroup.zMax,
            toMin: targetGroup.zMin,
            toMax: targetGroup.zMax
        )
        next.zMax = Self.map(
            zMax,
            fromMin: baseGroup.zMin,
            fromMax: baseGroup.zMax,
            toMin: targetGroup.zMin,
            toMax: targetGroup.zMax
        )
        let groupRotationDelta = targetGroup.orientation.concatenating(baseGroup.orientation.inverse)
        next.orientation = groupRotationDelta.concatenating(orientation)
        next.normalize()
        return next
    }

    private static func map(
        _ value: CGFloat,
        fromMin: CGFloat,
        fromMax: CGFloat,
        toMin: CGFloat,
        toMax: CGFloat
    ) -> CGFloat {
        let sourceSpan = fromMax - fromMin
        guard abs(sourceSpan) > minimumSize else {
            return (toMin + toMax) / 2.0
        }
        let ratio = (value - fromMin) / sourceSpan
        return toMin + ratio * (toMax - toMin)
    }

    private var centerX: CGFloat { (xMin + xMax) / 2.0 }
    private var centerY: CGFloat { (yMin + yMax) / 2.0 }
    private var centerZ: CGFloat { (zMin + zMax) / 2.0 }

    var centerPoint: ViewportModelPoint3D {
        ViewportModelPoint3D(x: centerX, y: centerY, z: centerZ)
    }

    func position(for vertex: ViewportBodyVertex) -> ViewportModelPoint3D {
        ViewportModelPoint3D(
            x: vertex.usesMinX ? xMin : xMax,
            y: vertex.usesMinY ? yMin : yMax,
            z: vertex.usesMinZ ? zMin : zMax
        )
    }

    func position(for face: ViewportBodyFace) -> ViewportModelPoint3D {
        switch face {
        case .front:
            ViewportModelPoint3D(x: centerX, y: yMin, z: centerZ)
        case .back:
            ViewportModelPoint3D(x: centerX, y: yMax, z: centerZ)
        case .top:
            ViewportModelPoint3D(x: centerX, y: centerY, z: zMax)
        case .bottom:
            ViewportModelPoint3D(x: centerX, y: centerY, z: zMin)
        case .left:
            ViewportModelPoint3D(x: xMin, y: centerY, z: centerZ)
        case .right, .side:
            ViewportModelPoint3D(x: xMax, y: centerY, z: centerZ)
        }
    }

    func projectedPoint(
        _ point: ViewportModelPoint3D,
        layout: ViewportLayout
    ) -> CGPoint {
        projectedPoint(x: point.x, y: point.y, z: point.z, layout: layout)
    }

    func projectedAxisBasis(layout: ViewportLayout) -> ViewportProjectionBasis {
        ViewportProjectionBasis(
            mode: .orbit,
            xDirection: projectedAxisDirection(.x, layout: layout),
            yDirection: projectedAxisDirection(.y, layout: layout),
            zDirection: projectedAxisDirection(.z, layout: layout)
        )
    }

    func projectedAxisDirection(
        _ axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGVector {
        projectedAxisVector(axis, layout: layout).normalized
    }

    func modelLength(
        forViewportLength length: CGFloat,
        axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGFloat {
        length / max(projectedAxisVector(axis, layout: layout).length, 1.0e-9)
    }

    func projectedCube(
        center: ViewportModelPoint3D,
        sideLength: CGFloat,
        layout: ViewportLayout
    ) -> ViewportProjectedBox {
        let halfSide = sideLength / 2.0
        return ViewportProjectedBox(
            minXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y - halfSide, z: center.z - halfSide),
                layout: layout
            ),
            maxXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y - halfSide, z: center.z - halfSide),
                layout: layout
            ),
            minXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y + halfSide, z: center.z - halfSide),
                layout: layout
            ),
            maxXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y + halfSide, z: center.z - halfSide),
                layout: layout
            ),
            minXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y - halfSide, z: center.z + halfSide),
                layout: layout
            ),
            maxXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y - halfSide, z: center.z + halfSide),
                layout: layout
            ),
            minXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y + halfSide, z: center.z + halfSide),
                layout: layout
            ),
            maxXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y + halfSide, z: center.z + halfSide),
                layout: layout
            )
        )
    }

    func projectedBox(layout: ViewportLayout) -> ViewportProjectedBox {
        ViewportProjectedBox(
            minXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMin, z: zMin),
                layout: layout
            ),
            maxXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMin, z: zMin),
                layout: layout
            ),
            minXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMax, z: zMin),
                layout: layout
            ),
            maxXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMax, z: zMin),
                layout: layout
            ),
            minXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMin, z: zMax),
                layout: layout
            ),
            maxXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMin, z: zMax),
                layout: layout
            ),
            minXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMax, z: zMax),
                layout: layout
            ),
            maxXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMax, z: zMax),
                layout: layout
            )
        )
    }

    private func projectedFootprint(y: CGFloat, layout: ViewportLayout) -> ViewportProjectedRect {
        ViewportProjectedRect(
            bottomLeft: projectedPoint(x: xMin, y: y, z: zMin, layout: layout),
            bottomRight: projectedPoint(x: xMax, y: y, z: zMin, layout: layout),
            topRight: projectedPoint(x: xMax, y: y, z: zMax, layout: layout),
            topLeft: projectedPoint(x: xMin, y: y, z: zMax, layout: layout)
        )
    }

    private func projectedPoint(
        x: CGFloat,
        y: CGFloat,
        z: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint {
        let rotated = rotatedPoint(x: x, y: y, z: z)
        let base = layout.project(CGPoint(x: rotated.x, y: rotated.z))
        return CGPoint(
            x: base.x + layout.basis.yDirection.dx * rotated.y * layout.scale,
            y: base.y + layout.basis.yDirection.dy * rotated.y * layout.scale
        )
    }

    private func projectedAxisVector(
        _ axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGVector {
        let start = projectedPoint(centerPoint, layout: layout)
        let end = projectedPoint(centerPoint.offset(axis: axis, amount: 1.0), layout: layout)
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private func rotatedPoint(x: CGFloat, y: CGFloat, z: CGFloat) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let local = ViewportModelVector3D(
            x: x - centerX,
            y: y - centerY,
            z: z - centerZ
        )
        let rotated = orientation.applied(to: local)
        return (centerX + rotated.x, centerY + rotated.y, centerZ + rotated.z)
    }

    private mutating func translate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMin += amount
            xMax += amount
        case .y:
            yMin += amount
            yMax += amount
        case .z:
            zMin += amount
            zMax += amount
        }
    }

    private mutating func resizePositive(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMax += amount
        case .y:
            yMax += amount
        case .z:
            zMax += amount
        }
    }

    private mutating func resizeFromCenter(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMin -= amount
            xMax += amount
        case .y:
            yMin -= amount
            yMax += amount
        case .z:
            zMin -= amount
            zMax += amount
        }
    }

    private mutating func rotate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        orientation.rotate(axis, by: amount)
    }

    private mutating func moveFace(
        _ face: ViewportBodyFace,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) {
        switch face {
        case .front:
            yMin += dragAmount(axis: .y, start: start, current: current, layout: layout)
        case .back:
            yMax += dragAmount(axis: .y, start: start, current: current, layout: layout)
        case .top:
            zMax += dragAmount(axis: .z, start: start, current: current, layout: layout)
        case .bottom:
            zMin += dragAmount(axis: .z, start: start, current: current, layout: layout)
        case .left:
            xMin += dragAmount(axis: .x, start: start, current: current, layout: layout)
        case .right, .side:
            xMax += dragAmount(axis: .x, start: start, current: current, layout: layout)
        }
    }

    private mutating func moveVertex(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) {
        let xAmount = dragAmount(axis: .x, start: start, current: current, layout: layout)
        let yAmount = dragAmount(axis: .y, start: start, current: current, layout: layout)
        let zAmount = dragAmount(axis: .z, start: start, current: current, layout: layout)
        if vertex.usesMinX {
            xMin += xAmount
        } else {
            xMax += xAmount
        }
        if vertex.usesMinY {
            yMin += yAmount
        } else {
            yMax += yAmount
        }
        if vertex.usesMinZ {
            zMin += zAmount
        } else {
            zMax += zAmount
        }
    }

    private func dragAmount(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let axisVector = projectedAxisVector(axis, layout: layout)
        let direction = axisVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        return (delta.dx * direction.dx + delta.dy * direction.dy) / max(axisVector.length, 1.0e-9)
    }

    private func rotationAmount(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let center = projectedPoint(centerPoint, layout: layout)
        let plane = rotationPlaneDirections(for: axis, layout: layout)
        let startAngle = rotationPlaneAngle(for: start, center: center, plane: plane)
        let currentAngle = rotationPlaneAngle(for: current, center: center, plane: plane)
        return normalizedRotationDelta(from: startAngle, to: currentAngle)
    }

    private func rotationPlaneDirections(
        for axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> (first: CGVector, second: CGVector) {
        switch axis {
        case .x:
            (projectedAxisDirection(.y, layout: layout), projectedAxisDirection(.z, layout: layout))
        case .y:
            (projectedAxisDirection(.z, layout: layout), projectedAxisDirection(.x, layout: layout))
        case .z:
            (projectedAxisDirection(.x, layout: layout), projectedAxisDirection(.y, layout: layout))
        }
    }

    private func rotationPlaneAngle(
        for point: CGPoint,
        center: CGPoint,
        plane: (first: CGVector, second: CGVector)
    ) -> CGFloat {
        let vector = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        let determinant = plane.first.dx * plane.second.dy - plane.first.dy * plane.second.dx
        guard abs(determinant) > 1.0e-6 else {
            return atan2(vector.dy, vector.dx)
        }
        let firstAmount = (vector.dx * plane.second.dy - vector.dy * plane.second.dx) / determinant
        let secondAmount = (plane.first.dx * vector.dy - plane.first.dy * vector.dx) / determinant
        return atan2(secondAmount, firstAmount)
    }

    private func normalizedRotationDelta(from startAngle: CGFloat, to currentAngle: CGFloat) -> CGFloat {
        var delta = startAngle - currentAngle
        while delta > .pi {
            delta -= .pi * 2.0
        }
        while delta < -.pi {
            delta += .pi * 2.0
        }
        return delta
    }

    private mutating func normalize() {
        if xMax - xMin < Self.minimumSize {
            xMax = xMin + Self.minimumSize
        }
        if yMax - yMin < Self.minimumSize {
            yMax = yMin + Self.minimumSize
        }
        if zMax - zMin < Self.minimumSize {
            zMax = zMin + Self.minimumSize
        }
    }
}

private enum TransformHandleStyle {
    case vertex
    case faceCenter
    case axisEndScale(ViewportCoordinateAxis)
    case axisCenterScale(ViewportCoordinateAxis)
}

private extension ViewportBodyFace {
    static var editableCases: [ViewportBodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var corners: [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
        ]
    }

    var handlePoints: [CGPoint] {
        corners + [
            CGPoint(x: midX, y: minY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: minX, y: midY),
            CGPoint(x: maxX, y: midY),
        ]
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1.0e-12 else {
            return distance(to: start)
        }

        let t = max(
            0.0,
            min(
                1.0,
                ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared
            )
        )
        let projection = CGPoint(
            x: start.x + t * dx,
            y: start.y + t * dy
        )
        return distance(to: projection)
    }
}

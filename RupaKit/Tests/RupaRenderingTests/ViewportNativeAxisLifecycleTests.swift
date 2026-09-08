import AppKit
import RupaCore
import RupaViewportScene
import SwiftUI
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
func viewportNativeRegionAxisCommitsAndCancels(projection: ViewportCameraProjection) async throws {
    _ = NSApplication.shared
    var document = DesignDocument.empty()
    let feature = try document.createRectangleSketch(
        name: "Axis input", plane: .xy,
        width: .length(20, .millimeter), height: .length(20, .millimeter)
    )
    let ruler = RulerConfiguration.standard(for: .millimeter)
    let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
    let item = try #require(scene.items.first { $0.featureID == feature })
    let region = try #require(item.sketchRegions.first)
    let target = SelectionTarget(sceneNodeID: try #require(item.sceneNodeID), component: .region(region.componentID))
    let selection = SelectionModel(selectedTargets: [target])
    let control = ViewportControlSession(camera: .init(projection: projection), basis: .axisFront(.z))
    let size = CGSize(width: 800, height: 600)
    var commits: [ViewportRegionOffsetDragTarget] = []
    var canvasDrags = 0
    let viewport = Viewport(
        document: document, sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        controlSession: control,
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: ruler),
        selection: selection, objectSelectionIndex: .init(document: document, selection: selection),
        allowsObjectAffordances: false, selectedPresentationHasExactCADContext: true,
        onCanvasDrag: { _ in canvasDrags += 1 }, onRegionOffsetDrag: { commits.append($0) }
    ).frame(width: size.width, height: size.height)
    let controller = NSHostingController(rootView: viewport)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.orderFront(nil)
    defer { window.contentViewController = nil; window.close() }

    // The layout only locates a deterministic pointer fixture. The production
    // callbacks below must hit the mounted native handle and query its camera.
    let layout = ViewportSceneContext(
        ruler: ruler, scene: scene, size: size, camera: control.camera, basis: .axisFront(.z),
        fittingInsets: ViewportCanvasChromeLayout(
            viewportSize: size, viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
        ).fittingInsets
    ).layout
    let local = try #require(region.points.first)
    let anchor = ViewportLayout.transformedPoint(
        Point3D(x: Double(local.x), y: 0, z: Double(local.y)), by: item.modelTransform
    )
    let minX = try #require(region.points.map(\.x).min())
    let maxX = try #require(region.points.map(\.x).max())
    let minY = try #require(region.points.map(\.y).min())
    let maxY = try #require(region.points.map(\.y).max())
    let center = ViewportLayout.transformedPoint(
        Point3D(x: Double((minX + maxX) / 2), y: 0, z: Double((minY + maxY) / 2)), by: item.modelTransform
    )
    let dx = anchor.x - center.x, dy = anchor.y - center.y, dz = anchor.z - center.z
    let length = (dx * dx + dy * dy + dz * dz).squareRoot()
    let endWorld = Point3D(x: anchor.x + dx / length * ruler.minorTickMeters,
                          y: anchor.y + dy / length * ruler.minorTickMeters,
                          z: anchor.z + dz / length * ruler.minorTickMeters)
    let projectedAnchor = try #require(layout.projectedPoint(anchor)?.point)
    let projectedEnd = try #require(layout.projectedPoint(endWorld)?.point)
    let screenLength = hypot(projectedEnd.x - projectedAnchor.x, projectedEnd.y - projectedAnchor.y)
    let unit = CGVector(dx: (projectedEnd.x - projectedAnchor.x) / screenLength,
                        dy: (projectedEnd.y - projectedAnchor.y) / screenLength)
    let start = CGPoint(x: projectedEnd.x + unit.dx * 64, y: projectedEnd.y + unit.dy * 64)
    let end = CGPoint(x: start.x + unit.dx * 24, y: start.y + unit.dy * 24)
    func input(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews { if let value = input(in: child) { return value } }
        return nil
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while commits.isEmpty, ContinuousClock.now < deadline {
        if let input = input(in: controller.view) {
            input.onPress?(start, size, .replace)
            try await Task.sleep(for: .milliseconds(500))
            input.onCanvasDrag?(start, end, size, .replace)
        }
        try await Task.sleep(for: .milliseconds(30))
    }
    let commit = try #require(commits.first,
        "Native axis did not commit: start=\(start), end=\(end), anchor=\(anchor), canvasDrags=\(canvasDrags)")
    #expect(commit.target == target)
    #expect(commit.distance > 0)
    #expect(canvasDrags == 0)
    let nativeInput = try #require(input(in: controller.view))
    try await Task.sleep(for: .milliseconds(800))
    nativeInput.onPress?(start, size, .replace)
    try await Task.sleep(for: .milliseconds(800))
    nativeInput.onDragPreview?(start, end, size)
    nativeInput.onCanvasDrag?(start, end, size, .replace)
    nativeInput.onDragPreview?(nil, nil, size)
    #expect(commits.count == 1)
    let finishDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while commits.count == 1, ContinuousClock.now < finishDeadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(commits.count == 2)
    #expect(abs(try #require(commits.last).distance - commit.distance) < 1e-9)
    try await Task.sleep(for: .milliseconds(800))
    func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: nativeInput.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }
    let count = commits.count
    nativeInput.mouseDown(with: try event(.leftMouseDown, at: start))
    nativeInput.cancelOperation(nil)
    nativeInput.mouseUp(with: try event(.leftMouseUp, at: end))
    #expect(commits.count == count)
    for cancelByCamera in [false, true] {
        try await Task.sleep(for: .milliseconds(800))
        nativeInput.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(800))
        nativeInput.onDragPreview?(start, end, size)
        nativeInput.onCanvasDrag?(start, end, size, .replace)
        nativeInput.onDragPreview?(nil, nil, size)
        #expect(commits.count == count)
        if cancelByCamera {
            _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
        } else {
            nativeInput.cancelOperation(nil)
        }
        try await Task.sleep(for: .milliseconds(800))
        #expect(commits.count == count)
    }
    _ = try control.perform(.pan(deltaXPoints: 17, deltaYPoints: 9))
    nativeInput.onPress?(start, size, .replace)
    nativeInput.onCanvasDrag?(start, end, size, .replace)
    #expect(commits.count == count)
    #expect(canvasDrags == 0)
}

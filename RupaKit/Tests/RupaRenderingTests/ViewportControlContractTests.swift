import CoreGraphics
import Foundation
import RupaCore
import RupaGeometry
import Testing
@testable import RupaRendering

@MainActor
@Test
func viewportWaitsForPositiveSizeBeforeResolvingItsCamera() throws {
    let control = ViewportControlSession()
    let mount = ViewportInstanceID()
    _ = control.mount(viewportID: mount)
    let valid = try viewportContractContext(mount: mount)
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20)
    for size in [CGSize.zero, CGSize(width: 900, height: 0)] {
        control.updateContext(.init(viewportID: mount, viewportSize: size,
            fittingInsets: .zero, modelBounds: valid.modelBounds,
            verticalBounds: valid.verticalBounds, ruler: valid.ruler,
            sceneBounds: valid.sceneBounds, selectedBounds: nil))
        #expect(control.camera.referenceScale == nil)
        #expect(throws: ViewportControlError.viewportContextUnavailable) { try control.snapshot() }
        let layout = ViewportLayout(modelBounds: valid.modelBounds, size: size)
        #expect(resolver.frame(for: .identity, in: layout) == nil)
    }
    control.updateContext(valid)
    #expect(control.camera.referenceScale != nil)
    let layout = ViewportLayout(modelBounds: valid.modelBounds, size: valid.viewportSize,
        camera: control.camera, basis: control.basis, verticalBounds: valid.verticalBounds)
    #expect(resolver.frame(for: control.camera, in: layout) != nil)
    _ = try control.snapshot()
}

@MainActor
@Test
func viewportSelectionChromeDoesNotMoveTheCamera() throws {
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        let control = ViewportControlSession(camera: .init(projection: projection))
        let id = ViewportInstanceID()
        _ = control.mount(viewportID: id)
        let base = try viewportContractContext(mount: id)
        func context(height: CGFloat) -> ViewportControlMountContext {
            let chrome = ViewportCanvasChromeLayout(viewportSize: base.viewportSize, bottomReservedHeight: height)
            return .init(viewportID: id, viewportSize: base.viewportSize,
                fittingInsets: chrome.fittingInsets, modelBounds: base.modelBounds,
                verticalBounds: base.verticalBounds, ruler: base.ruler,
                sceneBounds: base.sceneBounds, selectedBounds: height > 0 ? base.sceneBounds : nil)
        }
        func layout(_ context: ViewportControlMountContext) -> ViewportLayout {
            .init(modelBounds: context.modelBounds, size: context.viewportSize,
                camera: control.camera, basis: control.basis,
                maximumZoom: context.maximumZoom(for: control.basis, camera: control.camera),
                verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets)
        }
        control.updateContext(context(height: 0))
        let camera = control.camera
        let before = layout(context(height: 0))
        let points: [Point3D] = [.origin, .init(x: 0.2, y: 0.3, z: -0.4)]
        for height: CGFloat in [48, 96, 0] {
            let next = context(height: height)
            control.updateContext(next)
            let after = layout(next)
            #expect(control.camera == camera)
            #expect(after.scale == before.scale)
            #expect(after.visibleHeightMeters == before.visibleHeightMeters)
            for point in points {
                let a = before.project(point), b = after.project(point)
                #expect(hypot(a.x - b.x, a.y - b.y) < 1e-7)
            }
        }
        let selected = context(height: 96)
        control.updateContext(selected)
        _ = try control.perform(.fitSelected)
        let fitted = layout(selected)
        let safe = selected.fittingInsets.fittingRect(in: selected.viewportSize).insetBy(dx: -1e-4, dy: -1e-4)
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            #expect(safe.contains(fitted.project(.init(x: x, y: y, z: z))))
        } } }
    }
}

@MainActor
@Test
func viewportModelChangesPreserveCameraProjectionAndExplicitFitStillWorks() throws {
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        let control = ViewportControlSession(camera: .init(projection: projection))
        let mount = ViewportInstanceID()
        _ = control.mount(viewportID: mount)
        let initial = try viewportContractContext(mount: mount)
        control.updateContext(initial)
        let camera = control.camera
        func layout(_ context: ViewportControlMountContext) -> ViewportLayout {
            ViewportLayout(modelBounds: context.modelBounds, size: context.viewportSize,
                camera: control.camera, basis: control.basis,
                maximumZoom: context.maximumZoom(for: control.basis, camera: control.camera),
                verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets)
        }
        let original = layout(initial)
        let points: [Point3D] = [.origin, .init(x: 0.1, y: 0.2, z: -0.3)]
        for bounds in [CGRect(x: 90, y: 90, width: 20, height: 30),
                       CGRect(x: -2, y: -1, width: 0.5, height: 0.7), initial.modelBounds] {
            let context = ViewportControlMountContext(viewportID: mount,
                viewportSize: initial.viewportSize, fittingInsets: initial.fittingInsets,
                modelBounds: bounds, verticalBounds: -50...100, ruler: initial.ruler,
                sceneBounds: nil, selectedBounds: nil)
            control.updateContext(context)
            #expect(control.camera == camera)
            #expect(layout(context).scale == original.scale)
            for point in points {
                let before = original.project(point), after = layout(context).project(point)
                #expect(hypot(before.x - after.x, before.y - after.y) < 1e-7)
            }
        }
        control.updateContext(initial)
        _ = try control.perform(.fitVisible)
        #expect(control.camera != camera)
        let fitted = layout(initial)
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            #expect(initial.fittingInsets.fittingRect(in: initial.viewportSize)
                .insetBy(dx: -1e-6, dy: -1e-6).contains(fitted.project(.init(x: x, y: y, z: z))))
        } } }
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            let saved = try control.snapshot()
            #expect(throws: ViewportControlError.self) {
                try control.applyPresentationState(camera: .init(referenceScale: invalid), basis: control.basis)
            }
            #expect(try control.snapshot() == saved)
        }
    }
}

@Test
func viewportFitContainsOffsetBoundsInsideTheActualChromeInsets() throws {
    for basis in [ViewportProjectionBasis.isometric, .axisFront(.z), .orbit(yaw: -0.4, elevation: 0.7)] {
        let bounds = try GeometryBounds3D(
            minimum: .init(x: 7, y: -3, z: 11), maximum: .init(x: 19, y: 2, z: 15)
        )
        let size = CGSize(width: 1100, height: 600)
        let insets = ViewportLayout.FittingInsets(top: 40, leading: 70, bottom: 85, trailing: 24)
        let model = CGRect(x: 4, y: 8, width: 24, height: 18)
        let camera = try ViewportControlBoundsSolver.camera(
            for: bounds, sceneModelBounds: model, verticalBounds: -3...2,
            basis: basis, size: size, fittingInsets: insets, maximumZoom: 256
        )
        let layout = ViewportLayout(
            modelBounds: model, size: size, camera: camera, basis: basis,
            maximumZoom: 256, verticalBounds: -3...2, fittingInsets: insets
        )
        let fitting = insets.fittingRect(in: size).insetBy(dx: -1e-7, dy: -1e-7)
        for index in 0..<8 {
            let point = Point3D(
                x: index & 1 == 0 ? 7 : 19,
                y: index & 2 == 0 ? -3 : 2,
                z: index & 4 == 0 ? 11 : 15
            )
            #expect(fitting.contains(layout.project(point)))
        }
        let center = layout.project(Point3D(x: 13, y: -0.5, z: 13))
        #expect(abs(center.x - layout.fittingCenter.x) < 1e-7)
        #expect(abs(center.y - layout.fittingCenter.y) < 1e-7)
    }
}

@MainActor
@Test
func viewportControlRejectsInvalidOperationsAtomicallyAndTracksContextChanges() throws {
    let control = ViewportControlSession()
    let mount = ViewportInstanceID()
    #expect(throws: ViewportControlError.viewportNotMounted) { try control.perform(.fitVisible) }
    let initialMount = control.mount(viewportID: mount)
    #expect(throws: ViewportControlError.viewportContextUnavailable) { try control.snapshot() }
    let context = try viewportContractContext(mount: mount)
    control.updateContext(context)
    let original = try control.snapshot()
    control.updateContext(context)
    #expect(try control.snapshot() == original)

    for invalid in [
        ViewportControlAction.zoom(factor: 0),
        .pan(deltaXPoints: .greatestFiniteMagnitude, deltaYPoints: 0),
        .orbit(yawDeltaDegrees: .greatestFiniteMagnitude, elevationDeltaDegrees: 0),
        .pan(deltaXPoints: .nan, deltaYPoints: 0),
        .fitSelected,
    ] {
        #expect(throws: ViewportControlError.self) { try control.perform(invalid) }
        #expect(try control.snapshot() == original)
    }

    var resized = context
    resized = ViewportControlMountContext(
        viewportID: mount, viewportSize: CGSize(width: 1000, height: 700),
        fittingInsets: resized.fittingInsets, modelBounds: resized.modelBounds,
        verticalBounds: resized.verticalBounds, ruler: resized.ruler,
        sceneBounds: resized.sceneBounds, selectedBounds: resized.selectedBounds
    )
    control.updateContext(resized)
    #expect(control.revision > original.revision)
    #expect(throws: ViewportControlError.self) {
        try control.perform(.fitVisible, expectedRevision: original.revision)
    }
    let fitted = try control.perform(.fitVisible)
    #expect(fitted.camera.zoom > original.camera.zoom)
    #expect(fitted.displayMode == original.displayMode)

    let replacementMount = ViewportInstanceID()
    let replacementMountToken = control.mount(viewportID: replacementMount)
    control.updateContext(try viewportContractContext(mount: replacementMount))
    control.unmount(initialMount)
    control.updateContext(context)
    #expect(control.isReady)
    control.unmount(replacementMountToken)
    #expect(!control.isReady)
    #expect(throws: ViewportControlError.viewportNotMounted) { try control.snapshot() }
}

@MainActor
@Test
func viewportControlIgnoresStaleUnmountAfterSameIdentityRemount() throws {
    let control = ViewportControlSession()
    let viewportID = ViewportInstanceID()
    let context = try viewportContractContext(mount: viewportID)

    let firstMount = control.mount(viewportID: viewportID)
    control.updateContext(context)
    let firstSnapshot = try control.snapshot()

    let replacementMount = control.mount(viewportID: viewportID)
    control.updateContext(context)
    let replacementSnapshot = try control.snapshot()

    #expect(firstMount != replacementMount)
    #expect(replacementSnapshot.revision > firstSnapshot.revision)
    control.unmount(firstMount)
    #expect(control.isReady)
    #expect(try control.snapshot() == replacementSnapshot)

    control.unmount(replacementMount)
    #expect(!control.isReady)
    #expect(throws: ViewportControlError.viewportNotMounted) { try control.snapshot() }
}

@MainActor
@Test
func viewportControlUsesOneCameraForPresentationChangesAndCommands() throws {
    let control = ViewportControlSession()
    let mount = ViewportInstanceID()
    _ = control.mount(viewportID: mount)
    control.updateContext(try viewportContractContext(mount: mount))
    try control.applyPresentationState(
        camera: .init(zoom: 2, pan: CGSize(width: 30, height: -20)), basis: .axisFront(.z)
    )
    let revision = control.revision
    let appliedFocus = control.camera.focus
    let zoomed = try control.perform(.zoom(factor: 2), expectedRevision: revision)
    #expect(zoomed.camera.zoom == 4)
    #expect(zoomed.camera.pan == .zero)
    #expect(zoomed.camera.focus == appliedFocus)
    #expect(control.selectedAxis == .z)
    let mode = try control.perform(.setDisplayMode(.normals))
    #expect(mode.camera == zoomed.camera)
    let reset = try control.perform(.resetCamera)
    #expect(reset.camera == ViewportCamera(focus: .origin, referenceScale: control.camera.referenceScale))
    #expect(reset.camera.referenceScale != nil)
    #expect(reset.basis == .axisFront(.z))
    #expect(reset.displayMode == .normals)

    let context = try viewportContractContext(mount: mount)
    _ = try control.perform(.zoom(factor: 1e6))
    let turned = try control.perform(.setOrientation(.isometric))
    let layout = ViewportLayout(
        modelBounds: context.modelBounds, size: context.viewportSize,
        camera: turned.camera, basis: turned.basis,
        maximumZoom: context.maximumZoom(for: turned.basis, camera: turned.camera),
        verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets
    )
    #expect(turned.camera.zoom <= layout.maximumZoom)
    #expect(abs(layout.scale / (try #require(turned.camera.referenceScale)) - turned.camera.zoom) < 1e-7)
}

@MainActor
@Test
func viewportProjectionControlsPreserveIndependentStateAndRejectInvalidLenses() throws {
    let control = ViewportControlSession()
    let mount = ViewportInstanceID()
    _ = control.mount(viewportID: mount)
    control.updateContext(try viewportContractContext(mount: mount))
    try control.applyPresentationState(
        camera: .init(zoom: 2, pan: CGSize(width: 30, height: -20)), basis: .isometric
    )
    let before = try control.snapshot()
    let lens = ViewportCameraProjection.perspective(fieldOfViewRadians: 0.9)
    let perspective = try control.perform(.setProjection(lens))
    #expect(perspective.camera.projection == lens)
    #expect(perspective.camera.zoom == before.camera.zoom)
    #expect(perspective.camera.pan == before.camera.pan)
    #expect(perspective.basis == before.basis)
    #expect(perspective.displayMode == before.displayMode)
    for invalid in [Double.nan, .infinity, 0, -.pi, .pi] {
        #expect(throws: ViewportControlError.invalidProjection) {
            try control.perform(.setProjection(.perspective(fieldOfViewRadians: invalid)))
        }
        #expect(try control.snapshot() == perspective)
    }
    let oriented = try control.perform(.setOrientation(.zFront))
    #expect(oriented.camera.projection == lens)
    let reset = try control.perform(.resetCamera)
    #expect(reset.camera.projection == lens)
    #expect(reset.camera.zoom == 1)
    #expect(reset.camera.pan == .zero)
    #expect(reset.basis == oriented.basis)
    let parallel = try control.perform(.setProjection(.parallel))
    #expect(parallel.camera.projection == .parallel)
    #expect(parallel.basis == reset.basis)
}

@MainActor
private func viewportContractContext(mount: ViewportInstanceID) throws -> ViewportControlMountContext {
    ViewportControlMountContext(
        viewportID: mount, viewportSize: CGSize(width: 900, height: 700),
        fittingInsets: .zero, modelBounds: CGRect(x: -10, y: -10, width: 20, height: 20),
        verticalBounds: -1...1, ruler: .standard(for: .millimeter),
        sceneBounds: try GeometryBounds3D(
            minimum: .init(x: -1, y: -1, z: -1), maximum: .init(x: 1, y: 1, z: 1)
        ), selectedBounds: nil
    )
}

@MainActor
@Test
func viewportOrbitKeepsFittedAndPannedFocusCenteredInBothLenses() throws {
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        let control = ViewportControlSession(camera: .init(projection: projection))
        let mount = ViewportInstanceID()
        _ = control.mount(viewportID: mount)
        let context = ViewportControlMountContext(
            viewportID: mount, viewportSize: CGSize(width: 900, height: 700),
            fittingInsets: .init(top: 25, leading: 70, bottom: 60, trailing: 20),
            modelBounds: CGRect(x: -10, y: -10, width: 20, height: 20),
            verticalBounds: -10...10, ruler: .standard(for: .millimeter),
            sceneBounds: try GeometryBounds3D(minimum: .init(x: -9, y: -9, z: -9), maximum: .init(x: 9, y: 9, z: 9)),
            selectedBounds: try GeometryBounds3D(minimum: .init(x: 4, y: 2, z: -3), maximum: .init(x: 6, y: 4, z: -1))
        )
        control.updateContext(context)
        func layout(_ state: ViewportControlSnapshot) -> ViewportLayout {
            ViewportLayout(modelBounds: context.modelBounds, size: context.viewportSize,
                camera: state.camera, basis: state.basis,
                maximumZoom: context.maximumZoom(for: state.basis),
                verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets)
        }
        let fitted = try control.perform(.fitSelected)
        let target = try #require(fitted.camera.focus)
        let fittedLayout = layout(fitted)
        let fittedObjectCenter = fittedLayout.project(Point3D(x: 5, y: 3, z: -2))
        #expect(hypot(fittedObjectCenter.x - fittedLayout.fittingCenter.x,
            fittedObjectCenter.y - fittedLayout.fittingCenter.y) < 1e-7)
        let turned = try control.perform(.orbit(yawDeltaDegrees: 90, elevationDeltaDegrees: 10))
        let turnedLayout = layout(turned)
        #expect(turned.camera.focus == target)
        #expect(abs(fittedLayout.visibleHeightMeters - turnedLayout.visibleHeightMeters) < 1e-8)
        #expect(hypot(turnedLayout.project(target).x - turnedLayout.viewportCenter.x,
            turnedLayout.project(target).y - turnedLayout.viewportCenter.y) < 1e-7)

        let panned = try control.perform(.pan(deltaXPoints: 80, deltaYPoints: -35))
        let pannedLayout = layout(panned)
        let focus = try #require(panned.camera.focus)
        #expect(focus != target)
        #expect(panned.camera.pan == .zero)
        let oldTarget = pannedLayout.project(target)
        #expect(abs(oldTarget.x - pannedLayout.viewportCenter.x - 80) < 1e-7)
        #expect(abs(oldTarget.y - pannedLayout.viewportCenter.y + 35) < 1e-7)
        let orbited = try control.perform(.orbit(yawDeltaDegrees: -55, elevationDeltaDegrees: -8))
        let orbitedLayout = layout(orbited)
        #expect(orbited.camera.focus == focus)
        #expect(abs(pannedLayout.visibleHeightMeters - orbitedLayout.visibleHeightMeters) < 1e-8)
        #expect(hypot(orbitedLayout.project(focus).x - orbitedLayout.viewportCenter.x,
            orbitedLayout.project(focus).y - orbitedLayout.viewportCenter.y) < 1e-7)
        let original = try control.snapshot()
        let anchor = CGPoint(x: 250, y: 190)
        let anchoredWorld = try #require(orbitedLayout.worldPointOnFocusPlane(for: anchor))
        let zoomed = try control.perform(.zoom(factor: 1.4, anchor: anchor))
        let projectedAnchor = layout(zoomed).project(anchoredWorld)
        #expect(hypot(projectedAnchor.x - anchor.x, projectedAnchor.y - anchor.y) < 1e-7)
        try control.applyPresentationState(camera: original.camera, basis: original.basis)
        let restored = try control.snapshot()
        #expect(throws: ViewportControlError.self) {
            try control.applyPresentationState(camera: .init(focus: .init(x: .nan, y: 0, z: 0)), basis: original.basis)
        }
        #expect(try control.snapshot() == restored)
        control.updateContext(ViewportControlMountContext(
            viewportID: mount, viewportSize: context.viewportSize, fittingInsets: context.fittingInsets,
            modelBounds: CGRect(x: 90, y: 90, width: 20, height: 20), verticalBounds: 90...110,
            ruler: context.ruler, sceneBounds: context.sceneBounds, selectedBounds: context.selectedBounds))
        #expect(control.camera.focus == focus)
    }
}

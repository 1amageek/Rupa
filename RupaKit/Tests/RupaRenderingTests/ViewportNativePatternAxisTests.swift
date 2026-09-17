import AppKit
import CoreGraphics
import RupaCore
import SwiftCAD
import RupaViewportScene
import SwiftUI
import Testing
@testable import RupaRendering

/// The mounted test drives a shared `NSApplication` and an ordered window,
/// so the suite is serialized rather than sharing that state across cases.
@Suite(.serialized)
@MainActor
struct ViewportNativePatternAxisTests {
    @Test
    func nativePatternAxisInputMapsWorldRoutesAndRetainsPatternIdentity() throws {
        let sourceID = PatternArraySourceID()
        let outputSceneNodeID = SceneNodeID()
        let featureID = FeatureID()
        let linearSource = ViewportPatternAffordanceSource.LinearAxisHandle(
            sourceID: sourceID,
            axisSlot: .first,
            title: "Linear",
            basePoint: .origin,
            direction: .unitX,
            distanceMeters: 0.05,
            displayDistanceMeters: nil,
            distanceMode: .spacing,
            state: .normal
        )
        let extrudeSource = ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle(
            sourceID: sourceID,
            outputIndex: 3,
            outputSceneNodeID: outputSceneNodeID,
            featureID: featureID,
            title: "Extrude",
            basePoint: .origin,
            axis: .init(x: 2.0, y: 0.0, z: 0.0),
            distanceMeters: 0.10,
            displayDistanceMeters: nil,
            state: .normal
        )
        let dimensionSource = ViewportPatternAffordanceSource.IndependentCopyDimensionHandle(
            sourceID: sourceID,
            outputIndex: 4,
            outputSceneNodeID: outputSceneNodeID,
            featureID: featureID,
            kind: .sizeX,
            label: "Dimension",
            basePoint: .origin,
            axis: .init(x: 3.0, y: 0.0, z: 0.0),
            valueMeters: 0.20,
            displayValueMeters: nil,
            state: .normal
        )

        let linear = try #require(try ViewportNativeAxisInput(record: .init(
            target: .patternArrayLinearAxis(linearSource)
        )))
        let extrude = try #require(try ViewportNativeAxisInput(record: .init(
            target: .independentCopyExtrudeDistance(extrudeSource)
        )))
        let dimension = try #require(try ViewportNativeAxisInput(record: .init(
            target: .independentCopyBodyDimension(dimensionSource)
        )))
        let minimum = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
        let linearValue = try linear.value(forWorldDelta: 0.02)
        let extrudeValue = try extrude.value(forWorldDelta: 0.02)
        let dimensionValue = try dimension.value(forWorldDelta: 0.03)

        #expect(abs(linearValue - max(0.07, minimum)) < 1.0e-12)
        #expect(abs(extrudeValue - 0.12) < 1.0e-12)
        #expect(abs(dimensionValue - 0.23) < 1.0e-12)

        guard case .patternArrayLinearAxis(let linearCommit) = try linear.commit(value: linearValue) else {
            Issue.record("The Pattern linear-axis callback payload was not produced.")
            return
        }
        #expect(linearCommit.sourceID == sourceID)
        #expect(linearCommit.axisSlot == .first)
        #expect(abs(linearCommit.distance - max(0.07, minimum)) < 1.0e-12)

        guard case .independentCopyExtrudeDistance(let extrudeCommit) = try extrude.commit(value: extrudeValue) else {
            Issue.record("The independent-copy extrude callback payload was not produced.")
            return
        }
        #expect(extrudeCommit.sourceID == sourceID)
        #expect(extrudeCommit.outputIndex == 3)
        #expect(extrudeCommit.outputSceneNodeID == outputSceneNodeID)
        #expect(extrudeCommit.featureID == featureID)
        #expect(abs(extrudeCommit.distance - 0.06) < 1.0e-12)

        guard case .independentCopyBodyDimension(let dimensionCommit) = try dimension.commit(value: dimensionValue) else {
            Issue.record("The independent-copy dimension callback payload was not produced.")
            return
        }
        #expect(dimensionCommit.sourceID == sourceID)
        #expect(dimensionCommit.outputIndex == 4)
        #expect(dimensionCommit.outputSceneNodeID == outputSceneNodeID)
        #expect(dimensionCommit.featureID == featureID)
        #expect(dimensionCommit.kind == .sizeX)
        #expect(abs(dimensionCommit.value - (0.23 / 3.0)) < 1.0e-12)

        #expect(try linear.commit(value: try linear.value(forWorldDelta: 0.0)) == nil)
        #expect(try extrude.commit(value: try extrude.value(forWorldDelta: 0.0)) == nil)
        #expect(try dimension.commit(value: try dimension.value(forWorldDelta: 0.0)) == nil)
        #expect(abs(try linear.value(forWorldDelta: -1.0) - minimum) < 1.0e-12)
    }

    @Test
    func nativePatternAxisInputIgnoresRecordTransformForWorldPreparedAxes() throws {
        let source = ViewportPatternAffordanceSource.LinearAxisHandle(
            sourceID: PatternArraySourceID(),
            axisSlot: .second,
            title: "World axis",
            basePoint: Point3D(x: 10.0, y: -4.0, z: 2.0),
            direction: .unitX,
            distanceMeters: 0.10,
            displayDistanceMeters: nil,
            distanceMode: .spacing,
            state: .normal
        )
        let transformed = try Transform3D(matrix: Matrix4x4(values: [
            8.0, 0.0, 0.0, 12.0,
            0.0, 8.0, 0.0, -7.0,
            0.0, 0.0, 8.0, 3.0,
            0.0, 0.0, 0.0, 1.0,
        ]))
        let record = try ViewportSpatialInteractionRecord(
            target: .patternArrayLinearAxis(source),
            modelTransform: transformed
        )
        let input = try #require(try ViewportNativeAxisInput(record: record))
        #expect(abs(try input.value(forWorldDelta: 0.02) - 0.12) < 1.0e-12)
    }

    @Test
    func nativePatternAxisInputRejectsDegenerateAndOverflowingRoutes() throws {
        let zeroLinear = ViewportPatternAffordanceSource.LinearAxisHandle(
            sourceID: PatternArraySourceID(), axisSlot: .first, title: "Zero",
            basePoint: .origin, direction: .zero, distanceMeters: 0.1,
            displayDistanceMeters: nil, distanceMode: .spacing, state: .normal
        )
        let zeroExtrude = ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle(
            sourceID: PatternArraySourceID(), outputIndex: 0, outputSceneNodeID: .init(),
            featureID: .init(), title: "Zero", basePoint: .origin,
            axis: .zero, distanceMeters: 0.1, displayDistanceMeters: nil, state: .normal
        )
        let zeroDimension = ViewportPatternAffordanceSource.IndependentCopyDimensionHandle(
            sourceID: PatternArraySourceID(), outputIndex: 0, outputSceneNodeID: .init(),
            featureID: .init(), kind: .radius, label: "Zero", basePoint: .origin,
            axis: .zero, valueMeters: 0.1, displayValueMeters: nil, state: .normal
        )
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try ViewportNativeAxisInput(record: .init(target: .patternArrayLinearAxis(zeroLinear)))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try ViewportNativeAxisInput(record: .init(target: .independentCopyExtrudeDistance(zeroExtrude)))
        }
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try ViewportNativeAxisInput(record: .init(target: .independentCopyBodyDimension(zeroDimension)))
        }

        let smallAxis = ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle(
            sourceID: PatternArraySourceID(), outputIndex: 0, outputSceneNodeID: .init(),
            featureID: .init(), title: "Overflow", basePoint: .origin,
            axis: .init(x: 0.5, y: 0.0, z: 0.0), distanceMeters: 0.1,
            displayDistanceMeters: nil, state: .normal
        )
        let input = try #require(try ViewportNativeAxisInput(record: .init(
            target: .independentCopyExtrudeDistance(smallAxis)
        )))
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try input.commit(value: .greatestFiniteMagnitude)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
    func viewportNativePatternLinearAxisCommitsOnceAndCancels(projection: ViewportCameraProjection) async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let bodySceneNodeID = try #require(session.document.productMetadata.sceneNodes.first {
            $0.value.reference?.featureID == bodyFeatureID
        }?.key)
        _ = try session.execute(.createComponentDefinition(
            name: "Native Pattern Source", rootSceneNodeIDs: [bodySceneNodeID]
        ))
        let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
            $0.name == "Native Pattern Source"
        })
        _ = try session.execute(.createPatternArray(
            name: "Native Pattern", definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX, distance: .length(0.1, .meter), copyCount: 2
                )
            )), outputMode: .componentInstance
        ))
        let source = try #require(session.document.productMetadata.patternArrays.values.first {
            $0.name == "Native Pattern"
        })
        let document = session.document
        let ruler = session.workspaceState.ruler
        let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
        let selection = SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID)
        ])
        let size = CGSize(width: 900.0, height: 700.0)
        let control = ViewportControlSession(
            camera: .init(projection: projection), basis: .axisFront(.z)
        )
        let layout = ViewportSceneContext(
            ruler: ruler, scene: scene, size: size, camera: control.camera, basis: .axisFront(.z),
            fittingInsets: ViewportCanvasChromeLayout(
                viewportSize: size, viewportBadgeWidth: ViewportCanvasChromeLayout.maximumViewportBadgeWidth
            ).fittingInsets
        ).layout
        let patternInput = ViewportPatternAffordanceSource.RawInput(
            document: document,
            scene: scene,
            selection: selection,
            ruler: ruler,
            hasRoute: true,
            linearAxisRouteEnabled: true
        )
        let patternSource = try #require(try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
            from: patternInput,
            checkpoint: { _, _, _ in }
        ))
        let axisHandle = try #require(patternSource.linearAxisHandles.first)
        let projectedAnchor = try #require(layout.projectedPoint(axisHandle.basePoint)?.point)
        let directionLength = axisHandle.direction.length
        let tipWorld = Point3D(
            x: axisHandle.basePoint.x + axisHandle.direction.x / directionLength * axisHandle.distanceMeters,
            y: axisHandle.basePoint.y + axisHandle.direction.y / directionLength * axisHandle.distanceMeters,
            z: axisHandle.basePoint.z + axisHandle.direction.z / directionLength * axisHandle.distanceMeters
        )
        let projectedTip = try #require(layout.projectedPoint(tipWorld)?.point)
        let projectedLength = hypot(
            projectedTip.x - projectedAnchor.x, projectedTip.y - projectedAnchor.y
        )
        let screenLength = max(projectedLength, 76.0)
        let screenDirectionLength = max(projectedLength, 1.0e-12)
        let screenDirection = CGVector(
            dx: (projectedTip.x - projectedAnchor.x) / screenDirectionLength,
            dy: (projectedTip.y - projectedAnchor.y) / screenDirectionLength
        )
        let start = CGPoint(
            x: projectedAnchor.x + screenDirection.dx * screenLength * 0.5,
            y: projectedAnchor.y + screenDirection.dy * screenLength * 0.5
        )
        let end = CGPoint(
            x: start.x + screenDirection.dx * 24.0,
            y: start.y + screenDirection.dy * 24.0
        )
        var commits: [ViewportPatternArrayLinearAxisDragTarget] = []
        var canvasDrags = 0
        let viewport = Viewport(
            document: document,
            sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
            controlSession: control,
            workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: ruler),
            selection: selection,
            objectSelectionIndex: .init(document: document, selection: selection),
            allowsObjectAffordances: false,
            selectedPresentationHasExactCADContext: true,
            onCanvasDrag: { _ in canvasDrags += 1 },
            onPatternArrayLinearAxisDrag: { commits.append($0) }
        ).frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: viewport)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.view.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !window.isKeyWindow)
        defer { window.contentViewController = nil; window.close() }

        func input(in view: NSView) -> ViewportInputSurface.InputView? {
            if let value = view as? ViewportInputSurface.InputView { return value }
            for child in view.subviews {
                if let value = input(in: child) { return value }
            }
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
        let first = try #require(commits.first,
            "Native Pattern axis did not commit: start=\(start), end=\(end), canvasDrags=\(canvasDrags)")
        #expect(first.sourceID == source.id)
        #expect(first.axisSlot == .first)
        #expect(first.distance > 0.0)
        #expect(canvasDrags == 0)

        // The first phase polls until the view has mounted a frame at all. The
        // sub-phases below are single gestures, because a real drag is never
        // retried: each adds exactly one call to the sequence, so a red run names
        // the call that dropped the press instead of only reporting no commit.
        let nativeInput = try #require(input(in: controller.view))

        func awaitCommit(after count: Int) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while commits.count == count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        // A second gesture issued with no gap after the first commit. Committing
        // released the gesture, which dropped the axis value from the overlay
        // change key and started an overlay-only rebuild, so this press names an
        // identity whose own frame is not prepared yet. The frame it addressed is
        // still the mounted one, so the press must reach the native route.
        let countBeforeRepeat = commits.count
        nativeInput.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        nativeInput.onCanvasDrag?(start, end, size, .replace)
        try await awaitCommit(after: countBeforeRepeat)
        #expect(
            commits.count == countBeforeRepeat + 1,
            "A second native axis gesture issued with no gap did not commit."
        )

        // A mid-drag preview before the release, in the same turn. This is the
        // sequence a real drag produces, and the input owner must not require
        // the caller to press again for it to commit.
        let countBeforeSelfPreview = commits.count
        nativeInput.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        nativeInput.onDragPreview?(start, end, size)
        nativeInput.onCanvasDrag?(start, end, size, .replace)
        try await awaitCommit(after: countBeforeSelfPreview)
        #expect(
            commits.count == countBeforeSelfPreview + 1,
            "A press, mid-drag preview and release did not commit."
        )

        // The same sequence with the preview allowed to settle before the
        // release, so the release finds its own frame already mounted and
        // commits without deferral.
        let countBeforeSettledPreview = commits.count
        nativeInput.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        nativeInput.onDragPreview?(start, end, size)
        try await Task.sleep(for: .milliseconds(500))
        nativeInput.onCanvasDrag?(start, end, size, .replace)
        try await awaitCommit(after: countBeforeSettledPreview)
        #expect(
            commits.count == countBeforeSettledPreview + 1,
            "A press, settled mid-drag preview and release did not commit."
        )

        // The mouse-up preview clear that follows every release, with no
        // mid-drag preview. The press resolves against the frame it addressed,
        // so the clear must not end a commit that frame already authorized.
        let countBeforeClearedPreview = commits.count
        nativeInput.onPress?(start, size, .replace)
        try await Task.sleep(for: .milliseconds(500))
        nativeInput.onCanvasDrag?(start, end, size, .replace)
        nativeInput.onDragPreview?(nil, nil, size)
        try await awaitCommit(after: countBeforeClearedPreview)
        #expect(
            commits.count == countBeforeClearedPreview + 1,
            "A press, release and mouse-up preview clear did not commit."
        )

        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: nativeInput.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        let countBeforeCancel = commits.count
        nativeInput.mouseDown(with: try event(.leftMouseDown, at: start))
        nativeInput.cancelOperation(nil)
        nativeInput.mouseUp(with: try event(.leftMouseUp, at: end))
        #expect(commits.count == countBeforeCancel)
        #expect(canvasDrags == 0)
    }
}

import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI
import Testing
@testable import RupaRendering

private struct MissingFixtureProjection: Error {}

/// The mounted test drives a shared `NSApplication` and an ordered window,
/// so the suite is serialized rather than sharing that state across cases.
@Suite(.serialized)
@MainActor
struct ViewportNativePatternReleaseTests {
    /// A pattern drag released away from its last reported position must commit
    /// the value the release names.
    ///
    /// `ViewportInputSurface` reports no drag preview at the release point, so
    /// the last `mouseDragged` and the `mouseUp` disagree whenever the pointer
    /// moves between them. The gesture owner therefore reads the release point
    /// itself. Here the preview walks the copy count below its base and the
    /// release walks it above: a commit that reported the previewed value would
    /// lower the count, and only a commit that read the release point raises it.
    @Test(.timeLimit(.minutes(1)), arguments: [ViewportCameraProjection.parallel, .standardPerspective])
    func viewportNativePatternDragCommitsTheReleasePointValue(
        projection: ViewportCameraProjection
    ) async throws {
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

        // Only the copy-count route is enabled below, so it is the one handle
        // the press can meet and the only record the producer registers.
        let patternInput = ViewportPatternAffordanceSource.RawInput(
            document: document,
            scene: scene,
            selection: selection,
            ruler: ruler,
            hasRoute: true,
            copyCountRouteEnabled: true
        )
        let patternSource = try #require(try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
            from: patternInput,
            checkpoint: { _, _, _ in }
        ))
        let handle = try #require(patternSource.copyCountHandles.first { $0.slot == .rectangularFirst })
        guard case .linear(let basePoint, let direction, let distanceMeters, _) = handle.guide else {
            Issue.record("The rectangular pattern did not prepare a linear copy-count guide.")
            return
        }

        // The same materialization the press performs, resolved here against the
        // fixture layout so the drag offsets are expressed in copies rather than
        // in raw points.
        let materialized = try ViewportSpatialPreparedInteractionTarget
            .patternArrayCopyCount(handle)
            .materialize(using: { point in
                guard let projected = layout.projectedPoint(point)?.point else {
                    throw MissingFixtureProjection()
                }
                return projected
            })
        guard case .patternArrayCopyCountLinear(_, let countProjection) = materialized else {
            Issue.record("The prepared copy-count handle did not materialize a linear projection.")
            return
        }
        let baseCopyCount = countProjection.baseCopyCount
        #expect(baseCopyCount == 2)

        let directionLength = direction.length
        let tipWorld = Point3D(
            x: basePoint.x + direction.x / directionLength * distanceMeters * Double(handle.copyCount),
            y: basePoint.y + direction.y / directionLength * distanceMeters * Double(handle.copyCount),
            z: basePoint.z + direction.z / directionLength * distanceMeters * Double(handle.copyCount)
        )
        let projectedBase = try #require(layout.projectedPoint(basePoint)?.point)
        let projectedTip = try #require(layout.projectedPoint(tipWorld)?.point)
        let projectedLength = hypot(projectedTip.x - projectedBase.x, projectedTip.y - projectedBase.y)
        let screenDirectionLength = max(projectedLength, 1.0e-12)
        let screenDirection = CGVector(
            dx: (projectedTip.x - projectedBase.x) / screenDirectionLength,
            dy: (projectedTip.y - projectedBase.y) / screenDirectionLength
        )
        // The copy-count shaft keeps a screen-fixed minimum of 28 points per
        // copy, so the press lands halfway along whichever length is longer.
        let shaftLength = max(projectedLength, 28.0 * CGFloat(handle.copyCount))
        let start = CGPoint(
            x: projectedBase.x + screenDirection.dx * shaftLength * 0.5,
            y: projectedBase.y + screenDirection.dy * shaftLength * 0.5
        )
        let previewOffset = countProjection.pointsPerCopy * 2.0
        let releaseOffset = countProjection.pointsPerCopy * 3.0
        let previewPoint = CGPoint(
            x: start.x - countProjection.projectedDirection.dx * previewOffset,
            y: start.y - countProjection.projectedDirection.dy * previewOffset
        )
        let releasePoint = CGPoint(
            x: start.x + countProjection.projectedDirection.dx * releaseOffset,
            y: start.y + countProjection.projectedDirection.dy * releaseOffset
        )

        var commits: [ViewportPatternArrayCopyCountDragTarget] = []
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
            onPatternArrayCopyCountDrag: { commits.append($0) }
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
                input.onDragPreview?(start, previewPoint, size)
                input.onCanvasDrag?(start, releasePoint, size, .replace)
            }
            try await Task.sleep(for: .milliseconds(30))
        }

        let commit = try #require(commits.first, Comment(rawValue:
            "Native pattern copy count did not commit: start=\(start), preview=\(previewPoint), "
            + "release=\(releasePoint), canvasDrags=\(canvasDrags)"))
        #expect(commits.count == 1)
        #expect(commit.sourceID == source.id)
        #expect(commit.slot == .rectangularFirst)
        #expect(
            commit.copyCount > baseCopyCount,
            Comment(rawValue:
                "The release walked the count above \(baseCopyCount) and the preview walked it below, "
                + "so a committed count of \(commit.copyCount) reports the last preview instead of the release."
            )
        )
        #expect(canvasDrags == 0)
    }
}

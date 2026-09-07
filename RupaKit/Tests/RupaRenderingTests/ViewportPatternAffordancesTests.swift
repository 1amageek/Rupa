import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test
func rawPatternInputBuildsSelectedWorldRouteOnWorkerBoundary() throws {
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let sourceID = PatternArraySourceID()
    let sceneNode = SceneNode(
        id: sceneNodeID,
        name: "Pattern Root",
        reference: .body(featureID)
    )
    let source = PatternArraySource(
        id: sourceID,
        name: "Array",
        definitionID: ComponentDefinitionID(),
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(1.0, .meter),
                copyCount: 2
            )
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [sceneNodeID],
        rootSceneNodeID: sceneNodeID
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [sceneNodeID: sceneNode],
        rootSceneNodeIDs: [sceneNodeID],
        patternArrays: [sourceID: source]
    )
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "pattern-source",
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 2,
                sizeYMeters: 2,
                sizeZMeters: 2,
                yMinMeters: -1,
                yMaxMeters: 1
            ))
        ),
    ])
    let selection = SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)])
    let raw = ViewportPatternAffordanceSource.RawInput(
        document: document,
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        hasRoute: true,
        linearAxisRouteEnabled: true,
        copyCountRouteEnabled: true,
        outputModeRouteEnabled: true
    )

    let sourceValue = try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
        from: raw,
        checkpoint: { _, _, _ in }
    )

    let built = try #require(sourceValue)
    #expect(built.guides.contains { guide in
        if case .linear = guide { return true }
        return false
    })
    #expect(built.linearAxisHandles.contains { $0.sourceID == sourceID })
    #expect(built.copyCountHandles.contains { $0.sourceID == sourceID })
    #expect(built.outputModeHandles.contains { $0.sourceID == sourceID })
}

@Test
func rawPatternInputWithCallbacksAndNoSelectionReturnsAnEmptyFrame() throws {
    let raw = ViewportPatternAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: []),
        selection: SelectionModel(),
        ruler: .standard(for: .meter),
        hasRoute: true
    )

    let source = try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
        from: raw,
        checkpoint: { _, _, _ in }
    )
    #expect(source == nil)
}

@Test
func rawPatternInputBuildsRadialAndCurveRoutesFromDocumentValues() throws {
    let radialFeatureID = FeatureID()
    let radialNodeID = SceneNodeID()
    let radialSourceID = PatternArraySourceID()
    let curveFeatureID = FeatureID()
    let curveNodeID = SceneNodeID()
    let curveSourceID = PatternArraySourceID()
    let radialNode = SceneNode(id: radialNodeID, name: "Radial Root", reference: .body(radialFeatureID))
    let curveNode = SceneNode(id: curveNodeID, name: "Curve Root", reference: .body(curveFeatureID))
    let radialSource = PatternArraySource(
        id: radialSourceID,
        name: "Radial Array",
        definitionID: ComponentDefinitionID(),
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitY,
                angle: .angle(90, .degree),
                copyCount: 3,
                angleMode: .extent
            )
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [radialNodeID],
        rootSceneNodeID: radialNodeID
    )
    let curveSource = PatternArraySource(
        id: curveSourceID,
        name: "Curve Array",
        definitionID: ComponentDefinitionID(),
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 1, y: 0, z: 1)],
                normal: .unitY
            ),
            copyCount: 2,
            extent: .scalar(0.75),
            extentMode: .ratio
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [curveNodeID],
        rootSceneNodeID: curveNodeID
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [radialNodeID: radialNode, curveNodeID: curveNode],
        rootSceneNodeIDs: [radialNodeID, curveNodeID],
        patternArrays: [radialSourceID: radialSource, curveSourceID: curveSource]
    )
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "radial-source",
            featureID: radialFeatureID,
            sceneNodeID: radialNodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 2, sizeYMeters: 2, sizeZMeters: 2, yMinMeters: -1, yMaxMeters: 1
            ))
        ),
        ViewportSceneItem(
            id: "curve-source",
            featureID: curveFeatureID,
            sceneNodeID: curveNodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 2, sizeYMeters: 2, sizeZMeters: 2, yMinMeters: -1, yMaxMeters: 1
            ))
        ),
    ])
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(sceneNodeID: radialNodeID),
        SelectionTarget(sceneNodeID: curveNodeID),
    ])
    let raw = ViewportPatternAffordanceSource.RawInput(
        document: document,
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        hasRoute: true,
        radialAngleRouteEnabled: true,
        copyCountRouteEnabled: true,
        curveExtentRouteEnabled: true,
        curvePathPointRouteEnabled: true,
        outputModeRouteEnabled: true
    )

    let source = try #require(try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
        from: raw,
        checkpoint: { _, _, _ in }
    ))
    #expect(source.guides.contains { if case .radial = $0 { return true }; return false })
    #expect(source.guides.contains { if case .curve = $0 { return true }; return false })
    #expect(source.radialAngleHandles.contains { $0.sourceID == radialSourceID })
    #expect(source.curveExtentHandles.contains { $0.sourceID == curveSourceID })
    #expect(source.curvePathPointHandles.contains { $0.sourceID == curveSourceID })
    #expect(source.copyCountHandles.contains { $0.sourceID == radialSourceID })
    #expect(source.copyCountHandles.contains { $0.sourceID == curveSourceID })
}

@MainActor
@Test
func rawPatternInputBuildsIndependentCopyRouteFromEvaluatedDocument() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(session.document.productMetadata.sceneNodes.first {
        $0.value.reference?.featureID == bodyFeatureID
    }?.key)
    _ = try session.execute(.createComponentDefinition(
        name: "Raw Independent Source",
        rootSceneNodeIDs: [bodySceneNodeID]
    ))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Raw Independent Source"
    })
    _ = try session.execute(.createPatternArray(
        name: "Raw Independent Array",
        definitionID: definition.id,
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(8, .millimeter),
                copyCount: 2
            )
        )),
        outputMode: .independentCopy
    ))
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Raw Independent Array"
    })
    let outputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler
    )
    let selection = SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: outputSceneNodeID)])
    let raw = ViewportPatternAffordanceSource.RawInput(
        document: session.document,
        scene: scene,
        selection: selection,
        ruler: session.workspaceState.ruler,
        hasRoute: true,
        outputModeRouteEnabled: true,
        independentCopyExtrudeRouteEnabled: true,
        independentCopyDimensionRouteEnabled: true
    )

    let built = try #require(try ViewportSpatialOverlayProducer.makePatternAffordanceSource(
        from: raw,
        checkpoint: { _, _, _ in }
    ))
    #expect(built.outputModeHandles.contains { $0.sourceID == source.id })
    #expect(built.independentCopyExtrudeHandles.contains { $0.sourceID == source.id })
    #expect(built.independentCopyDimensionHandles.contains { $0.sourceID == source.id })
}

@Test
func independentCopyIndexPropagatesCancellationDuringNestedSubtreeTraversal() {
    let rootID = SceneNodeID()
    let featureID = FeatureID()
    let sourceID = PatternArraySourceID()
    let childIDs = (0..<64).map { _ in SceneNodeID() }
    var sceneNodes: [SceneNodeID: SceneNode] = [
        rootID: SceneNode(
            id: rootID,
            name: "Independent Output Root",
            childIDs: childIDs
        ),
    ]
    for (index, childID) in childIDs.enumerated() {
        sceneNodes[childID] = SceneNode(
            id: childID,
            name: "Output Child \(index)",
            reference: .body(featureID)
        )
    }
    let source = PatternArraySource(
        id: sourceID,
        name: "Independent Array",
        definitionID: ComponentDefinitionID(),
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(1, .meter),
                copyCount: 2
            )
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [rootID],
        rootSceneNodeID: rootID
    )
    let metadata = ProductMetadata(
        sceneNodes: sceneNodes,
        rootSceneNodeIDs: [rootID],
        patternArrays: [sourceID: source]
    )
    var visits = 0
    #expect(throws: CancellationError.self) {
        _ = try ViewportIndependentCopyOutputSelectionIndex(
            metadata: metadata,
            scene: ViewportScene(items: []),
            checkpoint: { _, _, count in
                visits += count
                if visits >= 71 { throw CancellationError() }
            }
        )
    }
    #expect(visits >= 71)
}

@Test
func patternAffordanceProducerEmitsEveryWorldRouteAndSharesHandleFragments() throws {
    let sourceID = PatternArraySourceID()
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let path = [
        Point3D(x: 0, y: 0, z: 0),
        Point3D(x: 1, y: 0, z: 0),
        Point3D(x: 1, y: 0, z: 1),
    ]
    let active = ViewportPatternAffordanceSource.VisualState(
        isActive: true,
        isHighlighted: false
    )
    let highlighted = ViewportPatternAffordanceSource.VisualState(
        isActive: false,
        isHighlighted: true
    )
    let source = ViewportPatternAffordanceSource(
        hasRoute: true,
        guides: [
            .linear(.init(
                title: "Linear Guide",
                basePoint: .origin,
                direction: .unitX,
                distanceMeters: 1,
                state: active
            )),
            .radial(.init(
                title: "Radial Guide",
                center: .origin,
                axis: .unitY,
                referencePoint: Point3D(x: 1, y: 0, z: 0),
                angleRadians: .pi / 2,
                state: highlighted,
                radialGuide: nil
            )),
            .curve(.init(
                title: "Curve Guide",
                pathPoints: path,
                extentDistanceMeters: 1.5,
                state: active
            )),
        ],
        previews: [
            .init(
                title: "Preview",
                outputCount: 1,
                outputs: [.init(
                    index: 0,
                    outline: [
                        .origin,
                        Point3D(x: 0.25, y: 0, z: 0),
                        Point3D(x: 0.25, y: 0, z: 0.25),
                    ],
                    center: Point3D(x: 0.125, y: 0, z: 0.125),
                    isSelected: true
                )]
            ),
        ],
        replacement: .init(
            title: "Replacement",
            pathPoints: [
                .origin,
                Point3D(x: 0, y: 0, z: 1),
            ],
            outputPoints: [Point3D(x: 0, y: 0, z: 0.5)],
            totalOutputCount: 1
        ),
        linearAxisHandles: [.init(
            sourceID: sourceID,
            axisSlot: .first,
            title: "Axis",
            basePoint: .origin,
            direction: .unitX,
            distanceMeters: 1,
            displayDistanceMeters: nil,
            distanceMode: .spacing,
            state: active
        )],
        radialAngleHandles: [.init(
            sourceID: sourceID,
            title: "Angle",
            center: .origin,
            axis: .unitY,
            referencePoint: Point3D(x: 1, y: 0, z: 0),
            angleRadians: .pi / 4,
            displayAngleRadians: nil,
            angleMode: .extent,
            state: highlighted
        )],
        copyCountHandles: [.init(
            sourceID: sourceID,
            slot: .curve,
            title: "Count",
            guide: .curve(pathPoints: path, extentDistanceMeters: 1.5),
            copyCount: 2,
            displayCopyCount: nil,
            state: active
        )],
        curveExtentHandles: [.init(
            sourceID: sourceID,
            title: "Extent",
            pathPoints: path,
            distanceMeters: 1.25,
            displayDistanceMeters: nil,
            extentMode: .distance,
            state: highlighted
        )],
        curvePathPointHandles: [.init(
            sourceID: sourceID,
            pointIndex: 1,
            title: "Path Point",
            pathPoints: path,
            activePoint: nil,
            state: active
        )],
        outputModeHandles: [.init(
            sourceID: sourceID,
            anchor: Point3D(x: 0.5, y: 0, z: 0.5),
            title: "Component",
            highlightedTitle: "Independent",
            state: highlighted
        )],
        independentCopyExtrudeHandles: [.init(
            sourceID: sourceID,
            outputIndex: 0,
            outputSceneNodeID: sceneNodeID,
            featureID: featureID,
            title: "Extrude",
            basePoint: .origin,
            axis: .unitY,
            distanceMeters: 0.5,
            displayDistanceMeters: nil,
            state: active
        )],
        independentCopyDimensionHandles: [.init(
            sourceID: sourceID,
            outputIndex: 0,
            outputSceneNodeID: sceneNodeID,
            featureID: featureID,
            kind: .sizeX,
            label: "Width",
            basePoint: .origin,
            axis: .unitX,
            valueMeters: 0.5,
            displayValueMeters: nil,
            state: highlighted
        )]
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    var handleIdentities: [ViewportSpatialHandleIdentity] = []
    try ViewportSpatialOverlayProducer.appendPatternAffordances(
        source,
        meshes: &meshes,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        activeFamilies: &families,
        handleIdentities: &handleIdentities,
        checkpoint: { _, _, _ in }
    )

    #expect(families.contains(.pattern))
    #expect(handleIdentities.count == 8)
    #expect(meshes.contains { $0.value.positions.contains(Point3D(x: 1, y: 0, z: 1)) })
    #expect(labels.contains { $0.value.text == "Independent" })
    #expect(cameraPaths.count >= 6)
    #expect(cameraLines.count >= 6)
    #expect(cameraLines.allSatisfy { line in
        guard let index = line.value.handleIndex else { return false }
        return cameraPaths.contains { $0.value.handleIndex == index }
    })
    if let firstLine = cameraLines.first?.value,
       let start = firstLine.points.first,
       let tip = firstLine.points.dropFirst().first {
        switch start.offset {
        case .fixed(let offset):
            #expect(offset == .zero)
        case .directed, .projected:
            Issue.record("Pattern camera arrows must begin at the fixed world anchor.")
        }
        switch tip.offset {
        case .projected(_, let minimumLength, _, _):
            #expect(minimumLength > 0)
        case .directed, .fixed:
            Issue.record("Pattern camera arrow tips must use projected native placement.")
        }
    } else {
        Issue.record("Pattern camera arrow did not publish both anchor and tip points.")
    }

    let emittedHandleIndices = cameraPaths.compactMap(\.value.handleIndex)
        + cameraLines.compactMap(\.value.handleIndex)
        + labels.compactMap(\.value.handleIndex)
        + markers.compactMap(\.value.handleIndex)
        + meshes.compactMap(\.value.handleIndex)
    #expect(Set(emittedHandleIndices).count == handleIdentities.count)
    #expect(labels.contains { label in
        guard let index = label.value.handleIndex else { return false }
        return cameraPaths.contains { $0.value.handleIndex == index }
    })
}

@Test
func patternAffordanceProducerRejectsInvalidWorldGuide() {
    let source = ViewportPatternAffordanceSource(
        hasRoute: true,
        guides: [.linear(.init(
            title: "Invalid",
            basePoint: .origin,
            direction: .init(x: 0, y: 0, z: 0),
            distanceMeters: 1,
            state: .normal
        ))]
    )
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    var handleIdentities: [ViewportSpatialHandleIdentity] = []
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.appendPatternAffordances(
            source,
            meshes: &meshes,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            activeFamilies: &families,
            handleIdentities: &handleIdentities,
            checkpoint: { _, _, _ in }
        )
    }
    #expect(meshes.isEmpty)
    #expect(labels.isEmpty)
    #expect(markers.isEmpty)
}

@Test
func patternAffordanceProducerPropagatesAdmissionFailureBeforeAppending() {
    let source = ViewportPatternAffordanceSource(
        hasRoute: true,
        guides: [.linear(.init(
            title: "Bounded",
            basePoint: .origin,
            direction: .unitX,
            distanceMeters: 1,
            state: .normal
        ))]
    )
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    var handleIdentities: [ViewportSpatialHandleIdentity] = []
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.appendPatternAffordances(
            source,
            meshes: &meshes,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            activeFamilies: &families,
            handleIdentities: &handleIdentities,
            checkpoint: { _, positions, _ in
                if positions > 0 {
                    throw RealityViewportSpatialBatch.exhausted()
                }
            }
        )
    }
    #expect(meshes.isEmpty)
    #expect(labels.isEmpty)
    #expect(markers.isEmpty)
    #expect(families.isEmpty)
}

@Test
func patternAffordanceProducerPropagatesCancellation() {
    let source = ViewportPatternAffordanceSource(
        hasRoute: true,
        guides: [.linear(.init(
            title: "Cancelled",
            basePoint: .origin,
            direction: .unitX,
            distanceMeters: 1,
            state: .normal
        ))]
    )
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    var handleIdentities: [ViewportSpatialHandleIdentity] = []
    #expect(throws: CancellationError.self) {
        try ViewportSpatialOverlayProducer.appendPatternAffordances(
            source,
            meshes: &meshes,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            activeFamilies: &families,
            handleIdentities: &handleIdentities,
            checkpoint: { _, _, _ in
                throw CancellationError()
            }
        )
    }
    #expect(meshes.isEmpty)
    #expect(labels.isEmpty)
    #expect(markers.isEmpty)
}

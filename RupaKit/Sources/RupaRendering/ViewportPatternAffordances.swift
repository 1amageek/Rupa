import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftUI

/// Immutable world-space values for the Pattern Array affordance routes.
///
/// This value is assembled at the producer boundary. It deliberately contains
/// no camera, layout, projected point, or SwiftUI state. A handle identity is
/// resolved once by the append operation and is shared by every visual
/// fragment belonging to that handle.
struct ViewportPatternAffordanceSource: Sendable {
    /// Checked-Sendable values captured by the MainActor. The worker resolves
    /// all world guides, previews, and independent-copy handles from this
    /// value; no camera or layout is needed to build the semantic source.
    struct RawInput: Sendable {
        let document: DesignDocument
        let scene: ViewportScene
        let selection: SelectionModel
        let ruler: RulerConfiguration
        let hasRoute: Bool
        let replacementRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest?
        let activeHandleIdentities: [ViewportSpatialHandleIdentity]
        let hoveredHandleIdentities: [ViewportSpatialHandleIdentity]
        let pendingHandleIdentities: [ViewportSpatialHandleIdentity]
        let activeLinearAxis: ViewportPatternArrayLinearAxisDragTarget?
        let activeRadialAngle: ViewportPatternArrayRadialAngleDragTarget?
        let activeCopyCount: ViewportPatternArrayCopyCountDragTarget?
        let activeCurveExtent: ViewportPatternArrayCurveExtentDragTarget?
        let activeCurvePathPoint: ViewportPatternArrayCurvePathPointDragTarget?
        let activeIndependentCopyExtrude: ViewportIndependentCopyExtrudeDistanceDragTarget?
        let activeIndependentCopyDimension: ViewportIndependentCopyBodyDimensionDragTarget?
        let linearAxisRouteEnabled: Bool
        let radialAngleRouteEnabled: Bool
        let copyCountRouteEnabled: Bool
        let curveExtentRouteEnabled: Bool
        let curvePathPointRouteEnabled: Bool
        let outputModeRouteEnabled: Bool
        let independentCopyExtrudeRouteEnabled: Bool
        let independentCopyDimensionRouteEnabled: Bool

        init(
            document: DesignDocument,
            scene: ViewportScene,
            selection: SelectionModel,
            ruler: RulerConfiguration = .standard(for: .meter),
            hasRoute: Bool,
            replacementRequest: ViewportPatternArrayCurvePathReplacementPreviewRequest? = nil,
            activeHandleIdentities: [ViewportSpatialHandleIdentity] = [],
            hoveredHandleIdentities: [ViewportSpatialHandleIdentity] = [],
            pendingHandleIdentities: [ViewportSpatialHandleIdentity] = [],
            activeLinearAxis: ViewportPatternArrayLinearAxisDragTarget? = nil,
            activeRadialAngle: ViewportPatternArrayRadialAngleDragTarget? = nil,
            activeCopyCount: ViewportPatternArrayCopyCountDragTarget? = nil,
            activeCurveExtent: ViewportPatternArrayCurveExtentDragTarget? = nil,
            activeCurvePathPoint: ViewportPatternArrayCurvePathPointDragTarget? = nil,
            activeIndependentCopyExtrude: ViewportIndependentCopyExtrudeDistanceDragTarget? = nil,
            activeIndependentCopyDimension: ViewportIndependentCopyBodyDimensionDragTarget? = nil,
            linearAxisRouteEnabled: Bool = false,
            radialAngleRouteEnabled: Bool = false,
            copyCountRouteEnabled: Bool = false,
            curveExtentRouteEnabled: Bool = false,
            curvePathPointRouteEnabled: Bool = false,
            outputModeRouteEnabled: Bool = false,
            independentCopyExtrudeRouteEnabled: Bool = false,
            independentCopyDimensionRouteEnabled: Bool = false
        ) {
            self.document = document
            self.scene = scene
            self.selection = selection
            self.ruler = ruler
            self.hasRoute = hasRoute
            self.replacementRequest = replacementRequest
            self.activeHandleIdentities = activeHandleIdentities
            self.hoveredHandleIdentities = hoveredHandleIdentities
            self.pendingHandleIdentities = pendingHandleIdentities
            self.activeLinearAxis = activeLinearAxis
            self.activeRadialAngle = activeRadialAngle
            self.activeCopyCount = activeCopyCount
            self.activeCurveExtent = activeCurveExtent
            self.activeCurvePathPoint = activeCurvePathPoint
            self.activeIndependentCopyExtrude = activeIndependentCopyExtrude
            self.activeIndependentCopyDimension = activeIndependentCopyDimension
            self.linearAxisRouteEnabled = linearAxisRouteEnabled
            self.radialAngleRouteEnabled = radialAngleRouteEnabled
            self.copyCountRouteEnabled = copyCountRouteEnabled
            self.curveExtentRouteEnabled = curveExtentRouteEnabled
            self.curvePathPointRouteEnabled = curvePathPointRouteEnabled
            self.outputModeRouteEnabled = outputModeRouteEnabled
            self.independentCopyExtrudeRouteEnabled = independentCopyExtrudeRouteEnabled
            self.independentCopyDimensionRouteEnabled = independentCopyDimensionRouteEnabled
        }
    }

    struct VisualState: Sendable {
        let isActive: Bool
        let isHighlighted: Bool

        static let normal = Self(isActive: false, isHighlighted: false)
    }

    struct LinearGuide: Sendable {
        let title: String
        let basePoint: Point3D
        let direction: Vector3D
        let distanceMeters: Double
        let state: VisualState
    }

    struct RadialGuide: Sendable {
        let title: String
        let center: Point3D
        let axis: Vector3D
        let referencePoint: Point3D
        let angleRadians: Double
        let state: VisualState
        let radialGuide: LinearGuide?
    }

    struct CurveGuide: Sendable {
        let title: String
        let pathPoints: [Point3D]
        let extentDistanceMeters: Double
        let state: VisualState
    }

    struct LinearAxisHandle: Sendable {
        let sourceID: PatternArraySourceID
        let axisSlot: ViewportPatternArrayLinearAxisSlot
        let title: String
        let basePoint: Point3D
        let direction: Vector3D
        let distanceMeters: Double
        let displayDistanceMeters: Double?
        let distanceMode: PatternArrayDistanceMode
        let state: VisualState
    }

    struct RadialAngleHandle: Sendable {
        let sourceID: PatternArraySourceID
        let title: String
        let center: Point3D
        let axis: Vector3D
        let referencePoint: Point3D
        let angleRadians: Double
        let displayAngleRadians: Double?
        let angleMode: PatternArrayAngleMode
        let state: VisualState
    }

    enum CopyCountGuide: Sendable {
        case linear(
            basePoint: Point3D,
            direction: Vector3D,
            distanceMeters: Double,
            distanceMode: PatternArrayDistanceMode
        )
        case radial(
            center: Point3D,
            axis: Vector3D,
            referencePoint: Point3D,
            angleRadians: Double,
            angleMode: PatternArrayAngleMode
        )
        case curve(
            pathPoints: [Point3D],
            extentDistanceMeters: Double
        )
    }

    struct CopyCountHandle: Sendable {
        let sourceID: PatternArraySourceID
        let slot: ViewportPatternArrayCopyCountSlot
        let title: String
        let guide: CopyCountGuide
        let copyCount: Int
        let displayCopyCount: Int?
        let state: VisualState
    }

    struct CurveExtentHandle: Sendable {
        let sourceID: PatternArraySourceID
        let title: String
        let pathPoints: [Point3D]
        let distanceMeters: Double
        let displayDistanceMeters: Double?
        let extentMode: PatternArrayCurveExtentMode
        let state: VisualState
    }

    struct CurvePathPointHandle: Sendable {
        let sourceID: PatternArraySourceID
        let pointIndex: Int
        let title: String
        let pathPoints: [Point3D]
        let activePoint: Point3D?
        let state: VisualState
    }

    struct OutputModeHandle: Sendable {
        let sourceID: PatternArraySourceID
        let anchor: Point3D
        let title: String
        let highlightedTitle: String
        let state: VisualState
    }

    struct IndependentCopyExtrudeHandle: Sendable {
        let sourceID: PatternArraySourceID
        let outputIndex: Int
        let outputSceneNodeID: SceneNodeID
        let featureID: FeatureID
        let title: String
        let basePoint: Point3D
        let axis: Vector3D
        let distanceMeters: Double
        let displayDistanceMeters: Double?
        let state: VisualState
    }

    struct IndependentCopyDimensionHandle: Sendable {
        let sourceID: PatternArraySourceID
        let outputIndex: Int
        let outputSceneNodeID: SceneNodeID
        let featureID: FeatureID
        let kind: ViewportIndependentCopyBodyDimensionKind
        let label: String
        let basePoint: Point3D
        let axis: Vector3D
        let valueMeters: Double
        let displayValueMeters: Double?
        let state: VisualState
    }

    struct PreviewOutput: Sendable {
        let index: Int
        let outline: [Point3D]
        let center: Point3D
        let isSelected: Bool
    }

    struct Preview: Sendable {
        let title: String
        let outputCount: Int
        let outputs: [PreviewOutput]
    }

    struct Replacement: Sendable {
        let title: String
        let pathPoints: [Point3D]
        let outputPoints: [Point3D]
        let totalOutputCount: Int
    }

    let hasRoute: Bool
    let ruler: RulerConfiguration
    let guides: [Guide]
    let previews: [Preview]
    let replacement: Replacement?
    let linearAxisHandles: [LinearAxisHandle]
    let radialAngleHandles: [RadialAngleHandle]
    let copyCountHandles: [CopyCountHandle]
    let curveExtentHandles: [CurveExtentHandle]
    let curvePathPointHandles: [CurvePathPointHandle]
    let outputModeHandles: [OutputModeHandle]
    let independentCopyExtrudeHandles: [IndependentCopyExtrudeHandle]
    let independentCopyDimensionHandles: [IndependentCopyDimensionHandle]

    enum Guide: Sendable {
        case linear(LinearGuide)
        case radial(RadialGuide)
        case curve(CurveGuide)
    }

    init(
        hasRoute: Bool = false,
        ruler: RulerConfiguration = .standard(for: .meter),
        guides: [Guide] = [],
        previews: [Preview] = [],
        replacement: Replacement? = nil,
        linearAxisHandles: [LinearAxisHandle] = [],
        radialAngleHandles: [RadialAngleHandle] = [],
        copyCountHandles: [CopyCountHandle] = [],
        curveExtentHandles: [CurveExtentHandle] = [],
        curvePathPointHandles: [CurvePathPointHandle] = [],
        outputModeHandles: [OutputModeHandle] = [],
        independentCopyExtrudeHandles: [IndependentCopyExtrudeHandle] = [],
        independentCopyDimensionHandles: [IndependentCopyDimensionHandle] = []
    ) {
        self.hasRoute = hasRoute
        self.ruler = ruler
        self.guides = guides
        self.previews = previews
        self.replacement = replacement
        self.linearAxisHandles = linearAxisHandles
        self.radialAngleHandles = radialAngleHandles
        self.copyCountHandles = copyCountHandles
        self.curveExtentHandles = curveExtentHandles
        self.curvePathPointHandles = curvePathPointHandles
        self.outputModeHandles = outputModeHandles
        self.independentCopyExtrudeHandles = independentCopyExtrudeHandles
        self.independentCopyDimensionHandles = independentCopyDimensionHandles
    }
}

extension ViewportSpatialOverlayProducer {
    /// Resolves raw checked-Sendable pattern inputs on the producer worker.
    /// This is the only worker entry for the Pattern Array affordance family;
    /// callers must not precompute projected geometry on the MainActor.
    static func makePatternAffordanceSource(
        from input: ViewportPatternAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> ViewportPatternAffordanceSource? {
        try Task.checkCancellation()
        let previews = try ViewportPatternArrayPreviewService().previews(
            document: input.document,
            scene: input.scene,
            selection: input.selection,
            checkpoint: checkpoint
        )
        try Task.checkCancellation()

        let metadata = input.document.productMetadata
        let sourceIndex = ViewportPatternArraySourceSelectionIndex(
            metadata: metadata,
            scene: input.scene,
            selection: input.selection
        )
        let selectedSourceIDs = try sourceIndex.selectedSourceIDs(checkpoint: checkpoint)
        var sourceGuides: [ViewportPatternAffordanceSource.Guide] = []
        var linearAxisHandles: [ViewportPatternAffordanceSource.LinearAxisHandle] = []
        var radialAngleHandles: [ViewportPatternAffordanceSource.RadialAngleHandle] = []
        var copyCountHandles: [ViewportPatternAffordanceSource.CopyCountHandle] = []
        var curveExtentHandles: [ViewportPatternAffordanceSource.CurveExtentHandle] = []
        var curvePathPointHandles: [ViewportPatternAffordanceSource.CurvePathPointHandle] = []
        var outputModeHandles: [ViewportPatternAffordanceSource.OutputModeHandle] = []

        if input.hasRoute {
            try checkpoint(0, 0, selectedSourceIDs.count)
        }
        for sourceID in selectedSourceIDs {
            try Task.checkCancellation()
            guard let patternSource = metadata.patternArrays[sourceID] else {
                throw RealityViewportSpatialBatch.invalid("Pattern array source is missing.")
            }
            guard let basePoint = try sourceIndex.sourceBaseModelPoint(
                source: patternSource,
                checkpoint: checkpoint
            ) else {
                throw RealityViewportSpatialBatch.invalid("Pattern array source has no world anchor.")
            }
            let resolver = PatternArrayExpressionResolver(
                parameters: input.document.cadDocument.parameters
            )
            try appendPatternRouteValues(
                patternSource,
                sourceID: sourceID,
                basePoint: basePoint,
                resolver: resolver,
                document: input.document,
                input: input,
                sourceGuides: &sourceGuides,
                linearAxisHandles: &linearAxisHandles,
                radialAngleHandles: &radialAngleHandles,
                copyCountHandles: &copyCountHandles,
                curveExtentHandles: &curveExtentHandles,
                curvePathPointHandles: &curvePathPointHandles,
                outputModeHandles: &outputModeHandles,
                checkpoint: checkpoint
            )
        }

        let previewValues = try makePatternPreviewValues(
            previews,
            document: input.document,
            scene: input.scene,
            checkpoint: checkpoint
        )
        let replacement = try makePatternReplacementValue(
            input.replacementRequest,
            document: input.document,
            scene: input.scene,
            checkpoint: checkpoint
        )
        let independentCopy = try makeIndependentCopyHandles(
            input: input,
            checkpoint: checkpoint
        )
        let hasAnyValue = !previewValues.isEmpty
            || replacement != nil
            || !sourceGuides.isEmpty
            || !linearAxisHandles.isEmpty
            || !radialAngleHandles.isEmpty
            || !copyCountHandles.isEmpty
            || !curveExtentHandles.isEmpty
            || !curvePathPointHandles.isEmpty
            || !outputModeHandles.isEmpty
            || !independentCopy.extrude.isEmpty
            || !independentCopy.dimension.isEmpty
        // Route callbacks can be installed while the document has no selected
        // Pattern Array source. That state is a valid empty semantic frame;
        // only a selected source whose world geometry fails validation is an
        // error. Do not let callback availability manufacture a failure.
        guard hasAnyValue else { return nil }
        return ViewportPatternAffordanceSource(
            hasRoute: input.hasRoute,
            ruler: input.ruler,
            guides: sourceGuides,
            previews: previewValues,
            replacement: replacement,
            linearAxisHandles: linearAxisHandles,
            radialAngleHandles: radialAngleHandles,
            copyCountHandles: copyCountHandles,
            curveExtentHandles: curveExtentHandles,
            curvePathPointHandles: curvePathPointHandles,
            outputModeHandles: outputModeHandles,
            independentCopyExtrudeHandles: independentCopy.extrude,
            independentCopyDimensionHandles: independentCopy.dimension
        )
    }

    private static func appendPatternRouteValues(
        _ patternSource: PatternArraySource,
        sourceID: PatternArraySourceID,
        basePoint: Point3D,
        resolver: PatternArrayExpressionResolver,
        document: DesignDocument,
        input: ViewportPatternAffordanceSource.RawInput,
        sourceGuides: inout [ViewportPatternAffordanceSource.Guide],
        linearAxisHandles: inout [ViewportPatternAffordanceSource.LinearAxisHandle],
        radialAngleHandles: inout [ViewportPatternAffordanceSource.RadialAngleHandle],
        copyCountHandles: inout [ViewportPatternAffordanceSource.CopyCountHandle],
        curveExtentHandles: inout [ViewportPatternAffordanceSource.CurveExtentHandle],
        curvePathPointHandles: inout [ViewportPatternAffordanceSource.CurvePathPointHandle],
        outputModeHandles: inout [ViewportPatternAffordanceSource.OutputModeHandle],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        switch patternSource.distribution {
        case .rectangular(let rectangular):
            let firstDistance = try resolvedPatternLength(
                rectangular.firstAxis.distance,
                resolver: resolver,
                label: "first linear axis"
            )
            try appendLinearPatternRoute(
                sourceID: sourceID,
                name: patternSource.name,
                axisSlot: .first,
                basePoint: basePoint,
                axis: rectangular.firstAxis,
                distanceMeters: firstDistance,
                checkpoint: checkpoint,
                input: input,
                sourceGuides: &sourceGuides,
                linearAxisHandles: &linearAxisHandles,
                copyCountHandles: &copyCountHandles
            )
            if let secondAxis = rectangular.secondAxis {
                let secondDistance = try resolvedPatternLength(
                    secondAxis.distance,
                    resolver: resolver,
                    label: "second linear axis"
                )
                try appendLinearPatternRoute(
                    sourceID: sourceID,
                    name: patternSource.name,
                    axisSlot: .second,
                    basePoint: basePoint,
                    axis: secondAxis,
                    distanceMeters: secondDistance,
                    checkpoint: checkpoint,
                    input: input,
                    sourceGuides: &sourceGuides,
                    linearAxisHandles: &linearAxisHandles,
                    copyCountHandles: &copyCountHandles
                )
            }
        case .radial(let radial):
            let angle = try resolvedPatternAngle(
                radial.angularAxis.angle,
                resolver: resolver,
                label: "angular axis"
            )
            let radialGuide: ViewportPatternAffordanceSource.LinearGuide?
            if let radialAxis = radial.radialAxis {
                let distance = try resolvedPatternLength(
                    radialAxis.distance,
                    resolver: resolver,
                    label: "radial axis"
                )
                radialGuide = .init(
                    title: "Pattern \(patternSource.name) Radius",
                    basePoint: basePoint,
                    direction: radialAxis.direction,
                    distanceMeters: distance,
                    state: .normal
                )
            } else {
                radialGuide = nil
            }
            if input.hasRoute {
                sourceGuides.append(.radial(.init(
                    title: "Pattern \(patternSource.name)",
                    center: radial.angularAxis.center,
                    axis: radial.angularAxis.axis,
                    referencePoint: basePoint,
                    angleRadians: angle,
                    state: .normal,
                    radialGuide: radialGuide
                )))
            }
            if input.radialAngleRouteEnabled {
                let identity = ViewportSpatialHandleIdentity.patternArrayRadialAngle(
                    .init(sourceID: sourceID)
                )
                let activeAngle = input.activeRadialAngle.flatMap {
                    $0.sourceID == sourceID ? $0.angleRadians : nil
                }
                radialAngleHandles.append(.init(
                    sourceID: sourceID,
                    title: "Radial \(patternAngleModeTitle(radial.angularAxis.angleMode))",
                    center: radial.angularAxis.center,
                    axis: radial.angularAxis.axis,
                    referencePoint: basePoint,
                    angleRadians: angle,
                    displayAngleRadians: activeAngle,
                    angleMode: radial.angularAxis.angleMode,
                    state: patternVisualState(for: identity, input: input)
                ))
            }
            if input.copyCountRouteEnabled {
                let angularIdentity = ViewportSpatialHandleIdentity.patternArrayCopyCount(
                    .init(sourceID: sourceID, slot: .radialAngular)
                )
                copyCountHandles.append(.init(
                    sourceID: sourceID,
                    slot: .radialAngular,
                    title: "Radial Count",
                    guide: .radial(
                        center: radial.angularAxis.center,
                        axis: radial.angularAxis.axis,
                        referencePoint: basePoint,
                        angleRadians: angle,
                        angleMode: radial.angularAxis.angleMode
                    ),
                    copyCount: radial.angularAxis.copyCount,
                    displayCopyCount: nil,
                    state: patternVisualState(for: angularIdentity, input: input)
                ))
                if let radialAxis = radial.radialAxis {
                    let distance = try resolvedPatternLength(
                        radialAxis.distance,
                        resolver: resolver,
                        label: "radial copy axis"
                    )
                    let radialIdentity = ViewportSpatialHandleIdentity.patternArrayCopyCount(
                        .init(sourceID: sourceID, slot: .radialAxis)
                    )
                    copyCountHandles.append(.init(
                        sourceID: sourceID,
                        slot: .radialAxis,
                        title: "Radius Count",
                        guide: .linear(
                            basePoint: basePoint,
                            direction: radialAxis.direction,
                            distanceMeters: distance,
                            distanceMode: radialAxis.distanceMode
                        ),
                        copyCount: radialAxis.copyCount,
                        displayCopyCount: nil,
                        state: patternVisualState(for: radialIdentity, input: input)
                    ))
                }
            }
        case .curve(let curve):
            let geometry: PatternArrayCurveDistributionGeometry
            do {
                geometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                    for: curve,
                    parameters: document.cadDocument.parameters,
                    cadDocument: document.cadDocument
                )
            } catch {
                throw RealityViewportSpatialBatch.invalid("Pattern-array curve path is unresolved.")
            }
            let pathPoints = try sampledPatternPath(geometry.path, checkpoint: checkpoint)
            guard pathPoints.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid("Pattern-array curve path has fewer than two world points.")
            }
            let extent = geometry.distributionLength
            if input.hasRoute {
                sourceGuides.append(.curve(.init(
                    title: "Pattern \(patternSource.name)",
                    pathPoints: pathPoints,
                    extentDistanceMeters: extent,
                    state: .normal
                )))
            }
            if input.curveExtentRouteEnabled {
                let identity = ViewportSpatialHandleIdentity.patternArrayCurveExtent(
                    .init(sourceID: sourceID)
                )
                let activeDistance: Double?
                if let active = input.activeCurveExtent, active.sourceID == sourceID {
                    switch active.extent {
                    case .distance(let value):
                        activeDistance = value
                    case .ratio(let value):
                        activeDistance = extent * value
                    }
                } else {
                    activeDistance = nil
                }
                curveExtentHandles.append(.init(
                    sourceID: sourceID,
                    title: curve.extentMode == .distance ? "Curve Extent" : "Curve Ratio",
                    pathPoints: pathPoints,
                    distanceMeters: extent,
                    displayDistanceMeters: activeDistance,
                    extentMode: curve.extentMode,
                    state: patternVisualState(for: identity, input: input)
                ))
            }
            if input.curvePathPointRouteEnabled,
               case .polyline(let controlPoints, _) = curve.path {
                try checkpoint(0, controlPoints.count, controlPoints.count)
                for (pointIndex, _) in controlPoints.enumerated() {
                    try Task.checkCancellation()
                    let identity = ViewportSpatialHandleIdentity.patternArrayCurvePathPoint(
                        .init(sourceID: sourceID, pointIndex: pointIndex)
                    )
                    curvePathPointHandles.append(.init(
                        sourceID: sourceID,
                        pointIndex: pointIndex,
                        title: "Path P\(pointIndex + 1)",
                        pathPoints: controlPoints,
                        activePoint: input.activeCurvePathPoint.flatMap {
                            $0.sourceID == sourceID && $0.pointIndex == pointIndex ? $0.point : nil
                        },
                        state: patternVisualState(for: identity, input: input)
                    ))
                }
            }
            if input.copyCountRouteEnabled {
                let identity = ViewportSpatialHandleIdentity.patternArrayCopyCount(
                    .init(sourceID: sourceID, slot: .curve)
                )
                copyCountHandles.append(.init(
                    sourceID: sourceID,
                    slot: .curve,
                    title: "Curve Count",
                    guide: .curve(pathPoints: pathPoints, extentDistanceMeters: extent),
                    copyCount: curve.copyCount,
                    displayCopyCount: nil,
                    state: patternVisualState(for: identity, input: input)
                ))
            }
        }
        if input.outputModeRouteEnabled {
            let identity = ViewportSpatialHandleIdentity.patternArrayOutputMode(
                .init(sourceID: sourceID)
            )
            let title: String
            let highlightedTitle: String
            switch patternSource.outputMode {
            case .componentInstance:
                title = "Output Instance"
                highlightedTitle = "Switch Independent"
            case .independentCopy:
                title = "Output Independent"
                highlightedTitle = "Switch Instance"
            }
            outputModeHandles.append(.init(
                sourceID: sourceID,
                anchor: basePoint,
                title: title,
                highlightedTitle: highlightedTitle,
                state: patternVisualState(for: identity, input: input)
            ))
        }
    }

    private static func appendLinearPatternRoute(
        sourceID: PatternArraySourceID,
        name: String,
        axisSlot: ViewportPatternArrayLinearAxisSlot,
        basePoint: Point3D,
        axis: PatternArrayLinearAxis,
        distanceMeters: Double,
        checkpoint: (Int, Int, Int) throws -> Void,
        input: ViewportPatternAffordanceSource.RawInput,
        sourceGuides: inout [ViewportPatternAffordanceSource.Guide],
        linearAxisHandles: inout [ViewportPatternAffordanceSource.LinearAxisHandle],
        copyCountHandles: inout [ViewportPatternAffordanceSource.CopyCountHandle]
    ) throws {
        try Task.checkCancellation()
        guard patternFinitePoint(basePoint), patternFiniteVector(axis.direction) else {
            throw RealityViewportSpatialBatch.invalid("Pattern linear world guide is not finite.")
        }
        if input.hasRoute {
            sourceGuides.append(.linear(.init(
                title: "Pattern \(name) \(axisSlotTitle(axisSlot))",
                basePoint: basePoint,
                direction: axis.direction,
                distanceMeters: distanceMeters,
                state: .normal
            )))
        }
        if input.linearAxisRouteEnabled {
            let identity = ViewportSpatialHandleIdentity.patternArrayLinearAxis(
                .init(sourceID: sourceID, axisSlot: axisSlot)
            )
            let activeDistance = input.activeLinearAxis.flatMap {
                $0.sourceID == sourceID && $0.axisSlot == axisSlot ? $0.distance : nil
            }
            linearAxisHandles.append(.init(
                sourceID: sourceID,
                axisSlot: axisSlot,
                title: "\(axisSlotTitle(axisSlot)) \(patternDistanceModeTitle(axis.distanceMode))",
                basePoint: basePoint,
                direction: axis.direction,
                distanceMeters: distanceMeters,
                displayDistanceMeters: activeDistance,
                distanceMode: axis.distanceMode,
                state: patternVisualState(for: identity, input: input)
            ))
        }
        if input.copyCountRouteEnabled {
            let slot: ViewportPatternArrayCopyCountSlot
            switch axisSlot {
            case .first: slot = .rectangularFirst
            case .second: slot = .rectangularSecond
            case .radial: slot = .radialAxis
            }
            let identity = ViewportSpatialHandleIdentity.patternArrayCopyCount(
                .init(sourceID: sourceID, slot: slot)
            )
            let activeCopyCount = input.activeCopyCount.flatMap {
                $0.sourceID == sourceID && $0.slot == slot ? $0.copyCount : nil
            }
            copyCountHandles.append(.init(
                sourceID: sourceID,
                slot: slot,
                title: axisSlot == .first ? "Axis 1 Count" : "Axis 2 Count",
                guide: .linear(
                    basePoint: basePoint,
                    direction: axis.direction,
                    distanceMeters: distanceMeters,
                    distanceMode: axis.distanceMode
                ),
                copyCount: axis.copyCount,
                displayCopyCount: activeCopyCount,
                state: patternVisualState(for: identity, input: input)
            ))
        }
        try checkpoint(0, 0, 1)
    }

    private static func resolvedPatternLength(
        _ expression: CADExpression,
        resolver: PatternArrayExpressionResolver,
        label: String
    ) throws -> Double {
        let value: Double
        do {
            value = try resolver.lengthMeters(for: expression)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Pattern \(label) is unresolved.")
        }
        guard value.isFinite, value > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern \(label) is invalid.")
        }
        return value
    }

    private static func resolvedPatternAngle(
        _ expression: CADExpression,
        resolver: PatternArrayExpressionResolver,
        label: String
    ) throws -> Double {
        let value: Double
        do {
            value = try resolver.angleRadians(for: expression)
        } catch {
            throw RealityViewportSpatialBatch.invalid("Pattern \(label) is unresolved.")
        }
        guard value.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Pattern \(label) is invalid.")
        }
        return value
    }

    private static func axisSlotTitle(_ slot: ViewportPatternArrayLinearAxisSlot) -> String {
        switch slot {
        case .first: "Axis 1"
        case .second: "Axis 2"
        case .radial: "Radius"
        }
    }

    private static func patternDistanceModeTitle(_ mode: PatternArrayDistanceMode) -> String {
        switch mode {
        case .spacing: "Spacing"
        case .extent: "Extent"
        }
    }

    private static func patternAngleModeTitle(_ mode: PatternArrayAngleMode) -> String {
        switch mode {
        case .spacing: "Spacing"
        case .extent: "Extent"
        }
    }

    private static func patternVisualState(
        for identity: ViewportSpatialHandleIdentity,
        input: ViewportPatternAffordanceSource.RawInput
    ) -> ViewportPatternAffordanceSource.VisualState {
        .init(
            isActive: input.activeHandleIdentities.contains(where: { $0 == identity }),
            isHighlighted: input.hoveredHandleIdentities.contains(where: { $0 == identity })
                || input.pendingHandleIdentities.contains(where: { $0 == identity })
        )
    }

    private static func makePatternPreviewValues(
        _ previews: [ViewportPatternArrayPreview],
        document: DesignDocument,
        scene: ViewportScene,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [ViewportPatternAffordanceSource.Preview] {
        guard !previews.isEmpty else { return [] }
        try checkpoint(0, 0, scene.items.count)
        let itemByID = Dictionary(uniqueKeysWithValues: scene.items.map { ($0.id, $0) })
        let limits = MeshSourcePresentationPlanLimits.standard
        try checkpoint(0, 0, previews.count)
        var values: [ViewportPatternAffordanceSource.Preview] = []
        values.reserveCapacity(previews.count)
        for preview in previews {
            try Task.checkCancellation()
            guard preview.outputs.count <= limits.maxItemCount,
                  preview.outputCount >= preview.outputs.count else {
                throw RealityViewportSpatialBatch.exhausted()
            }
            var outputs: [ViewportPatternAffordanceSource.PreviewOutput] = []
            outputs.reserveCapacity(preview.outputs.count)
            for output in preview.outputs {
                try Task.checkCancellation()
                try checkpoint(0, 0, output.itemIDs.count)
                guard output.index >= 0, !output.itemIDs.isEmpty else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Pattern-array output has incomplete evaluated world geometry."
                    )
                }
                let items = output.itemIDs.compactMap { itemByID[$0] }
                guard items.count == output.itemIDs.count else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Pattern-array output item identity resolution changed during preparation."
                    )
                }
                var outline: [Point3D] = []
                var centers: [Point3D] = []
                let positionCharge = items.count.multipliedReportingOverflow(by: 8)
                guard !positionCharge.overflow else {
                    throw RealityViewportSpatialBatch.exhausted()
                }
                try checkpoint(0, positionCharge.partialValue, items.count)
                outline.reserveCapacity(items.count * 4)
                centers.reserveCapacity(items.count)
                for item in items {
                    try Task.checkCancellation()
                    let bounds = item.modelBounds
                    guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                          bounds.width.isFinite, bounds.height.isFinite,
                          bounds.width > 0, bounds.height > 0 else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Pattern-array output bounds are invalid."
                        )
                    }
                    let local = [
                        Point3D(x: bounds.minX, y: 0, z: bounds.minY),
                        Point3D(x: bounds.maxX, y: 0, z: bounds.minY),
                        Point3D(x: bounds.maxX, y: 0, z: bounds.maxY),
                        Point3D(x: bounds.minX, y: 0, z: bounds.maxY),
                    ]
                    outline.append(contentsOf: local.map {
                        ViewportLayout.transformedPoint($0, by: item.modelTransform)
                    })
                    centers.append(ViewportLayout.transformedPoint(
                        Point3D(
                            x: (bounds.minX + bounds.maxX) * 0.5,
                            y: 0,
                            z: (bounds.minY + bounds.maxY) * 0.5
                        ),
                        by: item.modelTransform
                    ))
                }
                guard outline.count >= 4,
                      outline.allSatisfy(patternFinitePoint),
                      centers.allSatisfy(patternFinitePoint) else {
                    throw RealityViewportSpatialBatch.invalid(
                        "Pattern-array output has incomplete world bounds."
                    )
                }
                let minX = outline.map(\.x).min() ?? 0
                let maxX = outline.map(\.x).max() ?? 0
                let minZ = outline.map(\.z).min() ?? 0
                let maxZ = outline.map(\.z).max() ?? 0
                let corners = [
                    Point3D(x: minX, y: 0, z: minZ),
                    Point3D(x: maxX, y: 0, z: minZ),
                    Point3D(x: maxX, y: 0, z: maxZ),
                    Point3D(x: minX, y: 0, z: maxZ),
                ]
                let center = centers.reduce(Point3D.origin) { partial, point in
                    Point3D(
                        x: partial.x + point.x / Double(centers.count),
                        y: partial.y + point.y / Double(centers.count),
                        z: partial.z + point.z / Double(centers.count)
                    )
                }
                outputs.append(.init(
                    index: output.index,
                    outline: corners,
                    center: center,
                    isSelected: output.isSelected
                ))
            }
            values.append(.init(
                title: previewTitle(preview, document: document),
                outputCount: preview.outputCount,
                outputs: outputs
            ))
        }
        return values
    }

    private static func previewTitle(
        _ preview: ViewportPatternArrayPreview,
        document: DesignDocument?
    ) -> String {
        document?.productMetadata.patternArrays[preview.sourceID]?.name ?? "Pattern"
    }

    private static func sampledPatternPath(
        _ path: PatternArrayCurvePathGeometry,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [Point3D] {
        guard path.totalLength.isFinite, path.totalLength > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Pattern curve path has no length.")
        }
        let sampleCount = 72
        try checkpoint(0, sampleCount + 1, sampleCount + 1)
        var points: [Point3D] = []
        points.reserveCapacity(sampleCount + 1)
        for index in 0 ... sampleCount {
            try Task.checkCancellation()
            let point: Point3D
            do {
                point = try path.sample(
                    at: path.totalLength * Double(index) / Double(sampleCount)
                ).point
            } catch {
                throw RealityViewportSpatialBatch.invalid("Pattern curve path sampling failed.")
            }
            guard patternFinitePoint(point) else {
                throw RealityViewportSpatialBatch.invalid("Pattern curve path produced a non-finite world point.")
            }
            points.append(point)
        }
        return points
    }

    private static func makeIndependentCopyHandles(
        input: ViewportPatternAffordanceSource.RawInput,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> (
        extrude: [ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle],
        dimension: [ViewportPatternAffordanceSource.IndependentCopyDimensionHandle]
    ) {
        guard input.independentCopyExtrudeRouteEnabled
                || input.independentCopyDimensionRouteEnabled else {
            return ([], [])
        }
        let metadata = input.document.productMetadata
        try checkpoint(0, 0, metadata.patternArrays.count)
        try checkpoint(0, 0, metadata.sceneNodes.count)
        try checkpoint(0, 0, input.scene.items.count)
        let index = try ViewportIndependentCopyOutputSelectionIndex(
            metadata: metadata,
            scene: input.scene,
            checkpoint: checkpoint
        )
        let outputs = index.selectedOutputs(selection: input.selection)
        try checkpoint(0, 0, outputs.count)
        var extrude: [ViewportPatternAffordanceSource.IndependentCopyExtrudeHandle] = []
        var dimension: [ViewportPatternAffordanceSource.IndependentCopyDimensionHandle] = []
        for output in outputs {
            try Task.checkCancellation()
            let ownedFeatureIDs = Set(output.source.outputFeatureIDs)
            let bodyItems = index.bodyItems(
                rootedAt: output.outputSceneNodeID,
                ownedFeatureIDs: ownedFeatureIDs
            )
            try checkpoint(0, 0, bodyItems.count)
            let selectedSceneNodeIDs = Set(input.selection.selectedSceneNodeIDs)
            let selectedItems = bodyItems.filter { item in
                guard let sceneNodeID = item.sceneNodeID else { return false }
                return selectedSceneNodeIDs.contains(sceneNodeID)
            }
            let editableItems = selectedItems.isEmpty ? bodyItems : selectedItems
            if input.independentCopyExtrudeRouteEnabled {
                for item in editableItems {
                    try Task.checkCancellation()
                    guard let feature = input.document.cadDocument.designGraph.nodes[item.featureID],
                          case .extrude(let extrudeFeature) = feature.operation,
                          let localAxis = independentCopyExtrudeAxis(
                            for: extrudeFeature,
                            document: input.document
                          ),
                          let localDistance = independentCopyLength(
                            extrudeFeature.distance,
                            document: input.document
                          ) else {
                        continue
                    }
                    let worldAxis = output.modelTransform.viewportTransformedVector(localAxis)
                    let axisScale = worldAxis.length
                    guard axisScale.isFinite, axisScale > 1.0e-12 else {
                        throw RealityViewportSpatialBatch.invalid(
                            "Independent-copy extrude axis is degenerate."
                        )
                    }
                    let basePoint = independentCopyBasePoint(for: item)
                    let identity = ViewportSpatialHandleIdentity.independentCopyExtrudeDistance(
                        .init(
                            sourceID: output.source.id,
                            outputIndex: output.outputIndex,
                            featureID: item.featureID
                        )
                    )
                    var activeDistance: Double?
                    if let active = input.activeIndependentCopyExtrude,
                       active.sourceID == output.source.id,
                       active.outputIndex == output.outputIndex,
                       active.outputSceneNodeID == output.outputSceneNodeID,
                       active.featureID == item.featureID {
                        let displayDistance = active.distance * axisScale
                        guard displayDistance.isFinite else {
                            throw RealityViewportSpatialBatch.invalid(
                                "Independent-copy extrude drag value is not finite."
                            )
                        }
                        activeDistance = displayDistance
                    }
                    extrude.append(.init(
                        sourceID: output.source.id,
                        outputIndex: output.outputIndex,
                        outputSceneNodeID: output.outputSceneNodeID,
                        featureID: item.featureID,
                        title: "Extrude",
                        basePoint: basePoint,
                        axis: worldAxis,
                        distanceMeters: localDistance * axisScale,
                        displayDistanceMeters: activeDistance,
                        state: patternVisualState(for: identity, input: input)
                    ))
                }
            }
            if input.independentCopyDimensionRouteEnabled {
                let entries = try independentCopyDimensionEntries(
                    items: editableItems,
                    document: input.document
                )
                for item in editableItems {
                    try Task.checkCancellation()
                    for entry in entries where entry.sourceFeatureID == item.featureID.description {
                        guard let descriptor = independentCopyDimensionDescriptor(
                            entry: entry,
                            item: item
                        ) else {
                            continue
                        }
                        let worldAxis = output.modelTransform.viewportTransformedVector(descriptor.axis)
                        let axisScale = worldAxis.length
                        guard axisScale.isFinite, axisScale > 1.0e-12 else {
                            throw RealityViewportSpatialBatch.invalid(
                                "Independent-copy dimension axis is degenerate."
                            )
                        }
                        let identity = ViewportSpatialHandleIdentity.independentCopyBodyDimension(
                            .init(
                                sourceID: output.source.id,
                                outputIndex: output.outputIndex,
                                featureID: item.featureID,
                                kind: descriptor.kind
                            )
                        )
                        var activeValue: Double?
                        if let active = input.activeIndependentCopyDimension,
                           active.sourceID == output.source.id,
                           active.outputIndex == output.outputIndex,
                           active.outputSceneNodeID == output.outputSceneNodeID,
                           active.featureID == item.featureID,
                           active.kind == descriptor.kind {
                            let displayValue = active.value * axisScale
                            guard displayValue.isFinite else {
                                throw RealityViewportSpatialBatch.invalid(
                                    "Independent-copy dimension drag value is not finite."
                                )
                            }
                            activeValue = displayValue
                        }
                        dimension.append(.init(
                            sourceID: output.source.id,
                            outputIndex: output.outputIndex,
                            outputSceneNodeID: output.outputSceneNodeID,
                            featureID: item.featureID,
                            kind: descriptor.kind,
                            label: descriptor.label,
                            basePoint: descriptor.basePoint,
                            axis: worldAxis,
                            valueMeters: entry.resolvedMeters * axisScale,
                            displayValueMeters: activeValue,
                            state: patternVisualState(for: identity, input: input)
                        ))
                    }
                }
            }
        }
        return (extrude, dimension)
    }

    private static func makePatternReplacementValue(
        _ request: ViewportPatternArrayCurvePathReplacementPreviewRequest?,
        document: DesignDocument,
        scene: ViewportScene,
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> ViewportPatternAffordanceSource.Replacement? {
        guard let request else { return nil }
        guard let source = document.productMetadata.patternArrays[request.sourceID],
              case .curve(var curve) = source.distribution else {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern-array replacement source is not a curve."
            )
        }
        let index = ViewportPatternArraySourceSelectionIndex(
            metadata: document.productMetadata,
            scene: scene,
            selection: .empty
        )
        guard let basePoint = try index.sourceBaseModelPoint(
            source: source,
            checkpoint: checkpoint
        ) else {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern-array replacement has no world anchor."
            )
        }
        curve.path = request.path
        let geometry: PatternArrayCurveDistributionGeometry
        do {
            geometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                for: curve,
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
        } catch {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern-array replacement path is unresolved."
            )
        }
        let pathPoints = try sampledPatternPath(geometry.path, checkpoint: checkpoint)
        let transforms: [Transform3D]
        do {
            transforms = try PatternArrayInstancePlanner().transforms(
                for: .curve(curve),
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
        } catch {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern-array replacement outputs are unresolved."
            )
        }
        let limits = MeshSourcePresentationPlanLimits.standard
        guard transforms.count <= limits.maxItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        try checkpoint(0, 0, transforms.count)
        let outputPoints = transforms.map {
            ViewportLayout.transformedPoint(basePoint, by: $0)
        }
        guard outputPoints.allSatisfy(patternFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern-array replacement output point is not finite."
            )
        }
        return .init(
            title: request.title,
            pathPoints: pathPoints,
            outputPoints: outputPoints,
            totalOutputCount: transforms.count
        )
    }

    private static func independentCopyExtrudeAxis(
        for feature: ExtrudeFeature,
        document: DesignDocument
    ) -> Vector3D? {
        switch feature.direction {
        case .normal, .symmetric:
            guard let node = document.cadDocument.designGraph.nodes[feature.profile.featureID],
                  case .sketch(let sketch) = node.operation else {
                return nil
            }
            return independentCopySketchNormal(sketch.plane)
        case .vector(let vector):
            return vector
        }
    }

    private static func independentCopySketchNormal(_ plane: SketchPlane) -> Vector3D? {
        switch plane {
        case .xy: return .unitZ
        case .yz: return .unitX
        case .zx: return .unitY
        case .plane(let plane):
            guard plane.normal.length.isFinite, plane.normal.length > 1.0e-12 else {
                return nil
            }
            return plane.normal
        }
    }

    private static func independentCopyLength(
        _ expression: CADExpression,
        document: DesignDocument
    ) -> Double? {
        do {
            let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
            guard quantity.kind == .length,
                  quantity.value.isFinite,
                  quantity.value > 0 else {
                return nil
            }
            return quantity.value
        } catch {
            return nil
        }
    }

    private static func independentCopyBasePoint(for item: ViewportSceneItem) -> Point3D {
        let y: Double
        if case .body(let component) = item.kind,
           component.yMinMeters.isFinite,
           component.yMaxMeters.isFinite {
            y = (component.yMinMeters + component.yMaxMeters) * 0.5
        } else {
            y = 0
        }
        return Point3D(
            x: Double(item.modelBounds.midX),
            y: y,
            z: Double(item.modelBounds.midY)
        )
    }

    private static func independentCopyDimensionEntries(
        items: [ViewportSceneItem],
        document: DesignDocument
    ) throws -> [ObjectDimensionSummaryResult.Entry] {
        let targets = items.compactMap { item -> SelectionTarget? in
            guard let sceneNodeID = item.sceneNodeID else { return nil }
            return SelectionTarget(sceneNodeID: sceneNodeID)
        }
        guard !targets.isEmpty else { return [] }
        do {
            return try ObjectDimensionSnapshotService().snapshot(
                document: document,
                targets: targets
            ).entries
        } catch {
            throw RealityViewportSpatialBatch.invalid(
                "Independent-copy body dimensions could not be resolved."
            )
        }
    }

    private static func independentCopyDimensionDescriptor(
        entry: ObjectDimensionSummaryResult.Entry,
        item: ViewportSceneItem
    ) -> (kind: ViewportIndependentCopyBodyDimensionKind, label: String, axis: Vector3D, basePoint: Point3D)? {
        guard entry.resolvedMeters.isFinite, entry.resolvedMeters > 0 else { return nil }
        let y: Double
        if case .body(let component) = item.kind,
           component.yMinMeters.isFinite,
           component.yMaxMeters.isFinite {
            y = (component.yMinMeters + component.yMaxMeters) * 0.5
        } else {
            y = 0
        }
        switch (entry.sourceKind, entry.kind) {
        case (.box, .sizeX):
            return (
                .sizeX,
                "X",
                .unitX,
                Point3D(x: Double(item.modelBounds.minX), y: y, z: Double(item.modelBounds.midY))
            )
        case (.box, .sizeZ):
            return (
                .sizeZ,
                "Z",
                .unitZ,
                Point3D(x: Double(item.modelBounds.midX), y: y, z: Double(item.modelBounds.minY))
            )
        case (.cylinder, .radius):
            return (
                .radius,
                "R",
                .unitX,
                Point3D(x: Double(item.modelBounds.midX), y: y, z: Double(item.modelBounds.midY))
            )
        default:
            return nil
        }
    }


    /// Appends every Pattern Array route using world values. Camera-dependent
    /// presentation is limited to native marker, label, and directed camera
    /// line descriptors; no projected point or `ViewportLayout` value crosses
    /// this boundary.
    static func appendPatternAffordances(
        _ source: ViewportPatternAffordanceSource,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        labels: inout [ViewportSpatialOverlayInput.Label],
        markers: inout [ViewportSpatialOverlayInput.Marker],
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        activeFamilies: inout Set<ViewportSpatialOverlayFamily>,
        handleIdentities: inout [ViewportSpatialHandleIdentity],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        let limits = MeshSourcePresentationPlanLimits.standard
        try checkpoint(0, 0, source.guides.count + source.previews.count)
        try checkpoint(
            0,
            0,
            source.linearAxisHandles.count
                + source.radialAngleHandles.count
                + source.copyCountHandles.count
                + source.curveExtentHandles.count
                + source.curvePathPointHandles.count
                + source.outputModeHandles.count
                + source.independentCopyExtrudeHandles.count
                + source.independentCopyDimensionHandles.count
        )
        guard source.guides.count <= limits.maxItemCount,
              source.previews.count <= limits.maxItemCount else {
            throw RealityViewportSpatialBatch.exhausted()
        }

        var emitted = false
        for guide in source.guides {
            try Task.checkCancellation()
            switch guide {
            case .linear(let value):
                let tip = try patternLinearTip(
                    basePoint: value.basePoint,
                    direction: value.direction,
                    distanceMeters: value.distanceMeters
                )
                try appendPatternLine(
                    [value.basePoint, tip],
                    color: patternColor(value.state),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
                try appendPatternLabel(
                    value.title,
                    anchor: tip,
                    toward: value.basePoint,
                    color: patternColor(value.state),
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
                emitted = true
            case .radial(let value):
                let geometry = try patternRadialGeometry(
                    center: value.center,
                    axis: value.axis,
                    referencePoint: value.referencePoint,
                    angleRadians: value.angleRadians
                )
                try appendPatternLine(
                    geometry.arc,
                    color: patternColor(value.state),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
                try appendPatternLine(
                    [value.center, value.referencePoint],
                    color: patternColor(value.state),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
                try appendPatternLine(
                    [value.center, geometry.end],
                    color: patternColor(value.state),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
                try appendPatternLabel(
                    value.title,
                    anchor: geometry.end,
                    toward: value.center,
                    color: patternColor(value.state),
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
                if let radialGuide = value.radialGuide {
                    let tip = try patternLinearTip(
                        basePoint: radialGuide.basePoint,
                        direction: radialGuide.direction,
                        distanceMeters: radialGuide.distanceMeters
                    )
                    try appendPatternLine(
                        [radialGuide.basePoint, tip],
                        color: patternColor(radialGuide.state),
                        depth: .annotation,
                        handleIndex: nil,
                        meshes: &meshes,
                        checkpoint: checkpoint
                    )
                    try appendPatternLabel(
                        radialGuide.title,
                        anchor: tip,
                        toward: radialGuide.basePoint,
                        color: patternColor(radialGuide.state),
                        handleIndex: nil,
                        labels: &labels,
                        checkpoint: checkpoint
                    )
                }
                emitted = true
            case .curve(let value):
                let extent = try patternCurveExtent(
                    pathPoints: value.pathPoints,
                    distanceMeters: value.extentDistanceMeters
                )
                try appendPatternLine(
                    extent.points,
                    color: patternColor(value.state),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
                try appendPatternLabel(
                    value.title,
                    anchor: extent.tip,
                    toward: value.pathPoints[0],
                    color: patternColor(value.state),
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
                emitted = true
            }
        }

        for preview in source.previews {
            try Task.checkCancellation()
            guard preview.outputCount >= preview.outputs.count else {
                throw RealityViewportSpatialBatch.invalid(
                    "Pattern preview output count is smaller than its materialized outputs."
                )
            }
            var centers: [Point3D] = []
            if preview.outputs.count > 1 {
                centers.reserveCapacity(preview.outputs.count)
            }
            for output in preview.outputs {
                try Task.checkCancellation()
                guard output.index >= 0 else {
                    throw RealityViewportSpatialBatch.invalid("Pattern preview output index is invalid.")
                }
                guard patternFinitePoint(output.center) else {
                    throw RealityViewportSpatialBatch.invalid("Pattern preview center is not finite.")
                }
                centers.append(output.center)
                if output.outline.count >= 3 {
                    try appendPatternClosedLine(
                        output.outline,
                        color: output.isSelected
                            ? SIMD4<Float>(1.0, 0.56, 0.18, 0.90)
                            : SIMD4<Float>(0.22, 0.82, 1.0, 0.58),
                        depth: .annotation,
                        handleIndex: nil,
                        meshes: &meshes,
                        checkpoint: checkpoint
                    )
                } else if output.outline.count == 2 {
                    try appendPatternLine(
                        output.outline,
                        color: output.isSelected
                            ? SIMD4<Float>(1.0, 0.56, 0.18, 0.90)
                            : SIMD4<Float>(0.22, 0.82, 1.0, 0.58),
                        depth: .annotation,
                        handleIndex: nil,
                        meshes: &meshes,
                        checkpoint: checkpoint
                    )
                }
                let color = output.isSelected
                    ? SIMD4<Float>(1.0, 0.56, 0.18, 0.90)
                    : SIMD4<Float>(0.22, 0.82, 1.0, 0.58)
                try appendPatternMarker(
                    .sphere,
                    anchor: output.center,
                    diameterPoints: output.isSelected ? 10 : 8,
                    color: color,
                    handleIndex: nil,
                    markers: &markers,
                    checkpoint: checkpoint
                )
                try appendPatternLabel(
                    "\(preview.title) #\(output.index + 1)",
                    anchor: output.center,
                    toward: nil,
                    color: color,
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
                emitted = true
            }
            if centers.count >= 2 {
                try appendPatternLine(
                    centers,
                    color: SIMD4<Float>(0.22, 0.82, 1.0, 0.42),
                    depth: .annotation,
                    handleIndex: nil,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            if let first = centers.first {
                try appendPatternLabel(
                    "\(preview.title) \(preview.outputCount)",
                    anchor: first,
                    toward: nil,
                    color: SIMD4<Float>(0.22, 0.82, 1.0, 0.86),
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
            }
        }

        if let replacement = source.replacement {
            try Task.checkCancellation()
            guard replacement.totalOutputCount >= replacement.outputPoints.count else {
                throw RealityViewportSpatialBatch.invalid(
                    "Pattern replacement output count is smaller than its materialized outputs."
                )
            }
            guard replacement.pathPoints.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid(
                    "Pattern replacement path has fewer than two world points."
                )
            }
            try appendPatternLine(
                replacement.pathPoints,
                color: ViewportSpatialOverlayProducer.referenceColor,
                depth: .annotation,
                handleIndex: nil,
                meshes: &meshes,
                checkpoint: checkpoint
            )
            for point in replacement.outputPoints {
                try appendPatternMarker(
                    .sphere,
                    anchor: point,
                    diameterPoints: 7,
                    color: ViewportSpatialOverlayProducer.referenceColor,
                    handleIndex: nil,
                    markers: &markers,
                    checkpoint: checkpoint
                )
            }
            if let first = replacement.outputPoints.first {
                try appendPatternLabel(
                    "Path Preview \(replacement.title) (\(replacement.totalOutputCount))",
                    anchor: first,
                    toward: nil,
                    color: ViewportSpatialOverlayProducer.referenceColor,
                    handleIndex: nil,
                    labels: &labels,
                    checkpoint: checkpoint
                )
            }
            emitted = true
        }

        for value in source.linearAxisHandles {
            try Task.checkCancellation()
            let displayDistance = value.displayDistanceMeters ?? value.distanceMeters
            let tip = try patternLinearTip(
                basePoint: value.basePoint,
                direction: value.direction,
                distanceMeters: displayDistance
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .patternArrayLinearAxis(.init(sourceID: value.sourceID, axisSlot: value.axisSlot)),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            try appendPatternCameraArrow(
                anchor: value.basePoint,
                toward: tip,
                minimumLength: 76,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayDistanceMeters != nil {
                try appendPatternLine(
                    [value.basePoint, tip],
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.title) \(value.distanceMode.rawValue) \(patternLengthLabel(displayDistance, ruler: source.ruler))",
                anchor: value.basePoint,
                toward: tip,
                projectedMinimumLength: 76,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.radialAngleHandles {
            try Task.checkCancellation()
            let angle = value.displayAngleRadians ?? value.angleRadians
            let geometry = try patternRadialGeometry(
                center: value.center,
                axis: value.axis,
                referencePoint: value.referencePoint,
                angleRadians: angle
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .patternArrayRadialAngle(.init(sourceID: value.sourceID)),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            let tangentPoint = Point3D(
                x: geometry.end.x + geometry.tangent.x,
                y: geometry.end.y + geometry.tangent.y,
                z: geometry.end.z + geometry.tangent.z
            )
            try appendPatternCameraArrow(
                anchor: geometry.end,
                toward: tangentPoint,
                minimumLength: 64,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayAngleRadians != nil {
                try appendPatternLine(
                    geometry.arc,
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.title) \(value.angleMode.rawValue) \(patternAngleLabel(angle))",
                anchor: geometry.end,
                toward: tangentPoint,
                projectedMinimumLength: 64,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.copyCountHandles {
            try Task.checkCancellation()
            let point = try patternCopyCountPoint(
                value.guide,
                copyCount: value.displayCopyCount ?? value.copyCount
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .patternArrayCopyCount(.init(sourceID: value.sourceID, slot: value.slot)),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            let cameraGeometry = try patternCopyCountCameraGeometry(
                value.guide,
                copyCount: value.displayCopyCount ?? value.copyCount
            )
            try appendPatternCameraArrow(
                anchor: cameraGeometry.anchor,
                toward: cameraGeometry.toward,
                minimumLength: 56,
                parallel: cameraGeometry.parallel,
                perpendicular: cameraGeometry.perpendicular,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayCopyCount != nil, let toward = point.toward {
                try appendPatternLine(
                    [toward, point.point],
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.title) \(value.displayCopyCount ?? value.copyCount)",
                anchor: cameraGeometry.anchor,
                toward: cameraGeometry.toward,
                projectedMinimumLength: 56,
                projectedParallel: CGFloat(cameraGeometry.parallel),
                projectedPerpendicular: CGFloat(cameraGeometry.perpendicular),
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.curveExtentHandles {
            try Task.checkCancellation()
            let distance = value.displayDistanceMeters ?? value.distanceMeters
            let extent = try patternCurveExtent(pathPoints: value.pathPoints, distanceMeters: distance)
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .patternArrayCurveExtent(.init(sourceID: value.sourceID)),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            let tangentPoint = Point3D(
                x: extent.tip.x + extent.tangent.x,
                y: extent.tip.y + extent.tangent.y,
                z: extent.tip.z + extent.tangent.z
            )
            try appendPatternCameraArrow(
                anchor: extent.tip,
                toward: tangentPoint,
                minimumLength: 64,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayDistanceMeters != nil {
                try appendPatternLine(
                    extent.points,
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.title) \(value.extentMode == .distance ? patternLengthLabel(distance, ruler: source.ruler) : patternRatioLabel(distance, total: extent.totalLength))",
                anchor: extent.tip,
                toward: tangentPoint,
                projectedMinimumLength: 64,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.curvePathPointHandles {
            try Task.checkCancellation()
            guard value.pointIndex >= 0, value.pointIndex < value.pathPoints.count else {
                throw RealityViewportSpatialBatch.invalid("Pattern path-point handle index is invalid.")
            }
            guard value.pathPoints.count >= 2 else {
                throw RealityViewportSpatialBatch.invalid("Pattern path has fewer than two world points.")
            }
            var effectivePathPoints = value.pathPoints
            if let activePoint = value.activePoint,
               patternFinitePoint(activePoint),
               value.pointIndex >= 0,
               value.pointIndex < effectivePathPoints.count {
                effectivePathPoints[value.pointIndex] = activePoint
            }
            try appendPatternLine(
                effectivePathPoints,
                color: ViewportSpatialOverlayProducer.referenceColor,
                depth: .annotation,
                handleIndex: nil,
                meshes: &meshes,
                checkpoint: checkpoint
            )
            let point = effectivePathPoints[value.pointIndex]
            let identity = ViewportSpatialHandleIdentity.patternArrayCurvePathPoint(
                .init(sourceID: value.sourceID, pointIndex: value.pointIndex)
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: identity,
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            try appendPatternMarker(
                .sphere,
                anchor: point,
                diameterPoints: value.state.isActive ? 10 : 8,
                color: color,
                handleIndex: index,
                markers: &markers,
                checkpoint: checkpoint
            )
            try appendPatternLabel(
                value.title,
                anchor: point,
                toward: value.pointIndex > 0 ? effectivePathPoints[value.pointIndex - 1] : nil,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.outputModeHandles {
            try Task.checkCancellation()
            guard patternFinitePoint(value.anchor) else {
                throw RealityViewportSpatialBatch.invalid("Pattern output-mode anchor is not finite.")
            }
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .patternArrayOutputMode(.init(sourceID: value.sourceID)),
                in: &handleIdentities
            )
            try appendPatternLabel(
                value.state.isHighlighted ? value.highlightedTitle : value.title,
                anchor: value.anchor,
                toward: nil,
                fixedOffset: CGPoint(x: 46, y: -34),
                color: patternColor(value.state),
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.independentCopyExtrudeHandles {
            try Task.checkCancellation()
            let distance = value.displayDistanceMeters ?? value.distanceMeters
            let tip = try patternLinearTip(
                basePoint: value.basePoint,
                direction: value.axis,
                distanceMeters: distance
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .independentCopyExtrudeDistance(.init(
                    sourceID: value.sourceID,
                    outputIndex: value.outputIndex,
                    featureID: value.featureID
                )),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            try appendPatternCameraArrow(
                anchor: value.basePoint,
                toward: tip,
                minimumLength: 70,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayDistanceMeters != nil {
                try appendPatternLine(
                    [value.basePoint, tip],
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.title) \(patternLengthLabel(distance, ruler: source.ruler))",
                anchor: value.basePoint,
                toward: tip,
                projectedMinimumLength: 70,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        for value in source.independentCopyDimensionHandles {
            try Task.checkCancellation()
            let distance = value.displayValueMeters ?? value.valueMeters
            let tip = try patternLinearTip(
                basePoint: value.basePoint,
                direction: value.axis,
                distanceMeters: distance
            )
            let index = try ViewportSpatialOverlayProducer.handleIndex(
                for: .independentCopyBodyDimension(.init(
                    sourceID: value.sourceID,
                    outputIndex: value.outputIndex,
                    featureID: value.featureID,
                    kind: value.kind
                )),
                in: &handleIdentities
            )
            let color = patternColor(value.state)
            try appendPatternCameraArrow(
                anchor: value.basePoint,
                toward: tip,
                minimumLength: 58,
                color: color,
                handleIndex: index,
                cameraLines: &cameraLines,
                cameraPaths: &cameraPaths,
                checkpoint: checkpoint
            )
            if value.displayValueMeters != nil {
                try appendPatternLine(
                    [value.basePoint, tip],
                    color: color,
                    depth: .annotation,
                    handleIndex: index,
                    meshes: &meshes,
                    checkpoint: checkpoint
                )
            }
            try appendPatternLabel(
                "\(value.label) \(patternLengthLabel(distance, ruler: source.ruler))",
                anchor: value.basePoint,
                toward: tip,
                projectedMinimumLength: 58,
                color: color,
                handleIndex: index,
                labels: &labels,
                checkpoint: checkpoint
            )
            emitted = true
        }

        guard !source.hasRoute || emitted else {
            throw RealityViewportSpatialBatch.invalid(
                "The active Pattern Array route has no native world descriptor."
            )
        }
        if emitted {
            activeFamilies.insert(.pattern)
        }
    }

    private static func appendPatternLine(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth,
        handleIndex: UInt32?,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        guard points.count >= 2,
              points.allSatisfy(patternFinitePoint) else {
            throw RealityViewportSpatialBatch.invalid("Pattern line has invalid world topology.")
        }
        try checkpoint(1, points.count, 0)
        var value = try ViewportSpatialOverlayProducer.line(points, color: color, depth: depth)
        value.handleIndex = handleIndex
        meshes.append(.init(family: .pattern, value: value))
    }

    private static func appendPatternClosedLine(
        _ points: [Point3D],
        color: SIMD4<Float>,
        depth: RealityViewportSpatialBatch.Depth,
        handleIndex: UInt32?,
        meshes: inout [ViewportSpatialOverlayInput.Mesh],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        guard points.count >= 3 else {
            throw RealityViewportSpatialBatch.invalid("Pattern outline has fewer than three points.")
        }
        try appendPatternLine(
            points + [points[0]],
            color: color,
            depth: depth,
            handleIndex: handleIndex,
            meshes: &meshes,
            checkpoint: checkpoint
        )
    }

    /// Emits the constant-pixel arrow used by an interactive Pattern handle.
    /// The CAD anchor and direction remain world values; RealityKit resolves
    /// the projected direction and point-space length for every camera frame.
    private static func appendPatternCameraArrow(
        anchor: Point3D,
        toward: Point3D,
        minimumLength: Double,
        parallel: Double = 0,
        perpendicular: Double = 0,
        shape: RealityViewportSpatialBatch.Marker.Shape = .sphere,
        color: SIMD4<Float>,
        handleIndex: UInt32,
        cameraLines: inout [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: inout [ViewportSpatialOverlayInput.CameraPath],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        guard patternFinitePoint(anchor), patternFinitePoint(toward),
              anchor.x != toward.x || anchor.y != toward.y || anchor.z != toward.z,
              minimumLength.isFinite, minimumLength >= 0,
              parallel.isFinite,
              perpendicular.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "Pattern camera handle direction or length is invalid."
            )
        }
        let minimumLength = CGFloat(minimumLength)
        let parallel = CGFloat(parallel)
        let shaft = max(minimumLength, 18)
        let wingLength = min(max(shaft * 0.22, 6), 14)
        let wingParallel = max(shaft - wingLength, 0)
        let offset: (CGFloat, CGFloat) -> RealityViewportSpatialBatch.Offset = { parallel, perpendicular in
            .projected(
                toward: toward,
                minimumLength: minimumLength,
                parallel: parallel,
                perpendicular: perpendicular
            )
        }
        let points = [
            RealityViewportSpatialBatch.CameraPoint(
                anchor: anchor,
                offset: .fixed(.zero)
            ),
            RealityViewportSpatialBatch.CameraPoint(
                anchor: anchor,
                offset: offset(shaft, CGFloat(perpendicular))
            ),
            RealityViewportSpatialBatch.CameraPoint(
                anchor: anchor,
                offset: offset(wingParallel, CGFloat(perpendicular) + wingLength * 0.55)
            ),
            RealityViewportSpatialBatch.CameraPoint(
                anchor: anchor,
                offset: offset(shaft, CGFloat(perpendicular))
            ),
            RealityViewportSpatialBatch.CameraPoint(
                anchor: anchor,
                offset: offset(wingParallel, CGFloat(perpendicular) - wingLength * 0.55)
            ),
        ]
        // One line, five camera points, and one direction reference per point
        // are admitted before the native batch repeats the same validation.
        try checkpoint(11, 10, 0)
        var value = RealityViewportSpatialBatch.CameraLine(
            points: points,
            color: color,
            depth: .annotation
        )
        value.handleIndex = handleIndex
        cameraLines.append(.init(family: .pattern, value: value))

        let glyphBounds = CGRect(x: -5, y: -5, width: 10, height: 10)
        let glyphPath: Path
        switch shape {
        case .sphere:
            glyphPath = Path(ellipseIn: glyphBounds)
        case .box:
            glyphPath = Path(roundedRect: glyphBounds, cornerRadius: 1.5)
        }
        var glyph = RealityViewportSpatialBatch.CameraPath(
            path: glyphPath,
            anchor: anchor,
            offset: .projected(
                toward: toward,
                minimumLength: minimumLength,
                parallel: parallel,
                perpendicular: perpendicular
            ),
            color: color
        )
        glyph.handleIndex = handleIndex
        try checkpoint(2, cameraPathPointCount(glyphPath) + 1, 1)
        cameraPaths.append(.init(family: .pattern, value: glyph))
    }

    private static func cameraPathPointCount(_ path: Path) -> Int {
        var count = 0
        path.forEach { element in
            switch element {
            case .move, .line:
                count += 1
            case .quadCurve:
                count += 2
            case .curve:
                count += 3
            case .closeSubpath:
                break
            }
        }
        return count
    }

    private static func appendPatternMarker(
        _ shape: RealityViewportSpatialBatch.Marker.Shape,
        anchor: Point3D,
        diameterPoints: Float,
        color: SIMD4<Float>,
        handleIndex: UInt32?,
        markers: inout [ViewportSpatialOverlayInput.Marker],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        guard patternFinitePoint(anchor), diameterPoints.isFinite, diameterPoints > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern marker has invalid world placement.")
        }
        try checkpoint(1, 0, 0)
        var value = ViewportSpatialOverlayProducer.marker(
            shape,
            anchor: anchor,
            diameterPoints: diameterPoints,
            color: color
        )
        value.handleIndex = handleIndex
        markers.append(.init(family: .pattern, value: value))
    }

    private static func appendPatternLabel(
        _ text: String,
        anchor: Point3D,
        toward: Point3D?,
        projectedMinimumLength: CGFloat? = nil,
        projectedParallel: CGFloat = 0,
        projectedPerpendicular: CGFloat = -10,
        fixedOffset: CGPoint? = nil,
        color: SIMD4<Float>,
        handleIndex: UInt32?,
        labels: inout [ViewportSpatialOverlayInput.Label],
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws {
        try Task.checkCancellation()
        guard !text.isEmpty, patternFinitePoint(anchor) else {
            throw RealityViewportSpatialBatch.invalid("Pattern label has invalid content or placement.")
        }
        try checkpoint(1, text.unicodeScalars.count, 0)
        let offset: RealityViewportSpatialBatch.Offset
        if let projectedMinimumLength {
            guard let toward,
                  patternFinitePoint(toward),
                  toward.x != anchor.x || toward.y != anchor.y || toward.z != anchor.z,
                  projectedMinimumLength.isFinite, projectedMinimumLength >= 0,
                  projectedParallel.isFinite, projectedPerpendicular.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Pattern label projected placement is invalid.")
            }
            offset = .projected(
                toward: toward,
                minimumLength: projectedMinimumLength,
                parallel: projectedParallel,
                perpendicular: projectedPerpendicular
            )
        } else if let fixedOffset {
            guard fixedOffset.x.isFinite, fixedOffset.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Pattern label offset is not finite.")
            }
            offset = .fixed(fixedOffset)
        } else if let toward,
           patternFinitePoint(toward),
           toward.x != anchor.x || toward.y != anchor.y || toward.z != anchor.z {
            offset = .directed(toward: toward, parallel: 8, perpendicular: -10)
        } else {
            offset = .fixed(CGPoint(x: 8, y: -10))
        }
        var value = RealityViewportSpatialBatch.Label(
            text: text,
            anchor: anchor,
            offset: offset,
            heightPoints: 9,
            color: color
        )
        value.handleIndex = handleIndex
        labels.append(.init(family: .pattern, value: value))
    }

    private static func patternColor(
        _ state: ViewportPatternAffordanceSource.VisualState
    ) -> SIMD4<Float> {
        if state.isActive { return ViewportSpatialOverlayProducer.editColor }
        if state.isHighlighted { return ViewportSpatialOverlayProducer.hoverColor }
        return ViewportSpatialOverlayProducer.referenceColor
    }

    private static func patternFinitePoint(_ point: Point3D) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    private static func patternFiniteVector(_ vector: Vector3D) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func patternLinearTip(
        basePoint: Point3D,
        direction: Vector3D,
        distanceMeters: Double
    ) throws -> Point3D {
        guard patternFinitePoint(basePoint), patternFiniteVector(direction),
              distanceMeters.isFinite, distanceMeters > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern linear guide is invalid.")
        }
        let length = direction.length
        guard length.isFinite, length > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Pattern linear guide direction is degenerate.")
        }
        let result = Point3D(
            x: basePoint.x + direction.x / length * distanceMeters,
            y: basePoint.y + direction.y / length * distanceMeters,
            z: basePoint.z + direction.z / length * distanceMeters
        )
        guard patternFinitePoint(result) else {
            throw RealityViewportSpatialBatch.invalid("Pattern linear guide tip is not finite.")
        }
        return result
    }

    private static func patternRadialGeometry(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        angleRadians: Double
    ) throws -> (arc: [Point3D], end: Point3D, radius: Double, tangent: Vector3D) {
        guard patternFinitePoint(center), patternFinitePoint(referencePoint),
              patternFiniteVector(axis), angleRadians.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Pattern radial guide is invalid.")
        }
        let axisLength = axis.length
        guard axisLength.isFinite, axisLength > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Pattern radial axis is degenerate.")
        }
        let unitAxis = Vector3D(x: axis.x / axisLength, y: axis.y / axisLength, z: axis.z / axisLength)
        let raw = Vector3D(
            x: referencePoint.x - center.x,
            y: referencePoint.y - center.y,
            z: referencePoint.z - center.z
        )
        let axial = raw.x * unitAxis.x + raw.y * unitAxis.y + raw.z * unitAxis.z
        let radial = Vector3D(
            x: raw.x - unitAxis.x * axial,
            y: raw.y - unitAxis.y * axial,
            z: raw.z - unitAxis.z * axial
        )
        let radius = radial.length
        guard radius.isFinite, radius > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Pattern radial source has no radius.")
        }
        let segments = min(max(Int(abs(angleRadians) / (.pi / 18.0)), 12), 96)
        var arc: [Point3D] = []
        arc.reserveCapacity(segments + 1)
        for index in 0 ... segments {
            try Task.checkCancellation()
            let angle = angleRadians * Double(index) / Double(segments)
            arc.append(patternRotatedPoint(center, vector: radial, axis: unitAxis, angle: angle))
        }
        guard let end = arc.last, patternFinitePoint(end) else {
            throw RealityViewportSpatialBatch.invalid("Pattern radial guide endpoint is not finite.")
        }
        let tangent = patternCross(unitAxis, radial)
        guard tangent.length.isFinite, tangent.length > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Pattern radial guide tangent is degenerate.")
        }
        return (arc, end, radius, tangent)
    }

    private static func patternCurveExtent(
        pathPoints: [Point3D],
        distanceMeters: Double
    ) throws -> (points: [Point3D], tip: Point3D, tangent: Vector3D, totalLength: Double) {
        guard pathPoints.count >= 2,
              pathPoints.allSatisfy(patternFinitePoint),
              distanceMeters.isFinite, distanceMeters > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern curve extent is invalid.")
        }
        var totalLength = 0.0
        for index in 1 ..< pathPoints.count {
            let span = patternVector(from: pathPoints[index - 1], to: pathPoints[index]).length
            guard span.isFinite, span > 1.0e-12 else {
                throw RealityViewportSpatialBatch.invalid("Pattern curve path contains a degenerate span.")
            }
            totalLength += span
        }
        guard totalLength.isFinite, totalLength > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern curve path has no length.")
        }
        let distance = min(max(distanceMeters, 0), totalLength)
        var consumed = 0.0
        var points: [Point3D] = [pathPoints[0]]
        for index in 1 ..< pathPoints.count {
            let previous = pathPoints[index - 1]
            let next = pathPoints[index]
            let spanVector = patternVector(from: previous, to: next)
            let span = spanVector.length
            if consumed + span >= distance {
                let ratio = span > 1.0e-12 ? (distance - consumed) / span : 0
                let tip = Point3D(
                    x: previous.x + spanVector.x * ratio,
                    y: previous.y + spanVector.y * ratio,
                    z: previous.z + spanVector.z * ratio
                )
                if let last = points.last,
                   last.x == tip.x, last.y == tip.y, last.z == tip.z {
                    // The tip is already represented by the last source point.
                } else {
                    points.append(tip)
                }
                return (points, tip, patternNormalized(spanVector), totalLength)
            }
            points.append(next)
            consumed += span
        }
        let last = pathPoints[pathPoints.count - 1]
        let tangent = patternNormalized(patternVector(from: pathPoints[pathPoints.count - 2], to: last))
        return (points, last, tangent, totalLength)
    }

    private static func patternCopyCountPoint(
        _ guide: ViewportPatternAffordanceSource.CopyCountGuide,
        copyCount: Int
    ) throws -> (point: Point3D, toward: Point3D?) {
        guard copyCount > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern copy count must be positive.")
        }
        switch guide {
        case .linear(let basePoint, let direction, let distanceMeters, let mode):
            let distance = mode == .spacing ? distanceMeters * Double(copyCount) : distanceMeters
            let tip = try patternLinearTip(basePoint: basePoint, direction: direction, distanceMeters: distance)
            return (tip, basePoint)
        case .radial(let center, let axis, let referencePoint, let angleRadians, let mode):
            let angle = mode == .spacing ? angleRadians * Double(copyCount) : angleRadians
            let geometry = try patternRadialGeometry(
                center: center,
                axis: axis,
                referencePoint: referencePoint,
                angleRadians: angle
            )
            return (geometry.end, center)
        case .curve(let pathPoints, let extentDistanceMeters):
            let extent = try patternCurveExtent(pathPoints: pathPoints, distanceMeters: extentDistanceMeters)
            let spacing = max(extent.totalLength * 0.08, 0.01)
            let point = Point3D(
                x: extent.tip.x + extent.tangent.x * spacing * Double(copyCount),
                y: extent.tip.y + extent.tangent.y * spacing * Double(copyCount),
                z: extent.tip.z + extent.tangent.z * spacing * Double(copyCount)
            )
            guard patternFinitePoint(point) else {
                throw RealityViewportSpatialBatch.invalid("Pattern curve copy-count handle is not finite.")
            }
            return (point, extent.tip)
        }
    }

    private static func patternCopyCountCameraGeometry(
        _ guide: ViewportPatternAffordanceSource.CopyCountGuide,
        copyCount: Int
    ) throws -> (anchor: Point3D, toward: Point3D, parallel: Double, perpendicular: Double) {
        guard copyCount > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern copy count must be positive.")
        }
        let parallel = 28.0 * Double(copyCount)
        guard parallel.isFinite, parallel > 0 else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        switch guide {
        case .linear(let basePoint, let direction, let distanceMeters, let mode):
            let distance = mode == .spacing ? distanceMeters * Double(copyCount) : distanceMeters
            let tip = try patternLinearTip(
                basePoint: basePoint,
                direction: direction,
                distanceMeters: distance
            )
            return (
                basePoint,
                tip,
                parallel,
                mode == .extent ? 24 : 0
            )
        case .radial(let center, let axis, let referencePoint, let angleRadians, let mode):
            let angle = mode == .spacing ? angleRadians * Double(copyCount) : angleRadians
            let geometry = try patternRadialGeometry(
                center: center,
                axis: axis,
                referencePoint: referencePoint,
                angleRadians: angle
            )
            let toward = Point3D(
                x: geometry.end.x + geometry.tangent.x,
                y: geometry.end.y + geometry.tangent.y,
                z: geometry.end.z + geometry.tangent.z
            )
            return (
                geometry.end,
                toward,
                parallel,
                mode == .extent ? 24 : 0
            )
        case .curve(let pathPoints, let extentDistanceMeters):
            let extent = try patternCurveExtent(
                pathPoints: pathPoints,
                distanceMeters: extentDistanceMeters
            )
            let toward = Point3D(
                x: extent.tip.x + extent.tangent.x,
                y: extent.tip.y + extent.tangent.y,
                z: extent.tip.z + extent.tangent.z
            )
            return (extent.tip, toward, parallel, 24)
        }
    }

    private static func patternLengthLabel(
        _ meters: Double,
        ruler: RulerConfiguration
    ) -> String {
        ViewportLengthLabelFormatter.string(
            fromMeters: meters,
            preferredUnit: ruler.displayUnit
        )
    }

    private static func patternAngleLabel(_ radians: Double) -> String {
        let degrees = radians * 180.0 / Double.pi
        return "\(degrees.formatted(.number.precision(.fractionLength(0...1)))) deg"
    }

    private static func patternRatioLabel(_ distance: Double, total: Double) -> String {
        guard total.isFinite, total > 0, distance.isFinite else { return "0%" }
        return "\(Int((distance / total * 100.0).rounded()))%"
    }

    private static func patternVector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
    }

    private static func patternNormalized(_ vector: Vector3D) -> Vector3D {
        let length = vector.length
        guard length.isFinite, length > 1.0e-12 else { return .unitX }
        return Vector3D(x: vector.x / length, y: vector.y / length, z: vector.z / length)
    }

    private static func patternCross(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    private static func patternRotatedPoint(
        _ center: Point3D,
        vector: Vector3D,
        axis: Vector3D,
        angle: Double
    ) -> Point3D {
        let cosine = cos(angle)
        let sine = sin(angle)
        let cross = patternCross(axis, vector)
        let dot = axis.x * vector.x + axis.y * vector.y + axis.z * vector.z
        let rotated = Vector3D(
            x: vector.x * cosine + cross.x * sine + axis.x * dot * (1 - cosine),
            y: vector.y * cosine + cross.y * sine + axis.y * dot * (1 - cosine),
            z: vector.z * cosine + cross.z * sine + axis.z * dot * (1 - cosine)
        )
        return Point3D(
            x: center.x + rotated.x,
            y: center.y + rotated.y,
            z: center.z + rotated.z
        )
    }
}

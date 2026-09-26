import RupaCore

/// Builds the one Core command that arrays the selected objects, with the values each kind starts
/// from before the user edits them in the array inspector.
///
/// Core reads an array's distribution in the frame of the selection's parent, so world-space picks
/// (a radial center, an axis) are expressed in that frame here.
struct WorkspacePatternArrayCreationPlanner {
    enum Kind: String, CaseIterable, Sendable {
        case rectangular
        case radial
        case curve

        var title: String {
            switch self {
            case .rectangular: "Rectangular Array"
            case .radial: "Radial Array"
            case .curve: "Curve Array"
            }
        }
    }

    /// Copies added beside the original by a new rectangular or curve array.
    static let initialLinearCopyCount = 3
    /// Copies added around the center by a new radial array, closing a ring at the spacing angle.
    static let initialRadialCopyCount = 5
    static let initialRadialSpacingDegrees = 60.0

    let metadata: ProductMetadata

    /// The lowest free numbered name for a new array of `kind`.
    func name(for kind: Kind) -> String {
        let taken = Set(metadata.patternArrays.values.map(\.name))
        guard taken.contains(kind.title) else {
            return kind.title
        }
        var ordinal = 2
        while taken.contains("\(kind.title) \(ordinal)") {
            ordinal += 1
        }
        return "\(kind.title) \(ordinal)"
    }

    /// Copies along the parent's X axis, spaced one and a half selection widths apart so the copies
    /// start clear of each other.
    func rectangular(
        rootSceneNodeIDs: [SceneNodeID],
        selectionBounds: MeasurementResult.Bounds
    ) throws -> EditorCommand {
        let sizes = [
            selectionBounds.maxX - selectionBounds.minX,
            selectionBounds.maxY - selectionBounds.minY,
            selectionBounds.maxZ - selectionBounds.minZ,
        ]
        let width = sizes[0] > ModelingTolerance.standard.distance ? sizes[0] : (sizes.max() ?? 0)
        guard width.isFinite, width > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "A rectangular array needs a selection with a measurable size.")
        }
        return .createPatternArrayFromSceneNodes(
            name: name(for: .rectangular),
            rootSceneNodeIDs: rootSceneNodeIDs,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(width * 1.5, .meter),
                    copyCount: Self.initialLinearCopyCount
                )
            )),
            outputMode: .independentCopy
        )
    }

    /// A ring around `centerWorld` turning about `axisWorld`.
    func radial(
        rootSceneNodeIDs: [SceneNodeID],
        centerWorld: Point3D,
        axisWorld: Vector3D
    ) throws -> EditorCommand {
        let parentWorld = try parentWorldTransform(of: rootSceneNodeIDs)
        return .createPatternArrayFromSceneNodes(
            name: name(for: .radial),
            rootSceneNodeIDs: rootSceneNodeIDs,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: try parentWorld.inverse().applied(to: centerWorld),
                    axis: try parentWorld.inverseApplyingLinearPart(to: axisWorld),
                    angle: .angle(Self.initialRadialSpacingDegrees, .degree),
                    copyCount: Self.initialRadialCopyCount
                )
            )),
            outputMode: .independentCopy
        )
    }

    /// Copies spread along the whole of `path`.
    func curve(
        rootSceneNodeIDs: [SceneNodeID],
        path: PatternArrayCurvePath
    ) -> EditorCommand {
        .createPatternArrayFromSceneNodes(
            name: name(for: .curve),
            rootSceneNodeIDs: rootSceneNodeIDs,
            distribution: .curve(CurvePatternArray(path: path, copyCount: Self.initialLinearCopyCount)),
            outputMode: .independentCopy
        )
    }

    private func parentWorldTransform(of rootSceneNodeIDs: [SceneNodeID]) throws -> Transform3D {
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        guard let firstRoot = hierarchy.outermostSceneNodeIDs(among: rootSceneNodeIDs).first else {
            throw EditorError(code: .commandInvalid, message: "An array needs at least one selected object.")
        }
        return try hierarchy.parentWorldTransform(of: firstRoot)
    }
}

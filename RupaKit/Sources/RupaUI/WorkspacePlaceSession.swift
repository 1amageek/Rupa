import RupaCore

/// Place in progress: the objects being placed, the source reference once picked, and the options
/// every placement from this session uses.
///
/// The source reference is picked once; every destination click then places the objects and the
/// session keeps waiting for the next destination until it is withdrawn, so one source can be
/// placed repeatedly.
struct WorkspacePlaceSession: Equatable, Sendable {
    /// A picked reference point and, when it lies on a surface or plane, the outward normal there.
    struct Reference: Equatable, Sendable {
        var point: Point3D
        var normal: Vector3D?
        /// The scene node presenting the body the point lies on, which a Boolean combines with.
        var bodySceneNodeID: SceneNodeID? = nil
    }

    enum Phase: Equatable, Sendable {
        case source
        case destination(source: Reference)
    }

    /// What each placement inserts: the selected objects, or objects copied with placement.
    enum Source: Equatable, Sendable {
        case selection([SceneNodeID])
        case pasted(SceneFragment)
    }

    let source: Source
    var phase: Phase = .source
    var upAxis: SceneNodePlacementSpec.UpAxis = .z
    var flipsOrientation = false
    var angleDegrees = 0.0
    var scale = 1.0
    /// Copies placed per destination click; each further copy repeats the placement once more.
    var copyCount = 1
    var output: SceneNodePlacementOutput = .independentCopy
    /// The Boolean each placed copy makes with the body under the destination, `nil` for a new body.
    var booleanOperation: BooleanOperation?

    init(rootSceneNodeIDs: [SceneNodeID]) {
        source = .selection(rootSceneNodeIDs)
    }

    /// Pastes copied objects: the reference point they were copied at is the source.
    init(pasting payload: WorkspaceScenePlacementPayload) {
        source = .pasted(payload.fragment)
        phase = .destination(source: Reference(point: payload.basePoint, normal: payload.baseNormal))
    }

    /// Pasted objects are always independent copies; only a selection can be placed as instances.
    var allowsInstances: Bool {
        if case .selection = source { return true }
        return false
    }

    var prompt: String {
        switch phase {
        case .source:
            "Place: click the reference point on the objects. Esc cancels."
        case .destination:
            "Place: click where the reference point goes. F flips, I toggles instances, X/Y/Z sets the up axis, D adds a copy, Q/W/Shift-E union/difference/intersect with the body clicked, B places a new body."
        }
    }

    mutating func pickSource(_ reference: Reference) {
        phase = .destination(source: reference)
    }

    /// The command placing the objects with `destination` as the target reference.
    func command(destination: Reference) throws -> EditorCommand {
        guard case .destination(let reference) = phase else {
            throw EditorError(code: .commandInvalid, message: "Place needs its source reference point first.")
        }
        guard copyCount >= 1 else {
            throw EditorError(code: .commandInvalid, message: "Place needs at least one copy.")
        }
        let placement = try SceneNodePlacementSpec(
            sourcePoint: reference.point,
            sourceNormal: reference.normal,
            destinationPoint: destination.point,
            destinationNormal: destination.normal,
            upAxis: upAxis,
            flipsOrientation: flipsOrientation,
            angleRadians: angleDegrees * .pi / 180,
            scale: scale
        ).transform()
        // Consecutive copies repeat the placement: the second copy is placed from the first, and so on.
        var placements = [placement]
        while placements.count < copyCount {
            placements.append(try placement.composed(with: placements[placements.count - 1]))
        }
        var boolean: SceneNodePlacementBoolean?
        if let booleanOperation {
            guard let target = destination.bodySceneNodeID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A \(booleanOperation.rawValue) placement needs a destination on a body."
                )
            }
            boolean = SceneNodePlacementBoolean(operation: booleanOperation, targetSceneNodeID: target)
        }
        switch self.source {
        case .selection(let ids):
            return .placeSceneNodes(
                ids: ids,
                placements: placements,
                output: boolean == nil ? output : .independentCopy,
                boolean: boolean
            )
        case .pasted(let fragment):
            return .pasteSceneFragment(fragment, placements: placements, boolean: boolean)
        }
    }
}

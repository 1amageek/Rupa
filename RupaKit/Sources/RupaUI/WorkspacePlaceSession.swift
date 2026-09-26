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
    }

    enum Phase: Equatable, Sendable {
        case source
        case destination(source: Reference)
    }

    let rootSceneNodeIDs: [SceneNodeID]
    var phase: Phase = .source
    var upAxis: SceneNodePlacementSpec.UpAxis = .z
    var flipsOrientation = false
    var angleDegrees = 0.0
    var scale = 1.0
    /// Copies placed per destination click; each further copy repeats the placement once more.
    var copyCount = 1
    var output: SceneNodePlacementOutput = .independentCopy

    init(rootSceneNodeIDs: [SceneNodeID]) {
        self.rootSceneNodeIDs = rootSceneNodeIDs
    }

    var prompt: String {
        switch phase {
        case .source:
            "Place: click the reference point on the objects. Esc cancels."
        case .destination:
            "Place: click where the reference point goes. F flips, I toggles instances, X/Y/Z sets the up axis, D adds a copy."
        }
    }

    mutating func pickSource(_ reference: Reference) {
        phase = .destination(source: reference)
    }

    /// The command placing the objects with `destination` as the target reference.
    func command(destination: Reference) throws -> EditorCommand {
        guard case .destination(let source) = phase else {
            throw EditorError(code: .commandInvalid, message: "Place needs its source reference point first.")
        }
        guard copyCount >= 1 else {
            throw EditorError(code: .commandInvalid, message: "Place needs at least one copy.")
        }
        let placement = try SceneNodePlacementSpec(
            sourcePoint: source.point,
            sourceNormal: source.normal,
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
        return .placeSceneNodes(ids: rootSceneNodeIDs, placements: placements, output: output)
    }
}

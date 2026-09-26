import RupaCore

/// Mirror in progress: the objects, the plane chosen so far and the dialog options.
///
/// The plane starts at the construction plane's positive X; axis keys, a click on a face or two
/// freestyle clicks replace it. Return applies the mirror once and ends the session.
struct WorkspaceMirrorSession: Equatable, Sendable {
    /// The whole-object selection the session mirrors, in selection order.
    let sceneNodeIDs: [SceneNodeID]
    var plane: SceneMirrorPlane
    /// How the plane was chosen, for the panel and the status line.
    var planeName: String
    var options = SceneMirrorOptions()
    /// Freestyle points picked so far; `nil` unless freestyle is running.
    var freestylePoints: [Point3D]?

    init(sceneNodeIDs: [SceneNodeID], constructionPlane: SketchPlane) throws {
        self.sceneNodeIDs = sceneNodeIDs
        plane = try .axis(.x, positive: true, constructionPlane: constructionPlane)
        planeName = "+X"
    }

    /// X/Y/Z mirror toward the positive side of that construction-plane axis; Shift toward the negative.
    mutating func choose(axis: SceneTransformAxis, positive: Bool, constructionPlane: SketchPlane) throws {
        plane = try .axis(axis, positive: positive, constructionPlane: constructionPlane)
        planeName = (positive ? "+" : "−") + axis.rawValue.uppercased()
        freestylePoints = nil
    }

    /// A click on a face mirrors across the plane tangent to it there, toward its outward normal.
    mutating func choose(facePoint point: Point3D, normal: Vector3D) throws {
        plane = try SceneMirrorPlane(origin: point, normal: normal)
        planeName = "Face"
    }

    mutating func beginFreestyle() {
        freestylePoints = []
    }

    /// Adds a freestyle point; the second one sets the plane through the line and the construction
    /// plane normal.
    mutating func addFreestylePoint(_ point: Point3D, constructionPlane: SketchPlane) throws {
        var points = freestylePoints ?? []
        points.append(point)
        guard points.count == 2 else {
            freestylePoints = points
            return
        }
        plane = try .freestyle(start: points[0], end: points[1], constructionPlane: constructionPlane)
        planeName = "Freestyle"
        freestylePoints = nil
    }

    /// I toggles instances; making instances and joining halves exclude each other.
    mutating func toggleInstances() {
        options.makesInstances.toggle()
        if options.makesInstances { options.unionsHalves = false }
    }

    /// Q toggles joining the halves.
    mutating func toggleUnion() {
        options.unionsHalves.toggle()
        if options.unionsHalves { options.makesInstances = false }
    }

    var command: EditorCommand {
        .mirrorSceneNodes(ids: sceneNodeIDs, plane: plane, options: options)
    }

    var prompt: String {
        if let freestylePoints {
            return "Mirror freestyle: click the \(freestylePoints.isEmpty ? "start" : "end") of the mirror line. Esc cancels."
        }
        return "Mirror across \(planeName): X/Y/Z or Shift-X/Y/Z choose the plane, click a face, F freestyle, I instances, Q union, Return mirrors, Esc cancels."
    }
}

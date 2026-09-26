import AppKit
import RupaCore

/// What Copy with Placement puts on the pasteboard: the copied objects and the reference point
/// (with its surface normal, when it lay on one) they were copied at.
struct WorkspaceScenePlacementPayload: Codable, Equatable, Sendable {
    var fragment: SceneFragment
    var basePoint: Point3D
    var baseNormal: Vector3D?
}

/// Moves placement payloads through a pasteboard, so a copy reaches other windows and documents.
///
/// The payload travels under Rupa's own type; ordinary text and object pasteboard contents are
/// neither read nor replaced by anything else here.
@MainActor
struct WorkspaceSceneClipboard {
    static let payloadType = NSPasteboard.PasteboardType("team.stamp.rupa.scene-placement")

    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ payload: WorkspaceScenePlacementPayload) throws {
        let data = try JSONEncoder().encode(payload)
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: Self.payloadType) else {
            throw EditorError(code: .commandFailed, message: "The copied objects could not be written to the pasteboard.")
        }
    }

    /// The payload on the pasteboard, or `nil` when it holds none.
    func read() throws -> WorkspaceScenePlacementPayload? {
        guard let data = pasteboard.data(forType: Self.payloadType) else {
            return nil
        }
        return try JSONDecoder().decode(WorkspaceScenePlacementPayload.self, from: data)
    }
}
